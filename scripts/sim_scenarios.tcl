# File: sim_scenarios.tcl
# Non-interactive RTL Simulation Script for tb_scenarios (tb_scenarios.md 16 Test Cases)
# Toolchain: AMD Vivado 2025.2 xsim

set script_dir [file dirname [info script]]
set project_dir [file normalize "$script_dir/.."]
set sim_dir "$project_dir/vivado_sim"
file mkdir $sim_dir

cd $sim_dir

puts "========================================================================="
puts " Compiling and Simulating tb_scenarios in Vivado xsim"
puts " Reference: tb_scenarios.md (Scenarios TB-01 through TB-16)"
puts "========================================================================="

# Compile Design and TB VHDL-2008 Sources
exec xvhdl -2008 "$project_dir/rtl/pkg_fsd.vhd"
exec xvhdl -2008 "$project_dir/rtl/pkg_weights_gen.vhd"
exec xvhdl -2008 "$project_dir/rtl/sensor_mux.vhd"
exec xvhdl -2008 "$project_dir/rtl/snn_lif.vhd"
exec xvhdl -2008 "$project_dir/rtl/response.vhd"
exec xvhdl -2008 "$project_dir/rtl/victim_core.vhd"
exec xvhdl -2008 "$project_dir/sim/tb_scenarios.vhd"

# Elaborate
exec xelab -top tb_scenarios -snapshot tb_scenarios_snap

# Run simulation
set sim_output [exec xsim tb_scenarios_snap -R]
puts $sim_output

puts "========================================================================="
puts " tb_scenarios Simulation Finished Successfully!"
puts "========================================================================="
