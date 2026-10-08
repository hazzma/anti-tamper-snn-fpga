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
        spike_count    : in  unsigned(7 downto 0);
        key_display    : in  std_logic_vector(15 downto 0);
        
        -- 7-Segment Display Outputs (Nexys A7-100T)
        seg_an         : out std_logic_vector(7 downto 0);
        seg_cath       : out std_logic_vector(6 downto 0);
        seg_dp         : out std_logic
    );
end entity telemetry;

architecture rtl of telemetry is

    -- 200 ms Leak Tick Generator Counter (20,000,000 cycles @ 100MHz)
    signal leak_counter : unsigned(25 downto 0) := (others => '0');
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

    -- Membrane Peak-Hold for 7-Segment Display (50 ms persistence for human visibility)
    signal v_disp_val   : signed(15 downto 0) := (others => '0');
    signal v_hold_timer : unsigned(24 downto 0) := (others => '0');

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
    -- Decimal point aktif (low) pada Digit 4 sebagai pembatas visual antara Key (kiri) dan Counter/Status (kanan)
    seg_dp        <= '0' when digit_idx = 4 else '1';

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
                -- 200 ms Leak Tick generator (20,000,000 cycles @ 100MHz)
                if leak_counter >= 19999999 then
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
    -- Membrane Peak-Hold Process (Holds peak for 50 ms for human visual persistence)
    ----------------------------------------------------------------------------
    p_v_hold : process(clk100)
    begin
        if rising_edge(clk100) then
            if rstn = '0' then
                v_disp_val   <= (others => '0');
                v_hold_timer <= (others => '0');
            else
                if v_n1_membrane > v_disp_val then
                    v_disp_val   <= v_n1_membrane;
                    v_hold_timer <= (others => '0');
                else
                    if v_hold_timer >= 4999999 then -- 50 ms @ 100 MHz
                        v_hold_timer <= (others => '0');
                        v_disp_val   <= v_n1_membrane;
                    else
                        v_hold_timer <= v_hold_timer + 1;
                    end if;
                end if;
            end if;
        end if;
    end process p_v_hold;

    ----------------------------------------------------------------------------
    -- 7-Segment 8-Digit Display Scanner (Split: 4 Digit Kiri = Key, 4 Digit Kanan = Counter)
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
                -- Digit 7:4 (KIRI)  => 16-bit Key Display (wiped to 0000 on zeroize)
                -- Digit 3:0 (KANAN) => C <spike_count> <State> (misal C0Ar, C1AL, C2ZO)
                case digit_idx is
                    -- === 4 DIGIT KIRI (DATA KUNCI KRIPTOGRAFI) ===
                    when 7 =>
                        if zeroize_status = '1' then
                            cath_reg <= hex_to_7seg(x"0"); -- 0 (wiped)
                        else
                            cath_reg <= hex_to_7seg(key_display(15 downto 12));
                        end if;
                    when 6 =>
                        if zeroize_status = '1' then
                            cath_reg <= hex_to_7seg(x"0"); -- 0 (wiped)
                        else
                            cath_reg <= hex_to_7seg(key_display(11 downto 8));
                        end if;
                    when 5 =>
                        if zeroize_status = '1' then
                            cath_reg <= hex_to_7seg(x"0"); -- 0 (wiped)
                        else
                            cath_reg <= hex_to_7seg(key_display(7 downto 4));
                        end if;
                    when 4 =>
                        if zeroize_status = '1' then
                            cath_reg <= hex_to_7seg(x"0"); -- 0 (wiped)
                        else
                            cath_reg <= hex_to_7seg(key_display(3 downto 0));
                        end if;

                    -- === 4 DIGIT KANAN (COUNTER & STATUS SNN) ===
                    when 3 =>
                        cath_reg <= "1000110"; -- 'C' (Counter indicator)
                    when 2 =>
                        cath_reg <= hex_to_7seg(std_logic_vector(spike_count(3 downto 0)));
                    when 1 =>
                        if zeroize_status = '1' then
                            cath_reg <= "0100100"; -- 'Z' (GSR / Zeroized)
                        elsif alert_status = '1' then
                            cath_reg <= "0001000"; -- 'A' (Warning / Alert)
                        elsif arm_status = '1' then
                            cath_reg <= "0001000"; -- 'A'
                        else
                            cath_reg <= "0101011"; -- 'n'
                        end if;
                    when others => -- digit 0
                        if zeroize_status = '1' then
                            cath_reg <= "1000000"; -- 'O' / '0'
                        elsif alert_status = '1' then
                            cath_reg <= "1000111"; -- 'L' (AL = Warning)
                        elsif arm_status = '1' then
                            cath_reg <= "0101111"; -- 'r' (Ar = Armed)
                        else
                            cath_reg <= "0101111"; -- 'r'
                        end if;
                end case;

            end if;
        end if;
    end process p_7seg;

end architecture rtl;
