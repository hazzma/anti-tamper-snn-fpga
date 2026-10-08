--------------------------------------------------------------------------------
-- File: pkg_fsd.vhd
-- Description: Central Parameters and Types for FPGA Anti-Tamper Guard (FSD v2)
-- Standard: VHDL-2008, IEEE numeric_std
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package pkg_fsd is

    ----------------------------------------------------------------------------
    -- System Clocks & UART Constants
    ----------------------------------------------------------------------------
    constant SYS_CLK_FREQ_HZ : natural := 100_000_000; -- 100 MHz oscillator
    constant BAUD_RATE       : natural := 115_200;     -- ASCII line UART
    constant CLK_CORE_NOM_HZ : natural := 25_000_000;  -- 25 MHz nominal core

    ----------------------------------------------------------------------------
    -- SNN Architecture Dimensions
    ----------------------------------------------------------------------------
    constant N_NEUR : natural := 4;  -- N0: Transient, N1: Repeat-Probe, N2: Combined, N3: Spare
    constant N_CH   : natural := 12; -- 12 synaptic input channels
    constant Q_MAX  : natural := 15; -- Maximum spike intensity level

    ----------------------------------------------------------------------------
    -- Channel Index Map (FSD v2 §7.1)
    ----------------------------------------------------------------------------
    constant CH_CLK_FAST_H    : natural := 0;  -- Hard: clk > +5%
    constant CH_CLK_SLOW_H    : natural := 1;  -- Hard: clk < -5%
    constant CH_CLK_STOP_H    : natural := 2;  -- Hard: clk stalled 2 us
    constant CH_MMCM_UNLOCK_H : natural := 3;  -- Hard: MMCM lost lock
    constant CH_V_UNDER_H     : natural := 4;  -- Hard: VCCINT < 0.93V
    constant CH_V_OVER_H      : natural := 5;  -- Hard: VCCINT > 1.07V
    constant CH_KEY_CORRUPT_H : natural := 6;  -- Hard: Victim digest mismatch
    constant CH_JTAG_H        : natural := 7;  -- Hard: BSCANE2 debug access
    constant CH_CLK_SOFT      : natural := 8;  -- Soft: clk dev > 1% (q=1..15)
    constant CH_V_SOFT        : natural := 9;  -- Soft: VCCINT dip > 9mV (q=1..15)
    constant CH_TEMP_SOFT     : natural := 10; -- Soft: Thermal anomaly / Temperature spurt
    constant CH_PROBE_SOFT    : natural := 11; -- Soft: Capacitance microprobing sensor
    constant CH_SPARE_10      : natural := 10; -- Spare synth channel alias
    constant CH_SPARE_11      : natural := 11; -- Spare synth channel alias

    ----------------------------------------------------------------------------
    -- Common Types for SNN Datapath
    ----------------------------------------------------------------------------
    type q_array_t is array(0 to N_CH-1) of unsigned(3 downto 0);
    type weight_row_t is array(0 to N_CH-1) of signed(7 downto 0);
    type weight_matrix_t is array(0 to N_NEUR-1) of weight_row_t;
    type membrane_array_t is array(0 to N_NEUR-1) of signed(15 downto 0);
    type theta_array_t is array(0 to N_NEUR-1) of signed(15 downto 0);
    type m_array_t is array(0 to N_NEUR-1) of integer range 0 to 15;

    ----------------------------------------------------------------------------
    -- Sensor Multiplexer Modes (FSD v2 §6-U11)
    ----------------------------------------------------------------------------
    constant SENSOR_MODE_A : std_logic_vector(1 downto 0) := "00"; -- Full Synth
    constant SENSOR_MODE_B : std_logic_vector(1 downto 0) := "01"; -- Full Real
    constant SENSOR_MODE_C : std_logic_vector(1 downto 0) := "10"; -- Hybrid (Default)

    ----------------------------------------------------------------------------
    -- Default Configuration Constants
    ----------------------------------------------------------------------------
    constant WND_US_DEFAULT      : natural := 100;
    constant CLK_HI_PCT_DEFAULT  : natural := 5;
    constant CLK_LO_PCT_DEFAULT  : natural := 5;
    constant CLK_SOFT_TH_DEFAULT : natural := 1;
    constant STALL_CYC_DEFAULT   : natural := 200; -- 2 us @ 100 MHz
    constant V_UNDER_DEFAULT     : unsigned(11 downto 0) := to_unsigned(1270, 12); -- 0.93V
    constant V_OVER_DEFAULT      : unsigned(11 downto 0) := to_unsigned(1461, 12); -- 1.07V
    constant V_SOFT_TH_DEFAULT   : natural := 12;  -- ~9 mV
    constant ESC_TH_DEFAULT      : natural := 2;   -- Robustness default (2 alerts -> zeroize)
    constant ESC_TH_DEMO         : natural := 1;   -- Instant action for demo

    ----------------------------------------------------------------------------
    -- Telemetry Event Codes (FSD v2 §6-U14)
    ----------------------------------------------------------------------------
    constant EV_CODE_BOOT       : std_logic_vector(7 downto 0) := x"01";
    constant EV_CODE_GLITCH     : std_logic_vector(7 downto 0) := x"10";
    constant EV_CODE_SPIKE      : std_logic_vector(7 downto 0) := x"20";
    constant EV_CODE_FIRE       : std_logic_vector(7 downto 0) := x"21";
    constant EV_CODE_ALERT      : std_logic_vector(7 downto 0) := x"30";
    constant EV_CODE_ZEROIZE    : std_logic_vector(7 downto 0) := x"40";
    constant EV_CODE_UNLOCK     : std_logic_vector(7 downto 0) := x"50";
    constant EV_CODE_CORRUPT    : std_logic_vector(7 downto 0) := x"60";

    subtype signed16_t is signed(15 downto 0);

    ----------------------------------------------------------------------------
    -- Saturating Add Function for 16-bit Signed Membrane Potential
    ----------------------------------------------------------------------------
    function sat_add16 (
        a : signed16_t;
        b : signed16_t
    ) return signed16_t;

end package pkg_fsd;

package body pkg_fsd is

    function sat_add16 (
        a : signed16_t;
        b : signed16_t
    ) return signed16_t is
        variable sum32 : signed(16 downto 0);
    begin
        sum32 := resize(a, 17) + resize(b, 17);
        if sum32 > 32767 then
            return to_signed(32767, 16);
        elsif sum32 < -32768 then
            return to_signed(-32768, 16);
        else
            return resize(sum32, 16);
        end if;
    end function sat_add16;

end package body pkg_fsd;

