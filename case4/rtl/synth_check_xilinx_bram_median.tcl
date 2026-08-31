# Xilinx-only OOC synthesis check for the median -> Sobel cascade.
# The report is a structural Vivado reference; it is not an Efinix resource
# claim.  See BRAM_PORTABILITY.md before replacing the memory wrappers.
set script_dir [file dirname [file normalize [info script]]]
set case4_dir  [file normalize [file join $script_dir ..]]
if {[info exists ::env(CASE4_VIVADO_ROOT)] && $::env(CASE4_VIVADO_ROOT) ne ""} {
    set vivado_root [file normalize $::env(CASE4_VIVADO_ROOT)]
} else {
    set vivado_root "D:/vivado/vivado/Vivado/2023.1"
}
set xpm_file [file join $vivado_root data ip xpm xpm_memory hdl xpm_memory.sv]
if {![file exists $xpm_file]} {
    error "Xilinx XPM memory source not found: $xpm_file"
}

read_verilog -sv [list \
    $xpm_file \
    [file join $case4_dir rtl xilinx_bram_sdp_row.sv] \
    [file join $case4_dir rtl window3x3_gray_xilinx_bram.sv] \
    [file join $case4_dir rtl rgb_unpack_stream.sv] \
    [file join $case4_dir rtl gray_rgb_stream.sv] \
    [file join $case4_dir rtl case4_rgb_frontend.sv] \
    [file join $case4_dir rtl median3x3_u8.sv] \
    [file join $case4_dir rtl case4_sobel_edge_ops.sv] \
    [file join $case4_dir rtl case4_gray_median_sobel_core.sv] \
    [file join $case4_dir rtl case4_gray_median_sobel_core_xilinx_bram.sv]]

synth_design -top case4_gray_median_sobel_core_xilinx_bram \
    -part xc7a35tcpg236-1 -mode out_of_context
report_utilization -file [file join $case4_dir rtl core_xilinx_bram_median_utilization_xilinx.rpt]
report_timing_summary -file [file join $case4_dir rtl core_xilinx_bram_median_timing_xilinx.rpt]
puts "CASE4 XILINX BRAM MEDIAN SYNTH PASS: reports written under case4/rtl"
exit
