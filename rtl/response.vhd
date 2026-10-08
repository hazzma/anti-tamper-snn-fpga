--------------------------------------------------------------------------------
-- File: response.vhd
-- Description: U13 Active Defense & Escalation Response Controller (FSD v2 §6-U13)
-- Features: Dual-path trigger (Instant L1 vs SNN L3), Escalation Counter (D11),
--           BYPASS mode (D10), UNLOCK command (A12), and Cycle Latency Meter.
-- Standard: VHDL-2008, IEEE numeric_std
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.pkg_fsd.all;

entity response is
    port (
        clk100          : in  std_logic;
        rstn            : in  std_logic;
        
        -- Trigger Inputs
        hard_alert_l1   : in  std_logic; -- Layer 1 instant hard flags
        snn_alert_l3    : in  std_logic; -- Layer 3 SNN fire
        snn_class_in    : in  std_logic_vector(1 downto 0);
        
        -- Configuration & Control
        arm_en          : in  std_logic; -- 1: active defense, 0: log-only
        bypass_snn      : in  std_logic; -- 1: baseline mode (SNN disabled)
        esc_th          : in  unsigned(7 downto 0); -- default 2 (instant=1)
        unlock_pulse    : in  std_logic; -- UNLOCK: clear count & latch
        
        -- Latency Meter Interface
        attack_active   : in  std_logic; -- High when attack scenario is running
        
        -- Action Outputs
        zeroize_pulse   : out std_logic;
        alert_latched   : out std_logic;
        zeroized_latched: out std_logic;
        alert_count_out : out unsigned(7 downto 0);
        class_out       : out std_logic_vector(1 downto 0);
        latency_cycles  : out unsigned(31 downto 0);
        
        -- Status LEDs
        led_alert       : out std_logic;
        led_zeroized    : out std_logic
    );
end entity response;

architecture rtl of response is

    signal alert_cnt       : unsigned(7 downto 0) := (others => '0');
    signal is_alert        : std_logic := '0';
    signal is_zeroized     : std_logic := '0';
    signal zeroize_p       : std_logic := '0';
    signal class_latched   : std_logic_vector(1 downto 0) := "00";

    -- Cycle Latency Meter
    signal lat_timer       : unsigned(31 downto 0) := (others => '0');
    signal lat_captured    : unsigned(31 downto 0) := (others => '0');
    signal timing_active   : boolean := false;

begin

    zeroize_pulse    <= zeroize_p;
    alert_latched    <= is_alert;
    zeroized_latched <= is_zeroized;
    alert_count_out  <= alert_cnt;
    class_out        <= class_latched;
    latency_cycles   <= lat_captured;
    led_alert        <= is_alert;
    led_zeroized     <= is_zeroized;

    p_response : process(clk100)
        variable trigger_event : boolean;
    begin
        if rising_edge(clk100) then
            if rstn = '0' then
                alert_cnt     <= (others => '0');
                is_alert      <= '0';
                is_zeroized   <= '0';
                zeroize_p     <= '0';
                class_latched <= "00";
                lat_timer     <= (others => '0');
                lat_captured  <= (others => '0');
                timing_active <= false;
            else
                zeroize_p <= '0';

                -- Latency timer counter
                if attack_active = '1' and not timing_active and is_zeroized = '0' then
                    timing_active <= true;
                    lat_timer     <= (others => '0');
                elsif timing_active then
                    lat_timer <= lat_timer + 1;
                end if;

                -- UNLOCK Command Handling (A12:3): Clear latch and alert count
                if unlock_pulse = '1' then
                    alert_cnt     <= (others => '0');
                    is_alert      <= '0';
                    is_zeroized   <= '0'; -- Allows new security cycle, key still requires reload
                    timing_active <= false;
                end if;

                -- Dual-Path Alert Evaluation:
                -- Path 1: Instant L1 Hard Flag
                -- Path 2: SNN Layer 3 (gated by BYPASS)
                trigger_event := (hard_alert_l1 = '1') or ((snn_alert_l3 = '1') and (bypass_snn = '0'));

                if trigger_event then
                    -- Record class
                    if snn_alert_l3 = '1' and bypass_snn = '0' then
                        class_latched <= snn_class_in;
                    else
                        class_latched <= "00"; -- Hard flag attributed to transient/L1
                    end if;

                    -- Increment escalation counter
                    if alert_cnt < 255 then
                        alert_cnt <= alert_cnt + 1;
                    end if;

                    -- Latch alert state
                    is_alert <= '1';

                    -- Escalation check: count >= ESC_TH => ACTION (Zeroize key)
                    if (alert_cnt + 1) >= esc_th then
                        if arm_en = '1' and is_zeroized = '0' then
                            zeroize_p   <= '1';
                            is_zeroized <= '1';
                            if timing_active then
                                lat_captured  <= lat_timer;
                                timing_active <= false;
                            end if;
                        end if;
                    end if;

                end if;

            end if;
        end if;
    end process p_response;

end architecture rtl;
