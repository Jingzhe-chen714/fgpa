// Median of nine unsigned samples with a stream/sideband wrapper.
//
// The sorting loop describes a fully combinational 9-element sort.  Vivado
// unrolls the fixed bounds (36 compare/swap operations); this is intentionally
// transparent for the first implementation and can later be replaced by a
// balanced 19-comparator network.  REGISTER_OUTPUT=1 (the default) gives a
// deterministic one-cycle latency and II=1.

`timescale 1ns/1ps

module median3x3_u8 #(
    parameter integer PIXEL_BITS = 8,
    parameter integer X_BITS = 10,
    parameter integer Y_BITS = 9,
    parameter bit REGISTER_OUTPUT = 1'b1
) (
    input  logic                  clk,
    input  logic                  rst,

    input  logic                  in_valid,
    input  logic                  in_sof,
    input  logic                  in_eol,
    input  logic                  in_eof,
    input  logic [X_BITS-1:0]     in_x,
    input  logic [Y_BITS-1:0]     in_y,
    input  logic [PIXEL_BITS-1:0] in_p00,
    input  logic [PIXEL_BITS-1:0] in_p01,
    input  logic [PIXEL_BITS-1:0] in_p02,
    input  logic [PIXEL_BITS-1:0] in_p10,
    input  logic [PIXEL_BITS-1:0] in_p11,
    input  logic [PIXEL_BITS-1:0] in_p12,
    input  logic [PIXEL_BITS-1:0] in_p20,
    input  logic [PIXEL_BITS-1:0] in_p21,
    input  logic [PIXEL_BITS-1:0] in_p22,

    output logic                  out_valid,
    output logic                  out_sof,
    output logic                  out_eol,
    output logic                  out_eof,
    output logic [X_BITS-1:0]     out_x,
    output logic [Y_BITS-1:0]     out_y,
    output logic [PIXEL_BITS-1:0] out_pixel
);

    logic [PIXEL_BITS-1:0] sorted [0:8];
    logic [PIXEL_BITS-1:0] median_comb;
    integer i;
    integer j;
    logic [PIXEL_BITS-1:0] swap_tmp;

    // Sorting network written as a fixed-size bubble sort.  Since the bounds
    // are constants, synthesis produces a finite comparator network; no
    // run-time loops or state are present.
    always_comb begin
        sorted[0] = in_p00;
        sorted[1] = in_p01;
        sorted[2] = in_p02;
        sorted[3] = in_p10;
        sorted[4] = in_p11;
        sorted[5] = in_p12;
        sorted[6] = in_p20;
        sorted[7] = in_p21;
        sorted[8] = in_p22;
        swap_tmp = '0;

        for (i = 0; i < 9; i = i + 1) begin
            for (j = i + 1; j < 9; j = j + 1) begin
                if (sorted[j] < sorted[i]) begin
                    swap_tmp = sorted[i];
                    sorted[i] = sorted[j];
                    sorted[j] = swap_tmp;
                end
            end
        end
        median_comb = sorted[4];
    end

    generate
        if (REGISTER_OUTPUT) begin : g_registered
            always_ff @(posedge clk) begin
                if (rst) begin
                    out_valid <= 1'b0;
                    out_sof   <= 1'b0;
                    out_eol   <= 1'b0;
                    out_eof   <= 1'b0;
                    out_x     <= '0;
                    out_y     <= '0;
                    out_pixel <= '0;
                end else begin
                    out_valid <= in_valid;
                    out_sof   <= in_valid && in_sof;
                    out_eol   <= in_valid && in_eol;
                    out_eof   <= in_valid && in_eof;
                    out_x     <= in_x;
                    out_y     <= in_y;
                    out_pixel <= median_comb;
                end
            end
        end else begin : g_comb
            always_comb begin
                out_valid = in_valid;
                out_sof   = in_valid && in_sof;
                out_eol   = in_valid && in_eol;
                out_eof   = in_valid && in_eof;
                out_x     = in_x;
                out_y     = in_y;
                out_pixel = median_comb;
            end
        end
    endgenerate

endmodule
