`timescale 1ns/1ps

// Reserved replacement point for Efinix MIPI/HDMI/VGA output IP.  The system
// wrapper supplies a timing-qualified RGB565 stream; the generated IP owns
// serialization, PHY clocks, IO standards and board-specific pins.
(* black_box = "true" *)
module c2_video_phy_blackbox #(
    parameter int DATA_W = 16
) (
    input  logic                 clk_pix,
    input  logic                 rst_n,
    input  logic                 pixel_valid,
    output logic                 pixel_ready,
    input  logic [DATA_W-1:0]    pixel_data,
    input  logic                 pixel_de,
    input  logic                 pixel_hsync,
    input  logic                 pixel_vsync,
    output logic                 phy_clk,
    output logic [DATA_W-1:0]    phy_data,
    output logic                 phy_de,
    output logic                 phy_hsync,
    output logic                 phy_vsync,
    output logic                 phy_valid,
    output logic                 init_done,
    output logic                 init_error
);
endmodule
