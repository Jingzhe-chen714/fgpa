# Algorithm-only OOC benchmark: not a camera/display or Efinix board constraint.
create_clock -name pixel_clk -period 10.000 [get_ports clk]
set_property HD.CLK_SRC BUFGCE_X0Y0 [get_ports clk]
set_input_delay 2.000 -clock pixel_clk [get_ports -filter {DIRECTION == IN && NAME != clk}]
set_output_delay 2.000 -clock pixel_clk [get_ports -filter {DIRECTION == OUT}]
