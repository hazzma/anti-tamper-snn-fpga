# FSD — FPGA Anti-Tamper Guard with SNN (Nexys A7-100T)

**Project**: Anti-Tampering IC dengan SNN (Hackathon IC Design)
**Platform**: Digilent Nexys A7-100T (AMD Artix-7 `xc7a100tcsg324-1`)
**Toolchain**: Vivado **2025.2** (pinned, batch/Tcl only), xsim, Python ≥3.10 (host + golden model)
**AI Agent**: Google Antigravity (implementer), manusia (reviewer/decision maker)
**Reuse source**: https://github.com/Marco-Winzker/Spiking_NN_RGB_FPGA (MIT — catat commit hash saat clone)
**Tim**: Hansel Kay, Michel, Benjamin, Hiroshi (pembagian: §1.4)

| Versi | Tanggal | Status | Catatan |
|---|---|---|---|
| 0.1 | — | DRAFT | struktur awal |
| 0.2 | — | CONFIRMED | keputusan A1–A12 dikunci (§0) |
| 0.3 | — | CONFIRMED | +§12 Testing Architecture 5 lapis |
| 0.4 | — | CONFIRMED | +§7.6 tuning procedure; N1 recalibrated |
| 0.5 | — | CONFIRMED | weight definitif §7.3; leak-quantization rule; q-mapping contract |
| **1.0-RC** | — | **REVIEW TIM** | konsolidasi penuh; emission cadence + class rule + latency scoping + secure defaults; pending C1–C5 & PIC Michel |

**Dokumen referensi** (sumber kebenaran — JANGAN dari ingatan):
- UG472 (7-Series Clocking), UG480 (7-Series XADC), DS181 (Artix-7)
- XAPP888 (MMCM/PLL Dynamic Reconfiguration), XAPP1084 (Tamper-Resistant Designs)
- Digilent *Nexys A7 Reference Manual* + `Nexys-A7-100T-Master.xdc` (SATU-SATUNYA sumber pin)

---

## 0. Decision Record — Keputusan Terkunci (A1–A12)

| # | Topik | Keputusan | Nilai konkret |
|---|---|---|---|
| A1 | Mode sensor default | **C dulu → upgrade B kalau GATE 4 lolos**; runtime-switchable via UART | default `MODE C`; B/B didukung penuh |
| A2 | Target metrik | standar | FN-reduction ≥90% (20 run SCEN2); FP=0 (10 run SCEN0); latency jalur L1 <1 ms |
| A3 | Policy response | **escalation** | `alert_count` global; ≥ `ESC_TH` (CFG 0x0D, default 2) → zeroize; ESC=1 = instan |
| A4 | Stretch goal B9 | jtag + GSR | `BSCANE2` monitor + `STARTUPE2` GSR trigger |
| A5 | Parameter skenario | preset draft + semua via CFG | SCEN2: +2.6% (div 39), 2 µs, tiap 2 ms, ×8 |
| A6 | Jumlah neuron | 4 | N0 transient, N1 repeat-probe, N2 combined, N3 spare |
| A7 | Key store | 128-bit + victim berat | key 128b dual-copy + checksum 32b; datapath heavy Fmax ~110–130 MHz |
| A8 | Command set | draft + shortcut 1-huruf + W LOAD | `G`, `S`, `K`, `W LOAD…W END` |
| A9 | Tim/PIC | lihat §1.4 | Michel = Layer 1 + integrasi [KONFIRMASI] |
| A10 | Vivado | 2025.2 | fallback sim-only ke 2023.2 bila quirk |
| A11 | Live demo | kombinasi | tombol = quick demo; UART = detail & Q&A |
| A12 | Post-zeroize | latch + UNLOCK | `UNLOCK` clear latch+count; key tetap wipe sampai `KEY SET` |

---

## 1. Tujuan & Ruang Lingkup

### 1.1 Yang dibangun
"Secure element model" di FPGA: aset (key register), lapisan deteksi cepat
threshold-based (Layer 1), lapisan scoring SNN Leaky Integrate-and-Fire (Layer 3)
yang menangkap **pola serangan** yang lolos Layer 1, dan response layer (zeroize).
Skenario serangan disimulasikan terkontrol (UART/tombol/DRP clock manipulation) —
**bukan** fault injection fisik.

### 1.2 Non-goals
- Tidak ada fault injection fisik nyata (laser/EMFI/probing).
- Tidak ada training SNN berskala besar — weight hand-crafted via prosedur tuning
  analytik (§7.6); snnTorch = stretch.
- Tidak ada target produksi/sertifikasi. Proof-of-concept.
- Porting DE10-Nano TIDAK di-desain sekarang (§15).

### 1.3 Hipotesis yang dibuktikan
> Serangan berulang/kombinasi yang masing-masing event di bawah threshold Layer 1
> lolos dari baseline (threshold-only), tapi terdeteksi oleh Layer 1+3.
> Bukti = perbandingan baseline vs eksperimen pada skenario identik (§13).

### 1.4 Tim & PIC [KONFIRMASI untuk Michel]
| Area | PIC |
|---|---|
| Layer 3 (SNN: RTL, tuning, golden model) | Hansel Kay, Hiroshi |
| Attack simulation & host script | Benjamin, Hansel Kay |
| Layer 1 (monitor: clock, XADC, victim) + integrasi/sintesis | Michel [KONFIRMASI] |
| Dokumentasi & presentasi | Michel lead [KONFIRMASI] |

---

## 2. Architecture Decision Records

