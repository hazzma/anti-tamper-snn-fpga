--------------------------------------------------------------------------------
-- File: clk_gen.vhd
-- Description: U1 Clock Generator with MMCME2_ADV Primitive & DRP (FSD v2 §5.1 & §6-U1)
-- Inputs: 100 MHz board oscillator (pin E3)
-- Outputs: clk100 (100 MHz stable BUFG), clk_core (25 MHz nominal DRP BUFG), locked
-- Standard: VHDL-2008, IEEE numeric_std
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

entity clk_gen is
    port (
        clk100mhz_in   : in  std_logic; -- Pin E3 oscillator
        reset_in       : in  std_logic; -- Active-high reset
        
        -- System Clocks Output
        clk100         : out std_logic; -- 100 MHz stable domain
        clk_core       : out std_logic; -- 25 MHz nominal glitchable domain
        locked         : out std_logic;
        
        -- DRP Interface from mmcm_drp (U7)
        drp_daddr      : in  std_logic_vector(6 downto 0);
        drp_den        : in  std_logic;
        drp_dwe        : in  std_logic;
        drp_di         : in  std_logic_vector(15 downto 0);
        drp_do         : out std_logic_vector(15 downto 0);
        drp_drdy       : out std_logic
    );
end entity clk_gen;

architecture rtl of clk_gen is

    signal clkfb_out     : std_logic;
    signal clkfb_in      : std_logic;
    signal clk100_unbuf  : std_logic;
    signal clkcore_unbuf : std_logic;
    signal locked_int    : std_logic;

begin

    locked <= locked_int;

    ----------------------------------------------------------------------------
    -- MMCM Primitive Instantiation (VCO = 100 MHz * 10 / 1 = 1000 MHz)
    ----------------------------------------------------------------------------
    mmcm_inst : MMCME2_ADV
        generic map (
            BANDWIDTH            => "OPTIMIZED",
            CLKIN1_PERIOD        => 10.000, -- 100 MHz input
            CLKFBOUT_MULT_F      => 10.000, -- VCO = 1000 MHz
            DIVCLK_DIVIDE        => 1,
            
            -- CLKOUT0: clk_core, DIV=40 => 25 MHz nominal (DRP reconfigurable)
            CLKOUT0_DIVIDE_F     => 40.000,
            CLKOUT0_DUTY_CYCLE   => 0.500,
            CLKOUT0_PHASE        => 0.000,
            
            -- CLKOUT1: clk100, DIV=10 => 100 MHz stable
            CLKOUT1_DIVIDE       => 10,
            CLKOUT1_DUTY_CYCLE   => 0.500,
            CLKOUT1_PHASE        => 0.000,
            
            STARTUP_WAIT         => FALSE
        )
        port map (
            -- Clock Inputs & Feedback
            CLKIN1               => clk100mhz_in,
            CLKIN2               => '0',
            CLKINSEL             => '1',
            CLKFBIN              => clkfb_in,
            CLKFBOUT             => clkfb_out,
            CLKFBOUTB            => open,
            
            -- Clock Outputs
            CLKOUT0              => clkcore_unbuf,
            CLKOUT0B             => open,
            CLKOUT1              => clk100_unbuf,
            CLKOUT1B             => open,
            CLKOUT2              => open,
            CLKOUT2B             => open,
            CLKOUT3              => open,
            CLKOUT3B             => open,
            CLKOUT4              => open,
            CLKOUT5              => open,
            CLKOUT6              => open,
            
            -- Dynamic Reconfiguration Port (DRP)
            DCLK                 => clk100mhz_in,
            DADDR                => drp_daddr,
            DEN                  => drp_den,
            DWE                  => drp_dwe,
            DI                   => drp_di,
            DO                   => drp_do,
            DRDY                 => drp_drdy,
            
            -- Status & Control
            LOCKED               => locked_int,
            CLKFBSTOPPED         => open,
            CLKINSTOPPED         => open,
            PSDONE               => open,
            PSCLK                => '0',
            PSEN                 => '0',
            PSINCDEC             => '0',
            PWRDWN               => '0',
            RST                  => reset_in
        );

    ----------------------------------------------------------------------------
    -- Global Clock Buffers (BUFG)
    ----------------------------------------------------------------------------
    bufg_fb : BUFG
        port map (
            I => clkfb_out,
            O => clkfb_in
        );

    bufg_100 : BUFG
        port map (
            I => clk100_unbuf,
            O => clk100
        );

    bufg_core : BUFG
        port map (
            I => clkcore_unbuf,
            O => clk_core
        );

end architecture rtl;
