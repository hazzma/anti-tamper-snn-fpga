"""
snn_model.py - Bit-Exact Python Golden Model for SNN Layer 3 (FSD v2 §7)
4 Neurons x 12 Channels, integer arithmetic, subtractive reset, leak V>>M.
"""

from typing import List, Tuple, Optional

# Constants
N_NEUR = 4
N_CH = 12
SAT_MIN = -32768
SAT_MAX = 32767

# Definitive weights matrix (FSD v2 §7.3)
DEFAULT_WEIGHTS = [
    # N0: TRANSIENT
    [16, 16, 16, 16, 16, 16, 16, 0, 0, 0, 0, 0],
    # N1: REPEAT-PROBE
    [4, 0, 0, 0, 0, 0, 0, 0, 11, 11, 0, 0],
    # N2: COMBINED
    [2, 2, 0, 4, 2, 2, 0, 4, 12, 12, 0, 0],
    # N3: SPARE
    [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
]

DEFAULT_M_SHIFTS = [3, 4, 4, 4]
DEFAULT_THETA = [128, 128, 128, 128]


def sat16(val: int) -> int:
    """Clamp integer to signed 16-bit range."""
    if val > SAT_MAX:
        return SAT_MAX
    if val < SAT_MIN:
        return SAT_MIN
    return val


class LIFNeuronBank:
    """4-Neuron Leaky Integrate-and-Fire Bank matching VHDL implementation exactly."""

    def __init__(
        self,
        weights: Optional[List[List[int]]] = None,
        m_shifts: Optional[List[int]] = None,
        thetas: Optional[List[int]] = None,
    ):
        self.weights = weights if weights is not None else [list(row) for row in DEFAULT_WEIGHTS]
        self.m_shifts = m_shifts if m_shifts is not None else list(DEFAULT_M_SHIFTS)
        self.thetas = thetas if thetas is not None else list(DEFAULT_THETA)
        self.v = [0] * N_NEUR

    def reset(self):
        """Reset membrane potential of all neurons."""
        self.v = [0] * N_NEUR

    def deposit_spike(self, ch: int, q: int) -> List[int]:
        """
        Process an incoming spike event on channel ch with intensity q in [1..15].
        Updates membrane potentials and checks immediate threshold.
        Returns list of booleans indicating fires [fire0, fire1, fire2, fire3].
        """
        if ch < 0 or ch >= N_CH or q <= 0:
            return [0] * N_NEUR

        q_clamped = min(q, 15)
        fires = [0] * N_NEUR

        for n in range(N_NEUR):
            delta = self.weights[n][ch] * q_clamped
            self.v[n] = sat16(self.v[n] + delta)
            if self.v[n] >= self.thetas[n]:
                fires[n] = 1
                self.v[n] = sat16(self.v[n] - self.thetas[n])  # Subtractive reset

        return fires

    def leak_tick(self) -> List[int]:
        """
        Execute 1 periodic leak tick (every 1 ms):
        V[n] -= (V[n] >> M[n])
        Returns list of booleans indicating fires (if any, though leak decreases V).
        """
        fires = [0] * N_NEUR
        for n in range(N_NEUR):
            # Arithmetic shift right
            leak_amount = self.v[n] >> self.m_shifts[n]
            self.v[n] = sat16(self.v[n] - leak_amount)
            if self.v[n] >= self.thetas[n]:
                fires[n] = 1
                self.v[n] = sat16(self.v[n] - self.thetas[n])
        return fires

    def get_membrane_potentials(self) -> List[int]:
        return list(self.v)


def verify_scen2_worked_example():
    """Verify Worked Example from §7.4: N1 with C=33, 2 ms interval, fire at event 5."""
    bank = LIFNeuronBank()
    print("--- Verifying FSD v2 §7.4 Worked Example (SCEN2 on N1) ---")
    event_fires = []
    v_history = []

    for event_idx in range(1, 9):
        # Event arrival (ch=8 clk_soft, q=3 => delta = 11*3 = 33)
        v_before = bank.v[1]
        fires = bank.deposit_spike(ch=8, q=3)
        v_after_deposit = bank.v[1] + (bank.thetas[1] if fires[1] else 0)
        print(f"Event {event_idx}: V_before={v_before}, +33 -> {v_after_deposit}, Fire={fires[1]}")
        event_fires.append(fires[1])
        v_history.append(bank.v[1])

        # 2 ms gap = 2 leak ticks
        bank.leak_tick()
        bank.leak_tick()

    assert event_fires[4] == 1, f"Expected fire at event 5, got: {event_fires}"
    assert sum(event_fires[:4]) == 0, f"Expected no fires before event 5, got: {event_fires[:4]}"
    print(">>> Worked Example Passed Bit-Exact Verification! <<<\n")


if __name__ == "__main__":
    verify_scen2_worked_example()
