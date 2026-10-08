--------------------------------------------------------------------------------
-- File: snn_top.vhd
-- Description: Top-Level SNN Anti-Tamper System on Digilent Nexys A7-100T
-- Integrates:
--  1. Sensors (XADC DRP, RO Sensor, BRAM Monitor)
--  2. On-Chip Tamper Emulator with Thermal Safety Interlock
--  3. SNN Feature Extractor (8 Features Q16.16)
--  4. 14-Channel Spike Encoder
--  5. 1-Neuron LIF (Integer Bit-Exact, Leaky Integrate-and-Fire)
--  6. Sliding Window Accumulator & Temporal Alarm FSM
--  7. Response Unit & Protected Core (Zeroize in <= 2 cycles)
--  8. UART Telemetry and Emulator CLI (921600 baud)
--  9. Nexys A7 Board Peripheral Mapping & Status LEDs
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.snn_params_pkg.all;
use work.snn_weights_pkg.all;

entity snn_top is
    port (
        clk100mhz : in  std_logic;                    -- E3 pin
        cpu_resetn: in  std_logic;                    -- C12 pin (Active Low button)
        
        -- Nexys A7 Board Switches (Optional Override/Controls)
        sw        : in  std_logic_vector(15 downto 0);
        
        -- Nexys A7 Board LEDs
        led       : out std_logic_vector(15 downto 0);
        
        -- RGB LEDs (LD16, LD17)
        led16_r   : out std_logic;
        led16_g   : out std_logic;
        led16_b   : out std_logic;
        led17_r   : out std_logic;
        led17_g   : out std_logic;
        led17_b   : out std_logic;
        
        -- UART Interface to Host PC (USB-UART Bridge)
        uart_rx   : in  std_logic;                    -- C4 pin
        uart_tx   : out std_logic                     -- D4 pin
    );
end entity snn_top;

architecture rtl of snn_top is

    -- Synchronous Reset
    signal rst_sync_n : std_logic_vector(1 downto 0) := "00";
    signal sys_rst    : std_logic;

    -- Sensor Signals
    signal s_tick       : std_logic;
    signal s_t_raw      : unsigned(15 downto 0);
    signal s_v_raw      : unsigned(15 downto 0);
    signal s_f_raw      : unsigned(15 downto 0);
    signal s_m_raw      : unsigned(7 downto 0);
    signal s_bram_busy  : std_logic;
    
    -- Emulator Signals
    signal emu_active   : std_logic;
    signal emu_mode     : std_logic_vector(3 downto 0);
    signal emu_waster_en: std_logic;
    signal emu_waster_lv: unsigned(3 downto 0);
    signal emu_skew_en  : std_logic;
    signal emu_bram_inj : std_logic;
    signal emu_thermal_trip : std_logic;
    
    -- Feature Extraction Signals
    signal s_feat_valid : std_logic;
    signal s_t_dev      : signed(15 downto 0);
    signal s_t_trend    : signed(15 downto 0);
    signal s_v_dev      : signed(15 downto 0);
    signal s_v_step     : signed(15 downto 0);
    signal s_v_noise    : signed(15 downto 0);
    signal s_f_dev      : signed(15 downto 0);
    signal s_f_noise    : signed(15 downto 0);
    signal s_m_val      : unsigned(7 downto 0);
    
    -- Spike Encoder Signals
    signal s_spk_valid  : std_logic;
    signal s_spikes     : std_logic_vector(13 downto 0);
    
    -- LIF Neuron Signals
    signal s_step_done  : std_logic;
    signal s_spike_out  : std_logic;
    signal s_v_mem      : signed(15 downto 0);
    
    -- Alarm FSM Signals
    signal s_alarm_state   : std_logic_vector(1 downto 0);
    signal s_spike_count   : unsigned(15 downto 0);
    signal s_alarm_trigger : std_logic;
    signal s_alarm_latched : std_logic;
    signal s_hard_backstop : std_logic;
    
    -- Response & Protected Core Signals
    signal s_zeroize_pulse  : std_logic;
    signal s_zeroize_active : std_logic;
    signal s_core_disable   : std_logic;
    signal s_tamper_flag    : std_logic;
    signal s_key_zeroized   : std_logic;
    
    -- Heartbeat Divider
    signal hb_counter       : unsigned(26 downto 0) := (others => '0');

    -- UART / Logger Signals
    signal cmd_start_emu    : std_logic;
    signal cmd_stop_emu     : std_logic;
    signal cmd_scenario     : std_logic_vector(3 downto 0);
    signal tx_data          : std_logic_vector(7 downto 0);
    signal tx_valid         : std_logic;
    signal tx_ready         : std_logic;
    signal rx_byte          : std_logic_vector(7 downto 0);
    signal rx_valid         : std_logic;

