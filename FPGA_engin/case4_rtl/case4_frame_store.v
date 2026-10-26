`timescale 1ns/1ps
// Four-bank RGB565 frame store. Reuses the board's Efinix asymmetric FIFOs;
// a bank is published only after its complete frame and every AXI write response.
// Camera VSYNC falls at EOF; display rframe_vsync falls in vertical blanking.
module case4_frame_store #(
    parameter C_ID_LEN = 4,
    parameter C_RD_END_ADDR = 1280*720*2,
    parameter C_W_WIDTH = 8,
    parameter C_R_WIDTH = 16,
    parameter C_BUF_SIZE = 22,
    parameter C_BURST_LEN = 128
)(
    input wire axi_clk, axi_reset,
    output wire [31:0] axi_awaddr,
    output wire [7:0] axi_awlen,
    output wire axi_awvalid,
    input wire axi_awready,
    output wire [127:0] axi_wdata,
    output wire [15:0] axi_wstrb,
    output wire axi_wlast, axi_wvalid,
    input wire axi_wready,
    input wire [C_ID_LEN-1:0] axi_bid,
    input wire [1:0] axi_bresp,
    input wire axi_bvalid,
    output wire axi_bready,
    output wire [C_ID_LEN-1:0] axi_arid,
    output wire [31:0] axi_araddr,
    output wire [7:0] axi_arlen,
    output wire axi_arvalid,
    input wire axi_arready,
    input wire [C_ID_LEN-1:0] axi_rid,
    input wire [127:0] axi_rdata,
    input wire [1:0] axi_rresp,
    input wire axi_rlast, axi_rvalid,
    output wire axi_rready,
    input wire wframe_pclk, wframe_vsync, wframe_data_en,
    input wire [C_W_WIDTH-1:0] wframe_data,
    input wire rframe_pclk, rframe_vsync, rframe_data_en,
    output wire [C_R_WIDTH-1:0] rframe_data,
    input wire freeze_request,
    output reg frozen,
    output wire frame_ready,
    output wire error,
    output wire [31:0] tp_o
);
    localparam BURST_BYTES = C_BURST_LEN*16;
    localparam FRAME_WORDS = C_RD_END_ADDR/(C_W_WIDTH/8);
    // The supplied board IP is fixed at 8 -> 128 and 128 -> 16 bits.
    // 720p RGB565 frames contain exactly 900 complete 128-beat bursts.
    localparam W_IDLE=0, W_ADDR=1, W_DATA=2, W_RESP=3, W_RESET=4;
    localparam R_IDLE=0, R_ADDR=1, R_DATA=2, R_RESET=3, R_RELEASE=4;
    reg [2:0] ws;
    reg [2:0] rs;
    reg [1:0] write_bank, read_bank, latest_bank;
    reg latest_valid, read_valid;
    reg [C_BUF_SIZE-1:0] write_offset, read_offset;
    reg [7:0] write_beat;
    reg [6:0] write_reset_count, read_reset_count;
    reg write_fifo_reset, read_fifo_reset;
    reg write_failed, bus_error;
    reg end_pending, end_good;
    reg capture_ack;
    reg read_pending;
    (* async_reg = "true" *) reg [2:0] eof_sync;
    (* async_reg = "true" *) reg [2:0] display_sync;
    (* async_reg = "true" *) reg [1:0] freeze_sync;

    wire write_full, write_empty, write_almost_empty, write_busy;
    wire [127:0] write_data;
    wire read_full, read_empty, read_busy;
    wire [15:0] read_data;
    wire write_pop = axi_wvalid && axi_wready;
    wire read_push = axi_rvalid && axi_rready && (rs == R_DATA);

    // Capture-side metadata is held stable for a complete frame. Its toggle
    // crosses three synchronizer stages, after the metadata settles.
    reg capture_vsync_d, capture_armed, capture_bad;
    reg capture_started, capture_boundary_seen;
    reg [24:0] capture_count;
    reg capture_eof_toggle, capture_good;
    (* async_reg = "true" *) reg [1:0] writer_reset_sync;
    (* async_reg = "true" *) reg [1:0] capture_ack_sync;
    wire capture_end = capture_vsync_d && !wframe_vsync;
    // Decide admission once, on the first byte of a frame. The writer's EOF
    // acknowledgement prevents a delayed previous tail from mixing with the
    // next camera frame. If DDR is still busy, drop a WHOLE incoming frame.
    wire capture_admit = !capture_started && capture_boundary_seen &&
                         (capture_ack_sync[1] == capture_eof_toggle) &&
                         !writer_reset_sync[1] && !write_busy;
    wire capture_accept = (capture_armed || capture_admit) && wframe_data_en &&
                          !writer_reset_sync[1] && !write_busy &&
                          (capture_count < FRAME_WORDS);
    always @(posedge wframe_pclk or posedge axi_reset) begin
        if (axi_reset) begin
            capture_vsync_d <= 0;
            capture_armed <= 0;
            capture_started <= 0;
            capture_boundary_seen <= 0;
            capture_bad <= 0;
            capture_count <= 0;
            capture_eof_toggle <= 0;
            capture_good <= 0;
            writer_reset_sync <= 2'b11;
            capture_ack_sync <= 0;
        end else begin
            capture_vsync_d <= wframe_vsync;
            writer_reset_sync <= {writer_reset_sync[0], write_fifo_reset};
            capture_ack_sync <= {capture_ack_sync[0], capture_ack};
            if (capture_end) begin
                if (capture_armed) begin
                    capture_good <= !capture_bad && (capture_count == FRAME_WORDS);
                    capture_eof_toggle <= !capture_eof_toggle;
                end
                capture_count <= 0;
                capture_bad <= 0;
                capture_armed <= 0;
                capture_started <= 0;
                capture_boundary_seen <= 1;
            end else if (wframe_data_en) begin
                if (!capture_started) begin
                    capture_started <= 1;
                    capture_armed <= capture_admit;
                end
                if (capture_armed || capture_admit) begin
                    if (capture_count < FRAME_WORDS+1)
                        capture_count <= capture_count + 1'b1;
                    if (!capture_accept || write_full)
                        capture_bad <= 1;
                end
            end
        end
    end

    W0_FIFO_8 capture_fifo (
        .wr_clk_i(wframe_pclk), .wr_en_i(capture_accept && !write_full),
        .wdata(wframe_data), .a_rst_i(axi_reset || write_fifo_reset),
        .rd_clk_i(axi_clk), .rd_en_i(write_pop), .rdata(write_data),
        .prog_empty_o(write_almost_empty), .empty_o(write_empty),
        .full_o(write_full), .rst_busy(write_busy)
    );

    reg display_vsync_d, display_toggle;
    reg display_bad;
    (* async_reg = "true" *) reg [1:0] read_valid_sync;
    always @(posedge rframe_pclk or posedge axi_reset) begin
        if (axi_reset) begin
            display_vsync_d <= 0;
            display_toggle <= 0;
            display_bad <= 0;
            read_valid_sync <= 0;
        end else begin
            display_vsync_d <= rframe_vsync;
            read_valid_sync <= {read_valid_sync[0], read_valid};
            if (display_vsync_d && !rframe_vsync) begin
                display_toggle <= !display_toggle;
                display_bad <= 0;
            end else if (rframe_data_en && read_valid_sync[1] && read_empty)
                display_bad <= 1;
        end
    end
    R0_FIFO_16 display_fifo (
        .wr_clk_i(axi_clk), .wr_en_i(read_push), .wdata(axi_rdata),
        .a_rst_i(axi_reset || read_fifo_reset), .prog_full_o(read_full),
        .rst_busy(read_busy),
        .rd_clk_i(rframe_pclk),
        .rd_en_i(rframe_data_en && read_valid_sync[1] && !read_empty),
        .rdata(read_data), .empty_o(read_empty)
    );
    assign rframe_data = read_valid_sync[1] && !read_empty && !display_bad
                      ? read_data : 16'b0;

    // Never choose the current reader, the last committed frame, or the bank
    // just completed. Four banks guarantee a free candidate even if read and
    // write boundaries coincide. Frozen readers retain ownership indefinitely.
    reg [1:0] next_write_bank;
    integer candidate;
    always @* begin
        next_write_bank = write_bank;
        for (candidate=1; candidate<4; candidate=candidate+1)
            if (((write_bank+candidate)%4 != read_bank) &&
                (!latest_valid || (write_bank+candidate)%4 != latest_bank))
                next_write_bank = (write_bank+candidate)%4;
    end

    always @(posedge axi_clk or posedge axi_reset) begin
        if (axi_reset) begin
            eof_sync <= 0;
            display_sync <= 0;
            freeze_sync <= 0;
        end else begin
            eof_sync <= {eof_sync[1:0], capture_eof_toggle};
            display_sync <= {display_sync[1:0], display_toggle};
            freeze_sync <= {freeze_sync[0], freeze_request};
        end
    end

    // One write burst outstanding. B-response retires it before bank commit.
    always @(posedge axi_clk or posedge axi_reset) begin
        if (axi_reset) begin
            ws <= W_RESET;
            write_bank <= 0;
            latest_bank <= 0;
            latest_valid <= 0;
            write_offset <= 0;
            write_beat <= 0;
            write_reset_count <= 7'd63;
            write_fifo_reset <= 1;
            write_failed <= 0;
            bus_error <= 0;
            end_pending <= 0;
            end_good <= 0;
            capture_ack <= 0;
        end else begin
            if (eof_sync[2] != eof_sync[1]) begin
                end_pending <= 1;
                end_good <= capture_good;
            end
            case (ws)
                W_RESET: begin
                    if (write_reset_count != 0)
                        write_reset_count <= write_reset_count - 1'b1;
                    else begin
                        write_fifo_reset <= 0;
                        ws <= W_IDLE;
                    end
                end
                W_IDLE: begin
                    if (!write_almost_empty && write_offset < C_RD_END_ADDR) begin
                        write_beat <= 0;
                        ws <= W_ADDR;
                    end else if (end_pending &&
                        (!end_good || write_failed || write_offset == C_RD_END_ADDR)) begin
                        // Bad/partial frames are discarded, never displayed.
                        // A good EOF may arrive BEFORE the FIFO's synchronized
                        // final write pointer. Wait for the known byte count,
                        // never decide completion from a transient empty flag.
                        if (end_good && !write_failed &&
                            write_offset == C_RD_END_ADDR) begin
                            latest_bank <= write_bank;
                            latest_valid <= 1;
                        end
                        write_bank <= next_write_bank;
                        write_offset <= 0;
                        write_failed <= 0;
                        end_pending <= 0;
                        capture_ack <= eof_sync[2];
                        write_fifo_reset <= 1;
                        write_reset_count <= 7'd63;
                        ws <= W_RESET;
                    end
                end
                W_ADDR: if (axi_awready) ws <= W_DATA;
                W_DATA: if (axi_wready) begin
                    if (write_empty) begin
                        write_failed <= 1;
                        bus_error <= 1;
                    end
                    if (write_beat == C_BURST_LEN-1)
                        ws <= W_RESP;
                    else write_beat <= write_beat + 1'b1;
                end
                W_RESP: if (axi_bvalid) begin
                    if (axi_bresp != 0) begin
                        write_failed <= 1;
                        bus_error <= 1;
                    end
                    write_offset <= write_offset + BURST_BYTES;
                    ws <= W_IDLE;
                end
                default: ws <= W_RESET;
            endcase
        end
    end

    reg read_error;
    always @(posedge axi_clk or posedge axi_reset) begin
        if (axi_reset) begin
            rs <= R_RESET;
            read_bank <= 2;
            read_valid <= 0;
            read_pending <= 1;
            read_offset <= 0;
            read_reset_count <= 7'd63;
            read_fifo_reset <= 1;
            read_error <= 0;
            frozen <= 0;
        end else begin
            if (display_sync[2] != display_sync[1]) read_pending <= 1;
            case (rs)
                R_IDLE: begin
                    if (read_pending) begin
                        read_pending <= 0;
                        // Keep the same bank while frozen. Before the first
                        // valid frame, freeze waits for a committed image.
                        if ((!frozen || !freeze_sync[1] || !read_valid) && latest_valid) begin
                            read_bank <= latest_bank;
                            read_valid <= 1;
                        end
                        frozen <= freeze_sync[1] && (read_valid || latest_valid);
                        read_offset <= 0;
                        read_fifo_reset <= 1;
                        read_reset_count <= 7'd63;
                        rs <= R_RESET;
                    end else if (read_valid && !read_full && read_offset < C_RD_END_ADDR)
                        rs <= R_ADDR;
                end
                R_ADDR: if (axi_arready) rs <= R_DATA;
                R_DATA: if (axi_rvalid && axi_rlast) begin
                    read_offset <= read_offset + BURST_BYTES;
                    rs <= R_IDLE;
                end
                R_RESET: begin
                    if (read_reset_count != 0)
                        read_reset_count <= read_reset_count - 1'b1;
                    else begin
                        read_fifo_reset <= 0;
                        // Efinix resets deassert independently in both clock
                        // domains. Do not issue a burst while either is busy.
                        read_reset_count <= 7'd15;
                        rs <= R_RELEASE;
                    end
                end
                R_RELEASE: begin
                    if (read_reset_count != 0)
                        read_reset_count <= read_reset_count - 1'b1;
                    else if (!read_busy) rs <= R_IDLE;
                end
            endcase
            if (read_push && axi_rresp != 0) read_error <= 1;
        end
    end
    assign axi_awaddr = { {(30-C_BUF_SIZE){1'b0}}, write_bank, write_offset };
    assign axi_araddr = { {(30-C_BUF_SIZE){1'b0}}, read_bank, read_offset };
    assign axi_awlen = C_BURST_LEN-1;
    assign axi_arlen = C_BURST_LEN-1;
    assign axi_arid = 0;
    assign axi_awvalid = ws == W_ADDR;
    assign axi_wvalid = ws == W_DATA;
    assign axi_wlast = write_beat == C_BURST_LEN-1;
    assign axi_wdata = write_data;
    assign axi_wstrb = 16'hffff;
    assign axi_bready = ws == W_RESP;
    assign axi_arvalid = rs == R_ADDR;
    assign axi_rready = rs == R_DATA;
    assign frame_ready = latest_valid;
    assign error = bus_error || read_error;
    assign tp_o = {23'b0, error, frozen, latest_valid, read_valid, rs, ws[1:0]};
endmodule
