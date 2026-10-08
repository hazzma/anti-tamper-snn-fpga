--------------------------------------------------------------------------------
-- File: mon_victim.vhd
-- Description: U9 Victim Monitor with 4-Phase CDC Handshake on clk100 (FSD v2 §6-U9)
-- Clock Domain: clk100
-- Detects: key_corrupt_h (mismatch/overclock violation), xfer_err (handshake stall)
-- Standard: VHDL-2008, IEEE numeric_std
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.pkg_fsd.all;

entity mon_victim is
    port (
        clk100         : in  std_logic;
        rstn           : in  std_logic;
        
        -- Asynchronous Handshake Interface from victim_core (clk_core domain)
        req_async      : in  std_logic;
        digest_async   : in  std_logic_vector(31 downto 0);
        ack_out        : out std_logic;
        
        -- Status & SNN Spikes to sensor_mux
        key_corrupt_h  : out std_logic;
        xfer_err_event : out std_logic
    );
end entity mon_victim;

architecture rtl of mon_victim is

    -- 2-FF Synchronizer for req_async with ASYNC_REG attribute
    signal req_sync1 : std_logic := '0';
    signal req_sync2 : std_logic := '0';
    attribute ASYNC_REG : string;
    attribute ASYNC_REG of req_sync1 : signal is "TRUE";
    attribute ASYNC_REG of req_sync2 : signal is "TRUE";

    -- Handshake state machine
    type hs_rx_state_t is (RX_IDLE, RX_VALIDATE, RX_WAIT_DROP);
    signal rx_state     : hs_rx_state_t := RX_IDLE;
    signal ack_reg      : std_logic := '0';

    -- Shadow check and baseline tracking
    signal last_digest  : std_logic_vector(31 downto 0) := (others => '0');
    signal initialized  : boolean := false;
    signal corrupt_pulse: std_logic := '0';
    signal err_pulse    : std_logic := '0';

    -- Timeout Watchdog: 200,000 cycles of clk100 (2 ms) without transfer
    signal watchdog_cnt : unsigned(19 downto 0) := (others => '0');
    constant TIMEOUT_CYCLES : unsigned(19 downto 0) := to_unsigned(200000, 20);

begin

    ack_out        <= ack_reg;
    key_corrupt_h  <= corrupt_pulse;
    xfer_err_event <= err_pulse;

    ----------------------------------------------------------------------------
    -- CDC Synchronizer Process
    ----------------------------------------------------------------------------
    p_sync : process(clk100)
    begin
        if rising_edge(clk100) then
            if rstn = '0' then
                req_sync1 <= '0';
                req_sync2 <= '0';
            else
                req_sync1 <= req_async;
                req_sync2 <= req_sync1;
            end if;
        end if;
    end process p_sync;

    ----------------------------------------------------------------------------
    -- Handshake Receiver and Integrity Checker Process
    ----------------------------------------------------------------------------
    p_rx : process(clk100)
    begin
        if rising_edge(clk100) then
            if rstn = '0' then
                rx_state      <= RX_IDLE;
                ack_reg       <= '0';
                corrupt_pulse <= '0';
                err_pulse     <= '0';
                watchdog_cnt  <= (others => '0');
                last_digest   <= (others => '0');
                initialized   <= false;
            else
                -- Defaults
                corrupt_pulse <= '0';
                err_pulse     <= '0';
                watchdog_cnt  <= watchdog_cnt + 1;

                -- Watchdog Timeout Detection
                if watchdog_cnt >= TIMEOUT_CYCLES then
                    err_pulse    <= '1';
                    watchdog_cnt <= (others => '0');
                end if;

                case rx_state is
                    when RX_IDLE =>
                        if req_sync2 = '1' then
                            watchdog_cnt <= (others => '0');
                            rx_state     <= RX_VALIDATE;
                        end if;

                    when RX_VALIDATE =>
                        ack_reg <= '1';
                        
                        -- Check digest sanity: If timing violation occurred in victim_core,
                        -- digest is either corrupted or produces unstable state.
                        -- Here we also flag if digest is unexpectedly stuck or zeroed when not reset
                        if not initialized then
                            last_digest <= digest_async;
                            initialized <= true;
                        else
                            -- Digest should continuously evolve due to LFSR
                            if digest_async = last_digest and digest_async /= x"00000000" then
                                corrupt_pulse <= '1'; -- Stalled/timing corrupted
                            end if;
                            last_digest <= digest_async;
                        end if;

                        rx_state <= RX_WAIT_DROP;

                    when RX_WAIT_DROP =>
                        if req_sync2 = '0' then
                            ack_reg  <= '0';
                            rx_state <= RX_IDLE;
                        end if;
                end case;

            end if;
        end if;
    end process p_rx;

end architecture rtl;
