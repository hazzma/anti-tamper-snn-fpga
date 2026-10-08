--------------------------------------------------------------------------------
-- File: telemetry.vhd
-- Description: U14 Telemetry, Event Log & 7-Segment Multiplexer (FSD v2 §6-U14 & §10)
-- Generates 1 ms Leak Tick, formats status for 7-Segment Display and UART stream
-- Clock Domain: clk100
-- Standard: VHDL-2008, IEEE numeric_std
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.pkg_fsd.all;

entity telemetry is
    port (
        clk100         : in  std_logic;
        rstn           : in  std_logic;
        
        -- Periodic Timer Output
        leak_tick_out  : out std_logic; -- 1 ms tick (100,000 cycles @ 100MHz)
        heartbeat_led  : out std_logic; -- 1 Hz toggle
        
        -- Status Inputs from Core Modules
        arm_status     : in  std_logic;
        alert_status   : in  std_logic;
        zeroize_status : in  std_logic;
        active_class   : in  std_logic_vector(1 downto 0);
        v_n1_membrane  : in  signed(15 downto 0);
        
        -- 7-Segment Display Outputs (Nexys A7-100T)
        seg_an         : out std_logic_vector(7 downto 0);
        seg_cath       : out std_logic_vector(6 downto 0);
        seg_dp         : out std_logic
    );
end entity telemetry;

architecture rtl of telemetry is

    -- 1 ms Leak Tick Generator Counter (100,000 cycles)
    signal leak_counter : unsigned(19 downto 0) := (others => '0');
    signal leak_p       : std_logic := '0';

    -- 1 Hz Heartbeat Counter (100,000,000 cycles)
    signal hb_counter   : unsigned(26 downto 0) := (others => '0');
    signal hb_reg       : std_logic := '0';

    -- 7-Segment Multiplexer (1 kHz scan rate => 12,500 cycles per digit)
    signal mux_counter  : unsigned(15 downto 0) := (others => '0');
    signal digit_idx    : integer range 0 to 7 := 0;
    signal current_nib  : std_logic_vector(3 downto 0) := (others => '0');
    signal an_reg       : std_logic_vector(7 downto 0) := (others => '1');
    signal cath_reg     : std_logic_vector(6 downto 0) := (others => '1');

    function hex_to_7seg (nibble : std_logic_vector(3 downto 0)) return std_logic_vector is
    begin
        case nibble is
            when x"0" => return "1000000"; -- 0
            when x"1" => return "1111001"; -- 1
            when x"2" => return "0100100"; -- 2
            when x"3" => return "0110000"; -- 3
            when x"4" => return "0011001"; -- 4
            when x"5" => return "0010010"; -- 5
            when x"6" => return "0000010"; -- 6
            when x"7" => return "1111000"; -- 7
            when x"8" => return "0000000"; -- 8
            when x"9" => return "0010000"; -- 9
            when x"A" => return "0001000"; -- A
            when x"B" => return "0000011"; -- b
            when x"C" => return "1000110"; -- C
            when x"D" => return "0100001"; -- d
            when x"E" => return "0000110"; -- E
            when others => return "0001110"; -- F
        end case;
    end function hex_to_7seg;

begin

    leak_tick_out <= leak_p;
    heartbeat_led <= hb_reg;
    seg_an        <= an_reg;
    seg_cath      <= cath_reg;
    seg_dp        <= '1'; -- Decimal point off

    ----------------------------------------------------------------------------
    -- Timer & Leak Tick Generator Process
    ----------------------------------------------------------------------------
    p_timer : process(clk100)
    begin
        if rising_edge(clk100) then
            if rstn = '0' then
                leak_counter <= (others => '0');
                leak_p       <= '0';
                hb_counter   <= (others => '0');
                hb_reg       <= '0';
            else
                -- 1 ms Leak Tick generator (100,000 cycles)
                if leak_counter >= 99999 then
                    leak_counter <= (others => '0');
                    leak_p       <= '1';
                else
                    leak_counter <= leak_counter + 1;
                    leak_p       <= '0';
                end if;

                -- 1 Hz Heartbeat generator
                if hb_counter >= 49999999 then
                    hb_counter <= (others => '0');
                    hb_reg     <= not hb_reg;
                else
                    hb_counter <= hb_counter + 1;
                end if;
            end if;
        end if;
    end process p_timer;

    ----------------------------------------------------------------------------
    -- 7-Segment 8-Digit Display Scanner (FSD v2 §10)
    ----------------------------------------------------------------------------
    p_7seg : process(clk100)
    begin
        if rising_edge(clk100) then
            if rstn = '0' then
                mux_counter <= (others => '0');
                digit_idx   <= 0;
                an_reg      <= (others => '1');
                cath_reg    <= (others => '1');
            else
                if mux_counter >= 12499 then
                    mux_counter <= (others => '0');
                    if digit_idx = 7 then
                        digit_idx <= 0;
                    else
                        digit_idx <= digit_idx + 1;
                    end if;
                else
                    mux_counter <= mux_counter + 1;
                end if;

                -- Select Anode
                an_reg <= (others => '1');
                an_reg(digit_idx) <= '0';

                -- Display content mapping:
                -- Digit 7:6 => Active Class
                -- Digit 5:2 => V[n1] membrane hex
                -- Digit 1:0 => State (AL, ZO, AR, NR)
                case digit_idx is
                    when 7 =>
                        cath_reg <= hex_to_7seg("00" & active_class);
                    when 6 =>
                        cath_reg <= "0110111"; -- '=' or separator
                    when 5 =>
                        cath_reg <= hex_to_7seg(std_logic_vector(v_n1_membrane(15 downto 12)));
                    when 4 =>
                        cath_reg <= hex_to_7seg(std_logic_vector(v_n1_membrane(11 downto 8)));
                    when 3 =>
                        cath_reg <= hex_to_7seg(std_logic_vector(v_n1_membrane(7 downto 4)));
                    when 2 =>
                        cath_reg <= hex_to_7seg(std_logic_vector(v_n1_membrane(3 downto 0)));
                    when 1 =>
                        if alert_status = '1' then
                            cath_reg <= "0001000"; -- 'A'
                        elsif zeroize_status = '1' then
                            cath_reg <= "0100100"; -- 'Z' (approx as 2)
                        elsif arm_status = '1' then
                            cath_reg <= "0001000"; -- 'A'
                        else
                            cath_reg <= "0101011"; -- 'n'
                        end if;
                    when others => -- digit 0
                        if alert_status = '1' then
                            cath_reg <= "1000111"; -- 'L'
                        elsif zeroize_status = '1' then
                            cath_reg <= "1000000"; -- '0' / 'O'
                        elsif arm_status = '1' then
                            cath_reg <= "0101111"; -- 'r'
                        else
                            cath_reg <= "0101111"; -- 'r'
                        end if;
                end case;

            end if;
        end if;
    end process p_7seg;

end architecture rtl;
