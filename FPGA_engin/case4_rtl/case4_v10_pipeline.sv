`timescale 1ns/1ps
module case4_v10_pipeline #(
    parameter W=1280,H=720,HT=1650,XB=$clog2(W),YB=$clog2(H)
)(
    input wire clk,rst,in_hs,in_vs,in_de,input wire [23:0] in_rgb,
    input wire [1:0] median_mode,input wire canny_enable,scharr,input wire [10:0] threshold,
    input wire [23:0] process_rgb,input wire [7:0] in_edges,output wire [7:0] out_edges,
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
    case4_raster_delay #(.WIDTH(8),.STAGES(1+4*(HT+7))) edge_delay(clk,rst,in_edges,out_edges,edge_ready);
    always @(posedge clk) begin
        if(rst)begin gh<=1;gs<=1;gd<=0;rgb<=0;end
        else begin gh<=in_hs;gs<=in_vs;gd<=in_de;rgb<=in_rgb;end
    end
    wire mh,ms,md,ah,as_,ad,sh,ss,sd;
    wire [7:0] mp,ap;wire [31:0] mm,am,sm;wire [13:0] sf;
    case4_v10_raster_filter #(.W(W),.H(H),.HT(HT),.OP(0)) med(clk,rst,median_mode,gh,gs,gd,gray,{rgb,display_gray},mh,ms,md,mp,mm);
    case4_v10_raster_filter #(.W(W),.H(H),.HT(HT),.OP(1)) gauss(clk,rst,median_mode,mh,ms,md,mp,mm,ah,as_,ad,ap,am);
    case4_v9_gradient #(.W(W),.H(H),.HT(HT)) grad(clk,rst,ah,as_,ad,ap,am,threshold,scharr,sh,ss,sd,sf,sm);
    case4_stable_nms #(.W(W),.H(H),.HT(HT)) nms(clk,rst,sh,ss,sd,sf,sm,threshold,out_hs,out_vs,out_de,out_class,out_sobel,out_meta,out_magnitude);
endmodule
