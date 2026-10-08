--------------------------------------------------------------------------------
-- File: top.vhd
-- Description: Top-Level Integration of FPGA Anti-Tamper Guard with SNN (FSD v2 §4)
-- Target Board: Digilent Nexys A7-100T (XC7A100TCSG324-1)
-- Toolchain: AMD Vivado 2025.2, VHDL-2008
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.pkg_fsd.all;
use work.pkg_weights_gen.all;

entity top is
    port (
        -- Board Clock and Reset
        CLK100MHZ     : in  std_logic;
        CPU_RESETN    : in  std_logic;
        
        -- Physical User I/O
        SW            : in  std_logic_vector(15 downto 0) := (others => '0');
        BTNC          : in  std_logic := '0';
        BTNU          : in  std_logic := '0';
        BTND          : in  std_logic := '0';
        BTNL          : in  std_logic := '0'; -- Left: Soft Temperature Anomaly
        BTNR          : in  std_logic := '0'; -- Right: Capacitance Probing (Hold to accumulate)
        LED           : out std_logic_vector(15 downto 0);
        
        -- Multi-Color RGB LEDs (LD16, LD17)
        LED16_R       : out std_logic;
        LED16_G       : out std_logic;
        LED16_B       : out std_logic;
        LED17_R       : out std_logic;
        LED17_G       : out std_logic;
        LED17_B       : out std_logic;
        
        -- 7-Segment Display
        AN            : out std_logic_vector(7 downto 0);
        SEG           : out std_logic_vector(6 downto 0);
        DP            : out std_logic
    );
end entity top;

