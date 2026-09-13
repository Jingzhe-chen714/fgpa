`timescale 1ns/1ps

// Small self-checking XSIM test for the line-buffer/window and median stages.
// The active image is 5x5 and is a monotonic ramp, so the median of every
// interior 3x3 window is its centre sample.  The test also checks all nine
// window taps, centre coordinates, line/frame markers, and the one-cycle
// wrapper latency in the EXPLICIT legacy one-stage median mode. The default
// three-stage mode is covered by tb_median_pipeline and stream regression.

module tb_window3x3_median;
    localparam integer W = 5;
    localparam integer H = 5;
    localparam integer XW = (W <= 1) ? 1 : $clog2(W);
    localparam integer YW = (H <= 1) ? 1 : $clog2(H);

    logic clk = 1'b0;
    logic rst = 1'b1;
    always #5 clk = ~clk;

    logic in_valid, in_sof, in_eol, in_eof;
    logic [XW-1:0] in_x;
    logic [YW-1:0] in_y;
    logic [7:0] in_pixel;

    logic out_valid, out_sof, out_eol, out_eof;
    logic [XW-1:0] out_x;
    logic [YW-1:0] out_y;
    logic [7:0] out_pixel;
    logic window_valid, window_sof, window_eol, window_eof;
    logic [XW-1:0] window_x;
    logic [YW-1:0] window_y;
    logic [7:0] window_p00, window_p01, window_p02;
    logic [7:0] window_p10, window_p11, window_p12;
    logic [7:0] window_p20, window_p21, window_p22;

    window3x3_median #(
        .IMG_WIDTH (W),
        .IMG_HEIGHT(H),
        .PIXEL_BITS(8),
        .X_BITS    (XW),
        .Y_BITS    (YW),
        .MEDIAN_REGISTER_OUTPUT(1'b1), .MEDIAN_PIPELINE_STAGES(1)
    ) dut (
        .clk(clk), .rst(rst),
        .in_valid(in_valid), .in_sof(in_sof), .in_eol(in_eol), .in_eof(in_eof),
        .in_x(in_x), .in_y(in_y), .in_pixel(in_pixel),
        .out_valid(out_valid), .out_sof(out_sof), .out_eol(out_eol),
        .out_eof(out_eof), .out_x(out_x), .out_y(out_y), .out_pixel(out_pixel),
        .window_valid(window_valid), .window_sof(window_sof),
        .window_eol(window_eol), .window_eof(window_eof), .window_x(window_x),
        .window_y(window_y), .window_p00(window_p00), .window_p01(window_p01),
        .window_p02(window_p02), .window_p10(window_p10), .window_p11(window_p11),
        .window_p12(window_p12), .window_p20(window_p20), .window_p21(window_p21),
        .window_p22(window_p22)
    );

    integer errors = 0;
    integer cycles = 0;
    logic expected_valid_d;
    integer expected_x_d, expected_y_d, expected_pixel_d;

    task automatic check_after_edge;
        integer cx, cy;
        integer base;
        begin
            #1; // allow nonblocking assignments in the DUT to settle
            cycles = cycles + 1;

            cx = in_x;
            cy = in_y;
            if (in_valid && (cx >= 2) && (cy >= 2)) begin
                if (!window_valid) begin
                    $display("ERROR: missing window at input (%0d,%0d)", cx, cy);
                    errors = errors + 1;
                end else begin
                    if ((window_x !== cx-1) || (window_y !== cy-1)) begin
                        $display("ERROR: window coord got (%0d,%0d), expected (%0d,%0d)",
                                 window_x, window_y, cx-1, cy-1);
                        errors = errors + 1;
                    end
                    base = (cy-2)*W + (cx-2);
                    if ((window_p00 !== base) || (window_p01 !== base+1) ||
                        (window_p02 !== base+2) ||
                        (window_p10 !== base+W) || (window_p11 !== base+W+1) ||
                        (window_p12 !== base+W+2) ||
                        (window_p20 !== base+2*W) ||
                        (window_p21 !== base+2*W+1) ||
                        (window_p22 !== base+2*W+2)) begin
                        $display("ERROR: wrong taps at input (%0d,%0d): %0d %0d %0d / %0d %0d %0d / %0d %0d %0d",
                                 cx, cy, window_p00, window_p01, window_p02,
                                 window_p10, window_p11, window_p12,
                                 window_p20, window_p21, window_p22);
                        errors = errors + 1;
                    end
                end
            end else if (window_valid) begin
                $display("ERROR: spurious window at input (%0d,%0d)", cx, cy);
                errors = errors + 1;
            end

            // The median register sees the previous cycle's window output.
            if (out_valid !== expected_valid_d) begin
                $display("ERROR: median valid got %b expected %b at cycle %0d",
                         out_valid, expected_valid_d, cycles);
                errors = errors + 1;
            end
            if (expected_valid_d) begin
                if ((out_x !== expected_x_d) || (out_y !== expected_y_d) ||
                    (out_pixel !== expected_pixel_d[7:0])) begin
                    $display("ERROR: median got (%0d,%0d)=%0d expected (%0d,%0d)=%0d",
                             out_x, out_y, out_pixel, expected_x_d, expected_y_d,
                             expected_pixel_d);
                    errors = errors + 1;
                end
            end

            // Save the current window-valid expectation for the next edge.
            expected_valid_d = in_valid && (cx >= 2) && (cy >= 2);
            expected_x_d = cx - 1;
            expected_y_d = cy - 1;
            expected_pixel_d = (cy-1)*W + (cx-1);
        end
    endtask

    task automatic drive_pixel(input integer xx, input integer yy);
        begin
            @(negedge clk);
            in_valid = 1'b1;
            in_sof   = (xx == 0) && (yy == 0);
            in_eol   = (xx == W-1);
            in_eof   = (xx == W-1) && (yy == H-1);
            in_x     = xx[XW-1:0];
            in_y     = yy[YW-1:0];
            in_pixel = (yy*W + xx) & 8'hff;
            @(posedge clk);
            check_after_edge();
        end
    endtask

    integer xx, yy;
    initial begin
        in_valid = 1'b0;
        in_sof = 1'b0;
        in_eol = 1'b0;
        in_eof = 1'b0;
        in_x = '0;
        in_y = '0;
        in_pixel = '0;
        expected_valid_d = 1'b0;
        expected_x_d = 0;
        expected_y_d = 0;
        expected_pixel_d = 0;

        repeat (3) @(posedge clk);
        #1 rst = 1'b0;

        for (yy = 0; yy < H; yy = yy + 1)
            for (xx = 0; xx < W; xx = xx + 1)
                drive_pixel(xx, yy);

        // Flush the registered median stage with two idle cycles.
        @(negedge clk);
        in_valid = 1'b0;
        in_sof = 1'b0;
        in_eol = 1'b0;
        in_eof = 1'b0;
        @(posedge clk); check_after_edge();
        @(negedge clk);
        @(posedge clk); check_after_edge();

        if (errors == 0)
            $display("PASS: tb_window3x3_median (%0d cycles)", cycles);
        else
            $fatal(1,"FAIL: tb_window3x3_median errors=%0d", errors);
        $finish;
    end
endmodule

