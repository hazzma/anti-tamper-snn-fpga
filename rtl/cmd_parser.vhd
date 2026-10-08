--------------------------------------------------------------------------------
-- File: cmd_parser.vhd
-- Description: U2b ASCII Command Parser & Preset Attack Sequencer (FSD v2 §6-U2b & §8)
-- Interprets line-based commands and handles live demo shortcuts (G, S, K, UNLOCK)
-- Clock Domain: clk100
-- Standard: VHDL-2008, IEEE numeric_std
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.pkg_fsd.all;

entity cmd_parser is
    port (
        clk100          : in  std_logic;
        rstn            : in  std_logic;
        
        -- Byte Interface from/to uart_host
        rx_byte         : in  std_logic_vector(7 downto 0);
        rx_valid        : in  std_logic;
        
        tx_byte         : out std_logic_vector(7 downto 0);
        tx_valid        : out std_logic;
        tx_ready        : in  std_logic;
        
        -- Control Registers Output
        sensor_mode     : out std_logic_vector(1 downto 0);
        arm_en          : out std_logic;
        bypass_snn      : out std_logic;
        esc_th          : out unsigned(7 downto 0);
        unlock_pulse    : out std_logic;
        
        -- Key Store Load
        key_load_en     : out std_logic;
        key_data        : out std_logic_vector(127 downto 0);
        manual_wipe     : out std_logic;
        
        -- SNN Synthetic Spike Injection (Mode A)
        synth_spikes    : out std_logic_vector(11 downto 0);
        synth_q         : out q_array_t;
        
        -- MMCM DRP Control Interface
        glitch_req      : out std_logic;
        glitch_div      : out unsigned(7 downto 0);
        glitch_dur_us   : out unsigned(15 downto 0);
        
        -- Stressor Control
        stress_en       : out std_logic;
        
        -- Attack Sequencer Status (for Latency Meter)
        attack_active   : out std_logic;
        
        -- Telemetry Mode
        log_mode        : out std_logic_vector(1 downto 0)
    );
end entity cmd_parser;

architecture rtl of cmd_parser is

    -- Line buffer
    type line_buf_t is array(0 to 31) of std_logic_vector(7 downto 0);
    signal line_buf   : line_buf_t := (others => (others => '0'));
    signal buf_idx    : integer range 0 to 31 := 0;

    -- Reply string transmitter
    type reply_buf_t is array(0 to 39) of character;
    signal reply_msg  : reply_buf_t := (others => ' ');
    signal reply_len  : integer range 0 to 40 := 0;
    signal reply_idx  : integer range 0 to 40 := 0;
    signal tx_active  : boolean := false;

    -- Internal Registers
    signal mode_reg   : std_logic_vector(1 downto 0) := SENSOR_MODE_C; -- Default Mode C
    signal arm_reg    : std_logic := '1'; -- Secure default ARM=1
    signal bypass_reg : std_logic := '0';
    signal esc_th_reg : unsigned(7 downto 0) := to_unsigned(ESC_TH_DEFAULT, 8);
    signal log_reg    : std_logic_vector(1 downto 0) := "01"; -- LOG 1 event

    -- Synthetic spikes
    signal synth_spk_r : std_logic_vector(11 downto 0) := (others => '0');
    signal synth_q_r   : q_array_t := (others => (others => '0'));

    -- Sequencer for Presets SCEN 0-4
    type scen_state_t is (SCEN_IDLE, SCEN_RUN_1, SCEN_RUN_2, SCEN_RUN_3, SCEN_RUN_4);
    signal scen_state : scen_state_t := SCEN_IDLE;
    signal scen_cnt   : unsigned(23 downto 0) := (others => '0');
    signal scen_pulse_cnt : integer range 0 to 16 := 0;
    signal is_attacking : std_logic := '0';

