`timescale 1ns/1ps

// Small deterministic XSIM self-check for case4_sobel_edge_ops.sv.
// The test drives a complete 6x5 frame, including invalid border windows,
// then drains the four-cycle wrapper pipeline.  It checks gradients,
// magnitude, threshold, red overlay, coordinates, and all sideband marks.

module tb_case4_sobel_edge_ops;
    localparam integer W       = 6;
    localparam integer H       = 5;
    localparam integer X_W     = 4;
    localparam integer Y_W     = 4;
    localparam integer THRESH  = 300;
    localparam integer LATENCY = 4;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    always #5 clk = ~clk;

    logic in_valid, in_win_valid, in_sof, in_eol, in_eof;
    logic [X_W-1:0] in_x;
    logic [Y_W-1:0] in_y;
    logic [23:0] in_rgb;
    logic [7:0] p00, p01, p02, p10, p11, p12, p20, p21, p22;
    logic [10:0] threshold = THRESH[10:0];

    logic out_valid, out_win_valid, out_sof, out_eol, out_eof, out_edge;
    logic [X_W-1:0] out_x;
    logic [Y_W-1:0] out_y;
    logic [23:0] out_rgb;
    logic signed [11:0] out_gx, out_gy;
    logic [10:0] out_magnitude;

    case4_sobel_edge_pipeline #(
        .PIX_W(8), .RGB_W(24), .X_W(X_W), .Y_W(Y_W)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .in_win_valid(in_win_valid),
        .in_sof(in_sof), .in_eol(in_eol), .in_eof(in_eof),
        .in_x(in_x), .in_y(in_y), .in_rgb(in_rgb),
        .p00(p00), .p01(p01), .p02(p02),
        .p10(p10), .p11(p11), .p12(p12),
        .p20(p20), .p21(p21), .p22(p22),
        .threshold(threshold),
        .out_valid(out_valid), .out_win_valid(out_win_valid),
        .out_sof(out_sof), .out_eol(out_eol), .out_eof(out_eof),
        .out_x(out_x), .out_y(out_y), .out_rgb(out_rgb),
        .out_gx(out_gx), .out_gy(out_gy),
        .out_magnitude(out_magnitude), .out_edge(out_edge)
    );

    function automatic integer pix(input integer xx, input integer yy);
        integer v;
        begin
            if ((xx < 0) || (xx >= W) || (yy < 0) || (yy >= H)) begin
                pix = 0;
            end else begin
                // A ramp plus a small checker term exercises both signs and
                // prevents the test from passing with only one gradient.
                v = 23*xx + 41*yy + (((xx + 2*yy) & 1) ? 17 : 0);
                pix = v & 8'hff;
            end
        end
    endfunction

    function automatic integer rgb_value(input integer xx, input integer yy);
        integer r, g, b;
        begin
            r = (31*xx + 7*yy) & 8'hff;
            g = (11*xx + 43*yy + 19) & 8'hff;
            b = (53*xx + 5*yy + 101) & 8'hff;
            rgb_value = (r << 16) | (g << 8) | b;
        end
    endfunction

    function automatic integer gx_ref(input integer xx, input integer yy);
        begin
            gx_ref = (pix(xx+1, yy-1) - pix(xx-1, yy-1))
                   + 2*(pix(xx+1, yy) - pix(xx-1, yy))
                   + (pix(xx+1, yy+1) - pix(xx-1, yy+1));
        end
    endfunction

    function automatic integer gy_ref(input integer xx, input integer yy);
        begin
            gy_ref = (pix(xx-1, yy+1) - pix(xx-1, yy-1))
                   + 2*(pix(xx, yy+1) - pix(xx, yy-1))
                   + (pix(xx+1, yy+1) - pix(xx+1, yy-1));
        end
    endfunction

    function automatic integer abs_i(input integer v);
        begin
            abs_i = (v < 0) ? -v : v;
        end
    endfunction

    integer q_valid [0:LATENCY];
    integer q_win   [0:LATENCY];
    integer q_sof   [0:LATENCY];
    integer q_eol   [0:LATENCY];
    integer q_eof   [0:LATENCY];
    integer q_x     [0:LATENCY];
    integer q_y     [0:LATENCY];
    integer q_rgb   [0:LATENCY];
    integer q_gx    [0:LATENCY];
    integer q_gy    [0:LATENCY];
    integer q_mag   [0:LATENCY];
    integer q_edge  [0:LATENCY];
    integer errors;
    integer cycle_count;
    integer i;

    task automatic set_input(
        input integer xx,
        input integer yy,
        input integer active
    );
        integer rv;
        begin
            @(negedge clk);
            in_valid     = active;
            in_win_valid = active && (xx > 0) && (xx < W-1)
                                  && (yy > 0) && (yy < H-1);
            in_sof       = active && (xx == 0) && (yy == 0);
            in_eol       = active && (xx == W-1);
            in_eof       = active && (xx == W-1) && (yy == H-1);
            in_x         = active ? xx : 0;
            in_y         = active ? yy : 0;
            rv           = active ? rgb_value(xx, yy) : 0;
            in_rgb       = rv;
            p00          = pix(xx-1, yy-1);
            p01          = pix(xx,   yy-1);
            p02          = pix(xx+1, yy-1);
            p10          = pix(xx-1, yy);
            p11          = pix(xx,   yy);
            p12          = pix(xx+1, yy);
            p20          = pix(xx-1, yy+1);
            p21          = pix(xx,   yy+1);
            p22          = pix(xx+1, yy+1);
        end
    endtask

    task automatic enqueue_expected(
        input integer xx,
        input integer yy,
        input integer active
    );
        integer gv, hv, mv, wv;
        begin
            wv = active && (xx > 0) && (xx < W-1)
                      && (yy > 0) && (yy < H-1);
            gv = wv ? gx_ref(xx, yy) : 0;
            hv = wv ? gy_ref(xx, yy) : 0;
            mv = wv ? abs_i(gv) + abs_i(hv) : 0;
            q_valid[LATENCY] = active;
            q_win[LATENCY]   = wv;
            q_sof[LATENCY]   = active && (xx == 0) && (yy == 0);
            q_eol[LATENCY]   = active && (xx == W-1);
            q_eof[LATENCY]   = active && (xx == W-1) && (yy == H-1);
            q_x[LATENCY]     = active ? xx : 0;
            q_y[LATENCY]     = active ? yy : 0;
            q_rgb[LATENCY]   = active ? rgb_value(xx, yy) : 0;
            q_gx[LATENCY]    = gv;
            q_gy[LATENCY]    = hv;
            q_mag[LATENCY]   = mv;
            q_edge[LATENCY]  = wv && (mv >= THRESH);
        end
    endtask

    task automatic check_output;
        begin
            if (out_valid !== q_valid[0][0]) begin
                $display("valid mismatch cycle %0d: got %b exp %b", cycle_count, out_valid, q_valid[0][0]);
                errors = errors + 1;
            end
            if (out_win_valid !== q_win[0][0]) begin
                $display("win_valid mismatch cycle %0d: got %b exp %b", cycle_count, out_win_valid, q_win[0][0]);
                errors = errors + 1;
            end
            if (out_sof !== q_sof[0][0] || out_eol !== q_eol[0][0]
                || out_eof !== q_eof[0][0]) begin
                $display("sideband mismatch cycle %0d", cycle_count);
                errors = errors + 1;
            end
            if (out_x !== q_x[0][X_W-1:0] || out_y !== q_y[0][Y_W-1:0]) begin
                $display("coordinate mismatch cycle %0d: got (%0d,%0d) exp (%0d,%0d)",
                         cycle_count, out_x, out_y, q_x[0], q_y[0]);
                errors = errors + 1;
            end
            if ($signed(out_gx) !== q_gx[0] || $signed(out_gy) !== q_gy[0]
                || out_magnitude !== q_mag[0][10:0]) begin
                $display("gradient mismatch cycle %0d: got gx=%0d gy=%0d mag=%0d exp gx=%0d gy=%0d mag=%0d",
                         cycle_count, $signed(out_gx), $signed(out_gy), out_magnitude,
                         q_gx[0], q_gy[0], q_mag[0]);
                errors = errors + 1;
            end
            if (out_edge !== q_edge[0][0]) begin
                $display("edge mismatch cycle %0d: got %b exp %b", cycle_count, out_edge, q_edge[0][0]);
                errors = errors + 1;
            end
            if (out_rgb !== (q_edge[0][0] ? 24'hFF0000 : q_rgb[0][23:0])) begin
                $display("RGB overlay mismatch cycle %0d: got %h exp %h", cycle_count,
                         out_rgb, (q_edge[0][0] ? 24'hFF0000 : q_rgb[0][23:0]));
                errors = errors + 1;
            end
        end
    endtask

    task automatic shift_queue;
        integer j;
        begin
            for (j = 0; j < LATENCY; j = j + 1) begin
                q_valid[j] = q_valid[j+1];
                q_win[j]   = q_win[j+1];
                q_sof[j]   = q_sof[j+1];
                q_eol[j]   = q_eol[j+1];
                q_eof[j]   = q_eof[j+1];
                q_x[j]     = q_x[j+1];
                q_y[j]     = q_y[j+1];
                q_rgb[j]   = q_rgb[j+1];
                q_gx[j]    = q_gx[j+1];
                q_gy[j]    = q_gy[j+1];
                q_mag[j]   = q_mag[j+1];
                q_edge[j]  = q_edge[j+1];
            end
        end
    endtask

    initial begin
        errors = 0;
        cycle_count = 0;
        in_valid = 0; in_win_valid = 0;
        in_sof = 0; in_eol = 0; in_eof = 0;
        in_x = 0; in_y = 0; in_rgb = 0;
        p00 = 0; p01 = 0; p02 = 0; p10 = 0; p11 = 0; p12 = 0;
        p20 = 0; p21 = 0; p22 = 0;
        for (i = 0; i <= LATENCY; i = i + 1) begin
            q_valid[i] = 0; q_win[i] = 0; q_sof[i] = 0; q_eol[i] = 0; q_eof[i] = 0;
            q_x[i] = 0; q_y[i] = 0; q_rgb[i] = 0; q_gx[i] = 0; q_gy[i] = 0;
            q_mag[i] = 0; q_edge[i] = 0;
        end

        // Hold reset for two clocks, then feed the frame.
        repeat (2) @(posedge clk);
        rst_n = 1'b1;

        for (integer yy = 0; yy < H; yy = yy + 1) begin
            for (integer xx = 0; xx < W; xx = xx + 1) begin
                set_input(xx, yy, 1);
                enqueue_expected(xx, yy, 1);
                @(posedge clk); #1;
                check_output();
                shift_queue();
                cycle_count = cycle_count + 1;
            end
        end

        // Drain all registered stages with invalid transfers.
        for (integer d = 0; d < LATENCY + 1; d = d + 1) begin
            set_input(0, 0, 0);
            enqueue_expected(0, 0, 0);
            @(posedge clk); #1;
            check_output();
            shift_queue();
            cycle_count = cycle_count + 1;
        end

        if (errors == 0)
            $display("CASE4_SOBEL_EDGE_OPS_PASS");
        else
            $fatal(1, "CASE4_SOBEL_EDGE_OPS_FAIL errors=%0d", errors);
        $finish;
    end
endmodule
