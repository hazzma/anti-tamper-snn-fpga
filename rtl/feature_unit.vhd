--------------------------------------------------------------------------------
-- File: feature_unit.vhd
-- Description: 8-Feature Real-Time Integer Extraction Unit for SNN Anti-Tamper
-- Conforms to FSD Section 4.3 & python/features_ref.py (Bit-Exact Arithmetic)
-- Single Clock Domain (100 MHz), Synchronous Reset
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.snn_params_pkg.all;

entity feature_unit is
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;
        tick        : in  std_logic; -- Sensor measurement tick (XADC EOS ~0.53 ms)
        
        -- Raw Sensor Inputs
        t_raw       : in  unsigned(15 downto 0);
        v_raw       : in  unsigned(15 downto 0);
        f_raw       : in  unsigned(15 downto 0);
        m_raw       : in  unsigned(7 downto 0);
        
        -- Calibration Reference Inputs (Enrolled or Baseline)
        ref_t       : in  signed(15 downto 0);
        ref_v       : in  signed(15 downto 0);
        ref_f       : in  signed(15 downto 0);
        
        -- Extracted Features Output
        feat_valid  : out std_logic;
        t_dev       : out signed(15 downto 0);
        t_trend     : out signed(15 downto 0);
        v_dev       : out signed(15 downto 0);
        v_step      : out signed(15 downto 0);
        v_noise     : out signed(15 downto 0);
        f_dev       : out signed(15 downto 0);
        f_noise     : out signed(15 downto 0);
        m_val       : out unsigned(7 downto 0)
    );
end entity feature_unit;

architecture rtl of feature_unit is

    -- Internal Registers in Q16.16 Format (32-bit signed)
    signal t_ema1      : signed(31 downto 0) := (others => '0');
    signal t_ema2      : signed(31 downto 0) := (others => '0');
    signal v_ema       : signed(31 downto 0) := (others => '0');
    signal v_prev      : signed(15 downto 0) := (others => '0');
    signal v_noise_reg : signed(31 downto 0) := (others => '0');
    signal f_ema       : signed(31 downto 0) := (others => '0');
    signal f_prev      : signed(15 downto 0) := (others => '0');
    signal f_noise_reg : signed(31 downto 0) := (others => '0');
    
    signal initialized : boolean := false;
    
    -- Pipeline delay for valid signal
    signal tick_d1     : std_logic := '0';
    signal tick_d2     : std_logic := '0';

