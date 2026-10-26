`timescale 1ns/1ps
// Insert after the vendor lcd_driver and before rgb2dvi, in clk_pixel domain.
// Fixed raster: IMG_WIDTH active pixels, H_TOTAL clocks per line; active-low
// VSYNC. Left half is gray, right half is Sobel (same original coordinates).
// No scaling: this is a split view across the original image, not two copies.
// All sync/blanking samples are delayed, never replaced with window-valid.
module case4_video_compare #(
    parameter integer IMG_WIDTH=1280, IMG_HEIGHT=720, H_TOTAL=1650,
    parameter integer X_BITS=$clog2(IMG_WIDTH), Y_BITS=$clog2(IMG_HEIGHT),
    parameter integer BYPASS=0
) (
    input wire clk, rst,
    input wire in_hs, in_vs, in_de,
    input wire [23:0] in_rgb,
    input wire [10:0] threshold,
    output wire out_hs, out_vs, out_de,
    output wire [23:0] out_rgb
);
    reg [X_BITS-1:0] x;
    reg [Y_BITS-1:0] y;
    always @(posedge clk) begin
        if (rst || !in_vs) begin x<=0; y<=0; end
        else if (in_de) begin
            if (x == IMG_WIDTH-1) begin
                x<=0;
                y <= y == IMG_HEIGHT-1 ? 0 : y+1'b1;
            end else x<=x+1'b1;
        end
    end
    wire gv;
    wire [7:0] gray;
    wire [X_BITS-1:0] gx;
    wire [Y_BITS-1:0] gy;
    gray_rgb_stream #(.PIXEL_FORMAT(1),.X_W(X_BITS),.Y_W(Y_BITS)) u_gray (
        .clk(clk),.rst(rst),.in_valid(in_de && in_vs),
        .in_sof(x==0 && y==0),.in_eol(x==IMG_WIDTH-1),
        .in_eof(x==IMG_WIDTH-1 && y==IMG_HEIGHT-1),
        .in_x(x),.in_y(y),.pixel_in(in_rgb),
        .m_valid(gv),.m_sof(),.m_eol(),.m_eof(),.m_x(gx),.m_y(gy),
        .m_gray(gray),.m_acc()
    );
    reg hs_g,vs_g,de_g,left_g;
    always @(posedge clk) begin
        if (rst) begin hs_g<=1; vs_g<=1; de_g<=0; left_g<=0; end
        else begin hs_g<=in_hs; vs_g<=in_vs; de_g<=in_de; left_g<=x<IMG_WIDTH/2; end
    end
    wire wv;
    wire [X_BITS-1:0] wx;
    wire [Y_BITS-1:0] wy;
    wire [7:0] p00,p01,p02,p10,p11,p12,p20,p21,p22;
    window3x3_gray_sync #(.IMG_WIDTH(IMG_WIDTH),.IMG_HEIGHT(IMG_HEIGHT),
        .X_BITS(X_BITS),.Y_BITS(Y_BITS)) u_window (
        .clk(clk),.rst(rst),.in_valid(gv),.in_x(gx),.in_y(gy),.in_pixel(gray),
        .out_valid(wv),.out_x(wx),.out_y(wy),
        .p00(p00),.p01(p01),.p02(p02),.p10(p10),.p11(p11),.p12(p12),
        .p20(p20),.p21(p21),.p22(p22)
    );
    wire sv,swv;
    wire [10:0] magnitude;
    case4_sobel3x3 #(.X_W(X_BITS),.Y_W(Y_BITS)) u_sobel (
        .clk(clk),.rst_n(!rst),.in_valid(wv),.in_win_valid(wv),
        .in_sof(1'b0),.in_eol(1'b0),.in_eof(1'b0),.in_x(wx),.in_y(wy),.in_rgb(24'd0),
        .p00(p00),.p01(p01),.p02(p02),.p10(p10),.p11(p11),.p12(p12),
        .p20(p20),.p21(p21),.p22(p22),
        .out_valid(sv),.out_win_valid(swv),.out_sof(),.out_eol(),.out_eof(),
        .out_x(),.out_y(),.out_rgb(),.out_gx(),.out_gy(),.out_magnitude(magnitude)
    );
    wire ev,ewv,edge_bit;
    case4_edge_threshold #(.X_W(X_BITS),.Y_W(Y_BITS)) u_threshold (
        .clk(clk),.rst_n(!rst),.in_valid(sv),.in_win_valid(swv),
        .in_sof(1'b0),.in_eol(1'b0),.in_eof(1'b0),
        .in_x({X_BITS{1'b0}}),.in_y({Y_BITS{1'b0}}),.in_rgb(24'd0),
        .in_magnitude(magnitude),.threshold(threshold),
        .out_valid(ev),.out_win_valid(ewv),.out_sof(),.out_eol(),.out_eof(),
        .out_x(),.out_y(),.out_rgb(),.out_magnitude(),.out_edge(edge_bit)
    );
    // Window is centred one line + one pixel behind the arriving sample.
    // After gray: RAM read/window=2, Sobel=3, threshold=1 registers.
    // Circular RAM captures gray at the following edge; DELAY is the number
    // of edges from capture to read. Separate addresses avoid RAM collisions.
    localparam integer DELAY=H_TOTAL+6;
    localparam integer DEPTH=DELAY+1;
    localparam integer A_BITS=$clog2(DEPTH);
    reg [11:0] raster [0:DEPTH-1];
    reg [A_BITS-1:0] ptr;
    wire [A_BITS-1:0] next_ptr = ptr==DEPTH-1 ? 0 : ptr+1'b1;
    reg [11:0] delayed;
    reg [A_BITS:0] filled;
    always @(posedge clk) begin
        if (!rst) begin
            raster[ptr] <= {hs_g,vs_g,de_g,left_g,gray};
            delayed <= raster[next_ptr];
        end
    end
    always @(posedge clk) begin
        if (rst) begin ptr<=0; filled<=0; end
        else begin
            ptr<=next_ptr;
            if (filled < DEPTH) filled<=filled+1'b1;
        end
    end
    reg hs_o,vs_o,de_o;
    reg [23:0] rgb_o;
    wire [7:0] display_gray = delayed[8] ? delayed[7:0] :
                                  (ev && ewv && edge_bit ? 8'hff : 8'h00);
    always @(posedge clk) begin
        if (rst || filled < DEPTH) begin hs_o<=1;vs_o<=1;de_o<=0;rgb_o<=0;end
        else begin
            hs_o<=delayed[11];vs_o<=delayed[10];de_o<=delayed[9];
            rgb_o<=delayed[9] ? {3{display_gray}} : 24'd0;
        end
    end
    assign out_hs=BYPASS ? in_hs : hs_o;
    assign out_vs=BYPASS ? in_vs : vs_o;
    assign out_de=BYPASS ? in_de : de_o;
    assign out_rgb=BYPASS ? in_rgb : rgb_o;
endmodule
