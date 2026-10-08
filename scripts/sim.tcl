# File: sim.tcl
# Non-interactive RTL Simulation Script for SNN Anti-Tamper Guard using Vivado xsim
# Target TB: tb_snn_lif (L1 Unit Testbench)

set script_dir [file dirname [info script]]
set project_dir [file normalize "$script_dir/.."]
set sim_dir "$project_dir/vivado_sim"
file mkdir $sim_dir

cd $sim_dir

puts "========================================================================="
puts " Compiling and Simulating tb_snn_lif in Vivado xsim"
puts "========================================================================="

# Compile Packages & Design Sources
exec xvhdl -2008 "$project_dir/rtl/pkg_fsd.vhd"
exec xvhdl -2008 "$project_dir/rtl/pkg_weights_gen.vhd"
exec xvhdl -2008 "$project_dir/rtl/snn_lif.vhd"
exec xvhdl -2008 "$project_dir/sim/tb_snn_lif.vhd"

# Elaborate
exec xelab -top tb_snn_lif -snapshot tb_snn_lif_snap

# Run simulation
set sim_output [exec xsim tb_snn_lif_snap -R]
puts $sim_output

puts "========================================================================="
puts " Simulation Completed Successfully!"
puts "========================================================================="
