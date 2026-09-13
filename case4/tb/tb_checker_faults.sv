`timescale 1ns/1ps
// Expected failure: the runner requires the precise checker rejection marker.
module tb_checker_faults #(parameter integer FAULT=0);
    tb_gray_median_sobel_core original_tb();
    initial begin
        case (FAULT)
            0: force original_tb.dut.out_gx = 'x;
            1: force original_tb.dut.out_gy = 'x;
            2: force original_tb.dut.out_magnitude = 'x;
            3: force original_tb.dut.out_edge = 'x;
            4: force original_tb.dut.out_valid = 'x;
            5: force original_tb.dut.out_eol = 'x;
            default: $fatal(1, "bad FAULT parameter");
        endcase
    end
    initial begin #10000; $fatal(1,"CHECKER_FAULT_NOT_REJECTED"); end
endmodule
