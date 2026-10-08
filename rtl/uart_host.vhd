--------------------------------------------------------------------------------
-- File: uart_host.vhd
-- Description: U2 Host UART Interface 115200-8N1 (FSD v2 §6-U2 & §8)
-- Features: 2FF CDC synchronization on RX, Baud Rate Generator, TX/RX Byte Interfaces
-- Clock Domain: clk100
-- Standard: VHDL-2008, IEEE numeric_std
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.pkg_fsd.all;

entity uart_host is
    generic (
        CLKS_PER_BIT : natural := 868 -- 100 MHz / 115200 baud = 868.05
    );
    port (
        clk100      : in  std_logic;
        rstn        : in  std_logic;
        
        -- Physical UART Pins (Nexys A7 USB-UART bridge)
        uart_rx_pin : in  std_logic;
        uart_tx_pin : out std_logic;
        
        -- Byte Interface to cmd_parser / telemetry
        rx_byte     : out std_logic_vector(7 downto 0);
        rx_valid    : out std_logic;
        
        tx_byte     : in  std_logic_vector(7 downto 0);
        tx_valid    : in  std_logic;
        tx_ready    : out std_logic
    );
end entity uart_host;

architecture rtl of uart_host is

    -- RX Synchronizer (2-FF)
    signal rx_sync1 : std_logic := '1';
    signal rx_sync2 : std_logic := '1';
    attribute ASYNC_REG : string;
    attribute ASYNC_REG of rx_sync1 : signal is "TRUE";
    attribute ASYNC_REG of rx_sync2 : signal is "TRUE";

    -- RX State Machine
    type rx_state_t is (RX_IDLE, RX_START, RX_DATA, RX_STOP);
    signal rx_state     : rx_state_t := RX_IDLE;
    signal rx_clk_cnt   : integer range 0 to CLKS_PER_BIT := 0;
    signal rx_bit_idx   : integer range 0 to 7 := 0;
    signal rx_shifter   : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_valid_reg : std_logic := '0';

    -- TX State Machine
    type tx_state_t is (TX_IDLE, TX_START, TX_DATA, TX_STOP);
    signal tx_state     : tx_state_t := TX_IDLE;
    signal tx_clk_cnt   : integer range 0 to CLKS_PER_BIT := 0;
    signal tx_bit_idx   : integer range 0 to 7 := 0;
    signal tx_shifter   : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_pin_reg   : std_logic := '1';

begin

    uart_tx_pin <= tx_pin_reg;
    rx_valid    <= rx_valid_reg;

    ----------------------------------------------------------------------------
    -- 2-FF CDC Synchronizer for RX Pin
    ----------------------------------------------------------------------------
    p_rx_sync : process(clk100)
    begin
        if rising_edge(clk100) then
            if rstn = '0' then
                rx_sync1 <= '1';
                rx_sync2 <= '1';
            else
                rx_sync1 <= uart_rx_pin;
                rx_sync2 <= rx_sync1;
            end if;
        end if;
    end process p_rx_sync;

    ----------------------------------------------------------------------------
    -- UART Receiver Process
    ----------------------------------------------------------------------------
    p_rx : process(clk100)
    begin
        if rising_edge(clk100) then
            if rstn = '0' then
                rx_state     <= RX_IDLE;
                rx_clk_cnt   <= 0;
                rx_bit_idx   <= 0;
                rx_valid_reg <= '0';
                rx_byte      <= (others => '0');
            else
                rx_valid_reg <= '0';

                case rx_state is
                    when RX_IDLE =>
                        rx_clk_cnt <= 0;
                        rx_bit_idx <= 0;
                        if rx_sync2 = '0' then -- Start bit detected
                            rx_state <= RX_START;
                        end if;

                    when RX_START =>
                        -- Sample in the middle of start bit
                        if rx_clk_cnt = (CLKS_PER_BIT / 2) then
                            if rx_sync2 = '0' then
                                rx_clk_cnt <= 0;
                                rx_state   <= RX_DATA;
                            else
                                rx_state   <= RX_IDLE; -- Glitch
                            end if;
                        else
                            rx_clk_cnt <= rx_clk_cnt + 1;
                        end if;

                    when RX_DATA =>
                        if rx_clk_cnt = (CLKS_PER_BIT - 1) then
                            rx_clk_cnt <= 0;
                            rx_shifter(rx_bit_idx) <= rx_sync2;
                            if rx_bit_idx = 7 then
                                rx_state <= RX_STOP;
                            else
                                rx_bit_idx <= rx_bit_idx + 1;
                            end if;
                        else
                            rx_clk_cnt <= rx_clk_cnt + 1;
                        end if;

                    when RX_STOP =>
                        if rx_clk_cnt = (CLKS_PER_BIT - 1) then
                            rx_clk_cnt   <= 0;
                            rx_byte      <= rx_shifter;
                            rx_valid_reg <= '1';
                            rx_state     <= RX_IDLE;
                        else
                            rx_clk_cnt <= rx_clk_cnt + 1;
                        end if;
                end case;

            end if;
        end if;
    end process p_rx;

    ----------------------------------------------------------------------------
    -- UART Transmitter Process
    ----------------------------------------------------------------------------
    p_tx : process(clk100)
    begin
        if rising_edge(clk100) then
            if rstn = '0' then
                tx_state   <= TX_IDLE;
                tx_clk_cnt <= 0;
                tx_bit_idx <= 0;
                tx_pin_reg <= '1';
                tx_ready   <= '1';
            else
                case tx_state is
                    when TX_IDLE =>
                        tx_pin_reg <= '1';
                        tx_clk_cnt <= 0;
                        tx_bit_idx <= 0;
                        if tx_valid = '1' then
                            tx_shifter <= tx_byte;
                            tx_ready   <= '0';
                            tx_pin_reg <= '0'; -- Start bit
                            tx_state   <= TX_START;
                        else
                            tx_ready   <= '1';
                        end if;

                    when TX_START =>
                        if tx_clk_cnt = (CLKS_PER_BIT - 1) then
                            tx_clk_cnt <= 0;
                            tx_pin_reg <= tx_shifter(0);
                            tx_state   <= TX_DATA;
                        else
                            tx_clk_cnt <= tx_clk_cnt + 1;
                        end if;

                    when TX_DATA =>
                        if tx_clk_cnt = (CLKS_PER_BIT - 1) then
                            tx_clk_cnt <= 0;
                            if tx_bit_idx = 7 then
                                tx_pin_reg <= '1'; -- Stop bit
                                tx_state   <= TX_STOP;
                            else
                                tx_bit_idx <= tx_bit_idx + 1;
                                tx_pin_reg <= tx_shifter(tx_bit_idx + 1);
                            end if;
                        else
                            tx_clk_cnt <= tx_clk_cnt + 1;
                        end if;

                    when TX_STOP =>
                        if tx_clk_cnt = (CLKS_PER_BIT - 1) then
                            tx_clk_cnt <= 0;
                            tx_ready   <= '1';
                            tx_state   <= TX_IDLE;
                        else
                            tx_clk_cnt <= tx_clk_cnt + 1;
                        end if;
                end case;

            end if;
        end if;
    end process p_tx;

end architecture rtl;
