set script_dir [file dirname [file normalize [info script]]]
set rtl_file [file normalize [file join $script_dir .. rtl mem render_cmd_mem_engine.sv]]

read_verilog -sv $rtl_file
synth_design -top render_cmd_mem_engine -part xc7a35tcsg324-1 \
    -generic {WRITE_BURST_ENABLE=1 READ_BURST_ENABLE=1 MAX_READ_BEATS=16 MAX_WRITE_BEATS=16 LINE_BUFFER_PIXELS=4096 READ_BOUNDARY_BYTES=4096 WRITE_BOUNDARY_BYTES=4096}
report_utilization -hierarchical -file [file join $script_dir render_cmd_mem_engine_util.rpt]
report_timing_summary -file [file join $script_dir render_cmd_mem_engine_timing_unconstrained.rpt]
puts "SYNTH_ENGINE_PROXY_PASS"
