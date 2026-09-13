`timescale 1ns/1ps

// Two-line 3x3 window generator backed by Xilinx XPM BRAM.
//
// This is the BRAM-backed counterpart of window3x3_gray.sv.  The external
// stream contract and VALID_ONLY border policy are intentionally identical.
// The implementation keeps two physical rows and rotates their roles:
//   current bank is overwritten with the incoming row;
//   the other bank supplies y-1;
//   the current bank, read with XPM READ_FIRST semantics, supplies y-2.
//
// Because XPM BRAM reads are synchronous, input metadata/pixel and bank role
// are delayed one clock before the nine taps are assembled.  All sideband and
// coordinates are delayed with the same register boundary.
//
// VENDOR BOUNDARY: xilinx_bram_sdp_row.sv is the only Xilinx-specific memory
// implementation.  For an Efinix or other FPGA build, replace that wrapper
// (or this module) with the corresponding dual-port BRAM/IP implementation and
// preserve the one-cycle read, READ_FIRST collision, and reset contract.

module window3x3_gray_xilinx_bram #(
    parameter integer IMG_WIDTH  = 640,
    parameter integer IMG_HEIGHT = 480,
    parameter integer PIXEL_BITS = 8,
    parameter integer X_BITS = (IMG_WIDTH  <= 1) ? 1 : $clog2(IMG_WIDTH),
    parameter integer Y_BITS = (IMG_HEIGHT <= 1) ? 1 : $clog2(IMG_HEIGHT)
) (
    input  logic                   clk,
    input  logic                   rst,

    input  logic                   in_valid,
    input  logic                   in_sof,
    input  logic                   in_eol,
    input  logic                   in_eof,
    input  logic [X_BITS-1:0]      in_x,
    input  logic [Y_BITS-1:0]      in_y,
    input  logic [PIXEL_BITS-1:0]  in_pixel,

    output logic                   out_valid,
    output logic                   out_sof,
    output logic                   out_eol,
    output logic                   out_eof,
    output logic [X_BITS-1:0]      out_x,
    output logic [Y_BITS-1:0]      out_y,
    output logic [PIXEL_BITS-1:0]  out_p00,
    output logic [PIXEL_BITS-1:0]  out_p01,
    output logic [PIXEL_BITS-1:0]  out_p02,
    output logic [PIXEL_BITS-1:0]  out_p10,
    output logic [PIXEL_BITS-1:0]  out_p11,
    output logic [PIXEL_BITS-1:0]  out_p12,
    output logic [PIXEL_BITS-1:0]  out_p20,
    output logic [PIXEL_BITS-1:0]  out_p21,
    output logic [PIXEL_BITS-1:0]  out_p22
);

    localparam integer ADDR_WIDTH = (IMG_WIDTH <= 1) ? 1 : $clog2(IMG_WIDTH);

    initial begin
        if (IMG_WIDTH < 3 || IMG_HEIGHT < 3 || PIXEL_BITS < 1)
            $fatal(1, "CASE4_PARAM_WINDOW_SIZE: dimensions >= 3 and PIXEL_BITS >= 1 required");
        if (X_BITS < 1 || Y_BITS < 1 || X_BITS < $clog2(IMG_WIDTH) || Y_BITS < $clog2(IMG_HEIGHT))
            $fatal(1, "CASE4_PARAM_COORD: coordinate widths cannot represent the image");
    end

    logic [ADDR_WIDTH-1:0] rd_addr;
    logic [ADDR_WIDTH-1:0] wr_addr;
    logic                   rd_en0, rd_en1;
    logic                   wr_en0, wr_en1;
    logic [PIXEL_BITS-1:0]  row0_rd;
    logic [PIXEL_BITS-1:0]  row1_rd;
    logic                   cur_bank;
    logic                   effective_bank;
    logic                   line_end;

    // Delayed transaction corresponding to the BRAM data returned this
    // cycle.  bank_d selects which returned bank is y-2 versus y-1.
    logic                   valid_d, sof_d, eol_d, eof_d;
    logic [X_BITS-1:0]      x_d;
    logic [Y_BITS-1:0]      y_d;
    logic [PIXEL_BITS-1:0]  pixel_d;
    logic                   bank_d;

    logic [PIXEL_BITS-1:0]  top_at_x_d;
    logic [PIXEL_BITS-1:0]  mid_at_x_d;
    logic [PIXEL_BITS-1:0]  top_d1, top_d0;
    logic [PIXEL_BITS-1:0]  mid_d1, mid_d0;
    logic [PIXEL_BITS-1:0]  bot_d1, bot_d0;
    logic                   interior_d;
    logic                   line_end_d;

    always_comb begin
        effective_bank = in_sof ? 1'b0 : cur_bank;
        line_end = in_eol || (in_x == IMG_WIDTH-1);

        rd_addr = in_x[ADDR_WIDTH-1:0];
        wr_addr = in_x[ADDR_WIDTH-1:0];
        rd_en0 = 1'b0;
        rd_en1 = 1'b0;
        wr_en0 = 1'b0;
        wr_en1 = 1'b0;

        // Both rows are read for every input pixel.  The current bank is
        // also read while written; xilinx_bram_sdp_row is configured
        // READ_FIRST so that read returns the previous (y-2) sample.
        if (!rst && in_valid && (in_x < IMG_WIDTH)) begin
            rd_en0 = 1'b1;
            rd_en1 = 1'b1;
            if (effective_bank == 1'b0)
                wr_en0 = 1'b1;
            else
                wr_en1 = 1'b1;
        end
    end

    xilinx_bram_sdp_row #(
        .DEPTH(IMG_WIDTH), .DATA_WIDTH(PIXEL_BITS), .ADDR_WIDTH(ADDR_WIDTH)
    ) u_row0 (
        .clk(clk), .rst(rst),
        .wr_en(wr_en0), .wr_addr(wr_addr), .wr_data(in_pixel),
        .rd_en(rd_en0), .rd_addr(rd_addr), .rd_data(row0_rd)
    );

    xilinx_bram_sdp_row #(
        .DEPTH(IMG_WIDTH), .DATA_WIDTH(PIXEL_BITS), .ADDR_WIDTH(ADDR_WIDTH)
    ) u_row1 (
        .clk(clk), .rst(rst),
        .wr_en(wr_en1), .wr_addr(wr_addr), .wr_data(in_pixel),
        .rd_en(rd_en1), .rd_addr(rd_addr), .rd_data(row1_rd)
    );

    // BRAM output data is for the transaction described by bank_d/x_d,
    // not the currently arriving transaction.  Select the old current bank
    // as y-2 and the opposite bank as y-1.
    always_comb begin
        if (bank_d == 1'b0) begin
            top_at_x_d = row0_rd;
            mid_at_x_d = row1_rd;
        end else begin
            top_at_x_d = row1_rd;
            mid_at_x_d = row0_rd;
        end
        interior_d = valid_d && (x_d >= 2) && (y_d >= 2) &&
                     (x_d < IMG_WIDTH) && (y_d < IMG_HEIGHT);
        line_end_d = eol_d || (x_d == IMG_WIDTH-1);
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            cur_bank <= 1'b0;
            valid_d  <= 1'b0;
            sof_d    <= 1'b0;
            eol_d    <= 1'b0;
            eof_d    <= 1'b0;
            x_d      <= '0;
            y_d      <= '0;
            pixel_d  <= '0;
            bank_d   <= 1'b0;

            top_d1 <= '0;
            top_d0 <= '0;
            mid_d1 <= '0;
            mid_d0 <= '0;
            bot_d1 <= '0;
            bot_d0 <= '0;

            out_valid <= 1'b0;
            out_sof   <= 1'b0;
            out_eol   <= 1'b0;
            out_eof   <= 1'b0;
            out_x     <= '0;
            out_y     <= '0;
            out_p00   <= '0;
            out_p01   <= '0;
            out_p02   <= '0;
            out_p10   <= '0;
            out_p11   <= '0;
            out_p12   <= '0;
            out_p20   <= '0;
            out_p21   <= '0;
            out_p22   <= '0;
        end else begin
            // Assemble the window for the input transaction whose BRAM read
            // completed one clock ago.
            out_valid <= 1'b0;
            out_sof   <= 1'b0;
            out_eol   <= 1'b0;
            out_eof   <= 1'b0;

            if (valid_d) begin
                if (interior_d) begin
                    out_valid <= 1'b1;
                    out_sof   <= (x_d == 2) && (y_d == 2);
                    out_eol   <= line_end_d;
                    out_eof   <= line_end_d &&
                                 (eof_d || ((y_d == IMG_HEIGHT-1) &&
                                            (x_d == IMG_WIDTH-1)));
                    out_x     <= x_d - 1'b1;
                    out_y     <= y_d - 1'b1;
                    out_p00   <= top_d1;
                    out_p01   <= top_d0;
                    out_p02   <= top_at_x_d;
                    out_p10   <= mid_d1;
                    out_p11   <= mid_d0;
                    out_p12   <= mid_at_x_d;
                    out_p20   <= bot_d1;
                    out_p21   <= bot_d0;
                    out_p22   <= pixel_d;
                end

                if (x_d == 0) begin
                    top_d1 <= '0;
                    top_d0 <= top_at_x_d;
                    mid_d1 <= '0;
                    mid_d0 <= mid_at_x_d;
                    bot_d1 <= '0;
                    bot_d0 <= pixel_d;
                end else begin
                    top_d1 <= top_d0;
                    top_d0 <= top_at_x_d;
                    mid_d1 <= mid_d0;
                    mid_d0 <= mid_at_x_d;
                    bot_d1 <= bot_d0;
                    bot_d0 <= pixel_d;
                end
            end

            // Capture the transaction associated with the next BRAM output.
            valid_d <= in_valid;
            if (in_valid) begin
                sof_d   <= in_sof;
                eol_d   <= in_eol;
                eof_d   <= in_eof;
                x_d     <= in_x;
                y_d     <= in_y;
                pixel_d <= in_pixel;
                bank_d  <= effective_bank;

                if (in_sof)
                    cur_bank <= line_end ? 1'b1 : 1'b0;
                else if (line_end)
                    cur_bank <= ~cur_bank;
            end else begin
                sof_d <= 1'b0;
                eol_d <= 1'b0;
                eof_d <= 1'b0;
            end
        end
    end

endmodule
