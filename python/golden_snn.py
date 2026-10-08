#!/usr/bin/env python3
"""
golden_snn.py - Bit-Exact LIF Neuron and Alarm FSM Integer Golden Model
FSD §4.5 and §4.6
Pure Python (standard library only).
"""

from params import PARAMS

class GoldenLIF:
    def __init__(self, weights, vth=None, leak_l=None):
        self.w = [int(x) for x in weights]
        self.vth = vth if vth is not None else PARAMS['neuron']['vth']
        self.leak_l = leak_l if leak_l is not None else PARAMS['neuron']['leak_l']
        self.v = 0  # int16

    def step(self, spikes_in):
        """
        Urutan persis sesuai FSD §4.5:
        1. v = v - (v >>> L)
        2. v = v + sum_i(w[i] * s[i])
        3. saturasi int16
        4. jika v >= VTH: spike_out = 1, v = v - VTH (soft reset)
        """
        leak = self.v >> self.leak_l
        self.v -= leak

        syn_input = sum(self.w[i] * spikes_in[i] for i in range(len(self.w)))
        self.v += syn_input

        if self.v > 32767:
            self.v = 32767
        elif self.v < -32768:
            self.v = -32768

        if self.v >= self.vth:
            spike_out = 1
            self.v -= self.vth
        else:
            spike_out = 0

        return spike_out, self.v

class GoldenAlarmFSM:
    def __init__(self):
        a_cfg = PARAMS['alarm']
        self.w = a_cfg['w_window']
        self.n_sus = a_cfg['n_sus']
        self.n_alm = a_cfg['n_alm']
        self.hyst = a_cfg['hyst']

        self.history = [0] * self.w
        self.ptr = 0
        self.count = 0
        self.state = "NORMAL"

    def step(self, spike_in, hard_backstop=False):
        old_spike = self.history[self.ptr]
        self.history[self.ptr] = spike_in
        self.count += int(spike_in) - int(old_spike)
        self.ptr = (self.ptr + 1) % self.w

        if hard_backstop or self.count >= self.n_alm:
            self.state = "ALARM"
        elif self.state != "ALARM":
            if self.state == "NORMAL" and self.count >= self.n_sus:
                self.state = "SUSPECT"
            elif self.state == "SUSPECT" and self.count < (self.n_sus - self.hyst):
                self.state = "NORMAL"

        return self.state, self.count
