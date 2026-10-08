# File: format_waveform.tcl
# End-to-end script to relaunch tb_scenarios and format clean waveform in Vivado GUI
# Displays: 4 Switches, 4 Buttons, Master Key, SNN Potential Count, Spike Counter, Warning LED & Lockdown LED

# 1. Close any running simulation so changes in tb_scenarios.vhd are recompiled cleanly
catch {close_sim -force}

# 2. Ensure tb_scenarios is set as simulation top
set_property top tb_scenarios [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]
update_compile_order -fileset sim_1

# 3. Configure debug level to 'all' so all signals are preserved
set_property -name {xsim.elaborate.debug_level} -value {all} -objects [get_filesets sim_1]

# 4. Clean previous compilation and launch fresh simulation
catch {reset_simulation -simset sim_1 -mode behavioral}
launch_simulation

# 5. Create or get wave configuration
if {[current_wave_config] == ""} {
    create_wave_config
}

# 6. Clear any cluttered default wave objects
catch {delete_wave_objects [get_waves *]}

# 7. Add Dividers and Physical Signals:
# --- 4 Physical Switches (Layer 1 Instant Hard Attacks) ---
catch {add_wave_divider "4 PHYSICAL SWITCHES (LAYER 1)"}
add_wave -name "SW[3] (Extreme Clock)"       /tb_scenarios/sw_extreme_clk
add_wave -name "SW[2] (Extreme Voltage)"     /tb_scenarios/sw_extreme_volt
add_wave -name "SW[1] (Extreme Temperature)" /tb_scenarios/sw_extreme_temp
add_wave -name "SW[0] (Extreme Memory)"      /tb_scenarios/sw_extreme_mem

# --- 4 Physical Buttons (Layer 2 SNN Gray-Zone Perturbations) ---
catch {add_wave_divider "4 PHYSICAL BUTTONS (SNN GRAY-ZONE)"}
add_wave -name "BTNC (Clock Jitter Spike)"   /tb_scenarios/btnc_clk_glitch
add_wave -name "BTNU (Voltage Drop Spike)"   /tb_scenarios/btnu_volt_drop
add_wave -name "BTNL (Thermal Anomaly Spike)"/tb_scenarios/btnl_temp_anomaly
add_wave -name "BTNR (Probe / Laser Spike)"  /tb_scenarios/btnr_probe_cap

# --- Core Cryptographic Asset & SNN Detection ---
catch {add_wave_divider "CORE ASSET & SNN COUNTERS"}
add_wave -radix hex      -name "Master Key (0123 -> 0000)"         /tb_scenarios/key_disp
add_wave -radix signed   -name "SNN Membrane Potential Count"      /tb_scenarios/snn_count
add_wave -radix unsigned -name "SNN Incident Spike Counter (0,1,2)"/tb_scenarios/snn_spike_count

# --- Response LEDs ---
catch {add_wave_divider "RESPONSE STATUS LEDS"}
add_wave -name "Warning LED (Yellow Latched)"       /tb_scenarios/led_warning
add_wave -name "Lockdown Zeroize LED (Red Latched)" /tb_scenarios/led_zeroized

# 8. Format SNN Membrane Count as analog curve
catch {
    set_property waveform_style analog [get_waves -filter {NAME =~ *snn_count*}]
    set_property cell_height 80 [get_waves -filter {NAME =~ *snn_count*}]
}

# 9. Run full simulation across all 16 scenarios
restart
run all

# 10. Add Waveform Markers to easily navigate across scenarios
catch {
    add_wave_marker -name "TB-01: Normal" 100ns
    add_wave_marker -name "TB-02: Ext Volt (SW2)" 250ns
    add_wave_marker -name "TB-03: Ext Temp (SW1)" 450ns
    add_wave_marker -name "TB-04: Ext Clk (SW3)" 650ns
    add_wave_marker -name "TB-05: Ext Mem (SW0)" 800ns
    add_wave_marker -name "TB-06: Gray 1x (BTNC)" 1050ns
    add_wave_marker -name "TB-07: Gray 2x -> Warning LED" 1200ns
    add_wave_marker -name "TB-08: Gray 3x -> Zeroize Key" 1450ns
    add_wave_marker -name "TB-09: Probe Pulses (BTNR)" 1800ns
    add_wave_marker -name "TB-10: Multi-Param (BTNC+BTNU)" 2000ns
    add_wave_marker -name "TB-13: 3-Param Pattern" 3200ns
    add_wave_marker -name "TB-14: 4-Param Pattern" 3500ns
    add_wave_marker -name "TB-15: Decay Behavior" 3800ns
    add_wave_marker -name "TB-16: Fast Accumulation < T_decay" 4400ns
}

puts "========================================================================="
puts " SUCCESS: Simulation recompiled & fresh waveform configured!"
puts " Markers have been added along the timeline for all test scenarios."
puts " Press 'F' on your keyboard to Zoom to Fit the waveform."
puts "========================================================================="
