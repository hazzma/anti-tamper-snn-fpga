--------------------------------------------------------------------------------
-- File: response_unit.vhd
-- Description: Anti-Tamper Active Response & Countermeasure Unit
-- Latches alarm, commands immediate key zeroization within <= 2 clock cycles,
-- and isolates external interfaces into Safe Lockout.
-- Conforms to FSD Section 4.7
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity response_unit is
    port (
        clk            : in  std_logic;
        rst            : in  std_logic;
        
        -- Alarm inputs
        alarm_trigger  : in  std_logic;
        alarm_latched  : in  std_logic;
        
        -- Response Controls
        zeroize_pulse  : out std_logic; -- <= 1 cycle command
        zeroize_active : out std_logic; -- Constant high once triggered
        core_disable   : out std_logic; -- Gate core enable
        tamper_flag    : out std_logic  -- Output indicator
    );
end entity response_unit;

architecture rtl of response_unit is
    signal zero_act_reg : std_logic := '0';
    signal zero_pls_reg : std_logic := '0';
begin

    zeroize_active <= zero_act_reg;
    zeroize_pulse  <= zero_pls_reg;
    core_disable   <= zero_act_reg;
    tamper_flag    <= zero_act_reg;

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                zero_act_reg <= '0';
                zero_pls_reg <= '0';
            else
                if (alarm_trigger = '1' or alarm_latched = '1') and zero_act_reg = '0' then
                    zero_act_reg <= '1';
                    zero_pls_reg <= '1'; -- Immediate 1-cycle strobe
                else
                    zero_pls_reg <= '0';
                end if;
            end if;
        end if;
    end process;

end architecture rtl;
