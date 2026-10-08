#!/usr/bin/env python3
"""
features_ref.py - Golden Feature Extraction and Spike Encoder Model in Integer Arithmetic
Identical arithmetic sequence to VHDL-2008 hardware implementation.
Pure Python (standard library only).
"""

from params import PARAMS

class FeatureExtractor:
    def __init__(self):
        f_cfg = PARAMS['features']
        self.k_t1 = f_cfg['ema_k_t1_shift']
        self.k_t2 = f_cfg['ema_k_t2_shift']
        self.k_e  = f_cfg['ema_k_e_shift']
        self.q_frac = f_cfg['q_frac_bits']

        self.reset()

    def reset(self):
        self.t_ema1 = 0
        self.t_ema2 = 0
        self.v_ema  = 0
        self.v_prev = 0
        self.v_noise = 0
        self.f_ema  = 0
        self.f_prev = 0
        self.f_noise = 0
        self.initialized = False

    def update(self, t_code, v_code, f_code, m_code, ref_t=0, ref_v=0, ref_f=0):
        t_in = int(t_code)
        v_in = int(v_code)
        f_in = int(f_code)
        m_in = int(m_code)

        if not self.initialized:
            self.t_ema1 = t_in << self.q_frac
            self.t_ema2 = t_in << self.q_frac
            self.v_ema  = v_in << self.q_frac
            self.v_prev = v_in
            self.f_ema  = f_in << self.q_frac
            self.f_prev = f_in
            self.initialized = True

        self.t_ema1 += ((t_in << self.q_frac) - self.t_ema1) >> self.k_t1
        self.t_ema2 += ((t_in << self.q_frac) - self.t_ema2) >> self.k_t2
        self.v_ema  += ((v_in << self.q_frac) - self.v_ema)  >> self.k_t1
        self.f_ema  += ((f_in << self.q_frac) - self.f_ema)  >> self.k_t1

        v_step = v_in - self.v_prev
        f_step = f_in - self.f_prev
        self.v_prev = v_in
        self.f_prev = f_in

        self.v_noise += ((abs(v_step) << self.q_frac) - self.v_noise) >> self.k_e
        self.f_noise += ((abs(f_step) << self.q_frac) - self.f_noise) >> self.k_e

        t_filt = self.t_ema1 >> self.q_frac
        t_dev  = t_filt - ref_t
        t_trend= (self.t_ema1 - self.t_ema2) >> self.q_frac

        v_filt = self.v_ema >> self.q_frac
        v_dev  = v_filt - ref_v
        v_noise= self.v_noise >> self.q_frac

        f_filt = self.f_ema >> self.q_frac
        f_dev  = f_filt - ref_f
        f_noise= self.f_noise >> self.q_frac

        return {
            "T_dev": t_dev,
            "T_trend": t_trend,
            "V_dev": v_dev,
            "V_step": v_step,
            "V_noise": v_noise,
            "F_dev": f_dev,
            "F_noise": f_noise,
            "M": m_in
        }

class SpikeEncoder:
    def __init__(self):
        self.m_bad_consec = 0

    def encode(self, features, thresholds):
        spikes = [0] * 14

        if features["T_dev"] >= thresholds["th_t_pos"]: spikes[0] = 1
        if features["T_dev"] <= -thresholds["th_t_neg"]: spikes[1] = 1

        if features["T_trend"] >= thresholds["th_tt_pos"]: spikes[2] = 1
        if features["T_trend"] <= -thresholds["th_tt_neg"]: spikes[3] = 1

        if features["V_dev"] <= -thresholds["th_vd_neg"]: spikes[4] = 1
        if features["V_dev"] >= thresholds["th_vd_pos"]: spikes[5] = 1

        if features["V_step"] <= -thresholds["th_vs_neg"]: spikes[6] = 1
        if features["V_noise"] >= thresholds["th_vn"]: spikes[7] = 1

        if features["F_dev"] <= -thresholds["th_fd_neg"]: spikes[8] = 1
        if features["F_dev"] >= thresholds["th_fd_pos"]: spikes[9] = 1

        if features["F_noise"] >= thresholds["th_fn_hi"]: spikes[10] = 1
        if features["F_noise"] <= thresholds["th_fn_lo"]: spikes[11] = 1

        if features["M"] >= 1: spikes[12] = 1

        if features["M"] >= 1:
            self.m_bad_consec += 1
        else:
            self.m_bad_consec = 0

        if features["M"] >= 2 or self.m_bad_consec >= 2:
            spikes[13] = 1

        return spikes
