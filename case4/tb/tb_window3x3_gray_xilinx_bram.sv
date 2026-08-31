`timescale 1ns/1ps

// Cycle-level check for the Xilinx BRAM-backed window.  The image and
// scoreboard are intentionally the same style as tb_image_operators.sv so a
// vendor-memory replacement can be compared against the reference window.
module tb_window3x3_gray_xilinx_bram;
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

    wire out_valid, out_sof, out_eol, out_eof;
    wire [XB-1:0] out_x;
    wire [YB-1:0] out_y;
    wire [7:0] p00, p01, p02, p10, p11, p12, p20, p21, p22;

    window3x3_gray_xilinx_bram #(
        .IMG_WIDTH(W), .IMG_HEIGHT(H), .PIXEL_BITS(8),
        .X_BITS(XB), .Y_BITS(YB)
    ) dut (
        .clk(clk), .rst(rst), .in_valid(in_valid), .in_sof(in_sof),
        .in_eol(in_eol), .in_eof(in_eof), .in_x(in_x), .in_y(in_y),
        .in_pixel(in_pixel), .out_valid(out_valid), .out_sof(out_sof),
        .out_eol(out_eol), .out_eof(out_eof), .out_x(out_x), .out_y(out_y),
        .out_p00(p00), .out_p01(p01), .out_p02(p02), .out_p10(p10),
        .out_p11(p11), .out_p12(p12), .out_p20(p20), .out_p21(p21),
        .out_p22(p22)
    );

    integer ix, iy, cx, cy, errors, count;
    integer expected;

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
                in_pixel = image[iy][ix];
            end
        end
        repeat (8) begin
            @(negedge clk);
            in_valid = 1'b0;
            in_sof = 1'b0;
            in_eol = 1'b0;
            in_eof = 1'b0;
        end
        @(posedge clk);
        #2;
        if (count != (W-2)*(H-2)) begin
            $display("ERROR BRAM window count=%0d expected=%0d", count,
                     (W-2)*(H-2));
            errors = errors + 1;
        end
        if (errors == 0)
            $display("TB_WINDOW_XILINX_BRAM PASS: taps/coords/sideband");
        else
            $fatal(1, "TB_WINDOW_XILINX_BRAM FAIL errors=%0d", errors);
        $finish;
    end

    always @(posedge clk) begin
        #1;
        if (!rst && out_valid) begin
            cx = out_x;
            cy = out_y;
            count = count + 1;
            if (out_x !== cx || out_y !== cy ||
                p00 !== image[cy-1][cx-1] || p01 !== image[cy-1][cx] ||
                p02 !== image[cy-1][cx+1] || p10 !== image[cy][cx-1] ||
                p11 !== image[cy][cx]     || p12 !== image[cy][cx+1] ||
                p20 !== image[cy+1][cx-1] || p21 !== image[cy+1][cx] ||
                p22 !== image[cy+1][cx+1]) begin
                $display("ERROR BRAM window (%0d,%0d): got %0d %0d %0d / %0d %0d %0d / %0d %0d %0d",
                         cx, cy, p00,p01,p02,p10,p11,p12,p20,p21,p22);
                errors = errors + 1;
            end
            if ((cx == 1 && cy == 1) && !out_sof) begin
                $display("ERROR missing BRAM SOF");
                errors = errors + 1;
            end
            if ((cx == W-2) && !out_eol) begin
                $display("ERROR missing BRAM EOL at y=%0d", cy);
                errors = errors + 1;
            end
            if ((cx == W-2 && cy == H-2) && !out_eof) begin
                $display("ERROR missing BRAM EOF");
                errors = errors + 1;
            end
        end
    end
endmodule
