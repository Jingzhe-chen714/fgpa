set script_dir [file dirname [file normalize [info script]]]
set rtl_root [file normalize [file join $script_dir .. rtl]]

read_verilog -sv [file join $rtl_root common renderer_pkg.sv]
set rtl_files {}
foreach rtl_subdir {bus cmd fifo ip mem ops system video} {
    foreach rtl_file [glob -nocomplain [file join $rtl_root $rtl_subdir *.sv]] {
        if {![string match "tb_*" [file tail $rtl_file]]} {
            lappend rtl_files $rtl_file
        }
    }
}
read_verilog -sv $rtl_files

# Select all board/IP branches so the simulation-only framebuffer array is not
# synthesized. Empty named blackboxes remain outside the reported RTL totals.
synth_design -top c2_renderer_system -part xc7a35tcsg324-1 \
    -generic {USE_AXI4LITE_CSR=1 USE_EXT_MEM_IP=1 USE_VIDEO_PHY_IP=1 USE_CLOCK_RESET_IP=1}
report_utilization -hierarchical -file [file join $script_dir c2_renderer_system_ip_stub_util.rpt]
report_timing_summary -file [file join $script_dir c2_renderer_system_ip_stub_timing_unconstrained.rpt]
puts "SYNTH_SYSTEM_IP_STUB_PROXY_PASS"
