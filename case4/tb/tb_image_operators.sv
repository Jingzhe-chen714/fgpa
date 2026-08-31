`timescale 1ns/1ps

// Small frame, cycle-level regression for the line buffer, median, Sobel and
// threshold operators.  The coordinate sideband is used as the scoreboard
// key, so the test remains valid if the arithmetic pipeline depth changes.
module tb_image_operators;
    localparam integer W = 8;
    localparam integer H = 6;
    localparam integer XB = 3;
    localparam integer YB = 3;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    logic rst;
    logic in_valid, in_sof, in_eol, in_eof;
    logic [XB-1:0] in_x;
    logic [YB-1:0] in_y;
    logic [7:0] in_pixel;

    logic [7:0] image [0:H-1][0:W-1];

    wire w_valid, w_sof, w_eol, w_eof;
    wire [XB-1:0] wx;
    wire [YB-1:0] wy;
    wire [7:0] p00, p01, p02, p10, p11, p12, p20, p21, p22;

    window3x3_gray #(
        .IMG_WIDTH(W), .IMG_HEIGHT(H), .PIXEL_BITS(8),
        .X_BITS(XB), .Y_BITS(YB)
    ) u_window (
        .clk(clk), .rst(rst),
        .in_valid(in_valid), .in_sof(in_sof), .in_eol(in_eol), .in_eof(in_eof),
        .in_x(in_x), .in_y(in_y), .in_pixel(in_pixel),
        .out_valid(w_valid), .out_sof(w_sof), .out_eol(w_eol), .out_eof(w_eof),
        .out_x(wx), .out_y(wy),
        .out_p00(p00), .out_p01(p01), .out_p02(p02),
        .out_p10(p10), .out_p11(p11), .out_p12(p12),
        .out_p20(p20), .out_p21(p21), .out_p22(p22)
    );

    wire m_valid, m_sof, m_eol, m_eof;
    wire [XB-1:0] mx;
    wire [YB-1:0] my;
    wire [7:0] median_pixel;

    median3x3_u8 #(.PIXEL_BITS(8), .X_BITS(XB), .Y_BITS(YB)) u_median (
        .clk(clk), .rst(rst),
        .in_valid(w_valid), .in_sof(w_sof), .in_eol(w_eol), .in_eof(w_eof),
        .in_x(wx), .in_y(wy),
        .in_p00(p00), .in_p01(p01), .in_p02(p02),
        .in_p10(p10), .in_p11(p11), .in_p12(p12),
        .in_p20(p20), .in_p21(p21), .in_p22(p22),
        .out_valid(m_valid), .out_sof(m_sof), .out_eol(m_eol), .out_eof(m_eof),
        .out_x(mx), .out_y(my), .out_pixel(median_pixel)
    );

    wire s_valid, s_win_valid, s_sof, s_eol, s_eof;
    wire [XB-1:0] sx;
    wire [YB-1:0] sy;
    wire signed [11:0] gx, gy;
    wire [10:0] magnitude;

    case4_sobel3x3 #(
        .PIX_W(8), .RGB_W(24), .X_W(XB), .Y_W(YB),
        .PART_W(11), .GRAD_W(12), .MAG_W(11)
    ) u_sobel (
        .clk(clk), .rst_n(~rst),
        .in_valid(w_valid), .in_win_valid(w_valid),
        .in_sof(w_sof), .in_eol(w_eol), .in_eof(w_eof),
        .in_x(wx), .in_y(wy), .in_rgb(24'h112233),
        .p00(p00), .p01(p01), .p02(p02),
        .p10(p10), .p11(p11), .p12(p12),
        .p20(p20), .p21(p21), .p22(p22),
        .out_valid(s_valid), .out_win_valid(s_win_valid),
        .out_sof(s_sof), .out_eol(s_eol), .out_eof(s_eof),
        .out_x(sx), .out_y(sy), .out_rgb(),
        .out_gx(gx), .out_gy(gy), .out_magnitude(magnitude)
    );

    wire t_valid, t_win_valid, t_sof, t_eol, t_eof, edge_bit;
    wire [XB-1:0] tx;
    wire [YB-1:0] ty;
    wire [10:0] t_magnitude;
    wire [23:0] t_rgb;

    case4_edge_threshold #(.MAG_W(11), .RGB_W(24), .X_W(XB), .Y_W(YB)) u_threshold (
        .clk(clk), .rst_n(~rst),
        .in_valid(s_valid), .in_win_valid(s_win_valid),
        .in_sof(s_sof), .in_eol(s_eol), .in_eof(s_eof),
        .in_x(sx), .in_y(sy), .in_rgb(24'h112233),
        .in_magnitude(magnitude), .threshold(11'd100),
        .out_valid(t_valid), .out_win_valid(t_win_valid),
        .out_sof(t_sof), .out_eol(t_eol), .out_eof(t_eof),
        .out_x(tx), .out_y(ty), .out_rgb(t_rgb),
        .out_magnitude(t_magnitude), .out_edge(edge_bit)
    );

    wire o_valid, o_win_valid, o_sof, o_eol, o_eof, o_edge;
    wire [XB-1:0] ox;
    wire [YB-1:0] oy;
    wire [23:0] o_rgb;
    case4_edge_overlay #(.RGB_W(24), .X_W(XB), .Y_W(YB), .EDGE_COLOR(24'hFF0000)) u_overlay (
        .clk(clk), .rst_n(~rst),
        .in_valid(t_valid), .in_win_valid(t_win_valid),
        .in_sof(t_sof), .in_eol(t_eol), .in_eof(t_eof),
        .in_x(tx), .in_y(ty), .in_rgb(t_rgb), .in_edge(edge_bit),
        .out_valid(o_valid), .out_win_valid(o_win_valid),
        .out_sof(o_sof), .out_eol(o_eol), .out_eof(o_eof),
        .out_x(ox), .out_y(oy), .out_rgb(o_rgb), .out_edge(o_edge)
    );

    wire o565_valid, o565_win_valid, o565_edge;
    wire [XB-1:0] o565_x;
    wire [YB-1:0] o565_y;
    wire [15:0] o565_rgb;
    case4_edge_overlay_rgb565 #(.X_W(XB), .Y_W(YB), .EDGE_COLOR(16'hF800)) u_overlay565 (
        .clk(clk), .rst_n(~rst),
        .in_valid(t_valid), .in_win_valid(t_win_valid),
        .in_sof(t_sof), .in_eol(t_eol), .in_eof(t_eof),
        .in_x(tx), .in_y(ty), .in_rgb565(16'h1234), .in_edge(edge_bit),
        .out_valid(o565_valid), .out_win_valid(o565_win_valid),
        .out_sof(), .out_eol(), .out_eof(),
        .out_x(o565_x), .out_y(o565_y), .out_rgb565(o565_rgb), .out_edge(o565_edge)
    );

    wire e8_valid, e8_win_valid, e8_edge;
    wire [XB-1:0] e8_x;
    wire [YB-1:0] e8_y;
    wire [7:0] e8_pixel;
    case4_edge_expand8 #(.X_W(XB), .Y_W(YB)) u_edge_expand8 (
        .clk(clk), .rst_n(~rst),
        .in_valid(t_valid), .in_win_valid(t_win_valid),
        .in_sof(t_sof), .in_eol(t_eol), .in_eof(t_eof),
        .in_x(tx), .in_y(ty), .in_edge(edge_bit),
        .out_valid(e8_valid), .out_win_valid(e8_win_valid),
        .out_sof(), .out_eol(), .out_eof(), .out_x(e8_x), .out_y(e8_y),
        .out_edge(e8_edge), .out_edge8(e8_pixel)
    );

    integer iy, ix;
    integer errors;
    integer window_count, median_count, sobel_count, threshold_count;
    integer window_eol_count, threshold_eol_count;
    integer overlay_count, overlay565_count, edge8_count;
    integer cx, cy;
    integer ex_gx, ex_gy, ex_mag, ex_med;
    integer vals [0:8];
    integer a, b, tmp;

    initial begin
        // Deterministic non-symmetric image catches row/column swaps and sign
        // mistakes that a ramp alone can hide.
        for (iy = 0; iy < H; iy = iy + 1)
            for (ix = 0; ix < W; ix = ix + 1)
                image[iy][ix] = (ix*17 + iy*31 + ((ix*iy)%5)*7 + 3) & 255;

        errors = 0;
        window_count = 0;
        median_count = 0;
        sobel_count = 0;
        threshold_count = 0;
        window_eol_count = 0;
        threshold_eol_count = 0;
        overlay_count = 0;
        overlay565_count = 0;
        edge8_count = 0;
        rst = 1'b1;
        in_valid = 1'b0;
        in_sof = 1'b0;
        in_eol = 1'b0;
        in_eof = 1'b0;
        in_x = '0;
        in_y = '0;
        in_pixel = '0;

        repeat (3) @(posedge clk);
        rst = 1'b0;

        for (iy = 0; iy < H; iy = iy + 1) begin
            for (ix = 0; ix < W; ix = ix + 1) begin
                @(negedge clk);
                in_valid = 1'b1;
                in_sof = (ix == 0 && iy == 0);
                in_eol = (ix == W-1);
                in_eof = (ix == W-1 && iy == H-1);
                in_x = ix;
                in_y = iy;
                in_pixel = image[iy][ix];
            end
        end

        // Drain all registered stages.
        repeat (8) begin
            @(negedge clk);
            in_valid = 1'b0;
            in_sof = 1'b0;
            in_eol = 1'b0;
            in_eof = 1'b0;
        end
        @(posedge clk);
        #2;

        if (window_count != (W-2)*(H-2)) begin
            $display("ERROR window count=%0d expected=%0d", window_count, (W-2)*(H-2));
            errors = errors + 1;
        end
        if (median_count != (W-2)*(H-2)) begin
            $display("ERROR median count=%0d", median_count);
            errors = errors + 1;
        end
        if (sobel_count != (W-2)*(H-2)) begin
            $display("ERROR sobel count=%0d", sobel_count);
            errors = errors + 1;
        end
        if (threshold_count != (W-2)*(H-2)) begin
            $display("ERROR threshold count=%0d", threshold_count);
            errors = errors + 1;
        end
        if (overlay_count != (W-2)*(H-2) || overlay565_count != (W-2)*(H-2)) begin
            $display("ERROR overlay count RGB888=%0d RGB565=%0d", overlay_count, overlay565_count);
            errors = errors + 1;
        end
        if (edge8_count != (W-2)*(H-2)) begin
            $display("ERROR edge8 count=%0d", edge8_count);
            errors = errors + 1;
        end
        if (window_eol_count != H-2 || threshold_eol_count != H-2) begin
            $display("ERROR EOL count window=%0d threshold=%0d", window_eol_count, threshold_eol_count);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("TB_IMAGE_OPERATORS PASS: window/median/Sobel/threshold/overlay/edge8");
        else
            $fatal(1, "TB_IMAGE_OPERATORS FAIL errors=%0d", errors);
        $finish;
    end

    // Scoreboard runs after NBA updates so registered outputs are visible.
    always @(posedge clk) begin
        #1;
        if (rst)
            ;
        else begin
            if (w_valid) begin
                cx = wx;
                cy = wy;
                window_count = window_count + 1;
                if (cx < 1 || cx > W-2 || cy < 1 || cy > H-2) begin
                    $display("ERROR window coordinate (%0d,%0d)", cx, cy);
                    errors = errors + 1;
                end else begin
                    if (p00 !== image[cy-1][cx-1] || p01 !== image[cy-1][cx] || p02 !== image[cy-1][cx+1] ||
                        p10 !== image[cy][cx-1]   || p11 !== image[cy][cx]   || p12 !== image[cy][cx+1] ||
                        p20 !== image[cy+1][cx-1] || p21 !== image[cy+1][cx] || p22 !== image[cy+1][cx+1]) begin
                        $display("ERROR window center=(%0d,%0d) got=%0d,%0d,%0d/%0d,%0d,%0d/%0d,%0d,%0d",
                                 cx, cy, p00,p01,p02,p10,p11,p12,p20,p21,p22);
                        errors = errors + 1;
                    end
                end
                if (w_eol) window_eol_count = window_eol_count + 1;
            end

            if (m_valid) begin
                cx = mx;
                cy = my;
                median_count = median_count + 1;
                vals[0] = image[cy-1][cx-1]; vals[1] = image[cy-1][cx]; vals[2] = image[cy-1][cx+1];
                vals[3] = image[cy][cx-1];   vals[4] = image[cy][cx];   vals[5] = image[cy][cx+1];
                vals[6] = image[cy+1][cx-1]; vals[7] = image[cy+1][cx]; vals[8] = image[cy+1][cx+1];
                for (a = 0; a < 9; a = a + 1)
                    for (b = a+1; b < 9; b = b + 1)
                        if (vals[b] < vals[a]) begin tmp=vals[a]; vals[a]=vals[b]; vals[b]=tmp; end
                ex_med = vals[4];
                if (median_pixel !== ex_med[7:0]) begin
                    $display("ERROR median center=(%0d,%0d) exp=%0d got=%0d", cx,cy,ex_med,median_pixel);
                    errors = errors + 1;
                end
            end

            if (s_valid) begin
                cx = sx;
                cy = sy;
                sobel_count = sobel_count + 1;
                ex_gx = (image[cy-1][cx+1]-image[cy-1][cx-1])
                      + 2*(image[cy][cx+1]-image[cy][cx-1])
                      + (image[cy+1][cx+1]-image[cy+1][cx-1]);
                ex_gy = (image[cy+1][cx-1]-image[cy-1][cx-1])
                      + 2*(image[cy+1][cx]-image[cy-1][cx])
                      + (image[cy+1][cx+1]-image[cy-1][cx+1]);
                ex_mag = (ex_gx < 0 ? -ex_gx : ex_gx) + (ex_gy < 0 ? -ex_gy : ex_gy);
                if (!s_win_valid || gx !== ex_gx || gy !== ex_gy || magnitude !== ex_mag) begin
                    $display("ERROR Sobel center=(%0d,%0d) exp gx=%0d gy=%0d mag=%0d got gx=%0d gy=%0d mag=%0d valid=%b",
                             cx,cy,ex_gx,ex_gy,ex_mag,gx,gy,magnitude,s_win_valid);
                    errors = errors + 1;
                end
            end

            if (t_valid) begin
                cx = tx;
                cy = ty;
                threshold_count = threshold_count + 1;
                ex_gx = (image[cy-1][cx+1]-image[cy-1][cx-1])
                      + 2*(image[cy][cx+1]-image[cy][cx-1])
                      + (image[cy+1][cx+1]-image[cy+1][cx-1]);
                ex_gy = (image[cy+1][cx-1]-image[cy-1][cx-1])
                      + 2*(image[cy+1][cx]-image[cy-1][cx])
                      + (image[cy+1][cx+1]-image[cy-1][cx+1]);
                ex_mag = (ex_gx < 0 ? -ex_gx : ex_gx) + (ex_gy < 0 ? -ex_gy : ex_gy);
                if (!t_win_valid || t_magnitude !== ex_mag[10:0] || edge_bit !== (ex_mag >= 100)) begin
                    $display("ERROR threshold center=(%0d,%0d) exp_mag=%0d got_mag=%0d edge=%b", cx,cy,ex_mag,t_magnitude,edge_bit);
                    errors = errors + 1;
                end
                if (t_eol) threshold_eol_count = threshold_eol_count + 1;
            end

            if (o_valid) begin
                overlay_count = overlay_count + 1;
                cx = ox;
                cy = oy;
                ex_gx = (image[cy-1][cx+1]-image[cy-1][cx-1])
                      + 2*(image[cy][cx+1]-image[cy][cx-1])
                      + (image[cy+1][cx+1]-image[cy+1][cx-1]);
                ex_gy = (image[cy+1][cx-1]-image[cy-1][cx-1])
                      + 2*(image[cy+1][cx]-image[cy-1][cx])
                      + (image[cy+1][cx+1]-image[cy-1][cx+1]);
                ex_mag = (ex_gx < 0 ? -ex_gx : ex_gx) + (ex_gy < 0 ? -ex_gy : ex_gy);
                if (!o_win_valid || o_edge !== (ex_mag >= 100) ||
                    o_rgb !== ((ex_mag >= 100) ? 24'hFF0000 : 24'h112233)) begin
                    $display("ERROR RGB888 overlay x=%0d y=%0d exp_edge=%b got_edge=%b rgb=%h", ox, oy, (ex_mag >= 100), o_edge, o_rgb);
                    errors = errors + 1;
                end
            end

            if (o565_valid) begin
                overlay565_count = overlay565_count + 1;
                cx = o565_x;
                cy = o565_y;
                ex_gx = (image[cy-1][cx+1]-image[cy-1][cx-1])
                      + 2*(image[cy][cx+1]-image[cy][cx-1])
                      + (image[cy+1][cx+1]-image[cy+1][cx-1]);
                ex_gy = (image[cy+1][cx-1]-image[cy-1][cx-1])
                      + 2*(image[cy+1][cx]-image[cy-1][cx])
                      + (image[cy+1][cx+1]-image[cy-1][cx+1]);
                ex_mag = (ex_gx < 0 ? -ex_gx : ex_gx) + (ex_gy < 0 ? -ex_gy : ex_gy);
                if (!o565_win_valid || o565_edge !== (ex_mag >= 100) ||
                    o565_rgb !== ((ex_mag >= 100) ? 16'hF800 : 16'h1234)) begin
                    $display("ERROR RGB565 overlay x=%0d y=%0d exp_edge=%b got_edge=%b rgb=%h", o565_x, o565_y, (ex_mag >= 100), o565_edge, o565_rgb);
                    errors = errors + 1;
                end
            end

            if (e8_valid) begin
                edge8_count = edge8_count + 1;
                cx = e8_x;
                cy = e8_y;
                ex_gx = (image[cy-1][cx+1]-image[cy-1][cx-1])
                      + 2*(image[cy][cx+1]-image[cy][cx-1])
                      + (image[cy+1][cx+1]-image[cy+1][cx-1]);
                ex_gy = (image[cy+1][cx-1]-image[cy-1][cx-1])
                      + 2*(image[cy+1][cx]-image[cy-1][cx])
                      + (image[cy+1][cx+1]-image[cy-1][cx+1]);
                ex_mag = (ex_gx < 0 ? -ex_gx : ex_gx) + (ex_gy < 0 ? -ex_gy : ex_gy);
                if (!e8_win_valid || e8_edge !== (ex_mag >= 100) ||
                    e8_pixel !== ((ex_mag >= 100) ? 8'hFF : 8'h00)) begin
                    $display("ERROR edge8 x=%0d y=%0d exp=%b/%h got=%b/%h", e8_x,e8_y,(ex_mag>=100),((ex_mag>=100)?8'hFF:8'h00),e8_edge,e8_pixel);
                    errors = errors + 1;
                end
            end
        end
    end
endmodule
