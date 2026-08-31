// Fixed-point BT.601 luma converter, one pixel per clock.
//
// Y = round((77*R + 150*G + 29*B) / 256)
//   = (77*R + 150*G + 29*B + 128) >> 8
//
// The coefficients sum to 256, so for legal 8-bit RGB input the rounded
// result is always in 0..255.  The widened accumulator is exposed to make
// bit-exact scoreboards and later diagnostics straightforward.
// `rst` is synchronous, active high.  m_valid and all sideband are exactly
// one clock behind their corresponding input transaction.

`timescale 1ns/1ps

module gray_bt601_stream #(
    parameter integer X_W = 16,
    parameter integer Y_W = 16
) (
    input  wire                 clk,
    input  wire                 rst,
    input  wire                 in_valid,
    input  wire                 in_sof,
    input  wire                 in_eol,
    input  wire                 in_eof,
    input  wire [X_W-1:0]       in_x,
    input  wire [Y_W-1:0]       in_y,
    input  wire [7:0]           in_r,
    input  wire [7:0]           in_g,
    input  wire [7:0]           in_b,
    output reg                  m_valid,
    output reg                  m_sof,
    output reg                  m_eol,
    output reg                  m_eof,
    output reg [X_W-1:0]        m_x,
    output reg [Y_W-1:0]        m_y,
    output reg [7:0]            m_gray,
    output reg [16:0]           m_acc
);

    // Explicit 17-bit extensions are important: in Verilog the result width
    // of a shift follows its left operand, and an 8-bit shift would truncate.
    wire [16:0] r_ext = {9'd0, in_r};
    wire [16:0] g_ext = {9'd0, in_g};
    wire [16:0] b_ext = {9'd0, in_b};

    // Shift/add realization avoids requiring DSP blocks for the constants.
    wire [16:0] r_term = (r_ext << 6) + (r_ext << 3) +
                         (r_ext << 2) + r_ext;                 // 64+8+4+1=77
    wire [16:0] g_term = (g_ext << 7) + (g_ext << 4) +
                         (g_ext << 2) + (g_ext << 1);          // 128+16+4+2=150
    wire [16:0] b_term = (b_ext << 4) + (b_ext << 3) +
                         (b_ext << 2) + b_ext;                 // 16+8+4+1=29
    wire [16:0] acc_comb = r_term + g_term + b_term;
    wire [16:0] rounded_comb = acc_comb + 17'd128;

    always @(posedge clk) begin
        if (rst) begin
            m_valid <= 1'b0;
            m_sof   <= 1'b0;
            m_eol   <= 1'b0;
            m_eof   <= 1'b0;
            m_x     <= {X_W{1'b0}};
            m_y     <= {Y_W{1'b0}};
            m_gray  <= 8'd0;
            m_acc   <= 17'd0;
        end else begin
            m_valid <= in_valid;
            if (in_valid) begin
                m_sof  <= in_sof;
                m_eol  <= in_eol;
                m_eof  <= in_eof;
                m_x    <= in_x;
                m_y    <= in_y;
                m_acc  <= acc_comb;
                m_gray <= rounded_comb[15:8];
            end else begin
                m_sof  <= 1'b0;
                m_eol  <= 1'b0;
                m_eof  <= 1'b0;
                m_x    <= {X_W{1'b0}};
                m_y    <= {Y_W{1'b0}};
                m_gray <= 8'd0;
                m_acc  <= 17'd0;
            end
        end
    end

endmodule