begin

    ----------------------------------------------------------------------------
    -- Reset Synchronizer (Active-High Internal Reset from Active-Low CPU_RESETN)
    ----------------------------------------------------------------------------
    process(clk100mhz)
    begin
        if rising_edge(clk100mhz) then
            rst_sync_n <= rst_sync_n(0) & cpu_resetn;
        end if;
    end process;
    sys_rst <= not rst_sync_n(1);

    ----------------------------------------------------------------------------
    -- Heartbeat Counter
    ----------------------------------------------------------------------------
    process(clk100mhz)
    begin
        if rising_edge(clk100mhz) then
            if sys_rst = '1' then
                hb_counter <= (others => '0');
            else
                hb_counter <= hb_counter + 1;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- 1. Sensor Subsystems
    ----------------------------------------------------------------------------
    u_xadc : entity work.xadc_if
        port map (
            clk        => clk100mhz,
            rst        => sys_rst,
            eos_tick   => s_tick,
            temp_out   => s_t_raw,
            vccint_out => s_v_raw
        );

    u_ro : entity work.ro_sensor
        generic map (
            WINDOW_BITS => RO_WINDOW_BITS
        )
        port map (
            clk       => clk100mhz,
            rst       => sys_rst,
            skew_en   => emu_skew_en,
            ro_count  => s_f_raw
        );

    u_bram : entity work.bram_monitor
        port map (
            clk          => clk100mhz,
            rst          => sys_rst,
            fault_inject => emu_bram_inj,
            fault_count  => s_m_raw,
            scrub_busy   => s_bram_busy
        );

    ----------------------------------------------------------------------------
    -- 2. On-Chip Tamper Emulator
    ----------------------------------------------------------------------------
    u_emu : entity work.tamper_emulator
        port map (
            clk             => clk100mhz,
            rst             => sys_rst,
            start_cmd       => cmd_start_emu,
            stop_cmd        => cmd_stop_emu,
            scenario_sel    => cmd_scenario,
            curr_temp       => s_t_raw,
            waster_en       => emu_waster_en,
            waster_duty     => emu_waster_lv,
            skew_en         => emu_skew_en,
            bram_inject     => emu_bram_inj,
            thermal_trip    => emu_thermal_trip,
            emu_running     => emu_active,
            active_scenario => emu_mode
        );

    ----------------------------------------------------------------------------
    -- 3. Hard Backstop Detector
    ----------------------------------------------------------------------------
    s_hard_backstop <= '1' when (to_integer(s_v_raw) < VCCINT_MIN_CODE or 
                                 to_integer(s_v_raw) > VCCINT_MAX_CODE or 
                                 to_integer(s_m_raw) >= M_HARD_WORDS) else '0';

    ----------------------------------------------------------------------------
    -- 4. SNN Feature Extraction Unit
    ----------------------------------------------------------------------------
    u_feat : entity work.feature_unit
        port map (
            clk        => clk100mhz,
            rst        => sys_rst,
            tick       => s_tick,
            t_raw      => s_t_raw,
            v_raw      => s_v_raw,
            f_raw      => s_f_raw,
            m_raw      => s_m_raw,
            ref_t      => to_signed(2570, 16),
            ref_v      => to_signed(1365, 16),
            ref_f      => to_signed(15000, 16),
            feat_valid => s_feat_valid,
            t_dev      => s_t_dev,
            t_trend    => s_t_trend,
            v_dev      => s_v_dev,
            v_step     => s_v_step,
            v_noise    => s_v_noise,
            f_dev      => s_f_dev,
            f_noise    => s_f_noise,
            m_val      => s_m_val
        );

    ----------------------------------------------------------------------------
    -- 5. Spike Encoder
    ----------------------------------------------------------------------------
    u_enc : entity work.spike_encoder
        port map (
            clk          => clk100mhz,
            rst          => sys_rst,
            feat_valid   => s_feat_valid,
            t_dev        => s_t_dev,
            t_trend      => s_t_trend,
            v_dev        => s_v_dev,
            v_step       => s_v_step,
            v_noise      => s_v_noise,
            f_dev        => s_f_dev,
            f_noise      => s_f_noise,
            m_val        => s_m_val,
            spikes_valid => s_spk_valid,
            spikes       => s_spikes
        );

    ----------------------------------------------------------------------------
    -- 6. LIF Neuron
    ----------------------------------------------------------------------------
    u_lif : entity work.lif_neuron
        port map (
            clk          => clk100mhz,
            rst          => sys_rst,
            spikes_valid => s_spk_valid,
            spikes       => s_spikes,
            step_done    => s_step_done,
            spike_out    => s_spike_out,
            v_mem_out    => s_v_mem
        );

    ----------------------------------------------------------------------------
    -- 7. Temporal Alarm FSM
    ----------------------------------------------------------------------------
    u_fsm : entity work.alarm_fsm
        port map (
            clk           => clk100mhz,
            rst           => sys_rst,
            step_done     => s_step_done,
            spike_in      => s_spike_out,
            hard_backstop => s_hard_backstop,
            alarm_state   => s_alarm_state,
            spike_count   => s_spike_count,
            alarm_trigger => s_alarm_trigger,
            alarm_latched => s_alarm_latched
        );

    ----------------------------------------------------------------------------
    -- 8. Active Response Unit & Protected Core
    ----------------------------------------------------------------------------
    u_resp : entity work.response_unit
        port map (
            clk            => clk100mhz,
            rst            => sys_rst,
            alarm_trigger  => s_alarm_trigger,
            alarm_latched  => s_alarm_latched,
            zeroize_pulse  => s_zeroize_pulse,
            zeroize_active => s_zeroize_active,
            core_disable   => s_core_disable,
            tamper_flag    => s_tamper_flag
        );

    u_core : entity work.protected_core
        port map (
            clk          => clk100mhz,
            rst          => sys_rst,
            zeroize      => s_zeroize_pulse,
            disable      => s_core_disable,
            data_in      => x"55AA1234",
            data_valid   => '1',
            data_out     => open,
            data_ready   => open,
            key_zeroized => s_key_zeroized
        );

    ----------------------------------------------------------------------------
    -- 9. UART Telemetry and Logger
    ----------------------------------------------------------------------------
    u_uart_rx : entity work.uart_rx
        generic map (
            CLK_FREQ  => CLK_FREQ_HZ,
            BAUD_RATE => BAUD_RATE_LOGGER
        )
        port map (
            clk      => clk100mhz,
            rst      => sys_rst,
            rx       => uart_rx,
            data_out => rx_byte,
            valid    => rx_valid
        );

    u_cmd : entity work.cmd_parser
        port map (
            clk       => clk100mhz,
            rst       => sys_rst,
            rx_data   => rx_byte,
            rx_valid  => rx_valid,
            cmd_start => cmd_start_emu,
            cmd_stop  => cmd_stop_emu,
            cmd_scen  => cmd_scenario
        );

    u_logger : entity work.logger
        port map (
            clk       => clk100mhz,
            rst       => sys_rst,
            tick      => s_tick,
            temp_in   => s_t_raw,
            vcc_in    => s_v_raw,
            ro_in     => s_f_raw,
            bram_in   => s_m_raw,
            flags_in  => s_alarm_state & s_tamper_flag & s_key_zeroized & emu_active & emu_mode(2 downto 0),
            tx_data   => tx_data,
            tx_valid  => tx_valid,
            tx_ready  => tx_ready
        );

    u_uart_tx : entity work.uart_tx
        generic map (
            CLK_FREQ  => CLK_FREQ_HZ,
            BAUD_RATE => BAUD_RATE_LOGGER
        )
        port map (
            clk      => clk100mhz,
            rst      => sys_rst,
            tx_start => tx_valid,
            tx_data  => tx_data,
            tx       => uart_tx,
            tx_busy  => open,
            tx_done  => tx_ready
        );

    ----------------------------------------------------------------------------
    -- 10. Board LED Indicators
    ----------------------------------------------------------------------------
    led(0)  <= hb_counter(26);            -- Heartbeat LED (~0.74 Hz)
    led(1)  <= s_tick;                    -- Tick activity
    led(2)  <= s_bram_busy;               -- BRAM scrubbing activity
    led(3)  <= emu_active;                -- Emulator active
    led(4)  <= emu_thermal_trip;          -- Thermal safety trip
    led(5)  <= s_hard_backstop;           -- Hard backstop trip
    led(6)  <= s_spike_out;               -- SNN LIF spike output pulse
    led(7)  <= s_key_zeroized;            -- Key zeroized status
    led(8)  <= s_alarm_state(0);          -- SUSPECT indicator
    led(9)  <= s_alarm_state(1);          -- ALARM indicator
    led(10) <= s_tamper_flag;             -- Tamper response active
    led(15 downto 11) <= (others => '0');

    -- RGB LED 16: SNN Alarm State Indicator
    -- Green: NORMAL, Yellow: SUSPECT, Red: ALARM
    led16_r <= '1' when (s_alarm_state = "01" or s_alarm_state = "10") else '0';
    led16_g <= '1' when (s_alarm_state = "00" or s_alarm_state = "01") else '0';
    led16_b <= '0';

    -- RGB LED 17: Security Status Indicator
    -- Green: SECURE, Red: TAMPERED / ZEROIZED
    led17_r <= s_tamper_flag or s_key_zeroized;
    led17_g <= not (s_tamper_flag or s_key_zeroized);
    led17_b <= '0';

end architecture rtl;
