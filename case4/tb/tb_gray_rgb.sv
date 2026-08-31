`timescale 1ns/1ps

// Transaction-level smoke test for both supported packed camera formats.
// The RGB565 loop is exhaustive (all 65,536 code words); the RGB888 instance
// receives the corresponding bit-replicated color for every word.
module tb_gray_rgb;
    localparam integer X_W = 8;
    localparam integer Y_W = 8;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    logic rst;
    logic in_valid, in_sof, in_eol, in_eof;
    logic [X_W-1:0] in_x;
    logic [Y_W-1:0] in_y;
    logic [23:0] pixel565, pixel888;

    wire v565, sof565, eol565, eof565;
    wire [X_W-1:0] x565;
    wire [Y_W-1:0] y565;
    wire [7:0] gray565;
    wire [16:0] acc565;
    wire v888, sof888, eol888, eof888;
    wire [X_W-1:0] x888;
    wire [Y_W-1:0] y888;
    wire [7:0] gray888;
    wire [16:0] acc888;

    gray_rgb_stream #(.PIXEL_FORMAT(0), .X_W(X_W), .Y_W(Y_W)) dut565 (
        .clk(clk), .rst(rst), .in_valid(in_valid), .in_sof(in_sof),
        .in_eol(in_eol), .in_eof(in_eof), .in_x(in_x), .in_y(in_y),
        .pixel_in(pixel565), .m_valid(v565), .m_sof(sof565),
        .m_eol(eol565), .m_eof(eof565), .m_x(x565), .m_y(y565),
        .m_gray(gray565), .m_acc(acc565)
    );

    gray_rgb_stream #(.PIXEL_FORMAT(1), .X_W(X_W), .Y_W(Y_W)) dut888 (
        .clk(clk), .rst(rst), .in_valid(in_valid), .in_sof(in_sof),
        .in_eol(in_eol), .in_eof(in_eof), .in_x(in_x), .in_y(in_y),
        .pixel_in(pixel888), .m_valid(v888), .m_sof(sof888),
        .m_eol(eol888), .m_eof(eof888), .m_x(x888), .m_y(y888),
        .m_gray(gray888), .m_acc(acc888)
    );

    integer n;
    integer r5, g6, b5;
    integer r8_i, g8_i, b8_i;
    integer exp_acc;
    integer exp_gray;
    integer errors;

    initial begin
        errors = 0;
        rst = 1'b1;
        in_valid = 1'b0;
        in_sof = 1'b0;
        in_eol = 1'b0;
        in_eof = 1'b0;
        in_x = '0;
        in_y = '0;
        pixel565 = '0;
        pixel888 = '0;

        repeat (2) @(posedge clk);
        rst = 1'b0;

        for (n = 0; n < 65536; n = n + 1) begin
            r5 = (n >> 11) & 31;
            g6 = (n >> 5) & 63;
            b5 = n & 31;
            r8_i = (r5 << 3) | (r5 >> 2);
            g8_i = (g6 << 2) | (g6 >> 4);
            b8_i = (b5 << 3) | (b5 >> 2);
            exp_acc = 77*r8_i + 150*g8_i + 29*b8_i;
            exp_gray = (exp_acc + 128) >> 8;

            @(negedge clk);
            in_valid = 1'b1;
            in_sof = (n == 0);
            in_eol = ((n & 255) == 255);
            in_eof = (n == 65535);
            in_x = n & 255;
            in_y = (n >> 8) & 255;
            pixel565 = {8'h00, n[15:0]};
            pixel888 = {r8_i[7:0], g8_i[7:0], b8_i[7:0]};

            @(posedge clk);
            #1;
            if (!v565 || !v888) begin
                $display("ERROR missing valid at n=%0d", n);
                errors = errors + 1;
            end else begin
                if (gray565 !== exp_gray[7:0] || gray888 !== exp_gray[7:0] ||
                    acc565 !== exp_acc[16:0] || acc888 !== exp_acc[16:0]) begin
                    $display("ERROR gray n=%0d exp=%0d/%0d got=%0d/%0d acc=%0d/%0d",
                             n, exp_gray, exp_acc, gray565, gray888, acc565, acc888);
                    errors = errors + 1;
                end
                if (x565 !== in_x || y565 !== in_y || x888 !== in_x || y888 !== in_y ||
                    sof565 !== in_sof || eol565 !== in_eol || eof565 !== in_eof ||
                    sof888 !== in_sof || eol888 !== in_eol || eof888 !== in_eof) begin
                    $display("ERROR sideband n=%0d", n);
                    errors = errors + 1;
                end
            end
        end

        @(negedge clk);
        in_valid = 1'b0;
        in_sof = 1'b0;
        in_eol = 1'b0;
        in_eof = 1'b0;
        @(posedge clk);
        #1;
        if (v565 || v888) begin
            $display("ERROR valid did not clear after bubble");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("TB_GRAY_RGB PASS: exhaustive RGB565 and mapped RGB888 stream");
        else
            $fatal(1, "TB_GRAY_RGB FAIL errors=%0d", errors);
        $finish;
    end
endmodule
