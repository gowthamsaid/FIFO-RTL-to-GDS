# Standalone targeted STA on the final routed database, using extracted SPEF.
# Called inside the pinned ORFS image after source ../env.sh.
set root $::env(READPATH_DESIGN_DIR)
set reports $::env(READPATH_REPORT_DIR)
set platform "/OpenROAD-flow-scripts/flow/platforms/nangate45"
read_liberty "$platform/lib/NangateOpenCellLibrary_typical.lib"
read_db "$root/6_final.odb"
read_sdc "$root/6_final.sdc"
source "$platform/setRC.tcl"
if {![file exists "$root/6_final.spef"]} {
  error "Final SPEF missing. Refusing estimated/pre-route timing."
}
read_spef "$root/6_final.spef"
set_propagated_clock [all_clocks]
set from_regs [get_cells -quiet {*read_ptr*}]
set to_regs [get_cells -quiet {*data_out*}]
puts "READPATH: [llength $from_regs] launch registers, [llength $to_regs] endpoints"
if {[llength $from_regs] == 0 || [llength $to_regs] == 0} {
  error "Read-pointer and/or data-output registers missing."
}
set target "$reports/readpath-targeted.rpt"
set fd [open $target w]
close $fd
report_checks -from $from_regs -to $to_regs -path_delay max \
  -group_path_count 16 -endpoint_path_count 1 \
  -format full_clock_expanded -fields {slew capacitance fanout} \
  -digits 4 > $target
if {[file size $target] == 0} {
  error "Empty targeted read-path report."
}
puts "READPATH: wrote $target"
