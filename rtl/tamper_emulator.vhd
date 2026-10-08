-- tamper_emulator.vhd
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.snn_params_pkg.all;

entity tamper_emulator is
    port (
        clk                : in  std_logic;
        rst                : in  std_logic;
        -- Thermal Safety Feedback (from XADC)
        temp_code         : in  unsigned(11 downto 0);
        -- Emulator Control
        waster_en        : in  std_logic;
        waster_duty      : in  unsigned(3 downto 0); -- 0..15 intensity
        waster_pulsed    : in  std_logic;
        skew_en          : in  std_logic;
        skew_rate        : in  unsigned(7 downto 0); -- Skip 1 of N pulses
        flip_en          : in  std_logic;
        flip_addr        : in  unsigned(9 downto 0);
        flip_bit         : in  integer range 0 to 31;
        -- Outputs to Sensors & Telemetry
        skew_skip_out    : out std_logic;
        bram_inj_en_out  : out std_logic;
        bram_inj_addr_out: out unsigned(9 downto 0);
        bram_inj_bit_out : out integer range 0 to 31;
        emu_active_out   : out std_logic
     );
end entity tamper_emulator;

architecture rtl of tamper_emulator is
    -- T_SAFE = 75 C. Code = (75 + 273.15) * 4096 / 503.975 = 2829 (0xB0D)
    constant T_SAFE_CODE   : unsigned(11 downto 0) := to_unsigned(2829, 12);

    -- Power Waster Toggling Bank
    signal waster_lfsr   : unsigned(31 downto 0) := x"CAFEBABE";
    signal waster_toggle : std_logic_vector(255 downto 0) := (others => '0');
    attribute DONT_TOUCH : string;
    attribute DONT_TOUCH of waster_toggle : signal is "TRUE";

    signal pulse_timer   : unsigned(17 downto 0) := (others => '0');
    signal pulse_active  : std_logic := '1';
    signal thermal_trip  : std_logic := '0';

    signal skew_cnt      : unsigned(7 downto 0) := (others => '0');
    signal skew_skip     : std_logic := '0';
begin

    -- Thermal Safety Interlock
    thermal_trip <= '1' when temp_code > T_SAFE_CODE else '0';

    -- Pulsed Waster Timer (~200 Hz pulse)
    p_pulse: process(clk)
    begin
        if rising_edge(clk) then
            pulse_timer <= pulse_timer + 1;
            if waster_pulsed = '1' then
                pulse_active <= pulse_timer(17);
            else
                pulse_active <= '1';
            end if;
        end if;
    end process p_pulse;

    -- Power Waster Toggling Logic
    p_waster: process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                waster_lfsr   <= x"CAFEBABE";
                waster_toggle <= (others => '0');
            else
                if waster_en = '1' and thermal_trip = '0' and pulse_active = '1' then
                    waster_lfsr <= waster_lfsr(30 downto 0) & (waster_lfsr(31) xor waster_lfsr(21) xor waster_lfsr(1) xor waster_lfsr(0));
                    for i in 0 to 15 loop
                        if i < to_integer(waster_duty) then
                            waster_toggle((i+1)*16 - 1 downto i*16) <= not waster_toggle((i+1)*16 - 1 downto i*16);
                        end if;
                    end loop;
                end if;
            end if;
        end if;
    end process p_waster;

    -- Clock Skew Generator
    p_skew: process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                skew_cnt  <= (others => '0');
                skew_skip <= '0';
            else
                if skew_en = '1' then
                    if skew_cnt >= skew_rate then
                        skew_cnt  <= (others => '0');
                        skew_skip <= '1';
                    else
                        skew_cnt  <= skew_cnt + 1;
                        skew_skip <= '0';
                    end if;
                else
                    skew_skip <= '0';
                end if;
            end if;
        end if;
    end process p_skew;

    skew_skip_out     <= skew_skip;
    bram_inj_en_out   <= flip_en;
    bram_inj_addr_out <= flip_addr;
    bram_inj_bit_out  <= flip_bit;

    emu_active_out <= (waster_en and not thermal_trip) or skew_en or flip_en;

end architecture rtl;
