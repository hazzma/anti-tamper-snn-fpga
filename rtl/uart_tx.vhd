-- uart_tx.vhd
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_tx is
    generic (
        CLK_FREQ : integer := 100000000;
        BAUD_RATE: integer := 921600
    );
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        tx_data   : in  std_logic_vector(7 downto 0);
        tx_valid  : in  std_logic;
        tx_ready  : out std_logic;
        txd       : out std_logic
    );
end entity uart_tx;

architecture rtl of uart_tx is
    constant CLKS_PER_BIT : integer := CLK_FREQ / BAUD_RATE;

    type state_t is (IDLE, START, DATA, STOP);
    signal state     : state_t := IDLE;

    signal clk_cnt   : integer range 0 to CLKS_PER_BIT := 0;
    signal bit_idx   : integer range 0 to 7 := 0;
    signal shifter   : std_logic_vector(7 downto 0) := (others => '0');
    signal txd_reg   : std_logic := '1';
begin

    p_tx: process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state   <= IDLE;
                clk_cnt <= 0;
                bit_idx <= 0;
                txd_reg <= '1';
            else
                case state is
                    when IDLE =>
                        txd_reg <= '1';
                        clk_cnt <= 0;
                        bit_idx <= 0;
                        if tx_valid = '1' then
                            shifter <= tx_data;
                            txd_reg <= '0'; -- Start bit
                            state   <= START;
                        end if;

                    when START =>
                        if clk_cnt = CLKS_PER_BIT - 1 then
                            clk_cnt <= 0;
                            txd_reg <= shifter(0);
                            state   <= DATA;
                        else
                            clk_cnt <= clk_cnt + 1;
                        end if;

                    when DATA =>
                        if clk_cnt = CLKS_PER_BIT - 1 then
                            clk_cnt <= 0;
                            if bit_idx = 7 then
                                bit_idx <= 0;
                                txd_reg <= '1'; -- Stop bit
                                state   <= STOP;
                            else
                                bit_idx <= bit_idx + 1;
                                shifter <= '0' & shifter(7 downto 1);
                                txd_reg <= shifter(1);
                            end if;
                        else
                            clk_cnt <= clk_cnt + 1;
                        end if;

                    when STOP =>
                        if clk_cnt = CLKS_PER_BIT - 1 then
                            clk_cnt <= 0;
                            state   <= IDLE;
                        else
                            clk_cnt <= clk_cnt + 1;
                        end if;

                    when others =>
                        state <= IDLE;
            end case;
            end if;
        end if;
    end process p_tx;

    tx_ready <= '1' when state = IDLE else '0';
    txd      <= txd_reg;

end architecture rtl;
