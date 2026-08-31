`timescale 1ns/1ps

// Full active-frame throughput smoke test.  It intentionally checks stream
// counts and coordinate bounds rather than storing a 640x480 golden frame;
// numerical bit-exact checks are covered by the small-frame scoreboard.
module tb_gray_sobel_core_640 #(
    // 0 keeps the portable array backend; 1 selects the Xilinx XPM BRAM
    // backend.  The same stream/count checks are intentionally reused for
    // both implementations.
    parameter integer WINDOW_BACKEND = 0
);
    localparam integer W = 640;
    localparam integer H = 480;
    localparam integer XB = 10;
    localparam integer YB = 9;
    localparam integer EXPECTED = (W-2)*(H-2);

    logic clk = 1'b0;
    always #2 clk = ~clk;
    logic rst;
    logic in_valid, in_sof, in_eol, in_eof;
    logic [XB-1:0] in_x;
    logic [YB-1:0] in_y;
    logic [23:0] in_pixel;
    wire out_valid, out_win_valid, out_sof, out_eol, out_eof, out_edge;
    wire [XB-1:0] out_x;
    wire [YB-1:0] out_y;
    wire signed [11:0] out_gx, out_gy;
    wire [10:0] out_magnitude;

    case4_gray_sobel_core #(
        .PIXEL_FORMAT(1), .IMG_WIDTH(W), .IMG_HEIGHT(H),
        .X_BITS(XB), .Y_BITS(YB), .MAG_W(11),
        .WINDOW_BACKEND(WINDOW_BACKEND)
    ) dut (
        .clk(clk), .rst(rst), .in_valid(in_valid), .in_sof(in_sof),
        .in_eol(in_eol), .in_eof(in_eof), .in_x(in_x), .in_y(in_y),
        .in_pixel(in_pixel), .threshold(11'd320),
        .out_valid(out_valid), .out_win_valid(out_win_valid),
        .out_sof(out_sof), .out_eol(out_eol), .out_eof(out_eof),
        .out_x(out_x), .out_y(out_y), .out_gx(out_gx), .out_gy(out_gy),
        .out_magnitude(out_magnitude), .out_edge(out_edge)
    );

    integer x, y;
    reg [7:0] z8;
    integer count, errors;
    integer last_x, last_y;
    initial begin
        rst = 1'b1;
        in_valid = 1'b0;
        in_sof = 1'b0;
        in_eol = 1'b0;
        in_eof = 1'b0;
        in_x = '0;
        in_y = '0;
        in_pixel = '0;
        count = 0;
        errors = 0;
        last_x = -1;
        last_y = -1;
        repeat (3) @(posedge clk);
        rst = 1'b0;

        for (y = 0; y < H; y = y + 1) begin
            for (x = 0; x < W; x = x + 1) begin
                @(negedge clk);
                in_valid = 1'b1;
                in_sof = (x == 0 && y == 0);
                in_eol = (x == W-1);
                in_eof = (x == W-1 && y == H-1);
                in_x = x;
                in_y = y;
                // Deterministic RGB888 ramp; no frame memory is required.
                z8 = (x + y) & 255;
                in_pixel = {x[7:0], y[7:0], z8};
            end
        end
        repeat (12) begin
            @(negedge clk);
            in_valid = 1'b0;
            in_sof = 1'b0;
            in_eol = 1'b0;
            in_eof = 1'b0;
        end
        @(posedge clk);
        #2;
        if (count != EXPECTED) begin
            $display("ERROR 640x480 output count=%0d expected=%0d", count, EXPECTED);
            errors = errors + 1;
        end
        if (last_x != W-2 || last_y != H-2) begin
            $display("ERROR final center=(%0d,%0d) expected=(%0d,%0d)", last_x,last_y,W-2,H-2);
            errors = errors + 1;
        end
        if (errors == 0)
            $display("TB_GRAY_SOBEL_CORE_640 PASS: %0d valid windows", count);
        else
            $fatal(1, "TB_GRAY_SOBEL_CORE_640 FAIL errors=%0d", errors);
        $finish;
    end

    always @(posedge clk) begin
        #1;
        if (!rst && out_valid) begin
            count = count + 1;
            if (!out_win_valid || out_x < 1 || out_x > W-2 ||
                out_y < 1 || out_y > H-2) begin
                $display("ERROR invalid coordinate/qualifier x=%0d y=%0d win=%b", out_x,out_y,out_win_valid);
                errors = errors + 1;
            end
            last_x = out_x;
            last_y = out_y;
        end
    end
endmodule
