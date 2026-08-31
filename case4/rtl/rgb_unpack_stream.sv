// RGB565/RGB888 pixel unpacker with a one-clock streaming pipeline.
//
// PIXEL_FORMAT = 0: RGB565, pixel_in[15:11]=R, [10:5]=G, [4:0]=B.
// PIXEL_FORMAT = 1: RGB888, pixel_in[23:16]=R, [15:8]=G, [7:0]=B.
//
// The RGB565 expansion uses bit replication rather than a multiply:
//   R8={R5,R5[4:2]}, G8={G6,G6[5:4]}, B8={B5,B5[4:2]}.
// `rst` is synchronous, active high.  Every output, including sideband,
// is delayed by exactly one rising edge when in_valid is asserted.  When
// in_valid is low, m_valid and all sideband pulses are driven low.

`timescale 1ns/1ps

module rgb_unpack_stream #(
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
    // For RGB565 only pixel_in[15:0] is used.  Keeping a common 24-bit
    // port makes the module easy to place after either DVP packing mode.
    input  wire [23:0]          pixel_in,
    output reg                  m_valid,
    output reg                  m_sof,
    output reg                  m_eol,
    output reg                  m_eof,
    output reg [X_W-1:0]        m_x,
    output reg [Y_W-1:0]        m_y,
    output reg [7:0]            m_r,
    output reg [7:0]            m_g,
    output reg [7:0]            m_b
);

    reg [7:0] r_unpacked;
    reg [7:0] g_unpacked;
    reg [7:0] b_unpacked;

    always @* begin
        if (PIXEL_FORMAT == 0) begin
            // RGB565 -> full-range RGB888.  The replicated high bits give
            // the nearest uniformly spaced 8-bit code for each component.
            r_unpacked = {pixel_in[15:11], pixel_in[15:13]};
            g_unpacked = {pixel_in[10:5],  pixel_in[10:9]};
            b_unpacked = {pixel_in[4:0],   pixel_in[4:2]};
        end else begin
            r_unpacked = pixel_in[23:16];
            g_unpacked = pixel_in[15:8];
            b_unpacked = pixel_in[7:0];
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            m_valid <= 1'b0;
            m_sof   <= 1'b0;
            m_eol   <= 1'b0;
            m_eof   <= 1'b0;
            m_x     <= {X_W{1'b0}};
            m_y     <= {Y_W{1'b0}};
            m_r     <= 8'd0;
            m_g     <= 8'd0;
            m_b     <= 8'd0;
        end else begin
            m_valid <= in_valid;
            if (in_valid) begin
                m_sof <= in_sof;
                m_eol <= in_eol;
                m_eof <= in_eof;
                m_x   <= in_x;
                m_y   <= in_y;
                m_r   <= r_unpacked;
                m_g   <= g_unpacked;
                m_b   <= b_unpacked;
            end else begin
                m_sof <= 1'b0;
                m_eol <= 1'b0;
                m_eof <= 1'b0;
                m_x   <= {X_W{1'b0}};
                m_y   <= {Y_W{1'b0}};
                m_r   <= 8'd0;
                m_g   <= 8'd0;
                m_b   <= 8'd0;
            end
        end
    end

endmodule

