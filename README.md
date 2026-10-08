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

### 2. Slide Switches (Saklar Geser - 16 Switch Fisik)

> [!TIP]
> **ATURAN SEDERHANA**: Bila **SEMUA SAKLAR KE BAWAH (`0`)**, sistem **OTOMATIS 100% NORMAL & BERSENJATA (ARMED)**! Anda tidak perlu mengatur kode biner rumit untuk menjalankan operasi normal.

Tiga saklar paling kiri (`SW[15]`, `SW[14]`, `SW[13]`) didedikasikan secara independen sebagai pemicu serangan:

| Saklar Fisik | Pin FPGA | Posisi Standar | Fungsi & Aksi Saat Dinaikkan |
| :--- | :---: | :---: | :--- |
| **`SW[15]`** *(Paling Kiri)* | `V10` | Bawah (`0`) | **Serangan Probe (Repeat-Probe)**: Menembakkan rentetan 5 glitch clock 50 MHz berturut-turut. |
| **`SW[14]`** *(Ke-2 Kiri)* | `U11` | Bawah (`0`) | **Serangan Ekstrem (Extreme Overclock)**: Menembakkan 2 glitch clock 200 MHz ekstrem. |
| **`SW[13]`** *(Ke-3 Kiri)* | `U12` | Bawah (`0`) | **Serangan Gabungan (Combined Attack)**: Menembakkan glitch clock + menyalakan pemanas RO on-chip penguras daya. |
| **`SW[12]` s.d. `SW[1]`** | Beragam | Bawah (`0`) | *Reserved / Spare*. Biarkan di bawah (`0`). |
| **`SW[0]`** *(Paling Kanan)* | `J15` | Bawah (`0`) | **Manual Disarm Switch**: `0` = Normal Bersenjata (`Ar`), `1` = Disarm/Bypass (`nr`). |

---

### 📋 Cara Pengujian Super Simpel (Tanpa Pusing Biner)

| Skenario Uji | Saklar Fisik | Tombol Eksekusi | Layar 7-Segment | Indikator LED & Efek Sistem |
| :--- | :---: | :---: | :---: | :--- |
| **1. Kondisi Awal (Normal Baseline)** | **Semua Saklar di BAWAH (`0`)** | *(Tidak ada)* | `S 0 0 0 0 0 A r` | Sistem aman bersenjata. `LED[0]` (H17) denyut 1 Hz. `LED[2]` (J13) menyala hijau. |
| **2. Tes Glitch Tunggal (WARNING)** | Semua Saklar di BAWAH (`0`) | Tekan **`N17` (`BTNC`)** 1 kali | `S 1 0 0 8 0 A L` | Terdeteksi **1 SPIKE** $\rightarrow$ Status **WARNING / ALERT (`AL`)**! `LED[15]` (**WARNING**) MENYALA! |
| **3. Spam Tombol N17 (GSR / ZEROIZE)** | Semua Saklar di BAWAH (`0`) | Tekan **`N17` (`BTNC`)** ke-2 kali / spam | `S 2 0 0 0 0 Z O` | Terdeteksi **2 SPIKE** $\rightarrow$ **GSR (Global Security Reset / ZEROIZE)!** `LED[14]` (**GSR/Bahaya**) MENYALA! Kunci kripto dimusnahkan total, data di-wipe bersih ke `0000`! |
| **4. Serangan Probe (V10)** | Naikkan **`V10` (`SW[15]`)** ke atas | Otomatis (atau tekan `P18`) | `S 2 0 0 0 0 Z O` | Rentetan 5 glitch diluncurkan. SNN meletup, memicu **GSR / Zeroize** seketika! |
| **5. Serangan Ekstrem (U11)** | Naikkan **`U11` (`SW[14]`)** ke atas | Otomatis (atau tekan `P18`) | `S 2 0 0 0 0 Z O` | Clock 200 MHz menyengat core, memicu mitigasi **GSR / Zeroize**! |
| **6. Serangan Gabungan (U12)** | Naikkan **`U12` (`SW[13]`)** ke atas | Otomatis (atau tekan `P18`) | `S 2 0 0 0 0 Z O` | Pemanas chip aktif + clock glitch memicu mitigasi **GSR / Zeroize**! |
| **7. Reset Pemulihan Sistem** | Turunkan switch serangan ke bawah | Tekan **`CPU_RESETN` (`C12`)** *(Tombol Merah)* | `S 0 0 0 0 0 A r` | Alarm dibersihkan, memori di-reload, status kembali normal bersenjata. |

---

### 3. Indikator LED (`LED[15:0]`)

| LED | Pin FPGA | Sumber Sinyal | Arti Indikasi |
| :--- | :---: | :--- | :--- |
| **LED[0]** | `H17` | `heartbeat_led` | **1 Hz Heartbeat `clk100`**: Berkedip 1 Hz menandakan FPGA & osilator hidup normal. |
| **LED[1]** | `K15` | `mmcm_locked` | **MMCM Locked**: Menyala jika clock 25 MHz valid dan terkunci. |
| **LED[2]** | `J13` | `arm_active` | **Armed Indicator**: Menyala menandakan sistem bersenjata aktif (default ON saat semua switch 0). |
| **LED[11]**| `T16` | `glitch_act` | **Glitch In-Flight**: Menyala sesaat selama MMCM sedang disuntik glitch. |
| **LED[12]**| `V15` | `seq_attacking`| **Attack Active**: Menyala selama rangkaian burst serangan sedang dieksekusi. |
| **LED[13]**| `V14` | `stress_en` | **Stressor Active**: Menyala saat pemanas on-chip penguras daya aktif. |
| **LED[14]**| `V12` | `is_zeroized` | 🔴 **GSR / ZEROIZED ACTIVE (Bahaya)**: Menyala terkunci jika terjadi $\ge 2$ spike (kunci kripto dimusnahkan total)! |
| **LED[15]**| `V11` | `is_alert` | 🟡 **WARNING ACTIVE**: Menyala khusus saat terjadi 1 spike (peringatan dini / Alert). |

