# Optional syntax/inference smoke check with a locally installed Vivado.
# The contest target is Efinix; this is only a generic LUT/register sanity
# check and is not a resource prediction for Ti60F225.
read_verilog -sv case4/rtl/case4_sobel_edge_ops.sv
synth_design -top case4_sobel_edge_pipeline -part xc7a35tcpg236-1 -mode out_of_context
report_utilization -file case4/rtl/sobel_edge_utilization_xilinx.rpt
report_timing_summary -file case4/rtl/sobel_edge_timing_xilinx.rpt
exit

