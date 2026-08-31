# Generic Vivado syntax/inference smoke check for the algorithm-only core.
# The contest target is Efinix; these reports are not Ti60F225 resource claims.
read_verilog -sv \
  case4/rtl/gray_bt601_stream.sv \
  case4/rtl/gray_rgb_stream.sv \
  case4/rtl/case4_rgb_frontend.sv \
  case4/rtl/window3x3_gray.sv \
  case4/rtl/case4_sobel_edge_ops.sv \
  case4/rtl/case4_gray_sobel_core.sv
synth_design -top case4_gray_sobel_core -part xc7a35tcpg236-1 -mode out_of_context
report_utilization -file case4/rtl/core_utilization_xilinx.rpt
report_timing_summary -file case4/rtl/core_timing_xilinx.rpt
exit
