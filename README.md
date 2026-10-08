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

## 🎛️ Pemetaan Tombol, Saklar, & LED (Pinout Hardware)

Seluruh pemetaan pin disesuaikan dengan file master XDC resmi Digilent Nexys A7-100T ([`constr/nexys_a7_100t.xdc`](constr/nexys_a7_100t.xdc)).

### 1. Push Buttons (Tombol Tekan)

| Tombol | Pin FPGA | Nama Sinyal | Fungsi Utama |
| :--- | :--- | :--- | :--- |
| **CPU_RESETN** (Tombol Merah) | `C12` | `CPU_RESETN` | **Master Hardware Reset** (Active-Low). Mereset seluruh domain FPGA, MMCM, dan FSM ke kondisi awal. |
| **BTNC** (Center / Tengah) | `N17` | `btnc_i` | **Manual Glitch Injection**: Memicu 1 event clock glitch instan (durasi 5 siklus) ke domain victim core. |
| **BTNU** (Up / Atas) | `M18` | `btnu_i` | **Frequency Sweep Trigger**: Memicu sapuan frekuensi bertahap melalui MMCM DRP (overclocking/underclocking test). |
| **BTND** (Down / Bawah) | `P18` | `btnd_i` | **Execute Scenario Preset**: Menjalankan skenario serangan otomatis yang dipilih melalui `SW[15:12]`. |
| **BTNL** (Left / Kiri) | `P17` | `btnl_i` | **Display Page Toggle**: Mengganti mode tampilan 7-segment (Neuron Membrane Potential vs Error Counter). |
| **BTNR** (Right / Kanan) | `M17` | `btnr_i` | **Manual Zeroize Acknowledge / Clear Alert**: Mereset status alarm kembali ke kondisi normal jika diizinkan. |

---

### 2. Slide Switches (Saklar Geser)

| Saklar | Pin FPGA | Nilai | Deskripsi & Operasi |
| :--- | :--- | :--- | :--- |
| **SW[0]** | `J15` | `0` = Bypass<br>`1` = Enable | **Monitor Subsystem Enable**: Mengaktifkan seluruh sensor hardware (Clock RO & Voltage RO). |
| **SW[1]** | `L16` | `0` = Pass-through<br>`1` = SNN Active | **SNN Layer 3 Guard Enable**: Menghubungkan output SNN ke unit respons. Jika `0`, output bypass tanpa analisis SNN. |
| **SW[2]** | `M13` | `0` / `1` | **Stressor RO Enable**: Mengaktifkan bank ring oscillator pemanas on-chip untuk uji drop tegangan. |
| **SW[3]** | `R15` | `0` / `1` | **Telemetry Verbose Mode**: Mengaktifkan pengiriman streaming paket event melalui UART secara real-time. |
| **SW[11:4]** | - | - | *Reserved untuk konfigurasi ambang batas dinamis.* |
| **SW[15:12]** | `V10`, `U11`, `U12`, `H6` | *Preset ID* | **Attack Scenario Selector** (Digunakan saat menekan tombol `BTND`): |
| | | `0000` (0x0) | **SCEN0**: Normal Execution (Bypass / Kontrol Tanpa Serangan) |
| | | `0001` (0x1) | **SCEN1**: Single Isolated Glitch (Transient test) |
| | | `0010` (0x2) | **SCEN2**: Repeat-Probe Attack (5 glitch berturut-turut untuk membuktikan leaky integration SNN) |
| | | `0011` (0x3) | **SCEN3**: Combined Glitch + Voltage Drop Anomaly |
| | | `0100` (0x4) | **SCEN4**: Dynamic Frequency Drift / Sweep Overclocking |

---

### 3. Indikator LED & RGB LED

#### Status LEDs (16 LED Hijau: `LED[15:0]`)
- **`LED[0]`** (`H17`): Heartbeat `clk100` (Berkedip 1 Hz menandakan osilator 100 MHz aktif).
- **`LED[1]`** (`K15`): Heartbeat `clk_core` (Berkedip menandakan domain MMCM 25 MHz aktif).
- **`LED[2]`** (`J13`): MMCM Locked Status (`1` = MMCM terkunci stabil).
- **`LED[3]`** (`N14`): Monitor Activity Flag (Menyala saat mendeteksi clock ratio anomaly).
- **`LED[4]`** (`R18`): Voltage Drop Flag (Menyala saat RO delay line mendeteksi drop tegangan internal).
- **`LED[7:5]`** (`V17`, `U17`, `U16`): Indikator Spike Output Neuron SNN ($N_0, N_1, N_2$).
- **`LED[14:8]`**: Event Counter / Activity Bar.
- **`LED[15]`** (`L1`): **ZEROIZE ACTIVE INDICATION** (Menyala terang saat sistem ter-zeroize).

