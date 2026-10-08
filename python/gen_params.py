#!/usr/bin/env python3
import os, yaml

def main():
    base = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ypath = os.path.join(base, 'params.yaml')
    with open(ypath, 'r') as f:
        cfg = yaml.safe_load(f)
    vhdl_path = os.path.join(base, 'rtl', 'snn_params_pkg.vhd')
    sys = cfg['system']
    sens = cfg['sensors']
    feat = cfg['features']
    enr = cfg['enrollment']
    enc = cfg['encoder']
    nrn = cfg['neuron']
    alm = cfg['alarm']
    bks = cfg['backstop']
    emu = cfg['emulator']
    m_hex = format(sens['bram']['hash_multiplier'], '08X')
    x_hex = format(sens['bram']['hash_xor_const'], '08X')
    lines = [
        '--------------------------------------------------------------------------------',
        '-- File: snn_params_pkg.vhd',
        '-- Auto-generated from params.yaml by gen_params.py',
        '-- DO NOT EDIT DIRECTLY',
        '--------------------------------------------------------------------------------',
        'library ieee;',
        'use ieee.std_logic_1164.all;',
        'use ieee.numeric_std.all;',
        '',
        'package snn_params_pkg is',
        '',
        '    -- System Clock and Baud Rates',
        f"    constant CLK_FREQ_HZ            : integer := {sys['clk_freq_hz']};",
        f"    constant BAUD_RATE_LOGGER       : integer := {sys['baud_rate_logger']};",
        f"    constant BAUD_RATE_TELEMETRY    : integer := {sys['baud_rate_telemetry']};",
        '',
        '    -- Sensor Dimensions and Setup',
        f"    constant RO_WINDOW_BITS         : integer := {sens['ro']['window_bits']};",
        f"    constant BRAM_WORDS             : integer := {sens['bram']['words']};",
        f"    constant BRAM_WIDTH             : integer := {sens['bram']['width']};",
        f'    constant BRAM_HASH_MULT         : unsigned(31 downto 0) := x"{m_hex}";',
        f'    constant BRAM_HASH_XOR          : unsigned(31 downto 0) := x"{x_hex}";',
        '',
        '    -- Features EMA Shifts (Q.16)',
        f"    constant EMA_K_T1_SHIFT         : integer := {feat['ema_k_t1_shift']};",
        f"    constant EMA_K_T2_SHIFT         : integer := {feat['ema_k_t2_shift']};",
        f"    constant EMA_K_E_SHIFT          : integer := {feat['ema_k_e_shift']};",
        f"    constant Q_FRAC_BITS            : integer := {feat['q_frac_bits']};",
        '',
        '    -- Enrollment Constants',
        f"    constant N_WARM_TICKS           : integer := {enr['n_warm']};",
        f"    constant N_ACC_TICKS            : integer := {enr['n_acc']};",
        f"    constant S_MIN_T               : integer := {enr['s_min_t']};",
        f"    constant S_MIN_V               : integer := {enr['s_min_v']};",
        f"    constant S_MIN_F               : integer := {enr['s_min_f']};",
        f"    constant S_MIN_E               : integer := {enr['s_min_e']};",
        '',
        '    -- Spike Encoder',
        f"    constant N_SPIKE_CHANNELS      : integer := {enc['n_channels']};",
        '',
        '    -- LIF Neuron',
        f"    constant N_INPUTS              : integer := {nrn['n_inputs']};",
        f"    constant LEAK_L               : integer := {nrn['leak_l']};",
        f"    constant VTH_DEFAULT           : integer := {nrn['vth']};",
        '',
        '    -- Alarm FSM',
        f"    constant W_WINDOW              : integer := {alm['w_window']};",
        f"    constant N_SUS_DEFAULT         : integer := {alm['n_sus']};",
        f"    constant N_ALM_DEFAULT         : integer := {alm['n_alm']};",
        f"    constant HYST_DEFAULT          : integer := {alm['hyst']};",
        f"    constant BLACK_BOX_DEPTH       : integer := {alm['black_box_depth']};",
        '',
        '    -- Backstop Thresholds',
        f"    constant VCCINT_MIN_CODE        : integer := {bks['vccint_min_code']};",
        f"    constant VCCINT_MAX_CODE        : integer := {bks['vccint_max_code']};",
        f"    constant M_HARD_WORDS          : integer := {bks['m_hard_words']};",
        '',
        '    -- Emulator Parameters',
        f"    constant WASTER_LEVELS         : integer := {emu['waster_duty_levels']};",
        '',
        'end package snn_params_pkg;',
        ''
    ]
    with open(vhdl_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))
    print(f'VHDL package written: {vhdl_path}')
    py_path = os.path.join(base, 'python', 'params.py')
    with open(py_path, 'w', encoding='utf-8') as f:
        f.write(f'# Auto-generated from params.yaml\nPARAMS = {repr(cfg)}\n')
    print(f'Python config written: {py_path}')

if __name__ == '__main__':
    main()
