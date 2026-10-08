--------------------------------------------------------------------------------
-- File: mon_volt.vhd
-- Description: U4 Voltage Monitor on clk100 via 7-Series XADC DRP (FSD v2 §6-U4)
-- Samples VCCINT, calculates IIR baseline, detects under/over volt & soft dips
-- Standard: VHDL-2008, IEEE numeric_std
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

use work.pkg_fsd.all;

entity mon_volt is
    port (
        clk100         : in  std_logic;
        rstn           : in  std_logic;
        
        -- Configuration Registers (from cmd_parser / CFG)
        v_under_th     : in  unsigned(11 downto 0); -- default 1270 (0.93V)
        v_over_th      : in  unsigned(11 downto 0); -- default 1461 (1.07V)
        v_soft_th      : in  unsigned(7 downto 0);  -- default 12 code (~9 mV)
        
        -- Hard Flags (Layer 1)
        v_under_h      : out std_logic;
        v_over_h       : out std_logic;
        
        -- Soft Spike Output (Layer 3)
        v_soft_spike   : out std_logic;
        v_soft_q       : out unsigned(3 downto 0);
        
        -- Live telemetry
        vccint_raw_code: out unsigned(11 downto 0)
    );
end entity mon_volt;

architecture rtl of mon_volt is

    -- DRP Signals for XADC
    signal daddr_i     : std_logic_vector(6 downto 0) := "0000001"; -- 0x01: VCCINT
    signal den_i       : std_logic := '0';
    signal dwe_i       : std_logic := '0';
    signal di_i        : std_logic_vector(15 downto 0) := (others => '0');
    signal do_i        : std_logic_vector(15 downto 0);
    signal drdy_i      : std_logic;
    signal eoc_i       : std_logic;
    signal eos_i       : std_logic;
    signal channel_i   : std_logic_vector(4 downto 0);

    -- DRP state machine
    type drp_state_t is (DRP_WAIT_EOC, DRP_READ_REQ, DRP_WAIT_DRDY);
    signal drp_state   : drp_state_t := DRP_WAIT_EOC;

    -- IIR Baseline and Soft Filter Signals (16-bit fixed point Q12.4)
    signal vccint_code : unsigned(11 downto 0) := to_unsigned(1365, 12);
    signal base_reg    : signed(16 downto 0)   := to_signed(1365 * 16, 17); -- Q12.4
    
    -- Evaluation tick generator: ~100 us tick (10,000 cycles of clk100)
    signal eval_timer  : unsigned(15 downto 0) := (others => '0');
    signal new_sample  : boolean := false;

