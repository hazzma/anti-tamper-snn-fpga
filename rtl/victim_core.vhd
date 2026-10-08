--------------------------------------------------------------------------------
-- File: victim_core.vhd
-- Description: U8 Protected Core with 128-bit Key & Heavy Datapath (FSD v2 §6-U8)
-- Clock Domain: clk_core (glitchable/overclockable MMCM domain)
-- Target Fmax: ~110-130 MHz (heavy datapath to force genuine timing violations on overclock >=160MHz)
-- Standard: VHDL-2008, IEEE numeric_std
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity victim_core is
    port (
        clk_core     : in  std_logic;
        rstn_core    : in  std_logic;
        
        -- Key Management (from clk100 via sync/latch or direct config)
        key_load_en  : in  std_logic;
        key_in       : in  std_logic_vector(127 downto 0);
        zeroize_pulse: in  std_logic;
        
        -- 4-Phase Handshake to mon_victim on clk100
        req_out      : out std_logic;
        ack_in       : in  std_logic;
        digest_out   : out std_logic_vector(31 downto 0);
        
        -- Status & Display
        zeroized_out     : out std_logic;
        key_disp         : out std_logic_vector(15 downto 0);
        
        -- Memory Integrity Injection (BTND cosmic ray & SW12 hard tamper)
        cosmic_flip_p    : in  std_logic;
        corrupt_inject_h : in  std_logic;
        key_corrupt_out  : out std_logic
    );
end entity victim_core;

architecture rtl of victim_core is

    -- Dual-copy 128-bit key store with register-based storage (FSD v2 §6-U8)
    signal key_primary : std_logic_vector(127 downto 0) := x"0123456789ABCDEF0123456789ABCDEF";
    signal key_shadow  : std_logic_vector(127 downto 0) := x"0123456789ABCDEF0123456789ABCDEF";
    signal zeroized    : std_logic := '0';

    -- LFSR32 Pseudo-random state
    signal lfsr_reg    : unsigned(31 downto 0) := x"ACE12468";

    -- Heavy datapath pipelined stages (target Fmax ~110-130 MHz)
    signal mul_stage1  : unsigned(63 downto 0) := (others => '0');
    signal mul_stage2  : unsigned(63 downto 0) := (others => '0');
    signal mul_stage3  : unsigned(63 downto 0) := (others => '0');

    -- XOR Diffusion registers
    signal diff_reg1   : std_logic_vector(127 downto 0) := (others => '0');
    signal diff_reg2   : std_logic_vector(127 downto 0) := (others => '0');

    -- Epoch and Handshake FSM
    signal epoch_count : unsigned(9 downto 0) := (others => '0');
    type hs_state_t is (HS_IDLE, HS_WAIT_ACK, HS_WAIT_NACK);
    signal hs_state    : hs_state_t := HS_IDLE;
    signal digest_reg  : std_logic_vector(31 downto 0) := (others => '0');
    signal req_reg     : std_logic := '0';

begin

    zeroized_out    <= zeroized;
    digest_out      <= digest_reg;
    req_out         <= req_reg;
    key_disp        <= key_primary(127 downto 112);
    key_corrupt_out <= '1' when (key_primary /= key_shadow) or corrupt_inject_h = '1' else '0';

    ----------------------------------------------------------------------------
    -- Key Store & Heavy Datapath Process
    ----------------------------------------------------------------------------
    p_datapath : process(clk_core)
        variable lfsr_next : unsigned(31 downto 0);
        variable xor_part  : std_logic_vector(31 downto 0);
    begin
        if rising_edge(clk_core) then
            if rstn_core = '0' then
                key_primary <= x"0123456789ABCDEF0123456789ABCDEF";
                key_shadow  <= x"0123456789ABCDEF0123456789ABCDEF";
                zeroized    <= '0';
                lfsr_reg    <= x"ACE12468";
                mul_stage1  <= (others => '0');
                mul_stage2  <= (others => '0');
                mul_stage3  <= (others => '0');
                diff_reg1   <= (others => '0');
                diff_reg2   <= (others => '0');
                epoch_count <= (others => '0');
                digest_reg  <= (others => '0');
                req_reg     <= '0';
                hs_state    <= HS_IDLE;
            else
                -- Zeroization logic (instant wipe within clock cycle)
                if zeroize_pulse = '1' then
                    key_primary <= (others => '0');
                    key_shadow  <= (others => '0');
                    zeroized    <= '1';
                elsif key_load_en = '1' then
                    key_primary <= key_in;
                    key_shadow  <= key_in;
                    zeroized    <= '0';
                elsif zeroized = '0' then
                    if corrupt_inject_h = '1' then
                        -- Extreme Mode Memory Integrity Tamper (SW12 / H6): corrupt high word
                        key_primary(127 downto 112) <= x"DEAD";
                    elsif cosmic_flip_p = '1' then
                        -- Manual Cosmic Ray Single Event Upset (BTND): flip 1 bit on display (0123 <-> 0122)
                        key_primary(112) <= not key_primary(112);
                        key_shadow(112)  <= not key_shadow(112);
                    end if;
                end if;

                -- 32-bit LFSR Update
                if lfsr_reg(31) = '1' then
                    lfsr_next := (lfsr_reg(30 downto 0) & '0') xor x"80200003";
                else
                    lfsr_next := (lfsr_reg(30 downto 0) & '0');
                end if;
                lfsr_reg <= lfsr_next;

                -- Heavy Arithmetic Chain: 3-stage multiply-add
                mul_stage1 <= lfsr_reg * unsigned(key_primary(31 downto 0));
                mul_stage2 <= mul_stage1 + (lfsr_reg * unsigned(key_primary(63 downto 32)));
                mul_stage3 <= mul_stage2 + (lfsr_reg * unsigned(key_primary(95 downto 64)));

                -- Dual 128-bit XOR Diffusion
                diff_reg1 <= key_primary xor std_logic_vector(mul_stage3) & std_logic_vector(mul_stage3);
                diff_reg2 <= diff_reg1 xor (key_shadow(110 downto 0) & key_shadow(127 downto 111));

                -- Epoch Counter (1024 cycles)
                epoch_count <= epoch_count + 1;

                -- 4-Phase Handshake FSM
                case hs_state is
                    when HS_IDLE =>
                        if epoch_count = 1023 then
                            -- Generate 32-bit digest
                            xor_part := diff_reg2(31 downto 0) xor diff_reg2(63 downto 32) xor 
                                        diff_reg2(95 downto 64) xor diff_reg2(127 downto 96);
                            digest_reg <= xor_part xor std_logic_vector(lfsr_reg);
                            req_reg    <= '1';
                            hs_state   <= HS_WAIT_ACK;
                        end if;

                    when HS_WAIT_ACK =>
                        if ack_in = '1' then
                            req_reg  <= '0';
                            hs_state <= HS_WAIT_NACK;
                        end if;

                    when HS_WAIT_NACK =>
                        if ack_in = '0' then
                            hs_state <= HS_IDLE;
                        end if;
                end case;

            end if;
        end if;
    end process p_datapath;

end architecture rtl;
