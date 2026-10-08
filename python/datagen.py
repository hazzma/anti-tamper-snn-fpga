#!/usr/bin/env python3
"""
datagen.py - Pure Python Synthetic Sensor Stream Generator (FSD §7.2)
No external dependencies required (uses standard library random, csv).
"""

import os
import csv
import random
import argparse

def generate_session(ticks=10000, scenario="N1", out_path="data/raw/synthetic.csv"):
    random.seed(42)
    t_val = 2570.0  # ~43 C
    v_val = 1365.0  # ~1.00 V
    f_val = 15000.0 # RO counts

    header = ["timestamp", "tick", "T_code", "T_celsius", "V_code", "V_volt", "F_code", "M_code", "flags"]
    os.makedirs(os.path.dirname(out_path), exist_ok=True)

    with open(out_path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(header)

        for i in range(ticks):
            t_val += random.gauss(0, 0.002)
            v_val += random.gauss(0, 0.05)
            f_val += random.gauss(0, 0.2)

            m_val = 0
            flag_val = 0x01  # Logger mode

            if scenario == "A1" and i > ticks // 2:
                v_noise = 15.0 if (i % 100 < 50) else 0.0
                v_eff = v_val - v_noise
                f_eff = f_val
                flag_val |= 0x02
            elif scenario == "A2" and i > ticks // 2:
                f_eff = f_val - 150.0
                v_eff = v_val
                flag_val |= 0x02
            elif scenario == "A3" and i > ticks // 2:
                v_eff = v_val
                f_eff = f_val
                if i % 500 == 0: m_val = 2
                flag_val |= 0x02
            elif scenario == "A4" and i > ticks // 2:
                v_eff = v_val - (4.0 if (i % 80 < 40) else 0.0)
                f_eff = f_val - 30.0
                if i % 1500 == 0: m_val = 1
                flag_val |= 0x02
            else:
                v_eff = v_val
                f_eff = f_val

            t_code = max(0, min(4095, int(round(t_val))))
            v_code = max(0, min(4095, int(round(v_eff))))
            f_code = max(0, min(65535, int(round(f_eff))))

            t_c = round((t_code * 503.975 / 4096.0) - 273.15, 2)
            v_v = round(v_code * 3.0 / 4096.0, 4)
            t_sec = round(i * 0.00053, 4)

            writer.writerow([t_sec, i, t_code, t_c, v_code, v_v, f_code, m_val, hex(flag_val)])

    print(f"Generated {ticks} ticks for scenario {scenario} -> {out_path}")

def main():
    parser = argparse.ArgumentParser(description="Generate synthetic sensor data")
    parser.add_argument("--scenario", type=str, default="A4", choices=["N1", "A1", "A2", "A3", "A4"])
    parser.add_argument("--ticks", type=int, default=10000)
    parser.add_argument("--out", type=str, default="data/raw/synthetic_A4.csv")
    args = parser.parse_args()

    generate_session(ticks=args.ticks, scenario=args.scenario, out_path=args.out)

if __name__ == "__main__":
    main()