begin

    vccint_raw_code <= vccint_code;

    ----------------------------------------------------------------------------
    -- 7-Series XADC Primitive Instantiation
    ----------------------------------------------------------------------------
    xadc_inst : XADC
        generic map (
            INIT_40 => x"0000", -- Config 0: Continuous sequence mode, average 16
            INIT_41 => x"21AF", -- Config 1: Seq mode, disable alarms
            INIT_42 => x"0400", -- Config 2: DCLK divider = 4 (25 MHz DCLK)
            INIT_48 => x"0800", -- Seq ch: VCCINT
            INIT_49 => x"0000",
            INIT_4A => x"0000",
            INIT_4B => x"0000",
            INIT_4C => x"0000",
            INIT_4D => x"0000",
            INIT_4E => x"0000",
            INIT_4F => x"0000",
            INIT_50 => x"0000",
            INIT_51 => x"0000",
            INIT_52 => x"0000",
            INIT_53 => x"0000",
            INIT_54 => x"0000",
            INIT_55 => x"0000",
            INIT_56 => x"0000",
            INIT_57 => x"0000",
            INIT_58 => x"0000",
            SIM_DEVICE => "7SERIES"
        )
        port map (
            DCLK         => clk100,
            RESET        => not rstn,
            DADDR        => daddr_i,
            DEN          => den_i,
            DWE          => dwe_i,
            DI           => di_i,
            DO           => do_i,
            DRDY         => drdy_i,
            CONVST       => '0',
            CONVSTCLK    => '0',
            VP           => '0',
            VN           => '0',
            VAUXP        => (others => '0'),
            VAUXN        => (others => '0'),
            CHANNEL      => channel_i,
            EOC          => eoc_i,
            EOS          => eos_i,
            BUSY         => open,
            ALM          => open,
            OT           => open,
            JTAGBUSY     => open,
            JTAGLOCKED   => open,
            JTAGMODIFIED => open,
            MUXADDR      => open
        );

    ----------------------------------------------------------------------------
    -- XADC DRP Readout FSM
    ----------------------------------------------------------------------------
    p_drp : process(clk100)
    begin
        if rising_edge(clk100) then
            if rstn = '0' then
                drp_state   <= DRP_WAIT_EOC;
                den_i       <= '0';
                vccint_code <= to_unsigned(1365, 12);
                new_sample  <= false;
            else
                den_i      <= '0';
                new_sample <= false;

                case drp_state is
                    when DRP_WAIT_EOC =>
                        if eoc_i = '1' then
                            den_i     <= '1';
                            drp_state <= DRP_WAIT_DRDY;
                        end if;

                    when DRP_WAIT_DRDY =>
                        if drdy_i = '1' then
                            -- MSB 12-bit of DRP result
                            vccint_code <= unsigned(do_i(15 downto 4));
                            new_sample  <= true;
                            drp_state   <= DRP_WAIT_EOC;
                        end if;

                    when others =>
                        drp_state <= DRP_WAIT_EOC;
                end case;
            end if;
        end if;
    end process p_drp;

    ----------------------------------------------------------------------------
    -- Baseline Tracking & Spike Generation Process
    ----------------------------------------------------------------------------
    p_baseline : process(clk100)
        variable cur_val_q4  : signed(16 downto 0);
        variable base_val    : signed(16 downto 0);
        variable diff_code   : integer;
        variable q_calc      : integer;
    begin
        if rising_edge(clk100) then
            if rstn = '0' then
                eval_timer   <= (others => '0');
                base_reg     <= to_signed(1365 * 16, 17);
                v_under_h    <= '0';
                v_over_h     <= '0';
                v_soft_spike <= '0';
                v_soft_q     <= (others => '0');
            else
                v_under_h    <= '0';
                v_over_h     <= '0';
                v_soft_spike <= '0';
                v_soft_q     <= (others => '0');

                -- Hard Threshold Checking
                if vccint_code < v_under_th then
                    v_under_h <= '1';
                elsif vccint_code > v_over_th then
                    v_over_h <= '1';
                end if;

                -- IIR Baseline Update on new sample: base += (x - base) >> 5
                cur_val_q4 := to_signed(to_integer(vccint_code) * 16, 17);
                if new_sample then
                    base_reg <= base_reg + shift_right(cur_val_q4 - base_reg, 5);
                end if;

                -- 100 us Evaluation Window
                eval_timer <= eval_timer + 1;
                if eval_timer >= 10000 then
                    eval_timer <= (others => '0');
                    base_val   := shift_right(base_reg, 4); -- Extract integer code
                    diff_code  := abs(to_integer(vccint_code) - to_integer(base_val));

                    -- Soft Spike Generation if dip > V_SOFT_TH (default 12 codes ≈ 9 mV)
                    if diff_code >= to_integer(v_soft_th) then
                        v_soft_spike <= '1';
                        -- Q-mapping contract (§7.2): q = clamp(1 + floor(|delta_mV| / 4), 1, 15)
                        -- 1 code ≈ 0.732 mV => 5 codes ≈ 3.66 mV ≈ 4 mV
                        q_calc := 1 + (diff_code / 5);
                        if q_calc > 15 then
                            q_calc := 15;
                        elsif q_calc < 1 then
                            q_calc := 1;
                        end if;
                        v_soft_q <= to_unsigned(q_calc, 4);
                    end if;
                end if;

            end if;
        end if;
    end process p_baseline;

end architecture rtl;
