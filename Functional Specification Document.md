# **FSD — SNN Anti-Tamper Self-Monitor di FPGA Nexys A7-100T (Proof of Concept)**

Versi: 0.2 (merevisi v0.1). Perubahan utama: DUT \= FPGA itu sendiri, sensor internal (suhu, VCCINT, clock, integritas memori), SNN minimal **1 neuron LIF**, ada tamper emulator, action FSM, dan protokol evaluasi yang adil terhadap threshold biasa. Target: Xilinx Artix-7 XC7A100T (Nexys A7-100T), RTL **VHDL-2008**, tool **Vivado**.

> Semua angka adalah **nilai awal**. Semuanya ada di `params.yaml` (single source of truth) dan dituning dari **log sensor asli**, bukan dari tebakan. Dilarang hardcode di VHDL.

---

## **1\. Tujuan & Hipotesis**

Membuktikan bahwa **satu neuron LIF** yang memfusikan beberapa sensor internal secara temporal bisa mendeteksi tamper yang lolos threshold biasa, pada tingkat false alarm yang sama.

* **H1**: pada false alarm yang disamakan, SNN-1N mendeteksi skenario kombinasi-lemah (A4, A5) lebih sering dan/atau lebih cepat daripada threshold per-sensor.  
* **Hasil negatif itu sah.** Kalau tidak ada beda, laporkan apa adanya. PoC ini harus bisa gagal supaya hasilnya bermakna.  
* **Pemisahan klaim.** Baseline B3 (logistic regression pada fitur yang sama, §7.3) memisahkan "fusi \+ integrasi temporal" dari "spiking". Kalau B3 sama bagusnya, keunggulan datang dari fusi, bukan dari spike. Nilai SNN lalu ada di implementasi event-driven tanpa multiplier. Laporkan jujur.

  ## **2\. Scope & Asumsi**

* DUT \= XC7A100T. Monitor dan aset yang dilindungi ada di device yang sama. **Tanpa analog front-end.**  
* Tamper di-emulasi oleh blok `tamper_emulator` (compile-time `ENABLE_EMULATOR`) dan opsional fisik (jaga Tj \< 70 °C; grade komersial 0–85 °C).  
* **Di luar scope**: tamper invasif; serangan yang tidak menggeser satu pun sensor; glitch skala ns (tick ≈ 0,5 ms); attacker adaptif yang tahu detektor; attacker yang menguasai die dan mematikan monitor (self-monitoring tidak melindungi dari itu). Ini prototipe riset, bukan produk tersertifikasi.

  ### **2.1 Sensor**

| Parameter | Sensor | Konversi | Catatan |
| ----- | ----- | ----- | ----- |
| Suhu die | XADC temperature (ch 0x00) | `T[°C] = code × 503.975 / 4096 − 273.15` (≈ 0,123 °C/LSB) | via XADC Wizard, sequencer \+ averaging |
| Tegangan internal | XADC VCCINT (ch 0x01) | `V = code × 3 / 4096` (≈ 0,73 mV/LSB), nominal ≈ 1,0 V | opsional: VCCBRAM (0x06), VCCAUX (0x02) |
| Clock | **Ring oscillator (RO)** on-chip, jumlah siklusnya dihitung di window clock 100 MHz | `F = hitungan RO per window 2^15 clk` | RO independen dari osilator board, jadi pergeseran clock utama terlihat. RO juga peka V/T, dan itu **berguna**: korelasi antar-sensor bisa dimanfaatkan neuron |
| Integritas memori | **BRAM monitor**: 1×BRAM36 (1024×32), diisi `f(addr)` saat boot, di-scan tiap tick | `M = jumlah kata salah per scan` (saturasi 8 bit) | `f(addr)` \= hash deterministik (mis. `addr × 0x9E3779B1 xor C`). Setelah dihitung, kata salah ditulis ulang (scrub) supaya satu flip dihitung sekali |

