--------------------------------------------------------------------------------
-- File: tb_snn_lif.vhd
-- Description: L1 Unit Testbench for snn_lif.vhd (FSD v2 §12 L1)
-- Bit-exact verification against sw/golden/snn_model.py:
--   1. N0 instant reaction to hard flags (FP=0 for sub-threshold)
--   2. N1 rejection of single soft noise pulse (Peak V=33 < 128)
--   3. N1 detection of SCEN2 repeat probe at pulse 5 of 8 (Subtractive Reset V->5)
-- Standard: VHDL-2008, IEEE numeric_std
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.pkg_fsd.all;
use work.pkg_weights_gen.all;

entity tb_snn_lif is
end entity tb_snn_lif;

architecture sim of tb_snn_lif is

    constant CLK_PERIOD : time := 10 ns; -- 100 MHz clock
    
    signal clk100        : std_logic := '0';
    signal rstn          : std_logic := '0';
    signal spikes_active : std_logic_vector(N_CH-1 downto 0) := (others => '0');
    signal spikes_q      : q_array_t := (others => (others => '0'));
    signal leak_tick     : std_logic := '0';
    
    signal fire_out      : std_logic_vector(N_NEUR-1 downto 0);
    signal alert_snn     : std_logic;
    signal class_id      : std_logic_vector(1 downto 0);
    signal v_membranes   : membrane_array_t;

    signal sim_done      : boolean := false;

begin

    ----------------------------------------------------------------------------
    -- 100 MHz Clock Generator
    ----------------------------------------------------------------------------
    p_clk : process
    begin
        while not sim_done loop
            clk100 <= '0';
            wait for CLK_PERIOD / 2;
            clk100 <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process p_clk;

    ----------------------------------------------------------------------------
    -- Unit Under Test (snn_lif)
    ----------------------------------------------------------------------------
    uut : entity work.snn_lif
        port map (
            clk100        => clk100,
            rstn          => rstn,
            spikes_active => spikes_active,
            spikes_q      => spikes_q,
            leak_tick     => leak_tick,
            w_we          => '0',
            w_neur_idx    => 0,
            w_ch_idx      => 0,
            w_data        => (others => '0'),
            thetas        => DEFAULT_THETA,
            m_shifts      => DEFAULT_M_SHIFTS,
            fire_out      => fire_out,
            alert_snn     => alert_snn,
            class_id      => class_id,
            v_membranes   => v_membranes
        );

    ----------------------------------------------------------------------------
    -- Verification Process
    ----------------------------------------------------------------------------
    p_verify : process
    begin
        report "==========================================================" severity note;
        report "Starting tb_snn_lif: Bit-Exact L1 Unit Verification" severity note;
        report "==========================================================" severity note;

        -- Step 1: Reset
        rstn <= '0';
        wait for 100 ns;
        wait until rising_edge(clk100);
        rstn <= '1';
        wait for 100 ns;

        -- Test 1: Single noise pulse (Soft clock ch=8, q=3) -> must NOT fire
        report "Test 1: Single soft noise pulse (q=3)..." severity note;
        spikes_active(CH_CLK_SOFT) <= '1';
        spikes_q(CH_CLK_SOFT)      <= to_unsigned(3, 4);
        wait until rising_edge(clk100);
        spikes_active <= (others => '0');
        wait until rising_edge(clk100);
        wait for 1 ns;

        assert fire_out(1) = '0' 
            report "FAIL: Single noise pulse should NOT fire N1!" severity failure;
        assert v_membranes(1) = to_signed(33, 16)
            report "FAIL: N1 membrane should be exactly 33 after q=3 deposit!" severity failure;
        report "[PASS] Test 1: N1 V = 33 / 128 (No fire, FP=0)" severity note;

        -- Clear membrane back to 0
        rstn <= '0';
        wait for 20 ns;
        rstn <= '1';
        wait for 20 ns;

        -- Test 2: SCEN2 Repeat-Probe sequence (8 events, 2 leak ticks between each)
        report "Test 2: SCEN2 Repeat-Probe sequence (FSD v2 §7.4 worked example)..." severity note;
        for evt in 1 to 8 loop
            -- Deposit spike (ch=8, q=3)
            spikes_active(CH_CLK_SOFT) <= '1';
            spikes_q(CH_CLK_SOFT)      <= to_unsigned(3, 4);
            wait until rising_edge(clk100);
            spikes_active <= (others => '0');
            wait until rising_edge(clk100);

            -- Wait a delta or check
            wait for 1 ns;
            report "Event " & integer'image(evt) & " V=" & integer'image(to_integer(v_membranes(1))) & " Fire=" & std_logic'image(fire_out(1)) severity note;

            -- Check event 5 fire condition
            if evt = 5 then
                assert fire_out(1) = '1'
                    report "FAIL: N1 must FIRE at event 5!" severity failure;
                assert v_membranes(1) = to_signed(5, 16)
                    report "FAIL: N1 membrane after subtractive reset must be 5!" severity failure;
                report "[PASS] SCEN2 Fire observed exactly at event 5! V_reset = 5." severity note;
            else
                assert fire_out(1) = '0'
                    report "FAIL: N1 should not fire at event " & integer'image(evt) severity failure;
            end if;


            -- 2 leak ticks (representing 2 ms interval)
            for lk in 1 to 2 loop
                leak_tick <= '1';
                wait until rising_edge(clk100);
                leak_tick <= '0';
                wait until rising_edge(clk100);
            end loop;
        end loop;

        -- Test 3: N0 instant reaction to Hard Flag (ch=0 clk_fast_h, q=15)
        report "Test 3: N0 instant reaction to Hard Flag..." severity note;
        spikes_active(CH_CLK_FAST_H) <= '1';
        spikes_q(CH_CLK_FAST_H)      <= to_unsigned(15, 4);
        wait until rising_edge(clk100);
        spikes_active <= (others => '0');
        wait until rising_edge(clk100);
        wait for 1 ns;

        assert fire_out(0) = '1'
            report "FAIL: N0 must fire instantly on hard flag!" severity failure;
        assert class_id = "00"
            report "FAIL: Class must be N0 (Transient)!" severity failure;
        report "[PASS] N0 instant fire on hard flag confirmed!" severity note;


        report "==========================================================" severity note;
        report "tb_snn_lif PASSED ALL BIT-EXACT TESTS SUCCESSFULLY!" severity note;
        report "==========================================================" severity note;

        sim_done <= true;
        wait;
    end process p_verify;

end architecture sim;
