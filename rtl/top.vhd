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
        SW            : in  std_logic_vector(15 downto 0);
        BTNC          : in  std_logic;
        BTNU          : in  std_logic;
        BTND          : in  std_logic;
        LED           : out std_logic_vector(15 downto 0);
        
        -- 7-Segment Display
        AN            : out std_logic_vector(7 downto 0);
        SEG           : out std_logic_vector(6 downto 0);
        DP            : out std_logic;
        
        -- USB-UART Interface
        UART_TXD_IN   : out std_logic; -- FPGA TX -> FTDI RX
        UART_RXD_OUT  : in  std_logic  -- FTDI TX -> FPGA RX
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

    -- UART & Parser Signals
    signal rx_byte        : std_logic_vector(7 downto 0);
    signal rx_valid       : std_logic;
    signal tx_byte        : std_logic_vector(7 downto 0);
    signal tx_valid       : std_logic;
    signal tx_ready       : std_logic;

    -- Control Registers
    signal sensor_mode_cfg: std_logic_vector(1 downto 0);
    signal arm_cfg        : std_logic;
    signal bypass_cfg     : std_logic;
    signal esc_th_cfg     : unsigned(7 downto 0);
    signal unlock_p       : std_logic;
    signal key_load_en    : std_logic;
    signal key_data       : std_logic_vector(127 downto 0);
    signal manual_wipe    : std_logic;
    signal glitch_req     : std_logic;
    signal glitch_div     : unsigned(7 downto 0);
    signal glitch_dur_us  : unsigned(15 downto 0);
    signal stress_en      : std_logic;
    signal attack_active  : std_logic;
    signal log_mode       : std_logic_vector(1 downto 0);

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

    -- Synthetic Spikes
    signal synth_spikes   : std_logic_vector(11 downto 0);
    signal synth_q        : q_array_t;

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

    -- Combined zeroize signal to victim core
    signal total_zeroize  : std_logic;

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

    -- Combined zeroize pulse (from response escalation OR manual UART wipe)
    total_zeroize <= zeroize_pulse or manual_wipe;

    -- OR-reduction of all Layer 1 Hard Flags
    hard_alert_or <= clk_gross_h or clk_fast_h or clk_slow_h or clk_stop_h or
                     mmcm_unlock_h or v_under_h or v_over_h or key_corrupt_h;

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
    -- U7: MMCM DRP Controller
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
            glitch_req    => glitch_req or BTNC, -- Button BTNC triggers manual glitch
            glitch_div    => glitch_div,
            glitch_dur_us => glitch_dur_us,
            set_div_req   => '0',
            set_div_val   => to_unsigned(40, 8),
            drp_busy      => drp_busy,
            glitch_active => glitch_act
        );

    ----------------------------------------------------------------------------
    -- U2: UART Host Interface (115200-8N1)
    ----------------------------------------------------------------------------
    u_uart : entity work.uart_host
        port map (
            clk100      => clk100,
            rstn        => rstn,
            uart_rx_pin => UART_RXD_OUT,
            uart_tx_pin => UART_TXD_IN,
            rx_byte     => rx_byte,
            rx_valid    => rx_valid,
            tx_byte     => tx_byte,
            tx_valid    => tx_valid,
            tx_ready    => tx_ready
        );

    ----------------------------------------------------------------------------
    -- U2b: Command Parser & Preset Sequencer
    ----------------------------------------------------------------------------
    u_parser : entity work.cmd_parser
        port map (
            clk100        => clk100,
            rstn          => rstn,
            rx_byte       => rx_byte,
            rx_valid      => rx_valid,
            tx_byte       => tx_byte,
            tx_valid      => tx_valid,
            tx_ready      => tx_ready,
            sensor_mode   => sensor_mode_cfg,
            arm_en        => arm_cfg,
            bypass_snn    => bypass_cfg,
            esc_th        => esc_th_cfg,
            unlock_pulse  => unlock_p,
            key_load_en   => key_load_en,
            key_data      => key_data,
            manual_wipe   => manual_wipe,
            synth_spikes  => synth_spikes,
            synth_q       => synth_q,
            glitch_req    => glitch_req,
            glitch_div    => glitch_div,
            glitch_dur_us => glitch_dur_us,
            stress_en     => stress_en,
            attack_active => attack_active,
            log_mode      => log_mode
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
            stress_en  => stress_en,
            active_out => open
        );

    ----------------------------------------------------------------------------
    -- U8: Protected Victim Core (clk_core domain)
    ----------------------------------------------------------------------------
    u_victim : entity work.victim_core
        port map (
            clk_core      => clk_core,
            rstn_core     => rstn_core,
            key_load_en   => key_load_en,
            key_in        => key_data,
            zeroize_pulse => total_zeroize,
            req_out       => v_req_async,
            ack_in        => v_ack_async,
            digest_out    => v_digest_async,
            zeroized_out  => v_zeroized
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
            clk100            => clk100,
            rstn              => rstn,
            mode_sel          => sensor_mode_cfg,
            real_clk_fast_h   => clk_fast_h,
            real_clk_slow_h   => clk_slow_h,
            real_clk_stop_h   => clk_stop_h,
            real_mmcm_unlock  => mmcm_unlock_h,
            real_v_under_h    => v_under_h,
            real_v_over_h     => v_over_h,
            real_key_corr_h   => key_corrupt_h,
            real_jtag_h       => '0', -- mon_jtag stretch goal
            real_clk_soft_spk => clk_soft_spk,
            real_clk_soft_q   => clk_soft_q,
            real_v_soft_spk   => v_soft_spk,
            real_v_soft_q     => v_soft_q,
            synth_spikes      => synth_spikes,
            synth_q           => synth_q,
            spikes_active     => spikes_active,
            spikes_q_out      => spikes_q_mux
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
            arm_en           => arm_cfg and SW(0),
            bypass_snn       => bypass_cfg or SW(1),
            esc_th           => esc_th_cfg,
            unlock_pulse     => unlock_p,
            attack_active    => attack_active or BTND,
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
            clk100         => clk100,
            rstn           => rstn,
            leak_tick_out  => leak_tick,
            heartbeat_led  => heartbeat_led,
            arm_status     => arm_cfg and SW(0),
            alert_status   => is_alert,
            zeroize_status => is_zeroized or v_zeroized,
            active_class   => active_class,
            v_n1_membrane  => v_membranes(1),
            seg_an         => AN,
            seg_cath       => SEG,
            seg_dp         => DP
        );

    ----------------------------------------------------------------------------
    -- Output LED Status Mapping (FSD v2 §10)
    ----------------------------------------------------------------------------
    LED(0)  <= heartbeat_led;
    LED(1)  <= mmcm_locked;
    LED(2)  <= arm_cfg and SW(0);
    LED(3)  <= sensor_mode_cfg(1); -- Mode ind
    LED(4)  <= clk_fast_h or clk_slow_h;
    LED(5)  <= clk_soft_spk;
    LED(6)  <= v_soft_spk;
    LED(7)  <= snn_fires(0);
    LED(8)  <= snn_fires(1); -- N1 Fire (SCEN2 headline)
    LED(9)  <= snn_fires(2); -- N2 Fire
    LED(10) <= snn_fires(3);
    LED(11) <= glitch_act;
    LED(12) <= attack_active;
    LED(13) <= stress_en;
    LED(14) <= is_zeroized or v_zeroized;
    LED(15) <= is_alert;

end architecture rtl;
