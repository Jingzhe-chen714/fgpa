`timescale 1ns/1ps

// Self-checking smoke/regression test for the command and memory boundary.
// It intentionally applies back-pressure to both request and response paths;
// no vendor memory/clocking primitive is required.
module tb_cmd_mem;
    logic clk = 1'b0;
    always #5 clk = ~clk;

    logic rst_n = 1'b0;

    // ------------------------------------------------------------------ FIFO
    logic        f_in_valid, f_in_ready;
    logic [255:0] f_in_data;
    logic        f_out_valid, f_out_ready;
    logic [255:0] f_out_data;
    logic [1:0]  f_count;
    logic        f_full, f_empty, f_drop_event;
    logic [31:0] f_push_count, f_pop_count, f_drop_count;

    render_cmd_fifo #(.DEPTH(2)) u_fifo (
        .clk, .rst_n,
        .in_valid(f_in_valid), .in_ready(f_in_ready), .in_data(f_in_data),
        .out_valid(f_out_valid), .out_ready(f_out_ready), .out_data(f_out_data),
        .fifo_count(f_count), .full(f_full), .empty(f_empty),
        .drop_event(f_drop_event), .push_count(f_push_count),
        .pop_count(f_pop_count), .drop_count(f_drop_count)
    );

    // ---------------------------------------------------------- parser/engine
    logic         cmd_valid, cmd_ready;
    logic [255:0] cmd_data;
    logic         desc_valid, desc_ready;
    logic [255:0] desc_raw;
    logic [31:0]  desc_seq;
    logic [2:0]   desc_op;
    logic [7:0]   desc_flags;
    logic [1:0]   desc_pixel_fmt;
    logic [31:0]  desc_src_addr, desc_dst_addr;
    logic [15:0]  desc_width, desc_height;
    logic [15:0]  desc_src_stride, desc_dst_stride;
    logic [31:0]  desc_color;
    logic [7:0]   desc_alpha;
    logic [15:0]  desc_color_key;
    logic         accept_event, parser_error_valid;
    logic [3:0]   parser_error_code;
    logic [31:0]  parser_error_seq;
    logic [31:0]  accepted_count, completed_count, memory_error_count,
                  dropped_count;
    logic         parser_busy;

    logic         eng_done_valid, eng_done_error;
    logic [31:0]  eng_done_seq;
    logic         eng_busy;
    logic [31:0]  request_count, read_count, write_count, pixel_count,
                  engine_error_count;

    render_cmd_parser u_parser (
        .clk, .rst_n,
        .cmd_valid, .cmd_ready, .cmd_data,
        .desc_valid, .desc_ready, .desc_raw, .desc_seq, .desc_op,
        .desc_flags, .desc_pixel_fmt, .desc_src_addr, .desc_dst_addr,
        .desc_width, .desc_height, .desc_src_stride_bytes(desc_src_stride),
        .desc_dst_stride_bytes(desc_dst_stride), .desc_color,
        .desc_alpha, .desc_color_key,
        .accept_event, .error_valid(parser_error_valid),
        .error_code(parser_error_code), .error_seq(parser_error_seq),
        .done_valid(eng_done_valid), .done_error(eng_done_error),
        .accepted_count, .completed_count, .memory_error_count,
        .dropped_count, .busy(parser_busy)
    );

    logic         mem_req_valid, mem_req_ready, mem_req_write;
    logic [31:0]  mem_req_addr;
    logic [15:0]  mem_req_len;
    logic [15:0]  mem_req_wdata;
    logic [1:0]   mem_req_wstrb;
    logic         mem_rsp_valid, mem_rsp_ready;
    logic         model_rsp_valid;
    logic [15:0]  mem_rsp_rdata;
    logic         mem_rsp_last, mem_rsp_error;
    logic         mem_wr_valid, mem_wr_last;
    logic [15:0]  mem_wr_data;
    logic [1:0]   mem_wr_strb;
    logic         mem_wr_rsp_ready;

    render_cmd_mem_engine u_engine (
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
        // Legacy single-beat mode never activates this channel.  Connect it
        // explicitly so the compatibility regression also checks that the
        // new burst outputs remain inactive.
        .mem_wr_valid, .mem_wr_ready(1'b0), .mem_wr_data, .mem_wr_strb,
        .mem_wr_last, .mem_wr_error(1'b0),
        .mem_wr_rsp_valid(1'b0), .mem_wr_rsp_ready,
        .mem_wr_rsp_error(1'b0),
        .done_valid(eng_done_valid),
        .done_error(eng_done_error), .done_seq(eng_done_seq), .busy(eng_busy),
        .request_count, .read_count, .write_count, .pixel_count,
        .error_count(engine_error_count)
    );

    always @(posedge clk) begin
        if (rst_n && mem_wr_valid)
            $fatal(1, "legacy engine unexpectedly activated burst write data");
    end

    logic req_gate, rsp_gate;
    logic model_req_valid, model_req_ready, model_rsp_ready;
    assign model_req_valid = mem_req_valid && req_gate;
    assign mem_req_ready = model_req_ready && req_gate;
    // Gate both sides of the response handshake.  The engine sees no valid
    // beat while the testbench is stalling, and the model therefore keeps its
    // pending beat until a real handshake occurs.
    assign mem_rsp_valid = model_rsp_valid && rsp_gate;
    assign model_rsp_ready = mem_rsp_ready && rsp_gate;

    render_mem_model #(.MEM_BYTES(4096), .READ_LATENCY(2)) u_mem (
        .clk, .rst_n,
        .req_valid(model_req_valid), .req_ready(model_req_ready),
        .req_write(mem_req_write), .req_addr(mem_req_addr),
        .req_len(mem_req_len), .req_wdata(mem_req_wdata),
        .req_wstrb(mem_req_wstrb),
        .rsp_valid(model_rsp_valid), .rsp_ready(model_rsp_ready),
        .rsp_rdata(mem_rsp_rdata), .rsp_last(mem_rsp_last),
        .rsp_error(mem_rsp_error), .read_count(), .write_count(),
        .error_count()
    );

    integer cycle_counter;
    always @(posedge clk) begin
        if (!rst_n) begin
            cycle_counter <= 0;
            req_gate <= 1'b1;
            rsp_gate <= 1'b1;
        end else begin
            cycle_counter <= cycle_counter + 1;
            // Deterministic stalls: request and response channels each see
            // several blocked cycles during every long rectangle.
            req_gate <= ((cycle_counter % 5) != 1);
            rsp_gate <= ((cycle_counter % 7) != 3);
        end
    end

    function automatic [255:0] make_cmd(
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
        reg [255:0] c;
        begin
            c = '0;
            c[2:0] = op;
            c[12:11] = 2'd0;       // RGB565
            c[47:16] = src;
            c[79:48] = dst;
            c[95:80] = w;
            c[111:96] = h;
            c[127:112] = ss;
            c[143:128] = ds;
            c[175:144] = color;
            c[183:176] = alpha;
            c[199:184] = key;
            make_cmd = c;
        end
    endfunction

    task automatic send_command(input [255:0] c);
        begin
            cmd_data = c;
            cmd_valid = 1'b1;
            while (1) begin
                @(posedge clk);
                if (cmd_ready)
                    break;
            end
            #1;
            cmd_valid = 1'b0;
        end
    endtask

    task automatic wait_done(input bit expect_error);
        integer guard;
        begin
            guard = 0;
            while (!eng_done_valid && (guard < 2000)) begin
                @(posedge clk);
                guard = guard + 1;
            end
            if (guard >= 2000)
                $fatal(1, "timeout waiting for command completion");
            if (eng_done_error !== expect_error)
                $fatal(1, "unexpected done_error=%0d expected=%0d",
                       eng_done_error, expect_error);
            @(posedge clk);
        end
    endtask

    task automatic check_word(input integer addr, input [15:0] expected);
        begin
            if (u_mem.mem[addr/2] !== expected)
                $fatal(1, "memory[%0h] = %0h, expected %0h",
                       addr, u_mem.mem[addr/2], expected);
        end
    endtask

    integer i;
    initial begin
        f_in_valid = 1'b0;
        f_in_data = '0;
        f_out_ready = 1'b0;
        cmd_valid = 1'b0;
        cmd_data = '0;

        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        // FIFO ordering and full/drop behavior.
        f_in_data = 256'h1;
        f_in_valid = 1'b1;
        @(posedge clk);
        #1;
        f_in_data = 256'h2;
        @(posedge clk);
        #1;
        f_in_data = 256'h3;
        @(posedge clk);
        #1;
        if (!f_drop_event || f_drop_count != 32'd1)
            $fatal(1, "FIFO failed to report a dropped full push");
        f_in_valid = 1'b0;
        f_out_ready = 1'b1;
        @(negedge clk);
        if (f_out_data !== 256'h1) begin
            $fatal(1, "FIFO order mismatch (first)");
        end
        @(posedge clk);
        @(negedge clk);
        if (f_out_data !== 256'h2) $fatal(1, "FIFO order mismatch (second)");
        @(posedge clk);
        #1;
        f_out_ready = 1'b0;
        if (f_count != 0) $fatal(1, "FIFO did not empty");

        // Fill: 3x2 pixels, stride has two bytes of padding per row.
        send_command(make_cmd(3'd1, 0, 32'h0100, 3, 2, 0, 8,
                               32'h0000_F800, 8'hFF, 0));
        wait_done(1'b0);
        check_word(16'h0100, 16'hF800);
        check_word(16'h0102, 16'hF800);
        check_word(16'h0104, 16'hF800);
        check_word(16'h0108, 16'hF800);
        check_word(16'h010A, 16'hF800);
        check_word(16'h010C, 16'hF800);

        // Copy: source rows at 0x200, destination rows at 0x300.
        u_mem.mem[16'h0200/2] = 16'h001F;
        u_mem.mem[16'h0202/2] = 16'h07E0;
        u_mem.mem[16'h0204/2] = 16'hF800;
        u_mem.mem[16'h0208/2] = 16'hFFFF;
        u_mem.mem[16'h020A/2] = 16'h8410;
        u_mem.mem[16'h020C/2] = 16'h0000;
        send_command(make_cmd(3'd2, 32'h0200, 32'h0300, 3, 2, 8, 8,
                               0, 0, 0));
        wait_done(1'b0);
        check_word(16'h0300, 16'h001F);
        check_word(16'h0302, 16'h07E0);
        check_word(16'h0304, 16'hF800);
        check_word(16'h0308, 16'hFFFF);
        check_word(16'h030A, 16'h8410);
        check_word(16'h030C, 16'h0000);

        // COLOR_KEY: first source pixel hits the key and must leave the
        // destination untouched; the second pixel is copied.
        u_mem.mem[16'h0700/2] = 16'h1234;
        u_mem.mem[16'h0702/2] = 16'hABCD;
        u_mem.mem[16'h0800/2] = 16'h5555;
        u_mem.mem[16'h0802/2] = 16'h0000;
        send_command(make_cmd(3'd4, 32'h0700, 32'h0800, 2, 1, 4, 4,
                               0, 0, 16'h1234));
        wait_done(1'b0);
        check_word(16'h0800, 16'h5555);
        check_word(16'h0802, 16'hABCD);

        // ALPHA_BLEND: 50% red over blue.  The reference round-to-nearest
        // rule in render_cmd_mem_engine gives RGB565 0x800f.
        u_mem.mem[16'h0500/2] = 16'hF800;
        u_mem.mem[16'h0600/2] = 16'h001F;
        send_command(make_cmd(3'd3, 32'h0500, 32'h0600, 1, 1, 2, 2,
                               0, 8'h80, 0));
        wait_done(1'b0);
        check_word(16'h0600, 16'h800F);

        // An out-of-range source read is returned as a memory error by the
        // behavioral model and must reach the command completion counters.
        send_command(make_cmd(3'd2, 32'h1000, 32'h0900, 1, 1, 2, 2,
                               0, 0, 0));
        wait_done(1'b1);

        // Invalid zero-width command is consumed by parser and reported.
        send_command(make_cmd(3'd1, 0, 32'h0400, 0, 1, 0, 2,
                               32'hFFFF, 0, 0));
        i = 0;
        while (!parser_error_valid && (i < 20)) begin
            @(posedge clk);
            i = i + 1;
        end
        if (!parser_error_valid || parser_error_code != 4'd3)
            $fatal(1, "parser failed to flag zero-width command");

        if (accepted_count != 32'd6 || dropped_count != 32'd1 ||
            completed_count != 32'd5 || memory_error_count != 32'd1)
            $fatal(1, "unexpected parser counters accepted=%0d dropped=%0d completed=%0d memerr=%0d",
                   accepted_count, dropped_count, completed_count,
                   memory_error_count);

        $display("tb_cmd_mem PASS: req=%0d read=%0d write=%0d pixels=%0d",
                 request_count, read_count, write_count, pixel_count);
        $finish;
    end
endmodule
