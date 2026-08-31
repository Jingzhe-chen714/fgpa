`timescale 1ns/1ps

// Run the same byte-accurate protocol regression at the system's default width.
module tb_c2_mem_to_axi4_adapter_128;
    tb_c2_mem_to_axi4_adapter #(.AXI_DATA_W(128)) u_test();
endmodule
