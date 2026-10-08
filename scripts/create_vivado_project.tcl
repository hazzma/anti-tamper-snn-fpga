# File: create_vivado_project.tcl
# Generates Vivado GUI Project (.xpr) for FPGA Anti-Tamper Guard with SNN (FSD v2)
# Target: Digilent Nexys A7-100T (xc7a100tcsg324-1)

set script_dir [file dirname [info script]]
set project_dir [file normalize "$script_dir/.."]
set proj_output "$project_dir/vivado_project"

puts "========================================================================="
puts " Creating Vivado GUI Project: $proj_output/anti_tamper_snn.xpr"
puts " Target: Digilent Nexys A7-100T (xc7a100tcsg324-1)"
puts "========================================================================="

# Create Project
create_project anti_tamper_snn $proj_output -part xc7a100tcsg324-1 -force

# Set target language
set_property target_language VHDL [current_project]
set_property default_lib xil_defaultlib [current_project]

# Add VHDL-2008 Design Sources
puts "Adding Design Sources..."
add_files -fileset sources_1 [glob "$project_dir/rtl/*.vhd"]
set_property file_type {VHDL 2008} [get_files -of_objects [get_filesets sources_1]]

# Set Top Module
set_property top top [current_fileset]
update_compile_order -fileset sources_1

# Add Simulation Sources
puts "Adding Simulation Sources..."
add_files -fileset sim_1 [glob "$project_dir/sim/*.vhd"]
set_property file_type {VHDL 2008} [get_files -of_objects [get_filesets sim_1]]
set_property top tb_top [get_filesets sim_1]
update_compile_order -fileset sim_1

# Add Physical & Timing Constraints
puts "Adding Constraints..."
add_files -fileset constrs_1 "$project_dir/constr/nexys_a7_100t.xdc"

puts "========================================================================="
puts " Vivado Project created successfully!"
puts " Output location: $proj_output/anti_tamper_snn.xpr"
puts "========================================================================="
