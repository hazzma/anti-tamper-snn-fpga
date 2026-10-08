--------------------------------------------------------------------------------
-- File: spike_encoder.vhd
-- Description: 14-Channel Real-Time Level-Crossing Spike Encoder for SNN Anti-Tamper
-- Conforms to FSD Section 4.4 & python/features_ref.py (Bit-Exact Logic)
-- Single Clock Domain (100 MHz), Synchronous Reset
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.snn_params_pkg.all;

entity spike_encoder is
    generic (
        -- Default Thresholds
        DEF_TH_T_POS   : integer := 8;
        DEF_TH_T_NEG   : integer := 8;
        DEF_TH_TT_POS  : integer := 4;
        DEF_TH_TT_NEG  : integer := 4;
        DEF_TH_VD_NEG  : integer := 6;
        DEF_TH_VD_POS  : integer := 6;
        DEF_TH_VS_NEG  : integer := 4;
        DEF_TH_VN      : integer := 5;
        DEF_TH_FD_NEG  : integer := 25;
        DEF_TH_FD_POS  : integer := 25;
        DEF_TH_FN_HI   : integer := 15;
        DEF_TH_FN_LO   : integer := 1
    );
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;
        
        -- Feature inputs from feature_unit
        feat_valid   : in  std_logic;
        t_dev        : in  signed(15 downto 0);
        t_trend      : in  signed(15 downto 0);
        v_dev        : in  signed(15 downto 0);
        v_step       : in  signed(15 downto 0);
        v_noise      : in  signed(15 downto 0);
        f_dev        : in  signed(15 downto 0);
        f_noise      : in  signed(15 downto 0);
        m_val        : in  unsigned(7 downto 0);
        
        -- Encoded Spikes Output (14 channels)
        spikes_valid : out std_logic;
        spikes       : out std_logic_vector(13 downto 0)
    );
end entity spike_encoder;

architecture rtl of spike_encoder is

    signal m_bad_consec : unsigned(7 downto 0) := (others => '0');

begin

    process(clk)
        variable spk_var : std_logic_vector(13 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                m_bad_consec <= (others => '0');
                spikes       <= (others => '0');
                spikes_valid <= '0';
            else
                spikes_valid <= feat_valid;
                
                if feat_valid = '1' then
                    spk_var := (others => '0');
                    
                    -- Channel 0: T_dev >= th_t_pos
                    if t_dev >= to_signed(DEF_TH_T_POS, 16) then
                        spk_var(0) := '1';
                    end if;
                    
                    -- Channel 1: T_dev <= -th_t_neg
                    if t_dev <= to_signed(-DEF_TH_T_NEG, 16) then
                        spk_var(1) := '1';
                    end if;
                    
                    -- Channel 2: T_trend >= th_tt_pos
                    if t_trend >= to_signed(DEF_TH_TT_POS, 16) then
                        spk_var(2) := '1';
                    end if;
                    
                    -- Channel 3: T_trend <= -th_tt_neg
                    if t_trend <= to_signed(-DEF_TH_TT_NEG, 16) then
                        spk_var(3) := '1';
                    end if;
                    
                    -- Channel 4: V_dev <= -th_vd_neg
                    if v_dev <= to_signed(-DEF_TH_VD_NEG, 16) then
                        spk_var(4) := '1';
                    end if;
                    
                    -- Channel 5: V_dev >= th_vd_pos
                    if v_dev >= to_signed(DEF_TH_VD_POS, 16) then
                        spk_var(5) := '1';
                    end if;
                    
                    -- Channel 6: V_step <= -th_vs_neg
                    if v_step <= to_signed(-DEF_TH_VS_NEG, 16) then
                        spk_var(6) := '1';
                    end if;
                    
                    -- Channel 7: V_noise >= th_vn
                    if v_noise >= to_signed(DEF_TH_VN, 16) then
                        spk_var(7) := '1';
                    end if;
                    
                    -- Channel 8: F_dev <= -th_fd_neg
                    if f_dev <= to_signed(-DEF_TH_FD_NEG, 16) then
                        spk_var(8) := '1';
                    end if;
                    
                    -- Channel 9: F_dev >= th_fd_pos
                    if f_dev >= to_signed(DEF_TH_FD_POS, 16) then
                        spk_var(9) := '1';
                    end if;
                    
                    -- Channel 10: F_noise >= th_fn_hi
                    if f_noise >= to_signed(DEF_TH_FN_HI, 16) then
                        spk_var(10) := '1';
                    end if;
                    
                    -- Channel 11: F_noise <= th_fn_lo
                    if f_noise <= to_signed(DEF_TH_FN_LO, 16) then
                        spk_var(11) := '1';
                    end if;
                    
                    -- Channel 12: M >= 1
                    if m_val >= 1 then
                        spk_var(12) := '1';
                    end if;
                    
                    -- Channel 13: M >= 2 or consecutive bad ticks
                    if m_val >= 1 then
                        m_bad_consec <= m_bad_consec + 1;
                        if m_val >= 2 or m_bad_consec >= 1 then
                            spk_var(13) := '1';
                        end if;
                    else
                        m_bad_consec <= (others => '0');
                    end if;
                    
                    spikes <= spk_var;
                end if;
            end if;
        end if;
    end process;

end architecture rtl;
