# scripts/diagnose_timing.tcl
set script_dir [file dirname [info script]]
set project_dir [file normalize "$script_dir/.."]

open_project "$project_dir/vivado_project/anti_tamper_snn.xpr"

# Reset implementation run and re-run with our new RTL
reset_run impl_1
launch_runs impl_1 -to_step route_design
wait_on_run impl_1

open_run impl_1
report_timing_summary -max_paths 10 -file "$project_dir/reports/timing_impl1.rpt"

set wns [get_property STATS.WNS [get_runs impl_1]]
puts "=================================================="
puts "IMPL_1 COMPLETED WITH WNS: $wns ns"
puts "=================================================="
