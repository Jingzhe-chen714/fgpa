`timescale 1ns/1ps

// Small self-check for the independent pixel operators.  This testbench has
// no dependency on the case2 top or on a vendor memory primitive.
module tb_pixel_ops;
    logic [15:0] fg565, bg565, blend565;
    logic [7:0]  alpha565;
    logic [23:0] fg888, bg888, blend888;
    logic [7:0]  alpha888;

    alpha_blend_pixel #(.PIXEL_FORMAT(0), .PIXEL_W(16)) u_blend565 (
        .fg_pixel(fg565), .bg_pixel(bg565), .alpha(alpha565), .out_pixel(blend565)
    );
    alpha_blend_pixel #(.PIXEL_FORMAT(1), .PIXEL_W(24)) u_blend888 (
        .fg_pixel(fg888), .bg_pixel(bg888), .alpha(alpha888), .out_pixel(blend888)
    );

    logic [7:0] pack_r, pack_g, pack_b;
    logic [15:0] packed565;
    logic [7:0] unpack_r, unpack_g, unpack_b;
    pixel_pack #(.PIXEL_FORMAT(0), .PIXEL_W(16)) u_pack (
        .r8(pack_r), .g8(pack_g), .b8(pack_b), .pixel(packed565)
    );
    pixel_unpack #(.PIXEL_FORMAT(0), .PIXEL_W(16)) u_unpack (
        .pixel(packed565), .r8(unpack_r), .g8(unpack_g), .b8(unpack_b)
    );

    logic [23:0] packed888;
    logic [7:0] unpack888_r, unpack888_g, unpack888_b;
    pixel_pack #(.PIXEL_FORMAT(1), .PIXEL_W(24)) u_pack888 (
        .r8(pack_r), .g8(pack_g), .b8(pack_b), .pixel(packed888)
    );
    pixel_unpack #(.PIXEL_FORMAT(1), .PIXEL_W(24)) u_unpack888 (
        .pixel(packed888), .r8(unpack888_r), .g8(unpack888_g), .b8(unpack888_b)
    );

    logic [7:0] byte0, byte1, byte2;
    logic [15:0] bytes565;
    logic [7:0] byte0_back, byte1_back, byte2_back;
    pixel_pack_bytes #(.PIXEL_FORMAT(0), .PIXEL_W(16)) u_pack_bytes (
        .byte0(byte0), .byte1(byte1), .byte2(byte2), .pixel(bytes565)
    );
    pixel_unpack_bytes #(.PIXEL_FORMAT(0), .PIXEL_W(16)) u_unpack_bytes (
        .pixel(bytes565), .byte0(byte0_back), .byte1(byte1_back), .byte2(byte2_back)
    );

    logic [23:0] bytes888;
    logic [7:0] byte0_888_back, byte1_888_back, byte2_888_back;
    pixel_pack_bytes #(.PIXEL_FORMAT(1), .PIXEL_W(24)) u_pack_bytes888 (
        .byte0(byte0), .byte1(byte1), .byte2(byte2), .pixel(bytes888)
    );
    pixel_unpack_bytes #(.PIXEL_FORMAT(1), .PIXEL_W(24)) u_unpack_bytes888 (
        .pixel(bytes888), .byte0(byte0_888_back), .byte1(byte1_888_back),
        .byte2(byte2_888_back)
    );

    logic [15:0] key_src, key_bg, key_value, key_out;
    logic key_hit;
    color_key_pixel u_key (
        .src_pixel(key_src), .background_pixel(key_bg), .key_pixel(key_value),
        .out_pixel(key_out), .key_hit(key_hit)
    );

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    always #5 clk = ~clk;

    logic stream_in_valid, stream_in_ready;
    logic stream_out_valid, stream_out_ready;
    logic [15:0] stream_fg, stream_bg, stream_out;
    logic [7:0] stream_alpha;
    alpha_blend u_stream (
        .clk(clk), .rst_n(rst_n),
        .in_valid(stream_in_valid), .in_ready(stream_in_ready),
        .fg_pixel(stream_fg), .bg_pixel(stream_bg), .alpha(stream_alpha),
        .out_valid(stream_out_valid), .out_ready(stream_out_ready), .out_pixel(stream_out)
    );

    logic key_stream_in_valid, key_stream_in_ready;
    logic key_stream_out_valid, key_stream_out_ready, key_stream_hit;
    logic [15:0] key_stream_src, key_stream_bg, key_stream_key, key_stream_out;
    color_key u_key_stream (
        .clk(clk), .rst_n(rst_n),
        .in_valid(key_stream_in_valid), .in_ready(key_stream_in_ready),
        .src_pixel(key_stream_src), .background_pixel(key_stream_bg),
        .key_pixel(key_stream_key), .out_valid(key_stream_out_valid),
        .out_ready(key_stream_out_ready), .out_pixel(key_stream_out),
        .out_key_hit(key_stream_hit)
    );

    function automatic integer blend_ref(
        input integer fg_c,
        input integer bg_c,
        input integer a_c,
        input integer max_c
    );
        integer value;
        begin
            value = (fg_c*a_c + bg_c*(255-a_c) + 128) / 255;
            if (value < 0) value = 0;
            if (value > max_c) value = max_c;
            blend_ref = value;
        end
    endfunction

    function automatic [15:0] blend565_ref(
        input [15:0] fg,
        input [15:0] bg,
        input [7:0] a
    );
        integer rr, gg, bb;
        begin
            rr = blend_ref(fg[15:11], bg[15:11], a, 31);
            gg = blend_ref(fg[10:5],  bg[10:5],  a, 63);
            bb = blend_ref(fg[4:0],   bg[4:0],   a, 31);
            blend565_ref = {rr[4:0], gg[5:0], bb[4:0]};
        end
    endfunction

    integer errors;
    integer i;
    integer exp_r888;
    integer exp_g888;
    integer exp_b888;
    task automatic check565(input [15:0] fg, input [15:0] bg, input [7:0] a);
        reg [15:0] expected;
        begin
            fg565 = fg;
            bg565 = bg;
            alpha565 = a;
            #1;
            expected = blend565_ref(fg, bg, a);
            if (blend565 !== expected) begin
                $display("RGB565 blend mismatch fg=%h bg=%h a=%0d got=%h exp=%h",
                         fg, bg, a, blend565, expected);
                errors = errors + 1;
            end
        end
    endtask

    task automatic drive_stream(
        input [15:0] fg,
        input [15:0] bg,
        input [7:0] a
    );
        begin
            @(negedge clk);
            stream_fg = fg;
            stream_bg = bg;
            stream_alpha = a;
            stream_in_valid = 1'b1;
            while (!stream_in_ready) @(negedge clk);
            @(posedge clk);
            #1;
            stream_in_valid = 1'b0;
        end
    endtask

    initial begin
        errors = 0;
        fg565 = 16'h0;
        bg565 = 16'h0;
        alpha565 = 0;
        fg888 = 24'h0;
        bg888 = 24'h0;
        alpha888 = 0;
        pack_r = 0;
        pack_g = 0;
        pack_b = 0;
        byte0 = 0;
        byte1 = 0;
        byte2 = 0;
        key_src = 0;
        key_bg = 0;
        key_value = 0;
        stream_in_valid = 0;
        stream_out_ready = 0;
        stream_fg = 0;
        stream_bg = 0;
        stream_alpha = 0;
        key_stream_in_valid = 0;
        key_stream_out_ready = 0;
        key_stream_src = 0;
        key_stream_bg = 0;
        key_stream_key = 0;

        // Alpha boundary and a rounding-sensitive RGB565 case.
        check565(16'hF800, 16'h001F, 8'd0);
        check565(16'hF800, 16'h001F, 8'd255);
        check565(16'hF800, 16'h001F, 8'd128);
        check565(16'hFFFF, 16'h0000, 8'd127);

        // RGB888 parameter path.
        fg888 = 24'hFF8040;
        bg888 = 24'h102030;
        alpha888 = 8'd128;
        #1;
        exp_r888 = blend_ref(8'hff, 8'h10, 128, 255);
        exp_g888 = blend_ref(8'h80, 8'h20, 128, 255);
        exp_b888 = blend_ref(8'h40, 8'h30, 128, 255);
        if (blend888 !== {exp_r888[7:0], exp_g888[7:0], exp_b888[7:0]}) begin
            $display("RGB888 blend mismatch got=%h", blend888);
            errors = errors + 1;
        end

        // Channel and byte pack/unpack helpers.
        pack_r = 8'hf8;
        pack_g = 8'hfc;
        pack_b = 8'hf8;
        #1;
        if (packed565 !== 16'hffff || unpack_r !== 8'hff
            || unpack_g !== 8'hff || unpack_b !== 8'hff) begin
            $display("pack/unpack mismatch packed=%h unpack=(%h,%h,%h)",
                     packed565, unpack_r, unpack_g, unpack_b);
            errors = errors + 1;
        end
        if (packed888 !== 24'hf8fcf8 || unpack888_r !== pack_r
            || unpack888_g !== pack_g || unpack888_b !== pack_b) begin
            $display("RGB888 pack/unpack mismatch packed=%h unpack=(%h,%h,%h)",
                     packed888, unpack888_r, unpack888_g, unpack888_b);
            errors = errors + 1;
        end
        byte0 = 8'h1f;
        byte1 = 8'h00;
        byte2 = 8'hA5;
        #1;
        if (bytes565 !== 16'h001f || byte0_back !== byte0 || byte1_back !== byte1
            || byte2_back !== 8'h00) begin
            $display("byte order mismatch packed=%h back=(%h,%h,%h)",
                     bytes565, byte0_back, byte1_back, byte2_back);
            errors = errors + 1;
        end
        byte0 = 8'h12;
        byte1 = 8'h34;
        byte2 = 8'hab;
        #1;
        if (bytes888 !== 24'hab3412 || byte0_888_back !== byte0
            || byte1_888_back !== byte1 || byte2_888_back !== byte2) begin
            $display("RGB888 byte order mismatch packed=%h back=(%h,%h,%h)",
                     bytes888, byte0_888_back, byte1_888_back, byte2_888_back);
            errors = errors + 1;
        end

        // Color key hit keeps the destination; miss copies source.
        key_bg = 16'h1234;
        key_value = 16'h07e0;
        key_src = 16'h07e0;
        #1;
        if (!key_hit || key_out !== key_bg) begin
            $display("color-key hit mismatch hit=%b out=%h", key_hit, key_out);
            errors = errors + 1;
        end
        key_src = 16'h07e1;
        #1;
        if (key_hit || key_out !== key_src) begin
            $display("color-key miss mismatch hit=%b out=%h", key_hit, key_out);
            errors = errors + 1;
        end

        // The color-key stream carries the match indication with the pixel.
        rst_n = 1'b1;
        repeat (2) @(posedge clk);
        @(negedge clk);
        key_stream_src = key_value;
        key_stream_bg = key_bg;
        key_stream_key = key_value;
        key_stream_in_valid = 1'b1;
        while (!key_stream_in_ready) @(negedge clk);
        @(posedge clk);
        #1;
        key_stream_in_valid = 1'b0;
        if (!key_stream_out_valid || !key_stream_hit || key_stream_out !== key_bg) begin
            $display("color-key stream hit mismatch valid=%b hit=%b out=%h",
                     key_stream_out_valid, key_stream_hit, key_stream_out);
            errors = errors + 1;
        end
        key_stream_out_ready = 1'b1;
        @(posedge clk);
        #1;
        key_stream_out_ready = 1'b0;

        // Registered stream: hold output under backpressure, then consume it
        // while accepting a replacement in the same cycle.
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        drive_stream(16'hF800, 16'h001F, 8'd128);
        #1;
        if (!stream_out_valid || stream_out !== blend565_ref(16'hF800, 16'h001F, 8'd128)) begin
            $display("stream first output mismatch valid=%b out=%h", stream_out_valid, stream_out);
            errors = errors + 1;
        end
        repeat (2) begin
            @(posedge clk);
            #1;
            if (!stream_out_valid || stream_out !== blend565_ref(16'hF800, 16'h001F, 8'd128)) begin
                $display("stream hold mismatch valid=%b out=%h", stream_out_valid, stream_out);
                errors = errors + 1;
            end
        end

        // Consume first output and enqueue the second one simultaneously.
        @(negedge clk);
        stream_out_ready = 1'b1;
        stream_fg = 16'hffff;
        stream_bg = 16'h0000;
        stream_alpha = 8'd64;
        stream_in_valid = 1'b1;
        @(posedge clk);
        #1;
        if (!stream_out_valid || stream_out !== blend565_ref(16'hffff, 16'h0000, 8'd64)) begin
            $display("stream replacement mismatch valid=%b out=%h", stream_out_valid, stream_out);
            errors = errors + 1;
        end
        stream_in_valid = 1'b0;
        stream_out_ready = 1'b0;
        // With ready still high the replacement would be consumed on the
        // next edge.  Deassert ready first, then verify it is held under
        // backpressure.
        @(posedge clk);
        #1;
        if (!stream_out_valid || stream_out !== blend565_ref(16'hffff, 16'h0000, 8'd64)) begin
            $display("stream hold-after-replacement mismatch valid=%b out=%h", stream_out_valid, stream_out);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("TB_PIXEL_OPS_PASS");
        end else begin
            $display("TB_PIXEL_OPS_FAIL errors=%0d", errors);
            $fatal(1);
        end
        $finish;
    end
endmodule
