`timescale 1ns/1ps

// Self-checking regression for the renderer's row-level read-burst path.
//
// The model below implements the same abstract split channels used by the
// owner-aware arbiter: a descriptor is accepted first, read data is returned
// as an ordered burst, and write data is followed by a delayed commit
// response.  The test deliberately applies back-pressure on every channel.
//
// Coverage:
//   * BLOCK_COPY whose first source row starts eight bytes before a 4 KiB
//     boundary (MAX_READ_BEATS=4), proving both boundary and length splits;
//   * COLOR_KEY with full-row source/background bursts and final writeback;
//   * an early read rsp_last injection, which must terminate with done_error.
module tb_render_cmd_mem_engine_read_burst;
    localparam int DATA_W    = 16;
    localparam int MEM_WORDS = 16384;

    localparam logic [2:0] OP_BLOCK_COPY = 3'd2;
    localparam logic [2:0] OP_COLOR_KEY  = 3'd4;

    logic clk = 1'b0;
    always #5 clk = ~clk;
    logic rst_n = 1'b0;

    logic desc_valid;
    logic desc_ready;
    logic [31:0] desc_seq;
    logic [2:0] desc_op;
    logic [7:0] desc_flags;
    logic [1:0] desc_pixel_fmt;
    logic [31:0] desc_src_addr;
    logic [31:0] desc_dst_addr;
    logic [15:0] desc_width;
    logic [15:0] desc_height;
    logic [15:0] desc_src_stride;
    logic [15:0] desc_dst_stride;
    logic [31:0] desc_color;
    logic [7:0] desc_alpha;
    logic [15:0] desc_color_key;

    logic mem_req_valid;
    logic mem_req_ready;
    logic mem_req_write;
    logic [31:0] mem_req_addr;
    logic [15:0] mem_req_len;
    logic [15:0] mem_req_wdata;
    logic [1:0] mem_req_wstrb;

    logic mem_rsp_valid;
    logic mem_rsp_ready;
    logic [15:0] mem_rsp_rdata;
    logic mem_rsp_last;
    logic mem_rsp_error;

    logic mem_wr_valid;
    logic mem_wr_ready;
    logic [15:0] mem_wr_data;
    logic [1:0] mem_wr_strb;
    logic mem_wr_last;
    logic mem_wr_error;
    logic mem_wr_rsp_valid;
    logic mem_wr_rsp_ready;
    logic mem_wr_rsp_error;

    logic done_valid;
    logic done_error;
    logic [31:0] done_seq;
    logic busy;
    logic [31:0] request_count;
    logic [31:0] read_count;
    logic [31:0] write_count;
    logic [31:0] pixel_count;
    logic [31:0] error_count;

    logic [15:0] mem [0:MEM_WORDS-1];

    logic read_active_q;
    logic [31:0] read_addr_q;
    logic [16:0] read_left_q;
    logic [15:0] read_beat_q;
    logic read_bad_last_q;

    logic write_active_q;
    logic [31:0] write_addr_q;
    logic [16:0] write_left_q;
    logic write_rsp_pending_q;

    logic inject_bad_last_next;
    integer cycle_count;
    integer read_desc_seen;
    integer write_desc_seen;
    integer multi_read_seen;
    integer normal_last_checks;
    logic saw_boundary_first_segment;
    logic saw_boundary_follow_segment;

    render_cmd_mem_engine #(
        .ADDR_W(32),
        .DATA_W(DATA_W),
        .LEN_W(16),
        .SEQ_W(32),
        .WRITE_BURST_ENABLE(1'b1),
        .READ_BURST_ENABLE(1'b1),
        .MAX_READ_BEATS(4),
        .MAX_WRITE_BEATS(4),
        .LINE_BUFFER_PIXELS(32),
        .READ_BOUNDARY_BYTES(4096),
        .WRITE_BOUNDARY_BYTES(4096)
    ) dut (
        .clk,
        .rst_n,
        .desc_valid,
        .desc_ready,
        .desc_seq,
        .desc_op,
        .desc_flags,
        .desc_pixel_fmt,
        .desc_src_addr,
        .desc_dst_addr,
        .desc_width,
        .desc_height,
        .desc_src_stride_bytes(desc_src_stride),
        .desc_dst_stride_bytes(desc_dst_stride),
        .desc_color,
        .desc_alpha,
        .desc_color_key,
        .mem_req_valid,
        .mem_req_ready,
        .mem_req_write,
        .mem_req_addr,
        .mem_req_len,
        .mem_req_wdata,
        .mem_req_wstrb,
        .mem_rsp_valid,
        .mem_rsp_ready,
        .mem_rsp_rdata,
        .mem_rsp_last,
        .mem_rsp_error,
        .mem_wr_valid,
        .mem_wr_ready,
        .mem_wr_data,
        .mem_wr_strb,
        .mem_wr_last,
        .mem_wr_error,
        .mem_wr_rsp_valid,
        .mem_wr_rsp_ready,
        .mem_wr_rsp_error,
        .done_valid,
        .done_error,
        .done_seq,
        .busy,
        .request_count,
        .read_count,
        .write_count,
        .pixel_count,
        .error_count
    );

    // One descriptor may be outstanding at a time.  The deterministic stall
    // patterns exercise VALID/READY stability without relying on randomness.
    assign mem_req_ready = !read_active_q && !write_active_q &&
                           !write_rsp_pending_q &&
                           ((cycle_count % 5) != 2);
    assign mem_rsp_valid = read_active_q && ((cycle_count % 4) != 1);
    assign mem_rsp_rdata = mem[read_addr_q >> 1];
    assign mem_rsp_last  = (read_bad_last_q && (read_beat_q == 0)) ? 1'b1 :
                           (read_left_q == 17'd1);
    assign mem_rsp_error = 1'b0;

    assign mem_wr_ready = write_active_q && ((cycle_count % 3) != 0);
    assign mem_wr_error = 1'b0;
    assign mem_wr_rsp_valid = write_rsp_pending_q;
    assign mem_wr_rsp_error = 1'b0;

    // Testbench model state is also initialized/modified by directed stimulus,
    // so use a plain procedural block rather than the single-driver always_ff
    // construct required for synthesizable RTL.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_active_q <= 1'b0;
            read_addr_q <= '0;
            read_left_q <= '0;
            read_beat_q <= '0;
            read_bad_last_q <= 1'b0;
            write_active_q <= 1'b0;
            write_addr_q <= '0;
            write_left_q <= '0;
            write_rsp_pending_q <= 1'b0;
            inject_bad_last_next <= 1'b0;
            cycle_count <= 0;
            read_desc_seen <= 0;
            write_desc_seen <= 0;
            multi_read_seen <= 0;
            normal_last_checks <= 0;
            saw_boundary_first_segment <= 1'b0;
            saw_boundary_follow_segment <= 1'b0;
        end else begin
            cycle_count <= cycle_count + 1;

            if (write_rsp_pending_q && mem_wr_rsp_ready)
                write_rsp_pending_q <= 1'b0;

            if (mem_req_valid && mem_req_ready) begin
                if (((mem_req_addr % 4096) +
                     (({1'b0, mem_req_len} + 17'd1) * 2)) > 4096)
                    $fatal(1, "descriptor crossed 4 KiB: write=%0b addr=%h len=%0d",
                           mem_req_write, mem_req_addr, mem_req_len);

                if (mem_req_write) begin
                    write_desc_seen <= write_desc_seen + 1;
                    if ((mem_req_wdata !== 16'h0000) ||
                        (mem_req_wstrb !== 2'b00))
                        $fatal(1, "burst write descriptor carried legacy payload");
                    write_active_q <= 1'b1;
                    write_addr_q <= mem_req_addr;
                    write_left_q <= {1'b0, mem_req_len} + 17'd1;
                end else begin
                    read_desc_seen <= read_desc_seen + 1;
                    if (mem_req_len == 0)
                        $fatal(1, "row reader emitted a single-beat descriptor at %h",
                               mem_req_addr);
                    multi_read_seen <= multi_read_seen + 1;
                    if ((mem_req_addr == 32'h0000_0ff8) &&
                        (mem_req_len == 16'd3))
                        saw_boundary_first_segment <= 1'b1;
                    if ((mem_req_addr == 32'h0000_1000) &&
                        (mem_req_len == 16'd3))
                        saw_boundary_follow_segment <= 1'b1;
                    read_active_q <= 1'b1;
                    read_addr_q <= mem_req_addr;
                    read_left_q <= {1'b0, mem_req_len} + 17'd1;
                    read_beat_q <= 16'd0;
                    read_bad_last_q <= inject_bad_last_next;
                    inject_bad_last_next <= 1'b0;
                end
            end

            if (mem_rsp_valid && mem_rsp_ready) begin
                if (!read_bad_last_q) begin
                    if (mem_rsp_last !== (read_left_q == 17'd1))
                        $fatal(1, "memory model rsp_last bookkeeping failed");
                    normal_last_checks <= normal_last_checks + 1;
                end
                if (read_bad_last_q)
                    read_bad_last_q <= 1'b0;
                if (read_left_q == 17'd1) begin
                    read_active_q <= 1'b0;
                    read_left_q <= '0;
                end else begin
                    read_addr_q <= read_addr_q + 32'd2;
                    read_left_q <= read_left_q - 17'd1;
                    read_beat_q <= read_beat_q + 16'd1;
                end
            end

            if (mem_wr_valid && mem_wr_ready) begin
                if (mem_wr_strb !== 2'b11)
                    $fatal(1, "unexpected write strobe %b", mem_wr_strb);
                if (mem_wr_last !== (write_left_q == 17'd1))
                    $fatal(1, "write last mismatch addr=%h left=%0d",
                           write_addr_q, write_left_q);
                if (mem_wr_strb[0])
                    mem[write_addr_q >> 1][7:0] <= mem_wr_data[7:0];
                if (mem_wr_strb[1])
                    mem[write_addr_q >> 1][15:8] <= mem_wr_data[15:8];
                if (write_left_q == 17'd1) begin
                    write_active_q <= 1'b0;
                    write_left_q <= '0;
                    write_rsp_pending_q <= 1'b1;
                end else begin
                    write_addr_q <= write_addr_q + 32'd2;
                    write_left_q <= write_left_q - 17'd1;
                end
            end
        end
    end

    task automatic send_desc(
        input logic [2:0]  op,
        input logic [31:0] src,
        input logic [31:0] dst,
        input logic [15:0] width,
        input logic [15:0] height,
        input logic [15:0] src_stride,
        input logic [15:0] dst_stride,
        input logic [15:0] key
    );
        begin
            @(negedge clk);
            desc_seq = desc_seq + 32'd1;
            desc_op = op;
            desc_flags = '0;
            desc_pixel_fmt = 2'd0;
            desc_src_addr = src;
            desc_dst_addr = dst;
            desc_width = width;
            desc_height = height;
            desc_src_stride = src_stride;
            desc_dst_stride = dst_stride;
            desc_color = '0;
            desc_alpha = 8'd128;
            desc_color_key = key;
            desc_valid = 1'b1;
            while (!desc_ready)
                @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            desc_valid = 1'b0;
        end
    endtask

    task automatic wait_done(input logic expect_error);
        integer guard;
        begin
            guard = 0;
            while (!done_valid && (guard < 10000)) begin
                @(posedge clk);
                guard = guard + 1;
            end
            if (guard >= 10000)
                $fatal(1, "read-burst engine timeout");
            if (done_error !== expect_error)
                $fatal(1, "done_error=%0b expected=%0b seq=%0d",
                       done_error, expect_error, done_seq);
            if (done_seq !== desc_seq)
                $fatal(1, "done_seq=%0d expected=%0d", done_seq, desc_seq);
            @(negedge clk);
        end
    endtask

    task automatic check_word(
        input integer byte_addr,
        input logic [15:0] expected
    );
        begin
            if (mem[byte_addr >> 1] !== expected)
                $fatal(1, "mem[%h]=%h expected=%h", byte_addr,
                       mem[byte_addr >> 1], expected);
        end
    endtask

    integer base_read_desc;
    integer base_write_desc;
    integer base_requests;
    integer base_pixels;
    integer base_errors;

    initial begin
        desc_valid = 1'b0;
        desc_seq = '0;
        desc_op = '0;
        desc_flags = '0;
        desc_pixel_fmt = '0;
        desc_src_addr = '0;
        desc_dst_addr = '0;
        desc_width = '0;
        desc_height = '0;
        desc_src_stride = '0;
        desc_dst_stride = '0;
        desc_color = '0;
        desc_alpha = '0;
        desc_color_key = '0;

        for (integer k = 0; k < MEM_WORDS; k = k + 1)
            mem[k] = 16'h0000;

        // Two 10-pixel source rows.  Row zero begins at 0x0ff8 and therefore
        // must be described as 4 + 4 + 2 beats, with the first descriptor
        // ending exactly at the 4 KiB boundary.
        for (integer k = 0; k < 10; k = k + 1) begin
            mem[(16'h0ff8 >> 1) + k] = 16'h1100 + k;
            mem[(16'h1018 >> 1) + k] = 16'h2200 + k;
            mem[(16'h1800 >> 1) + k] = 16'hdead;
            mem[(16'h1840 >> 1) + k] = 16'hbeef;
        end

        // COLOR_KEY input/output rows.  Key hits must preserve destination;
        // misses must copy the source pixel into the line writeback.
        mem[16'h2200 >> 1] = 16'h07e0;
        mem[16'h2202 >> 1] = 16'h1111;
        mem[16'h2204 >> 1] = 16'h07e0;
        mem[16'h2206 >> 1] = 16'h2222;
        mem[16'h2208 >> 1] = 16'h3333;
        mem[16'h220a >> 1] = 16'h07e0;
        for (integer k = 0; k < 6; k = k + 1)
            mem[(16'h2400 >> 1) + k] = 16'ha000 + k;

        // Data used only by the malformed-rsp_last case.
        for (integer k = 0; k < 4; k = k + 1)
            mem[(16'h2ff8 >> 1) + k] = 16'h5000 + k;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (3) @(posedge clk);

        base_read_desc = read_desc_seen;
        base_write_desc = write_desc_seen;
        base_requests = request_count;
        base_pixels = pixel_count;
        send_desc(OP_BLOCK_COPY, 32'h0000_0ff8, 32'h0000_1800,
                  16'd10, 16'd2, 16'h0020, 16'h0040, 16'h0000);
        wait_done(1'b0);

        for (integer k = 0; k < 10; k = k + 1) begin
            check_word(16'h1800 + (k * 2), 16'h1100 + k);
            check_word(16'h1840 + (k * 2), 16'h2200 + k);
        end
        if ((read_desc_seen - base_read_desc) != 6)
            $fatal(1, "copy read descriptor count=%0d expected=6",
                   read_desc_seen - base_read_desc);
        if ((write_desc_seen - base_write_desc) != 6)
            $fatal(1, "copy write descriptor count=%0d expected=6",
                   write_desc_seen - base_write_desc);
        if ((request_count - base_requests) != 12)
            $fatal(1, "copy request_count delta=%0d expected=12",
                   request_count - base_requests);
        if ((pixel_count - base_pixels) != 20)
            $fatal(1, "copy pixel_count delta=%0d expected=20",
                   pixel_count - base_pixels);
        if (!saw_boundary_first_segment || !saw_boundary_follow_segment)
            $fatal(1, "4 KiB read split was not observed");

        base_read_desc = read_desc_seen;
        base_write_desc = write_desc_seen;
        base_requests = request_count;
        base_pixels = pixel_count;
        send_desc(OP_COLOR_KEY, 32'h0000_2200, 32'h0000_2400,
                  16'd6, 16'd1, 16'h000c, 16'h000c, 16'h07e0);
        wait_done(1'b0);

        check_word(16'h2400, 16'ha000);
        check_word(16'h2402, 16'h1111);
        check_word(16'h2404, 16'ha002);
        check_word(16'h2406, 16'h2222);
        check_word(16'h2408, 16'h3333);
        check_word(16'h240a, 16'ha005);
        if ((read_desc_seen - base_read_desc) != 4)
            $fatal(1, "color-key read descriptor count=%0d expected=4",
                   read_desc_seen - base_read_desc);
        if ((write_desc_seen - base_write_desc) != 2)
            $fatal(1, "color-key write descriptor count=%0d expected=2",
                   write_desc_seen - base_write_desc);
        if ((request_count - base_requests) != 6)
            $fatal(1, "color-key request_count delta=%0d expected=6",
                   request_count - base_requests);
        if ((pixel_count - base_pixels) != 6)
            $fatal(1, "color-key pixel_count delta=%0d expected=6",
                   pixel_count - base_pixels);

        // rsp_last is deliberately asserted on beat zero of a four-beat
        // descriptor.  The engine must reject the protocol violation rather
        // than treating a partial row as complete.
        base_errors = error_count;
        inject_bad_last_next = 1'b1;
        send_desc(OP_BLOCK_COPY, 32'h0000_2ff8, 32'h0000_3200,
                  16'd4, 16'd1, 16'h0008, 16'h0008, 16'h0000);
        wait_done(1'b1);
        if ((error_count - base_errors) != 1)
            $fatal(1, "rsp_last violation did not increment error_count");

        if (multi_read_seen < 11 || normal_last_checks == 0)
            $fatal(1, "insufficient read-burst/rsp_last coverage");

        $display("TB_RENDER_CMD_MEM_ENGINE_READ_BURST_PASS reads=%0d writes=%0d pixels=%0d errors=%0d",
                 read_desc_seen, write_desc_seen, pixel_count, error_count);
        $finish;
    end

endmodule
