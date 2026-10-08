-- logger_top.vhd
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.snn_params_pkg.all;

entity logger_top is
    port (
        CLK100MHZ       : in  std_logic;
        CPU_RESETN      : in  std_logic;
        SW              : in  std_logic_vector(1 downto 0); -- SW(1): Enable Logger
        UART_TXD_IN    : out std_logic; -- FPGA TX to FTDI RX
        UART_RXD_OUT   : in  std_logic; -- FTDI TX to FPGA RX
        LED             : out std_logic_vector(3 downto 0)
    );
end entity logger_top;

architecture rtl of logger_top is
    signal rst_sync1    : std_logic := '1';
    signal rst          : std_logic := '1';

    signal tick         : std_logic;
    signal temp_code    : unsigned(11 downto 0);
    signal vccint_code  : unsigned(11 downto 0);
    signal ro_count     : unsigned(15 downto 0);
    signal bad_words    : unsigned(7 downto 0);

    signal logger_tick : std_logic;
    signal flags       : std_logic_vector(7 downto 0);

    signal tx_data     : std_logic_vector(7 downto 0);
    signal tx_valid    : std_logic;
    signal tx_ready    : std_logic;

    signal rx_data     : std_logic_vector(7 downto 0);
    signal rx_valid    : std_logic;

    signal waster_en    : std_logic;
    signal waster_duty  : unsigned(3 downto 0);
    signal waster_pulse : std_logic;
    signal skew_en      : std_logic;
    signal skew_rate    : unsigned(7 downto 0);
    signal flip_en      : std_logic;
    signal flip_addr    : unsigned(9 downto 0);
    signal flip_bit     : integer range 0 to 31;

    signal skew_skip    : std_logic;
    signal emu_active   : std_logic;

    signal heartbeat   : unsigned(25 downto 0) := (others => '0');
begin

    -- Synchronous Reset Conditioner
    p_rst: process(CLK100MHZ)
    begin
        if rising_edge(CLK100MHZ) then
            rst_sync1 <= not CPU_RESETN;
            rst       <= rst_sync1;
        end if;
    end process p_rst;

    -- XADC Interface
    u_xadc: entity work.xadc_if
        port map (
            clk             => CLK100MHZ,
            rst             => rst,
            tick_out        => tick,
            temp_code_out   => temp_code,
            vccint_code_out => vccint_code,
            sim_override    => '0',
            sim_tick        => '0',
            sim_temp_code   => (others => '0'),
            sim_vccint_code => (others => '0')
        );

    -- Ring Oscillator Sensor
    u_ro: entity work.ro_sensor
        port map (
            clk           => CLK100MHZ,
            rst           => rst,
            tick_in       => tick,
            skew_skip     => skew_skip,
            ro_count_out => ro_count
        );

    -- BRAM Integrity Monitor
    u_bram: entity work.bram_monitor
        port map (
            clk             => CLK100MHZ,
            rst             => rst,
            tick_in         => tick,
            inj_en          => flip_en,
            inj_addr        => flip_addr,
            inj_bit         => flip_bit,
            bad_words_out  => bad_words
        );

    -- Tamper Emulator
    u_emu: entity work.tamper_emulator
        port map (
            clk                => CLK100MHZ,
            rst                => rst,
            temp_code         => temp_code,
            waster_en        => waster_en,
            waster_duty      => waster_duty,
            waster_pulsed    => waster_pulse,
            skew_en          => skew_en,
            skew_rate        => skew_rate,
            flip_en          => flip_en,
            flip_addr        => flip_addr,
            flip_bit         => flip_bit,
            skew_skip_out    => skew_skip,
            bram_inj_en_out  => open,
            bram_inj_addr_out=> open,
            bram_inj_bit_out => open,
            emu_active_out   => emu_active
        );

    -- UART RX for remote commands
    u_uart_rx: entity work.uart_rx
        generic map (
            CLK_FREQ  => CLK_FREQ_HZ,
            BAUD_RATE => BAUD_RATE_LOGGER
        )
        port map (
            clk      => CLK100MHZ,
            rst      => rst,
            rxd      => UART_RXD_OUT,
            rx_data  => rx_data,
            rx_valid => rx_valid
        );

    -- Command Parser
    u_cmd: entity work.cmd_parser
        port map (
            clk                => CLK100MHZ,
            rst                => rst,
            rx_data            => rx_data,
            rx_valid           => rx_valid,
            waster_en        => waster_en,
            waster_duty      => waster_duty,
            waster_pulsed    => waster_pulse,
            skew_en          => skew_en,
            skew_rate        => skew_rate,
            flip_en          => flip_en,
            flip_addr        => flip_addr,
            flip_bit         => flip_bit
        );

    logger_tick <= tick and SW(1);
    flags       <= "000000" & emu_active & SW(1);

    -- Logger Frame Packer
    u_logger: entity work.logger
        port map (
            clk         => CLK100MHZ,
            rst         => rst,
            tick_in     => logger_tick,
            temp_code    => temp_code,
            vccint_code  => vccint_code,
            ro_count     => ro_count,
            bad_words    => bad_words,
            flags        => flags,
            tx_data      => tx_data,
            tx_valid     => tx_valid,
            tx_ready     => tx_ready
        );

    -- UART TX at 921600 Baud
    u_uart_tx: entity work.uart_tx
        generic map (
            CLK_FREQ  => CLK_FREQ_HZ,
            BAUD_RATE => BAUD_RATE_LOGGER
        )
        port map (
            clk      => CLK100MHZ,
            rst      => rst,
            tx_data  => tx_data,
            tx_valid => tx_valid,
            tx_ready => tx_ready,
            txd      => UART_TXD_IN
        );

    -- Heartbeat & Status LEDs
    p_led: process(CLK100MHZ)
    begin
        if rising_edge(CLK100MHZ) then
            heartbeat <= heartbeat + 1;
        end if;
    end process p_led;

    LED(0) <= heartbeat(25);
    LED(1) <= SW(1);
    LED(2) <= tick;
    LED(3) <= emu_active;

end architecture rtl;
