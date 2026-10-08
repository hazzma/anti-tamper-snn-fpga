-- logger.vhd
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.snn_params_pkg.all;

entity logger is
    port (
        clk             : in  std_logic;
        rst             : in  std_logic;
        tick_in         : in  std_logic;
        -- Raw Sensor Data
        temp_code       : in  unsigned(11 downto 0);
        vccint_code     : in  unsigned(11 downto 0);
        ro_count        : in  unsigned(15 downto 0);
        bad_words       : in  unsigned(7 downto 0);
        flags           : in  std_logic_vector(7 downto 0);
        -- UART TX Interface
        tx_data         : out std_logic_vector(7 downto 0);
        tx_valid        : out std_logic;
        tx_ready        : in  std_logic
    );
end entity logger;

architecture rtl of logger is
    type byte_array_t is array(0 to 7) of std_logic_vector(7 downto 0);
    signal frame_buffer : byte_array_t := (others => (others => '0'));
    signal byte_idx     : integer range 0 to 7 := 0;
    signal sending      : boolean := false;
begin

    p_logger: process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                sending     <= false;
                byte_idx    <= 0;
                tx_valid    <= '0';
                tx_data     <= (others => '0');
            else
                if tick_in = '1' and not sending then
                    -- Pack 8-byte frame: T[2], V[2], F[2], M[1], Flags[1]
                    frame_buffer(0) <= "0000" & std_logic_vector(temp_code(11 downto 8));
                    frame_buffer(1) <= std_logic_vector(temp_code(7 downto 0));
                    frame_buffer(2) <= "0000" & std_logic_vector(vccint_code(11 downto 8));
                    frame_buffer(3) <= std_logic_vector(vccint_code(7 downto 0));
                    frame_buffer(4) <= std_logic_vector(ro_count(15 downto 8));
                    frame_buffer(5) <= std_logic_vector(ro_count(7 downto 0));
                    frame_buffer(6) <= std_logic_vector(bad_words);
                    frame_buffer(7) <= flags;

                    byte_idx     <= 0;
                    sending      <= true;
                end if;

                if sending then
                    if tx_ready = '1' then
                        tx_data  <= frame_buffer(byte_idx);
                        tx_valid <= '1';
                        if byte_idx = 7 then
                            sending <= false;
                        else
                            byte_idx <= byte_idx + 1;
                        end if;
                else
                    tx_valid <= '0';
                end if;
            else
                tx_valid <= '0';
            end if;
        end if;
    end if;
    end process p_logger;

end architecture rtl;