---

### 📟 Tampilan 7-Segment Display (8 Digit)

Display 8 digit 7-segment pada Nexys A7 langsung mengabarkan jumlah spike dan status sistem secara real-time:

```text
 +-------+-------+   +-------+-------+-------+-------+   +-------+-------+
 |  AN7  |  AN6  |   |  AN5  |  AN4  |  AN3  |  AN2  |   |  AN1  |  AN0  |
 |  [S]  | SPIKE |   |   [ MEMBRANE POTENTIAL / WIPED ]  |   [ STATUS ]  |
 | LABEL | COUNT |   |   (HEX: 0000..0080 atau 0000 GSR) | (Ar / AL / ZO)|
 +-------+-------+   +-------+-------+-------+-------+   +-------+-------+
```

| Posisi Digit | Tampilan | Arti & Maknanya |
| :--- | :---: | :--- |
| **Digit 7** *(Paling Kiri)* | **`S`** | Indikator **Spike Detector** subsistem SNN. |
| **Digit 6** | **`0`, `1`, `2`, `3`..** | **Spike Counter**: Menunjukkan secara live **sudah berapa kali spike terjadi**! |
| **Digit 5 - 2** *(4 Digit Tengah)* | **`0000` s.d. `0080`** | **Tegangan Membran / Indikator Data Terhapus**:<br>• Kondisi Normal: Menampilkan tegangan membran live $V$ dalam format Hexadecimal.<br>• **Kondisi GSR / Zeroize**: Menampilkan **`0000`** menandakan **seluruh data rahasia & kunci kripto telah dibersihkan/dihapus total!** |
| **Digit 1 - 0** *(2 Digit Paling Kanan)* | **`Ar`, `AL`, `ZO`** | **Status Keamanan FSM**:<br>• **`Ar`** : **ARMED** (Kondisi normal bersenjata, Spike = 0)<br>• **`AL`** : **WARNING** (Peringatan anomali! Spike = 1)<br>• **`ZO`** : **GSR / ZEROIZED** (Global Security Reset! Spike $\ge$ 2, kunci kripto musnah!) |

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

### Pengujian 5: Pengujian Mandiri Hardware Tanpa PC (On-Board Live Test)

Anda dapat menguji seluruh fungsi sistem secara mandiri langsung di board Nexys A7:

1. **Inisialisasi & Kondisi Awal (Armed Baseline)**:
   - Naikkan saklar **`SW[0]` (`J15`)** dan **`SW[1]` (`L16`)** ke atas (`1 1` di paling kanan).
   - Pastikan seluruh saklar lainnya (`SW[15..2]`) dalam posisi **BAWAH** (`0`).
   - Tekan tombol merah `CPU_RESETN` (`C12`) sesaat untuk reset awal.
   - **Tampilan Board**:
     - `LED[0]` (`H17`) berkedip 1 Hz (denyut jantung clock).
     - `LED[1]` (`K15`) dan `LED[2]` (`J13`) menyala hijau (MMCM locked & Armed).
     - 7-Segment menampilkan: **`0 = 0 0 0 0 A r`** *(Class 0, V=0000, ARMED)*.

2. **Uji Serangan Glitch Tunggal (Transient Filter Imunitas SNN)**:
   - Tekan tombol tengah **`BTNC` (`N17`)** satu kali.
   - **Pengamatan**:
     - MMCM menyuntikkan 1 pulsa clock 50 MHz (50 $\mu$s).
     - Tegangan membran melonjak sesaat di digit 5..2 (misal `0021`) berkat fitur peak-hold 250 ms, kemudian bocor (*leaked*) kembali ke `0000`.
     - Status tetap **`Ar`** (tidak zeroize). Ini membuktikan SNN berhasil memfilter gangguan sesaat agar tidak memicu alarm palsu.

3. **Uji Repeat-Probe Attack $\rightarrow$ ZEROIZE (Skenario 2)**:
   - Naikkan saklar **`SW[13]` (`U12`)** ke atas. Konfigurasi 4 switch paling kiri menjadi: **`0 0 1 0`**.
   - Tekan tombol bawah **`P18` (`BTND`)**.
   - **Pengamatan Hardware**:
     - Rangkaian hardware sequencer menembakkan rentetan 5 glitch 50 MHz berturut-turut.
     - Potensial membran $N_1$ terakumulasi melampaui $\Theta \ge 128$ (`0080`).
     - SNN meletupkan sinyal pertahanan!
     - 7-Segment seketika berubah menjadi: **`2 = 0 0 8 0 Z O`** (**ZEROIZED**).
     - LED bahaya **`LED[14]` (`V12`)** dan **`LED[15]` (`V11`)** menyala! Kunci rahasia pada victim core telah dihapus (*wiped*) dan victim core dihentikan.

4. **Uji Reset / Pemulihan Sistem**:
   - Kembalikan saklar `SW[13]` ke bawah (`0`).
   - Tekan tombol merah **`CPU_RESETN` (`C12`)**.
   - Sistem akan me-reload konfigurasi awal dan kembali siap siaga di status **`0 = 0 0 0 0 A r`**.

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
