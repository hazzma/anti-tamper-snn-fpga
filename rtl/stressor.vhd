--------------------------------------------------------------------------------
-- File: stressor.vhd
-- Description: U5 Synchronous Power Stressor for VCCINT IR-Drop (FSD v2 §6-U5)
-- Generates massive di/dt synchronous switching when enabled (VSTRESS command)
-- Standard: VHDL-2008, IEEE numeric_std
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity stressor is
    generic (
        STRESS_BANKS : natural := 32 -- 32 banks x 64 FFs = ~2048 switching elements
    );
    port (
        clk100      : in  std_logic;
        rstn        : in  std_logic;
        stress_en   : in  std_logic;
        active_out  : out std_logic
    );
end entity stressor;

architecture rtl of stressor is

    type bank_array_t is array(0 to STRESS_BANKS-1) of std_logic_vector(63 downto 0);
    signal shift_banks : bank_array_t := (others => (others => '0'));
    signal toggle_bit  : std_logic := '0';

begin

    active_out <= stress_en;

    p_stress : process(clk100)
    begin
        if rising_edge(clk100) then
            if rstn = '0' then
                shift_banks <= (others => (others => '0'));
                toggle_bit  <= '0';
            else
                if stress_en = '1' then
                    toggle_bit <= not toggle_bit;
                    for b in 0 to STRESS_BANKS-1 loop
                        -- Synchronous shift and inverted toggle across all banks
                        shift_banks(b) <= shift_banks(b)(62 downto 0) & (toggle_bit xor shift_banks(b)(63));
                    end loop;
                else
                    toggle_bit <= '0';
                    -- Hold idle to eliminate dynamic dissipation
                    for b in 0 to STRESS_BANKS-1 loop
                        shift_banks(b) <= (others => '0');
                    end loop;
                end if;
            end if;
        end if;
    end process p_stress;

end architecture rtl;
