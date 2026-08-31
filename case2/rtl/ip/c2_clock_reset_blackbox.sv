`timescale 1ns/1ps

// Reserved replacement point for Efinix PLL/reset IP.  In simulation the
// system wrapper bypasses this module and uses the supplied clock directly.
(* black_box = "true" *)
module c2_clock_reset_blackbox (
    input  logic clk_in,
    input  logic rst_n_in,
    output logic clk_sys,
    output logic clk_pix,
    output logic rst_sys_n,
    output logic rst_pix_n,
    output logic locked
);
endmodule
