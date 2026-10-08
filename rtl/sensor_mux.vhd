--------------------------------------------------------------------------------
-- File: sensor_mux.vhd
-- Description: U11 12-Channel Spike Multiplexer (FSD v2 §6-U11 & §7.1)
-- Selects between Real Monitors, Synthetic Spikes, or Hybrid Mode C (Default)
-- Standard: VHDL-2008, IEEE numeric_std
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.pkg_fsd.all;

entity sensor_mux is
    port (
        clk100          : in  std_logic;
        rstn            : in  std_logic;
        
        -- Mode Selection (D5): "00"=A (Synth), "01"=B (Real), "10"=C (Hybrid)
        mode_sel        : in  std_logic_vector(1 downto 0);
        
        -- Real Hardware Monitor Inputs (Layer 1)
        real_clk_fast_h : in  std_logic;
        real_clk_slow_h : in  std_logic;
        real_clk_stop_h : in  std_logic;
        real_mmcm_unlock: in  std_logic;
        real_v_under_h  : in  std_logic;
        real_v_over_h   : in  std_logic;
        real_key_corr_h : in  std_logic;
        real_jtag_h     : in  std_logic;
        real_clk_soft_spk: in std_logic;
        real_clk_soft_q : in  unsigned(3 downto 0);
        real_v_soft_spk : in  std_logic;
        real_v_soft_q   : in  unsigned(3 downto 0);
        
        -- Synthetic Attack Injection Inputs (from cmd_parser / attack_seq)
        synth_spikes    : in  std_logic_vector(11 downto 0);
        synth_q         : in  q_array_t;
        
        -- Muxed Outputs to SNN Layer 3 (snn_lif)
        spikes_active   : out std_logic_vector(11 downto 0);
        spikes_q_out    : out q_array_t
    );
end entity sensor_mux;

architecture rtl of sensor_mux is
begin

    p_mux : process(clk100)
    begin
        if rising_edge(clk100) then
            if rstn = '0' then
                spikes_active <= (others => '0');
                for i in 0 to N_CH-1 loop
                    spikes_q_out(i) <= (others => '0');
                end loop;
            else
                -- Default inactive
                spikes_active <= (others => '0');
                for i in 0 to N_CH-1 loop
                    spikes_q_out(i) <= (others => '0');
                end loop;

                case mode_sel is
            --------------------------------------------------------------------
            -- Mode A: Full Synthetic Injection
            --------------------------------------------------------------------
            when SENSOR_MODE_A =>
                spikes_active <= synth_spikes;
                spikes_q_out  <= synth_q;

            --------------------------------------------------------------------
            -- Mode B: Full Real Hardware Monitors
            --------------------------------------------------------------------
            when SENSOR_MODE_B =>
                -- Hard channels (q=15 always)
                spikes_active(CH_CLK_FAST_H)    <= real_clk_fast_h;
                spikes_q_out(CH_CLK_FAST_H)     <= to_unsigned(15, 4);

                spikes_active(CH_CLK_SLOW_H)    <= real_clk_slow_h;
                spikes_q_out(CH_CLK_SLOW_H)     <= to_unsigned(15, 4);

                spikes_active(CH_CLK_STOP_H)    <= real_clk_stop_h;
                spikes_q_out(CH_CLK_STOP_H)     <= to_unsigned(15, 4);

                spikes_active(CH_MMCM_UNLOCK_H) <= real_mmcm_unlock;
                spikes_q_out(CH_MMCM_UNLOCK_H)  <= to_unsigned(15, 4);

                spikes_active(CH_V_UNDER_H)     <= real_v_under_h;
                spikes_q_out(CH_V_UNDER_H)      <= to_unsigned(15, 4);

                spikes_active(CH_V_OVER_H)      <= real_v_over_h;
                spikes_q_out(CH_V_OVER_H)       <= to_unsigned(15, 4);

                spikes_active(CH_KEY_CORRUPT_H) <= real_key_corr_h;
                spikes_q_out(CH_KEY_CORRUPT_H)  <= to_unsigned(15, 4);

                spikes_active(CH_JTAG_H)        <= real_jtag_h;
                spikes_q_out(CH_JTAG_H)         <= to_unsigned(15, 4);

                -- Soft channels
                spikes_active(CH_CLK_SOFT)      <= real_clk_soft_spk;
                spikes_q_out(CH_CLK_SOFT)       <= real_clk_soft_q;

                spikes_active(CH_V_SOFT)        <= real_v_soft_spk;
                spikes_q_out(CH_V_SOFT)         <= real_v_soft_q;

            --------------------------------------------------------------------
            -- Mode C (Default): Hybrid (Clock & Victim = REAL, Voltage = SYNTH)
            --------------------------------------------------------------------
            when others => -- SENSOR_MODE_C
                -- Clock channels from Real
                spikes_active(CH_CLK_FAST_H)    <= real_clk_fast_h;
                spikes_q_out(CH_CLK_FAST_H)     <= to_unsigned(15, 4);

                spikes_active(CH_CLK_SLOW_H)    <= real_clk_slow_h;
                spikes_q_out(CH_CLK_SLOW_H)     <= to_unsigned(15, 4);

                spikes_active(CH_CLK_STOP_H)    <= real_clk_stop_h;
                spikes_q_out(CH_CLK_STOP_H)     <= to_unsigned(15, 4);

                spikes_active(CH_MMCM_UNLOCK_H) <= real_mmcm_unlock;
                spikes_q_out(CH_MMCM_UNLOCK_H)  <= to_unsigned(15, 4);

                spikes_active(CH_CLK_SOFT)      <= real_clk_soft_spk;
                spikes_q_out(CH_CLK_SOFT)       <= real_clk_soft_q;

                -- Victim & JTAG from Real
                spikes_active(CH_KEY_CORRUPT_H) <= real_key_corr_h;
                spikes_q_out(CH_KEY_CORRUPT_H)  <= to_unsigned(15, 4);

                spikes_active(CH_JTAG_H)        <= real_jtag_h;
                spikes_q_out(CH_JTAG_H)         <= to_unsigned(15, 4);

                -- Voltage channels from Synth (allows controlled sub-threshold voltage dips)
                spikes_active(CH_V_UNDER_H)     <= synth_spikes(CH_V_UNDER_H);
                spikes_q_out(CH_V_UNDER_H)      <= synth_q(CH_V_UNDER_H);

                spikes_active(CH_V_OVER_H)      <= synth_spikes(CH_V_OVER_H);
                spikes_q_out(CH_V_OVER_H)       <= synth_q(CH_V_OVER_H);

                spikes_active(CH_V_SOFT)        <= synth_spikes(CH_V_SOFT);
                spikes_q_out(CH_V_SOFT)         <= synth_q(CH_V_SOFT);
        end case;
            end if;
        end if;
    end process p_mux;

end architecture rtl;
