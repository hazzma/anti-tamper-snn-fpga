#!/usr/bin/env python3
"""
plot_logs.py - Visualize temperature, voltage, RO frequency, and memory faults from CSV log.
"""

import sys
import os
import argparse
import pandas as pd
import matplotlib.pyplot as plt

def main():
    parser = argparse.ArgumentParser(description="Plot SNN Anti-Tamper sensor logs")
    parser.add_argument("file", type=str, help="Path to CSV file")
    parser.add_argument("--out", type=str, default=None, help="Path to save plot image")
    args = parser.parse_args()

    if not os.path.exists(args.file):
        print(f"Error: File not found: {args.file}")
        sys.exit(1)

    df = pd.read_csv(args.file)
    print(f"Loaded {len(df)} records from {args.file}")

    fig, axes = plt.subplots(4, 1, figsize=(12, 10), sharex=True)

    time_col = df["timestamp"]

    # 1. Temperature
    axes[0].plot(time_col, df["T_celsius"], color="tab:red", label="Die Temperature")
    axes[0].set_ylabel("Temp (°C)")
    axes[0].grid(True, alpha=0.3)
    axes[0].legend(loc="upper right")

    # 2. Voltage
    axes[1].plot(time_col, df["V_volt"], color="tab:blue", label="VCCINT")
    axes[1].axhline(0.95, color="r", linestyle="--", alpha=0.6, label="Min 0.95V")
    axes[1].axhline(1.05, color="r", linestyle="--", alpha=0.6, label="Max 1.05V")
    axes[1].set_ylabel("Voltage (V)")
    axes[1].grid(True, alpha=0.3)
    axes[1].legend(loc="upper right")

    # 3. Ring Oscillator
    axes[2].plot(time_col, df["F_code"], color="tab:green", label="RO Counts (Window 2^15)")
    axes[2].set_ylabel("RO Counts")
    axes[2].grid(True, alpha=0.3)
    axes[2].legend(loc="upper right")

    # 4. BRAM Faults
    axes[3].step(time_col, df["M_code"], color="tab:purple", label="Bad Words (Bit Flips)")
    axes[3].set_ylabel("Faults")
    axes[3].set_xlabel("Time (seconds)")
    axes[3].grid(True, alpha=0.3)
    axes[3].legend(loc="upper right")

    plt.suptitle(f"SNN Anti-Tamper Sensor Telemetry - {os.path.basename(args.file)}")
    plt.tight_layout()

    if args.out:
        plt.savefig(args.out, dpi=150)
        print(f"Plot saved to {args.out}")
    else:
        plt.show()

if __name__ == "__main__":
    main()
