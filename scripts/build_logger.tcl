# build_logger.tcl
# Batch script to create project, run synthesis, implementation and bitstream for Logger

set proj_name "snn_logger"
set proj_dir  "./vivado_logger"
set part      "xc7a100tcsg324-1"

create_project -force $proj_name $proj_dir -part $part

# Add VHDL-2008 sources
add_files -scan_for_includes ./rtl/snn_params_pkg.vhd
add_files -scan_for_includes ./rtl/ro_sensor.vhd
add_files -scan_for_includes ./rtl/bram_monitor.vhd
add_files -scan_for_includes ./rtl/xadc_if.vhd
add_files -scan_for_includes ./rtl/uart_tx.vhd
add_files -scan_for_includes ./rtl/uart_rx.vhd
add_files -scan_for_includes ./rtl/cmd_parser.vhd
add_files -scan_for_includes ./rtl/tamper_emulator.vhd
add_files -scan_for_includes ./rtl/logger.vhd
add_files -scan_for_includes ./rtl/logger_top.vhd

set_property FILE_TYPE {VHDL 2008} [get_files *.vhd]
set_property top logger_top [current_fileset]

# Add Constraints
add_files -fileset constrs_1 ./constr/nexys_a7_100t.xdc

# Run Synthesis
launch_runs synth_1 -jobs 4
wait_on_run synth_1

# Run Implementation and Bitstream
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

puts "================================================"
puts "Build Logger Bitstream Completed!"
puts "================================================"
