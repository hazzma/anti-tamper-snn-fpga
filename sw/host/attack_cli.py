"""
attack_cli.py - Interactive Host CLI for FPGA Anti-Tamper Guard (FSD v2 §8 & §12)
Connects to Nexys A7 USB-UART bridge at 115200-8N1 for live testing and demonstration.
"""

import sys
import time

try:
    import serial
except ImportError:
    serial = None


class SNNGuardClient:
    def __init__(self, port: str = "COM3", baudrate: int = 115200, timeout: float = 1.0):
        if serial is None:
            print("[WARN] pyserial not installed. Operating in offline/mock mode.")
            self.ser = None
        else:
            try:
                self.ser = serial.Serial(port=port, baudrate=baudrate, timeout=timeout)
                print(f"[OK] Connected to SNN Guard on {port} @ {baudrate} baud.")
            except Exception as e:
                print(f"[ERR] Could not open {port}: {e}")
                self.ser = None

    def send_cmd(self, cmd: str) -> str:
        if not self.ser:
            print(f"[MOCK TX] {cmd}")
            return "OK MOCK"
        full_cmd = (cmd.strip() + "\r\n").encode("ascii")
        self.ser.write(full_cmd)
        time.sleep(0.2)
        response = self.ser.read_all().decode("ascii", errors="replace").strip()
        return response

    def ping(self):
        return self.send_cmd("PING")

    def unlock(self):
        return self.send_cmd("UNLOCK")

    def set_arm(self, enabled: bool):
        return self.send_cmd(f"ARM {'1' if enabled else '0'}")

    def set_bypass(self, bypass: bool):
        return self.send_cmd(f"BYPASS {'1' if bypass else '0'}")

    def set_mode(self, mode: str):
        return self.send_cmd(f"MODE {mode.upper()}")

    def trigger_glitch(self, dur_us: int = 2, div: int = 39):
        return self.send_cmd(f"G {dur_us} {div}")

    def trigger_scenario(self, scen_id: int):
        return self.send_cmd(f"S {scen_id}")

    def wipe_key(self):
        return self.send_cmd("K")


def interactive_shell():
    print("=================================================================")
    print(" SNN Anti-Tamper Guard - Interactive CLI Shell")
    print(" Commands: PING, S <0-4>, G <us> <div>, ARM <0/1>, BYPASS <0/1>,")
    print("           MODE <A/B/C>, UNLOCK, K, exit")
    print("=================================================================")
    import argparse
    parser = argparse.ArgumentParser(description="SNN Anti-Tamper Guard Host CLI")
    parser.add_argument("pos_port", nargs="?", default=None, help="COM port (misal COM57)")
    parser.add_argument("--port", "-p", default=None, help="COM port (misal COM57)")
    parser.add_argument("--baud", "-b", type=int, default=115200, help="Baud rate (default 115200)")
    args = parser.parse_args()

    chosen_port = args.port or args.pos_port or "COM57"
    client = SNNGuardClient(port=chosen_port, baudrate=args.baud)

    while True:
        try:
            line = input("snn-guard> ").strip()
            if not line:
                continue
            if line.lower() in ["exit", "quit"]:
                break
            resp = client.send_cmd(line)
            print(f"<- {resp}")
        except KeyboardInterrupt:
            break
        except Exception as e:
            print(f"Error: {e}")


if __name__ == "__main__":
    interactive_shell()
