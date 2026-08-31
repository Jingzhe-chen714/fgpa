`timescale 1ns/1ps

// Boundary-value smoke test for the signed Sobel arithmetic.  It exercises
// the ±1020 gradient limits that are easy to break when an unsigned 8-bit
// subtraction is performed before sign extension.
module tb_case4_sobel_extremes;
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    always #5 clk = ~clk;

    logic in_valid = 1'b0, in_win_valid = 1'b0;
    logic in_sof = 1'b0, in_eol = 1'b0, in_eof = 1'b0;
    logic [3:0] in_x = 0, in_y = 0;
    logic [23:0] in_rgb = 0;
    logic [7:0] p00=0,p01=0,p02=0,p10=0,p11=0,p12=0,p20=0,p21=0,p22=0;
    logic out_valid, out_win_valid, out_sof, out_eol, out_eof;
    logic [3:0] out_x, out_y;
    logic [23:0] out_rgb;
    logic signed [11:0] out_gx, out_gy;
    logic [10:0] out_magnitude;
    integer errors = 0;

    case4_sobel3x3 #(.X_W(4), .Y_W(4)) dut (
        .clk, .rst_n, .in_valid, .in_win_valid, .in_sof, .in_eol, .in_eof,
        .in_x, .in_y, .in_rgb,
        .p00,.p01,.p02,.p10,.p11,.p12,.p20,.p21,.p22,
        .out_valid,.out_win_valid,.out_sof,.out_eol,.out_eof,
        .out_x,.out_y,.out_rgb,.out_gx,.out_gy,.out_magnitude
    );

    task automatic clear_input;
        begin
            in_valid = 0; in_win_valid = 0; in_sof = 0; in_eol = 0; in_eof = 0;
            in_x = 0; in_y = 0; in_rgb = 0;
            p00=0;p01=0;p02=0;p10=0;p11=0;p12=0;p20=0;p21=0;p22=0;
        end
    endtask

    task automatic drive_window(input integer horizontal, input integer sign_dir);
        // horizontal=1: Gx limit; horizontal=0: Gy limit.
        // sign_dir=+1 gives positive gradient, -1 gives negative gradient.
        begin
            @(negedge clk);
            in_valid = 1; in_win_valid = 1; in_x = 2; in_y = 2;
            if (horizontal) begin
                if (sign_dir > 0) begin
                    p00=0;p01=0;p02=255; p10=0;p11=0;p12=255; p20=0;p21=0;p22=255;
                end else begin
                    p00=255;p01=0;p02=0; p10=255;p11=0;p12=0; p20=255;p21=0;p22=0;
                end
            end else begin
                if (sign_dir > 0) begin
                    p00=0;p01=0;p02=0; p10=0;p11=0;p12=0; p20=255;p21=255;p22=255;
                end else begin
                    p00=255;p01=255;p02=255; p10=0;p11=0;p12=0; p20=0;p21=0;p22=0;
                end
            end
            @(posedge clk); #1;
            @(negedge clk); clear_input();
            @(posedge clk); #1;
            @(negedge clk); clear_input();
            @(posedge clk); #1;
            if (!out_valid || !out_win_valid) begin
                $display("extreme valid failure"); errors = errors + 1;
            end
            if (horizontal && (out_gx !== sign_dir*1020 || out_gy !== 0
                               || out_magnitude !== 1020)) begin
                $display("Gx extreme failure: got gx=%0d gy=%0d mag=%0d",
                         out_gx, out_gy, out_magnitude);
                errors = errors + 1;
            end
            if (!horizontal && (out_gx !== 0 || out_gy !== sign_dir*1020
                                || out_magnitude !== 1020)) begin
                $display("Gy extreme failure: got gx=%0d gy=%0d mag=%0d",
                         out_gx, out_gy, out_magnitude);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        rst_n = 1;
        drive_window(1, 1);
        drive_window(1, -1);
        drive_window(0, 1);
        drive_window(0, -1);
        if (errors == 0) $display("CASE4_SOBEL_EXTREMES_PASS");
        else $fatal(1, "CASE4_SOBEL_EXTREMES_FAIL errors=%0d", errors);
        $finish;
    end
endmodule

