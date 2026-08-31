`timescale 1ns/1ps

// Small-frame numerical and coordinate scoreboard for the cascaded
// median->Sobel core.  WINDOW_BACKEND=0 is the portable reference; a wrapper
// selects 1 for the Xilinx XPM/BRAM regression.
module tb_gray_median_sobel_core #(
    parameter integer WINDOW_BACKEND = 0
);
    localparam integer W = 8;
    localparam integer H = 6;
    localparam integer XB = 3;
    localparam integer YB = 3;
    localparam integer EXPECTED = (W-4)*(H-4);

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

    case4_gray_median_sobel_core #(
        .PIXEL_FORMAT(1), .IMG_WIDTH(W), .IMG_HEIGHT(H),
        .X_BITS(XB), .Y_BITS(YB), .MAG_W(11),
        .WINDOW_BACKEND(WINDOW_BACKEND)
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
    logic [7:0] med_image [0:H-1][0:W-1];
    integer ix, iy, cx, cy;
    integer ex_gx, ex_gy, ex_mag;
    integer errors, count;

    function automatic integer pix(input logic [7:0] v);
        begin pix = v; end
    endfunction

    function automatic [7:0] median9(
        input integer a0, input integer a1, input integer a2,
        input integer a3, input integer a4, input integer a5,
        input integer a6, input integer a7, input integer a8
    );
        integer a [0:8];
        integer i, j, t;
        begin
            a[0]=a0; a[1]=a1; a[2]=a2; a[3]=a3; a[4]=a4;
            a[5]=a5; a[6]=a6; a[7]=a7; a[8]=a8;
            for (i=0; i<9; i=i+1)
                for (j=i+1; j<9; j=j+1)
                    if (a[j] < a[i]) begin
                        t=a[i]; a[i]=a[j]; a[j]=t;
                    end
            median9 = a[4];
        end
    endfunction

    initial begin
        for (iy = 0; iy < H; iy = iy + 1) begin
            for (ix = 0; ix < W; ix = ix + 1) begin
                image[iy][ix] = (ix*17 + iy*31 + ((ix*iy)%5)*7 + 3) & 255;
                med_image[iy][ix] = 0;
            end
        end
        for (iy = 1; iy < H-1; iy = iy + 1)
            for (ix = 1; ix < W-1; ix = ix + 1)
                med_image[iy][ix] = median9(
                    pix(image[iy-1][ix-1]), pix(image[iy-1][ix]),
                    pix(image[iy-1][ix+1]), pix(image[iy][ix-1]),
                    pix(image[iy][ix]),   pix(image[iy][ix+1]),
                    pix(image[iy+1][ix-1]), pix(image[iy+1][ix]),
                    pix(image[iy+1][ix+1]));

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
        repeat (30) begin
            @(negedge clk);
            in_valid = 1'b0;
            in_sof = 1'b0;
            in_eol = 1'b0;
            in_eof = 1'b0;
        end
        @(posedge clk);
        #2;
        if (count != EXPECTED) begin
            $display("ERROR median/Sobel count=%0d expected=%0d", count, EXPECTED);
            errors = errors + 1;
        end
        if (errors == 0)
            $display("TB_GRAY_MEDIAN_SOBEL_CORE PASS: %0d valid windows backend=%0d", count, WINDOW_BACKEND);
        else
            $fatal(1, "TB_GRAY_MEDIAN_SOBEL_CORE FAIL errors=%0d backend=%0d", errors, WINDOW_BACKEND);
        $finish;
    end

    always @(posedge clk) begin
        #1;
        if (!rst && out_valid) begin
            cx = out_x;
            cy = out_y;
            count = count + 1;
            if (!out_win_valid || cx < 2 || cx > W-3 || cy < 2 || cy > H-3) begin
                $display("ERROR median/Sobel coordinate/valid x=%0d y=%0d win=%b", cx, cy, out_win_valid);
                errors = errors + 1;
            end else begin
                ex_gx = (pix(med_image[cy-1][cx+1])-pix(med_image[cy-1][cx-1]))
                      + 2*(pix(med_image[cy][cx+1])-pix(med_image[cy][cx-1]))
                      + (pix(med_image[cy+1][cx+1])-pix(med_image[cy+1][cx-1]));
                ex_gy = (pix(med_image[cy+1][cx-1])-pix(med_image[cy-1][cx-1]))
                      + 2*(pix(med_image[cy+1][cx])-pix(med_image[cy-1][cx]))
                      + (pix(med_image[cy+1][cx+1])-pix(med_image[cy-1][cx+1]));
                ex_mag = (ex_gx < 0 ? -ex_gx : ex_gx)
                       + (ex_gy < 0 ? -ex_gy : ex_gy);
                if ($signed(out_gx) != ex_gx || $signed(out_gy) != ex_gy ||
                    out_magnitude != ex_mag || out_edge != (ex_mag >= 100)) begin
                    $display("ERROR median/Sobel (%0d,%0d) exp gx=%0d gy=%0d mag=%0d edge=%b got gx=%0d gy=%0d mag=%0d edge=%b",
                        cx, cy, ex_gx, ex_gy, ex_mag, (ex_mag >= 100),
                        out_gx, out_gy, out_magnitude, out_edge);
                    errors = errors + 1;
                end
            end
            if ((cx == 2 && cy == 2) && !out_sof) begin
                $display("ERROR missing median/Sobel SOF");
                errors = errors + 1;
            end
            if ((cx == W-3) && !out_eol) begin
                $display("ERROR missing median/Sobel EOL at y=%0d", cy);
                errors = errors + 1;
            end
            if ((cx == W-3 && cy == H-3) && !out_eof) begin
                $display("ERROR missing median/Sobel EOF");
                errors = errors + 1;
            end
        end
    end
endmodule