| # | Keputusan | Rationale |
|---|---|---|
| D1 | VHDL-2008 semua (RTL+TB) | konsisten repo reuse; xsim support |
| D2 | **Dua domain clock**: `clk100` (stabil) & `clk_core` (output MMCM, glitchable via DRP). Semua yang MENILAI (monitor/SNN/response/UART) di `clk100`; hanya victim di `clk_core` | detektor tidak boleh ikut terganggu serangan yang ia deteksi |
| D3 | CDC `clk_core`→`clk100`: 2FF sync `ASYNC_REG`; bus via handshake 4-phase; XDC async | freq clk_core berubah runtime → timing antar domain tak terjamin |
| D4 | XADC via primitive + DRP FSM (tanpa IP wizard) | minim dependensi; agent-friendly |
| D5 | **Sensor source mux mode A/B/C** (A1:4) | Opsi A/B/C proposal tanpa ubah arsitektur; fallback built-in |
| D6 | SNN: weight 8b signed, membrane 16b signed, q 4b (0–15), leak multiplicative shift `V -= V>>M`, tick per-neuron | tanpa divider; gaya repo Winzker |
| D7 | UART ASCII line-based 115200-8N1 | manusia & agent bisa ketik; gampang di-parse |
| D8 | Fault model clock: overclock excursion (≥~160 MHz) → timing violation riil → korupsi digest; deviasi kecil hanya terlihat monitor | pisah bersih: korupsi = mon_victim; anomali freq = mon_clk |
| D9 | Build 100% Tcl batch + Makefile | prasyarat agent loop mandiri |
| D10 | Baseline comparison = flag runtime `BYPASS` | proposal §9: kondisi baseline tanpa ubah skenario |
| D11 | **Escalation**: `alert_count` global; setiap alert (flag hard ATAU fire SNN) menaikkan count; count ≥ `ESC_TH` (CFG 0x0D, default 2) → zeroize + latch. ESC=1 = instant mode | A3:4; 1 false positive tidak langsung bunuh key; demo-configurable |
| D12 | Demo: tombol = quick trigger, UART = detail + shortcut 1-huruf | A11:3, A8:4 |
| D13 | Toolchain pinned Vivado 2025.2, batch-only | A10 |
| D14 | Key 128-bit + victim datapath heavy (target Fmax ~110–130 MHz) | A7:3; menjamin overclock menghasilkan korupsi riil |
| D15 | **Secure defaults post-GSR**: semua register CFG inisialisasi ke nilai aman (ARM=1, BYPASS=0, MODE=C, ESC_TH=2) | GSR me-reset CFG (FF-based); sistem bangun dalam keadaan armed |
| D16 | **Class attribution**: neuron pertama yang capai θ menentukan class; tie → index terkecil | determinisme log ALERT |

---

## 3. Platform: Nexys A7-100T

> **Aturan keras**: pin assignment HANYA dari `Nexys-A7-100T-Master.xdc` Digilent
> (di-fetch `make setup`). FSD menetapkan resource LOGIS, bukan pin.

| Resource board | Dipakai untuk |
|---|---|
| 100 MHz oscillator | `clk100`, input MMCM |
| CPU_RESETN | reset global |
| USB-UART bridge | command host, log, telemetry |
| LED[15:0], SW[15:0], BTNC/U/D/L/R | status, trigger serangan, pemilih skenario (§10) |
| 7-seg 8 digit | state & class |
| XADC internal (VCCINT ch0) | voltage monitor (tanpa wiring) |
| JTAG via USB | programming; objek test mon_jtag |

Kapasitas XC7A100T (⚠ verifikasi DS181): ~63.400 LUT, ~126.800 FF, 135 BRAM36, 240 DSP, 6 CMT, 1 XADC.

---

## 4. Diagram Arsitektur

```text
                        ┌────────────────────── Nexys A7-100T ──────────────────────┐
 CLK100MHZ ──► clk100 ──┼──► [U1 clk_gen: MMCM + DRP] ──clk_core──► [U8 victim_core] │
                │       │        ▲DRP        │locked                  │ epoch_p,    │
                │       │   [U7 mmcm_drp]    │                        │ digest(32b) │
                │       │        ▲           │                        ▼ (4-phase    │
                │       │        │           │                        │ handshake)  │
                │       │  [U6 attack_seq]   │            [U9 mon_victim]──key_corrupt┐│
                │       │        ▲           │      [U3 mon_clk]──clk_{fast,slow,   ││
                │       │  [U5 stressor]─────┘            ▲      │  stop,gross}_h,  ││
                │       │        ▲           │      clk_core     │  mmcm_unlock_h,  ││
                │       │        │           │                   │  clk_soft(burst) ││
                │       │        │           │     [U4 mon_volt (XADC DRP)]         ││
                │       │        │           │       v_under_h, v_over_h, v_soft    ││
                │       │        │           │     [U10 mon_jtag (stretch)]──jtag_h ││
                │       │        │           │               │                      ││
 USB-UART ◄─────┼──►[U2 uart_host]─►[U2b cmd_parser]─►[U11 sensor_mux]──spikes──►[U12 snn_lif×4]
   ▲            │        ▲                 ▲               ▲MODE             │fire      │
   │ ASCII log  │        │                 │               │                 ▼          │
   └────────────┼──[U14 telemetry / event log]◄───────────┘        [U13 response]───►[key_store]
                │        ▲               ▲                           │  ▲      (zeroize)│
 BTNC/U/D,SW ───┼──[U6 attack_seq]───────┘                           │  └───────────────┘
                └────────────────────────────────────────────────────┴──────────────────┘
                     PC: sw/host/attack_cli.py + run_experiments.py
```

**Prinsip alur**: Layer 1 dan Layer 3 paralel di `clk100`. Response punya dua jalur
trigger: (1) instan dari flag hard Layer 1, (2) dari fire SNN (di-bypass oleh
`BYPASS=1` = kondisi baseline). Escalation D11 mengatur kapan ALERT jadi zeroize.

---

## 5. Clocking, Reset, CDC

### 5.1 Clock plan
| Clock | Sumber | Freq default | Isi domain |
|---|---|---|---|
| `clk100` | osc board → BUFG | 100 MHz | monitor, SNN, response, UART, telemetry, attack_seq, victim checker |
| `clk_core` | MMCM CLKOUT0 (DRP-reconfigurable) | 25 MHz (VCO 1000 MHz = 100×M10/D1, DIV=40) | victim_core SAJA |

Rentang via DRP (⚠ verifikasi rentang VCO UG472):
| CLKOUT0_DIVIDE | Fout | Makna |
|---|---|---|
| 80 | 12.5 MHz | slow probe |
| 39 | 25.64 MHz (+2.6%) | **sub-threshold probe (SCEN2)** |
| 40 | 25 MHz | nominal |
| 20 / 10 | 50 / 100 MHz | obvious |
| 5 | 200 MHz | **overclock → fault injection (SCEN1)** |

