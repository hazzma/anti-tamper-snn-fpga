#!/usr/bin/env python3
"""
emu_ctl.py - Send tamper emulation commands to Nexys A7-100T via UART
Commands:
  0 : All emulators OFF
  1 : Waster Steady Low (duty 4)
  2 : Waster Steady Mid (duty 8)
  3 : Waster Pulsed (Scenario A1)
  4 : Clock Skew (Scenario A2)
  5 : Bit-flip single shot (Scenario A3)
"""

import sys
import argparse
try:
    import serial
except ImportError:
    serial = None

from params import PARAMS

def main():
    parser = argparse.ArgumentParser(description="Control on-chip tamper emulator")
    parser.add_argument("cmd", type=str, choices=["0", "1", "2", "3", "4", "5"], help="Command character to send")
    parser.add_argument("--port", type=str, default="COM3", help="Serial port")
    parser.add_argument("--baud", type=int, default=PARAMS['system']['baud_rate_logger'], help="Baud rate")
    args = parser.parse_args()

    if serial is None:
        print("Error: pyserial is not installed.")
        sys.exit(1)

    try:
        ser = serial.Serial(args.port, args.baud, timeout=1.0)
        ser.write(args.cmd.encode("ascii"))
        ser.close()
        print(f"Sent command '{args.cmd}' to {args.port} successfully.")
    except Exception as e:
        print(f"Failed to send command: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