architecture rtl of top is

    -- Clock & Reset Domain Signals
    signal clk100         : std_logic;
    signal clk_core       : std_logic;
    signal mmcm_locked    : std_logic;
    signal rstn           : std_logic := '0';
    signal rstn_core      : std_logic := '0';

    -- Synchronized reset generation
    signal rstn_sync1     : std_logic := '0';
    signal rstn_sync2     : std_logic := '0';
    signal rstn_c_sync1   : std_logic := '0';
    signal rstn_c_sync2   : std_logic := '0';

    -- DRP Signals between mmcm_drp (U7) and clk_gen (U1)
    signal drp_daddr      : std_logic_vector(6 downto 0);
    signal drp_den        : std_logic;
    signal drp_dwe        : std_logic;
    signal drp_di         : std_logic_vector(15 downto 0);
    signal drp_do         : std_logic_vector(15 downto 0);
    signal drp_drdy       : std_logic;
    signal drp_busy       : std_logic;
    signal glitch_act     : std_logic;

    -- Control Configuration Signals (Hardware-Only Standalone Mode)
    signal sensor_mode_cfg: std_logic_vector(1 downto 0) := SENSOR_MODE_C;
    signal arm_cfg        : std_logic := '1';
    signal bypass_cfg     : std_logic := '0';
    signal esc_th_cfg     : unsigned(7 downto 0) := to_unsigned(2, 8);
    signal unlock_p       : std_logic := '0';
    signal key_load_en    : std_logic := '0';
    signal key_data       : std_logic_vector(127 downto 0) := (others => '0');
    signal manual_wipe    : std_logic := '0';
    signal glitch_req     : std_logic := '0';
    signal glitch_div     : unsigned(7 downto 0) := to_unsigned(40, 8);
    signal glitch_dur_us  : unsigned(15 downto 0) := to_unsigned(50, 16);
    signal stress_en      : std_logic := '0';
    signal attack_active  : std_logic := '0';

    -- Hardware Monitor Flags & Spikes
    signal clk_gross_h    : std_logic;
    signal clk_fast_h     : std_logic;
    signal clk_slow_h     : std_logic;
    signal clk_stop_h     : std_logic;
    signal mmcm_unlock_h  : std_logic;
    signal clk_soft_spk   : std_logic;
    signal clk_soft_q     : unsigned(3 downto 0);

    signal v_under_h      : std_logic;
    signal v_over_h       : std_logic;
    signal v_soft_spk     : std_logic;
    signal v_soft_q       : unsigned(3 downto 0);

    -- Victim Core & CDC Handshake
    signal v_req_async    : std_logic;
    signal v_ack_async    : std_logic;
    signal v_digest_async : std_logic_vector(31 downto 0);
    signal v_zeroized     : std_logic;
    signal key_corrupt_h  : std_logic;
    signal xfer_err_event : std_logic;
    
    -- Memory Integrity & Display Signals
    signal key_disp_val   : std_logic_vector(15 downto 0);
    signal key_corrupt_core : std_logic;
    signal cosmic_toggle  : std_logic := '0';
    signal c_tog_sync1    : std_logic := '0';
    signal c_tog_sync2    : std_logic := '0';
    signal c_tog_sync3    : std_logic := '0';
    signal cosmic_flip_core : std_logic := '0';

    -- Synthetic Spikes
    signal synth_spikes   : std_logic_vector(11 downto 0) := (others => '0');
    signal synth_q        : q_array_t := (others => (others => '0'));

    -- Muxed Spikes to SNN
    signal spikes_active  : std_logic_vector(11 downto 0);
    signal spikes_q_mux   : q_array_t;

    -- SNN Core Signals
    signal leak_tick      : std_logic;
    signal snn_fires      : std_logic_vector(3 downto 0);
    signal snn_alert      : std_logic;
    signal snn_class      : std_logic_vector(1 downto 0);
    signal v_membranes    : membrane_array_t;

    -- Active Defense & Response Signals
    signal hard_alert_or  : std_logic;
    signal zeroize_pulse  : std_logic;
    signal is_alert       : std_logic;
    signal is_zeroized    : std_logic;
    signal alert_cnt_out  : unsigned(7 downto 0);
    signal active_class   : std_logic_vector(1 downto 0);
    signal latency_cycles : unsigned(31 downto 0);
    signal heartbeat_led  : std_logic;
    -- Button Edge Detection & Debouncing (20 ms lockout timer @ 100MHz)
    signal btnc_d1, btnc_d2   : std_logic := '0';
    signal btnu_d1, btnu_d2   : std_logic := '0';
    signal btnd_d1, btnd_d2   : std_logic := '0';
    signal btnl_d1, btnl_d2   : std_logic := '0';
    signal btnr_d1, btnr_d2   : std_logic := '0';
    signal btnc_pulse         : std_logic := '0';
    signal btnu_pulse         : std_logic := '0';
    signal btnd_pulse         : std_logic := '0';
    signal btnl_pulse         : std_logic := '0';
    signal btnr_pulse         : std_logic := '0';
    signal btnc_lockout       : unsigned(20 downto 0) := (others => '0');
    signal btnu_lockout       : unsigned(20 downto 0) := (others => '0');
    signal btnd_lockout       : unsigned(20 downto 0) := (others => '0');
    signal btnl_lockout       : unsigned(20 downto 0) := (others => '0');

    -- Capacitance Probing Hold Timer (BTNR: Right Button)
    signal btnr_hold_timer    : unsigned(22 downto 0) := (others => '0');
    signal btnr_hold_pulse    : std_logic := '0';

    -- Switch Edge Detectors & Extreme Trips (SW15, SW14, SW13, SW12)
    signal sw15_d, sw14_d, sw13_d, sw12_d : std_logic := '0';
    signal sw15_edge, sw14_edge, sw13_edge, sw12_edge : std_logic := '0';
    signal sw15_trip, sw14_trip, sw13_trip, sw12_trip : std_logic := '0';
    signal sw_extreme_trip    : std_logic := '0';
    signal seq_manual_spk     : std_logic := '0';
    signal arm_active         : std_logic := '1';

    -- Switch-gated Monitor Flags (SW(0) = Monitor Bypass / Disarm)
    signal g_clk_fast_h       : std_logic;
    signal g_clk_slow_h       : std_logic;
    signal g_clk_stop_h       : std_logic;
    signal g_mmcm_unlock_h    : std_logic;
    signal g_v_under_h        : std_logic;
    signal g_v_over_h         : std_logic;
    signal g_clk_soft_spk     : std_logic;
    signal g_clk_soft_q       : unsigned(3 downto 0);
    signal g_v_soft_spk       : std_logic;
    signal g_v_soft_q         : unsigned(3 downto 0);
    signal g_temp_soft_spk    : std_logic;
    signal g_temp_soft_q      : unsigned(3 downto 0);
    signal g_probe_soft_spk   : std_logic;
    signal g_probe_soft_q     : unsigned(3 downto 0);

    -- Combined zeroize signal to victim core
    signal total_zeroize      : std_logic;

