--------------------------------------------------------------------------------
-- File: snn_params_pkg.vhd
-- Auto-generated from params.yaml by gen_params.py
-- DO NOT EDIT DIRECTLY
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package snn_params_pkg is

    -- System Clock and Baud Rates
    constant CLK_FREQ_HZ            : integer := 100000000;
    constant BAUD_RATE_LOGGER       : integer := 921600;
    constant BAUD_RATE_TELEMETRY    : integer := 115200;

    -- Sensor Dimensions and Setup
    constant RO_WINDOW_BITS         : integer := 15;
    constant BRAM_WORDS             : integer := 1024;
    constant BRAM_WIDTH             : integer := 32;
    constant BRAM_HASH_MULT         : unsigned(31 downto 0) := x"9E3779B1";
    constant BRAM_HASH_XOR          : unsigned(31 downto 0) := x"C001CAFE";

    -- Features EMA Shifts (Q.16)
    constant EMA_K_T1_SHIFT         : integer := 8;
    constant EMA_K_T2_SHIFT         : integer := 11;
    constant EMA_K_E_SHIFT          : integer := 6;
    constant Q_FRAC_BITS            : integer := 16;

    -- Enrollment Constants
    constant N_WARM_TICKS           : integer := 4096;
    constant N_ACC_TICKS            : integer := 16384;
    constant S_MIN_T               : integer := 1;
    constant S_MIN_V               : integer := 1;
    constant S_MIN_F               : integer := 4;
    constant S_MIN_E               : integer := 1;

    -- Spike Encoder
    constant N_SPIKE_CHANNELS      : integer := 14;

    -- LIF Neuron
    constant N_INPUTS              : integer := 14;
    constant LEAK_L               : integer := 7;
    constant VTH_DEFAULT           : integer := 200;

    -- Alarm FSM
    constant W_WINDOW              : integer := 1024;
    constant N_SUS_DEFAULT         : integer := 25;
    constant N_ALM_DEFAULT         : integer := 60;
    constant HYST_DEFAULT          : integer := 8;
    constant BLACK_BOX_DEPTH       : integer := 512;

    -- Backstop Thresholds
    constant VCCINT_MIN_CODE        : integer := 1297;
    constant VCCINT_MAX_CODE        : integer := 1433;
    constant M_HARD_WORDS          : integer := 8;

    -- Emulator Parameters
    constant WASTER_LEVELS         : integer := 16;

end package snn_params_pkg;
