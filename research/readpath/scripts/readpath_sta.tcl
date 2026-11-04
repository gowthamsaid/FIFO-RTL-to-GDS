# Targeted post-route STA. Run via ORFS 'make ... RUN_SCRIPT=... run'.
# Keep the actual post-route SPEF where available (no ideal wire-delay claims).
source $::env(SCRIPTS_DIR)/load.tcl
load_design 6_final.odb 6_final.sdc
set_propagated_clock [all_clocks]

set spef "$::env(RESULTS_DIR)/6_final.spef"
if {[file exists $spef]} {
  puts "READPATH_STA_PARASITICS: extracted SPEF"
  read_spef $spef
} elseif {[grt::have_routes]} {
  puts "READPATH_STA_PARASITICS: estimated from global route (not extracted SPEF)"
  estimate_parasitics -global_routing
} else {
  error "Cannot obtain routed parasitics; refusing a pre-route timing claim"
}

set from_regs [get_cells -hierarchical *read_ptr*]
set to_regs [get_cells -hierarchical *data_out*]
if {[llength $from_regs] == 0 || [llength $to_regs] == 0} {
  error "Cannot locate read_ptr and data_out registers after synthesis. Inspect naming; do not report missing path as zero delay."
}
set target "$::env(REPORTS_DIR)/readpath-targeted.rpt"
set global "$::env(REPORTS_DIR)/readpath-global.rpt"
puts "READPATH_STA: reporting read_ptr to data_out register-to-register setup paths"
report_checks -path_delay max -from $from_regs -to $to_regs \
  -group_path_count 5 -fields {slew cap input net fanout} \
  -format full_clock_expanded > $target
report_checks -path_delay max -fields {slew cap input net fanout} \
  -format full_clock_expanded > $global
puts "READPATH_STA: target $target; global $global"