begin

    ----------------------------------------------------------------------------
    -- Reset Synchronizers for clk100 and clk_core
    ----------------------------------------------------------------------------
    p_rst_sync : process(clk100)
    begin
        if rising_edge(clk100) then
            rstn_sync1 <= CPU_RESETN and mmcm_locked;
            rstn_sync2 <= rstn_sync1;
        end if;
    end process p_rst_sync;
    rstn <= rstn_sync2;

    p_rst_core_sync : process(clk_core)
    begin
        if rising_edge(clk_core) then
            rstn_c_sync1 <= CPU_RESETN and mmcm_locked;
            rstn_c_sync2 <= rstn_c_sync1;
        end if;
    end process p_rst_core_sync;
    rstn_core <= rstn_c_sync2;

    -- Combined zeroize pulse (from response escalation OR manual wipe)
    total_zeroize <= zeroize_pulse or manual_wipe;

    -- Active Security Armed State: Armed by default when all switches are DOWN (0)
    arm_active <= arm_cfg and (not SW(0));

    -- CDC Synchronizer for Cosmic Ray Memory Toggle from clk100 to clk_core
    p_cosmic_sync : process(clk_core)
    begin
        if rising_edge(clk_core) then
            if rstn_core = '0' then
                c_tog_sync1      <= '0';
                c_tog_sync2      <= '0';
                c_tog_sync3      <= '0';
                cosmic_flip_core <= '0';
            else
                c_tog_sync1      <= cosmic_toggle;
                c_tog_sync2      <= c_tog_sync1;
                c_tog_sync3      <= c_tog_sync2;
                cosmic_flip_core <= c_tog_sync2 xor c_tog_sync3;
            end if;
        end if;
    end process p_cosmic_sync;

    -- Monitor flags (Active by default, manual pulse from N17 injected directly to SNN Leaky Bucket)
    g_clk_fast_h    <= clk_fast_h and (not SW(0));
    g_clk_slow_h    <= clk_slow_h and (not SW(0));
    g_clk_stop_h    <= clk_stop_h and (not SW(0));
    g_mmcm_unlock_h <= mmcm_unlock_h and (not SW(0));
    g_v_under_h     <= v_under_h and (not SW(0));
    g_v_over_h      <= v_over_h and (not SW(0));
    -- Manual Soft Pulses to SNN Leaky Bucket (+50 water per click):
    -- BTNC (N17): Soft Clock Glitch -> CH_CLK_SOFT
    -- BTND (P18): Memory Cosmic Ray -> CH_CLK_SOFT
    -- BTNU (M18): Soft Voltage Drop -> CH_V_SOFT
    g_clk_soft_spk  <= (clk_soft_spk and (not SW(0))) or btnc_pulse or btnd_pulse;
    g_clk_soft_q    <= to_unsigned(1, 4) when (btnc_pulse = '1' or btnd_pulse = '1') else
                       clk_soft_q when SW(0) = '0' else
                       (others => '0');

    g_v_soft_spk    <= (v_soft_spk and (not SW(0))) or btnu_pulse;
    g_v_soft_q      <= to_unsigned(1, 4) when btnu_pulse = '1' else
                       v_soft_q when SW(0) = '0' else
                       (others => '0');

    -- BTNL (Left): Soft Temperature Anomaly (+50 weight)
    g_temp_soft_spk <= btnl_pulse;
    g_temp_soft_q   <= to_unsigned(1, 4) when btnl_pulse = '1' else (others => '0');

    -- BTNR (Right): Capacitance Probing Sensor (+10 weight per tick, hold to accumulate)
    g_probe_soft_spk <= btnr_pulse or btnr_hold_pulse;
    g_probe_soft_q   <= to_unsigned(1, 4) when (btnr_pulse = '1' or btnr_hold_pulse = '1') else (others => '0');

    -- Extreme Switch Trip Generation:
    -- SW15 (V10): Extreme Clock Fault
    -- SW14 (U11): Extreme Voltage Fault
    -- SW13 (U12): Extreme Thermal / Multi-Stress Fault
    -- SW12 (H6):  Extreme Memory Integrity Fault
    sw15_trip <= sw15_edge or (SW(15) and not sw15_d);
    sw14_trip <= sw14_edge or (SW(14) and not sw14_d);
    sw13_trip <= sw13_edge or (SW(13) and not sw13_d);
    sw12_trip <= sw12_edge or (SW(12) and not sw12_d);

    sw_extreme_trip <= sw15_trip or sw14_trip or sw13_trip or sw12_trip;

    -- OR-reduction of Layer 1 Hard Flags (Extreme Switches directly trip Layer 1!)
    hard_alert_or <= sw_extreme_trip or g_clk_fast_h or g_clk_stop_h or g_mmcm_unlock_h or
                     (g_v_under_h and sensor_mode_cfg(0)) or (g_v_over_h and sensor_mode_cfg(0));

    ----------------------------------------------------------------------------
    -- Physical Button Debounce & Manual Attack Event Generation
    ----------------------------------------------------------------------------
    p_hw_seq : process(clk100)
    begin
        if rising_edge(clk100) then
            if rstn = '0' then
                btnc_d1        <= '0';
                btnc_d2        <= '0';
                btnu_d1        <= '0';
                btnu_d2        <= '0';
                btnd_d1        <= '0';
                btnd_d2        <= '0';
                btnl_d1        <= '0';
                btnl_d2        <= '0';
                btnr_d1        <= '0';
                btnr_d2        <= '0';
                btnc_pulse     <= '0';
                btnu_pulse     <= '0';
                btnd_pulse     <= '0';
                btnl_pulse     <= '0';
                btnr_pulse     <= '0';
                btnc_lockout   <= (others => '0');
                btnu_lockout   <= (others => '0');
                btnd_lockout   <= (others => '0');
                btnl_lockout   <= (others => '0');
                btnr_hold_timer<= (others => '0');
                btnr_hold_pulse<= '0';
                sw15_d         <= SW(15);
                sw14_d         <= SW(14);
                sw13_d         <= SW(13);
                sw12_d         <= SW(12);
                sw15_edge      <= '0';
                sw14_edge      <= '0';
                sw13_edge      <= '0';
                sw12_edge      <= '0';
                seq_manual_spk <= '0';
                cosmic_toggle  <= '0';
            else
                btnc_d1 <= BTNC; btnc_d2 <= btnc_d1;
                btnu_d1 <= BTNU; btnu_d2 <= btnu_d1;
                btnd_d1 <= BTND; btnd_d2 <= btnd_d1;
                btnl_d1 <= BTNL; btnl_d2 <= btnl_d1;
                btnr_d1 <= BTNR; btnr_d2 <= btnr_d1;

                -- Debounced single pulse for BTNC (Center / Soft Clock Glitch)
                if (btnc_d1 = '1' and btnc_d2 = '0' and btnc_lockout = 0) then
                    btnc_pulse   <= '1';
                    btnc_lockout <= to_unsigned(2000000, 21); -- 20 ms debounce lockout
                else
                    btnc_pulse <= '0';
                    if btnc_lockout > 0 then
                        btnc_lockout <= btnc_lockout - 1;
                    end if;
                end if;

                -- Debounced single pulse for BTNU (Up / Soft Voltage Drop)
                if (btnu_d1 = '1' and btnu_d2 = '0' and btnu_lockout = 0) then
                    btnu_pulse   <= '1';
                    btnu_lockout <= to_unsigned(2000000, 21); -- 20 ms debounce lockout
                else
                    btnu_pulse <= '0';
                    if btnu_lockout > 0 then
                        btnu_lockout <= btnu_lockout - 1;
                    end if;
                end if;

                -- Debounced single pulse for BTND (Down / Cosmic Ray SEU)
                if (btnd_d1 = '1' and btnd_d2 = '0' and btnd_lockout = 0) then
                    btnd_pulse   <= '1';
                    btnd_lockout <= to_unsigned(2000000, 21); -- 20 ms debounce lockout
                else
                    btnd_pulse <= '0';
                    if btnd_lockout > 0 then
                        btnd_lockout <= btnd_lockout - 1;
                    end if;
                end if;

                -- Debounced single pulse for BTNL (Left / Soft Thermal Anomaly)
                if (btnl_d1 = '1' and btnl_d2 = '0' and btnl_lockout = 0) then
                    btnl_pulse   <= '1';
                    btnl_lockout <= to_unsigned(2000000, 21); -- 20 ms debounce lockout
                else
                    btnl_pulse <= '0';
                    if btnl_lockout > 0 then
                        btnl_lockout <= btnl_lockout - 1;
                    end if;
                end if;

                -- Continuous hold accumulation for BTNR (Right / Capacitance Probing Sensor)
                -- Initial tap pulse on rising edge:
                if (btnr_d1 = '1' and btnr_d2 = '0') then
                    btnr_pulse      <= '1';
                    btnr_hold_timer <= (others => '0');
                else
                    btnr_pulse <= '0';
                end if;

                -- While held down: inject a small weight tick (+10) every 40 ms (4,000,000 cycles)
                if btnr_d1 = '1' then
                    if btnr_hold_timer >= 3999999 then
                        btnr_hold_timer <= (others => '0');
                        btnr_hold_pulse <= '1';
                    else
                        btnr_hold_timer <= btnr_hold_timer + 1;
                        btnr_hold_pulse <= '0';
                    end if;
                else
                    btnr_hold_timer <= (others => '0');
                    btnr_hold_pulse <= '0';
                end if;

                sw15_d    <= SW(15);
                sw15_edge <= SW(15) and not sw15_d;

                sw14_d    <= SW(14);
                sw14_edge <= SW(14) and not sw14_d;

                sw13_d    <= SW(13);
                sw13_edge <= SW(13) and not sw13_d;

                sw12_d    <= SW(12);
                sw12_edge <= SW(12) and not sw12_d;

                -- Memory bit-flip toggle on BTND (Cosmic Ray SEU)
                if btnd_pulse = '1' then
                    cosmic_toggle <= not cosmic_toggle;
                end if;

                seq_manual_spk <= btnc_pulse or btnd_pulse or btnu_pulse or btnl_pulse or btnr_pulse;
            end if;
        end if;
    end process p_hw_seq;

    ----------------------------------------------------------------------------
    -- U1: Clock Generator (MMCME2_ADV)
    ----------------------------------------------------------------------------
    u_clk_gen : entity work.clk_gen
        port map (
            clk100mhz_in => CLK100MHZ,
            reset_in     => not CPU_RESETN,
            clk100       => clk100,
            clk_core     => clk_core,
            locked       => mmcm_locked,
            drp_daddr    => drp_daddr,
            drp_den      => drp_den,
            drp_dwe      => drp_dwe,
            drp_di       => drp_di,
            drp_do       => drp_do,
            drp_drdy     => drp_drdy
        );

    ----------------------------------------------------------------------------
    -- U7: MMCM DRP Controller (Stable Nominal 25 MHz Core Clock)
    ----------------------------------------------------------------------------
    u_mmcm_drp : entity work.mmcm_drp
        port map (
            clk100        => clk100,
            rstn          => rstn,
            drp_daddr     => drp_daddr,
            drp_den       => drp_den,
            drp_dwe       => drp_dwe,
            drp_di        => drp_di,
            drp_do        => drp_do,
            drp_drdy      => drp_drdy,
            mmcm_locked   => mmcm_locked,
            glitch_req    => '0',
            glitch_div    => to_unsigned(40, 8),
            glitch_dur_us => to_unsigned(0, 16),
            set_div_req   => '0',
            set_div_val   => to_unsigned(40, 8),
            drp_busy      => drp_busy,
            glitch_active => glitch_act
        );

    ----------------------------------------------------------------------------
    -- U3: Clock Monitor (Layer 1)
    ----------------------------------------------------------------------------
    u_mon_clk : entity work.mon_clk
        port map (
            clk100          => clk100,
            rstn            => rstn,
            clk_core_async  => clk_core,
            mmcm_locked     => mmcm_locked,
            wnd_us          => to_unsigned(WND_US_DEFAULT, 16),
            clk_hi_pct      => to_unsigned(CLK_HI_PCT_DEFAULT, 8),
            clk_lo_pct      => to_unsigned(CLK_LO_PCT_DEFAULT, 8),
            clk_soft_th     => to_unsigned(CLK_SOFT_TH_DEFAULT, 8),
            stall_cyc_th    => to_unsigned(STALL_CYC_DEFAULT, 16),
            clk_gross_h     => clk_gross_h,
            clk_fast_h      => clk_fast_h,
            clk_slow_h      => clk_slow_h,
            clk_stop_h      => clk_stop_h,
            mmcm_unlock_h   => mmcm_unlock_h,
            clk_soft_spike  => clk_soft_spk,
            clk_soft_q      => clk_soft_q,
            live_edge_count => open
        );

    ----------------------------------------------------------------------------
    -- U4: Voltage Monitor via XADC DRP (Layer 1)
    ----------------------------------------------------------------------------
    u_mon_volt : entity work.mon_volt
        port map (
            clk100          => clk100,
            rstn            => rstn,
            v_under_th      => V_UNDER_DEFAULT,
            v_over_th       => V_OVER_DEFAULT,
            v_soft_th       => to_unsigned(V_SOFT_TH_DEFAULT, 8),
            v_under_h       => v_under_h,
            v_over_h        => v_over_h,
            v_soft_spike    => v_soft_spk,
            v_soft_q        => v_soft_q,
            vccint_raw_code => open
        );

    ----------------------------------------------------------------------------
    -- U5: Synchronous Power Stressor
    ----------------------------------------------------------------------------
    u_stressor : entity work.stressor
        port map (
            clk100     => clk100,
            rstn       => rstn,
            stress_en  => SW(13),
            active_out => open
        );

    ----------------------------------------------------------------------------
    -- U8: Protected Victim Core (clk_core domain)
    ----------------------------------------------------------------------------
    u_victim : entity work.victim_core
        port map (
            clk_core         => clk_core,
            rstn_core        => rstn_core,
            key_load_en      => key_load_en,
            key_in           => key_data,
            zeroize_pulse    => total_zeroize,
            req_out          => v_req_async,
            ack_in           => v_ack_async,
            digest_out       => v_digest_async,
            zeroized_out     => v_zeroized,
            key_disp         => key_disp_val,
            cosmic_flip_p    => cosmic_flip_core,
            corrupt_inject_h => sw12_trip,
            key_corrupt_out  => key_corrupt_core
        );

    ----------------------------------------------------------------------------
    -- U9: Victim Monitor on clk100 (Layer 1)
    ----------------------------------------------------------------------------
    u_mon_victim : entity work.mon_victim
        port map (
            clk100         => clk100,
            rstn           => rstn,
            req_async      => v_req_async,
            digest_async   => v_digest_async,
            ack_out        => v_ack_async,
            key_corrupt_h  => key_corrupt_h,
            xfer_err_event => xfer_err_event
        );

    ----------------------------------------------------------------------------
    -- U11: Sensor Multiplexer (Modes A, B, C)
    ----------------------------------------------------------------------------
    u_sensor_mux : entity work.sensor_mux
        port map (
            clk100              => clk100,
            rstn                => rstn,
            mode_sel            => sensor_mode_cfg,
            real_clk_fast_h     => g_clk_fast_h,
            real_clk_slow_h     => g_clk_slow_h,
            real_clk_stop_h     => g_clk_stop_h,
            real_mmcm_unlock    => g_mmcm_unlock_h,
            real_v_under_h      => g_v_under_h,
            real_v_over_h       => g_v_over_h,
            real_key_corr_h     => key_corrupt_h or key_corrupt_core,
            real_jtag_h         => '0', -- mon_jtag stretch goal
            real_clk_soft_spk   => g_clk_soft_spk,
            real_clk_soft_q     => g_clk_soft_q,
            real_v_soft_spk     => g_v_soft_spk,
            real_v_soft_q       => g_v_soft_q,
            real_temp_soft_spk  => g_temp_soft_spk,
            real_temp_soft_q    => g_temp_soft_q,
            real_probe_soft_spk => g_probe_soft_spk,
            real_probe_soft_q   => g_probe_soft_q,
            synth_spikes        => synth_spikes,
            synth_q             => synth_q,
            spikes_active       => spikes_active,
            spikes_q_out        => spikes_q_mux
        );

    ----------------------------------------------------------------------------
    -- U12: SNN Layer 3 (4-Neuron LIF Bank)
    ----------------------------------------------------------------------------
    u_snn_lif : entity work.snn_lif
        port map (
            clk100        => clk100,
            rstn          => rstn,
            spikes_active => spikes_active,
            spikes_q      => spikes_q_mux,
            leak_tick     => leak_tick,
            w_we          => '0',
            w_neur_idx    => 0,
            w_ch_idx      => 0,
            w_data        => (others => '0'),
            thetas        => DEFAULT_THETA,
            m_shifts      => DEFAULT_M_SHIFTS,
            fire_out      => snn_fires,
            alert_snn     => snn_alert,
            class_id      => snn_class,
            v_membranes   => v_membranes
        );

    ----------------------------------------------------------------------------
    -- U13: Active Defense & Escalation Response Controller
    ----------------------------------------------------------------------------
    u_response : entity work.response
        port map (
            clk100           => clk100,
            rstn             => rstn,
            hard_alert_l1    => hard_alert_or,
            snn_alert_l3     => snn_alert,
            snn_class_in     => snn_class,
            arm_en           => arm_active,
            bypass_snn       => bypass_cfg,
            esc_th           => esc_th_cfg,
            unlock_pulse     => unlock_p,
            attack_active    => sw_extreme_trip,
            zeroize_pulse    => zeroize_pulse,
            alert_latched    => is_alert,
            zeroized_latched => is_zeroized,
            alert_count_out  => alert_cnt_out,
            class_out        => active_class,
            latency_cycles   => latency_cycles,
            led_alert        => open,
            led_zeroized     => open
        );

    ----------------------------------------------------------------------------
    -- U14: Telemetry & 7-Segment Controller
    ----------------------------------------------------------------------------
    u_telemetry : entity work.telemetry
        port map (
            clk100          => clk100,
            rstn            => rstn,
            leak_tick_out   => leak_tick,
            heartbeat_led   => heartbeat_led,
            arm_status      => arm_active,
            alert_status    => is_alert,
            zeroize_status  => is_zeroized or v_zeroized,
            active_class    => active_class,
            v_n1_membrane   => v_membranes(1),
            key_display     => key_disp_val,
            seg_an          => AN,
            seg_cath        => SEG,
            seg_dp          => DP
        );

    ----------------------------------------------------------------------------
    -- Multi-Color RGB LEDs (LD16 & LD17) Security State Indication
    ----------------------------------------------------------------------------
    -- Normal Armed: Solid GREEN
    -- Warning / Alert: Bright YELLOW (Red + Green)
    -- GSR Zeroized: Solid RED (Hazard / Keys Wiped)
    p_rgb : process(is_zeroized, v_zeroized, is_alert, arm_active)
    begin
        if (is_zeroized = '1' or v_zeroized = '1') then
            -- RED (GSR Zeroize Active)
            LED16_R <= '1';
            LED16_G <= '0';
            LED16_B <= '0';
            LED17_R <= '1';
            LED17_G <= '0';
            LED17_B <= '0';
        elsif is_alert = '1' then
            -- YELLOW (Warning / Alert)
            LED16_R <= '1';
            LED16_G <= '1';
            LED16_B <= '0';
            LED17_R <= '1';
            LED17_G <= '1';
            LED17_B <= '0';
        elsif arm_active = '1' then
            -- GREEN (Normal Armed)
            LED16_R <= '0';
            LED16_G <= '1';
            LED16_B <= '0';
            LED17_R <= '0';
            LED17_G <= '1';
            LED17_B <= '0';
        else
            -- BLUE (Disarmed)
            LED16_R <= '0';
            LED16_G <= '0';
            LED16_B <= '1';
            LED17_R <= '0';
            LED17_G <= '0';
            LED17_B <= '1';
        end if;
    end process p_rgb;

    ----------------------------------------------------------------------------
    -- Output LED Status Mapping (FSD v2 §10)
    ----------------------------------------------------------------------------
    LED(0)  <= heartbeat_led;
    LED(1)  <= mmcm_locked;
    LED(2)  <= arm_active;
    LED(3)  <= sensor_mode_cfg(1); -- Mode ind
    LED(4)  <= clk_fast_h or clk_slow_h;
    LED(5)  <= clk_soft_spk;
    LED(6)  <= v_soft_spk;
    LED(7)  <= snn_fires(0);
    LED(8)  <= snn_fires(1); -- N1 Fire (SCEN2 headline)
    LED(9)  <= snn_fires(2); -- N2 Fire
    LED(10) <= snn_fires(3);
    LED(11) <= glitch_act;
    LED(12) <= '0';                                        -- LED 12 (Pin V15 idle)
    LED(13) <= '0';                                        -- LED 13 (Pin V14 idle)
    LED(14) <= is_zeroized or v_zeroized;                  -- GSR ACTIVE (LED14 ON, Red Hazard)
    LED(15) <= is_alert and not (is_zeroized or v_zeroized); -- WARNING ACTIVE (LED15 ON only when 1 spike warning)

end architecture rtl;
