-- ro_sensor.vhd
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.snn_params_pkg.all;

entity ro_sensor is
    generic (
        STAGES : integer := 5
    );
    port (
        clk           : in  std_logic;
        rst           : in  std_logic;
        tick_in       : in  std_logic;
        skew_skip     : in  std_logic;
        ro_count_out : out unsigned(15 downto 0)
    );
end entity ro_sensor;

architecture rtl of ro_sensor is
    signal ring : std_logic_vector(STAGES - 1 downto 0);
    attribute DONT_TOUCH : string;
    attribute DONT_TOUCH of ring : signal is "TRUE";

    signal prescaler : unsigned(2 downto 0) := (others => '0');
    signal ro_pulse  : std_logic;

    signal sync_ff1  : std_logic := '0';
    signal sync_ff2  : std_logic := '0';
    signal sync_ff3  : std_logic := '0';
    signal edge_detect: std_logic;

    signal window_cnt : unsigned(RO_WINDOW_BITS - 1 downto 0) := (others => '0');
    signal accum_cnt  : unsigned(15 downto 0) := (others => '0');
    signal latch_cnt  : unsigned(15 downto 0) := (others => '0');
begin

    -- Ring Oscillator Chain (odd number of inverters)
    gen_ring: for i in 0 to STAGES - 1 generate
        gen_first: if i = 0 generate
            ring(0) <= not ring(STAGES - 1);
        end generate gen_first;
        gen_rest: if i > 0 generate
            ring(i) <= not ring(i - 1);
        end generate gen_rest;
    end generate gen_ring;

    -- Prescaler in RO domain
    p_prescale: process(ring(0))
    begin
        if rising_edge(ring(0)) then
            prescaler <= prescaler + 1;
        end if;
    end process p_prescale;

    ro_pulse <= prescaler(2);

    -- 2-FF CDC Synchronizer to 100 MHz clock domain
    p_sync: process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                sync_ff1   <= '0';
                sync_ff2   <= '0';
                sync_ff3   <= '0';
            else
                sync_ff1   <= ro_pulse;
                sync_ff2   <= sync_ff1;
                sync_ff3   <= sync_ff2;
            end if;
        end if;
    end process p_sync;

    edge_detect <= sync_ff2 and (not sync_ff3);

    -- Window Measurement Counter (2^15 clk window)
    p_count: process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                window_cnt <= (others => '0');
                accum_cnt  <= (others => '0');
                latch_cnt  <= (others => '0');
            else
                -- Window timer advances unless skew injection skips it
                if skew_skip = '0' then
                    window_cnt <= window_cnt + 1;
                end if;

                if edge_detect = '1' then
                    accum_cnt <= accum_cnt + 1;
                end if;

                -- At the end of window, latch accumulated count
                if window_cnt = (window_cnt'range => '1') then
                    latch_cnt  <= accum_cnt;
                    accum_cnt  <= (others => '0');
                end if;
            end if;
        end if;
    end process p_count;

    ro_count_out <= latch_cnt;

end architecture rtl;
