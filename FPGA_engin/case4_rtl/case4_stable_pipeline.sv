`timescale 1ns/1ps
// V6: independent processing RGB with visible-frame metadata; Gaussian in every edge mode.
module case4_stable_nms #(
    parameter W=1280,H=720,HT=1650,XB=$clog2(W),YB=$clog2(H)
)(
    input wire clk,rst,in_hs,in_vs,in_de,input wire [13:0] in_feature,
    input wire [31:0] in_meta,input wire [10:0] threshold,
    output reg out_hs,out_vs,out_de,output reg [1:0] out_class,
    output reg out_sobel,output reg [31:0] out_meta,output reg [10:0] out_magnitude
);
    wire [XB-1:0] x,wx;wire [YB-1:0] y,wy;
    case4_raster_xy #(.W(W),.H(H)) xy(clk,rst,in_vs,in_de,x,y);
    wire wv;wire [12:0] p00,p01,p02,p10,p11,p12,p20,p21,p22;
    case4_window3x3 #(.DATA_BITS(13),.IMG_WIDTH(W),.IMG_HEIGHT(H)) win(
        .clk(clk),.rst(rst),.in_valid(in_de&&in_vs),.in_x(x),.in_y(y),.in_pixel(in_feature[12:0]),
        .out_valid(wv),.out_x(wx),.out_y(wy),
        .p00(p00),.p01(p01),.p02(p02),.p10(p10),.p11(p11),.p12(p12),.p20(p20),.p21(p21),.p22(p22));
    reg [10:0] before_mag,after_mag;
    always @* begin
        case(p11[12:11])
            0: begin before_mag=p10[10:0];after_mag=p12[10:0];end
            1: begin before_mag=p00[10:0];after_mag=p22[10:0];end
            2: begin before_mag=p01[10:0];after_mag=p21[10:0];end
            default: begin before_mag=p02[10:0];after_mag=p20[10:0];end
        endcase
    end
    wire keep=wv && p11[10:0]!=0 && p11[10:0]>=before_mag && p11[10:0]>after_mag;
    wire [1:0] decision=!keep?2'b00:p11[10:0]>=threshold?2'b11:p11[10:0]>=(threshold>>1)?2'b01:2'b00;
    // Spatial hysteresis: retain a near-threshold center only when its
    // neighbourhood contains strong gradient support. No temporal feedback.
    wire [10:0] low_sobel=threshold-(threshold>>2);
    wire strong_neighbor=p00[10:0]>=threshold||p01[10:0]>=threshold||p02[10:0]>=threshold||
        p10[10:0]>=threshold||p12[10:0]>=threshold||p20[10:0]>=threshold||p21[10:0]>=threshold||p22[10:0]>=threshold;
    wire supported=wv && p11[10:0]!=0 && (p11[10:0]>=threshold || (p11[10:0]>=low_sobel && strong_neighbor));
    reg [2:0] sobel_delay;
    reg [1:0] c0,c1,c2;reg [10:0] mag0,mag1,mag2;
    always @(posedge clk) begin
        if(rst) begin c0<=0;c1<=0;c2<=0;sobel_delay<=0;mag0<=0;mag1<=0;mag2<=0;end
        else begin c0<=decision;c1<=c0;c2<=c1;mag0<=wv?p11[10:0]:0;mag1<=mag0;mag2<=mag1;sobel_delay<={sobel_delay[1:0],supported};end
    end
    wire [48:0] delayed;wire ready;
    case4_raster_delay #(.WIDTH(49),.STAGES(HT+6)) delay(clk,rst,{in_hs,in_vs,in_de,in_feature,in_meta},delayed,ready);
    always @(posedge clk) begin
        if(rst||!ready) begin out_hs<=1;out_vs<=1;out_de<=0;out_meta<=0;out_class<=0;out_sobel<=0;out_magnitude<=0;end
        else begin
            {out_hs,out_vs,out_de}<=delayed[48:46];out_meta<=delayed[31:0];
            out_class<=c2;
            out_sobel<=sobel_delay[2];out_magnitude<=mag2;
        end
    end
endmodule


module case4_stable_pipeline #(
    parameter W=1280,H=720,HT=1650,XB=$clog2(W),YB=$clog2(H)
)(
    input wire clk,rst,in_hs,in_vs,in_de,input wire [23:0] in_rgb,
    input wire median_enable,canny_enable,input wire [10:0] threshold,
    input wire [23:0] process_rgb,input wire in_edge,output wire out_edge,
    output wire out_hs,out_vs,out_de,output wire [31:0] out_meta,
    output wire out_sobel,output wire [1:0] out_class,output wire [10:0] out_magnitude
);
    wire [XB-1:0] x;wire [YB-1:0] y;
    case4_raster_xy #(.W(W),.H(H)) xy(clk,rst,in_vs,in_de,x,y);
    wire [7:0] gray;wire gv;
    gray_rgb_stream #(.PIXEL_FORMAT(1),.X_W(XB),.Y_W(YB)) grayconv(
        .clk(clk),.rst(rst),.in_valid(in_de&&in_vs),.in_sof(x==0&&y==0),.in_eol(x==W-1),.in_eof(x==W-1&&y==H-1),
        .in_x(x),.in_y(y),.pixel_in(process_rgb),.m_valid(gv),.m_sof(),.m_eol(),.m_eof(),.m_x(),.m_y(),.m_gray(gray),.m_acc());
    reg gh,gs,gd;reg [23:0] rgb;
    wire [7:0] display_gray;
    gray_rgb_stream #(.PIXEL_FORMAT(1),.X_W(XB),.Y_W(YB)) display_grayconv(
        .clk(clk),.rst(rst),.in_valid(in_de&&in_vs),.in_sof(x==0&&y==0),.in_eol(x==W-1),.in_eof(x==W-1&&y==H-1),
        .in_x(x),.in_y(y),.pixel_in(in_rgb),.m_valid(),.m_sof(),.m_eol(),.m_eof(),.m_x(),.m_y(),.m_gray(display_gray),.m_acc());
    wire edge_ready;
    case4_raster_delay #(.WIDTH(1),.STAGES(1+4*(HT+7))) edge_delay(clk,rst,in_edge,out_edge,edge_ready);
    always @(posedge clk) begin
        if(rst)begin gh<=1;gs<=1;gd<=0;rgb<=0;end
        else begin gh<=in_hs;gs<=in_vs;gd<=in_de;rgb<=in_rgb;end
    end
    wire mh,ms,md,ah,as_,ad,sh,ss,sd;
    wire [7:0] mp,ap;wire [31:0] mm,am,sm;wire [13:0] sf;
    case4_raster_filter #(.W(W),.H(H),.HT(HT),.OP(0)) med(clk,rst,median_enable,gh,gs,gd,gray,{rgb,display_gray},mh,ms,md,mp,mm);
    case4_raster_filter #(.W(W),.H(H),.HT(HT),.OP(1)) gauss(clk,rst,1'b1,mh,ms,md,mp,mm,ah,as_,ad,ap,am);
    case4_raster_gradient #(.W(W),.H(H),.HT(HT)) grad(clk,rst,ah,as_,ad,ap,am,threshold,sh,ss,sd,sf,sm);
    case4_stable_nms #(.W(W),.H(H),.HT(HT)) nms(clk,rst,sh,ss,sd,sf,sm,threshold,out_hs,out_vs,out_de,out_class,out_sobel,out_meta,out_magnitude);
endmodule