**Aturan DRP** (XAPP888): `PSCLK = clk100`; hanya tulis `CLKOUT0_DIVIDE` (&
`POWER_REG` untuk stop); VCO tak disentuh agar relock cepat. Sequence: LOCKED & DRDY
→ pulsa DEN → tunggu DRDY → tunggu LOCKED. Setiap operasi ke event log.

### 5.2 Reset
- Asinkron assert (CPU_RESETN), de-assert tersinkron per domain.
- `RESET` via UART = reset penuh; key harus `KEY SET` ulang.
- **Zeroize ≠ reset**: zeroize hanya wipe key_store; sistem tetap hidup.
- **GSR (B9)**: reset seluruh fabric via `STARTUPE2` → semua FF (termasuk CFG & key)
  kembali ke INIT = **secure defaults** (D15). Post-GSR: armed, protected, key kosong.

### 5.3 Aturan CDC (wajib semua modul)
1. Lintasan `clk_core`→`clk100` via 2FF sync (`ASYNC_REG=TRUE`); bus via handshake 4-phase.
2. Tanpa lintasan kombinasional antar domain; tanpa counter multi-bit lintas domain tanpa handshake.
3. Metastability saat glitch = **fitur**: transfer gagal → event `XFER_ERR` (q=8 di channel key_corrupt).
4. Margin pengukuran monitor ≥ 4 siklus `clk100` (menelan latensi sync).

---

## 6. Spesifikasi Modul (RTL)

Konvensi: 1 entity/file, nama file = nama entity, konstanta terpusat di
`rtl/pkg_fsd.vhd` + `rtl/pkg_weights_gen.vhd` (generated). Suffiks `_h` = hard flag
(Layer 1), `_soft` = soft event (burst, hanya ke SNN). Semua modul: `clk, rstn`.

### U1 `clk_gen`
MMCM (`MMCME2_ADV`) + reset FSM → `clk100, clk_core, locked`. Generics `M=10, D=1, DIV_DEFAULT=40`.

### U7 `mmcm_drp_ctrl` (clk100)
Eksekusi XAPP888 atas perintah cmd_parser/attack_seq:
- `glitch(div, dur_us)` — tulis div, tahan, tulis balik nominal. Min durasi riil ⚠ beberapa µs (diukur B4).
- `set(div)`, `stop(ms)` via POWER_REG, `sweep(lo,hi,step,dwell_us,reps)`.
- Output `busy`, `glitch_active`; log tiap langkah.

### U2 `uart_host` + U2b `cmd_parser`
115200-8N1; RX 2FF-sync; FIFO TX (log tak boleh block RX). Parser ASCII line (`\n`),
reply `OK ...` / `ERR <code>`. Command set = §8.

### U3 `mon_clk` (clk100) — Layer 1 clock detector
Input: `clk_core` (via 2FF), `mmcm_locked`. Evaluasi per window `WND_US` (default 100 µs = 2.500 cycle @25 MHz).

| Output | Mekanisme | Default |
|---|---|---|
| `clk_gross_h` | count 1 periode; flag jika > 2× nominal | instan |
| `clk_fast_h` | edge-count window; freq > nominal + `CLK_HI_PCT` | +5% |
| `clk_slow_h` | idem, < nominal − `CLK_LO_PCT` | −5% |
| `clk_stop_h` | stall watchdog: tanpa edge selama `STALL_CYC` | 2 µs |
| `mmcm_unlock_h` | `locked` falling edge | instan |
| `clk_soft` (burst) | deviasi > `CLK_SOFT_TH` (default 1% = 25 count) → **1 spike per window**, q per §7.2 | soft |

Hard flag = 1 spike per **rising edge**. Sync latency (±2 cyc) ≪ margin (≥4 cyc). ✓D3.

### U4 `mon_volt` (clk100) — XADC
- Primitive `XADC`, DCLK=clk100 (⚠ max DCLK UG480; fallback clk100/2), continuous ch0 (VCCINT), average 16, ~10 kSPS efektif.
- LSB = 732,4 µV (⚠ UG480); VCCINT 1,00 V ≈ code 1365 (plausible range 1300–1450).
- Output: `v_under_h`/`v_over_h` (default 0,93 V / 1,07 V, hysteresis 8 code);
  `v_soft` (burst): baseline IIR `base += (x-base)>>5`; |x−base| > `V_SOFT_TH`
  (default 12 code ≈ 9 mV) → **1 spike per eval tick 100 µs**, q per §7.2 (step 4 mV ≈ 5 code).
- ⚠ Magnitude dip stressor dikarakterisasi B5; fallback: turunkan `V_SOFT_TH` / besarkan stressor / `MODE A`.

### U5 `stressor` (clk100)
Shift-register masif (~2–4k LUT) switching **sinkron sempurna** tiap cycle saat
enable → di/dt tajam → IR-drop sesaat pada VCCINT → terbaca XADC (Opsi B proposal).
Enable via `VSTRESS` / SCEN3.

### U8 `victim_core` (clk_core) — aset yang dilindungi
- `key_store`: **128-bit** + checksum 32b + **salinan dobel** (mismatch = event).
  Register-based (BUKAN BRAM) — syarat agar GSR/zeroize menyentuhnya.
- Load via `KEY SET`; checksum good = `0xDEADC0DE`.
- **Datapath heavy** (D14): LFSR32 per cycle + 3-stage 64-bit multiply-add chain +
  dual 128-bit XOR diffusion — disizing agar timing tertutup ≤ ~110–130 MHz ⚠ →
  overclock ≥160 MHz menghasilkan violation riil → digest salah (D8).
- Output ke stable domain (handshake 4-phase): `epoch_p` (tiap 1024 cycle) + `digest`.
- Zeroize: key:=0, checksum:=`0xDEADC0DE`, latch `zeroized`.

