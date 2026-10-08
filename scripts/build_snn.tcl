# File: build_snn.tcl
# Non-interactive Vivado Synthesis, Implementation, and Bitstream script for SNN Anti-Tamper Guard (FSD v2)
# Target Part: xc7a100tcsg324-1 (Digilent Nexys A7-100T)

set script_dir [file dirname [info script]]
set project_dir [file normalize "$script_dir/.."]
set output_dir "$project_dir/vivado_output_snn"
file mkdir $output_dir

puts "========================================================================="
puts " Building FPGA Anti-Tamper Guard (top.vhd) for Nexys A7-100T"
puts " Project Root: $project_dir"
puts " Output Dir:   $output_dir"
puts "========================================================================="

# Create in-memory project
create_project -in_memory -part xc7a100tcsg324-1

# Set VHDL-2008 language standard
set_property target_language VHDL [current_project]

# Read VHDL Packages & RTL Sources
puts "Reading VHDL-2008 sources..."
read_vhdl -vhdl2008 "$project_dir/rtl/pkg_fsd.vhd"
read_vhdl -vhdl2008 "$project_dir/rtl/pkg_weights_gen.vhd"
read_vhdl -vhdl2008 "$project_dir/rtl/clk_gen.vhd"
read_vhdl -vhdl2008 "$project_dir/rtl/mmcm_drp.vhd"
read_vhdl -vhdl2008 "$project_dir/rtl/uart_host.vhd"
read_vhdl -vhdl2008 "$project_dir/rtl/cmd_parser.vhd"
read_vhdl -vhdl2008 "$project_dir/rtl/mon_clk.vhd"
read_vhdl -vhdl2008 "$project_dir/rtl/mon_volt.vhd"
read_vhdl -vhdl2008 "$project_dir/rtl/stressor.vhd"
read_vhdl -vhdl2008 "$project_dir/rtl/victim_core.vhd"
read_vhdl -vhdl2008 "$project_dir/rtl/mon_victim.vhd"
read_vhdl -vhdl2008 "$project_dir/rtl/sensor_mux.vhd"
read_vhdl -vhdl2008 "$project_dir/rtl/snn_lif.vhd"
read_vhdl -vhdl2008 "$project_dir/rtl/response.vhd"
read_vhdl -vhdl2008 "$project_dir/rtl/telemetry.vhd"
read_vhdl -vhdl2008 "$project_dir/rtl/top.vhd"

# Read Constraints
puts "Reading constraints..."
read_xdc "$project_dir/constr/nexys_a7_100t.xdc"

# Synthesis
puts "Starting Synthesis..."
synth_design -top top -part xc7a100tcsg324-1 -flatten_hierarchy rebuilt
write_checkpoint -force "$output_dir/post_synth.dcp"
report_utilization -file "$output_dir/synth_utilization.rpt"
report_timing_summary -file "$output_dir/synth_timing.rpt"

# Logic Optimization
puts "Starting Logic Optimization..."
opt_design

# Placement
puts "Starting Placement..."
place_design
write_checkpoint -force "$output_dir/post_place.dcp"

# Physical Optimization
puts "Starting Physical Optimization..."
phys_opt_design

# Routing
puts "Starting Routing..."
route_design
write_checkpoint -force "$output_dir/post_route.dcp"
report_timing_summary -file "$output_dir/route_timing_summary.rpt"
report_utilization -file "$output_dir/route_utilization.rpt"
report_drc -file "$output_dir/route_drc.rpt"

# Bitstream Generation
puts "Generating Bitstream..."
write_bitstream -force "$output_dir/anti_tamper_snn.bit"

puts "========================================================================="
puts " SNN Anti-Tamper Guard Build Finished Successfully!"
puts " Bitstream located at: $output_dir/anti_tamper_snn.bit"
puts "========================================================================="
