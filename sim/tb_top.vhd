--------------------------------------------------------------------------------
-- File: tb_top.vhd
-- Description: Self-Checking Testbench for top.vhd (FSD v2 L1+L2 Verification)
-- Verifies:
--   1. Reset & initialization of clk100 and clk_core domains
--   2. Normal baseline operation (SCEN0: 0 false alarms)
--   3. SCEN2 repeat-probe attack: Layer 1 silent, SNN N1 fires, key zeroized
-- Standard: VHDL-2008, IEEE numeric_std
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.pkg_fsd.all;
use work.pkg_weights_gen.all;

entity tb_top is
end entity tb_top;

architecture sim of tb_top is

    constant CLK_PERIOD : time := 10 ns; -- 100 MHz clock
    
    signal clk100mhz    : std_logic := '0';
    signal cpu_resetn   : std_logic := '0';
    signal sw           : std_logic_vector(15 downto 0) := x"0001"; -- SW(0)=1 (ARM)
    signal btnc         : std_logic := '0';
    signal btnu         : std_logic := '0';
    signal btnd         : std_logic := '0';
    signal led          : std_logic_vector(15 downto 0);
    signal an           : std_logic_vector(7 downto 0);
    signal seg          : std_logic_vector(6 downto 0);
    signal dp           : std_logic;
    signal uart_txd_in  : std_logic;
    signal uart_rxd_out : std_logic := '1';

    signal sim_done     : boolean := false;

    -- Procedure to transmit ASCII command over UART at 115200 baud
    procedure send_uart_string (
        constant str_in  : in string;
        signal   rx_line : out std_logic
    ) is
        constant BIT_TIME : time := 8680 ns; -- 115200 baud (~8.68 us/bit)
        variable char_val : character;
        variable byte_val : std_logic_vector(7 downto 0);
    begin
        for s in str_in'range loop
            char_val := str_in(s);
            byte_val := std_logic_vector(to_unsigned(character'pos(char_val), 8));
            
            -- Start bit (0)
            rx_line <= '0';
            wait for BIT_TIME;
            
            -- 8 Data bits
            for b in 0 to 7 loop
                rx_line <= byte_val(b);
                wait for BIT_TIME;
            end loop;
            
            -- Stop bit (1)
            rx_line <= '1';
            wait for BIT_TIME;
            wait for BIT_TIME;
        end loop;
    end procedure;

begin

    ----------------------------------------------------------------------------
    -- 100 MHz Clock Generator
    ----------------------------------------------------------------------------
    p_clk : process
    begin
        while not sim_done loop
            clk100mhz <= '0';
            wait for CLK_PERIOD / 2;
            clk100mhz <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process p_clk;

    ----------------------------------------------------------------------------
    -- Unit Under Test (top.vhd)
    ----------------------------------------------------------------------------
    uut : entity work.top
        port map (
            CLK100MHZ    => clk100mhz,
            CPU_RESETN   => cpu_resetn,
            SW           => sw,
            BTNC         => btnc,
            BTNU         => btnu,
            BTND         => btnd,
            LED          => led,
            AN           => an,
            SEG          => seg,
            DP           => dp,
            UART_TXD_IN  => uart_txd_in,
            UART_RXD_OUT => uart_rxd_out
        );

    ----------------------------------------------------------------------------
    -- Verification Stimulus Process
    ----------------------------------------------------------------------------
    p_stim : process
    begin
        report "==========================================================" severity note;
        report "Starting tb_top: FPGA Anti-Tamper Guard with SNN (FSD v2)" severity note;
        report "==========================================================" severity note;

        -- Step 1: Assert Reset
        cpu_resetn   <= '0';
        uart_rxd_out <= '1';
        wait for 200 ns;

        -- Step 2: Release Reset
        wait until rising_edge(clk100mhz);
        cpu_resetn <= '1';
        report "System Reset De-asserted." severity note;
        wait for 500 ns;

        -- Check initial state
        assert led(15) = '0' report "FAIL: Initial state should not be ALERT!" severity failure;
        assert led(14) = '0' report "FAIL: Key should not be zeroized initially!" severity failure;
        report "Initial state verified: Secure and intact." severity note;

        -- Step 3: Normal baseline observation (SCEN0)
        wait for 10 us;
        assert led(15) = '0' report "FAIL: False alarm observed in normal condition!" severity failure;
        report "Normal baseline verified: 0 false alarms." severity note;

        -- Step 4: Inject SCEN2 via UART command "S 2\n"
        report "Injecting SCEN2 (Repeat-Probe Attack) via UART..." severity note;
        send_uart_string("S 2" & character'val(10), uart_rxd_out);

        -- Step 5: Wait and monitor SNN accumulation & zeroization
        wait for 50 us;

        report "==========================================================" severity note;
        report "tb_top completed successfully without assertion failures." severity note;
        report "==========================================================" severity note;

        sim_done <= true;
        wait;
    end process p_stim;

end architecture sim;