begin

    process(clk)
        variable t_in_q16   : signed(31 downto 0);
        variable v_in_q16   : signed(31 downto 0);
        variable f_in_q16   : signed(31 downto 0);
        
        variable v_step_var : signed(15 downto 0);
        variable f_step_var : signed(15 downto 0);
        variable v_step_abs : signed(31 downto 0);
        variable f_step_abs : signed(31 downto 0);
        
        variable t_diff1    : signed(31 downto 0);
        variable t_diff2    : signed(31 downto 0);
        variable v_diff     : signed(31 downto 0);
        variable f_diff     : signed(31 downto 0);
        variable vn_diff    : signed(31 downto 0);
        variable fn_diff    : signed(31 downto 0);
        
    begin
        if rising_edge(clk) then
            if rst = '1' then
                t_ema1      <= (others => '0');
                t_ema2      <= (others => '0');
                v_ema       <= (others => '0');
                v_prev      <= (others => '0');
                v_noise_reg <= (others => '0');
                f_ema       <= (others => '0');
                f_prev      <= (others => '0');
                f_noise_reg <= (others => '0');
                initialized <= false;
                
                t_dev       <= (others => '0');
                t_trend     <= (others => '0');
                v_dev       <= (others => '0');
                v_step      <= (others => '0');
                v_noise     <= (others => '0');
                f_dev       <= (others => '0');
                f_noise     <= (others => '0');
                m_val       <= (others => '0');
                
                tick_d1     <= '0';
                tick_d2     <= '0';
                feat_valid  <= '0';
            else
                tick_d1    <= tick;
                tick_d2    <= tick_d1;
                feat_valid <= tick_d2;
                
                if tick = '1' then
                    -- Align raw inputs to Q16.16 signed
                    t_in_q16 := signed(resize(t_raw, 32)) sll Q_FRAC_BITS;
                    v_in_q16 := signed(resize(v_raw, 32)) sll Q_FRAC_BITS;
                    f_in_q16 := signed(resize(f_raw, 32)) sll Q_FRAC_BITS;
                    
                    if not initialized then
                        t_ema1      <= t_in_q16;
                        t_ema2      <= t_in_q16;
                        v_ema       <= v_in_q16;
                        v_prev      <= signed(v_raw);
                        v_noise_reg <= (others => '0');
                        f_ema       <= f_in_q16;
                        f_prev      <= signed(f_raw);
                        f_noise_reg <= (others => '0');
                        initialized <= true;
                    else
                        -- Calculate EMA updates
                        -- ema += ((in << 16) - ema) >> k
                        t_diff1 := t_in_q16 - t_ema1;
                        t_diff2 := t_in_q16 - t_ema2;
                        v_diff  := v_in_q16 - v_ema;
                        f_diff  := f_in_q16 - f_ema;
                        
                        t_ema1 <= t_ema1 + shift_right(t_diff1, EMA_K_T1_SHIFT);
                        t_ema2 <= t_ema2 + shift_right(t_diff2, EMA_K_T2_SHIFT);
                        v_ema  <= v_ema  + shift_right(v_diff,  EMA_K_T1_SHIFT);
                        f_ema  <= f_ema  + shift_right(f_diff,  EMA_K_T1_SHIFT);
                        
                        -- Step calculation
                        v_step_var := signed(v_raw) - v_prev;
                        f_step_var := signed(f_raw) - f_prev;
                        v_prev     <= signed(v_raw);
                        f_prev     <= signed(f_raw);
                        
                        v_step_abs := signed(resize(unsigned(abs(v_step_var)), 32)) sll Q_FRAC_BITS;
                        f_step_abs := signed(resize(unsigned(abs(f_step_var)), 32)) sll Q_FRAC_BITS;
                        
                        vn_diff := v_step_abs - v_noise_reg;
                        fn_diff := f_step_abs - f_noise_reg;
                        
                        v_noise_reg <= v_noise_reg + shift_right(vn_diff, EMA_K_E_SHIFT);
                        f_noise_reg <= f_noise_reg + shift_right(fn_diff, EMA_K_E_SHIFT);
                    end if;
                end if;
                
                -- Pipeline Stage 1: Feature Calculation
                if tick_d1 = '1' then
                    -- T_dev = (t_ema1 >> 16) - ref_t
                    t_dev   <= resize(shift_right(t_ema1, Q_FRAC_BITS)(15 downto 0), 16) - ref_t;
                    
                    -- T_trend = (t_ema1 - t_ema2) >> 16
                    t_trend <= resize(shift_right(t_ema1 - t_ema2, Q_FRAC_BITS)(15 downto 0), 16);
                    
                    -- V_dev = (v_ema >> 16) - ref_v
                    v_dev   <= resize(shift_right(v_ema, Q_FRAC_BITS)(15 downto 0), 16) - ref_v;
                    
                    -- V_step = v_raw - v_prev (registered)
                    v_step  <= signed(v_raw) - v_prev;
                    
                    -- V_noise = v_noise_reg >> 16
                    v_noise <= resize(shift_right(v_noise_reg, Q_FRAC_BITS)(15 downto 0), 16);
                    
                    -- F_dev = (f_ema >> 16) - ref_f
                    f_dev   <= resize(shift_right(f_ema, Q_FRAC_BITS)(15 downto 0), 16) - ref_f;
                    
                    -- F_noise = f_noise_reg >> 16
                    f_noise <= resize(shift_right(f_noise_reg, Q_FRAC_BITS)(15 downto 0), 16);
                    
                    -- M = m_raw
                    m_val   <= m_raw;
                end if;
                
            end if;
        end if;
    end process;

end architecture rtl;