Rumus konversi diambil dari UG480; **agent wajib memverifikasi** ke dokumen, jangan percaya angka di sini mentah-mentah.

RO: loop inverter di LUT (`DONT_TOUCH`, izinkan combinatorial loop untuk DRC LUTLP-1, `set_false_path` ke domain clk), pakai prescaler, lalu 2-FF synchronizer dan penghitung tepi di domain clk.

## **3\. Arsitektur**

1. XADC (Temp, VCCINT) \--\> feature\_unit \--\\  
2.  RO sensor \------------\> (EMA, selisih,  \> spike\_encoder \--14 spike--\> LIF neuron \--\> alarm\_fsm \--\> response\_unit  
3.  BRAM monitor \---------\> learn\_unit)    /      (m x S)        (1 neuron)      |            |- zeroize key  
4.                                                                               |            |- black-box buffer  
5.  tamper\_emulator (test-only):                                              telemetry /     |- LED, UART  
6.    power waster | clock-skew injector | bit-flip injector                   logger (UART)  
     
* Satu clock 100 MHz, reset sinkron dari CPU\_RESET (di-synchronize).  
* **Tick \= event EOS (end-of-sequence) dari XADC Wizard**, dengan averaging 256 sampel dan 2 kanal (Temp, VCCINT): ≈ 2 × 256 × 104 clk ≈ 53.000 clk ≈ **0,53 ms (≈ 1,9 kHz)**. Angka pasti diambil dari konfigurasi wizard. Tick dari XADC (bukan counter bebas) mencegah sampel duplikat/skip yang akan merusak fitur selisih.  
* Pada tiap tick: RO dihitung di window tetap 2^15 clk; BRAM di-scan penuh (1024 clk). Semua muat jauh di dalam 53.000 clk.  
* Neuron tunggal dengan 14 input: update ≤ 50 clk per tick. Tidak butuh DSP.

  ## **4\. Spesifikasi Fungsional**

  ### **4.1 Mode (FR-01)**

`IDLE → WARMUP (N_WARM = 4096 tick) → LEARN (N_ACC = 16384 tick) → RUN`. SW\[0\] memicu enrollment. Alarm tidak armed selama WARMUP/LEARN. Mode **LOGGER** (SW\[1\]) menyiarkan fitur mentah ke PC dan menonaktifkan SNN (untuk pengumpulan data, §7.1).

### **4.2 Learn / enrollment (FR-02)**

Dari data normal tersimpan: `REF_T`, `REF_V`, `REF_F` (rata-rata) dan skala `S_x = mean|fitur|` (Q.4) untuk setiap fitur. Clamp `S_x ≥ S_min` (sebesar resolusi sensor) supaya threshold tidak nol pada sinyal sangat tenang. Threshold encoder \= `m × S_x` dengan `m` konstanta kecil (shift/add, tanpa divider). Hasilnya bobot portabel antar-board. Enrollment dilakukan ulang bila ALARM di-clear.

### **4.3 Fitur (FR-03) — integer, urutan identik di Python dan VHDL**

`>>>` \= arithmetic shift right (floor), sama dengan `shift_right(signed)` di VHDL dan `>>` pada int numpy. Baseline/EMA disimpan dengan fractional bit cukup (Q.16) supaya tidak macet oleh deadband floor.

| Fitur | Rumus |
| ----- | ----- |
| `T_dev` | `Tf − REF_T`, `Tf` \= EMA(Tc, K\_T1) |
| `T_trend` | `EMA(Tc, K_T1) − EMA(Tc, K_T2)` (tren naik/turun tanpa memori histori) |
| `V_dev` | `Vf − REF_V` |
| `V_step` | `Vc[t] − Vc[t−1]` |
| `V_noise` | `e_V = EMA(|V_step|, K_E)` |
| `F_dev` | `Ff − REF_F` |
| `F_noise` | `e_F = EMA(|F[t] − F[t−1]|, K_E)` |
| `M` | `n_bad` per scan (langsung) |