### U9 `mon_victim` (clk100)
Shadow recompute: salinan KEY + shadow LFSR/hash, step sinkron per `epoch_p`
(synchronized) → bandingkan digest. Mismatch → `key_corrupt_h` (q=15). Handshake
timeout → `xfer_err` → channel key_corrupt q=8.

### U10 `mon_jtag` (STRETCH, A4:1)
`BSCANE2` USER1: strobe aktivitas SHIFT/UPDATE → `jtag_h`. Batas jujur: hanya
mendeteksi akses USER chain; mewakili "debug port access attempt" untuk demo.

### U11 `sensor_mux`
12 channel spike (§7.1). Mode (D5):
| Mode | Sumber | Makna |
|---|---|---|
| A | semua SYNTH (UART `SPK`/attack_seq) | full digital — Opsi A |
| B | semua REAL (monitor) | full real — Opsi B (pasca GATE 4) |
| **C (default)** | clock=REAL, voltage=SYNTH | hybrid — Opsi C |

### U12 `snn_lif` — Layer 3
- N_NEUR=4, N_CH=12, weight 4×12×8b signed = **48 register inferred** (nol BRAM/DSP;
  multiply 8×4 via LUT), init dari `pkg_weights_gen.vhd` (generated oleh `tune.py`,
  default §7.3), write port dari cmd_parser (`W SET/LOAD`).
- Update (event-driven, per siklus): `on spike(ch,q): V[n] += sat16(V[n] + w[n][ch]×q)`;
  per leak_tick[n]: `V[n] -= V[n] >> M[n]`; `if V[n] ≥ θ[n]: fire[n]=1; V[n] -= θ[n]` (reset subtraktif → sustains panjang fire ulang).
- **Konvensi bit-exact** (satu sumber kebenaran = golden model §7.5): per tick,
  deposit dulu lalu leak; leak integer `V>>M`; saturating add 16b signed.
- **Emission cadence contract** (dari monitor §6-U3/U4): hard = 1 spike/edge;
  soft = 1 spike/window. Konsekuensi: sustained anomaly → stream event;
  transient glitch → ≤1 event.
- Class (D16): neuron pertama capai θ; tie → index terkecil. ALERT = OR(fire[0..2]);
  N3 off di MVP.

### U13 `response`
- Jalur instan: flag hard Layer 1 (per-channel policy) → alert.
- Jalur SNN: fire → alert (bypass jika `BYPASS=1`).
- **Escalation (D11)**: tiap alert → `alert_count++`. `count ≥ ESC_TH` → ACTION.
  `ESC_TH=1` = instan (demo & eksperimen); default 2 = FP-robust.
- ACTION (jika `ARM=1`): **zeroize key_store**, latch ALERT, LED/7-seg, log
  `ALERT class=<c> t=<ts> delta=<Δcyc>`.
- Latency meter: timestamp attack_seq mulai skenario vs ACTION → Δciklus.
- `UNLOCK` (A12:3): clear `alert_count` + latch ALERT/zeroized; **key tetap wipe**
  sampai `KEY SET` ulang.

### U14 `telemetry`
- Event log FIFO BRAM 1k×32b: `(ts_us, code, data)` → drain UART line `E ...`.
- Timestamp counter 32-bit µs. Kode event: lihat `pkg_fsd` (EV_*).
- Counter (RO via `STAT`): per-flag count, alert_cnt, fp_cnt, lat_min/max.
- Mode `LOG`: 0=quiet, 1=event, **2=verbose (stream V[n] tiap leak_tick → plotting Python)**.

---

## 7. SNN Detail

### 7.1 Peta channel (N_CH = 12)
| ch | Nama | Jenis | Sumber |
|---|---|---|---|
| 0 | clk_fast_h | hard | mon_clk |
| 1 | clk_slow_h | hard | mon_clk |
| 2 | clk_stop_h | hard | mon_clk |
| 3 | mmcm_unlock_h | hard | mon_clk |
| 4 | v_under_h | hard | mon_volt |
| 5 | v_over_h | hard | mon_volt |
| 6 | key_corrupt_h | hard | mon_victim |
| 7 | jtag_h | hard | mon_jtag (stretch) |
| 8 | clk_soft | soft | mon_clk |
| 9 | v_soft | soft | mon_volt |
| 10–11 | spare | synth | UART/attack_seq |

### 7.2 Q-Mapping Contract (sensor → SNN)
| Jenis | Definisi | Contoh |
|---|---|---|
| Hard (`_h`) | 1 spike, **q=15** selalu | `clk_fast_h` naik |
| Soft clock | `q = clamp(1 + floor(deviasi%), 1, 15)`, step **1%** | +2.6% → q=3 |
| Soft voltage | `q = clamp(1 + floor(|ΔmV|/4), 1, 15)`, step **4 mV (≈5 code)** | dip 9 mV → q=3 |

Emission: hard = per rising edge; soft = **per evaluation window** (clk: `WND_US`;
volt: tick 100 µs). Deviasi di bawah soft threshold → q=0 → tanpa event.
**SCEN2 → 8 event sparse (q=3); SCEN3 → ~10 clk_soft + ~20 v_soft (q=3, sustained).**

### 7.3 Weight Matrix Definitif (4×12) — sumber kebenaran
θ = 128 semua neuron; leak tick **1 ms** semua neuron.

| ch | Sinyal | N0 TRANSIENT | N1 REPEAT-PROBE | N2 COMBINED | N3 (off) |
|---|---|---:|---:|---:|---:|
| 0 | clk_fast_h | 16 | 4 | 2 | 0 |
| 1 | clk_slow_h | 16 | 0 | 2 | 0 |
| 2 | clk_stop_h | 16 | 0 | 0 | 0 |
| 3 | mmcm_unlock_h | 16 | 0 | 4 | 0 |
| 4 | v_under_h | 16 | 0 | 2 | 0 |
| 5 | v_over_h | 16 | 0 | 2 | 0 |
| 6 | key_corr_h | 16 | 0 | 0 | 0 |
| 7 | jtag_h | 0 | 0 | 4 | 0 |
| 8 | clk_soft | 0 | **11** | **12** | 0 |
| 9 | v_soft | 0 | **11** | **12** | 0 |
| 10–11 | spare | 0 | 0 | 0 | 0 |
| | **leak M** | 3 | **4** | **4** | — |
| | **leak tick** | 1 ms | 1 ms | 1 ms | — |

