`timescale 1ns/1ps
// One fixed-raster binary operator. Exactly two historical rows feed a3x3
// window; three arithmetic registers follow the two window registers. The
// originalRGB and sync traverse HT+6 delay stages plus this output register.
// OP0: majority>=5/9. OP1: inner boundary, centre1 but not all nine pixels1.
module case4_change_binary_raster #(
    parameter integer W=1920,H=1080,HT=2200,OP=0,
    parameter integer XB=$clog2(W),YB=$clog2(H)
)(
    input wire clk,rst,in_hs,in_vs,in_de,
    input wire [23:0] in_rgb,
    input wire in_mask,
    output reg out_hs,out_vs,out_de,
    output reg [23:0] out_rgb,
    output reg out_mask
);
    wire [XB-1:0] x,wx;
    wire [YB-1:0] y,wy;
    wire wv,p00,p01,p02,p10,p11,p12,p20,p21,p22;
    case4_raster_xy #(.W(W),.H(H)) xy(clk,rst,in_vs,in_de,x,y);
    case4_window3x3 #(.DATA_BITS(1),.IMG_WIDTH(W),.IMG_HEIGHT(H)) win(
        .clk(clk),.rst(rst),.in_valid(in_de&&in_vs),.in_x(x),.in_y(y),.in_pixel(in_mask),
        .out_valid(wv),.out_x(wx),.out_y(wy),
        .p00(p00),.p01(p01),.p02(p02),.p10(p10),.p11(p11),.p12(p12),
        .p20(p20),.p21(p21),.p22(p22));
    reg [1:0] row0,row1,row2;
    reg [3:0] sum;
    reg centre0,centre1,result;
    reg [2:0] valid;
    // A complete two-operator neighbourhood needs a2-pixel margin. Suppress
    // this outer margin rather than treating absent frame pixels as changes.
    wire accepted=wv&&((OP==0)||(wx>=2&&wx<W-2&&wy>=2&&wy<H-2));
    always @(posedge clk) begin
        if(rst) begin
            row0<=0;row1<=0;row2<=0;sum<=0;
            centre0<=0;centre1<=0;result<=0;valid<=0;
        end else begin
            row0<={1'b0,p00}+{1'b0,p01}+{1'b0,p02};
            row1<={1'b0,p10}+{1'b0,p11}+{1'b0,p12};
            row2<={1'b0,p20}+{1'b0,p21}+{1'b0,p22};
            sum<={2'b0,row0}+{2'b0,row1}+{2'b0,row2};
            centre0<=p11;centre1<=centre0;
            result<=(OP==0)?(sum>=5):(centre1&&sum!=9);
            valid<={valid[1:0],accepted};
        end
    end
    wire [26:0] delayed;
    wire ready;
    case4_raster_delay #(.WIDTH(27),.STAGES(HT+6)) metadata(
        clk,rst,{in_hs,in_vs,in_de,in_rgb},delayed,ready);
    always @(posedge clk) begin
        if(rst||!ready) begin out_hs<=1;out_vs<=1;out_de<=0;out_rgb<=0;out_mask<=0;end
        else begin
            {out_hs,out_vs,out_de}<=delayed[26:24];
            out_rgb<=delayed[23:0];
            out_mask<=delayed[24]&&delayed[25]&&valid[2]&&result;
        end
    end
endmodule

// Keep original selected-frameRGB everywhere except the cleaned change-region
// contour, drawn red. No filled yellow/red regions and no modification of the
// region interior. Inputmask must be zero outsideCOMPARE; latency never changes
// between modes. Standard raster requires W contiguous active pixels per line.
// Two operators have2*(HT+7) registered stages: a sample at edgeN is visible
// after edgeN+2*HT+13. Native1080 has4414 stages (29.657us at148.8MHz), II=1.
module case4_change_contour #(
    parameter integer W=1920,H=1080,HT=2200
)(
    input wire clk,rst,in_hs,in_vs,in_de,
    input wire [23:0] in_rgb,
    input wire in_change,
    output wire out_hs,out_vs,out_de,
    output wire [23:0] out_rgb
);
    wire mh,mv,md,majority;
    wire [23:0] mrgb,original;
    wire contour;
    case4_change_binary_raster #(.W(W),.H(H),.HT(HT),.OP(0)) denoise(
        .clk(clk),.rst(rst),.in_hs(in_hs),.in_vs(in_vs),.in_de(in_de),
        .in_rgb(in_rgb),.in_mask(in_change),.out_hs(mh),.out_vs(mv),.out_de(md),
        .out_rgb(mrgb),.out_mask(majority));
    case4_change_binary_raster #(.W(W),.H(H),.HT(HT),.OP(1)) boundary(
        .clk(clk),.rst(rst),.in_hs(mh),.in_vs(mv),.in_de(md),
        .in_rgb(mrgb),.in_mask(majority),.out_hs(out_hs),.out_vs(out_vs),.out_de(out_de),
        .out_rgb(original),.out_mask(contour));
    assign out_rgb=contour?24'hff0000:original;
endmodule