### **4.4 Spike encoder (FR-04) — 14 channel, level-crossing (spike \= 1 pada tick selama kondisi benar)**

| ch | Fitur | Kondisi | Threshold |
| ----- | ----- | ----- | ----- |
| 0 / 1 | T\_dev | `≥ +θ` / `≤ −θ` | `m_Td · S_Td` |
| 2 / 3 | T\_trend | naik / turun | `m_Tt · S_Tt` |
| 4 / 5 | V\_dev | turun (droop) / naik | `m_Vd · S_Vd` |
| 6 | V\_step | `≤ −θ` (droop cepat) | `m_Vs · S_Vs` |
| 7 | V\_noise | `e_V ≥ θ` | `m_Vn · S_Vn` |
| 8 / 9 | F\_dev | RO melambat / mempercepat | `m_Fd · S_Fd` |
| 10 / 11 | F\_noise | tinggi / rendah | `m_Fn_hi · S_Fn`, `m_Fn_lo · S_Fn` |
| 12 | M | `n_bad ≥ 1` | — |
| 13 | M | `n_bad ≥ 2` atau `n_bad ≥ 1` di ≥ 2 scan beruntun | — |

Nilai awal semua `m_*`: dipilih dari **log normal** sehingga laju spike normal tiap channel ≈ 0,5% per tick (persentil ke-99,5). Itu aturan penurunannya, bukan angka karangan.

### **4.5 Neuron (FR-05) — Stage A: tepat 1 neuron LIF**

Per tick, urutan didefinisikan persis (golden dan RTL harus sama):

1. `v = v − (v >>> L)`  
2. `v = v + Σ_i w[i] · s[i]` (hanya spike aktif; 14 sinapsis)  
3. saturasi int16  
4. jika `v ≥ VTH`: `spike_out = 1`, `v = v − VTH` (soft reset)

Bobot int8 signed. `L` (leak) dipilih dari grid 5..9 (τ \= 2^L tick ≈ 17 ms–270 ms). Neuron ini adalah **integrator berbobot dengan memori temporal**: bukti lemah dari beberapa sensor yang terjadi bersamaan dalam rentang waktu akan menumpuk di membran, sedangkan bukti dari satu sensor saja tidak. **Stage B (opsional, hanya jika perlu):** hidden layer 14→8→1 untuk korelasi non-linear. Core ditulis dengan generic `N_HID` (0 \= Stage A), tapi default dan klaim PoC adalah Stage A.

### **4.6 Alarm & Action (FR-06)**

`count` \= jumlah spike output dalam sliding window W \= 1024 tick (≈ 0,54 s).

| State | Masuk bila | Aksi |
| ----- | ----- | ----- |
| NORMAL | default | tidak ada |
| SUSPECT | `count ≥ N_SUS` | LED kuning; **black box freeze** (ring buffer 512 tick terakhir: 14 bit spike \+ 4 fitur mentah, bisa dibaca via UART); frekuensi scrub BRAM dinaikkan; flag ke telemetry |
| ALARM (sticky) | `count ≥ N_ALM` atau **hard backstop** | LED merah; **zeroize**: register kunci 128-bit di-clear sinkron, output aset diputus (`protected_en = 0`); pesan UART `ALARM tick=…`; black-box dikunci untuk forensik |

* SUSPECT → NORMAL hanya bila `count < N_SUS − HYST` (histeresis).  
* ALARM hanya bisa di-clear manual (BTNC) **dan** wajib re-enroll, karena baseline bisa sudah terkontaminasi. Kunci harus di-load ulang.  
* **Hard backstop (deterministik)**: ALARM langsung bila `VCCINT` di luar window datasheet, `Tj` di luar batas, atau `n_bad ≥ M_HARD` (mis. 8 kata). SNN ditujukan untuk kasus halus; pelanggaran kasar ditangani aturan sederhana (defense in depth). Backstop punya parameter `HARD_EN` dan **dimatikan saat evaluasi SNN** (§7.3) supaya yang diukur murni SNN.  
* Zeroize adalah logika hard-wired (bukan software). Latensi dari `alarm` ke clear kunci ≤ 2 clk.

  ### **4.7 Aset yang dilindungi (FR-07)**

