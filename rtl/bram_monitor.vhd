-- bram_monitor.vhd
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.snn_params_pkg.all;

entity bram_monitor is
    port (
        clk             : in  std_logic;
        rst             : in  std_logic;
        tick_in         : in  std_logic;
        -- Tamper emulator port B injection
        inj_en          : in  std_logic;
        inj_addr        : in  unsigned(9 downto 0);
        inj_bit         : in  integer range 0 to 31;
        -- Output
        bad_words_out  : out unsigned(7 downto 0)
    );
end entity bram_monitor;

architecture rtl of bram_monitor is
    type ram_t is array (0 to BRAM_WORDS - 1) of std_logic_vector(31 downto 0);
    signal ram : ram_t := (others => (others => '0'));

    function calc_expected_word(addr : unsigned(9 downto 0)) return std_logic_vector is
        variable prod : unsigned(63 downto 0);
        variable res  : unsigned(31 downto 0);
    begin
        prod := resize(addr, 32) * BRAM_HASH_MULT;
        res  := prod(31 downto 0) xor BRAM_HASH_XOR;
        return std_logic_vector(res);
    end function;

    type state_t is (INIT, IDLE, SCAN_READ, SCAN_CHECK, DONE);
    signal state           : state_t := INIT;

    signal scan_addr      : unsigned(9 downto 0) := (others => '0');
    signal bad_cnt        : unsigned(7 downto 0) := (others => '0');
    signal bad_latch      : unsigned(7 downto 0) := (others => '0');
    signal rdata          : std_logic_vector(31 downto 0);
    signal exp_word       : std_logic_vector(31 downto 0);
begin

    -- Port B Bit-flip injector (for tamper emulator)
    p_inj: process(clk)
        variable tmp : std_logic_vector(31 downto 0);
    begin
        if rising_edge(clk) then
            if inj_en = '1' then
                tmp := ram(to_integer(inj_addr));
                tmp(inj_bit) := not tmp(inj_bit);
                ram(to_integer(inj_addr)) <= tmp;
            end if;
        end if;
    end process p_inj;

    -- Port A Scan, Check and Scrub FSM
    p_fsm: process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state     <= INIT;
                scan_addr <= (others => '0');
                bad_cnt   <= (others => '0');
                bad_latch <= (others => '0');
            else
                case state is
                    when INIT =>
                        -- Populate BRAM with deterministic hash words
                        ram(to_integer(scan_addr)) <= calc_expected_word(scan_addr);
                        if scan_addr = BRAM_WORDS - 1 then
                            scan_addr <= (others => '0');
                            state     <= IDLE;
                        else
                            scan_addr <= scan_addr + 1;
                        end if;

                    when IDLE =>
                        scan_addr <= (others => '0');
                        if tick_in = '1' then
                            bad_cnt <= (others => '0');
                            rdata   <= ram(0);
                            state   <= SCAN_CHECK;
                        end if;

                    when SCAN_CHECK =>
                        exp_word <= calc_expected_word(scan_addr);
                        if rdata /= calc_expected_word(scan_addr) then
                            if bad_cnt < 255 then
                                bad_cnt <= bad_cnt + 1;
                            end if;
                            -- Scrub (write back correct word)
                            ram(to_integer(scan_addr)) <= calc_expected_word(scan_addr);
                        end if;

                        if scan_addr = BRAM_WORDS - 1 then
                            state <= DONE;
                        else
                            scan_addr <= scan_addr + 1;
                            rdata     <= ram(to_integer(scan_addr + 1));
                        end if;

                    when DONE =>
                        bad_latch <= bad_cnt;
                        state     <= IDLE;

                    when others =>
                        state <= IDLE;
            end case;
            end if;
        end if;
    end process p_fsm;

    bad_words_out <= bad_latch;

end architecture rtl;
