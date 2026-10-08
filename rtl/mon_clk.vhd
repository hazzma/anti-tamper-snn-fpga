--------------------------------------------------------------------------------
-- File: mon_clk.vhd
-- Description: U3 Clock Monitor on clk100 (FSD v2 §6-U3)
-- Evaluates clk_core frequency, stalls, and unlocks over window WND_US (100 us)
-- Standard: VHDL-2008, IEEE numeric_std
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.pkg_fsd.all;

entity mon_clk is
    port (
        clk100         : in  std_logic;
        rstn           : in  std_logic;
        
        -- Target Clock and MMCM Status
        clk_core_async : in  std_logic;
        mmcm_locked    : in  std_logic;
        
        -- Configuration Registers (from cmd_parser / CFG)
        wnd_us         : in  unsigned(15 downto 0); -- default 100 us
        clk_hi_pct     : in  unsigned(7 downto 0);  -- default 5%
        clk_lo_pct     : in  unsigned(7 downto 0);  -- default 5%
        clk_soft_th    : in  unsigned(7 downto 0);  -- default 1%
        stall_cyc_th   : in  unsigned(15 downto 0); -- default 200 (2 us)
        
        -- Hard Flags (Layer 1 - 1 cycle pulse)
        clk_gross_h    : out std_logic;
        clk_fast_h     : out std_logic;
        clk_slow_h     : out std_logic;
        clk_stop_h     : out std_logic;
        mmcm_unlock_h  : out std_logic;
        
        -- Soft Spike Output (Layer 3 - 1 pulse per window with intensity q)
        clk_soft_spike : out std_logic;
        clk_soft_q     : out unsigned(3 downto 0);
        
        -- Live telemetry readout
        live_edge_count: out unsigned(15 downto 0)
    );
end entity mon_clk;

architecture rtl of mon_clk is

    -- 2-FF Synchronizer for clk_core_async
    signal clk_sync1     : std_logic := '0';
    signal clk_sync2     : std_logic := '0';
    signal clk_sync3     : std_logic := '0';
    attribute ASYNC_REG  : string;
    attribute ASYNC_REG of clk_sync1 : signal is "TRUE";
    attribute ASYNC_REG of clk_sync2 : signal is "TRUE";

    -- Window generator counter (counts clk100 cycles up to wnd_us * 100)
    signal wnd_timer     : unsigned(15 downto 0) := (others => '0');
    signal wnd_limit     : unsigned(15 downto 0) := to_unsigned(10000, 16);
    signal edge_counter  : unsigned(15 downto 0) := (others => '0');
    signal stall_counter : unsigned(15 downto 0) := (others => '0');
    signal locked_d1     : std_logic := '1';

    -- Pipelined window evaluation signals
    signal eval_pipe1     : std_logic := '0';
    signal eval_pipe2     : std_logic := '0';
    signal count_sample   : unsigned(15 downto 0) := (others => '0');
    signal is_gross_pipe1 : std_logic := '0';
    signal is_fast_pipe1  : std_logic := '0';
    signal is_slow_pipe1  : std_logic := '0';
    signal diff_mult_pipe1: unsigned(21 downto 0) := (others => '0');

