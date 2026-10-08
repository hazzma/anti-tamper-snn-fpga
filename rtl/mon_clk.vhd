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
    -- Frequency Evaluation & Stall Watchdog Process
    ----------------------------------------------------------------------------
    p_eval : process(clk100)
        variable core_rising   : boolean;
        variable count_val     : integer;
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

                -- Window Evaluation
                wnd_timer <= wnd_timer + 1;
                if wnd_timer >= wnd_limit then
                    wnd_timer <= (others => '0');
                    count_val := to_integer(edge_counter);
                    live_edge_count <= edge_counter;
                    edge_counter <= (others => '0');

                    -- Nominal expected count in 100 us window is 2500 edges (@ 25 MHz)
                    -- Hard Thresholds:
                    upper_hard_th := 2500 + (2500 * to_integer(clk_hi_pct)) / 100; -- e.g. 2625
                    lower_hard_th := 2500 - (2500 * to_integer(clk_lo_pct)) / 100; -- e.g. 2375

                    -- Gross Anomaly: > 2x nominal
                    if count_val > 5000 then
                        clk_gross_h <= '1';
                    elsif count_val > upper_hard_th then
                        clk_fast_h  <= '1';
                    elsif count_val < lower_hard_th then
                        clk_slow_h  <= '1';
                    end if;

                    -- Soft Deviation Check (deviasi > CLK_SOFT_TH, default 1% = 25 count delta)
                    if count_val > 2500 then
                        delta_pct := ((count_val - 2500) * 100) / 2500;
                    else
                        delta_pct := ((2500 - count_val) * 100) / 2500;
                    end if;

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
