--------------------------------------------------------------------------------
-- File: tb_scenarios.vhd
-- Description: Comprehensive Self-Checking Verification Testbench
--              Runs all 16 scenarios sequentially in one single simulation window.
--
-- Waveform Interface:
--   Inputs:  clk, rst, sw(3 downto 0), btn(3 downto 0)
--   Outputs: snn_count, snn_spike_count, key, warning_led, zeroize_led
--   Status:  tb_id (1-16), tb_pass ('1'=PASS, '0'=Testing/Reset)
--
-- Coverage (tb_scenarios.md):
--   TB-01 to TB-05: Conventional Threshold Detection (Layer 1 Instant)
--   TB-06 to TB-08: Single Gray-Zone Parameter (SNN Layer 2 Accumulation)
--   TB-09 to TB-12: Gray-Zone Combination (Multi-Sensor SNN Coincidence)
--   TB-13 to TB-14: Parameter Sweep (3 & 4 Simultaneous Tamper Injections)
--   TB-15 to TB-16: Membrane Potential Decay Behavior (Leaky Integrator)
--
-- Standard: VHDL-2008, IEEE numeric_std
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.finish;

use work.pkg_fsd.all;
use work.pkg_weights_gen.all;

entity tb_scenarios is
end entity tb_scenarios;

architecture sim of tb_scenarios is

    constant CLK_PERIOD : time := 10 ns; -- 100 MHz clock
    signal sim_done     : boolean := false;

    -- =========================================================================
    -- Top Waveform Interface Signals (Directly visualized in waveform window)
    -- =========================================================================
    -- Verification Markers
    signal tb_id              : integer range 0 to 16 := 0;  -- Active Scenario ID (1 to 16)
    signal tb_pass            : std_logic := '0';            -- '1' on PASS, '0' on Reset/Running

    -- Inputs
    signal clk                : std_logic := '0';            -- 100 MHz System Clock
    signal rst                : std_logic := '1';            -- Active-High Reset (Synchronous)
    signal sw                 : std_logic_vector(3 downto 0) := "0000"; -- 4 Switches: [3]=Clk, [2]=Volt, [1]=Temp, [0]=Mem
    signal btn                : std_logic_vector(3 downto 0) := "0000"; -- 4 Buttons:  [3]=Clk, [2]=Volt, [1]=Temp, [0]=Probe

    -- Outputs
    signal key                : std_logic_vector(15 downto 0); -- Master Key: 0x0123 (Intact) -> 0x0000 (Zeroized)
    signal snn_count          : signed(15 downto 0) := (others => '0'); -- SNN Membrane Potential (Count / Potential V)
    signal snn_spike_count    : unsigned(7 downto 0) := (others => '0'); -- Escalation Spike Counter (0, 1, 2)
    signal warning_led        : std_logic := '0';            -- Yellow Warning LED (Incident 1)
    signal zeroize_led        : std_logic := '0';            -- Red Lockdown Zeroize LED (Incident 2)

    -- Internal Active-Low Reset
    signal rstn               : std_logic := '0';

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

    -- Layer 1 Hard Alert OR-reduction
    signal hard_alert_l1        : std_logic := '0';

    -- Response Escalation Unit Signals
    signal unlock_pulse         : std_logic := '0';
    signal zeroize_pulse        : std_logic;
    signal alert_latched        : std_logic;
    signal zeroized_latched     : std_logic;
    signal alert_count_out      : unsigned(7 downto 0);
    signal class_out            : std_logic_vector(1 downto 0);
    signal latency_cycles       : unsigned(31 downto 0);

    -- Victim Cryptographic Asset Core
    signal core_zeroized        : std_logic;
    signal cosmic_flip_p        : std_logic := '0';
    signal corrupt_inject_h     : std_logic := '0';
    signal key_corrupt_out      : std_logic;

