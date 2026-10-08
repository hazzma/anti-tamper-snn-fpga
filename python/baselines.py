#!/usr/bin/env python3
"""
baselines.py - Classical Threshold Baselines (FSD §7.3)
  B1: Datasheet window limits
  B2: Tuned per-sensor thresholds (matched false alarm rate)
Pure Python (standard library only).
"""

from params import PARAMS

class BaselineB1:
    """Datasheet Window Baseline"""
    def __init__(self):
        b_cfg = PARAMS['backstop']
        self.v_min = b_cfg['vccint_min_code']  # 1297 (0.95V)
        self.v_max = b_cfg['vccint_max_code']  # 1433 (1.05V)
        self.t_max = int((85.0 + 273.15) * 4096.0 / 503.975)  # 85 C
        self.m_max = 1

    def eval_tick(self, t_code, v_code, f_code, m_code, f_ref=15000):
        # Check if any sensor violates datasheet
        if v_code < self.v_min or v_code > self.v_max: return 1
        if t_code > self.t_max: return 1
        if abs(f_code - f_ref) > int(f_ref * 0.03): return 1
        if m_code >= self.m_max: return 1
        return 0

class BaselineB2:
    """Tuned Per-Sensor Thresholds (OR-fused)"""
    def __init__(self, th_dict=None):
        self.th = th_dict or {
            "v_noise": 10,
            "f_dev": 120,
            "m": 1
        }

    def eval_tick(self, features):
        if features["V_noise"] >= self.th["v_noise"]: return 1
        if abs(features["F_dev"]) >= self.th["f_dev"]: return 1
        if features["M"] >= self.th["m"]: return 1
        return 0
