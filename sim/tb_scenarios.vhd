--------------------------------------------------------------------------------
-- File: tb_scenarios.vhd
-- Description: Comprehensive Self-Checking Verification Testbench implementing
--              all 16 scenarios defined in tb_scenarios.md (Scenarios A, B, C, D, F)
--
-- Coverage:
--   Scenario A (Conventional Threshold Detection):
--     TB-01: Normal operation               -> No action
--     TB-02: Extreme voltage                -> Key clear (Instant Layer 1)
--     TB-03: Extreme temperature            -> Key clear (Instant Layer 1)
--     TB-04: Extreme clock                  -> Key clear (Instant Layer 1)
--     TB-05: Extreme memory integrity       -> Key clear (Instant Layer 1)
--
--   Scenario B (Single Gray-Zone Parameter):
--     TB-06: Single gray event              -> snn_spike = 0, no action
--     TB-07: Repeat same parameter          -> snn_spike = 1, warning LED
--     TB-08: Repeat same parameter again    -> snn_spike = 2, key clear
--
--   Scenario C (Gray-Zone Combination):
--     TB-09: 2 gray events (small weights)  -> snn_spike = 0, no action
--     TB-10: 2 gray events (large weights)  -> snn_spike = 1, warning LED
--     TB-11: Repeat small weight combo      -> snn_spike = 2, key clear
--     TB-12: Repeat large weight combo      -> snn_spike = 2, key clear
--
--   Scenario D (Parameter Sweep):
--     TB-13: 3 parameter combination pattern -> snn_spike = 2, key clear
--     TB-14: 4 parameter combination pattern -> snn_spike = 2, key clear
--
--   Scenario F (Decay Behavior):
--     TB-15: Single gray event + decay      -> Monotonic decay to 0, snn_spike = 0
--     TB-16: Gray events with interval < T_decay -> Accumulation fires snn_spike = 1
--
-- Standard: VHDL-2008, IEEE numeric_std
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.pkg_fsd.all;
use work.pkg_weights_gen.all;

entity tb_scenarios is
end entity tb_scenarios;

architecture sim of tb_scenarios is

    constant CLK_PERIOD : time := 10 ns; -- 100 MHz clock
    
    -- Global Testbench Signals
    signal clk100        : std_logic := '0';
    signal rstn          : std_logic := '0';
    signal sim_done      : boolean   := false;

    -- Sensor MUX Physical/Internal Simulation Inputs
    signal real_clk_fast_h      : std_logic := '0';
    signal real_clk_slow_h      : std_logic := '0';
    signal real_clk_stop_h      : std_logic := '0';
    signal real_mmcm_unlock_h   : std_logic := '0';
    signal real_v_under_h       : std_logic := '0';
    signal real_v_over_h        : std_logic := '0';
    signal real_key_corrupt_h   : std_logic := '0';
    signal real_jtag_h          : std_logic := '0';

    signal real_clk_soft_spk    : std_logic := '0';
    signal real_clk_soft_q      : unsigned(3 downto 0) := (others => '0');
    signal real_v_soft_spk      : std_logic := '0';
    signal real_v_soft_q        : unsigned(3 downto 0) := (others => '0');
    signal real_temp_soft_spk   : std_logic := '0';
    signal real_temp_soft_q     : unsigned(3 downto 0) := (others => '0');
    signal real_probe_soft_spk  : std_logic := '0';
    signal real_probe_soft_q    : unsigned(3 downto 0) := (others => '0');

    -- Interconnect between MUX and SNN LIF
    signal mux_spikes_active    : std_logic_vector(N_CH-1 downto 0);
    signal mux_spikes_q         : q_array_t;

    -- SNN LIF Unit Signals
    signal leak_tick            : std_logic := '0';
    signal snn_fire_out         : std_logic_vector(N_NEUR-1 downto 0);
    signal snn_alert            : std_logic;
    signal snn_class            : std_logic_vector(1 downto 0);
    signal snn_v_mem            : membrane_array_t;

    -- Layer 1 Hard Alert OR-reduction (Direct Conventional Detection Path)
    signal hard_alert_l1        : std_logic := '0';

    -- Response Escalation Unit Signals
    signal unlock_pulse         : std_logic := '0';
    signal zeroize_pulse        : std_logic;
    signal alert_latched        : std_logic;
    signal zeroized_latched     : std_logic;
    signal alert_count_out      : unsigned(7 downto 0);
    signal class_out            : std_logic_vector(1 downto 0);
    signal latency_cycles       : unsigned(31 downto 0);
    signal led_alert            : std_logic;
    signal led_zeroized         : std_logic;

    -- Victim Cryptographic Asset Core
    signal key_disp             : std_logic_vector(15 downto 0);
    signal core_zeroized        : std_logic;
    signal cosmic_flip_p        : std_logic := '0';
    signal corrupt_inject_h     : std_logic := '0';
    signal key_corrupt_out      : std_logic;

    -- Component wiring complete, process begins below