`protected_core`: register kunci 128-bit \+ LFSR sederhana yang memakai kunci, outputnya ke LED/PMOD. Sebelum ALARM output berdenyut, sesudahnya tetap nol. Ini memperagakan action secara nyata di board.

### **4.7a Tamper emulator (FR-08, test-only)**

Dikontrol via UART (level \+ durasi), seluruh aktivitasnya dicatat ke telemetry sebagai **label ground-truth** (bit `emu_active`, kode skenario, intensitas).

* **Power waster**: bank flip-flop toggling (LFSR) dengan duty/intensitas 0..15 dan mode `steady` / `pulsed` (frekuensi pulsa terprogram). Efek: droop VCCINT, naik suhu, jitter RO. **Pengaman**: otomatis nonaktif bila `Tj > T_SAFE` (default 75 °C).  
* **Clock-skew injector**: window clock RO dikendalikan clock-enable yang di-skip 1 dari N pulsa, menghasilkan pergeseran frekuensi efektif 0,1–1% (emulasi manipulasi clock; bukan manipulasi osilator fisik).  
* **Bit-flip injector**: XOR bit tertentu pada port B BRAM monitor; mode single, burst (k flip per detik), dan sebaran acak.

Ini emulasi terkontrol, jadi harus dilaporkan sebagai emulasi.

### **4.8 UART & Logger (FR-09)**

* **Logger**: frame 8 byte per tick `{T_code[2], V_code[2], F[2], M[1], flags[1]}` (flags: mode, emu\_active, alarm state). ≈ 15 kB/s, jadi **921600 baud** (115200 tidak cukup).  
* **Telemetry RUN**: ringkas, tiap 16 tick, 115200 cukup.  
* **Perintah RX**: mode, enrollment, `emu_*`, set `N_SUS/N_ALM`, clear alarm, dump black box.  
* Semua pin (clock, LED, switch, tombol, UART) **diambil dari Master XDC Digilent**, bukan ditebak.

  ## **5\. Threshold — tiga lapis**

1. **Threshold encoder** (per fitur): `m × S_x` dari enrollment (§4.2, §4.4). Ini yang membuat variasi normal tidak dianggap anomali: ambangnya mengikuti noise normal IC/board itu sendiri.  
2. **Threshold neuron**: `VTH` dan `L`, hasil training (§6), dikunci di `snn_weights_pkg.vhd`.  
3. **Threshold alarm**: `W`, `N_SUS`, `N_ALM`, `HYST`. Ini satu-satunya yang boleh digeser setelah bobot terkunci, untuk mengatur trade-off false alarm vs latency: sweep di validation set, ambil titik dengan false alarm terendah yang masih memenuhi target latency.

**Threshold klasik (untuk baseline & backstop):**

| Sensor | Window datasheet (B1) |
| ----- | ----- |
| VCCINT | 0,95–1,05 V (Artix-7 DS181, grade \-1; **agent verifikasi**) |
| Tj | 0–85 °C (grade komersial) |
| RO | `REF_F ± TOL_F`, default ±3% |
| Memori | `n_bad ≥ 1` (strict) |

## **6\. Weight**

### **6.1 Model dan format**

1 neuron: 14 bobot int8 signed ∈ \[−127, 127\], `VTH`, `L`. Diekspor sebagai `snn_weights_pkg.vhd` (konstanta array; `constant W : w_t(0 to 13)`) beserta hash SHA-256 yang sama dengan header vektor golden.

### **6.2 Prosedur**

