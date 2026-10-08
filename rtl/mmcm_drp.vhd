--------------------------------------------------------------------------------
-- File: mmcm_drp.vhd
-- Description: U7 MMCM Dynamic Reconfiguration Port Controller (FSD v2 §6-U7 & XAPP888)
-- Controls CLKOUT0_DIVIDE runtime for glitch, set, stop, and sweep operations
-- Clock Domain: clk100
-- Standard: VHDL-2008, IEEE numeric_std
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mmcm_drp is
    port (
        clk100          : in  std_logic;
        rstn            : in  std_logic;
        
        -- DRP Physical Interface to MMCME2_ADV
        drp_daddr       : out std_logic_vector(6 downto 0);
        drp_den         : out std_logic;
        drp_dwe         : out std_logic;
        drp_di          : out std_logic_vector(15 downto 0);
        drp_do          : in  std_logic_vector(15 downto 0);
        drp_drdy        : in  std_logic;
        mmcm_locked     : in  std_logic;
        
        -- Control Request Interface (from cmd_parser / attack_seq)
        glitch_req      : in  std_logic;
        glitch_div      : in  unsigned(7 downto 0);
        glitch_dur_us   : in  unsigned(15 downto 0);
        
        set_div_req     : in  std_logic;
        set_div_val     : in  unsigned(7 downto 0);
        
        -- Status
        drp_busy        : out std_logic;
        glitch_active   : out std_logic
    );
end entity mmcm_drp;

architecture rtl of mmcm_drp is

    type drp_state_t is (
        DRP_IDLE,
        DRP_READ_CMD,
        DRP_WAIT_READ_DRDY,
        DRP_WRITE_CMD,
        DRP_WAIT_WRITE_DRDY,
        DRP_HOLD_DURATION,
        DRP_RESTORE_READ,
        DRP_WAIT_RESTORE_READ_DRDY,
        DRP_RESTORE_WRITE,
        DRP_WAIT_RESTORE_WRITE_DRDY
    );
    signal state : drp_state_t := DRP_IDLE;

    signal target_div  : unsigned(7 downto 0) := to_unsigned(40, 8);
    signal timer_us    : unsigned(23 downto 0) := (others => '0');
    signal dur_cycles  : unsigned(23 downto 0) := (others => '0');
    signal is_glitch   : boolean := false;
    signal busy_reg    : std_logic := '0';
    signal glitch_reg  : std_logic := '0';

begin

    drp_busy      <= busy_reg;
    glitch_active <= glitch_reg;

    p_drp_fsm : process(clk100)
    begin
        if rising_edge(clk100) then
            if rstn = '0' then
                state       <= DRP_IDLE;
                drp_den     <= '0';
                drp_dwe     <= '0';
                drp_daddr   <= (others => '0');
                drp_di      <= (others => '0');
                busy_reg    <= '0';
                glitch_reg  <= '0';
                timer_us    <= (others => '0');
                is_glitch   <= false;
            else
                drp_den <= '0';
                drp_dwe <= '0';

                case state is
                    when DRP_IDLE =>
                        busy_reg   <= '0';
                        glitch_reg <= '0';

                        if glitch_req = '1' then
                            busy_reg   <= '1';
                            glitch_reg <= '1';
                            is_glitch  <= true;
                            target_div <= glitch_div;
                            dur_cycles <= resize(glitch_dur_us * 100, 24); -- 100 cycles per us
                            state      <= DRP_READ_CMD;
                        elsif set_div_req = '1' then
                            busy_reg   <= '1';
                            is_glitch  <= false;
                            target_div <= set_div_val;
                            state      <= DRP_READ_CMD;
                        end if;

                    when DRP_READ_CMD =>
                        -- Address 0x08 for MMCM CLKOUT0 register 1 (XAPP888)
                        drp_daddr <= "0001000";
                        drp_den   <= '1';
                        drp_dwe   <= '0';
                        state     <= DRP_WAIT_READ_DRDY;

                    when DRP_WAIT_READ_DRDY =>
                        if drp_drdy = '1' then
                            state <= DRP_WRITE_CMD;
                        end if;

                    when DRP_WRITE_CMD =>
                        drp_daddr <= "0001000";
                        drp_den   <= '1';
                        drp_dwe   <= '1';
                        -- Modify high/low divide bits using target_div
                        drp_di    <= x"10" & std_logic_vector(target_div);
                        state     <= DRP_WAIT_WRITE_DRDY;

                    when DRP_WAIT_WRITE_DRDY =>
                        if drp_drdy = '1' then
                            if is_glitch then
                                timer_us <= (others => '0');
                                state    <= DRP_HOLD_DURATION;
                            else
                                state <= DRP_IDLE;
                            end if;
                        end if;

                    when DRP_HOLD_DURATION =>
                        timer_us <= timer_us + 1;
                        if timer_us >= dur_cycles then
                            target_div <= to_unsigned(40, 8); -- Restore nominal 25 MHz (DIV=40)
                            state      <= DRP_RESTORE_READ;
                        end if;

                    when DRP_RESTORE_READ =>
                        drp_daddr <= "0001000";
                        drp_den   <= '1';
                        drp_dwe   <= '0';
                        state     <= DRP_WAIT_RESTORE_READ_DRDY;

                    when DRP_WAIT_RESTORE_READ_DRDY =>
                        if drp_drdy = '1' then
                            state <= DRP_RESTORE_WRITE;
                        end if;

                    when DRP_RESTORE_WRITE =>
                        drp_daddr <= "0001000";
                        drp_den   <= '1';
                        drp_dwe   <= '1';
                        drp_di    <= x"1028"; -- DIV=40 (0x28)
                        state     <= DRP_WAIT_RESTORE_WRITE_DRDY;

                    when DRP_WAIT_RESTORE_WRITE_DRDY =>
                        if drp_drdy = '1' then
                            state <= DRP_IDLE;
                        end if;

                end case;

            end if;
        end if;
    end process p_drp_fsm;

end architecture rtl;
