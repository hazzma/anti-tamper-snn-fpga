-- tb_logger.vhd
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.snn_params_pkg.all;

entity tb_logger is
end entity tb_logger;

architecture sim of tb_logger is
    signal clk             : std_logic := '0';
    signal rst             : std_logic := '1';
    signal tick_in         : std_logic := '0';
    signal temp_code       : unsigned(11 downto 0) := x"A12";
    signal vccint_code     : unsigned(11 downto 0) := x"543";
    signal ro_count        : unsigned(15 downto 0) := x"3A98";
    signal bad_words       : unsigned(7 downto 0) := x"02";
    signal flags           : std_logic_vector(7 downto 0) := x"01";

    signal tx_data         : std_logic_vector(7 downto 0);
    signal tx_valid        : std_logic;
    signal tx_ready        : std_logic := '1';

    type captured_t is array(0 to 7) of std_logic_vector(7 downto 0);
    signal captured       : captured_t := (others => (others => '0'));
    signal cap_idx        : integer range 0 to 8 := 0;
begin

    clk <= not clk after 5 ns;

    dut: entity work.logger
        port map (
            clk         => clk,
            rst         => rst,
            tick_in     => tick_in,
            temp_code    => temp_code,
            vccint_code  => vccint_code,
            ro_count     => ro_count,
            bad_words    => bad_words,
            flags        => flags,
            tx_data      => tx_data,
            tx_valid     => tx_valid,
            tx_ready     => tx_ready
        );

    p_cap: process(clk)
    begin
        if rising_edge(clk) then
            if tx_valid = '1' and tx_ready = '1' then
                captured(cap_idx) <= tx_data;
                if cap_idx < 7 then
                    cap_idx <= cap_idx + 1;
                end if;
            end if;
        end if;
    end process p_cap;

    p_stim: process
    begin
        rst <= '1';
        wait for 100 ns;
        rst <= '0';
        wait for 50 ns;

        -- Trigger 1 tick
        tick_in <= '1';
        wait for 10 ns;
        tick_in <= '0';

        wait for 200 ns;

        -- Check all 8 bytes
        assert captured(0) = x"0A" report "Byte 0 mismatch" severity failure;
        assert captured(1) = x"12" report "Byte 1 mismatch" severity failure;
        assert captured(2) = x"05" report "Byte 2 mismatch" severity failure;
        assert captured(3) = x"43" report "Byte 3 mismatch" severity failure;
        assert captured(4) = x"3A" report "Byte 4 mismatch" severity failure;
        assert captured(5) = x"98" report "Byte 5 mismatch" severity failure;
        assert captured(6) = x"02" report "Byte 6 mismatch" severity failure;
        assert captured(7) = x"01" report "Byte 7 mismatch" severity failure;

        report "TB LOGGER PASSED SUCCESSFULLY" severity note;
        wait;
    end process p_stim;
end architecture sim;
