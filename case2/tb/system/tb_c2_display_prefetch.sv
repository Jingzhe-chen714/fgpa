`timescale 1ns/1ps

// Focused regression for the vertical-blank display-prefetch boundary.
// The first active frame is intentionally black.  A page request is committed
// at vblank_start, the updated base is captured at prefetch_start one clock
// later, and the following active frame consumes the prefetched pixels.
module tb_c2_display_prefetch;
    localparam int ADDR_W  = 16;
    localparam int DATA_W  = 16;
    localparam int H_ACTIVE = 4;
    localparam int H_FRONT  = 1;
    localparam int H_SYNC   = 1;
    localparam int H_BACK   = 2;
    localparam int V_ACTIVE = 2;
    localparam int V_FRONT  = 1;
    localparam int V_SYNC   = 1;
    localparam int V_BACK   = 2;
    localparam int H_TOTAL  = H_ACTIVE + H_FRONT + H_SYNC + H_BACK;
    localparam int V_TOTAL  = V_ACTIVE + V_FRONT + V_SYNC + V_BACK;
    localparam int H_COUNT_W = $clog2(H_TOTAL);
    localparam int V_COUNT_W = $clog2(V_TOTAL);

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    always #5 clk = ~clk;

    logic [H_COUNT_W-1:0] h_count;
    logic [V_COUNT_W-1:0] v_count;
    logic [$clog2(H_ACTIVE)-1:0] pixel_x;
    logic [$clog2(V_ACTIVE)-1:0] pixel_y;
    logic timing_de, active_video, timing_hsync, timing_vsync;
    logic hblank, vblank;
    logic active_frame_start, vblank_start, prefetch_start;
    logic frame_end, line_start, line_end, vsync_start, vsync_end;

    c2_video_timing_gen #(
        .H_ACTIVE(H_ACTIVE), .H_FRONT(H_FRONT), .H_SYNC(H_SYNC),
        .H_BACK(H_BACK), .V_ACTIVE(V_ACTIVE), .V_FRONT(V_FRONT),
        .V_SYNC(V_SYNC), .V_BACK(V_BACK)
    ) u_timing (
        .clk, .rst_n, .h_count, .v_count, .pixel_x, .pixel_y,
        .de(timing_de), .active_video, .hsync(timing_hsync),
        .vsync(timing_vsync), .hblank, .vblank,
        .frame_start(active_frame_start), .vblank_start, .prefetch_start,
        .frame_end, .line_start, .line_end, .vsync_start, .vsync_end
    );

    logic request_valid, request_ready, request_page;
    logic active_page, pending_page, flip_pending, flip_ack, request_error;

    c2_page_flip_ctrl #(.PAGE_W(1), .PAGE_COUNT(2)) u_page_flip (
        .clk, .rst_n, .frame_start(vblank_start),
        .request_valid, .request_ready, .request_page,
        .active_page, .pending_page, .flip_pending, .flip_ack,
        .request_error
    );

    logic [ADDR_W-1:0] base_addr;
    always_comb base_addr = active_page ? ADDR_W'(16'h0100) : '0;

    logic mem_req_valid, mem_req_ready, mem_req_write;
    logic [ADDR_W-1:0] mem_req_addr;
    logic [15:0] mem_req_len;
    logic [DATA_W-1:0] mem_req_wdata;
    logic [(DATA_W/8)-1:0] mem_req_wstrb;
    logic mem_rsp_valid, mem_rsp_ready;
    logic [DATA_W-1:0] mem_rsp_rdata;
    logic mem_rsp_last, mem_rsp_error;
    logic phy_pixel_ready;
    logic video_valid;
    logic [DATA_W-1:0] video_data;
    logic video_de, video_hsync, video_vsync;
    logic display_busy, display_done, display_error, display_underflow;
    logic [31:0] display_pixel_count, display_error_count;
    logic [$clog2(17)-1:0] fifo_level;

    c2_display_path #(
        .ADDR_W(ADDR_W), .DATA_W(DATA_W), .MAX_BURST_BEATS(4),
        .LINE_FIFO_DEPTH(16)
    ) u_display (
        .clk, .rst_n, .prefetch_start, .active_frame_start,
        .timing_de, .timing_hsync, .timing_vsync,
        .base_addr, .stride_bytes(ADDR_W'(8)),
        .width(16'(H_ACTIVE)), .height(16'(V_ACTIVE)),
        .phy_pixel_ready,
        .mem_req_valid, .mem_req_ready, .mem_req_write, .mem_req_addr,
        .mem_req_len, .mem_req_wdata, .mem_req_wstrb,
        .mem_rsp_valid, .mem_rsp_ready, .mem_rsp_rdata, .mem_rsp_last,
        .mem_rsp_error,
        .video_valid, .video_data, .video_de, .video_hsync, .video_vsync,
        .display_busy, .display_done, .display_error, .display_underflow,
        .display_pixel_count, .display_error_count, .fifo_level
    );

    // One-request-at-a-time deterministic read responder.  Disabling
    // memory_enable during the second blank intentionally produces an empty
    // third-frame boundary so the non-arming/underflow behavior is observable.
    logic memory_enable;
    logic rsp_active_q;
    logic [ADDR_W-1:0] rsp_addr_q;
    logic [16:0] rsp_beats_left_q;

    assign mem_req_ready = memory_enable && !rsp_active_q;
    assign mem_rsp_valid = rsp_active_q;
    assign mem_rsp_rdata = 16'hA000 | ((rsp_addr_q >> 1) & 16'h0fff);
    assign mem_rsp_last  = rsp_active_q && (rsp_beats_left_q == 1);
    assign mem_rsp_error = 1'b0;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rsp_active_q     <= 1'b0;
            rsp_addr_q       <= '0;
            rsp_beats_left_q <= '0;
        end else begin
            if (mem_req_valid && mem_req_ready) begin
                if (mem_req_write)
                    $fatal(1, "display issued a write request");
                rsp_active_q     <= 1'b1;
                rsp_addr_q       <= mem_req_addr;
                rsp_beats_left_q <= {1'b0, mem_req_len} + 17'd1;
            end else if (mem_rsp_valid && mem_rsp_ready) begin
                if (rsp_beats_left_q == 1) begin
                    rsp_active_q     <= 1'b0;
                    rsp_beats_left_q <= '0;
                end else begin
                    rsp_addr_q       <= rsp_addr_q + ADDR_W'(DATA_W/8);
                    rsp_beats_left_q <= rsp_beats_left_q - 17'd1;
                end
            end
        end
    end

    integer active_frame_count;
    integer second_frame_pixels;
    integer first_req_seen;
    integer expect_prefetch;
    integer expect_underflow_clear;
    integer third_frame_seen;
    logic [31:0] error_count_before_phy_stall;

    always @(negedge clk) begin
        if (!rst_n) begin
            active_frame_count       = 0;
            second_frame_pixels      = 0;
            first_req_seen           = 0;
            expect_prefetch          = 0;
            expect_underflow_clear   = 0;
            third_frame_seen         = 0;
            error_count_before_phy_stall = '0;
        end else begin
            if (expect_prefetch) begin
                if (!prefetch_start)
                    $fatal(1, "prefetch_start was not one clock after vblank_start");
                if (!vblank)
                    $fatal(1, "prefetch_start escaped vertical blanking");
                if (!active_page)
                    $fatal(1, "prefetch captured before page commit settled");
                expect_prefetch = 0;
            end
            if (vblank_start) begin
                if (prefetch_start)
                    $fatal(1, "vblank_start and prefetch_start must be separated");
                expect_prefetch = 1;
                if (active_frame_count == 2)
                    memory_enable = 1'b0;
            end

            if (expect_underflow_clear) begin
                if (display_underflow)
                    $fatal(1, "underflow did not clear at the next prefetch");
                expect_underflow_clear = 0;
            end
            if (prefetch_start && third_frame_seen)
                expect_underflow_clear = 1;

            if (active_frame_start) begin
                active_frame_count = active_frame_count + 1;
                if (active_frame_count == 3)
                    third_frame_seen = 1;
            end

            if (active_frame_count == 1 && timing_de && video_valid)
                $fatal(1, "reset-time first frame was not black");

            if (mem_req_valid && mem_req_ready && !first_req_seen) begin
                first_req_seen = 1;
                if (mem_req_addr != 16'h0100)
                    $fatal(1, "display captured stale page base: %h", mem_req_addr);
            end

            if (active_frame_count == 2 && video_valid) begin
                if (video_data != (16'hA080 + second_frame_pixels))
                    $fatal(1, "pixel %0d mismatch: got %h", second_frame_pixels,
                           video_data);
                second_frame_pixels = second_frame_pixels + 1;
            end

            if (active_frame_count == 3 && active_frame_start)
                error_count_before_phy_stall = display_error_count;

            if (active_frame_count == 3 && h_count == 1 && v_count == 0)
                phy_pixel_ready = 1'b0;
            else if (!phy_pixel_ready)
                phy_pixel_ready = 1'b1;

            if (active_frame_count == 3 && h_count == 3 && v_count == 0) begin
                if (!display_underflow)
                    $fatal(1, "empty prefetched frame did not report underflow");
                if (display_error_count <= error_count_before_phy_stall)
                    $fatal(1, "active-video phy not-ready was not counted");
                if (video_valid)
                    $fatal(1, "late data armed a partial third frame");
            end

            if (active_frame_count >= 4) begin
                if (second_frame_pixels != H_ACTIVE*V_ACTIVE)
                    $fatal(1, "expected %0d second-frame pixels, got %0d",
                           H_ACTIVE*V_ACTIVE, second_frame_pixels);
                if (!first_req_seen)
                    $fatal(1, "no display request observed");
                $display("TB_C2_DISPLAY_PREFETCH_PASS pixels=%0d errors=%0d",
                         second_frame_pixels, display_error_count);
                $finish;
            end
        end
    end

    initial begin
        request_valid   = 1'b0;
        request_page    = 1'b1;
        phy_pixel_ready = 1'b1;
        memory_enable   = 1'b1;

        repeat (3) @(posedge clk);
        #1 rst_n = 1'b1;

        // Queue page 1 during the first active frame.
        @(negedge clk);
        if (!request_ready)
            $fatal(1, "page request interface was not ready");
        request_valid = 1'b1;
        @(negedge clk);
        request_valid = 1'b0;

        repeat (H_TOTAL*V_TOTAL*6) @(posedge clk);
        $fatal(1, "timeout");
    end
endmodule
