--------------------------------------------------------------------------------
-- File: lif_neuron.vhd
-- Description: Single-Neuron Leaky Integrate-and-Fire (LIF) for Anti-Tamper
-- Conforms to FSD Section 4.5 & python/golden_snn.py (Bit-Exact Arithmetic)
-- Synaptic weights and parameters imported from snn_weights_pkg.vhd
-- Single Clock Domain (100 MHz), Synchronous Reset
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.snn_params_pkg.all;
use work.snn_weights_pkg.all;

entity lif_neuron is
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;
        
        -- Input Spikes
        spikes_valid : in  std_logic;
        spikes       : in  std_logic_vector(13 downto 0);
        
        -- Neuron State and Output
        step_done    : out std_logic;
        spike_out    : out std_logic;
        v_mem_out    : out signed(15 downto 0)
    );
end entity lif_neuron;

architecture rtl of lif_neuron is

    signal v_mem : signed(15 downto 0) := (others => '0');

begin

    v_mem_out <= v_mem;

    process(clk)
        variable leak       : signed(15 downto 0);
        variable v_leaked   : signed(15 downto 0);
        variable syn_sum    : signed(15 downto 0);
        variable v_acc      : signed(31 downto 0);
        variable v_sat      : signed(15 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                v_mem     <= (others => '0');
                spike_out <= '0';
                step_done <= '0';
            else
                step_done <= spikes_valid;
                
                if spikes_valid = '1' then
                    -- 1. Leak calculation: v - (v >>> L)
                    leak     := shift_right(v_mem, LEAK_L_PARAM);
                    v_leaked := v_mem - leak;
                    
                    -- 2. Synaptic integration: sum(W[i] * spikes[i])
                    syn_sum  := (others => '0');
                    for i in 0 to 13 loop
                        if spikes(i) = '1' then
                            syn_sum := syn_sum + resize(W(i), 16);
                        end if;
                    end loop;
                    
                    v_acc := resize(v_leaked, 32) + resize(syn_sum, 32);
                    
                    -- 3. Saturation int16 [-32768, 32767]
                    if v_acc > 32767 then
                        v_sat := to_signed(32767, 16);
                    elsif v_acc < -32768 then
                        v_sat := to_signed(-32768, 16);
                    else
                        v_sat := resize(v_acc, 16);
                    end if;
                    
                    -- 4. Threshold & Soft Reset
                    if v_sat >= to_signed(VTH_PARAM, 16) then
                        spike_out <= '1';
                        v_mem     <= v_sat - to_signed(VTH_PARAM, 16);
                    else
                        spike_out <= '0';
                        v_mem     <= v_sat;
                    end if;
                else
                    spike_out <= '0';
                end if;
            end if;
        end if;
    end process;

end architecture rtl;
