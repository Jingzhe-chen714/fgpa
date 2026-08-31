`timescale 1ns/1ps

// RGB565 descriptor-entry regression. Every used byte stride must be even,
// otherwise row zero could succeed before a later row becomes unaligned.
// Exercise the parser and the engine's parser-bypass guard independently.
// All odd-stride cases have two rows and stride >= width*2, so only the new
// alignment rule can reject them. No memory VALID may be emitted on rejection.
module tb_c2_stride_alignment;
    localparam logic [2:0] OP_NOP         = 3'd0;
    localparam logic [2:0] OP_SOLID_FILL  = 3'd1;
    localparam logic [2:0] OP_BLOCK_COPY  = 3'd2;
    localparam logic [2:0] OP_ALPHA_BLEND = 3'd3;
    localparam logic [2:0] OP_COLOR_KEY   = 3'd4;
    localparam logic [3:0] ERR_BAD_STRIDE = 4'd4;

    logic clk = 1'b0;
    always #5 clk = ~clk;
    logic rst_n = 1'b0;

    logic cmd_valid, cmd_ready;
    logic [255:0] cmd_data;
    logic parser_desc_valid, parser_desc_ready;
    logic [255:0] parser_desc_raw;
    logic [31:0] parser_desc_seq;
    logic parser_accept, parser_error_valid;
    logic [3:0] parser_error_code;
    logic [31:0] parser_error_seq;
    logic [31:0] parser_accepted_count, parser_completed_count;
    logic [31:0] parser_memory_error_count, parser_dropped_count;
    logic parser_busy;

    logic direct_mode, direct_valid;
    logic [255:0] direct_data;
    logic [31:0] direct_seq;
    logic engine_desc_valid, engine_desc_ready;
    logic [255:0] engine_desc_data;
    logic [31:0] engine_desc_seq;

    logic mem_req_valid, mem_req_ready, mem_req_write;
    logic [31:0] mem_req_addr;
    logic [15:0] mem_req_len, mem_req_wdata;
    logic [1:0] mem_req_wstrb;
    logic mem_rsp_valid, mem_rsp_ready, mem_rsp_last, mem_rsp_error;
    logic [15:0] mem_rsp_rdata;
    logic mem_wr_valid, mem_wr_ready, mem_wr_last, mem_wr_error;
    logic [15:0] mem_wr_data;
    logic [1:0] mem_wr_strb;
    logic mem_wr_rsp_valid, mem_wr_rsp_ready, mem_wr_rsp_error;

    logic engine_done_valid, engine_done_error, engine_busy;
    logic [31:0] engine_done_seq;
    logic [31:0] request_count, read_count, write_count, pixel_count;
    logic [31:0] engine_error_count;
    logic [31:0] model_descriptor_count, model_error_count;

    logic no_mem_expected;
    integer parser_desc_seen;
    integer parser_error_seen;
    integer engine_done_seen;
    integer parser_rejected;
    integer direct_rejected;
    integer allowed_commands;

    assign engine_desc_valid = direct_mode ? direct_valid : parser_desc_valid;
    assign engine_desc_data = direct_mode ? direct_data : parser_desc_raw;
    assign engine_desc_seq = direct_mode ? direct_seq : parser_desc_seq;
    assign parser_desc_ready = !direct_mode && engine_desc_ready;

    render_cmd_parser u_parser (
        .clk, .rst_n, .cmd_valid, .cmd_ready, .cmd_data,
        .desc_valid(parser_desc_valid), .desc_ready(parser_desc_ready),
        .desc_raw(parser_desc_raw), .desc_seq(parser_desc_seq),
        .desc_op(), .desc_flags(), .desc_pixel_fmt(), .desc_src_addr(),
        .desc_dst_addr(), .desc_width(), .desc_height(),
        .desc_src_stride_bytes(), .desc_dst_stride_bytes(), .desc_color(),
        .desc_alpha(), .desc_color_key(), .accept_event(parser_accept),
        .error_valid(parser_error_valid), .error_code(parser_error_code),
        .error_seq(parser_error_seq),
        .done_valid(engine_done_valid && !direct_mode),
        .done_error(engine_done_error),
        .accepted_count(parser_accepted_count),
        .completed_count(parser_completed_count),
        .memory_error_count(parser_memory_error_count),
        .dropped_count(parser_dropped_count), .busy(parser_busy)
    );

    render_cmd_mem_engine #(
        .WRITE_BURST_ENABLE(1'b1), .READ_BURST_ENABLE(1'b1),
        .MAX_READ_BEATS(4), .MAX_WRITE_BEATS(4), .LINE_BUFFER_PIXELS(16)
    ) u_engine (
        .clk, .rst_n,
        .desc_valid(engine_desc_valid), .desc_ready(engine_desc_ready),
        .desc_seq(engine_desc_seq), .desc_op(engine_desc_data[2:0]),
        .desc_flags(engine_desc_data[10:3]),
        .desc_pixel_fmt(engine_desc_data[12:11]),
        .desc_src_addr(engine_desc_data[47:16]),
        .desc_dst_addr(engine_desc_data[79:48]),
        .desc_width(engine_desc_data[95:80]),
        .desc_height(engine_desc_data[111:96]),
        .desc_src_stride_bytes(engine_desc_data[127:112]),
        .desc_dst_stride_bytes(engine_desc_data[143:128]),
        .desc_color(engine_desc_data[175:144]),
        .desc_alpha(engine_desc_data[183:176]),
        .desc_color_key(engine_desc_data[199:184]),
        .mem_req_valid, .mem_req_ready, .mem_req_write, .mem_req_addr,
        .mem_req_len, .mem_req_wdata, .mem_req_wstrb,
        .mem_rsp_valid, .mem_rsp_ready, .mem_rsp_rdata, .mem_rsp_last,
        .mem_rsp_error, .mem_wr_valid, .mem_wr_ready, .mem_wr_data,
        .mem_wr_strb, .mem_wr_last, .mem_wr_error,
        .mem_wr_rsp_valid, .mem_wr_rsp_ready, .mem_wr_rsp_error,
        .done_valid(engine_done_valid), .done_error(engine_done_error),
        .done_seq(engine_done_seq), .busy(engine_busy),
        .request_count, .read_count, .write_count, .pixel_count,
        .error_count(engine_error_count)
    );

    render_owner_mem_model #(.MEM_BYTES(4096), .READ_LATENCY(1)) u_mem (
        .clk, .rst_n,
        .req_valid(mem_req_valid), .req_ready(mem_req_ready),
        .req_write(mem_req_write), .req_addr(mem_req_addr),
        .req_len(mem_req_len), .req_wdata(mem_req_wdata),
        .req_wstrb(mem_req_wstrb),
        .wr_valid(mem_wr_valid), .wr_ready(mem_wr_ready),
        .wr_data(mem_wr_data), .wr_strb(mem_wr_strb), .wr_last(mem_wr_last),
        .wr_error(mem_wr_error), .wr_rsp_valid(mem_wr_rsp_valid),
        .wr_rsp_ready(mem_wr_rsp_ready), .wr_rsp_error(mem_wr_rsp_error),
        .rsp_valid(mem_rsp_valid), .rsp_ready(mem_rsp_ready),
        .rsp_rdata(mem_rsp_rdata), .rsp_last(mem_rsp_last),
        .rsp_error(mem_rsp_error), .descriptor_count(model_descriptor_count),
        .read_count(), .write_count(), .write_beat_count(),
        .write_response_count(), .response_count(), .error_count(model_error_count)
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            parser_desc_seen <= 0;
            parser_error_seen <= 0;
            engine_done_seen <= 0;
        end else begin
            if (no_mem_expected && (mem_req_valid || mem_wr_valid))
                $fatal(1, "rejected/no-op command emitted memory VALID");
            if (parser_desc_valid && parser_desc_ready)
                parser_desc_seen <= parser_desc_seen + 1;
            if (parser_error_valid)
                parser_error_seen <= parser_error_seen + 1;
            if (engine_done_valid)
                engine_done_seen <= engine_done_seen + 1;
        end
    end

    function automatic [255:0] make_command(
        input logic [2:0] op,
        input logic [31:0] src,
        input logic [31:0] dst,
        input logic [15:0] width,
        input logic [15:0] height,
        input logic [15:0] src_stride,
        input logic [15:0] dst_stride
    );
        logic [255:0] packet;
        begin
            packet = '0;
            packet[2:0] = op;
            packet[47:16] = src;
            packet[79:48] = dst;
            packet[95:80] = width;
            packet[111:96] = height;
            packet[127:112] = src_stride;
            packet[143:128] = dst_stride;
            packet[175:144] = 32'h0000_5a3c;
            packet[183:176] = 8'd128;
            packet[199:184] = 16'h07e0;
            make_command = packet;
        end
    endfunction

    task automatic send_parser(input logic [255:0] packet);
        begin
            @(negedge clk);
            direct_mode = 1'b0;
            cmd_data = packet;
            cmd_valid = 1'b1;
            while (!cmd_ready)
                @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            cmd_valid = 1'b0;
        end
    endtask

    task automatic send_direct(input logic [255:0] packet);
        begin
            @(negedge clk);
            direct_mode = 1'b1;
            direct_data = packet;
            direct_seq = direct_seq + 32'd1;
            direct_valid = 1'b1;
            while (!engine_desc_ready)
                @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            direct_valid = 1'b0;
        end
    endtask

    task automatic wait_done(input logic expected_error);
        integer guard;
        begin
            guard = 0;
            while (!engine_done_valid && guard < 1000) begin
                @(negedge clk);
                guard = guard + 1;
            end
            if (guard >= 1000 || engine_done_error !== expected_error)
                $fatal(1, "completion mismatch/timeout error=%0b expected=%0b",
                       engine_done_error, expected_error);
            @(negedge clk);
        end
    endtask

    task automatic reject_at_parser(input logic [255:0] packet);
        integer before_req, before_model, before_desc, before_drop, before_err;
        begin
            before_req = request_count;
            before_model = model_descriptor_count;
            before_desc = parser_desc_seen;
            before_drop = parser_dropped_count;
            before_err = engine_error_count;
            no_mem_expected = 1'b1;
            send_parser(packet);
            if (!parser_error_valid || parser_error_code !== ERR_BAD_STRIDE)
                $fatal(1, "parser failed ERR_BAD_STRIDE op=%0d ss=%0d ds=%0d code=%0d",
                       packet[2:0], packet[127:112], packet[143:128],
                       parser_error_code);
            if (parser_desc_valid)
                $fatal(1, "parser emitted an odd-stride descriptor");
            repeat (3) @(negedge clk);
            if (request_count != before_req || model_descriptor_count != before_model ||
                parser_desc_seen != before_desc || engine_error_count != before_err ||
                parser_dropped_count != before_drop + 1)
                $fatal(1, "parser rejection leaked a descriptor/request or bad counters");
            parser_rejected = parser_rejected + 1;
            no_mem_expected = 1'b0;
        end
    endtask

    task automatic reject_at_engine(input logic [255:0] packet);
        integer before_req, before_model, before_err, before_pixels;
        begin
            before_req = request_count;
            before_model = model_descriptor_count;
            before_err = engine_error_count;
            before_pixels = pixel_count;
            no_mem_expected = 1'b1;
            send_direct(packet);
            // A direct invalid descriptor completes at its acceptance edge,
            // before the engine can enter a request-generating state.
            if (!engine_done_valid || !engine_done_error || engine_busy)
                $fatal(1, "engine did not reject stride at descriptor entry");
            wait_done(1'b1);
            repeat (2) @(negedge clk);
            if (request_count != before_req || model_descriptor_count != before_model ||
                pixel_count != before_pixels || engine_error_count != before_err + 1)
                $fatal(1, "direct rejection leaked a request or bad counters");
            direct_rejected = direct_rejected + 1;
            no_mem_expected = 1'b0;
        end
    endtask

    task automatic allow_command(
        input logic use_direct,
        input logic [255:0] packet,
        input integer expected_requests,
        input integer expected_pixels
    );
        integer before_req, before_model, before_pixels, before_errors, before_drop;
        begin
            before_req = request_count;
            before_model = model_descriptor_count;
            before_pixels = pixel_count;
            before_errors = engine_error_count;
            before_drop = parser_dropped_count;
            no_mem_expected = (expected_requests == 0);
            if (use_direct)
                send_direct(packet);
            else
                send_parser(packet);
            wait_done(1'b0);
            if (request_count != before_req + expected_requests ||
                model_descriptor_count != before_model + expected_requests ||
                pixel_count != before_pixels + expected_pixels ||
                engine_error_count != before_errors ||
                parser_dropped_count != before_drop)
                $fatal(1, "legal command changed counters unexpectedly op=%0d direct=%0b",
                       packet[2:0], use_direct);
            allowed_commands = allowed_commands + 1;
            no_mem_expected = 1'b0;
        end
    endtask

    task automatic check_rect(input integer base, input logic is_fill);
        logic [15:0] expected;
        begin
            for (integer row = 0; row < 2; row = row + 1)
                for (integer pixel = 0; pixel < 4; pixel = pixel + 1) begin
                    expected = is_fill ? 16'h5a3c :
                               16'(16'h1000 + row * 16'h0100 + pixel);
                    if (u_mem.mem[(base + row * 10 + pixel * 2) / 2] !== expected)
                        $fatal(1, "legal rectangle mismatch base=%h row=%0d pixel=%0d",
                               base, row, pixel);
                end
        end
    endtask

    initial begin
        cmd_valid = 1'b0;
        cmd_data = '0;
        direct_mode = 1'b0;
        direct_valid = 1'b0;
        direct_data = '0;
        direct_seq = '0;
        no_mem_expected = 1'b0;
        parser_rejected = 0;
        direct_rejected = 0;
        allowed_commands = 0;
        for (integer k = 0; k < 2048; k = k + 1)
            u_mem.mem[k] = 16'h0000;
        for (integer row = 0; row < 2; row = row + 1)
            for (integer pixel = 0; pixel < 4; pixel = pixel + 1)
                u_mem.mem[(16'h0100 + row * 10 + pixel * 2) / 2] =
                    16'(16'h1000 + row * 16'h0100 + pixel);

        repeat (4) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);

        // All source-using operations reject odd source OR destination
        // stride. A four-pixel row needs eight bytes; nine is long enough
        // but would put the second row at an odd byte address.
        for (integer op = 2; op <= 4; op = op + 1) begin
            reject_at_parser(make_command(3'(op), 32'h100, 32'h600,
                                           16'd4, 16'd2, 16'd9, 16'd10));
            reject_at_parser(make_command(3'(op), 32'h100, 32'h600,
                                           16'd4, 16'd2, 16'd10, 16'd9));
        end
        reject_at_parser(make_command(OP_SOLID_FILL, 32'h101, 32'h600,
                                      16'd4, 16'd2, 16'd1, 16'd9));

        // NOP uses neither stride; Fill uses no source surface. Both must
        // remain legal, and a normal even-stride two-row copy must be exact.
        allow_command(1'b0, make_command(OP_NOP, 32'h101, 32'h201,
                                         16'd0, 16'd0, 16'd1, 16'd3), 0, 0);
        allow_command(1'b0, make_command(OP_SOLID_FILL, 32'h101, 32'h300,
                                         16'd4, 16'd2, 16'd1, 16'd10), 2, 8);
        check_rect(16'h0300, 1'b1);
        allow_command(1'b0, make_command(OP_BLOCK_COPY, 32'h100, 32'h200,
                                         16'd4, 16'd2, 16'd10, 16'd10), 4, 8);
        check_rect(16'h0200, 1'b0);

        for (integer op = 2; op <= 4; op = op + 1) begin
            reject_at_engine(make_command(3'(op), 32'h100, 32'h600,
                                           16'd4, 16'd2, 16'd9, 16'd10));
            reject_at_engine(make_command(3'(op), 32'h100, 32'h600,
                                           16'd4, 16'd2, 16'd10, 16'd9));
        end
        reject_at_engine(make_command(OP_SOLID_FILL, 32'h101, 32'h600,
                                      16'd4, 16'd2, 16'd1, 16'd9));
        allow_command(1'b1, make_command(OP_NOP, 32'h101, 32'h201,
                                         16'd0, 16'd0, 16'd1, 16'd3), 0, 0);
        allow_command(1'b1, make_command(OP_SOLID_FILL, 32'h101, 32'h400,
                                         16'd4, 16'd2, 16'd1, 16'd10), 2, 8);
        check_rect(16'h0400, 1'b1);
        allow_command(1'b1, make_command(OP_BLOCK_COPY, 32'h100, 32'h500,
                                         16'd4, 16'd2, 16'd10, 16'd10), 4, 8);
        check_rect(16'h0500, 1'b0);
        repeat (3) @(negedge clk);

        if (parser_rejected != 7 || direct_rejected != 7 || allowed_commands != 6 ||
            parser_error_seen != 7 || parser_desc_seen != 3 ||
            parser_accepted_count != 10 || parser_dropped_count != 7 ||
            parser_completed_count != 3 || parser_memory_error_count != 0 ||
            engine_done_seen != 13 || engine_error_count != 7 ||
            request_count != 12 || read_count != 4 || write_count != 8 ||
            pixel_count != 32 || model_descriptor_count != 12 || model_error_count != 0)
            $fatal(1, "stride regression final counters did not match");

        $display("TB_C2_STRIDE_ALIGNMENT_PASS parser_rejected=%0d direct_rejected=%0d allowed=%0d requests=%0d reads=%0d writes=%0d pixels=%0d errors=%0d",
                 parser_rejected, direct_rejected, allowed_commands, request_count,
                 read_count, write_count, pixel_count, engine_error_count);
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "tb_c2_stride_alignment timeout");
    end
endmodule
