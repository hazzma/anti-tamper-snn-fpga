# Daftar Testbench Scenario (FSD v2 Anti-Tamper SNN)

**Keterangan**

* `snn_spike` = jumlah spike output SNN (0, 1, 2)
* **Spike 0** → tidak ada aksi (potensial di bawah threshold $\theta=128$, key utuh)
* **Spike 1** → warning LED (LED RGB Kuning berkedip, `alert_cnt = 1`, key utuh)
* **Spike 2** → key clear / GSR Zeroize (LED Merah solid, `alert_cnt = 2`, Master Key di-wipe permanen ke `0000`)

---

## Scenario A — Conventional Threshold Detection (Layer 1 Instant)

| ID | Skenario | Expected | Status | Detail Verifikasi |
| :--- | :--- | :--- | :---: | :--- |
| **TB-01** | Normal operation | Tidak ada aksi | **PASS** | $V=0$, `snn_spike=0`, 0 alerts, Master Key `0123` utuh |
| **TB-02** | Extreme voltage | Key clear | **PASS** | Bypass SNN, Key di-wipe instan ke `0000` dalam $\le 2$ siklus |
| **TB-03** | Extreme temperature | Key clear | **PASS** | Thermal breaker trip langsung memicu zeroize, Key `0000` |
| **TB-04** | Extreme clock | Key clear | **PASS** | Glitch clock / unlock memicu zeroize instan, Key `0000` |
| **TB-05** | Extreme memory integrity | Key clear | **PASS** | Korup data register memicu alarm Layer 1, Key `0000` |

---

## Scenario B — Single Gray-Zone Parameter

| ID | Skenario | Expected | Status | Detail Verifikasi |
| :--- | :--- | :--- | :---: | :--- |
| **TB-06** | Single gray event (parameter apa pun) | `snn_spike = 0`, tidak ada aksi | **PASS** | 1x pulsa soft clock ($w=50$), $V=50 < 128$, 0 spike |
| **TB-07** | Parameter yang sama diulang | `snn_spike = 1`, warning LED | **PASS** | 2x pulsa lagi ($V=150 \ge 128$), Spike 1 fire, Warning LED ON, Key utuh |
| **TB-08** | Parameter yang sama diulang lagi | `snn_spike = 2`, key clear | **PASS** | 3x pulsa lagi ($V=172 \ge 128$), Spike 2 fire, Zeroize Key ke `0000` |

---

## Scenario C — Gray-Zone Combination

| ID | Skenario | Expected | Status | Detail Verifikasi |
| :--- | :--- | :--- | :---: | :--- |
| **TB-09** | Two gray events (2 parameter weight kecil) | `snn_spike = 0`, tidak ada aksi | **PASS** | 2x capacitance probe tick ($w=10$), $V=20 < 128$, no action |
| **TB-10** | Two gray events (2 parameter weight besar) | `snn_spike = 1`, warning LED | **PASS** | Clock ($w=50$) + Voltage ($w=100$), $V=150 \ge 128$, Spike 1 fire |
| **TB-11** | Two gray events diulang (2 parameter weight kecil) | `snn_spike = 2`, key clear | **PASS** | 14 pasang probe ticks beruntun tembus threshold $2\times$, Key clear ke `0000` |
| **TB-12** | Two gray events diulang (2 parameter weight besar) | `snn_spike = 2`, key clear | **PASS** | 2 burst kombinasi besar tembus threshold $2\times$, Key clear ke `0000` |

---

## Scenario D — Parameter Sweep & Multi-Sensor Pattern

| ID | Skenario | Expected | Status | Detail Verifikasi |
| :--- | :--- | :--- | :---: | :--- |
| **TB-13** | Combination parameter pattern (3 parameter) | `snn_spike = 2`, key clear | **PASS** | Clock + Voltage + Temperature simultan ($150 \ge 128$), 2 burst $\rightarrow$ Key clear `0000` |
| **TB-14** | Combination parameter pattern (4 parameter) | `snn_spike = 2`, key clear | **PASS** | Clock + Voltage + Temp + Probe simultan ($160 \ge 128$), 2 burst $\rightarrow$ Key clear `0000` |

---

## Scenario F — Membrane Potential Decay Behavior

Tujuan: Memverifikasi sifat leaky integrator eksponensial ($V \leftarrow V - (V \gg 2)$) untuk membedakan antara noise lingkungan dan serangan berulang terkoordinasi.

| ID | Skenario | Expected | Status | Detail Verifikasi |
| :--- | :--- | :--- | :---: | :--- |
| **TB-15** | Satu gray event, lalu didiamkan (tidak ada input) | Potensial turun bertahap hingga resting state ($V=0$), `snn_spike = 0` | **PASS** | $V$ meluruh bersih secara monoton: $50 \rightarrow 38 \rightarrow 29 \rightarrow 22 \dots \rightarrow 0$. Tidak ada false alarm! |
| **TB-16** | Gray event diulang dengan interval **< T_decay** | Potensial terakumulasi mengalahkan leak, `snn_spike = 1`, warning LED | **PASS** | Akumulasi cepat mengalahkan peluruhan ($50 \rightarrow 88 \rightarrow 116 \rightarrow 137 \ge 128$), Spike 1 fire |

---

## Cara Menjalankan Testbench

Eksekusi simulasi batch Vivado xsim:
```powershell
& "C:\AMDDesignTools\2025.2\Vivado\bin\vivado.bat" -mode batch -source scripts/sim_scenarios.tcl
```

File implementasi:
* Testbench VHDL: [`sim/tb_scenarios.vhd`](file:///c:/Users/hanse/Documents/FPGA/ANTI_TEMPER/sim/tb_scenarios.vhd)
* Runner Script: [`scripts/sim_scenarios.tcl`](file:///c:/Users/hanse/Documents/FPGA/ANTI_TEMPER/scripts/sim_scenarios.tcl)
