# Run CURRENT sources by default; -tclargs baseline allows the immutable audit
# snapshot to be measured with the same device, clock, I/O and place/route flow.
# Baseline failures are recorded; CURRENT timing failures return an error.
set case4_dir [file normalize [file join [file dirname [info script]] ..]]
set variant current
if {[llength $argv] > 0} {set variant [lindex $argv 0]}
if {$variant ni {current baseline}} {error "Expected current or baseline"}
set rtl_dir [file join $case4_dir rtl]
if {$variant eq "baseline"} {set rtl_dir [file join $case4_dir audit_20260913 reference case4 rtl]}
set report_dir [file join $case4_dir build timing_zynq $variant]
file mkdir $report_dir
set part xczu3eg-sbva484-1-e
if {[llength [get_parts -quiet $part]] != 1} {error "Reference part unavailable: $part"}
set_param general.maxThreads 4
set failures 0
set summary [open [file join $report_dir summary.txt] w]
puts $summary "variant=$variant part=$part period_ns=10 input_delay_ns=2 output_delay_ns=2"
foreach kind {basic median} {
    create_project -in_memory -part $part
    set_property XPM_LIBRARIES {XPM_MEMORY} [current_project]
    read_verilog -sv [glob [file join $rtl_dir *.sv]]
    read_xdc [file join $case4_dir constraints reference_zynq.xdc]
    if {$kind eq "basic"} {set top case4_gray_sobel_core_xilinx_bram} else {set top case4_gray_median_sobel_core_xilinx_bram}
    synth_design -top $top -part $part -mode out_of_context
    report_utilization -file [file join $report_dir ${kind}_synth_utilization.rpt]
    opt_design
    place_design
    route_design
    report_utilization -file [file join $report_dir ${kind}_routed_utilization.rpt]
    report_timing_summary -report_unconstrained -file [file join $report_dir ${kind}_routed_timing.rpt]
    report_timing -max_paths 10 -file [file join $report_dir ${kind}_critical_paths.rpt]
    check_timing -verbose -file [file join $report_dir ${kind}_checks.rpt]
    set setup [get_timing_paths -delay_type max -max_paths 1]
    set hold [get_timing_paths -delay_type min -max_paths 1]
    if {[llength $setup] != 1 || [llength $hold] != 1} {error "Missing timing paths: $kind"}
    set wns [get_property SLACK $setup]
    set whs [get_property SLACK $hold]
    # Verify the clock and I/O constraints actually reached the netlist.
    if {[llength [get_clocks pixel_clk]] != 1} {error "Missing pixel clock"}
    set checks [open [file join $report_dir ${kind}_checks.rpt] r]
    set check_text [read $checks]
    close $checks
    foreach category {no_clock unconstrained_internal_endpoints no_input_delay no_output_delay multiple_clock loops partial_input_delay partial_output_delay latch_loops} {
        if {![regexp "checking $category \\(0\\)" $check_text]} {error "Timing coverage check not clean: $category ($kind)"}
    }
    set line "CASE4_TIMING variant=$variant kind=$kind WNS=$wns WHS=$whs"
    puts $line
    puts $summary $line
    flush $summary
    set timing_file [open [file join $report_dir ${kind}_routed_timing.rpt] r]
    set timing_text [read $timing_file]
    close $timing_file
    # The summary also includes pulse-width constraints, beyond max/min paths.
    if {$wns < 0 || $whs < 0 || ![regexp {All user specified timing constraints are met\.} $timing_text]} {incr failures}
    close_project
}
puts $summary "timing_failures=$failures"
close $summary
if {$variant eq "current" && $failures != 0} {error "CASE4_TIMING_FAIL: $failures core(s) violate timing"}
puts "CASE4_IMPLEMENTATION_COMPLETE variant=$variant timing_failures=$failures"
exit