**Design intent & constraint check:**

| Neuron | Properti yang dijamin | Cek |
|---|---|---|
| N0 | Soft weight = 0 → **mustahil fire dari sub-threshold** (FP=0 by construction); 1 event hard → instan | 16×15=240 ≥ 128 ✓ |
| N1 | 1 event soft (C=33) = 26% θ → no fire; noise 1×/500 ms → bocor total antar event → no fire; SCEN2 → fire event ke-5/8 (margin 3) | 33<128; V₅=133 ✓ |
| N2 | Detector lintas-channel & sustained-anomaly; satu-satunya yang menimbang jtag/mmcm/unlock; sparse single-channel (cadence 2 ms) → V*≈297 fire bersamaan N1 (redundansi = fitur); kombinasi 3 vektor → instan | 36+36+60=132 ≥ 128 ✓ |

**⚠ Design rule leak-quantization (WAJIB):**
```
M ≤ log2(θ) − 1          (θ=128 → M ≤ 6)
```
Alasan: leak `V>>M` = 0 jika V < 2^M → di rentang kerja V≈θ, M terlalu besar
membuat leak MATI TOTAL → neuron jadi pure accumulator → noise 1×/detik pasti
fire (false positive tak terhindarkan). Kontinu "decay 0.39%/tick" bisa berarti
"decay 0%" dalam integer. Verifikasi: seluruh parameter §7.3 memenuhi rule (M≤4 ≤ 6 ✓).

### 7.4 Worked Example — N1 menghadapi SCEN2 (integer eksak)
C = w×q = 11×3 = **33**. Leak per 1 ms; antar event (2 ms) = 2 tick. Fire V≥128, reset subtraktif.

| Event ke | V sebelum | +33 → | Fire? |
|---:|---:|---:|---|
| 1 | 0 | 33 | — |
| 2 | 30 | 63 | — |
| 3 | 57 | 90 | — |
| 4 | 80 | 113 | — (89% θ, aman) |
| 5 | 100 | **133** | **FIRE** → alert (V→5) |

Fire di event 5 dari 8 → margin 3 (tetap fire walau 1–2 spike gagal capture).
Single event = 26% θ → percobaan tunggal attacker tak menyalakan alarm.

### 7.5 Golden Model
`sw/golden/snn_model.py` (numpy, integer bit-exact) — SATU-SATUNYA sumber kebenaran
konvensi (deposit→leak; `V>>M`; saturating 16b; reset subtraktif; class rule D16).
TB membandingkan RTL vs golden per siklus. Konsep dipinjam dari Python model repo
Winzker (attribution).

### 7.6 Tuning Procedure (analytic-first, ML-last)
Tiga lapis parameter, urutan TIDAK boleh dibalik:
```
A: THRESHOLD SENSOR (CLK_SOFT_TH, V_SOFT_TH)  → "apa yang dianggap anomali"
B: INTENSITAS q (dari deviasi vs step)        → "seberapa aneh"
C: NEURON (w, θ, M, tick)                     → "berapa anomali dalam berapa waktu = alarm"
```

1. **Ukur noise floor** (hardware, SCEN0 + `LOG 2`) — semua tuning dari angka terukur.
2. **Set threshold sensor** di atas noise floor (mis. ×1.5) — noise normal → q=0 → SNN tak banjir.
3. **Desain analytik**: `decay = (1−2^−M)^ticks`; titik jenuh `V* = C/(1−decay)`;
   syarat: fire ≤ E_target ∧ C < θ ∧ V*_noise < θ.
4. **Golden sweep** (`sw/golden/tune.py`): grid search di sekitar hasil analytik;
   constraint = fire(SCEN2) ≤ E6 ∧ no-fire(1 event) ∧ no-fire(1 jam noise) ∧
   fire(SCEN3) ∧ no-fire(SCEN0). Output: **`pkg_weights_gen.vhd` + `weights_default.hex`
   + tabel margin** (lampiran laporan). Ratusan kombinasi = detik.
5. **Deploy & verifikasi live TANPA resynthesis**: `W SET`/`CFG`/`LOG 2` → lihat V[n]
   real-time → `S 0` (FP) → `S 2` (deteksi). Semua parameter = register.

**Aturan empty-window**: jika sweep tak menemukan parameter yang sekaligus
fire-untuk-serangan & silent-untuk-noise → masalahnya di LAPIS SENSOR (geser
`CLK_SOFT_TH`/`V_SOFT_TH` agar q lebih terpisah), bukan di neuron.

---

## 8. Register Map & Command Set (kontrak UART)

Line protocol, `\n` terminator; angka desimal kecuali `KEY SET` (hex).
Reply `OK ...` / `ERR <code>`.

| Command | Shortcut | Aksi |
|---|---|---|
| `PING` | — | ID: `OK SNN-GUARD fw=1.0 part=xc7a100t` |
| `MODE <A/B/C>` | — | sensor_mux |
| `KEY SET <32hex>` / `KEY SHOW` / `KEY WIPE` | `K` | muat / lihat / zeroize |
| `ARM <0/1>` | — | response aktif / log-only (default 1, D15) |
| `BYPASS <0/1>` | — | 1 = baseline (Layer 3 off; default 0) |
| `UNLOCK` | — | clear alert_count + latch ALERT/zeroized (key tetap wipe) |
| `SPK <ch> <q>` | — | inject spike synth (mode A) |
| `CLK GLITCH <us> <div>` | `G <us> <div>` | DRP glitch |
| `CLK STOP <ms>` | — | DRP power-down |
| `CLK SWEEP <lo> <hi> <step> <us> <reps>` | — | parameter sweep |
| `VSTRESS <ms>` | — | stressor on |
| `SCEN <0-4>` | `S <0-4>` | preset skenario (§13) |
| `CFG <addr> <val>` | — | tulis register |
| `W SET <n> <ch> <val>` | — | tulis 1 weight |
| `W LOAD` … `W END` | — | upload weight multi-line hex (urutan n-major, ch-minor) |
| `W DUMP` | — | dump weight matrix |
| `STAT` | — | dump counter metrik |
| `LOG <0/1/2>` | — | mode telemetry (2 = stream V[n]) |
| `RESET` | — | soft reset penuh (tanpa reply) |