1. **Hipotesis tanda (sanity check, bukan constraint).** Bukti tamper cenderung berbobot positif: `V_noise↑`, `F_noise↑`, `V_step↓`, `M≥2`. Kandidat penjelasan jinak cenderung negatif/lemah: `T_dev↑` atau `V_dev↓` yang menjelaskan `F_dev↓` (panas atau droop memperlambat RO), sehingga RO melambat **tanpa** gerak suhu/tegangan menjadi yang mencurigakan. Tanda nyata dipelajari dari data; kalau hasil training bertentangan dengan fisika, selidiki dulu sebelum percaya.  
2. **Inisialisasi**: logistic regression (L1, class weight benign lebih besar) pada fitur `x_i(t) = Σ_k s_i(t−k)·(1 − 2^−L)^k`, yaitu keadaan integrator leaky untuk tiap channel. Convex, cepat, dan setara dengan neuron LIF linear.  
3. **Fine-tune**: BPTT dengan surrogate gradient lewat neuron LIF integer (custom, bukan snnTorch, supaya persamaan leak shift dan soft reset persis sama dengan §4.5), chunk 2048 tick. Label \= `emu_active` (exact, dari telemetry).  
4. **QAT int8**: `w_int = clamp(round(w·s), −127, 127)` dengan straight-through estimator; `s` dipilih agar `max|w| ≈ 100`.  
5. **Grid `L ∈ {5..9}`**, `VTH` ditentukan agar target false alarm tercapai.  
6. **Validasi di golden model integer** pada sesi yang tidak dipakai training. **Angka yang sah adalah angka dari golden integer, bukan forward training.**  
7. Bila bobot final masih belum memberi keunggulan atas B2: coba Stage B (§4.5) sebelum menyimpulkan.

   ## **7\. Data & Evaluasi**

   ### **7.1 Data asli lebih dulu (karena DUT ada di board)**

Mode LOGGER mengumpulkan log fitur mentah ke PC (CSV). Ini menutup kelemahan "data sintetis ≠ dunia nyata" dari versi sebelumnya.

**Normal (label 0\)**: N1 idle, N2 cold-start → steady (30–60 menit), N3 workload steady di level L0..L3 (waster legit, tiap level 5 menit), N4 perubahan workload bertahap, N5 satu bit-flip terisolasi jarang (SEU, ≤ 1 per ≥ 10 menit). Minimal 3 sesi di hari/suhu ruang berbeda; sesi dipisah **per sesi** (bukan per tick) menjadi train / val / test.

**Tamper (label 1), semua dirancang tetap di dalam window datasheet B1**:

| Kelas | Emulasi |
| ----- | ----- |
| A1 | beban berdenyut (pulsed waster, rata-rata kecil): `V_noise↑`, `F_noise↑` tanpa pergeseran mean |
| A2 | clock skew kecil 0,2–1% saat V/T tidak bergerak (pergeseran RO yang tidak dijelaskan V/T) |
| A3 | burst bit-flip 2–5/detik |
| A4 | **kombinasi lemah**: pulsed kecil \+ skew 0,2% \+ flip jarang (tiap komponen sendirian jinak) |
| A5 | **HOLD-OUT**, tidak dipakai training: pola lain (mis. glitch train 1 ms tiap 5 s, duty/frekuensi berbeda) |

Tiap kelas ≥ 20 trial, intensitas acak, mulai acak, durasi 10–60 detik.

### **7.2 Dataset sintetis (pelengkap)**

Generator `datagen.py` hanya untuk sanity check pipeline dan augmentasi, **bukan** untuk klaim akhir.

### **7.3 Baseline dan protokol adil**

| Kode | Detektor |
| ----- | ----- |
| B1 | window datasheet (§5), OR-fused |
| B2 | threshold per-sensor **dituning di validation set**, OR-fused, disamakan false alarm-nya dengan SNN |
| B3 | logistic regression pada fitur yang sama (window features), threshold disamakan |
| SNN-1N | Stage A |