#### Multi-Color RGB LEDs
- **RGB 1 (`LED16`: `R12`=Red, `M16`=Green, `N15`=Blue)**: Status Keamanan Sistem (Security State FSM)
  - 🟢 **HIJAU**: Status **NORMAL** (Aman, tidak ada anomali).
  - 🟡 **KUNING**: Status **ARMED / ALERT** (Anomali terdeteksi, membran neuron sedang terintegrasi).
  - 🔴 **MERAH**: Status **ZEROIZED** (Tamper terkonfirmasi! Kunci kripto telah dimusnahkan).
- **RGB 2 (`LED17`: `G14`=Red, `R11`=Green, `N16`=Blue)**: Status Core Integrity & CDC Health.

---

## 📟 Tampilan 7-Segment Display (Decoding 8 Digit)

Display 8 digit 7-segment pada Nexys A7 dikontrol melalui multiplexing 1 kHz aktif-rendah (`AN[7:0]` dan katoda `SEG[6:0]`, `DP`).

```
 +-------+-------+   +-------+-------+-------+-------+   +-------+-------+
 |  AN7  |  AN6  |   |  AN5  |  AN4  |  AN3  |  AN2  |   |  AN1  |  AN0  |
 |  [ ATTACK ]   |   |   [ MEMBRANE POTENTIAL ]      |   |   [ STATE ]   |
 |  [ CLASS  ]   |   |        (HEX: 0000..0080)      |   |               |
 +-------+-------+   +-------+-------+-------+-------+   +-------+-------+
```

### Rincian Pembagian Digit:

| Posisi Digit | Nama Digit | Makna Tampilan | Contoh Nilai & Interpretasi |
| :--- | :--- | :--- | :--- |
| **Digit 7 - 6** *(Paling Kiri)* | `AN7`, `AN6` | **Attack Class ID**<br>Kategori serangan yang diklasifikasikan oleh neuron SNN. | • `00` : **Class 0** ($N_0$ - Transient Glitch sesaat)<br>• `01` : **Class 1** ($N_1$ - Repeat-Probe Attack berulang)<br>• `02` : **Class 2** ($N_2$ - Serangan gabungan Glitch + Voltage Drop)<br>• `03` : **Class 3** ($N_3$ - Voltage anomaly/Undervoltage)<br>• `--` : Tidak ada serangan aktif (Idle) |
| **Digit 5 - 2** *(4 Digit Tengah)* | `AN5`, `AN4`,<br>`AN3`, `AN2` | **Live Neuron Potential ($V$)**<br>Nilai potensial membran neuron $N_1$ secara live (format Hexadecimal 16-bit). | • `0000` : Kondisi istirahat ($V_{rest} = 0$).<br>• `0021` : Anomali 1 terdeteksi ($V = 33$).<br>• `005A` : Serangan berlanjut berakumulasi ($V = 90$).<br>• `0080` : **Ambang Batas Pecah!** ($V_{th} = 128$). Neuron meletup (spike) dan memicu zeroize! |
| **Digit 1 - 0** *(Paling Kanan)* | `AN1`, `AN0` | **System FSM State**<br>Status mesin kondisi keamanan subsistem. | • `nr` : **NORMAL** (Sistem berjalan normal)<br>• `Ar` : **ARMED** (Sistem dalam kewaspadaan penuh)<br>• `AL` : **ALERT** (Anomali terdeteksi, counter siaga)<br>• `ZO` : **ZEROIZED** (Tamper terbukti, sistem dihentikan) |

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

### Pengujian 3: Smoke Test Hardware via Interactive CLI

Setelah memprogram bitstream ke board Nexys A7 melalui **Vivado Hardware Manager**:

