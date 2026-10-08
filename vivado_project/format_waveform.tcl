# File: format_waveform.tcl
# End-to-end script to launch tb_scenarios and format clean waveform in Vivado GUI
# Displays: tb_id, tb_pass, Inputs (clk, rst, 4 switch, 4 button), Outputs (snn_count, key, warning_led)

# 1. Close any running simulation cleanly
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

# 7. Add Verification Status & Markers
catch {add_wave_divider "VERIFICATION STATUS & SCENARIO ID"}
add_wave -radix unsigned -name "Scenario ID (TB 1-16)" /tb_scenarios/tb_id
add_wave                 -name "Scenario PASS Flag"    /tb_scenarios/tb_pass

# 8. Add Inputs
catch {add_wave_divider "INPUTS (CLK, RST, 4 SWITCH, 4 BUTTON)"}
add_wave                 -name "clk (100 MHz)"         /tb_scenarios/clk
add_wave                 -name "rst (Active-High)"     /tb_scenarios/rst
add_wave -radix bin      -name "4 Switch (SW3..SW0)"   /tb_scenarios/sw
add_wave -radix bin      -name "4 Button (BTN3..BTN0)" /tb_scenarios/btn

# 9. Add Outputs
catch {add_wave_divider "OUTPUTS (SNN COUNT, KEY, WARNING LED)"}
add_wave -radix signed   -name "Counter SNN (Membrane)"/tb_scenarios/snn_count
add_wave -radix hex      -name "Master Key (0123->0000)"/tb_scenarios/key
add_wave                 -name "Warning LED (Yellow)"  /tb_scenarios/warning_led
add_wave                 -name "Lockdown Zeroize LED"  /tb_scenarios/zeroize_led

# 10. Format SNN Membrane Count as analog curve
catch {
    set_property waveform_style analog [get_waves -filter {NAME =~ *snn_count*}]
    set_property cell_height 80 [get_waves -filter {NAME =~ *snn_count*}]
}

# 11. Run full simulation across all 16 scenarios
restart
run all

puts "========================================================================="
puts " SUCCESS: tb_scenarios Waveform configured with 16 Scenarios!"
puts " Inputs: clk, rst, 4 switch, 4 button"
puts " Outputs: counter snn, key, warning LED"
puts " Press 'F' on your keyboard to Zoom to Fit the waveform."
puts "========================================================================="