begin

    wnd_limit <= resize(wnd_us * 100, 16);

    ----------------------------------------------------------------------------
    -- Clock Edge Synchronizer
    ----------------------------------------------------------------------------
    p_sync : process(clk100)
    begin
        if rising_edge(clk100) then
            if rstn = '0' then
                clk_sync1 <= '0';
                clk_sync2 <= '0';
                clk_sync3 <= '0';
            else
                clk_sync1 <= clk_core_async;
                clk_sync2 <= clk_sync1;
                clk_sync3 <= clk_sync2;
            end if;
        end if;
    end process p_sync;

    ----------------------------------------------------------------------------
    -- Frequency Evaluation & Stall Watchdog Process (Pipelined for Timing Closure)
    ----------------------------------------------------------------------------
    p_eval : process(clk100)
        variable core_rising   : boolean;
        variable count_val     : integer;
        variable diff_val      : integer;
        variable delta_pct     : integer;
        variable q_calc        : integer;
        variable upper_hard_th : integer;
        variable lower_hard_th : integer;
    begin
        if rising_edge(clk100) then
            if rstn = '0' then
                wnd_timer       <= (others => '0');
                edge_counter    <= (others => '0');
                stall_counter   <= (others => '0');
                locked_d1       <= '1';
                clk_gross_h     <= '0';
                clk_fast_h      <= '0';
                clk_slow_h      <= '0';
                clk_stop_h      <= '0';
                mmcm_unlock_h   <= '0';
                clk_soft_spike  <= '0';
                clk_soft_q      <= (others => '0');
                live_edge_count <= (others => '0');
                eval_pipe1      <= '0';
                eval_pipe2      <= '0';
                count_sample    <= (others => '0');
                is_gross_pipe1  <= '0';
                is_fast_pipe1   <= '0';
                is_slow_pipe1   <= '0';
                diff_mult_pipe1 <= (others => '0');
            else
                -- Defaults for 1-cycle pulses
                clk_gross_h    <= '0';
                clk_fast_h     <= '0';
                clk_slow_h     <= '0';
                clk_stop_h     <= '0';
                mmcm_unlock_h  <= '0';
                clk_soft_spike <= '0';
                clk_soft_q     <= (others => '0');

                locked_d1 <= mmcm_locked;

                -- Detect MMCM Unlock falling edge
                if locked_d1 = '1' and mmcm_locked = '0' then
                    mmcm_unlock_h <= '1';
                end if;

                -- Core rising edge detection in clk100 domain
                core_rising := (clk_sync2 = '1' and clk_sync3 = '0');

                if core_rising then
                    edge_counter  <= edge_counter + 1;
                    stall_counter <= (others => '0');
                else
                    stall_counter <= stall_counter + 1;
                    if stall_counter >= stall_cyc_th then
                        clk_stop_h <= '1';
                    end if;
                end if;

                -- Window Timer & Sampling
                wnd_timer  <= wnd_timer + 1;
                eval_pipe1 <= '0';
                if wnd_timer >= wnd_limit then
                    wnd_timer       <= (others => '0');
                    count_sample    <= edge_counter;
                    live_edge_count <= edge_counter;
                    edge_counter    <= (others => '0');
                    eval_pipe1      <= '1';
                end if;

                -- Pipeline Stage 1: Threshold checks & diff scaling (replaces /100 and /2500)
                eval_pipe2 <= eval_pipe1;
                if eval_pipe1 = '1' then
                    count_val     := to_integer(count_sample);
                    -- 2500 * pct / 100 = 25 * pct (no division needed)
                    upper_hard_th := 2500 + (25 * to_integer(clk_hi_pct));
                    lower_hard_th := 2500 - (25 * to_integer(clk_lo_pct));

                    if count_val > 5000 then
                        is_gross_pipe1 <= '1';
                    else
                        is_gross_pipe1 <= '0';
                    end if;

                    if count_val > upper_hard_th then
                        is_fast_pipe1 <= '1';
                    else
                        is_fast_pipe1 <= '0';
                    end if;

                    if count_val < lower_hard_th then
                        is_slow_pipe1 <= '1';
                    else
                        is_slow_pipe1 <= '0';
                    end if;

                    if count_val > 2500 then
                        diff_val := count_val - 2500;
                    else
                        diff_val := 2500 - count_val;
                    end if;
                    -- Multiply by 41: diff * 41 / 1024 is bit-exact equivalent of diff / 25
                    diff_mult_pipe1 <= to_unsigned(diff_val * 41, 22);
                end if;

                -- Pipeline Stage 2: Register output flags
                if eval_pipe2 = '1' then
                    clk_gross_h <= is_gross_pipe1;
                    clk_fast_h  <= is_fast_pipe1;
                    clk_slow_h  <= is_slow_pipe1;

                    -- Shift right by 10 (bits 21 downto 10) gives floor(diff / 25)
                    delta_pct := to_integer(diff_mult_pipe1(21 downto 10));
                    if delta_pct >= to_integer(clk_soft_th) then
                        clk_soft_spike <= '1';
                        -- Q-mapping contract (§7.2): q = clamp(1 + floor(deviasi%), 1, 15)
                        q_calc := 1 + delta_pct;
                        if q_calc > 15 then
                            q_calc := 15;
                        elsif q_calc < 1 then
                            q_calc := 1;
                        end if;
                        clk_soft_q <= to_unsigned(q_calc, 4);
                    end if;
                end if;

            end if;
        end if;
    end process p_eval;

end architecture rtl;
