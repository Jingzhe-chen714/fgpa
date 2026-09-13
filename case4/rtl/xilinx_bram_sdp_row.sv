`timescale 1ns/1ps

// Xilinx-specific BRAM boundary for one raster line.
//
// This wrapper intentionally contains the only Xilinx XPM dependency in the
// line-buffer path.  A later Efinix/other-FPGA port should replace this file
// with the target vendor's dual-port BRAM/IP wrapper while keeping the
// read/write/latency contract below unchanged.
//
// Contract:
//   * one synchronous write port (port A), one synchronous read port (port B)
//   * read latency is exactly one rising edge when rd_en is asserted
//   * read-during-write at the same address is READ_FIRST (old data is
//     returned); the two-row window relies on this behavior
//   * rst is active-high synchronous and resets the read output, not memory
//     contents
//
// The default 640x8 configuration occupies one Xilinx BRAM18-class block.

module xilinx_bram_sdp_row #(
    parameter integer DEPTH      = 640,
    parameter integer DATA_WIDTH = 8,
    parameter integer ADDR_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH)
) (
    input  logic                  clk,
    input  logic                  rst,
    input  logic                  wr_en,
    input  logic [ADDR_WIDTH-1:0] wr_addr,
    input  logic [DATA_WIDTH-1:0] wr_data,
    input  logic                  rd_en,
    input  logic [ADDR_WIDTH-1:0] rd_addr,
    output logic [DATA_WIDTH-1:0] rd_data
);

    localparam integer MEMORY_SIZE = DEPTH * DATA_WIDTH;
    initial begin
        if (DEPTH < 1 || DATA_WIDTH < 1 || ADDR_WIDTH < 1 || ADDR_WIDTH < $clog2(DEPTH))
            $fatal(1, "CASE4_PARAM_BRAM: positive dimensions and sufficient address width required");
    end

    // XPM is supplied by Vivado's Xilinx primitive library.  The regression
    // script explicitly compiles xpm_memory.sv so this module also works in
    // a standalone xvlog/xelab flow.
    xpm_memory_sdpram #(
        .MEMORY_SIZE        (MEMORY_SIZE),
        .MEMORY_PRIMITIVE   ("block"),
        .CLOCKING_MODE      ("common_clock"),
        .ECC_MODE           ("no_ecc"),
        .MEMORY_INIT_FILE   ("none"),
        .MEMORY_INIT_PARAM  (""),
        .USE_MEM_INIT       (0),
        .USE_MEM_INIT_MMI   (0),
        .MESSAGE_CONTROL    (0),
        .WRITE_DATA_WIDTH_A (DATA_WIDTH),
        .BYTE_WRITE_WIDTH_A (DATA_WIDTH),
        .ADDR_WIDTH_A       (ADDR_WIDTH),
        .READ_DATA_WIDTH_B  (DATA_WIDTH),
        .ADDR_WIDTH_B       (ADDR_WIDTH),
        .READ_RESET_VALUE_B ("0"),
        .READ_LATENCY_B     (1),
        .WRITE_MODE_B       ("read_first"),
        .RST_MODE_B         ("SYNC")
    ) u_xpm_row (
        .sleep          (1'b0),
        .clka           (clk),
        .ena            (wr_en && !rst),
        .wea            (wr_en && !rst),
        .addra          (wr_addr),
        .dina           (wr_data),
        .injectsbiterra (1'b0),
        .injectdbiterra (1'b0),
        .clkb           (clk),
        .rstb           (rst),
        .enb            (rd_en && !rst),
        .regceb         (1'b1),
        .addrb          (rd_addr),
        .doutb          (rd_data),
        .sbiterrb       (),
        .dbiterrb       ()
    );

endmodule