begin

    ----------------------------------------------------------------------------
    -- Signal Mappings
    ----------------------------------------------------------------------------
    rstn            <= not rst;
    snn_count       <= snn_v_mem(1);
    snn_spike_count <= alert_count_out;
    warning_led     <= alert_latched;
    zeroize_led     <= zeroized_latched;

    ----------------------------------------------------------------------------
    -- 100 MHz System Clock Generator
    ----------------------------------------------------------------------------
    p_clk : process
    begin
        while not sim_done loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process p_clk;

    ----------------------------------------------------------------------------
    -- U11: Sensor Multiplexer
    ----------------------------------------------------------------------------
    u_sensor_mux : entity work.sensor_mux
        port map (
            clk100              => clk,
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
            clk100         => clk,
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
            clk100           => clk,
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
            led_alert        => open,
            led_zeroized     => open
        );

    ----------------------------------------------------------------------------
    -- U8: Protected Cryptographic Victim Core
    ----------------------------------------------------------------------------
    u_victim : entity work.victim_core
        port map (
            clk_core         => clk,
            rstn_core        => rstn,
            key_load_en      => '0',
            key_in           => (others => '0'),
            zeroize_pulse    => zeroize_pulse,
            req_out          => open,
            ack_in           => '0',
            digest_out       => open,
            zeroized_out     => core_zeroized,
            key_disp         => key,
            cosmic_flip_p    => cosmic_flip_p,
            corrupt_inject_h => corrupt_inject_h,
            key_corrupt_out  => key_corrupt_out
        );

    ----------------------------------------------------------------------------
    -- Main Verification Process: Tasks / Procedures for All 16 Scenarios
    ----------------------------------------------------------------------------
    p_main : process
        variable pass_count : integer := 0;
        variable fail_count : integer := 0;

        -- Procedure to wait clock cycles
        procedure wait_cycles(constant n : in integer) is
        begin
            for i in 1 to n loop
                wait until rising_edge(clk);
            end loop;
            wait for 1 ns; -- allow delta cycles to settle
        end procedure;

        -- Task: do_reset (dipanggil sebelum tiap skenario)
        procedure do_reset is
        begin
            tb_pass <= '0';
            rst     <= '1'; -- Assert Active-High Reset
            sw      <= "0000";
            btn     <= "0000";
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
            rst <= '0'; -- Deassert Reset
            wait_cycles(5);

            -- Pulse unlock to clear latches & counters
            unlock_pulse <= '1';
            wait_cycles(1);
            unlock_pulse <= '0';
            wait_cycles(5);
        end procedure;

        -- Task: check (membandingkan output, set tb_pass, display PASS/FAIL, jeda 20 cycles)
        procedure check(
            constant test_num : in integer;
            constant cond     : in boolean;
            constant msg      : in string
        ) is
        begin
            if cond then
                tb_pass    <= '1';
                pass_count := pass_count + 1;
                report " [PASS] TB-" & integer'image(test_num) & ": " & msg severity note;
            else
                tb_pass    <= '0';
                fail_count := fail_count + 1;
                report " [FAIL] TB-" & integer'image(test_num) & ": " & msg severity error;
            end if;
            wait_cycles(20); -- Jeda 20 siklus clock setelah check
        end procedure;

        -- ---------------------------------------------------------------------
        -- Skenario TB-01 s/d TB-16 dalam bentuk Task / Procedure mandiri
        -- ---------------------------------------------------------------------
        -- TB-01: Normal operation -> expected: key intact, 0 alerts, 0 spikes
        procedure task_tb_01 is
        begin
            tb_id <= 1;
            do_reset;
            wait_cycles(20);
            check(1, (alert_count_out = 0) and (warning_led = '0') and (zeroize_led = '0') and (key = x"0123"),
                  "Normal baseline verified (Key=0123 intact, 0 alerts, 0 spikes)");
        end procedure;

        -- TB-02: Extreme voltage -> expected: key clear instantly
        procedure task_tb_02 is
        begin
            tb_id <= 2;
            do_reset;
            sw(2)          <= '1'; -- SW2: Extreme Voltage
            real_v_under_h <= '1';
            hard_alert_l1  <= '1';
            wait_cycles(3);
            sw(2)          <= '0';
            real_v_under_h <= '0';
            hard_alert_l1  <= '0';
            wait_cycles(2);
            check(2, (zeroize_led = '1') and (key = x"0000"),
                  "Extreme voltage triggered instant Key clear to 0000");
        end procedure;

        -- TB-03: Extreme temperature -> expected: key clear instantly
        procedure task_tb_03 is
        begin
            tb_id <= 3;
            do_reset;
            sw(1)         <= '1'; -- SW1: Extreme Temperature
            hard_alert_l1 <= '1';
            wait_cycles(3);
            sw(1)         <= '0';
            hard_alert_l1 <= '0';
            wait_cycles(2);
            check(3, (zeroize_led = '1') and (key = x"0000"),
                  "Extreme temperature triggered instant Key clear to 0000");
        end procedure;

        -- TB-04: Extreme clock -> expected: key clear instantly
        procedure task_tb_04 is
        begin
            tb_id <= 4;
            do_reset;
            sw(3)           <= '1'; -- SW3: Extreme Clock
            real_clk_fast_h <= '1';
            hard_alert_l1   <= '1';
            wait_cycles(3);
            sw(3)           <= '0';
            real_clk_fast_h <= '0';
            hard_alert_l1   <= '0';
            wait_cycles(2);
            check(4, (zeroize_led = '1') and (key = x"0000"),
                  "Extreme clock glitch triggered instant Key clear to 0000");
        end procedure;

        -- TB-05: Extreme memory integrity -> expected: key clear instantly
        procedure task_tb_05 is
        begin
            tb_id <= 5;
            do_reset;
            sw(0)            <= '1'; -- SW0: Extreme Memory
            corrupt_inject_h <= '1';
            wait_cycles(1);
            hard_alert_l1    <= key_corrupt_out;
            wait_cycles(1);
            corrupt_inject_h <= '0';
            wait_cycles(3);
            sw(0)            <= '0';
            hard_alert_l1    <= '0';
            wait_cycles(2);
            check(5, (zeroize_led = '1') and (key = x"0000"),
                  "Memory integrity tamper triggered instant Key clear to 0000");
        end procedure;

        -- TB-06: Single gray event -> expected: snn_spike = 0, no action
        procedure task_tb_06 is
        begin
            tb_id <= 6;
            do_reset;
            btn(3)            <= '1'; -- BTN3: Soft Clock Glitch (+50)
            real_clk_soft_spk <= '1';
            real_clk_soft_q   <= to_unsigned(1, 4);
            wait_cycles(1);
            btn(3)            <= '0';
            real_clk_soft_spk <= '0';
            wait_cycles(4);
            check(6, (alert_count_out = 0) and (warning_led = '0') and (snn_v_mem(1) = 50) and (key = x"0123"),
                  "Single gray event absorbed without false alarm (V=50 < 128, spike=0)");
        end procedure;

        -- TB-07: Parameter yang sama diulang -> expected: snn_spike = 1, warning LED
        procedure task_tb_07 is
        begin
            tb_id <= 7;
            do_reset;
            -- 3 pulses total (+50 + 50 + 50 = 150 >= 128)
            for i in 1 to 3 loop
                btn(3)            <= '1';
                real_clk_soft_spk <= '1';
                real_clk_soft_q   <= to_unsigned(1, 4);
                wait_cycles(1);
                btn(3)            <= '0';
                real_clk_soft_spk <= '0';
                wait_cycles(3);
            end loop;
            check(7, (alert_count_out = 1) and (warning_led = '1') and (zeroize_led = '0') and (key = x"0123"),
                  "Repeated gray event triggered Warning LED (snn_spike=1, Key intact)");
        end procedure;

        -- TB-08: Parameter yang sama diulang lagi -> expected: snn_spike = 2, key clear
        procedure task_tb_08 is
        begin
            tb_id <= 8;
            do_reset;
            -- Burst 1 (3 pulses -> Spike 1, V_sub=22)
            for i in 1 to 3 loop
                btn(3)            <= '1';
                real_clk_soft_spk <= '1';
                real_clk_soft_q   <= to_unsigned(1, 4);
                wait_cycles(1);
                btn(3)            <= '0';
                real_clk_soft_spk <= '0';
                wait_cycles(3);
            end loop;
            -- Burst 2 (3 pulses -> 22 + 150 = 172 >= 128 -> Spike 2)
            for i in 1 to 3 loop
                btn(3)            <= '1';
                real_clk_soft_spk <= '1';
                real_clk_soft_q   <= to_unsigned(1, 4);
                wait_cycles(1);
                btn(3)            <= '0';
                real_clk_soft_spk <= '0';
                wait_cycles(3);
            end loop;
            wait_cycles(5);
            check(8, (alert_count_out = 2) and (zeroize_led = '1') and (key = x"0000"),
                  "Repeated gray event escalated to Key clear (snn_spike=2, Key=0000)");
        end procedure;

        -- TB-09: 2 gray events (weight kecil) -> expected: snn_spike = 0, no action
        procedure task_tb_09 is
        begin
            tb_id <= 9;
            do_reset;
            btn(0)              <= '1'; -- BTN0: Probe (+10)
            real_probe_soft_spk <= '1';
            real_probe_soft_q   <= to_unsigned(1, 4);
            wait_cycles(1);
            btn(0)              <= '0';
            real_probe_soft_spk <= '0';
            wait_cycles(3);
            btn(0)              <= '1';
            real_probe_soft_spk <= '1';
            real_probe_soft_q   <= to_unsigned(1, 4);
            wait_cycles(1);
            btn(0)              <= '0';
            real_probe_soft_spk <= '0';
            wait_cycles(4);
            check(9, (alert_count_out = 0) and (warning_led = '0') and (snn_v_mem(1) = 20),
                  "2 small weight events absorbed (V=20 < 128, snn_spike=0, no action)");
        end procedure;

        -- TB-10: 2 gray events (weight besar) -> expected: snn_spike = 1, warning LED
        procedure task_tb_09_10 is
        begin
            tb_id <= 10;
            do_reset;
            btn(3)            <= '1'; -- BTN3: Clock (+50)
            btn(2)            <= '1'; -- BTN2: Volt (+100)
            real_clk_soft_spk <= '1';
            real_clk_soft_q   <= to_unsigned(1, 4);
            real_v_soft_spk   <= '1';
            real_v_soft_q     <= to_unsigned(2, 4);
            wait_cycles(1);
            btn(3)            <= '0';
            btn(2)            <= '0';
            real_clk_soft_spk <= '0';
            real_v_soft_spk   <= '0';
            wait_cycles(4);
            check(10, (alert_count_out = 1) and (warning_led = '1') and (zeroize_led = '0'),
                  "2 large weight events fired Warning LED (snn_spike=1, Key intact)");
        end procedure;

        -- TB-11: 2 gray events diulang (weight kecil) -> expected: snn_spike = 2, key clear
        procedure task_tb_11 is
        begin
            tb_id <= 11;
            do_reset;
            for pair in 1 to 14 loop
                btn(0)              <= '1'; -- BTN0: Probe (+20)
                real_probe_soft_spk <= '1';
                real_probe_soft_q   <= to_unsigned(2, 4);
                wait_cycles(1);
                btn(0)              <= '0';
                real_probe_soft_spk <= '0';
                wait_cycles(2);
            end loop;
            wait_cycles(5);
            check(11, (alert_count_out = 2) and (zeroize_led = '1') and (key = x"0000"),
                  "Repeated small weight combo escalated to Key clear (snn_spike=2)");
        end procedure;

        -- TB-12: 2 gray events diulang (weight besar) -> expected: snn_spike = 2, key clear
        procedure task_tb_12 is
        begin
            tb_id <= 12;
            do_reset;
            for burst in 1 to 4 loop
                btn(3)            <= '1';
                btn(2)            <= '1';
                real_clk_soft_spk <= '1';
                real_clk_soft_q   <= to_unsigned(1, 4);
                real_v_soft_spk   <= '1';
                real_v_soft_q     <= to_unsigned(1, 4);
                wait_cycles(1);
                btn(3)            <= '0';
                btn(2)            <= '0';
                real_clk_soft_spk <= '0';
                real_v_soft_spk   <= '0';
                wait_cycles(2);
            end loop;
            wait_cycles(5);
            check(12, (alert_count_out = 2) and (zeroize_led = '1') and (key = x"0000"),
                  "Repeated large weight combo escalated to Key clear (snn_spike=2)");
        end procedure;

        -- TB-13: 3 parameter pattern -> expected: snn_spike = 2, key clear
        procedure task_tb_13 is
        begin
            tb_id <= 13;
            do_reset;
            for burst in 1 to 2 loop
                btn(3) <= '1'; real_clk_soft_spk  <= '1'; real_clk_soft_q  <= to_unsigned(1, 4);
                btn(2) <= '1'; real_v_soft_spk    <= '1'; real_v_soft_q    <= to_unsigned(1, 4);
                btn(1) <= '1'; real_temp_soft_spk <= '1'; real_temp_soft_q <= to_unsigned(1, 4);
                wait_cycles(1);
                btn(3) <= '0'; real_clk_soft_spk  <= '0';
                btn(2) <= '0'; real_v_soft_spk    <= '0';
                btn(1) <= '0'; real_temp_soft_spk <= '0';
                wait_cycles(4);
            end loop;
            wait_cycles(5);
            check(13, (alert_count_out = 2) and (zeroize_led = '1') and (key = x"0000"),
                  "3-parameter pattern escalated to Key clear (snn_spike=2)");
        end procedure;

        -- TB-14: 4 parameter pattern -> expected: snn_spike = 2, key clear
        procedure task_tb_14 is
        begin
            tb_id <= 14;
            do_reset;
            for burst in 1 to 2 loop
                btn(3) <= '1'; real_clk_soft_spk   <= '1'; real_clk_soft_q   <= to_unsigned(1, 4);
                btn(2) <= '1'; real_v_soft_spk     <= '1'; real_v_soft_q     <= to_unsigned(1, 4);
                btn(1) <= '1'; real_temp_soft_spk  <= '1'; real_temp_soft_q  <= to_unsigned(1, 4);
                btn(0) <= '1'; real_probe_soft_spk <= '1'; real_probe_soft_q <= to_unsigned(1, 4);
                wait_cycles(1);
                btn(3) <= '0'; real_clk_soft_spk   <= '0';
                btn(2) <= '0'; real_v_soft_spk     <= '0';
                btn(1) <= '0'; real_temp_soft_spk  <= '0';
                btn(0) <= '0'; real_probe_soft_spk <= '0';
                wait_cycles(4);
            end loop;
            wait_cycles(5);
            check(14, (alert_count_out = 2) and (zeroize_led = '1') and (key = x"0000"),
                  "4-parameter pattern escalated to Key clear (snn_spike=2)");
        end procedure;

        -- TB-15: Decay Behavior (T_DECAY diperkecil untuk simulasi) -> expected: decay to 0, no action
        procedure task_tb_15 is
        begin
            tb_id <= 15;
            do_reset;
            btn(3)            <= '1'; -- 1x pulsa soft (+50)
            real_clk_soft_spk <= '1';
            real_clk_soft_q   <= to_unsigned(1, 4);
            wait_cycles(1);
            btn(3)            <= '0';
            real_clk_soft_spk <= '0';
            wait_cycles(3);

            -- T_DECAY simulasi dipercepat: pulsa leak_tick 15 kali
            for lk in 1 to 15 loop
                leak_tick <= '1';
                wait_cycles(1);
                leak_tick <= '0';
                wait_cycles(2);
            end loop;
            check(15, (snn_v_mem(1) = 0) and (alert_count_out = 0) and (warning_led = '0'),
                  "Monotonic decay to resting state verified (50 -> 0, spike=0)");
        end procedure;

        -- TB-16: Interval < T_decay -> expected: accumulation fires snn_spike = 1
        procedure task_tb_16 is
        begin
            tb_id <= 16;
            do_reset;
            -- 3 pulsa bertahap dengan jeda leak singkat
            for step in 1 to 3 loop
                btn(3)            <= '1';
                real_clk_soft_spk <= '1';
                real_clk_soft_q   <= to_unsigned(1, 4);
                wait_cycles(1);
                btn(3)            <= '0';
                real_clk_soft_spk <= '0';
                wait_cycles(2);
                leak_tick <= '1';
                wait_cycles(1);
                leak_tick <= '0';
                wait_cycles(2);
            end loop;
            -- Pulsa ke-4 tembus threshold (137 >= 128)
            btn(3)            <= '1';
            real_clk_soft_spk <= '1';
            real_clk_soft_q   <= to_unsigned(1, 4);
            wait_cycles(1);
            btn(3)            <= '0';
            real_clk_soft_spk <= '0';
            wait_cycles(4);
            check(16, (alert_count_out = 1) and (warning_led = '1') and (zeroize_led = '0'),
                  "Fast repeat < T_decay accumulated and fired Warning LED (snn_spike=1)");
        end procedure;

    begin
        report "========================================================================" severity note;
        report " Starting tb_scenarios: Complete FSD v2 Anti-Tamper Verification Suite " severity note;
        report " Executing TB-01 through TB-16 Sequentially in One Simulation Window   " severity note;
        report "========================================================================" severity note;

        -- Eksekusi 16 Task Skenario secara berurutan
        task_tb_01;
        task_tb_02;
        task_tb_03;
        task_tb_04;
        task_tb_05;
        task_tb_06;
        task_tb_07;
        task_tb_08;
        task_tb_09;
        task_tb_09_10;
        task_tb_11;
        task_tb_12;
        task_tb_13;
        task_tb_14;
        task_tb_15;
        task_tb_16;

        -- Rekap Hasil PASS / FAIL
        report "========================================================================" severity note;
        report " VERIFICATION RECAP: ALL 16 SCENARIOS EXECUTED!                         " severity note;
        report " Total Passed : " & integer'image(pass_count) & " / 16 scenarios         " severity note;
        report " Total Failed : " & integer'image(fail_count) & " / 16 scenarios         " severity note;
        report "========================================================================" severity note;

        if fail_count = 0 then
            report " >>> ALL 16 SCENARIOS PASSED WITH ZERO FAILURES! <<< " severity note;
        else
            report " >>> SOME SCENARIOS FAILED! PLEASE REVIEW LOGS. <<< " severity error;
        end if;

        sim_done <= true;
        finish; -- $finish equivalent in VHDL-2008 std.env
        wait;
    end process p_main;

end architecture sim;
