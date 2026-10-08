# scripts/test_full_timing.tcl
set script_dir [file dirname [info script]]
set project_dir [file normalize "$script_dir/.."]

create_project -in_memory -part xc7a100tcsg324-1
set_property target_language VHDL [current_project]

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

read_xdc "$project_dir/constr/nexys_a7_100t.xdc"

puts "Starting Synthesis..."
synth_design -top top -part xc7a100tcsg324-1

puts "Running opt_design..."
opt_design

puts "Running place_design..."
place_design

puts "Running route_design..."
route_design

puts "Reporting Final Timing Summary..."
report_timing_summary -max_paths 10 -file "$project_dir/reports/full_timing_routed.rpt"

set wns [get_property STATS.WNS [current_design]]
set whs [get_property STATS.WHS [current_design]]
puts "=================================================="
puts "FINAL FULL TIMING: WNS = $wns ns, WHS = $whs ns"
puts "=================================================="