**CFG map**: `0x01 MODE, 0x02 ARM, 0x03 BYPASS, 0x04 WND_US, 0x05 CLK_HI_PCT,
0x06 CLK_LO_PCT, 0x07 CLK_SOFT(%), 0x08 STALL_CYC, 0x09 V_UNDER(code), 0x0A V_OVER,
0x0B V_SOFT(mV), 0x0C reserved, 0x0D ESC_TH, 0x10–13 θ[0..3], 0x14–17 leak_tick_us[0..3],
0x18–1B M[0..3], 0x20–4F weight[n*12+ch] (n-major)`.

**RO map (0x50+)**: `0x50 alert_cnt, 0x51 fp_cnt, 0x52–5A flag_cnt[...],
0x5B lat_min, 0x5C lat_max, 0x5D fw_ver, 0x5E vccint_code(live), 0x5F clk_dev_pct(live)`.

---

## 9. Constraint (XDC) Plan

```
## pin: HANYA dari Digilent master XDC (make setup → constr/nexys_a7_100t.xdc)
create_clock -period 10.000 -name clk100 [get_ports CLK100MHZ]
## B4+: clk_core DRP-reconfigurable → antar-domain async
set_clock_groups -asynchronous -group [get_clocks clk100] -group [get_clocks clk_core]
set_property ASYNC_REG TRUE [get_cells -hier -filter {NAME =~ *sync*ff*}]
```
Timing: clk100 100 MHz (mudah); victim `clk_core` dijamin sampai ~110–130 MHz ⚠
(sengaja — fault model overclock). Catat WNS per karakterisasi.

---

## 10. I/O Mapping (logis; pin = master XDC)

| LED | Fungsi | | Input | Fungsi |
|---|---|---|---|---|
| 0 | heartbeat 1 Hz | | BTNC | manual single glitch (`G 1000 5`) |
| 1 | mmcm locked | | BTNU | manual sweep |
| 2 | armed | | BTND | run SCEN (SW[15:12] memilih) |
| 3 | mode ind (A=off, B=on, C=blink) | | SW[0] | ARM |
| 13 | stressor active | | SW[1] | BYPASS |
| 14 | zeroized (clear saat UNLOCK) | | SW[15:12] | SCEN select |
| 15 | ALERT | | | |

7-seg: digit[7:6]=class terakhir, digit[5:2]=V[n1], digit[1:0]=state (`NR`,`AR`,`ZO`,`AL`). Mux 1 kHz.

**Demo pattern (A11:3)**: quick demo via tombol (BTND), detail & Q&A via UART (`K`, `STAT`, `LOG 2`).

---

## 11. Struktur Repo & Konvensi

```
fpga-snn-guard/
├── docs/FSD.md                      ← DOKUMEN INI (kontrak)
├── docs/source_attribution.md       ← commit hash semua sumber eksternal
├── docs/reuse_report.md             ← hasil analisis repo Winzker (agent, Fase 1)
├── AGENTS.md                        ← aturan kerja AI agent
├── rtl/
│   ├── pkg_fsd.vhd                  ← konstanta & default (⚠ weight: sync ke §7.3 saat B6)
│   ├── pkg_weights_gen.vhd          ← GENERATED oleh tune.py (B6); jangan edit manual
│   ├── top.vhd
│   ├── clk_gen.vhd  mmcm_drp.vhd  uart_host.vhd  cmd_parser.vhd
│   ├── mon_clk.vhd  mon_volt.vhd  mon_victim.vhd  victim_core.vhd
│   ├── stressor.vhd  sensor_mux.vhd  snn_lif.vhd  response.vhd  telemetry.vhd
│   └── reuse/                       ← kode borrow Winzker + header attribution
├── sim/  (tb_*.vhd)                 ← self-checking, L1+L2 (§12)
├── constr/ (nexys_a7_100t.xdc [generated], Nexys-A7-100T-Master.xdc, timing.xdc)
├── scripts/ (setup.sh, xdc_active.py, build.tcl, sim.tcl, prog.tcl)
├── sw/golden/ (snn_model.py, tune.py)
├── sw/host/ (attack_cli.py, run_experiments.py)
├── weights/weights_default.hex      ← GENERATED oleh tune.py
└── Makefile                         → make setup / sim / synth / bit / prog / clean
```

**Status artefak kode** (B0 package sudah dibuat): `pkg_fsd.vhd` ⚠ STALE (weight
draft lama w=16/M=6 — wajib sync ke §7.3 via tune.py di B6); `top.vhd`, `tb_top_b0`,
`timing.xdc`, `setup.sh`, `xdc_active.py`, `build.tcl`, `prog.tcl`, `Makefile`,
`AGENTS.md` = current.

**Header attribution (wajib file reuse/modified):**
```vhdl
-- [REUSE] Adapted from Marco-Winzker/Spiking_NN_RGB_FPGA @ <commit-hash>
-- Original: <file/entity> — MIT License. Modified by <tim>: <ringkasan>
```

**Aturan TB**: self-checking, print `PASS/FAIL <nama>` + metrik ke stdout. Tanpa
waveform. Parameterizable via generic (shrink config → sim detik). Modul tanpa TB
hijau tidak boleh diintegrasikan.

---

## 12. Testing Architecture (5 Layers)

**Prinsip utama: sim dulu, board belakangan.** Biaya iterasi sim = detik–menit;
board = 10–20 menit (sintesis+bitstream+program). Board = alat VERIFIKASI, bukan
tempat debugging. Larangan: tidak boleh `make bit`/`make prog` sebelum semua sim
(L1+L2) fase terkait hijau.

**Klaim validasi**: skenario identik dijalankan di sim dan hardware; kecocokan
keduanya bagian dari bukti (Equivalence Contract di bawah).

### L1 — Unit Testbench (per modul, sim)
- Satu TB per modul U1–U14; "serangan" = stimulus kode (ubah periode clock, inject
  spike, byte UART) — bukan tombol fisik.
