`timescale 1ns/1ps

// Minimal self-checking test for render_cmd_mem_engine's optional line
// write-back path.  The memory model deliberately exposes the same split
// descriptor/data channels used by c2_mem_arbiter_2m_owner: a write request is
// accepted first, then write beats are consumed until mem_wr_last.
module tb_render_cmd_mem_engine_burst;
    localparam int DATA_W = 16;
    localparam int MEM_WORDS = 4096;

    logic clk = 1'b0;
    always #5 clk = ~clk;
    logic rst_n = 1'b0;

    logic desc_valid, desc_ready;
    logic [31:0] desc_seq;
    logic [2:0] desc_op;
    logic [7:0] desc_flags;
    logic [1:0] desc_pixel_fmt;
    logic [31:0] desc_src_addr, desc_dst_addr;
    logic [15:0] desc_width, desc_height;
    logic [15:0] desc_src_stride, desc_dst_stride;
    logic [31:0] desc_color;
    logic [7:0] desc_alpha;
    logic [15:0] desc_color_key;

    logic mem_req_valid, mem_req_ready, mem_req_write;
    logic [31:0] mem_req_addr;
    logic [15:0] mem_req_len;
    logic [15:0] mem_req_wdata;
    logic [1:0] mem_req_wstrb;
    logic mem_rsp_valid, mem_rsp_ready;
    logic [15:0] mem_rsp_rdata;
    logic mem_rsp_last, mem_rsp_error;
    logic mem_wr_valid, mem_wr_ready;
    logic [15:0] mem_wr_data;
    logic [1:0] mem_wr_strb;
    logic mem_wr_last, mem_wr_error;
    logic mem_wr_rsp_valid, mem_wr_rsp_ready, mem_wr_rsp_error;

    logic done_valid, done_error;
    logic [31:0] done_seq;
    logic busy;
    logic [31:0] request_count, read_count, write_count, pixel_count,
                 error_count;

    logic [15:0] mem [0:MEM_WORDS-1];
    logic read_pending;
    logic [15:0] read_data_q;
    logic write_active;
    logic write_rsp_pending;
    logic write_rsp_error_q;
    logic force_next_rsp_error;
    logic [31:0] write_addr_q;
    logic [16:0] write_left_q;
    integer cycle_counter;
    integer req_seen;
    integer wr_seen;

    assign mem_req_ready = !read_pending && !write_active &&
                           !write_rsp_pending &&
                           ((cycle_counter % 4) != 1);
    assign mem_wr_ready  = write_active && ((cycle_counter % 3) != 0);
    assign mem_rsp_valid = read_pending;
    assign mem_rsp_rdata = read_data_q;
    assign mem_rsp_last  = 1'b1;
    assign mem_rsp_error = 1'b0;
    assign mem_wr_error  = 1'b0;
    assign mem_wr_rsp_valid = write_rsp_pending;
    assign mem_wr_rsp_error = write_rsp_error_q;

    render_cmd_mem_engine #(
        .ADDR_W(32), .DATA_W(DATA_W), .LEN_W(16), .SEQ_W(32),
        .WRITE_BURST_ENABLE(1'b1), .MAX_WRITE_BEATS(2),
        .LINE_BUFFER_PIXELS(32)
    ) dut (
        .clk, .rst_n,
        .desc_valid, .desc_ready, .desc_seq, .desc_op, .desc_flags,
        .desc_pixel_fmt, .desc_src_addr, .desc_dst_addr, .desc_width,
        .desc_height, .desc_src_stride_bytes(desc_src_stride),
        .desc_dst_stride_bytes(desc_dst_stride), .desc_color, .desc_alpha,
        .desc_color_key,
        .mem_req_valid, .mem_req_ready, .mem_req_write, .mem_req_addr,
        .mem_req_len, .mem_req_wdata, .mem_req_wstrb,
        .mem_rsp_valid, .mem_rsp_ready, .mem_rsp_rdata, .mem_rsp_last,
        .mem_rsp_error,
        .mem_wr_valid, .mem_wr_ready, .mem_wr_data, .mem_wr_strb,
        .mem_wr_last, .mem_wr_error,
        .mem_wr_rsp_valid, .mem_wr_rsp_ready, .mem_wr_rsp_error,
        .done_valid, .done_error, .done_seq, .busy,
        .request_count, .read_count, .write_count, .pixel_count,
        .error_count
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_pending <= 1'b0;
            read_data_q <= '0;
            write_active <= 1'b0;
            write_rsp_pending <= 1'b0;
            write_rsp_error_q <= 1'b0;
            write_addr_q <= '0;
            write_left_q <= '0;
            req_seen <= 0;
            wr_seen <= 0;
            cycle_counter <= 0;
        end else begin
            cycle_counter <= cycle_counter + 1;
            if (read_pending && mem_rsp_ready)
                read_pending <= 1'b0;
            if (write_rsp_pending && mem_wr_rsp_ready) begin
                write_rsp_pending <= 1'b0;
                write_rsp_error_q <= 1'b0;
            end

            if (mem_req_valid && mem_req_ready) begin
                req_seen <= req_seen + 1;
                if (mem_req_write) begin
                    if (((mem_req_addr % 4096) +
                         ((mem_req_len + 1) * 2)) > 4096)
                        $fatal(1, "write descriptor crossed 4 KiB boundary addr=%h len=%0d",
                               mem_req_addr, mem_req_len);
                    write_active <= 1'b1;
                    write_addr_q <= mem_req_addr;
                    write_left_q <= {1'b0, mem_req_len} + 1'b1;
                end else begin
                    read_pending <= 1'b1;
                    read_data_q <= mem[mem_req_addr / 2];
                end
            end

            if (mem_wr_valid && mem_wr_ready) begin
                wr_seen <= wr_seen + 1;
                if (mem_wr_strb[0])
                    mem[write_addr_q / 2][7:0] <= mem_wr_data[7:0];
                if (mem_wr_strb[1])
                    mem[write_addr_q / 2][15:8] <= mem_wr_data[15:8];
                if (mem_wr_last || (write_left_q == 1)) begin
                    write_active <= 1'b0;
                    write_left_q <= '0;
                    write_rsp_pending <= 1'b1;
                    write_rsp_error_q <= force_next_rsp_error;
                end else begin
                    write_addr_q <= write_addr_q + 2;
                    write_left_q <= write_left_q - 1'b1;
                end
            end
        end
    end

    task automatic send_desc(
        input [2:0] op,
        input [31:0] src,
        input [31:0] dst,
        input [15:0] w,
        input [15:0] h,
        input [15:0] ss,
        input [15:0] ds,
        input [31:0] color,
        input [7:0] alpha,
        input [15:0] key
    );
        begin
            @(negedge clk);
            desc_seq = desc_seq + 1'b1;
            desc_op = op;
            desc_flags = '0;
            desc_pixel_fmt = 2'd0;
            desc_src_addr = src;
            desc_dst_addr = dst;
            desc_width = w;
            desc_height = h;
            desc_src_stride = ss;
            desc_dst_stride = ds;
            desc_color = color;
            desc_alpha = alpha;
            desc_color_key = key;
            desc_valid = 1'b1;
            while (!desc_ready)
                @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            desc_valid = 1'b0;
        end
    endtask

    task automatic wait_done;
        integer guard;
        begin
            guard = 0;
            while (!done_valid && guard < 5000) begin
                @(posedge clk);
                guard = guard + 1;
            end
            if (guard >= 5000)
                $fatal(1, "burst engine timeout");
            if (done_error)
                $fatal(1, "burst engine reported error");
            @(posedge clk);
        end
    endtask

    task automatic wait_done_error;
        integer guard;
        begin
            guard = 0;
            while (!done_valid && guard < 5000) begin
                @(posedge clk);
                guard = guard + 1;
            end
            if (guard >= 5000 || !done_error)
                $fatal(1, "late write-response error was not reported");
            @(posedge clk);
        end
    endtask

    task automatic check_word(input integer byte_addr, input [15:0] expected);
        begin
            if (mem[byte_addr / 2] !== expected)
                $fatal(1, "mem[%0h]=%0h expected=%0h", byte_addr,
                       mem[byte_addr / 2], expected);
        end
    endtask

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
        force_next_rsp_error = 1'b0;
        for (integer k = 0; k < MEM_WORDS; k = k + 1)
            mem[k] = 16'h0000;

        // Seed source and destination values used by copy/key tests.
        mem[16'h0200/2] = 16'h001F;
        mem[16'h0202/2] = 16'h07E0;
        mem[16'h0204/2] = 16'hF800;
        mem[16'h0300/2] = 16'hAAAA;
        mem[16'h0302/2] = 16'hBBBB;
        mem[16'h0304/2] = 16'hCCCC;
        mem[16'h0400/2] = 16'h1234;
        mem[16'h0402/2] = 16'hABCD;
        mem[16'h0500/2] = 16'h5555;
        mem[16'h0502/2] = 16'h0000;
        mem[16'h0600/2] = 16'hF800;
        mem[16'h0700/2] = 16'h001F;

        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        // Width 5 with a two-beat limit forces three descriptors per row.
        send_desc(3'd1, 0, 32'h0100, 5, 2, 0, 12,
                  32'h0000_F81F, 8'hFF, 0);
        wait_done();
        for (integer k = 0; k < 5; k = k + 1) begin
            check_word(16'h0100 + 2*k, 16'hF81F);
            check_word(16'h0100 + 12 + 2*k, 16'hF81F);
        end

        send_desc(3'd2, 32'h0200, 32'h0300, 3, 1, 6, 6,
                  0, 0, 0);
        wait_done();
        check_word(16'h0300, 16'h001F);
        check_word(16'h0302, 16'h07E0);
        check_word(16'h0304, 16'hF800);

        // COLOR_KEY must read back the destination for the key hit before
        // writing the complete line, preserving 0x5555 at the first pixel.
        send_desc(3'd4, 32'h0400, 32'h0500, 2, 1, 4, 4,
                  0, 0, 16'h1234);
        wait_done();
        check_word(16'h0500, 16'h5555);
        check_word(16'h0502, 16'hABCD);

        send_desc(3'd3, 32'h0600, 32'h0700, 1, 1, 2, 2,
                  0, 8'h80, 0);
        wait_done();
        check_word(16'h0700, 16'h800F);

        // Starting one beat before 0x1000 forces the write planner to emit a
        // one-beat descriptor followed by a two-beat descriptor.  The monitor
        // above rejects any abstract burst that crosses the AXI 4 KiB rule.
        send_desc(3'd1, 0, 32'h0000_0FFE, 3, 1, 0, 6,
                  32'h0000_07E0, 8'hFF, 0);
        wait_done();
        check_word(16'h0FFE, 16'h07E0);
        check_word(16'h1000, 16'h07E0);
        check_word(16'h1002, 16'h07E0);

        if (error_count != 0 || wr_seen < 9)
            $fatal(1, "unexpected counters errors=%0d wr_beats=%0d",
                   error_count, wr_seen);

        // The command must wait beyond the final W beat for the controller's
        // later completion response.  Injecting an error only on that response
        // proves it reaches done_error and is not reported as success early.
        force_next_rsp_error = 1'b1;
        send_desc(3'd1, 0, 32'h0000_1200, 1, 1, 0, 2,
                  32'h0000_FFFF, 8'hFF, 0);
        wait_done_error();
        if (error_count != 1)
            $fatal(1, "late write response did not increment error counter");

        $display("TB_RENDER_CMD_MEM_ENGINE_BURST_PASS req=%0d reads=%0d writes=%0d pixels=%0d beats=%0d",
                 request_count, read_count, write_count, pixel_count, wr_seen);
        $finish;
    end
endmodule