1. Pastikan kabel Micro-USB terpasang ke port **PROG / UART** (J6) Nexys A7 dan port USB PC.
2. Buka Device Manager di Windows untuk melihat port COM (misal: `COM5`).
3. Buka PowerShell dan arahkan ke root repositori, jalankan:
   ```powershell
   python sw/host/attack_cli.py --port COM5 --baud 115200
   ```
4. Anda akan masuk ke prompt interaktif `SNN-GUARD>`.
5. Coba jalankan perintah berikut secara berurutan:
   ```text
   SNN-GUARD> STATUS
   SNN-GUARD> ARM
   SNN-GUARD> G 1000 5
   SNN-GUARD> STATUS
   SNN-GUARD> STRESS 1
   SNN-GUARD> ZEROIZE
   ```
   *Amati respons JSON/teks dari UART serta perubahan pada 7-segment dan LED board.*

---

### Pengujian 4: Benchmark Otomatis (Experiment Suite)

Skrip ini akan menguji seluruh skenario (SCEN0 s.d. SCEN4) secara otomatis, menghitung Time-to-Detect (TTD), False Positive Rate (FPR), dan Detection Rate (DR), serta mencatatnya ke dalam file CSV.

Jalankan perintah:
```powershell
python sw/host/run_experiments.py --port COM5 --baud 115200 --output results/
```
Hasil pengujian dapat ditemukan di folder `results/exp_*.csv`.

---

### Pengujian 5: Pengujian Manual Tanpa PC

Anda dapat menguji sistem secara mandiri hanya menggunakan tombol dan display pada board:

1. **Inisialisasi**:
   - Tekan tombol merah `CPU_RESETN`.
   - Pastikan LED RGB 1 menyala **HIJAU** dan 7-segment menampilkan `---- 0000 nr`.
2. **Uji Serangan Glitch Tunggal (Transient Filter)**:
   - Tekan tombol tengah `BTNC` **satu kali**.
   - Amati 7-segment: Potensial $V$ akan naik sesaat (misal `0021`), namun segera meluruh (leak) kembali mendekati `0000` tanpa memicu zeroize.
   - Hal ini membuktikan SNN berhasil menyaring noise tanpa false positive!
3. **Uji Serangan Berulang (Repeat-Probe Attack)**:
   - Tekan tombol tengah `BTNC` **berulang kali secara cepat** (5 kali berturut-turut).
   - Amati 7-segment: Potensial $V$ bertambah drastis: `0021` $\rightarrow$ `0042` $\rightarrow$ `0063` $\rightarrow$ `0080`.
   - Begitu mencapai `0080` ($V_{th}$), neuron meletup!
   - 7-segment berubah menjadi `01 0080 ZO`.
   - LED RGB 1 seketika menyala **MERAH**, dan `LED[15]` menyala menandakan kunci rahasia telah dimusnahkan.
4. **Uji Skenario Preset**:
   - Ubah saklar `SW[15:12]` ke `0011` (Skenario 3: Combined Attack).
   - Tekan tombol bawah `BTND`.
   - Sistem akan mengeksekusi serangan simultan, mengklasifikasikan Class 2 (`02`), dan melakukan mitigasi.

---

## 📡 Protokol Komunikasi UART & Perintah CLI

UART beroperasi pada baud rate **115200 bps, 8 Data bits, No Parity, 1 Stop bit (8-N-1)**.

| Perintah | Argumen | Contoh | Deskripsi |
| :--- | :--- | :--- | :--- |
| `STATUS` | - | `STATUS` | Membaca status lengkap register: FSM state, frekuensi core, voltage count, nilai membrane potential, dan attack flag. |
| `G` | `<period> <width>` | `G 1000 5` | Menembakkan glitch pulsa clock dengan interval `<period>` siklus dan lebar pulsa `<width>`. |
| `SWEEP` | `<start> <step> <count>` | `SWEEP 25 1 10` | Menjalankan dynamic frequency sweep dari nominal 25 MHz melalui MMCM DRP. |
| `STRESS` | `<level>` | `STRESS 3` | Menyalakan beban ring oscillator (Level 0: Off, Level 1..3: Menguras daya internal). |
| `ARM` | - | `ARM` | Mengubah state sistem menjadi ARMED (siaga tinggi). |
| `DISARM` | - | `DISARM` | Mengembalikan status ke NORMAL. |
| `ZEROIZE` | - | `ZEROIZE` | Memicu zeroization manual (emergency wipe). |

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
