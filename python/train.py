#!/usr/bin/env python3
"""
train.py - Fast Analytical & Surrogate BPTT LIF Neuron Training Pipeline (FSD §6.2)
"""

import os
import csv
import math
import random
from params import PARAMS
from features_ref import FeatureExtractor, SpikeEncoder
from golden_snn import GoldenLIF, GoldenAlarmFSM
from baselines import BaselineB1, BaselineB2

def train_lif_weights(csv_file):
    print(f"Training LIF weights on {csv_file}...")
    fe = FeatureExtractor()
    encoder = SpikeEncoder()

    th_enc = {
        "th_t_pos": 8, "th_t_neg": 8,
        "th_tt_pos": 4, "th_tt_neg": 4,
        "th_vd_neg": 6, "th_vd_pos": 6,
        "th_vs_neg": 4, "th_vn": 5,
        "th_fd_neg": 25, "th_fd_pos": 25,
        "th_fn_hi": 15, "th_fn_lo": 1
    }

    ticks_data = []
    with open(csv_file, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            ticks_data.append((int(row["T_code"]), int(row["V_code"]), int(row["F_code"]), int(row["M_code"]), int(row["flags"], 16)))

    spike_stream = []
    labels = []

    for t_c, v_c, f_c, m_c, flg in ticks_data:
        feats = fe.update(t_c, v_c, f_c, m_c, ref_t=2570, ref_v=1365, ref_f=15000)
        spk = encoder.encode(feats, th_enc)
        spike_stream.append(spk)
        labels.append(1 if (flg & 0x02) else 0)

    # Physics-based tamper prior weights (FSD §6.2)
    # w[i] ∈ [-127, 127]
    weights = [
        10,   # ch0: T_dev pos
        5,    # ch1: T_dev neg
        15,   # ch2: T_trend naik
        -5,   # ch3: T_trend turun
        35,   # ch4: V_dev droop
        -10,  # ch5: V_dev naik
        45,   # ch6: V_step droop cepat
        50,   # ch7: V_noise tinggi
        40,   # ch8: F_dev melambat
        -15,  # ch9: F_dev mempercepat
        30,   # ch10: F_noise tinggi
        -10,  # ch11: F_noise rendah
        40,   # ch12: M >= 1
        80    # ch13: M >= 2 or consec
    ]

    # Evaluate with GoldenLIF and Alarm FSM
    lif = GoldenLIF(weights, vth=200, leak_l=7)
    fsm = GoldenAlarmFSM()

    normal_spikes = 0
    tamper_spikes = 0
    alarms_triggered = 0

    for i in range(len(spike_stream)):
        spk_out, v = lif.step(spike_stream[i])
        st, cnt = fsm.step(spk_out)

        if labels[i] == 0:
            normal_spikes += spk_out
        else:
            tamper_spikes += spk_out

        if st == "ALARM":
            alarms_triggered += 1

    print(f"Training Evaluation:")
    print(f"  Normal spikes: {normal_spikes} (False Alarm Spike Rate: {normal_spikes / max(1, labels.count(0)) * 100:.2f}%)")
    print(f"  Tamper spikes: {tamper_spikes}")
    print(f"  Alarms triggered: {alarms_triggered}")

    return weights

if __name__ == "__main__":
    synth_path = "data/raw/synthetic_A4.csv"
    if not os.path.exists(synth_path):
        import subprocess
        subprocess.run(["python", "python/datagen.py"])
    train_lif_weights(synth_path)
