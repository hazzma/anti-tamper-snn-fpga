--------------------------------------------------------------------------------
-- File: protected_core.vhd
-- Description: Toy Protected Cryptographic Asset Core
-- Holds a sensitive 128-bit root secret key and dummy hash/cipher logic.
-- Guarantees immediate zeroization of the secret register within <= 1 cycle
-- upon zeroize assertion.
-- Conforms to FSD Section 4.7
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity protected_core is
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;
        
        -- Countermeasure signals
        zeroize      : in  std_logic; -- Synchronous zeroize command
        disable      : in  std_logic; -- Functional gate
        
        -- Functional Interface
        data_in      : in  std_logic_vector(31 downto 0);
        data_valid   : in  std_logic;
        data_out     : out std_logic_vector(31 downto 0);
        data_ready   : out std_logic;
        
        -- Debug/Inspection Port (for self-checking testbench)
        key_zeroized : out std_logic
    );
end entity protected_core;

architecture rtl of protected_core is

    -- 128-bit Secret Key Register
    constant DEFAULT_SECRET : std_logic_vector(127 downto 0) := 
        x"DEADBEEF_CAFEF00D_01234567_89ABCDEF";
        
    signal key_reg   : std_logic_vector(127 downto 0) := DEFAULT_SECRET;
    signal out_reg   : std_logic_vector(31 downto 0)  := (others => '0');
    signal ready_reg : std_logic                      := '0';

begin

    data_out <= out_reg;
    data_ready <= ready_reg;
    key_zeroized <= '1' when key_reg = (127 downto 0 => '0') else '0';

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                key_reg   <= DEFAULT_SECRET;
                out_reg   <= (others => '0');
                ready_reg <= '0';
            else
                -- Zeroization takes highest synchronous priority
                if zeroize = '1' then
                    key_reg   <= (others => '0'); -- Instant overwrite
                    out_reg   <= (others => '0');
                    ready_reg <= '0';
                elsif disable = '1' then
                    out_reg   <= (others => '0');
                    ready_reg <= '0';
                elsif data_valid = '1' then
                    -- Simple pseudo-cipher mixing input with key chunk
                    out_reg   <= data_in xor key_reg(31 downto 0);
                    ready_reg <= '1';
                else
                    ready_reg <= '0';
                end if;
            end if;
        end if;
    end process;

end architecture rtl;
