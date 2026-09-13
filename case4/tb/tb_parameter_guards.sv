`timescale 1ns/1ps
// Every instance below MUST fail at elaboration/startup with its own marker.
module tb_parameter_guards #(parameter integer BAD=0);
    generate
        if(BAD==0) case4_sobel3x3 #(.MAG_W(10)) dut();
        if(BAD==1) case4_sobel3x3 #(.PART_W(9)) dut();
        if(BAD==2) case4_sobel3x3 #(.GRAD_W(10)) dut();
        if(BAD==3) gray_rgb_stream #(.PIXEL_FORMAT(2)) dut();
        if(BAD==4) rgb_unpack_stream #(.PIXEL_FORMAT(2)) dut();
        if(BAD==5) case4_gray_median_sobel_core #(.IMG_WIDTH(4)) dut();
        if(BAD==6) case4_gray_sobel_core #(.IMG_WIDTH(8),.X_BITS(2)) dut();
        if(BAD==7) window3x3_gray #(.IMG_WIDTH(2)) dut();
        if(BAD==8) case4_gray_sobel_core #(.WINDOW_BACKEND(2)) dut();
        if(BAD==9) median3x3_u8 #(.PIPELINE_STAGES(2)) dut();
        if(BAD==10) median3x3_u8 #(.PIPELINE_STAGES(0),.REGISTER_OUTPUT(1)) dut();
        if(BAD==11) case4_edge_overlay #(.RGB_W(16)) dut();
        if(BAD==12) window3x3_gray_xilinx_bram #(.IMG_WIDTH(8),.X_BITS(2)) dut();
        if(BAD==13) case4_gray_median_sobel_core #(.MAG_W(10)) dut();
    endgenerate
    initial begin #100; $fatal(1,"PARAM_GUARD_NOT_REJECTED");end
endmodule