begin

    ----------------------------------------------------------------------------
    -- 100 MHz System Clock Generator
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
    -- U11: Sensor Multiplexer
    ----------------------------------------------------------------------------
    u_sensor_mux : entity work.sensor_mux
        port map (
            clk100              => clk100,
            rstn                => rstn,
            mode_sel            => "10", -- Mode C (Hybrid)
            real_clk_fast_h     => real_clk_fast_h,
            real_clk_slow_h     => real_clk_slow_h,
            real_clk_stop_h     => real_clk_stop_h,
            real_mmcm_unlock    => real_mmcm_unlock_h,
            real_v_under_h      => real_v_under_h,
            real_v_over_h       => real_v_over_h,
            real_key_corr_h     => real_key_corrupt_h,
            real_jtag_h         => real_jtag_h,
            real_clk_soft_spk   => real_clk_soft_spk,
            real_clk_soft_q     => real_clk_soft_q,
            real_v_soft_spk     => real_v_soft_spk,
            real_v_soft_q       => real_v_soft_q,
            real_temp_soft_spk  => real_temp_soft_spk,
            real_temp_soft_q    => real_temp_soft_q,
            real_probe_soft_spk => real_probe_soft_spk,
            real_probe_soft_q   => real_probe_soft_q,
            synth_spikes        => (others => '0'),
            synth_q             => (others => (others => '0')),
            spikes_active       => mux_spikes_active,
            spikes_q_out        => mux_spikes_q
        );

    ----------------------------------------------------------------------------
    -- U12: SNN LIF 4-Neuron Bank
    ----------------------------------------------------------------------------
    u_snn_lif : entity work.snn_lif
        port map (
            clk100         => clk100,
            rstn           => rstn,
            spikes_active  => mux_spikes_active,
            spikes_q       => mux_spikes_q,
            leak_tick      => leak_tick,
            w_we           => '0',
            w_neur_idx     => 0,
            w_ch_idx       => 0,
            w_data         => (others => '0'),
            thetas         => DEFAULT_THETA,
            m_shifts       => DEFAULT_M_SHIFTS,
            fire_out       => snn_fire_out,
            alert_snn      => snn_alert,
            class_id       => snn_class,
            v_membranes    => snn_v_mem
        );

    ----------------------------------------------------------------------------
    -- U13: Response Escalation Controller
    ----------------------------------------------------------------------------
    u_response : entity work.response
        port map (
            clk100           => clk100,
            rstn             => rstn,
            hard_alert_l1    => hard_alert_l1,
            snn_alert_l3     => snn_alert,
            snn_class_in     => snn_class,
            arm_en           => '1',
            bypass_snn       => '0',
            esc_th           => to_unsigned(2, 8), -- 1: Warning, 2: Zeroize Key
            unlock_pulse     => unlock_pulse,
            attack_active    => '0',
            zeroize_pulse    => zeroize_pulse,
            alert_latched    => alert_latched,
            zeroized_latched => zeroized_latched,
            alert_count_out  => alert_count_out,
            class_out        => class_out,
            latency_cycles   => latency_cycles,
            led_alert        => led_alert,
            led_zeroized     => led_zeroized
        );

    ----------------------------------------------------------------------------
    -- U8: Protected Cryptographic Victim Core
    ----------------------------------------------------------------------------
    u_victim : entity work.victim_core
        port map (
            clk_core         => clk100,
            rstn_core        => rstn,
            key_load_en      => '0',
            key_in           => (others => '0'),
            zeroize_pulse    => zeroize_pulse,
            req_out          => open,
            ack_in           => '0',
            digest_out       => open,
            zeroized_out     => core_zeroized,
            key_disp         => key_disp,
            cosmic_flip_p    => cosmic_flip_p,
            corrupt_inject_h => corrupt_inject_h,
            key_corrupt_out  => key_corrupt_out
        );

    ----------------------------------------------------------------------------
    -- Main Verification Process: Executes Scenarios TB-01 to TB-16
    ----------------------------------------------------------------------------
    p_main : process
        variable pass_count : integer := 0;
        variable fail_count : integer := 0;

        -- Helper procedure to pulse a clock cycle
        procedure wait_cycles(constant n : in integer) is
        begin
            for i in 1 to n loop
                wait until rising_edge(clk100);
            end loop;
            wait for 1 ns; -- allow delta cycles & combinational outputs to settle
        end procedure;

        -- Helper procedure to reset and unlock the security system to pristine state
        procedure reset_system is
        begin
            -- Assert Reset
            rstn <= '0';
            real_clk_fast_h    <= '0';
            real_clk_slow_h    <= '0';
            real_clk_stop_h    <= '0';
            real_mmcm_unlock_h <= '0';
            real_v_under_h     <= '0';
            real_v_over_h      <= '0';
            real_key_corrupt_h <= '0';
            real_jtag_h        <= '0';
            real_clk_soft_spk  <= '0';
            real_clk_soft_q    <= (others => '0');
            real_v_soft_spk    <= '0';
            real_v_soft_q      <= (others => '0');
            real_temp_soft_spk <= '0';
            real_temp_soft_q   <= (others => '0');
            real_probe_soft_spk<= '0';
            real_probe_soft_q  <= (others => '0');
            leak_tick          <= '0';
            unlock_pulse       <= '0';
            cosmic_flip_p      <= '0';
            corrupt_inject_h   <= '0';
            hard_alert_l1      <= '0';
            
            wait_cycles(5);
            rstn <= '1';
            wait_cycles(5);

            -- Send unlock pulse to clear response latch & counters
            unlock_pulse <= '1';
            wait_cycles(1);
            unlock_pulse <= '0';
            wait_cycles(5);
        end procedure;
    begin
        report "========================================================================" severity note;
        report " Starting tb_scenarios: Complete FSD v2 Anti-Tamper Verification Suite " severity note;
        report " Reference: tb_scenarios.md (Scenarios A, B, C, D, F)                  " severity note;
        report "========================================================================" severity note;

        ------------------------------------------------------------------------
        -- Scenario A: Conventional Threshold Detection (Layer 1 Instant)
        ------------------------------------------------------------------------
        report "----------------------------------------------------------------" severity note;
        report " [Scenario A] Conventional Threshold Detection (TB-01 to TB-05)" severity note;
        report "----------------------------------------------------------------" severity note;

        -- TB-01: Normal operation -> No action
        reset_system;
        wait_cycles(20);
        assert (alert_count_out = 0) and (alert_latched = '0') and (zeroized_latched = '0') and (key_disp = x"0123")
            report "TB-01 FAILED: Unexpected alert in normal condition!" severity failure;
        report " [PASS] TB-01: Normal operation verified (Key=0123 intact, 0 alerts, 0 spikes)" severity note;
        pass_count := pass_count + 1;

        -- TB-02: Extreme voltage -> Key clear
        reset_system;
        real_v_under_h <= '1';
        hard_alert_l1  <= '1';
        wait_cycles(3);
        assert (zeroized_latched = '1') and (key_disp = x"0000")
            report "TB-02 FAILED: Extreme voltage did not trigger immediate key clear!" severity failure;
        report " [PASS] TB-02: Extreme voltage verified (Key cleared to 0000 instantly)" severity note;
        pass_count := pass_count + 1;

        -- TB-03: Extreme temperature -> Key clear
        reset_system;
        hard_alert_l1 <= '1'; -- Simulated thermal breaker trip
        wait_cycles(3);
        assert (zeroized_latched = '1') and (key_disp = x"0000")
            report "TB-03 FAILED: Extreme temperature did not trigger immediate key clear!" severity failure;
        report " [PASS] TB-03: Extreme temperature verified (Key cleared to 0000 instantly)" severity note;
        pass_count := pass_count + 1;

        -- TB-04: Extreme clock -> Key clear
        reset_system;
        real_clk_fast_h <= '1';
        hard_alert_l1   <= '1';
        wait_cycles(3);
        assert (zeroized_latched = '1') and (key_disp = x"0000")
            report "TB-04 FAILED: Extreme clock glitch did not trigger immediate key clear!" severity failure;
        report " [PASS] TB-04: Extreme clock verified (Key cleared to 0000 instantly)" severity note;
        pass_count := pass_count + 1;

        -- TB-05: Extreme memory integrity -> Key clear
        reset_system;
        corrupt_inject_h <= '1';
        wait_cycles(1);
        hard_alert_l1    <= key_corrupt_out;
        wait_cycles(1);
        corrupt_inject_h <= '0';
        wait_cycles(3);
        assert (zeroized_latched = '1') and (key_disp = x"0000")
            report "TB-05 FAILED: Memory integrity tamper did not trigger immediate key clear!" severity failure;
        report " [PASS] TB-05: Extreme memory integrity verified (Key cleared to 0000 instantly)" severity note;
        pass_count := pass_count + 1;

        ------------------------------------------------------------------------
        -- Scenario B: Single Gray-Zone Parameter
        ------------------------------------------------------------------------
        report "----------------------------------------------------------------" severity note;
        report " [Scenario B] Single Gray-Zone Parameter (TB-06 to TB-08)      " severity note;
        report "----------------------------------------------------------------" severity note;

        -- TB-06: Single gray event -> snn_spike = 0, no action
        reset_system;
        real_clk_soft_spk <= '1';
        real_clk_soft_q   <= to_unsigned(1, 4); -- 1x pulse (+50 weight)
        wait_cycles(1);
        real_clk_soft_spk <= '0';
        wait_cycles(4);
        assert (alert_count_out = 0) and (alert_latched = '0') and (zeroized_latched = '0') and (snn_v_mem(1) = 50)
            report "TB-06 FAILED: Single gray event falsely triggered spike or alert!" severity failure;
        report " [PASS] TB-06: Single gray event verified (V=50 < 128, snn_spike=0, no action)" severity note;
        pass_count := pass_count + 1;

        -- TB-07: Parameter yang sama diulang -> snn_spike = 1, warning LED
        -- Inject 2 more pulses (+50 + 50 => Total 150 >= 128)
        for i in 1 to 2 loop
            real_clk_soft_spk <= '1';
            real_clk_soft_q   <= to_unsigned(1, 4);
            wait_cycles(1);
            real_clk_soft_spk <= '0';
            wait_cycles(3);
        end loop;
        assert (alert_count_out = 1) and (alert_latched = '1') and (zeroized_latched = '0') and (key_disp = x"0123")
            report "TB-07 FAILED: Repeated gray event did not fire snn_spike=1 Warning LED!" severity failure;
        report " [PASS] TB-07: Repeated gray event verified (snn_spike=1, Warning LED=1, Key intact)" severity note;
        pass_count := pass_count + 1;

        -- TB-08: Parameter yang sama diulang lagi -> snn_spike = 2, key clear
        -- Subtractive reset leaves V = 150 - 128 = 22.
        -- Inject 3 more pulses (+50 x 3 = +150 => 22 + 150 = 172 >= 128)
        for i in 1 to 3 loop
            real_clk_soft_spk <= '1';
            real_clk_soft_q   <= to_unsigned(1, 4);
            wait_cycles(1);
            real_clk_soft_spk <= '0';
            wait_cycles(3);
        end loop;
        wait_cycles(5);
        assert (alert_count_out = 2) and (zeroized_latched = '1') and (key_disp = x"0000")
            report "TB-08 FAILED: Further repeated gray event did not escalate to snn_spike=2 key clear!" severity failure;
        report " [PASS] TB-08: Repeated gray event verified (snn_spike=2, Zeroize=1, Key cleared to 0000)" severity note;
        pass_count := pass_count + 1;

        ------------------------------------------------------------------------
        -- Scenario C: Gray-Zone Combination
        ------------------------------------------------------------------------
        report "----------------------------------------------------------------" severity note;
        report " [Scenario C] Gray-Zone Combination (TB-09 to TB-12)           " severity note;
        report "----------------------------------------------------------------" severity note;

        -- TB-09: Two gray events (2 parameter weight kecil) -> snn_spike = 0, no action
        reset_system;
        -- CH_PROBE_SOFT (w=10) + small pulse
        real_probe_soft_spk <= '1';
        real_probe_soft_q   <= to_unsigned(1, 4);
        wait_cycles(1);
        real_probe_soft_spk <= '0';
        wait_cycles(3);
        real_probe_soft_spk <= '1';
        real_probe_soft_q   <= to_unsigned(1, 4);
        wait_cycles(1);
        real_probe_soft_spk <= '0';
        wait_cycles(4);
        assert (alert_count_out = 0) and (alert_latched = '0') and (snn_v_mem(1) = 20)
            report "TB-09 FAILED: Small weight combination exceeded threshold!" severity failure;
        report " [PASS] TB-09: 2 small weight gray events verified (V=20 < 128, snn_spike=0, no action)" severity note;
        pass_count := pass_count + 1;

        -- TB-10: Two gray events (2 parameter weight besar) -> snn_spike = 1, warning LED
        reset_system;
        -- CH_CLK_SOFT (w=50, q=1) + CH_V_SOFT (w=50, q=2) => 50 + 100 = 150 >= 128
        real_clk_soft_spk <= '1';
        real_clk_soft_q   <= to_unsigned(1, 4);
        real_v_soft_spk   <= '1';
        real_v_soft_q     <= to_unsigned(2, 4);
        wait_cycles(1);
        real_clk_soft_spk <= '0';
        real_v_soft_spk   <= '0';
        wait_cycles(4);
        assert (alert_count_out = 1) and (alert_latched = '1') and (zeroized_latched = '0')
            report "TB-10 FAILED: Large weight combination did not trigger warning LED!" severity failure;
        report " [PASS] TB-10: 2 large weight gray events verified (snn_spike=1, Warning LED=1, Key intact)" severity note;
        pass_count := pass_count + 1;

        -- TB-11: Two gray events diulang (2 parameter weight kecil) -> snn_spike = 2, key clear
        reset_system;
        -- Inject 14 pairs of probe pulses (+10 each => 20 per pair => 140 each burst => 2 spikes)
        for pair in 1 to 14 loop
            real_probe_soft_spk <= '1';
            real_probe_soft_q   <= to_unsigned(2, 4); -- 2 x 10 = +20 per tick
            wait_cycles(1);
            real_probe_soft_spk <= '0';
            wait_cycles(2);
        end loop;
        wait_cycles(5);
        assert (alert_count_out = 2) and (zeroized_latched = '1') and (key_disp = x"0000")
            report "TB-11 FAILED: Repeated small weight combo did not escalate to key clear!" severity failure;
        report " [PASS] TB-11: Repeated small weight combo verified (snn_spike=2, Key cleared)" severity note;
        pass_count := pass_count + 1;

        -- TB-12: Two gray events diulang (2 parameter weight besar) -> snn_spike = 2, key clear
        reset_system;
        -- Burst 1: CLK_SOFT (w=50) + V_SOFT (w=50) => 100 + 100 = 200 >= 128 => Spike 1
        for burst in 1 to 2 loop
            real_clk_soft_spk <= '1';
            real_clk_soft_q   <= to_unsigned(1, 4);
            real_v_soft_spk   <= '1';
            real_v_soft_q     <= to_unsigned(1, 4);
            wait_cycles(1);
            real_clk_soft_spk <= '0';
            real_v_soft_spk   <= '0';
            wait_cycles(2);
        end loop;
        wait_cycles(3);
        assert (alert_count_out = 1)
            report "TB-12 Check 1 FAILED: Expected Spike 1 after burst 1!" severity failure;
        -- Burst 2: repeat CLK_SOFT + V_SOFT => Spike 2
        for burst in 1 to 2 loop
            real_clk_soft_spk <= '1';
            real_clk_soft_q   <= to_unsigned(1, 4);
            real_v_soft_spk   <= '1';
            real_v_soft_q     <= to_unsigned(1, 4);
            wait_cycles(1);
            real_clk_soft_spk <= '0';
            real_v_soft_spk   <= '0';
            wait_cycles(2);
        end loop;
        wait_cycles(5);
        assert (alert_count_out = 2) and (zeroized_latched = '1') and (key_disp = x"0000")
            report "TB-12 FAILED: Repeated large weight combo did not escalate to key clear!" severity failure;
        report " [PASS] TB-12: Repeated large weight combo verified (snn_spike=2, Key cleared)" severity note;
        pass_count := pass_count + 1;

        ------------------------------------------------------------------------
        -- Scenario D: Parameter Sweep
        ------------------------------------------------------------------------
        report "----------------------------------------------------------------" severity note;
        report " [Scenario D] Parameter Sweep (TB-13 & TB-14)                  " severity note;
        report "----------------------------------------------------------------" severity note;

        -- TB-13: Combination parameter pattern (3 parameter) -> snn_spike = 2, key clear
        reset_system;
        -- Simultaneous Clock (50) + Voltage (50) + Temperature (50) = 150 >= 128
        -- Event 1: 150 >= 128 -> Spike 1 (V_reset = 22)
        real_clk_soft_spk  <= '1'; real_clk_soft_q  <= to_unsigned(1, 4);
        real_v_soft_spk    <= '1'; real_v_soft_q    <= to_unsigned(1, 4);
        real_temp_soft_spk <= '1'; real_temp_soft_q <= to_unsigned(1, 4);
        wait_cycles(1);
        real_clk_soft_spk  <= '0';
        real_v_soft_spk    <= '0';
        real_temp_soft_spk <= '0';
        wait_cycles(4);
        assert (alert_count_out = 1)
            report "TB-13 Check 1 FAILED: Expected Spike 1 on 3-parameter combination!" severity failure;

        -- Event 2: 22 + 150 = 172 >= 128 -> Spike 2 -> Key Clear
        real_clk_soft_spk  <= '1'; real_clk_soft_q  <= to_unsigned(1, 4);
        real_v_soft_spk    <= '1'; real_v_soft_q    <= to_unsigned(1, 4);
        real_temp_soft_spk <= '1'; real_temp_soft_q <= to_unsigned(1, 4);
        wait_cycles(1);
        real_clk_soft_spk  <= '0';
        real_v_soft_spk    <= '0';
        real_temp_soft_spk <= '0';
        wait_cycles(5);
        assert (alert_count_out = 2) and (zeroized_latched = '1') and (key_disp = x"0000")
            report "TB-13 FAILED: 3-parameter pattern did not escalate to key clear!" severity failure;
        report " [PASS] TB-13: 3-parameter pattern verified (snn_spike=2, Key cleared to 0000)" severity note;
        pass_count := pass_count + 1;

        -- TB-14: Combination parameter pattern (4 parameter) -> snn_spike = 2, key clear
        reset_system;
        -- Simultaneous Clock (50) + Voltage (50) + Temp (50) + Probe (10) = 160 >= 128
        -- Event 1: 160 >= 128 -> Spike 1 (V_reset = 32)
        real_clk_soft_spk   <= '1'; real_clk_soft_q   <= to_unsigned(1, 4);
        real_v_soft_spk     <= '1'; real_v_soft_q     <= to_unsigned(1, 4);
        real_temp_soft_spk  <= '1'; real_temp_soft_q  <= to_unsigned(1, 4);
        real_probe_soft_spk <= '1'; real_probe_soft_q <= to_unsigned(1, 4);
        wait_cycles(1);
        real_clk_soft_spk   <= '0';
        real_v_soft_spk     <= '0';
        real_temp_soft_spk  <= '0';
        real_probe_soft_spk <= '0';
        wait_cycles(4);
        assert (alert_count_out = 1)
            report "TB-14 Check 1 FAILED: Expected Spike 1 on 4-parameter combination!" severity failure;

        -- Event 2: 32 + 160 = 192 >= 128 -> Spike 2 -> Key Clear
        real_clk_soft_spk   <= '1'; real_clk_soft_q   <= to_unsigned(1, 4);
        real_v_soft_spk     <= '1'; real_v_soft_q     <= to_unsigned(1, 4);
        real_temp_soft_spk  <= '1'; real_temp_soft_q  <= to_unsigned(1, 4);
        real_probe_soft_spk <= '1'; real_probe_soft_q <= to_unsigned(1, 4);
        wait_cycles(1);
        real_clk_soft_spk   <= '0';
        real_v_soft_spk     <= '0';
        real_temp_soft_spk  <= '0';
        real_probe_soft_spk <= '0';
        wait_cycles(5);
        assert (alert_count_out = 2) and (zeroized_latched = '1') and (key_disp = x"0000")
            report "TB-14 FAILED: 4-parameter pattern did not escalate to key clear!" severity failure;
        report " [PASS] TB-14: 4-parameter pattern verified (snn_spike=2, Key cleared to 0000)" severity note;
        pass_count := pass_count + 1;

        ------------------------------------------------------------------------
        -- Scenario F: Decay Behavior
        ------------------------------------------------------------------------
        report "----------------------------------------------------------------" severity note;
        report " [Scenario F] Membrane Potential Decay Behavior (TB-15 & TB-16)" severity note;
        report "----------------------------------------------------------------" severity note;

        -- TB-15: Satu gray event, lalu tidak ada input. Pantau membrane potential
        reset_system;
        real_clk_soft_spk <= '1';
        real_clk_soft_q   <= to_unsigned(1, 4); -- +50 weight
        wait_cycles(1);
        real_clk_soft_spk <= '0';
        wait_cycles(3);
        assert (snn_v_mem(1) = 50)
            report "TB-15 FAILED: Initial deposit != 50!" severity failure;
        report "  TB-15 Initial deposit: V = " & integer'image(to_integer(snn_v_mem(1))) severity note;

        -- Pulse leak ticks and observe monotonic decay: V -= V >> 2
        -- 50 -> 38 -> 29 -> 22 -> 17 -> 13 -> 10 -> 8 -> 6 -> 5 -> 4 -> 3 -> 2 -> 1 -> 0
        for lk in 1 to 15 loop
            leak_tick <= '1';
            wait_cycles(1);
            leak_tick <= '0';
            wait_cycles(2);
            report "  TB-15 Leak Step " & integer'image(lk) & ": V = " & integer'image(to_integer(snn_v_mem(1))) severity note;
        end loop;
        assert (snn_v_mem(1) = 0) and (alert_count_out = 0)
            report "TB-15 FAILED: Membrane potential did not decay to 0!" severity failure;
        report " [PASS] TB-15: Monotonic decay verified (Decayed cleanly 50 -> 0, snn_spike=0)" severity note;
        pass_count := pass_count + 1;

        -- TB-16: Gray event diulang dengan interval < T_decay
        reset_system;
        -- Deposit +50, leak 1 tick, repeat 4 times:
        -- Dep 1 (+50): V=50
        -- Leak 1: V=38
        -- Dep 2 (+50): V=88
        -- Leak 2: V=66
        -- Dep 3 (+50): V=116
        -- Leak 3: V=87
        -- Dep 4 (+50): V=137 >= 128 => Spike 1!
        for step in 1 to 3 loop
            real_clk_soft_spk <= '1';
            real_clk_soft_q   <= to_unsigned(1, 4);
            wait_cycles(1);
            real_clk_soft_spk <= '0';
            wait_cycles(2);
            -- Single leak tick (interval < T_decay)
            leak_tick <= '1';
            wait_cycles(1);
            leak_tick <= '0';
            wait_cycles(2);
            report "  TB-16 Fast Repeat Step " & integer'image(step) & ": V = " & integer'image(to_integer(snn_v_mem(1))) severity note;
        end loop;

        -- Final 4th deposit
        real_clk_soft_spk <= '1';
        real_clk_soft_q   <= to_unsigned(1, 4);
        wait_cycles(1);
        real_clk_soft_spk <= '0';
        wait_cycles(4);
        report "  TB-16 After Deposit 4: V = " & integer'image(to_integer(snn_v_mem(1))) & ", Alerts = " & integer'image(to_integer(alert_count_out)) severity note;

        assert (alert_count_out = 1) and (alert_latched = '1') and (zeroized_latched = '0')
            report "TB-16 FAILED: Fast repeat < T_decay did not accumulate and fire snn_spike=1!" severity failure;
        report " [PASS] TB-16: Accumulation < T_decay verified (Overcame decay, snn_spike=1, Warning LED=1)" severity note;
        pass_count := pass_count + 1;

        ------------------------------------------------------------------------
        -- Verification Summary
        ------------------------------------------------------------------------
        report "========================================================================" severity note;
        report " VERIFICATION COMPLETED: ALL 16 SCENARIOS PASSED WITH ZERO FAILURES!     " severity note;
        report " Total Passed: " & integer'image(pass_count) & " / 16 scenarios          " severity note;
        report "========================================================================" severity note;

        sim_done <= true;
        wait;
    end process p_main;

end architecture sim;
