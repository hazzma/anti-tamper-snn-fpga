# FPGA SNN Anti-Tamper & Fault Injection Guard

> **Hardware-Assisted Real-Time Anti-Tamper Security Subsystem utilizing Leaky Integrate-and-Fire (LIF) Spiking Neural Network on AMD Artix-7 (Digilent Nexys A7-100T).**

---

## 📌 Daftar Isi
1. [Ringkasan Proyek](#-ringkasan-proyek)
2. [Spesifikasi Perangkat Keras & Toolchain](#-spesifikasi-perangkat-keras--toolchain)
3. [Arsitektur Sistem (FSD v2)](#-arsitektur-sistem-fsd-v2)
4. [Pemetaan Tombol, Saklar, & LED (Pinout Hardware)](#-pemetaan-tombol-saklar--led-pinout-hardware)
   - [Push Buttons (Tombol Tekan)](#1-push-buttons-tombol-tekan)
   - [Slide Switches (Saklar Geser)](#2-slide-switches-saklar-geser)
   - [Indikator LED & RGB LED](#3-indikator-led--rgb-led)
5. [Tampilan 7-Segment Display (Decoding 8 Digit)](#-tampilan-7-segment-display-decoding-8-digit)
6. [Struktur Direktori](#-struktur-direktori)
7. [Panduan Pengujian (Testing Guide)](#-panduan-pengujian-testing-guide)
   - [Pengujian 1: Simulasi Vivado (Unit & Top-Level Testbenches)](#pengujian-1-simulasi-vivado)
   - [Pengujian 2: Sintesis, Implementasi, & Bitstream](#pengujian-2-sintesis-implementasi--bitstream)
   - [Pengujian 3: Smoke Test Hardware via Interactive CLI (UART)](#pengujian-3-smoke-test-hardware-via-interactive-cli)
   - [Pengujian 4: Benchmark Otomatis (Experiment Suite)](#pengujian-4-benchmark-otomatis-experiment-suite)
   - [Pengujian 5: Pengujian Manual Tanpa PC (On-Board Testing)](#pengujian-5-pengujian-manual-tanpa-pc)
8. [Protokol Komunikasi UART & Perintah CLI](#-protokol-komunikasi-uart--perintah-cli)
9. [Catatan Timing Closure & Desain RTL](#-catatan-timing-closure--desain-rtl)

---

## 🛡️ Ringkasan Proyek

Sistem ini adalah subsistem keamanan anti-tamper berbasis perangkat keras yang dirancang untuk melindungi sirkuit kriptografi (Victim Core) dari serangan fisik seperti **Clock Glitch Injection**, **Frequency Tampering / Overclocking**, dan **Voltage Drop Attack (Fault Injection)**.

Sistem memanfaatkan **Spiking Neural Network (SNN)** berbasis model neuron **Leaky Integrate-and-Fire (LIF)** 4-neuron integer bit-exact yang beroperasi secara langsung pada clock 100 MHz. SNN bertindak sebagai pengklasifikasi anomali multi-sensor secara real-time dengan latensi sub-mikrodetik, mampu membedakan glitch transien sesaat dari serangan berulang terencana (repeat-probe attack), dan secara otomatis memicu mitigasi **Zeroization** (penghapusan kunci rahasia dan penghentian proses victim core) jika ancaman terkonfirmasi.

---

## ⚙️ Spesifikasi Perangkat Keras & Toolchain

- **Target FPGA Board**: Digilent Nexys A7-100T
- **FPGA Part**: AMD/Xilinx Artix-7 `xc7a100tcsg324-1`
- **Toolchain**: AMD Vivado Design Suite 2025.2 (Support VHDL-2008)
- **Bahasa RTL**: VHDL-2008 (IEEE `numeric_std` murni, zero unconstrained latches)
- **Host OS**: Windows 11 / Linux (Python 3.10+ dengan `pyserial`, `numpy`, `matplotlib`)

---

## 🏗️ Arsitektur Sistem (FSD v2)

```
                 +-----------------------------------------------------------+
                 |                     NEXYS A7-100T FPGA                    |
                 |                                                           |
 [Board Osc] --->| CLK_GEN (100 MHz clk100)                                  |
   100 MHz       |    |                                                      |
                 |    +---> MMCM DRP (Dynamic Reconf) ---> clk_core (25 MHz) |
                 |             ^                                 |           |
                 |             | Glitch / Freq Ctrl              v           |
                 |    +--------------------+             +-----------------+ |
                 |    |   STRESSOR & GLITCH|             |   VICTIM CORE   | |
                 |    +--------------------+             | (Crypto Engine) | |
                 |             |                                 |           |
                 |             v (CDC Synchronizers)             v (4-Phase) |
                 |    +-----------------------------------------------+      |
                 |    |   LAYER 1 & 2: SENSOR MONITORS                |      |
                 |    |   - mon_clk (Ring Osc dual-counter ratio)     |      |
                 |    |   - mon_volt (RO delay-line voltage drop)     |      |
                 |    |   - mon_victim (Digest mismatch detector)     |      |
                 |    +-----------------------------------------------+      |
                 |                            | Event Spikes                 |
                 |                            v                              |
                 |    +-----------------------------------------------+      |
                 |    |   LAYER 3: 4-NEURON LIF SNN CLASSIFIER        |      |
                 |    |   (Parallel Adder Tree, Bit-Exact 16-bit)     |      |
                 |    |   N0: Transient | N1: Repeat-Probe            |      |
                 |    |   N2: Combined  | N3: Voltage Drop            |      |
                 |    +-----------------------------------------------+      |
                 |                            |                              |
                 |                            v                              |
                 |    +-----------------------------------------------+      |
                 |    |   RESPONSE UNIT & ZEROIZATION                 |      |
                 |    |   - State Machine: NORMAL -> ARMED -> ALERT   |      |
                 |    |   - Hard Zeroize (Clear Keys, Halt Core)      |      |
                 |    +-----------------------------------------------+      |
                 |             |                                 |           |
                 |             v                                 v           |
                 |     [7-Segment (8-digit)]               [UART 115200]     |
                 +-----------------------------------------------------------+
```

### Clock Domains & Clock Domain Crossing (CDC)
1. **Domain `clk100` (100 MHz)**:
   - Oscillator board utama. Menjalankan seluruh monitor detektor, filter SNN Layer 3, FSM Response Unit, Telemetry, UART, dan kontrol display.
2. **Domain `clk_core` (Nominal 25 MHz)**:
   - Clock rekonfigurasi dinamis MMCM DRP. Hanya menggerakkan `victim_core`.
   - Terisolasi dari domain sistem menggunakan **2-FF synchronizers** (`ASYNC_REG = TRUE`) untuk sinyal kontrol dan **4-phase handshake protocol** untuk transfer data bus 32-bit digest.

---

## 🧠 Arsitektur Komprehensif Spiking Neural Network (SNN Layer 3)

Subsistem pertahanan ini menggunakan arsitektur **Integer Bit-Exact Leaky Integrate-and-Fire (LIF)** 4-Neuron yang dirancang tanpa floating-point guna mencapai efisiensi area dan latensi deterministik 10 ns (1 siklus clock @ 100 MHz).

### 1. Formulasi Matematika Model Neuron LIF
Setiap neuron $i \in \{0, 1, 2, 3\}$ memiliki potensial membran integer 16-bit bersandi ($V_i \in [-32768, 32767]$) yang diperbarui secara siklis:

$$I_i[t] = \sum_{j=0}^{11} W_{i,j} \cdot S_j[t] \cdot q_j[t]$$

1. **Integrasi Sinaptik (Input Accumulation)**:
   $$V_i[t] \leftarrow V_i[t-1] + I_i[t]$$
2. **Pemicuan Spike & Subtraktif Reset (Threshold Check)**:
   $$\text{Jika } V_i[t] \ge \Theta_i \implies \begin{cases} \text{Spike Out}_i = 1 \\ V_i[t] \leftarrow V_i[t] - \Theta_i \quad \text{(Soft/Subtractive Reset)} \end{cases}$$
3. **Kebocoran Eksponensial (Leak Decay)**:
   Terjadi secara periodik setiap sinyal `leak_tick` aktif (berbasis waktu nyata):
   $$V_i[t] \leftarrow V_i[t] - (V_i[t] \gg M_i)$$

---

### 2. Parameter Intrinsik Keempat Neuron

| ID Neuron | Nama Kelas Deteksi | Ambang Batas ($\Theta_i$) | Pergeseran Bocor ($M_i$) | Karakteristik & Respon Ancaman |
| :---: | :--- | :---: | :---: | :--- |
| **Neuron 0** | **Transient Anomaly** | `128` | $M=3$ (Bocor cepat $\approx 12.5\%$/tick) | Mendeteksi glitch sesaat/noise acak. Muatan cepat surut agar tidak menimbulkan false alarm. |
| **Neuron 1** | **Repeat-Probe Attack** | `128` | $M=2$ (Bocor lambat $\approx 25\%$/tick) | **Mendeteksi Hacker Berulang (Uji N17 & V10)**. Menampung pulsa berulang berjarak dekat hingga meluap. |
| **Neuron 2** | **Combined Multi-Stress**| `128` | $M=4$ (Bocor sangat lambat $\approx 6.25\%$/tick) | Sensitif terhadap akumulasi gabungan (anomali clock + pemanas stres termal). |
| **Neuron 3** | **Voltage Drop Attack** | `128` | $M=4$ (Bocor lambat) | Didedikasikan untuk anomali fluktuasi drop tegangan pasokan $V_{CCINT}$. |

---

### 3. Matriks Bobot Sinapsis Resmi (Synaptic Weight Matrix $W_{i,j}$)
SNN menerima **12 Saluran Sensor (Channels)** secara simultan. Bobot bernilai integer 8-bit bersandi ($[-128, 127]$) yang disimpan pada package [`rtl/pkg_weights_gen.vhd`](rtl/pkg_weights_gen.vhd):

| No | Nama Saluran Sensor ($j$) | Deskripsi Saluran Input | Bobot N0 (Transient) | Bobot N1 (Repeat-Probe) | Bobot N2 (Combined) | Bobot N3 (Voltage) |
| :---: | :--- | :--- | :---: | :---: | :---: | :---: |
| **0** | `CH_CLK_FAST_H` | Clock Overclocking Ekstrem | **+16** | **+4** | **+2** | 0 |
| **1** | `CH_CLK_SLOW_H` | Clock Underclocking Rendah | **+16** | 0 | **+2** | 0 |
| **2** | `CH_CLK_STOP_H` | Clock Hilang / Terhenti Total | **+16** | 0 | 0 | 0 |
| **3** | `CH_MMCM_UNLOCK_H`| MMCM PLL Hilang Kunci (*Loss of Lock*) | **+16** | 0 | **+4** | 0 |
| **4** | `CH_V_UNDER_H` | Tegangan Drop di Bawah Ambang Kritis | **+16** | 0 | **+2** | 0 |
| **5** | `CH_V_OVER_H` | Tegangan Lonjakan Berlebih (*Spike*) | **+16** | 0 | **+2** | 0 |
| **6** | `CH_KEY_CORRUPT_H`| Kunci Bayangan Tidak Sinkron (*Integrity*) | **+16** | 0 | 0 | 0 |
| **7** | `CH_JTAG_H` | Aktivitas Tamper Probe JTAG Ilegal | 0 | 0 | **+4** | 0 |
| **8** | `CH_CLK_SOFT` | **Glitch Clock Halus / Pulsa N17** | 0 | **+50** | **+12** | 0 |
| **9** | `CH_V_SOFT` | **Fluktuasi Tegangan Ringan** | 0 | **+50** | **+12** | 0 |
| **10**| `CH_SPARE_10` | Saluran Cadangan 1 | 0 | 0 | 0 | 0 |
| **11**| `CH_SPARE_11` | Saluran Cadangan 2 | 0 | 0 | 0 | 0 |

> [!NOTE]
> - Saluran Hard (0–6) berbobot $+16$ berfungsi memberikan sinyal kontribusi langsung pada Neuron 0 saat terjadi anomali drastis.
> - Saluran Soft (8–9) berbobot **$+50$** secara khusus diarahkan ke **Neuron 1**. Karena ambang batas $\Theta_1 = 128$, maka:
>   - **1x Tekan N17**: Masuk muatan $+50$ ($50 < 128$), ember tidak luber $\rightarrow$ surut kembali ke 0.
>   - **3x Tekan Cepat N17**: Masuk muatan $3 \times 50 = 150 \ge 128$ $\rightarrow$ ember luber ke-1 (Warning / Alert)!
>   - **3x Tekan Cepat Lanjutan**: Akumulasi melampaui ambang batas lagi $\rightarrow$ ember luber ke-2 $\rightarrow$ memicu **Zeroization (GSR)**.

---

## 🎛️ Pemetaan Tombol, Saklar, & LED (Pinout Hardware)

Seluruh pemetaan pin disesuaikan dengan file master XDC resmi Digilent Nexys A7-100T ([`constr/nexys_a7_100t.xdc`](constr/nexys_a7_100t.xdc)).

### 1. Push Buttons (Tombol Tekan Manual)

| Tombol | Pin FPGA | Nama Sinyal | Karakteristik & Respon Sistem |
| :--- | :---: | :--- | :--- |
| **CPU_RESETN** (Tombol Merah) | `C12` | `CPU_RESETN` | **Master Hardware Reset** (Active-Low): Me-restore kunci AES ke `0123`, mereset membran SNN ke 0, me-reset counter ke 0, status kembali ke `0123 . C0Ar`. |
| **BTNC** (Center / Tengah) | `N17` | `BTNC` | **Manual Soft Clock Glitch (+50 ke Leaky Bucket SNN)**:<br>• 1x Tekan: Menambah muatan $+50$ ke membran SNN ($\Theta=128$), ember tidak luber, surut sendiri dalam ~1.5 detik.<br>• 3x Tekan Cepat: Akumulasi $3 \times 50 = 150 \ge 128 \implies$ SNN Luber ke-1 $\rightarrow$ Status **Warning (`C1AL`)**, `LED[15]` ON!<br>• 6x Tekan Cepat: SNN Luber ke-2 $\rightarrow$ **GSR Zeroize (`0000 . C2ZO`)**, `LED[14]` ON, Kunci di-wipe ke `0000`! |
| **BTND** (Down / Bawah) | `P18` | `BTND` | **Memory Integrity / Cosmic Ray Single-Event Upset (SEU)**:<br>• 1x Tekan: Membalik 1 bit pada kunci kripto (`0123` $\rightarrow$ `0122`) dan menyuntik 1 soft spike ke SNN. Dianggap sebagai radiasi cosmic ray alami tanpa memicu alarm (`0122 . C0Ar`).<br>• Spam Beruntun: SNN mendeteksi anomali bertubi-tubi (fault attack aktif), membran meluap $\rightarrow$ memicu Warning (`C1AL`) hingga GSR Zeroize (`0000 . C2ZO`)! |
| **BTNU** (Up / Atas) | `M18` | `BTNU` | **Manual Soft Frequency Jitter**: Menyuntik pulsa jitter halus (+50 ke Leaky Bucket SNN). |

---

### 2. Slide Switches (Saklar Geser - 4 Mode Ekstrem Langsung Tembus Layer 1)

> [!TIP]
> **ATURAN SEDERHANA**: Bila **SEMUA SAKLAR KE BAWAH (`0`)**, sistem **OTOMATIS NORMAL & BERSENJATA (ARMED)** dengan kunci `0123` dan status `C0Ar`!

Empat switch paling kiri (`SW[15:12]`) adalah **Mode Serangan Ekstrem** yang langsung menembus Layer 1 Hard Trip (Bypass SNN):

| Saklar Fisik | Pin FPGA | Posisi Standar | Fungsi & Aksi Saat Dinaikkan (Mode Ekstrem) |
| :--- | :---: | :---: | :--- |
| **`SW[15]`** *(Paling Kiri)* | `V10` | Bawah (`0`) | **Extreme Clock Glitch Trip**: Menembus Layer 1 langsung $\rightarrow$ Seketika mengunci ke `0000 . C2ZO`, `LED[14]` ON, Kunci dihapus total (<40 ns)! |
| **`SW[14]`** *(Ke-2 Kiri)* | `U11` | Bawah (`0`) | **Extreme Voltage Drop Trip**: Menembus Layer 1 langsung $\rightarrow$ Seketika mengunci ke `0000 . C2ZO`, `LED[14]` ON! |
| **`SW[13]`** *(Ke-3 Kiri)* | `U12` | Bawah (`0`) | **Extreme Thermal / Multi-Stress Trip**: Menyalakan stressor on-chip & menembus Layer 1 langsung $\rightarrow$ Instant Lock `0000 . C2ZO`, `LED[13]` & `LED[14]` ON! |
| **`SW[12]`** *(Ke-4 Kiri)* | `H6` | Bawah (`0`) | **Extreme Memory Tamper Trip**: Merusak memori kunci secara paksa & menembus Layer 1 langsung $\rightarrow$ Instant Lock `0000 . C2ZO`, `LED[12]` & `LED[14]` ON! |
| **`SW[11]` s.d. `SW[1]`** | Beragam | Bawah (`0`) | *Reserved*. Biarkan di bawah (`0`). |
| **`SW[0]`** *(Paling Kanan)* | `J15` | Bawah (`0`) | **Monitor Disarm Switch**: `0` = Armed (Bersenjata, default), `1` = Bypass/Disarm. |

---

### 📋 Skenario Pengujian Hardware (Board Nexys A7 Live Test)

| Skenario Uji | Saklar Fisik | Tombol Eksekusi | Layar 7-Segment | Indikator LED & Efek Sistem |
| :--- | :---: | :---: | :---: | :--- |
| **1. Normal Armed (Boot Awal)** | Semua Saklar di BAWAH (`0`) | *(Tidak ada)* | `0123 . C0Ar` | Normal Armed. Prefix kunci `0123`, counter 0, status Armed (`Ar`). `LED[0]` denyut 1 Hz, `LED[1]` & `LED[2]` ON. |
| **2. Cosmic Ray Test (1x BTND)** | Semua Saklar di BAWAH (`0`) | Tekan **`BTND` (`P18`)** 1 kali | `0122 . C0Ar` | Bit kunci terbalik (`0123` $\rightarrow$ `0122`). SNN menganggap anomali kecil alami (surut sendiri). **Tidak ada alarm.** |
| **3. Soft Glitch 1x (BTNC)** | Semua Saklar di BAWAH (`0`) | Tekan **`BTNC` (`N17`)** 1 kali | `0123 . C0Ar` | Membran SNN naik $+50$, tidak luber ($\Theta=128$), surut perlahan ke 0 dalam ~1.5 detik. **Aman.** |
| **4. Spam 3x BTNC/BTND (WARNING)** | Semua Saklar di BAWAH (`0`) | Spam **`BTNC` / `BTND`** 3 kali cepat | `0123 . C1AL` | Membran meluap ($150 \ge 128$) $\rightarrow$ Counter naik ke 1! Status **WARNING (`AL`)**! `LED[15]` MENYALA! |
| **5. Spam Lanjutan (GSR ZEROIZE)** | Semua Saklar di BAWAH (`0`) | Spam 3 kali lagi | `0000 . C2ZO` | Counter naik ke 2 ($\ge$ Ambang Eskalasi) $\rightarrow$ **GSR ZEROIZE!** Kunci dihapus total menjadi `0000`. `LED[14]` (Bahaya) MENYALA! |
| **6. Extreme Clock Trip (V10)** | Naikkan **`V10` (`SW[15]`)** | *(Instan)* | `0000 . C2ZO` | Bypass SNN $\rightarrow$ Layer 1 Hard Trip instan! Kunci seketika lenyap menjadi `0000`, terkunci di status `C2ZO`. |
| **7. Extreme Voltage Trip (U11)** | Naikkan **`U11` (`SW[14]`)** | *(Instan)* | `0000 . C2ZO` | Layer 1 Hard Trip instan! Terkunci di status `0000 . C2ZO`. |
| **8. Extreme Thermal Trip (U12)** | Naikkan **`U12` (`SW[13]`)** | *(Instan)* | `0000 . C2ZO` | Layer 1 Hard Trip instan! Pemanas aktif, kunci lenyap, terkunci di status `0000 . C2ZO`. |
| **9. Extreme Memory Tamper (H6)** | Naikkan **`H6` (`SW[12]`)** | *(Instan)* | `0000 . C2ZO` | Memori kunci dirusak & Layer 1 Hard Trip instan $\rightarrow$ Kunci musnah total, terkunci di status `0000 . C2ZO`. |
| **10. Master Reset** | Turunkan switch ekstrem ke bawah | Tekan **`CPU_RESETN` (`C12`)** | `0123 . C0Ar` | Kunci dipulihkan kembali ke `0123`, counter di-reset ke 0, status kembali normal bersenjata (`C0Ar`). |

---

### 3. Indikator LED (`LED[15:0]`)

| LED | Pin FPGA | Sumber Sinyal | Arti Indikasi |
| :--- | :---: | :--- | :--- |
| **LED[0]** | `H17` | `heartbeat_led` | **1 Hz Heartbeat `clk100`**: Berkedip 1 Hz menandakan FPGA & osilator hidup normal. |
| **LED[1]** | `K15` | `mmcm_locked` | **MMCM Locked**: Menyala jika clock 25 MHz valid dan terkunci. |
| **LED[2]** | `J13` | `arm_active` | **Armed Indicator**: Menyala menandakan sistem bersenjata aktif (default ON saat semua switch 0). |
| **LED[12]**| `V15` | `SW[12]` | **Extreme Memory Tamper Switch (H6)**: Menyala saat switch H6 aktif. |
| **LED[13]**| `V14` | `SW[13]` | **Extreme Thermal Switch (U12)**: Menyala saat switch U12 aktif (stressor on-chip menyala). |
| **LED[14]**| `V12` | `is_zeroized` | 🔴 **GSR / ZEROIZED ACTIVE (Bahaya)**: Menyala terkunci jika terjadi mitigasi darurat / switch ekstrem (Kunci dimusnahkan total)! |
| **LED[15]**| `V11` | `is_alert` | 🟡 **WARNING ACTIVE**: Menyala khusus saat terjadi 1 spike (peringatan dini / Alert sebelum eskalasi zeroize). |

---

### 📟 Tampilan 7-Segment Display (Split 8 Digit)

Display 8 digit 7-segment pada Nexys A7 dibagi menjadi 2 zona yang dipisahkan oleh Decimal Point (`DP`):

```text
 +-------+-------+-------+-------+       +-------+-------+-------+-------+
 |  AN7  |  AN6  |  AN5  |  AN4  |   .   |  AN3  |  AN2  |  AN1  |  AN0  |
 |        KEY DISPLAY (4 DIGIT)   |   DP  |      COUNTER & STATUS (4 DIGIT)|
 |  [0123] Normal / [0000] Wiped | [ON]  |  [C]  | COUNT | [Ar / AL / ZO] |
 +-------+-------+-------+-------+       +-------+-------+-------+-------+
```

| Zona Display | Digit | Tampilan | Arti & Maknanya |
| :--- | :---: | :---: | :--- |
| **Zona Kiri (Kunci AES)** | **`AN[7:4]`** | **`0123`** atau **`0000`** | **Prefix Kunci Kriptografi AES**:<br>• Normal: Menampilkan hex **`0123`**.<br>• Cosmic Ray (1x BTND): Menampilkan **`0122`** (1 bit terbalik).<br>• **GSR / Zeroize**: Menampilkan **`0000`** (kunci terhapus bersih dari hardware)! |
| **Pemisah Desimal** | **`DP` (Digit 4)** | **`.` (Menyala)** | **Decimal Point** aktif di digit 4 sebagai pemisah visual antara Kunci dan Counter. |
| **Zona Kanan (Counter & Status)** | **`AN[3:0]`** | **`C 0 Ar`** / **`C 1 AL`** / **`C 2 ZO`** | **Format: `C <count> <Status>`**:<br>• **`C0Ar`**: Count 0, Status **Armed** (Normal)<br>• **`C1AL`**: Count 1, Status **Alert / Warning** (SNN Mendeteksi Anomali)<br>• **`C2ZO`**: Count 2, Status **GSR Zeroize** (Kunci Musnah & Sistem Terkunci)! |

---

## 📁 Struktur Direktori

```
ANTI_TEMPER/
├── constr/
│   └── nexys_a7_100t.xdc         # File constraint resmi Nexys A7-100T (Clocks, Pins, I/O)
├── rtl/
│   ├── pkg_fsd.vhd               # Package parameter arsitektur FSD v2
│   ├── pkg_weights_gen.vhd       # Bobot sinaptik dan ambang batas SNN
│   ├── clk_gen.vhd               # Clock buffer dan generator domain
│   ├── mmcm_drp.vhd              # Dynamic Reconfiguration Port MMCM
│   ├── stressor.vhd              # Ring-oscillator array penguras beban daya
│   ├── mon_clk.vhd               # Clock monitor dual-counter ratio
│   ├── mon_volt.vhd              # Voltage monitor delay-chain
│   ├── victim_core.vhd           # Core kripto simulasi (AES/Digest)
│   ├── mon_victim.vhd            # Monitor integritas digest core
│   ├── sensor_mux.vhd            # Multiplexer dan filter glitch sensor
│   ├── snn_lif.vhd               # 4-Neuron LIF SNN dengan Parallel Adder Tree
│   ├── response.vhd              # Zeroization controller & alarm FSM
│   ├── uart_host.vhd             # UART 115200 controller (TX/RX)
│   ├── cmd_parser.vhd            # Text protocol parser
│   ├── telemetry.vhd             # 7-Segment multiplexer & LED driver
│   └── top.vhd                   # Top-level entity integrasi FSD v2
├── sim/
│   ├── tb_top.vhd                # Scenario testbench integrasi penuh (SCEN0..SCEN4)
│   └── tb_snn_lif.vhd            # Unit testbench SNN Layer 3
├── scripts/
│   ├── create_project.tcl        # Script otomatis pembuatan project Vivado
│   ├── synth.tcl                 # Script batch non-GUI sintesis
│   ├── sim.tcl                   # Script batch non-GUI simulasi
│   └── run_vivado.bat            # Helper shortcut menjalankan Vivado
├── sw/
│   ├── golden/
│   │   ├── snn_model.py          # Model matematis Python bit-exact tolok ukur SNN
│   │   └── tune.py               # Generator bobot hex dan verifikasi margin
│   └── host/
│       ├── attack_cli.py         # Terminal CLI interaktif smoke test hardware
│       └── run_experiments.py    # Skrip automated benchmarking & logging CSV
├── vivado_project/
│   └── anti_tamper_snn.xpr       # Project file resmi Vivado 2025.2 GUI
├── params.yaml                   # Single Source of Truth parameter sistem
└── README.md                     # Dokumentasi panduan lengkap
```

---

## 🚀 Panduan Pengujian (Testing Guide)

Pengujian mengadopsi metodologi verifikasi berlapis (**5-Layer Testing Architecture**).

---

### Pengujian 1: Simulasi Vivado

Pengujian logika RTL dan bit-exact SNN sebelum implementasi ke silicon.

#### Opsi A: Melalui GUI Vivado 2025.2
1. Jalankan Vivado dan buka project [`vivado_project/anti_tamper_snn.xpr`](vivado_project/anti_tamper_snn.xpr).
2. Di panel **Flow Navigator**, pilih **Simulation** $\rightarrow$ **Run Behavioral Simulation**.
3. Di jendela waveform yang terbuka:
   - Klik menu **Restart** (Shift+F5).
   - Jalankan simulasi penuh dengan mengetik di Tcl Console: `run all`.
4. Periksa log Tcl Console: Testbench akan mengeluarkan output self-checking:
   ```
   ==================================================
   TEST SCENARIO 0: Baseline Normal Running ... PASS
   TEST SCENARIO 1: Single Isolated Glitch ... PASS
   TEST SCENARIO 2: Repeat-Probe Attack (5 glitches) ... PASS
   TEST SCENARIO 3: Combined Glitch + Voltage Drop ... PASS
   ALL TESTCASES COMPLETED SUCCESSFULLY: PASS
   ==================================================
   ```

#### Opsi B: Melalui Terminal Batch Mode (Headless)
Jalankan perintah berikut di PowerShell atau Command Prompt:
```powershell
vivado -mode batch -source scripts/sim.tcl
```

---

### Pengujian 2: Sintesis, Implementasi, & Bitstream

1. Buka project di Vivado 2025.2.
2. Di toolbar atas atau Flow Navigator, klik **Generate Bitstream**.
3. Vivado akan menjalankan:
   - **Synthesis**: Memetakan VHDL-2008 ke Artix-7 LUT, FF, dan DSP slices.
   - **Implementation**: Melakukan place & route dengan constraint timing 100 MHz.
   - **Timing Verification**: Pastikan hasil **Worst Negative Slack (WNS) > 0.000 ns**. Desain telah divalidasi memiliki margin positif ($WNS = +2.423\text{ ns}$).
   - **Bitstream Generation**: Menghasilkan file bitstream `anti_tamper_snn.bit`.

---

### Pengujian 3: Pemrograman Bitstream ke Board Nexys A7-100T

Bitstream siap pakai berlokasi di:
- `vivado_output_snn/anti_tamper_snn.bit`
- `vivado_project/anti_tamper_snn.runs/impl_1/top.bit`

Cara memprogram melalui Vivado Hardware Manager:
1. Hubungkan kabel Micro-USB ke port **PROG / UART** (J6) Nexys A7-100T dan nyalakan saklar daya (POWER switch).
2. Di Vivado, buka **Hardware Manager** $\rightarrow$ **Open Target** $\rightarrow$ **Auto Connect**.
3. Klik kanan pada target FPGA `xc7a100t_0` $\rightarrow$ pilih **Program Device...**.
4. Pilih file bitstream: `vivado_output_snn/anti_tamper_snn.bit`.
5. Klik **Program**. LED DONE akan menyala hijau, dan display 7-segment langsung menampilkan:
   ```text
   0123 . C0Ar
   ```

---

### Pengujian 4: Pengujian Interaktif On-Board (Live Physical Test)

Sistem beroperasi secara **100% Standalone Hardware** (seluruh fungsi dijalankan langsung melalui tombol, saklar, dan indikator board):

1. **Kondisi Awal (Armed Baseline)**:
   - Pastikan seluruh saklar `SW[15:0]` berada di posisi **BAWAH (`0`)**.
   - Tekan tombol merah `CPU_RESETN` (`C12`).
   - Layar 7-Segment menampilkan: **`0123 . C0Ar`** (Kunci `0123`, Counter 0, Status Armed `Ar`).
   - `LED[0]` (H17) berkedip 1 Hz, `LED[1]` (K15) dan `LED[2]` (J13) menyala.

2. **Uji Bit-Flip Cosmic Ray SEU (1x Tekan `BTND` / `P18`)**:
   - Tekan tombol bawah **`BTND` (`P18`)** 1 kali.
   - Layar 7-Segment berubah menjadi: **`0122 . C0Ar`**.
   - Terlihat bit 112 kunci kripto terbalik (`3` -> `2`), dan muatan +50 masuk ke SNN.
   - Karena muatan +50 < Theta (128), SNN menganggapnya sebagai fluktuasi/cosmic ray alami dan muatan surut ke 0. **Tidak memicu alarm!**

3. **Uji Transient Soft Glitch (1x Tekan `BTNC` / `N17`)**:
   - Tekan tombol tengah **`BTNC` (`N17`)** 1 kali.
   - Muatan +50 masuk ke SNN. Karena tidak melampaui Theta=128, muatan surut dalam ~1.5 detik. **Sistem tetap aman.**

4. **Uji Serangan Berulang (Spam `BTNC` atau `BTND` 3x -> WARNING)**:
   - Tekan cepat **`BTNC`** atau **`BTND`** sebanyak 3 kali berturut-turut.
   - Akumulasi 3 x 50 = 150 >= 128 -> SNN ember luber ke-1!
   - Layar 7-Segment berubah menjadi: **`0123 . C1AL`** (atau `0122 . C1AL`).
   - Counter naik ke **1**, status berubah menjadi **`AL` (Alert / Warning)**, dan **`LED[15]` MENYALA**!

5. **Uji Eskalasi Pertahanan (Spam 3x Lagi -> GSR ZEROIZE)**:
   - Tekan cepat 3 kali lagi.
   - SNN luber ke-2 -> ambang eskalasi tercapai -> **GSR ZEROIZE**!
   - Layar 7-Segment seketika berubah menjadi: **`0000 . C2ZO`**!
   - Seluruh kunci rahasia dimusnahkan total (`0000`), proses dihentikan, dan LED bahaya **`LED[14]` MENYALA MERAH**!

6. **Uji 4 Saklar Mode Ekstrem (Bypass SNN -> Tembus Layer 1 Instan)**:
   - **`SW[15]` (`V10`)**: Naikkan -> Langsung loncat ke **`0000 . C2ZO`** (Extreme Clock Trip)!
   - **`SW[14]` (`U11`)**: Naikkan -> Langsung loncat ke **`0000 . C2ZO`** (Extreme Voltage Trip)!
   - **`SW[13]` (`U12`)**: Naikkan -> Langsung loncat ke **`0000 . C2ZO`** & `LED[13]` ON (Extreme Thermal Trip)!
   - **`SW[12]` (`H6`)**: Naikkan -> Kunci dirusak & langsung loncat ke **`0000 . C2ZO`** & `LED[12]` ON (Extreme Memory Integrity Trip)!

7. **Uji Pemulihan Sistem (Master Reset)**:
   - Turunkan seluruh saklar ekstrem ke bawah (`0`).
   - Tekan tombol merah **`CPU_RESETN` (`C12`)**.
   - Sistem seketika kembali ke kondisi normal bersenjata: **`0123 . C0Ar`**.

---

## ⚡ Catatan Timing Closure & Desain RTL

Desain ini telah melalui pengujian sintesis dan implementasi Vivado 2025.2:

1. **Parallel Adder Tree**:
   Pada implementasi awal, penjumlahan bobot 12 sinapsis secara serial menghasilkan 82 logic levels dan $-40.528\text{ ns}$ slack violation.
   Di [`rtl/snn_lif.vhd`](rtl/snn_lif.vhd), implementasi telah dirombak menggunakan **Parallel Balanced Adder Tree (3-stage)**.
2. **Timing Result**:
   - **Worst Negative Slack (WNS)**: $+2.423\text{ ns}$ (MET).
   - **Worst Hold Slack (WHS)**: $+2.383\text{ ns}$ (MET).
   - Zero unconstrained paths dan zero CDC hazards.