- Self-checking `PASS/FAIL` stdout. Wajib parameterizable (generic shrink; contoh
  `tb_top_b0` override `HEARTBEAT_BIT=>5`). Unit sim selesai dalam detik.

### L2 — Scenario Testbench (integrasi, sim)
- `tb_scen1..4` mereplikasi preset §13 parameter identik. Dua cek: (a) self-check
  RTL, (b) RTL vs golden model bit-exact.
- Biaya: SCEN2 ≈16 ms realtime = 1,6 jt siklus → xsim beberapa menit. Wajar untuk
  integrasi; JANGAN di unit sim.
- Mode run: shrunk-config (regresi tiap commit) + full-config (pre-check GATE).

### L3 — Hardware Smoke Test (board, manusia, ~15 menit/GATE)
- Verifikasi fisik per fase (§14 DoD): heartbeat, `PING`, `KEY SET/SHOW`, `STAT`
  (plausibilitas XADC), glitch tunggal, trigger via tombol.
- Kriteria masuk: semua L2 fase itu hijau. Tanpa pengecualian.

### L4 — Eksperimen Hardware Otomatis (board, agent)
- `run_experiments.py` via pyserial: `UNLOCK` → `S <n>` → drain log → parse → CSV.
- Tanpa input manusia (attack_seq internal). Antigravity BOLEH jalan mandiri
  (kirim/baca/assert); eskalasi ke manusia hanya jika hasil hardware ≠ sim.
- Prosedur mismatch (temuan, bukan kegagalan): ambil parameter terukur dari hardware
  → masukkan ke L1/L2 → reproduksi → fix → rerun kedua dunia. Kelas akar masalah:
  CDC, noise/kalibrasi XADC, timing, state tak ter-init.

### L5 — ILA (opsional, upaya terakhir)
- Jika log UART tak memadai (mis. bentuk dip stressor). Agent siapkan IP ILA +
  export via Tcl→CSV; eksplorasi interaktif = manusia. Bitstream debug TERPISAH
  dari bitstream demo.

### Equivalence Contract
| | Sim (L2) | Hardware (L3/L4) |
|---|---|---|
| Stimulus | proses TB | attack_seq + UART/tombol |
| Observasi | semua sinyal internal | UART log, LED/7-seg, STAT |
| Sama | parameter skenario, RTL | parameter skenario, bitstream |
| Harus cocok | "fire di event ke-N" | "fire di event ke-N" |

Mismatch = temuan berprosedur L4. Bukti akhir: tabel hasil sim vs board per skenario.

---

## 13. Skenario & Rencana Eksperimen

### Preset (attack_seq; semua parameter via CFG)
| SCEN | Nama | Isi | Baseline (L1 saja) | Full (L1+L3) | Latency harapan |
|---|---|---|---|---|---|
| 0 | NORMAL | 10 s tanpa serangan | 0 alert | 0 alert (FP) | — |
| 1 | SINGLE-GLITCH | 200 MHz, 5 µs, 1× | terdeteksi (clk_fast/gross) | terdeteksi (tidak regresi) | **L1 path <1 ms** |
| 2 | REPEAT-PROBE | div 39 (+2.6%) 2 µs, tiap 2 ms, ×8 | **lolos** (di bawah ±5%) | **fire N1 event ke-5 → alert** | L3 path ≈8 ms (per golden) |
| 3 | COMBINED | clock −2% 1 ms + VSTRESS 2 ms | **lolos** (dua-duanya sub-hard-threshold) | **fire (stream sustained, N1/N2)** | L3 path ≈0,4–1 ms |
| 4 | SWEEP | div 80→5 step 1 dwell 100 µs | sebagian | 100% | campuran |

Catatan latency (A2:2 di-scope): target **<1 ms berlaku untuk jalur L1** (hard flag
→ ACTION). Jalur SNN by design lebih lambat (akumulasi); targetnya = match prediksi
golden model ±20%, dilaporkan terpisah.

### Protokol eksperimen (dengan escalation D11)
Tiap run: `UNLOCK` → set `CFG 0x0D 1` (ESC=1, instant) → trigger → drain log →
catat (detected_by L1/L3/none; class; latency; zeroize latency). FP = alert apapun.
Run tambahan dengan ESC default 2 = data robustness.

### Eksperimen (run_experiments.py)
| ID | Isi | Target (A2:2) |
|---|---|---|
| E1 | SCEN0 ×10, ARM=1 | FP = 0 |
| E2 | SCEN1 ×20, BYPASS 1 vs 0 | 100% keduanya; no-regression |
| E3 | SCEN2 ×20, kedua mode | **FN-reduction ≥90%** (metrik headline) |
| E4 | SCEN3 ×20, kedua mode | FN-reduction ≥90% |
| E5 | SCEN4 ×10, kedua mode | 100% |

Output `results/exp_<id>.csv` (kolom: scenario, run, mode, bypass, detected_by,
class, latency_cycles, zeroized). Plot: V[n] vs waktu (`LOG 2`) → figure presentasi.

---

## 14. Bring-up Sequence (B0–B9, GATE review)

| Fase | Isi | Definition of Done | Review |
|---|---|---|---|
| B0 | project Tcl + clk100 + heartbeat + build batch | `make setup && make sim && make bit` pass; LED0 blink | **[GATE 1]** |
| B1 | uart_host + PING/echo | PING dari terminal & attack_cli.py | — |
| B2 | victim_core + key_store + CFG/KEY | `KEY SET/SHOW/WIPE` benar; STAT hidup | — |
| B3 | mon_volt (XADC) | VCCINT code 1300–1450 ⚠ di STAT | **[GATE 2]** |
| B4 | mmcm_drp + mon_clk | freq terukur cocok ±0,5%; min-glitch-duration terukur & dicatat | **[GATE 3]** |
| B5 | attack_seq + SCEN1–4 + stressor + karakterisasi ⚠ | SCEN1 tertangkap L1; **SCEN2 terkonfirmasi LOLOS L1**; magnitudo dip stressor tercatat → keputusan MODE B (A1) | **[GATE 4]** |
| B6 | snn_lif + golden + **tune.py** | TB RTL vs golden bit-exact; sweep menghasilkan `pkg_weights_gen.vhd` final + tabel margin; **`pkg_fsd.vhd` weight di-sync** | — |
| B7 | response + escalation + BYPASS + latency meter | SCEN2 full (`CFG 0x0D 1`) → zeroize+ALERT; BYPASS=1 → tidak; Δcyc log | **[GATE 5]** |
| B8 | eksperimen E1–E5 otomatis + CSV + plot | tabel hasil lengkap (bahan proposal §8/§9) | — |
| B9 | STRETCH (A4:1): mon_jtag (BSCANE2) + GSR (STARTUPE2) | jtag_h terpicu oleh probing JTAG riil; GSR → fabric reset, secure defaults (D15) | opsional |

