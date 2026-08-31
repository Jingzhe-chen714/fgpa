set script_dir [file dirname [file normalize [info script]]]
set rtl_file [file normalize [file join $script_dir .. rtl fifo c2_line_fifo.sv]]

read_verilog -sv $rtl_file
synth_design -top c2_line_fifo -part xc7a35tcsg324-1 \
    -generic {DATA_W=16 DEPTH=1024}
report_utilization -hierarchical -file [file join $script_dir c2_line_fifo_util.rpt]
report_timing_summary -file [file join $script_dir c2_line_fifo_timing_unconstrained.rpt]
puts "SYNTH_LINE_FIFO_PROXY_PASS"