Protokol: dengan `HARD_EN = 0`, setiap detektor dituning ke ≤ 1 alarm per 30 menit data normal di validation, lalu diukur di sesi test terpisah. Laporkan per kelas: detection rate, waktu deteksi (distribusi), false alarm. Untuk false alarm 0 pada durasi T, laporkan batas atas 95% ≈ `3/T` (rule of three), jangan klaim "nol".

## **8\. Struktur Repo & Modul**

7. snn-tamper/  
8.   AGENTS.md  FSD.md  params.yaml  
9.   python/  gen\_params.py logger\_rx.py datagen.py features\_ref.py golden\_snn.py  
10.            baselines.py train.py export\_weights.py eval.py plot\_logs.py  
11.   data/    raw/  sessions/   (CSV log, tidak di-commit bila besar)  
12.   golden\_vectors/  
13.   rtl/     snn\_params\_pkg.vhd snn\_weights\_pkg.vhd  
14.            xadc\_if.vhd ro\_sensor.vhd bram\_monitor.vhd feature\_unit.vhd  
15.            learn\_unit.vhd spike\_encoder.vhd lif\_neuron.vhd alarm\_fsm.vhd  
16.            response\_unit.vhd protected\_core.vhd tamper\_emulator.vhd  
17.            uart\_rx.vhd uart\_tx.vhd cmd\_parser.vhd logger.vhd telemetry.vhd snn\_top.vhd  
18.   tb/      (satu TB self-checking per modul \+ tb\_top)  
19.   constr/  nexys\_a7\_100t.xdc   \# turunan Master XDC  
20.   scripts/ build.tcl sim.tcl program.tcl  
21.   reports/  
    

    ## **9\. Rencana Testing**

| Level | Apa | Lulus bila |
| ----- | ----- | ----- |
| L0 | Logger di board \+ `plot_logs.py` | T/V/F/M terbaca masuk akal; drift suhu terlihat; CRC frame benar |
| L1 | Python float/integer: fitur \+ encoder \+ golden | rate spike normal ≈ 0,5%/tick; tak ada overflow assert |
| L2 | TB unit tiap modul (xsim/GHDL) | 0 mismatch vs vektor referensi modul |
| L3 | `tb_top` membaca `stim_*` (kode sensor mentah per tick), bandingkan `exp_*` per tick | **bit-exact**, 0 mismatch |
| L4 | Post-synthesis/implementation | WNS ≥ 0 @ 100 MHz; utilisasi diverifikasi dari report (ekspektasi sangat kecil) |
| L5 | **HIL**: board RUN \+ emulator, skenario A1–A5 dan N1–N5 | metrik §7.3 tercapai/dilaporkan |
| L6 | Fisik opsional (hair dryer jauh/dingin ringan, jaga Tj aman) | observasi, bukan klaim utama |

Format vektor: `stim` \= per tick `T_code,V_code,F,M`; `exp` \= per tick `spikes_in(hex4), v(dec), s_out, count, state`. RO dan BRAM scan di L3 disuap dari nilai F/M di `stim` (sensor di-bypass lewat interface `sensor_valid`), karena RO dan XADC tidak ada di simulasi.

## **10\. Cara AI Agent (Antigravity) Mengerjakan**

**Aturan `AGENTS.md`**: VHDL-2008, `numeric_std`, satu clock 100 MHz, reset sinkron, tanpa latch, tanpa `wait for` di kode sintesis; lebar signed eksplisit, saturasi sesuai FSD; **dilarang mengarang** pin (Master XDC), konfigurasi XADC (wizard/UG480), atau angka parameter (`params.yaml` / log); golden model dan vektor tidak boleh diubah agar RTL lulus (kalau yakin golden salah, **berhenti dan tanya**); satu modul \= satu TB self-checking \+ satu perintah run.

