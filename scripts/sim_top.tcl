# File: sim_top.tcl
# Non-interactive RTL Simulation Script for Top-Level Integration (FSD v2 L2)
# Target TB: tb_top

set script_dir [file dirname [info script]]
set project_dir [file normalize "$script_dir/.."]
set sim_dir "$project_dir/vivado_sim"
file mkdir $sim_dir

cd $sim_dir

puts "========================================================================="
puts " Compiling and Simulating tb_top in Vivado xsim"
puts "========================================================================="

# Compile all VHDL-2008 Sources
exec xvhdl -2008 "$project_dir/rtl/pkg_fsd.vhd"
exec xvhdl -2008 "$project_dir/rtl/pkg_weights_gen.vhd"
exec xvhdl -2008 "$project_dir/rtl/clk_gen.vhd"
exec xvhdl -2008 "$project_dir/rtl/mmcm_drp.vhd"
exec xvhdl -2008 "$project_dir/rtl/uart_host.vhd"
exec xvhdl -2008 "$project_dir/rtl/cmd_parser.vhd"
exec xvhdl -2008 "$project_dir/rtl/mon_clk.vhd"
exec xvhdl -2008 "$project_dir/rtl/mon_volt.vhd"
exec xvhdl -2008 "$project_dir/rtl/stressor.vhd"
exec xvhdl -2008 "$project_dir/rtl/victim_core.vhd"
exec xvhdl -2008 "$project_dir/rtl/mon_victim.vhd"
exec xvhdl -2008 "$project_dir/rtl/sensor_mux.vhd"
exec xvhdl -2008 "$project_dir/rtl/snn_lif.vhd"
exec xvhdl -2008 "$project_dir/rtl/response.vhd"
exec xvhdl -2008 "$project_dir/rtl/telemetry.vhd"
exec xvhdl -2008 "$project_dir/rtl/top.vhd"
exec xvhdl -2008 "$project_dir/sim/tb_top.vhd"

# Elaborate
exec xelab -top tb_top -snapshot tb_top_snap

# Run simulation
set sim_output [exec xsim tb_top_snap -R]
puts $sim_output

puts "========================================================================="
puts " tb_top Simulation Finished Successfully!"
puts "========================================================================="
