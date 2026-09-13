`timescale 1ns/1ps

// Convert the resource-efficient one-bit edge decision to an 8-bit display
// pixel (0 or 255), while preserving the stream sideband.
module case4_edge_expand8 #(
    parameter integer X_W = 12,
    parameter integer Y_W = 12
) (
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic                 in_valid,
    input  logic                 in_win_valid,
    input  logic                 in_sof,
    input  logic                 in_eol,
    input  logic                 in_eof,
    input  logic [X_W-1:0]       in_x,
    input  logic [Y_W-1:0]       in_y,
    input  logic                 in_edge,
    output logic                 out_valid,
    output logic                 out_win_valid,
    output logic                 out_sof,
    output logic                 out_eol,
    output logic                 out_eof,
    output logic [X_W-1:0]       out_x,
    output logic [Y_W-1:0]       out_y,
    output logic                 out_edge,
    output logic [7:0]           out_edge8
);
    // Active-low synchronous reset, matching the other arithmetic stages.
    initial begin
        if (X_W < 1 || Y_W < 1)
            $fatal(1, "CASE4_PARAM_EDGE8_WIDTH: coordinate widths must be positive");
    end
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            out_valid     <= 1'b0;
            out_win_valid <= 1'b0;
            out_sof       <= 1'b0;
            out_eol       <= 1'b0;
            out_eof       <= 1'b0;
            out_x         <= '0;
            out_y         <= '0;
            out_edge      <= 1'b0;
            out_edge8     <= 8'h00;
        end else begin
            out_valid     <= in_valid;
            out_win_valid <= in_valid && in_win_valid;
            out_sof       <= in_valid && in_sof;
            out_eol       <= in_valid && in_eol;
            out_eof       <= in_valid && in_eof;
            out_x         <= in_x;
            out_y         <= in_y;
            out_edge      <= in_valid && in_win_valid && in_edge;
            out_edge8     <= (in_valid && in_win_valid && in_edge) ? 8'hFF : 8'h00;
        end
    end
endmodule
