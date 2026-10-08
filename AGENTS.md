# AGENTS.md - AI Agent Conventions (FSD v2 - Nexys A7-100T)

## 1. RTL Design Standards
- VHDL-2008, IEEE numeric_std only
- Clock Domains:
  - `clk100` (100 MHz oscillator board): Semua monitor, SNN Layer 3, response unit, UART, telemetry.
  - `clk_core` (Output MMCM DRP-reconfigurable, nominal 25 MHz): Hanya `victim_core`.
- CDC Rules:
  - 2-FF synchronizer (`ASYNC_REG = TRUE`) untuk sinyal kontrol.
  - 4-phase handshake untuk transfer bus digest dari `victim_core` ke `mon_victim`.
  - Asynchronous clock group constraint di XDC.
- Synchronous active-high reset internal (disinkronkan per clock domain dari `CPU_RESETN` dan `mmcm_locked`).
- Explicit signed/unsigned widths, zero latches.

## 2. Single Source of Truth
- Parameter utama terpusat di `params.yaml`, `rtl/pkg_fsd.vhd`, dan `rtl/pkg_weights_gen.vhd`.
- Golden model Python di `sw/golden/snn_model.py` adalah tolok ukur bit-exact.

## 3. Vivado & Physical Constraints
- Target FPGA: `xc7a100tcsg324-1` (Digilent Nexys A7-100T).
- Toolchain: Vivado 2025.2 (batch & GUI project `vivado_project/anti_tamper_snn.xpr`).
- Pinout resmi dari Digilent Nexys A7 Master XDC.

## 4. Verification & Testing (5-Layer Testing Architecture)
- L1: Unit Testbenches (per modul, self-checking `PASS/FAIL`).
- L2: Scenario Testbenches (`tb_top`, integrasi SCEN 0–4).
- L3: Hardware Smoke Test (board live interactive CLI `sw/host/attack_cli.py`).
- L4: Hardware Experiments otomatis (`sw/host/run_experiments.py` -> `results/exp_*.csv`).
