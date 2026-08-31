// Packed-pixel RGB565/RGB888 to BT.601 gray stream.
//
// This convenience block combines RGB unpacking and fixed-point gray
// conversion in a single register stage.  It has the same input contract as
// rgb_unpack_stream, but emits only gray/accumulator data.  Use the two
// standalone modules when RGB channels are also needed downstream.
//
// PIXEL_FORMAT = 0: pixel_in[15:11]/[10:5]/[4:0] = RGB565.
// PIXEL_FORMAT = 1: pixel_in[23:16]/[15:8]/[7:0] = RGB888.
// `rst` is synchronous, active high; output sideband latency is one clock.

`timescale 1ns/1ps

module gray_rgb_stream #(
    parameter integer PIXEL_FORMAT = 0,
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
    input  wire [23:0]          pixel_in,
    output reg                  m_valid,
    output reg                  m_sof,
    output reg                  m_eol,
    output reg                  m_eof,
    output reg [X_W-1:0]        m_x,
    output reg [Y_W-1:0]        m_y,
    output reg [7:0]            m_gray,
    output reg [16:0]           m_acc
);

    reg [7:0] r_unpacked;
    reg [7:0] g_unpacked;
    reg [7:0] b_unpacked;

    always @* begin
        if (PIXEL_FORMAT == 0) begin
            r_unpacked = {pixel_in[15:11], pixel_in[15:13]};
            g_unpacked = {pixel_in[10:5],  pixel_in[10:9]};
            b_unpacked = {pixel_in[4:0],   pixel_in[4:2]};
        end else begin
            r_unpacked = pixel_in[23:16];
            g_unpacked = pixel_in[15:8];
            b_unpacked = pixel_in[7:0];
        end
    end

    wire [16:0] r_ext = {9'd0, r_unpacked};
    wire [16:0] g_ext = {9'd0, g_unpacked};
    wire [16:0] b_ext = {9'd0, b_unpacked};
    wire [16:0] r_term = (r_ext << 6) + (r_ext << 3) +
                         (r_ext << 2) + r_ext;
    wire [16:0] g_term = (g_ext << 7) + (g_ext << 4) +
                         (g_ext << 2) + (g_ext << 1);
    wire [16:0] b_term = (b_ext << 4) + (b_ext << 3) +
                         (b_ext << 2) + b_ext;
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

