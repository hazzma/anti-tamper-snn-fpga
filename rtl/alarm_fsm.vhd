--------------------------------------------------------------------------------
-- File: alarm_fsm.vhd
-- Description: Sliding-Window Spike Accumulator & Temporal Alarm FSM
-- Conforms to FSD Section 4.6 & python/golden_snn.py (Bit-Exact Logic)
-- W = 1024, N_SUS = 25, N_ALM = 60, HYST = 8
-- States: NORMAL (00), SUSPECT (01), ALARM (10)
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.snn_params_pkg.all;

entity alarm_fsm is
    generic (
        W_LEN       : integer := W_WINDOW;
        N_SUS_TH    : integer := N_SUS_DEFAULT;
        N_ALM_TH    : integer := N_ALM_DEFAULT;
        HYST_VAL    : integer := HYST_DEFAULT
    );
    port (
        clk           : in  std_logic;
        rst           : in  std_logic;
        step_done     : in  std_logic;
        spike_in      : in  std_logic;
        hard_backstop : in  std_logic;
        alarm_state   : out std_logic_vector(1 downto 0);
        spike_count   : out unsigned(15 downto 0);
        alarm_trigger : out std_logic;
        alarm_latched : out std_logic
    );
end entity alarm_fsm;

architecture rtl of alarm_fsm is
    type state_t is (ST_NORMAL, ST_SUSPECT, ST_ALARM);
    signal current_state : state_t := ST_NORMAL;
    type bit_history_t is array (0 to 1023) of std_logic;
    signal history     : bit_history_t := (others => '0');
    signal ptr         : unsigned(9 downto 0) := (others => '0');
    signal count       : unsigned(15 downto 0) := (others => '0');
    signal latched_reg : std_logic := '0';
begin
    spike_count   <= count;
    alarm_latched <= latched_reg;

    process(current_state)
    begin
        case current_state is
            when ST_NORMAL  => alarm_state <= "00";
            when ST_SUSPECT => alarm_state <= "01";
            when ST_ALARM   => alarm_state <= "10";
        end case;
    end process;

    process(clk)
        variable old_bit   : std_logic;
        variable new_count : integer;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                current_state <= ST_NORMAL;
                history       <= (others => '0');
                ptr           <= (others => '0');
                count         <= (others => '0');
                latched_reg   <= '0';
                alarm_trigger <= '0';
            else
                alarm_trigger <= '0';
                if hard_backstop = '1' and latched_reg = '0' then
                    current_state <= ST_ALARM;
                    latched_reg   <= '1';
                    alarm_trigger <= '1';
                elsif step_done = '1' then
                    old_bit := history(to_integer(ptr));
                    history(to_integer(ptr)) <= spike_in;
                    new_count := to_integer(count);
                    if spike_in = '1' and old_bit = '0' then
                        new_count := new_count + 1;
                    elsif spike_in = '0' and old_bit = '1' then
                        new_count := new_count - 1;
                    end if;
                    if new_count < 0 then
                        count <= (others => '0');
                    else
                        count <= to_unsigned(new_count, 16);
                    end if;
                    ptr <= ptr + 1;
                    if latched_reg = '1' then
                        current_state <= ST_ALARM;
                    elsif new_count >= N_ALM_TH then
                        current_state <= ST_ALARM;
                        latched_reg   <= '1';
                        alarm_trigger <= '1';
                    else
                        case current_state is
                            when ST_NORMAL =>
                                if new_count >= N_SUS_TH then
                                    current_state <= ST_SUSPECT;
                                end if;
                            when ST_SUSPECT =>
                                if new_count < (N_SUS_TH - HYST_VAL) then
                                    current_state <= ST_NORMAL;
                                end if;
                            when ST_ALARM =>
                                latched_reg <= '1';
                        end case;
                    end if;
                end if;
            end if;
        end if;
    end process;
end architecture rtl;