begin

    sensor_mode   <= mode_reg;
    arm_en        <= arm_reg;
    bypass_snn    <= bypass_reg;
    esc_th        <= esc_th_reg;
    synth_spikes  <= synth_spk_r;
    synth_q       <= synth_q_r;
    attack_active <= is_attacking;
    log_mode      <= log_reg;
    key_data      <= x"0123456789ABCDEF0123456789ABCDEF";

    ----------------------------------------------------------------------------
    -- Command Reception and Parsing Process
    ----------------------------------------------------------------------------
    p_parse : process(clk100)
        variable char_in : character;
        variable c0, c1, c2 : character;

        procedure set_reply (constant msg : in string) is
        begin
            for i in 1 to msg'length loop
                reply_msg(i - 1) <= msg(msg'left + i - 1);
            end loop;
            reply_msg(msg'length)     <= character'val(13);
            reply_msg(msg'length + 1) <= character'val(10);
            reply_len <= msg'length + 2;
            reply_idx <= 0;
            tx_active <= true;
        end procedure;
    begin
        if rising_edge(clk100) then
            if rstn = '0' then
                buf_idx       <= 0;
                tx_active     <= false;
                reply_idx     <= 0;
                reply_len     <= 0;
                mode_reg      <= SENSOR_MODE_C;
                arm_reg       <= '1';
                bypass_reg    <= '0';
                esc_th_reg    <= to_unsigned(ESC_TH_DEFAULT, 8);
                unlock_pulse  <= '0';
                manual_wipe   <= '0';
                key_load_en   <= '0';
                glitch_req    <= '0';
                glitch_div    <= to_unsigned(40, 8);
                glitch_dur_us <= to_unsigned(2, 16);
                stress_en     <= '0';
                synth_spk_r   <= (others => '0');
                tx_valid      <= '0';
                tx_byte       <= (others => '0');
                is_attacking  <= '0';
                scen_state    <= SCEN_IDLE;
            else
                -- Defaults for 1-cycle pulses
                unlock_pulse <= '0';
                manual_wipe  <= '0';
                key_load_en  <= '0';
                glitch_req   <= '0';
                synth_spk_r  <= (others => '0');

                -- TX Reply Handling
                if tx_active then
                    if tx_ready = '1' and tx_valid = '0' then
                        if reply_idx < reply_len then
                            tx_byte   <= std_logic_vector(to_unsigned(character'pos(reply_msg(reply_idx)), 8));
                            tx_valid  <= '1';
                            reply_idx <= reply_idx + 1;
                        else
                            tx_active <= false;
                            tx_valid  <= '0';
                        end if;
                    else
                        tx_valid <= '0';
                    end if;
                end if;

                -- RX Character Processing
                if rx_valid = '1' then
                    char_in := character'val(to_integer(unsigned(rx_byte)));

                    if char_in = character'val(10) or char_in = character'val(13) then
                        -- End of line: parse command
                        if buf_idx > 0 then
                            c0 := character'val(to_integer(unsigned(line_buf(0))));
                            c1 := character'val(to_integer(unsigned(line_buf(1))));
                            c2 := character'val(to_integer(unsigned(line_buf(2))));

                            -- Command: PING
                            if c0 = 'P' and c1 = 'I' then
                                set_reply("OK SNN-GUARD");

                            -- Command: UNLOCK
                            elsif c0 = 'U' and c1 = 'N' then
                                unlock_pulse <= '1';
                                set_reply("OK UNLOCKED");

                            -- Command: ARM <0/1>
                            elsif c0 = 'A' and c1 = 'R' then
                                if buf_idx >= 5 and line_buf(4) = x"30" then
                                    arm_reg <= '0';
                                else
                                    arm_reg <= '1';
                                end if;
                                set_reply("OK ARM");

                            -- Command: BYPASS <0/1>
                            elsif c0 = 'B' and c1 = 'Y' then
                                if buf_idx >= 8 and line_buf(7) = x"31" then
                                    bypass_reg <= '1';
                                else
                                    bypass_reg <= '0';
                                end if;
                                set_reply("OK BYPASS");

                            -- Command: MODE <A/B/C>
                            elsif c0 = 'M' and c1 = 'O' then
                                if buf_idx >= 6 and line_buf(5) = x"41" then -- 'A'
                                    mode_reg <= SENSOR_MODE_A;
                                elsif buf_idx >= 6 and line_buf(5) = x"42" then -- 'B'
                                    mode_reg <= SENSOR_MODE_B;
                                else
                                    mode_reg <= SENSOR_MODE_C;
                                end if;
                                set_reply("OK MODE");

                            -- Command: KEY WIPE or K
                            elsif c0 = 'K' and (buf_idx = 1 or c1 = ' ') then
                                manual_wipe <= '1';
                                set_reply("OK WIPED");

                            -- Command: GLITCH or G (e.g. G 2 39 for SCEN2)
                            elsif c0 = 'G' then
                                glitch_div    <= to_unsigned(39, 8); -- +2.6% default
                                glitch_dur_us <= to_unsigned(2, 16);
                                glitch_req    <= '1';
                                set_reply("OK GLITCH");

                            -- Command: SCEN <0-4> or S <0-4>
                            elsif c0 = 'S' then
                                if buf_idx >= 2 and line_buf(buf_idx-1) = x"31" then
                                    -- SCEN1: Single Glitch (200 MHz, DIV=5, 5 us)
                                    glitch_div    <= to_unsigned(5, 8);
                                    glitch_dur_us <= to_unsigned(5, 16);
                                    glitch_req    <= '1';
                                    is_attacking  <= '1';
                                elsif buf_idx >= 2 and line_buf(buf_idx-1) = x"32" then
                                    -- SCEN2: Repeat-Probe (+2.6% div 39, 2 us, tiap 2 ms, x8)
                                    scen_state     <= SCEN_RUN_2;
                                    scen_cnt       <= (others => '0');
                                    scen_pulse_cnt <= 0;
                                    is_attacking   <= '1';
                                elsif buf_idx >= 2 and line_buf(buf_idx-1) = x"33" then
                                    -- SCEN3: Combined (clock -2% + VSTRESS 2 ms)
                                    stress_en    <= '1';
                                    is_attacking <= '1';
                                end if;
                                set_reply("OK SCEN");

                            -- Command: VSTRESS
                            elsif c0 = 'V' and c1 = 'S' then
                                stress_en <= '1';
                                set_reply("OK VSTRESS");

                            else
                                set_reply("OK");
                            end if;

                            buf_idx <= 0;
                        end if;

                    else
                        if buf_idx < 31 then
                            line_buf(buf_idx) <= rx_byte;
                            buf_idx <= buf_idx + 1;
                        end if;
                    end if;
                end if;

                -- Sequencer FSM for Repeat-Probe SCEN2 (8 pulses of +2.6% spaced by 2 ms)
                case scen_state is
                    when SCEN_IDLE =>
                        null;

                    when SCEN_RUN_2 =>
                        scen_cnt <= scen_cnt + 1;
                        if scen_cnt = 1 then
                            -- Trigger pulse
                            glitch_div    <= to_unsigned(39, 8);
                            glitch_dur_us <= to_unsigned(2, 16);
                            glitch_req    <= '1';
                            
                            -- In Mode C or A, also inject soft spike (ch 8 clk_soft, q=3)
                            synth_spk_r(CH_CLK_SOFT) <= '1';
                            synth_q_r(CH_CLK_SOFT)   <= to_unsigned(3, 4);
                            
                            scen_pulse_cnt <= scen_pulse_cnt + 1;
                        elsif scen_cnt >= 200000 then -- 2 ms gap (200,000 cycles @ 100MHz)
                            scen_cnt <= (others => '0');
                            if scen_pulse_cnt >= 8 then
                                scen_state   <= SCEN_IDLE;
                                is_attacking <= '0';
                            end if;
                        end if;

                    when others =>
                        scen_state <= SCEN_IDLE;
                end case;

            end if;
        end if;
    end process p_parse;

end architecture rtl;
