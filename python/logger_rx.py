#!/usr/bin/env python3
"""
logger_rx.py - Receive and parse raw 8-byte sensor frames from Nexys A7-100T via UART
Frame format (8 bytes):
  [0..1] : T_code (uint16, 12-bit XADC temp)
  [2..3] : V_code (uint16, 12-bit XADC VCCINT)
  [4..5] : F_code (uint16, 16-bit RO counter)
  [6]    : M_code (uint8, bad words count)
  [7]    : Flags (uint8, status, emulator state)
"""

import sys
import os
import time
import csv
import argparse
from datetime import datetime
try:
    import serial
except ImportError:
    serial = None

from params import PARAMS

def convert_temp(code):
    return (code * 503.975 / 4096.0) - 273.15

def convert_vccint(code):
    return (code * 3.0 / 4096.0)

def main():
    parser = argparse.ArgumentParser(description="Capture SNN Anti-Tamper sensor logs from FPGA")
    parser.add_argument("--port", type=str, default="COM3", help="Serial port (e.g. COM3 or /dev/ttyUSB1)")
    parser.add_argument("--baud", type=int, default=PARAMS['system']['baud_rate_logger'], help="Baud rate")
    parser.add_argument("--duration", type=float, default=60.0, help="Capture duration in seconds")
    parser.add_argument("--out", type=str, default=None, help="Output CSV file path")
    args = parser.parse_args()

    if serial is None:
        print("Error: pyserial is not installed. Run 'pip install pyserial'.")
        sys.exit(1)

    if args.out is None:
        now_str = datetime.now().strftime("%Y%m%d_%H%M%S")
        args.out = os.path.join("data", "raw", f"session_{now_str}.csv")

    os.makedirs(os.path.dirname(args.out), exist_ok=True)

    print(f"Opening {args.port} at {args.baud} baud...")
    try:
        ser = serial.Serial(args.port, args.baud, timeout=1.0)
    except Exception as e:
        print(f"Failed to open serial port: {e}")
        sys.exit(1)

    header = ["timestamp", "tick", "T_code", "T_celsius", "V_code", "V_volt", "F_code", "M_code", "flags"]
    frame_count = 0
    t_start = time.time()

    with open(args.out, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(header)
        print(f"Logging to {args.out} for {args.duration} seconds...")

        while (time.time() - t_start) < args.duration:
            raw = ser.read(8)
            if len(raw) == 8:
                t_code = (raw[0] << 8) | raw[1]
                v_code = (raw[2] << 8) | raw[3]
                f_code = (raw[4] << 8) | raw[5]
                m_code = raw[6]
                flags = raw[7]

                t_c = convert_temp(t_code)
                v_v = convert_vccint(v_code)

                now_t = time.time() - t_start
                writer.writerow([f"{now_t:.4f}", frame_count, t_code, f"{t_c:.2f}", v_code, f"{v_v:.4f}", f_code, m_code, hex(flags)])
                frame_count += 1

                if frame_count % 1000 == 0:
                    print(f"[{now_t:.1f}s] Frames: {frame_count} | T: {t_c:.1f}C | VCCINT: {v_v:.3f}V | RO: {f_code} | M: {m_code}")

    ser.close()
    print(f"Capture finished. Total frames: {frame_count}. Saved to {args.out}")

if __name__ == "__main__":
    main()
