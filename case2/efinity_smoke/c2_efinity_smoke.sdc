create_clock -period 20 -name clk [get_ports clk]
set_false_path -from [get_ports rst_n]
set_output_delay 5 -clock clk [get_ports led]
