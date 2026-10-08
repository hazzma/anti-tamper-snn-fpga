-- uart_rx.vhd
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_rx is
    generic (
        CLK_FREQ : integer := 100000000;
        BAUD_RATE: integer := 921600
    );
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        rxd       : in  std_logic;
        rx_data   : out std_logic_vector(7 downto 0);
        rx_valid  : out std_logic
    );
end entity uart_rx;

architecture rtl of uart_rx is
    constant CLKS_PER_BIT : integer := CLK_FREQ / BAUD_RATE;

    signal rxd_sync1   : std_logic := '1';
    signal rxd_sync2   : std_logic := '1';

    type state_t is (IDLE, START, DATA, STOP);
    signal state     : state_t := IDLE;

    signal clk_cnt   : integer range 0 to CLKS_PER_BIT := 0;
    signal bit_idx   : integer range 0 to 7 := 0;
    signal shifter   : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_val_reg: std_logic := '0';
begin

    p_sync: process(clk)
    begin
        if rising_edge(clk) then
            rxd_sync1 <= rxd;
            rxd_sync2 <= rxd_sync1;
        end if;
    end process p_sync;

    p_rx: process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state      <= IDLE;
                clk_cnt   <= 0;
                bit_idx   <= 0;
                rx_val_reg <= '0';
            else
                rx_val_reg <= '0';
                case state is
                    when IDLE =>
                        clk_cnt <= 0;
                        bit_idx <= 0;
                        if rxd_sync2 = '0' then -- Start bit detected
                            state <= START;
                        end if;

                    when START =>
                        -- Sample at mid-point of start bit
                        if clk_cnt = CLKS_PER_BIT / 2 then
                            if rxd_sync2 = '0' then
                                clk_cnt <= 0;
                            state   <= DATA;
                            else
                                state   <= IDLE;
                            end if;
                        else
                            clk_cnt <= clk_cnt + 1;
                        end if;

                    when DATA =>
                        if clk_cnt = CLKS_PER_BIT - 1 then
                            clk_cnt <= 0;
                            shifter(bit_idx) <= rxd_sync2;
                            if bit_idx = 7 then
                                bit_idx <= 0;
                                state   <= STOP;
                            else
                                bit_idx <= bit_idx + 1;
                            end if;
                        else
                            clk_cnt <= clk_cnt + 1;
                        end if;

                    when STOP =>
                        if clk_cnt = CLKS_PER_BIT - 1 then
                            clk_cnt     <= 0;
                            rx_val_reg <= '1';
                            state      <= IDLE;
                    else
                            clk_cnt <= clk_cnt + 1;
                    end if;

                    when others =>
                        state <= IDLE;
            end case;
            end if;
        end if;
    end process p_rx;

    rx_data  <= shifter;
    rx_valid <= rx_val_reg;

end architecture rtl;
