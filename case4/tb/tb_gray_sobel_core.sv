`timescale 1ns/1ps

module tb_gray_sobel_core;
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
    logic [23:0] in_pixel;
    wire out_valid, out_win_valid, out_sof, out_eol, out_eof, out_edge;
    wire [XB-1:0] out_x;
    wire [YB-1:0] out_y;
    wire signed [11:0] out_gx, out_gy;
    wire [10:0] out_magnitude;

    case4_gray_sobel_core #(
        .PIXEL_FORMAT(1), .IMG_WIDTH(W), .IMG_HEIGHT(H),
        .X_BITS(XB), .Y_BITS(YB), .MAG_W(11)
    ) dut (
        .clk(clk), .rst(rst), .in_valid(in_valid), .in_sof(in_sof),
        .in_eol(in_eol), .in_eof(in_eof), .in_x(in_x), .in_y(in_y),
        .in_pixel(in_pixel), .threshold(11'd100),
        .out_valid(out_valid), .out_win_valid(out_win_valid),
        .out_sof(out_sof), .out_eol(out_eol), .out_eof(out_eof),
        .out_x(out_x), .out_y(out_y), .out_gx(out_gx), .out_gy(out_gy),
        .out_magnitude(out_magnitude), .out_edge(out_edge)
    );

    logic [7:0] image [0:H-1][0:W-1];
    integer ix, iy, cx, cy;
    integer ex_gx, ex_gy, ex_mag;
    integer errors, count;

    initial begin
        for (iy = 0; iy < H; iy = iy + 1)
            for (ix = 0; ix < W; ix = ix + 1)
                image[iy][ix] = (ix*17 + iy*31 + ((ix*iy)%5)*7 + 3) & 255;

        errors = 0;
        count = 0;
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
                in_pixel = {image[iy][ix], image[iy][ix], image[iy][ix]};
            end
        end
        repeat (10) begin
            @(negedge clk);
            in_valid = 1'b0;
            in_sof = 1'b0;
            in_eol = 1'b0;
            in_eof = 1'b0;
        end
        @(posedge clk);
        #2;
        if (count != (W-2)*(H-2)) begin
            $display("ERROR core count=%0d expected=%0d", count, (W-2)*(H-2));
            errors = errors + 1;
        end
        if (errors == 0)
            $display("TB_GRAY_SOBEL_CORE PASS");
        else
            $fatal(1, "TB_GRAY_SOBEL_CORE FAIL errors=%0d", errors);
        $finish;
    end

    always @(posedge clk) begin
        #1;
        if (!rst && out_valid) begin
            cx = out_x;
            cy = out_y;
            count = count + 1;
            ex_gx = (image[cy-1][cx+1]-image[cy-1][cx-1])
                  + 2*(image[cy][cx+1]-image[cy][cx-1])
                  + (image[cy+1][cx+1]-image[cy+1][cx-1]);
            ex_gy = (image[cy+1][cx-1]-image[cy-1][cx-1])
                  + 2*(image[cy+1][cx]-image[cy-1][cx])
                  + (image[cy+1][cx+1]-image[cy-1][cx+1]);
            ex_mag = (ex_gx < 0 ? -ex_gx : ex_gx) + (ex_gy < 0 ? -ex_gy : ex_gy);
            if (!out_win_valid || out_gx !== ex_gx || out_gy !== ex_gy ||
                out_magnitude !== ex_mag[10:0] || out_edge !== (ex_mag >= 100)) begin
                $display("ERROR core (%0d,%0d) exp gx=%0d gy=%0d mag=%0d edge=%b got gx=%0d gy=%0d mag=%0d edge=%b",
                         cx,cy,ex_gx,ex_gy,ex_mag,(ex_mag>=100),out_gx,out_gy,out_magnitude,out_edge);
                errors = errors + 1;
            end
        end
    end
endmodule