Simulasi/build lewat CLI: `xvhdl --2008` / `xelab` / `xsim`, `vivado -mode batch -source scripts/{sim,build}.tcl`. GHDL `--std=08` untuk loop cepat (XADC/RO dibungkus dan di-stub).

| \# | Task | Done when |
| ----- | ----- | ----- |
| T0 | scaffold repo \+ `params.yaml` \+ `gen_params.py` | paket VHDL dan `params.py` konsisten |
| T1 | `xadc_if` (wizard), `ro_sensor`, `bram_monitor`, `logger`, XDC | bitstream **logger** jadi; WNS ≥ 0; frame valid di PC |
| T2 | `logger_rx.py`, `plot_logs.py` | CSV \+ plot suhu/V/RO/M dari board |
| T3 | `tamper_emulator` \+ `cmd_parser` | tiap emulator terkendali via UART; `emu_active` tercatat; pengaman T\_SAFE teruji |
| **Gate Han** | **kampanye pengumpulan data (§7.1)** | sesi normal \+ tamper terekam |
| T4 | `features_ref.py`, `golden_snn.py`, `baselines.py` | rate spike normal sesuai; B1/B2/B3 jalan di log asli |
| T5 | `train.py`, `export_weights.py`, `eval.py` | metrik golden integer sesuai §7.3; hash cocok |
| **Gate Han** | review hasil T5 (H1 didukung / tidak) sebelum RTL SNN dikunci | keputusan lanjut / Stage B |
| T6 | `feature_unit`, `learn_unit`, `spike_encoder`, `lif_neuron`, `alarm_fsm` \+ TB | L2 bit-exact |
| T7 | `response_unit`, `protected_core`, `snn_top`, `tb_top` | L3 bit-exact |
| T8 | build penuh \+ uji HIL | L4 \+ L5 |
| T9 | `reports/eval.md` | tabel per kelas SNN vs B1/B2/B3 \+ jujur soal batasan |

**Gate manual**: Han yang menjalankan kampanye data, memprogram board, dan menjaga keamanan termal (waster tidak boleh dibiarkan tanpa pengaman).

## **11\. Kebutuhan**

**Hardware**: Nexys A7-100T \+ USB. Tidak perlu AFE. Opsional: termometer IR untuk cross-check suhu. **Software**: Vivado ML Standard (mendukung XC7A100T) \+ board file/Master XDC Digilent; Python 3.10+ (numpy, PyTorch, matplotlib, pyyaml, pyserial, scikit-learn untuk B3); GHDL opsional.

## **12\. Risiko & Batasan**

* Sensor internal yang berkorelasi (RO, suhu, VCCINT berbagi die) berarti fusi kuat sebagian karena fisika yang sama; ini sah, tapi harus dijelaskan di laporan.  
* Emulator mengubah beban di device yang sama dengan monitor; tamper nyata dari luar bisa berbeda karakternya. Hasil PoC tidak otomatis berlaku ke tamper fisik.  
* Pembuktian hanya untuk kelas tamper yang diuji. A5 hold-out mengukur generalisasi; jangan asumsikan.  
* Resolusi dan noise sensor membatasi apa yang terlihat.  
* Kuantisasi/saturasi dapat menggeser perilaku dibanding forward float; selalu ukur ulang di golden integer.  
* XADC dan RO dipengaruhi suhu board dan pencahayaan ruang; catat kondisi tiap sesi.

  ## **13\. Keputusan Terbuka**

1. Apakah VCCBRAM/VCCAUX ditambah sebagai kanal ke-3/4 (tick lebih panjang)?  
2. Target false alarm (default: ≤ 1 alarm per 30 menit normal di validasi) dan latency maksimum yang dapat diterima.  
3. Apakah Stage B (hidden layer) diizinkan bila Stage A tidak cukup, atau PoC dibatasi ketat 1 neuron.  
4. Apakah uji fisik (L6) masuk scope laporan.  
22. 