---

## 15. Portability (DE10-Nano — bootcamp, TIDAK sekarang)
- Primitive Xilinx terisolasi di wrapper: `clk_gen`, `mmcm_drp`, `mon_volt`, `mon_jtag`
  → padanan Intel per-wrapper. Core logic (SNN, monitor aritmetika, response) = RTL generik.
- Constraint `.xdc` ↔ `.sdc/.qsf` dipisah per target.
- Tanpa primitive BRAM/DSP langsung (infer dari kode).

---

## 16. Estimasi Resource
| Resource | Estimasi | Catatan |
|---|---|---|
| LUT | 8–12k (~15%) | didominasi stressor + telemetry |
| FF | 12–18k | stressor shifter + sinkronisasi |
| BRAM | 2–3 | event log (weight = register, bukan BRAM) |
| DSP | 0 | multiply 8×4 via LUT |
| MMCM / XADC | 1 / 1 | hardcoded |
≪ kapasitas 100T. Verifikasi riil pasca B7.

---

## 17. Risiko Teknis & Mitigasi
| Risiko | Mitigasi |
|---|---|
| Dip stressor < noise XADC | karakterisasi B5; fallback: `V_SOFT_TH` turun / stressor sinkron diperbesar / `MODE A` |
| Overclock tidak menghasilkan korupsi | victim heavy (D14) dip sizing agar Fmax ~110–130 MHz; korupsi bukan syarat demo S2/S3 (soft-path tetap jalan) |
| Durasi glitch minimal DRP ≫ target µs | ukur B4; skenario pakai durasi ≥ batas terukur |
| Metastability merusak handshake victim | xfer_err = event (by design) |
| Repo Winzker tak mudah diadaptasi | fallback LIF hand-written (~150 baris, attribution konsep) — dianggarkan |
| Adaptasi repo molor | fallback single-neuron hand-crafted dari awal |
| Leak kuantisasi mematikan integrator | design rule M ≤ log2(θ)−1 (§7.3); diverifikasi tune.py |
| ESC_TH default 2 menyembunyikan zeroize di demo | demo & B7/E2–E5 pakai ESC=1; ESC=2 sebagai run robustness |

---

## 18. Traceability ke Proposal
| Proposal | FSD |
|---|---|
| §4 arsitektur 3-layer | §4, §6 (U3/U4/U9/U10 = L1; U11→U12 = L3; U13 = Response; U5/U6/U7 = Attack Sim) |
| §4.1 Opsi A/B/C | D5 sensor_mux (A1:4) |
| §4.2 XAPP1084 | U10 (BSCANE2) + GSR (STARTUPE2) — B9 |
| §5 langkah 1–11 | §14 B0–B9 |
| §8 metrics | U13 latency meter + U14 counters + §13 (latency L1 <1 ms; L3 vs golden) |
| §9 baseline | D10 `BYPASS` + §13 |
| §10 risiko & kontingensi | §17 |
| §11 attribution | §11 header + docs/source_attribution.md |
| §13 demo flow | §10 demo pattern + A11:3, A12:3, D11 (ESC switching) |
| Template §3.2 (Rencana Pengujian: RTL / hardware / SignalTap) | §12 L1–L2 / L3–L4 / L5 (ILA) |

---

## 19. Open Items — sebelum development penuh
- [ ] **C1**: `vivado -version` → 2025.2 terkonfirmasi
- [ ] **C2**: board terdeteksi (FTDI Dual-RS232 + power LED)
- [ ] **C3**: repo dibuat & first commit (FSD + B0 package)
- [ ] **C4**: smoke test Antigravity (clone Winzker → docs/reuse_report.md)
- [ ] **C5**: Python ≥3.10
- [ ] **PIC Michel [KONFIRMASI]**: Layer 1 + integrasi/sintesis + dokumentasi lead?
- [ ] `pkg_fsd.vhd` B0: init_weights masih DRAFT → sync ke §7.3 via tune.py (B6)
- [ ] Review & sign-off FSD v1.0-RC oleh seluruh tim (tiap anggota baca §0, §7, §12–14)

---

## 20. Demo Narrative (untuk presentasi — mapping proposal §13)
1. Problem (30 s): gap threshold-based → pola serangan lolos.
2. Arsitektur (45 s): diagram 3-layer (§4).
3. Live demo (1–2 mnt): setup `CFG 0x0D 1` (ESC=1), ARM=1, MODE sesuai keputusan
  GATE 4. (a) `S 1` via BTND → L1 instan-kill. (b) `S 2` → **L1 diam** (tunjukkan
  STAT: clk_fast_h = 0) → SNN fire → LED15 + zeroize (LED14). (c) `LOG 2` + plot
  V[n1] menunjukkan akumulasi & leak real-time. (d) opsional B9: trigger GSR on
  camera → "reset oleh silikon, bukan kode kami".
4. Hasil kuantitatif (45 s): tabel E1–E5 (FN-reduction, FP, latency sim vs board).
5. Transparansi (30 s): serangan = simulasi terkontrol (DRP/stressor); kenapa valid.
6. Future work (15 s): §14 FSD proposal (training real dataset, adversarial eval, dst).

Re-provisioning moment (A12:3): setelah zeroize, `KEY SET` ulang via UART =
"chip tidak percaya dirinya sendiri sampai host re-provision lewat channel aman".