-- xadc_if.vhd
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity xadc_if is
    port (
        clk             : in  std_logic;
        rst             : in  std_logic;
        -- Outputs to system
        tick_out        : out std_logic;
        temp_code_out   : out unsigned(11 downto 0);
        vccint_code_out : out unsigned(11 downto 0);
        -- Simulation override (bypasses XADC when sim_override = '1')
        sim_override    : in  std_logic := '0';
        sim_tick        : in  std_logic := '0';
        sim_temp_code   : in  unsigned(11 downto 0) := (others => '0');
        sim_vccint_code : in  unsigned(11 downto 0) := (others => '0')
    );
end entity xadc_if;

architecture rtl of xadc_if is
    signal daddr       : std_logic_vector(6 downto 0) := "0000000";
    signal den        : std_logic := '0';
    signal dwe        : std_logic := '0';
    signal di         : std_logic_vector(15 downto 0) := (others => '0');
    signal do_sig     : std_logic_vector(15 downto 0);
    signal drdy       : std_logic;
    signal eoc        : std_logic;
    signal eos        : std_logic;
    signal channel    : std_logic_vector(4 downto 0);

    type state_t is (WAIT_EOS, READ_TEMP, WAIT_TEMP_DRDY, READ_VCCINT, WAIT_VCCINT_DRDY, DONE_TICK);
    signal state         : state_t := WAIT_EOS;

    signal temp_reg     : unsigned(11 downto 0) := (others => '0');
    signal vccint_reg   : unsigned(11 downto 0) := (others => '0');
    signal tick_reg     : std_logic := '0';

    -- XADC primitive declaration for 7-series
    component XADC
        generic (
            INIT_40 : bit_vector := X"0000";
            INIT_41 : bit_vector := X"21A0"; -- Continuous sequence mode, averaging 256
            INIT_42 : bit_vector := X"0400"; -- DCLK division
            INIT_48 : bit_vector := X"0101"; -- Channel seq: Temp (bit 8), VCCINT (bit 0)
            INIT_49 : bit_vector := X"0000";
            INIT_4A : bit_vector := X"0101"; -- Averaging enabled for Temp, VCCINT
            INIT_4B : bit_vector := X"0000";
            SIM_DEVICE : string := "7SERIES"
        );
        port (
            DADDR          : in  std_logic_vector(6 downto 0);
            DEN            : in  std_logic;
            DWE            : in  std_logic;
            DI             : in  std_logic_vector(15 downto 0);
            DO             : out std_logic_vector(15 downto 0);
            DRDY           : out std_logic;
            DCLK           : in  std_logic;
            RESET          : in  std_logic;
            CONVST         : in  std_logic;
            CONVSTCLK      : in  std_logic;
            VP             : in  std_logic;
            VN             : in  std_logic;
            VAUXP          : in  std_logic_vector(15 downto 0);
            VAUXN          : in  std_logic_vector(15 downto 0);
            CHANNEL        : out std_logic_vector(4 downto 0);
            EOC            : out std_logic;
            EOS            : out std_logic;
            ALM            : out std_logic_vector(7 downto 0);
            OT             : out std_logic
        );
    end component;
begin

    u_xadc: XADC
        port map (
            DADDR      => daddr,
            DEN        => den,
            DWE        => dwe,
            DI         => di,
            DO         => do_sig,
            DRDY       => drdy,
            DCLK       => clk,
            RESET      => rst,
            CONVST     => '0',
            CONVSTCLK  => '0',
            VP         => '0',
            VN         => '0',
            VAUXP      => (others => '0'),
            VAUXN      => (others => '0'),
            CHANNEL    => channel,
            EOC        => eoc,
            EOS        => eos,
            ALM        => open,
            OT         => open
        );

    -- DRP Readout Sequencer
    p_drp: process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state       <= WAIT_EOS;
                den        <= '0';
                tick_reg   <= '0';
                temp_reg   <= (others => '0');
                vccint_reg <= (others => '0');
            else
                den      <= '0';
                tick_reg <= '0';
                case state is
                    when WAIT_EOS =>
                        if eos = '1' then
                            daddr <= "0000000"; -- 0x00: Temp
                            den   <= '1';
                            state <= WAIT_TEMP_DRDY;
                        end if;

                    when WAIT_TEMP_DRDY =>
                        if drdy = '1' then
                            temp_reg <= unsigned(do_sig(15 downto 4));
                            daddr    <= "0000001"; -- 0x01: VCCINT
                            den      <= '1';
                            state    <= WAIT_VCCINT_DRDY;
                        end if;

                    when WAIT_VCCINT_DRDY =>
                        if drdy = '1' then
                            vccint_reg <= unsigned(do_sig(15 downto 4));
                            tick_reg   <= '1';
                            state      <= WAIT_EOS;
                        end if;

                    when others =>
                        state <= WAIT_EOS;
                end case;
            end if;
        end if;
    end process p_drp;

    -- Output Mux (allows simulation override since XADC has no real analog stimulus in RTL sim)
    tick_out        <= sim_tick when sim_override = '1' else tick_reg;
    temp_code_out   <= sim_temp_code when sim_override = '1' else temp_reg;
    vccint_code_out <= sim_vccint_code when sim_override = '1' else vccint_reg;

end architecture rtl;
