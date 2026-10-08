--------------------------------------------------------------------------------
-- File: snn_lif.vhd
-- Description: U12 4-Neuron Leaky Integrate-and-Fire Bank (FSD v2 §6-U12 & §7)
-- Architecture: Balanced Parallel Adder Tree for high-speed 100 MHz timing closure
-- Standard: VHDL-2008, IEEE numeric_std
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.pkg_fsd.all;
use work.pkg_weights_gen.all;

entity snn_lif is
    port (
        clk100         : in  std_logic;
        rstn           : in  std_logic;
        
        -- Synaptic Spike Inputs from sensor_mux
        spikes_active  : in  std_logic_vector(N_CH-1 downto 0);
        spikes_q       : in  q_array_t;
        
        -- Periodic Leak Tick (1 ms pulse)
        leak_tick      : in  std_logic;
        
        -- Runtime Weight Modification Port (W SET / W LOAD from cmd_parser)
        w_we           : in  std_logic;
        w_neur_idx     : in  integer range 0 to N_NEUR-1;
        w_ch_idx       : in  integer range 0 to N_CH-1;
        w_data         : in  signed(7 downto 0);
        
        -- Runtime Configurable Threshold & Leak
        thetas         : in  theta_array_t;
        m_shifts       : in  m_array_t;
        
        -- Neuron Outputs
        fire_out       : out std_logic_vector(N_NEUR-1 downto 0);
        alert_snn      : out std_logic;
        class_id       : out std_logic_vector(1 downto 0);
        
        -- Membrane Potential Telemetry (for LOG 2 real-time streaming)
        v_membranes    : out membrane_array_t
    );
end entity snn_lif;

architecture rtl of snn_lif is

    -- Weight Matrix Storage: 4 x 12 x 8-bit signed (inferred registers)
    signal weights     : weight_matrix_t := DEFAULT_WEIGHTS;

    -- Membrane Potentials V[n]
    signal v_mem       : membrane_array_t := (others => (others => '0'));

    -- Fire and Class Signals
    signal fire_reg    : std_logic_vector(N_NEUR-1 downto 0) := (others => '0');
    signal class_reg   : std_logic_vector(1 downto 0) := "00";

    -- Types for balanced adder tree
    type prod_array_t is array(0 to N_CH-1) of signed(12 downto 0);
    type sum_l1_row_t is array(0 to 5) of signed(13 downto 0);
    type sum_l2_row_t is array(0 to 2) of signed(14 downto 0);

    -- Pure function for balanced adder tree (Depth = 3 levels, ~3 carry4 stages)
    function calc_total_delta (
        w_row   : weight_row_t;
        spk_act : std_logic_vector(N_CH-1 downto 0);
        spk_q   : q_array_t
    ) return signed16_t is
        variable p   : prod_array_t := (others => (others => '0'));
        variable l1  : sum_l1_row_t := (others => (others => '0'));
        variable l2  : sum_l2_row_t := (others => (others => '0'));
        variable tot : signed(15 downto 0);
    begin
        -- Level 0: 12 synaptic products
        for ch in 0 to N_CH-1 loop
            if spk_act(ch) = '1' and spk_q(ch) > 0 then
                p(ch) := w_row(ch) * signed('0' & std_logic_vector(spk_q(ch)));
            else
                p(ch) := (others => '0');
            end if;
        end loop;

        -- Level 1: 6 pairwise sums (14-bit)
        l1(0) := resize(p(0), 14)  + resize(p(1), 14);
        l1(1) := resize(p(2), 14)  + resize(p(3), 14);
        l1(2) := resize(p(4), 14)  + resize(p(5), 14);
        l1(3) := resize(p(6), 14)  + resize(p(7), 14);
        l1(4) := resize(p(8), 14)  + resize(p(9), 14);
        l1(5) := resize(p(10), 14) + resize(p(11), 14);

        -- Level 2: 3 sums (15-bit)
        l2(0) := resize(l1(0), 15) + resize(l1(1), 15);
        l2(1) := resize(l1(2), 15) + resize(l1(3), 15);
        l2(2) := resize(l1(4), 15) + resize(l1(5), 15);

        -- Level 3: Total balanced delta (16-bit)
        tot := resize(l2(0), 16) + resize(l2(1), 16) + resize(l2(2), 16);
        return tot;
    end function calc_total_delta;

    -- Pipeline registers between Adder Tree and Membrane Update
    type delta_pipe_array_t is array(0 to N_NEUR-1) of signed(15 downto 0);
    signal delta_pipe     : delta_pipe_array_t := (others => (others => '0'));
    signal leak_pipe      : std_logic := '0';

begin

    fire_out    <= fire_reg;
    class_id    <= class_reg;
    v_membranes <= v_mem;
    alert_snn   <= fire_reg(0) or fire_reg(1) or fire_reg(2);

    ----------------------------------------------------------------------------
    -- Stage 1: Parallel Adder Tree Evaluation (Registered)
    ----------------------------------------------------------------------------
    p_pipe1 : process(clk100)
    begin
        if rising_edge(clk100) then
            if rstn = '0' then
                delta_pipe <= (others => (others => '0'));
                leak_pipe  <= '0';
            else
                leak_pipe <= leak_tick;
                for n in 0 to N_NEUR-1 loop
                    delta_pipe(n) <= calc_total_delta(weights(n), spikes_active, spikes_q);
                end loop;
            end if;
        end if;
    end process p_pipe1;

    ----------------------------------------------------------------------------
    -- Stage 2: Sequential Membrane State Update & Threshold Firing Process
    ----------------------------------------------------------------------------
    p_neuron : process(clk100)
        variable v_accum     : signed(15 downto 0);
        variable leak_val    : signed(15 downto 0);
        variable n_fired     : std_logic_vector(N_NEUR-1 downto 0);
    begin
        if rising_edge(clk100) then
            if rstn = '0' then
                v_mem     <= (others => (others => '0'));
                fire_reg  <= (others => '0');
                class_reg <= "00";
                weights   <= DEFAULT_WEIGHTS;
            else
                -- Runtime weight write port
                if w_we = '1' then
                    weights(w_neur_idx)(w_ch_idx) <= w_data;
                end if;

                n_fired := (others => '0');

                for n in 0 to N_NEUR-1 loop
                    if leak_pipe = '1' then
                        -- Pure leak step
                        leak_val := shift_right(v_mem(n), m_shifts(n));
                        v_mem(n) <= sat_add16(v_mem(n), -leak_val);
                    else
                        -- Deposit & Threshold Evaluation
                        v_accum := sat_add16(v_mem(n), delta_pipe(n));
                        if v_accum >= thetas(n) then
                            n_fired(n) := '1';
                            -- Subtractive reset: V -= theta
                            v_mem(n)   <= sat_add16(v_accum, -thetas(n));
                        else
                            v_mem(n)   <= v_accum;
                        end if;
                    end if;
                end loop;

                fire_reg <= n_fired;

                -- Step 4: Class Attribution Rule (D16): lowest index wins
                if n_fired(0) = '1' then
                    class_reg <= "00"; -- N0: Transient
                elsif n_fired(1) = '1' then
                    class_reg <= "01"; -- N1: Repeat-Probe
                elsif n_fired(2) = '1' then
                    class_reg <= "10"; -- N2: Combined
                elsif n_fired(3) = '1' then
                    class_reg <= "11"; -- N3: Spare
                end if;

            end if;
        end if;
    end process p_neuron;

end architecture rtl;
