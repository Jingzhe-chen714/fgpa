`timescale 1ns/1ps
// Fixed-raster filter, preserving complete sync and original RGB/gray metadata.
// OP0 median sorting network, OP1 separable 3x3 Gaussian [1 2 1]^T[1 2 1]/16.
// Borders pass the unfiltered centre pixel. Both operators have three stages.
module case4_raster_filter #(
    parameter W=1280,H=720,HT=1650,OP=0,XB=$clog2(W),YB=$clog2(H)
)(
    input wire clk,rst,enable,in_hs,in_vs,in_de,
    input wire [7:0] in_pixel,input wire [31:0] in_meta,
    output reg out_hs,out_vs,out_de,output reg [7:0] out_pixel,
    output reg [31:0] out_meta
);
    wire [XB-1:0] x,wx;wire [YB-1:0] y,wy;
    case4_raster_xy #(.W(W),.H(H)) xy(clk,rst,in_vs,in_de,x,y);
    wire wv;wire [7:0] p00,p01,p02,p10,p11,p12,p20,p21,p22;
    case4_window3x3 #(.IMG_WIDTH(W),.IMG_HEIGHT(H)) win(
        .clk(clk),.rst(rst),.in_valid(in_de&&in_vs),.in_x(x),.in_y(y),.in_pixel(in_pixel),
        .out_valid(wv),.out_x(wx),.out_y(wy),
        .p00(p00),.p01(p01),.p02(p02),.p10(p10),.p11(p11),.p12(p12),.p20(p20),.p21(p21),.p22(p22));
    wire fv;wire [7:0] filtered;
    generate if(OP==0) begin:g_med
        median3x3_u8 #(.X_BITS(XB),.Y_BITS(YB)) median(
            .clk(clk),.rst(rst),.in_valid(wv),.in_sof(1'b0),.in_eol(1'b0),.in_eof(1'b0),.in_x(wx),.in_y(wy),
            .in_p00(p00),.in_p01(p01),.in_p02(p02),.in_p10(p10),.in_p11(p11),.in_p12(p12),
            .in_p20(p20),.in_p21(p21),.in_p22(p22),.out_valid(fv),.out_sof(),.out_eol(),.out_eof(),.out_x(),.out_y(),.out_pixel(filtered));
    end else begin:g_gauss
        reg [9:0] row0,row1,row2;reg [11:0] sum;reg [7:0] result;reg [2:0] valid;
        always @(posedge clk) begin
            if(rst) begin row0<=0;row1<=0;row2<=0;sum<=0;result<=0;valid<=0;end
            else begin
                row0<={2'b0,p00}+{1'b0,p01,1'b0}+{2'b0,p02};
                row1<={2'b0,p10}+{1'b0,p11,1'b0}+{2'b0,p12};
                row2<={2'b0,p20}+{1'b0,p21,1'b0}+{2'b0,p22};
                sum<={2'b0,row0}+{1'b0,row1,1'b0}+{2'b0,row2}+12'd8;
                result<=sum[11:4];valid<={valid[1:0],wv};
            end
        end
        assign fv=valid[2];assign filtered=result;
    end endgenerate
    wire [42:0] delayed;wire ready;
    case4_raster_delay #(.WIDTH(43),.STAGES(HT+6)) delay(
        clk,rst,{in_hs,in_vs,in_de,in_pixel,in_meta},delayed,ready);
    always @(posedge clk) begin
        if(rst||!ready) begin out_hs<=1;out_vs<=1;out_de<=0;out_meta<=0;out_pixel<=0;end
        else begin
            {out_hs,out_vs,out_de}<=delayed[42:40];out_meta<=delayed[31:0];
            out_pixel<=enable&&fv?filtered:delayed[39:32];
        end
    end
endmodule

// Four Sobel stages: partial sums, Gx/Gy, L1 magnitude, threshold.
// Direction quantization is computed alongside the fourth stage.
module case4_raster_gradient #(
    parameter W=1280,H=720,HT=1650,XB=$clog2(W),YB=$clog2(H)
)(
    input wire clk,rst,in_hs,in_vs,in_de,input wire [7:0] in_pixel,input wire [31:0] in_meta,
    input wire [10:0] threshold,
    output reg out_hs,out_vs,out_de,output reg [13:0] out_feature,output reg [31:0] out_meta
);
    wire [XB-1:0] x,wx;wire [YB-1:0] y,wy;
    case4_raster_xy #(.W(W),.H(H)) xy(clk,rst,in_vs,in_de,x,y);
    wire wv;wire [7:0] p00,p01,p02,p10,p11,p12,p20,p21,p22;
    case4_window3x3 #(.IMG_WIDTH(W),.IMG_HEIGHT(H)) win(
        .clk(clk),.rst(rst),.in_valid(in_de&&in_vs),.in_x(x),.in_y(y),.in_pixel(in_pixel),
        .out_valid(wv),.out_x(wx),.out_y(wy),
        .p00(p00),.p01(p01),.p02(p02),.p10(p10),.p11(p11),.p12(p12),.p20(p20),.p21(p21),.p22(p22));
    wire sv,swv;wire [10:0] mag;wire signed [11:0] dx,dy;
    case4_sobel3x3 #(.X_W(XB),.Y_W(YB)) sobel(
        .clk(clk),.rst_n(!rst),.in_valid(wv),.in_win_valid(wv),.in_sof(1'b0),.in_eol(1'b0),.in_eof(1'b0),
        .in_x(wx),.in_y(wy),.in_rgb(24'd0),
        .p00(p00),.p01(p01),.p02(p02),.p10(p10),.p11(p11),.p12(p12),.p20(p20),.p21(p21),.p22(p22),
        .out_valid(sv),.out_win_valid(swv),.out_sof(),.out_eol(),.out_eof(),.out_x(),.out_y(),.out_rgb(),
        .out_gx(dx),.out_gy(dy),.out_magnitude(mag));
    wire [11:0] ax=dx[11]?$unsigned(-dx):$unsigned(dx);
    wire [11:0] ay=dy[11]?$unsigned(-dy):$unsigned(dy);
    wire [19:0] ax106=({8'b0,ax}<<6)+({8'b0,ax}<<5)+({8'b0,ax}<<3)+({8'b0,ax}<<1);
    wire [19:0] ay106=({8'b0,ay}<<6)+({8'b0,ay}<<5)+({8'b0,ay}<<3)+({8'b0,ay}<<1);
    wire [1:0] direction=({ay,8'b0}<=ax106)?2'd0:({ax,8'b0}<=ay106)?2'd2:(dx[11]==dy[11]?2'd1:2'd3);
    wire [34:0] delayed;wire ready;
    // Window(2)+Sobel(3), then registered feature and raster output together.
    case4_raster_delay #(.WIDTH(35),.STAGES(HT+6)) delay(clk,rst,{in_hs,in_vs,in_de,in_meta},delayed,ready);
    always @(posedge clk) begin
        if(rst||!ready) begin out_hs<=1;out_vs<=1;out_de<=0;out_meta<=0;out_feature<=0;end
        else begin
            {out_hs,out_vs,out_de}<=delayed[34:32];out_meta<=delayed[31:0];
            out_feature<=sv&&swv?{(mag!=0 && mag>=threshold),direction,mag}:14'd0;
        end
    end
endmodule

module case4_raster_nms #(
    parameter W=1280,H=720,HT=1650,XB=$clog2(W),YB=$clog2(H)
)(
    input wire clk,rst,in_hs,in_vs,in_de,input wire [13:0] in_feature,
    input wire [31:0] in_meta,input wire [10:0] threshold,
    output reg out_hs,out_vs,out_de,output reg [1:0] out_class,
    output reg out_sobel,output reg [31:0] out_meta
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
    reg [1:0] c0,c1,c2;
    always @(posedge clk) begin
        if(rst) begin c0<=0;c1<=0;c2<=0;end
        else begin c0<=decision;c1<=c0;c2<=c1;end
    end
    wire [48:0] delayed;wire ready;
    case4_raster_delay #(.WIDTH(49),.STAGES(HT+6)) delay(clk,rst,{in_hs,in_vs,in_de,in_feature,in_meta},delayed,ready);
    always @(posedge clk) begin
        if(rst||!ready) begin out_hs<=1;out_vs<=1;out_de<=0;out_meta<=0;out_class<=0;out_sobel<=0;end
        else begin
            {out_hs,out_vs,out_de}<=delayed[48:46];out_meta<=delayed[31:0];
            out_class<=c2;
            out_sobel<=delayed[45]; // Stage-four decision delayed with its source pixel.
        end
    end
endmodule

module case4_advanced_pipeline #(
    parameter W=1280,H=720,HT=1650,XB=$clog2(W),YB=$clog2(H)
)(
    input wire clk,rst,in_hs,in_vs,in_de,input wire [23:0] in_rgb,
    input wire median_enable,canny_enable,input wire [10:0] threshold,
    output wire out_hs,out_vs,out_de,output wire [31:0] out_meta,
    output wire out_sobel,output wire [1:0] out_class
);
    wire [XB-1:0] x;wire [YB-1:0] y;
    case4_raster_xy #(.W(W),.H(H)) xy(clk,rst,in_vs,in_de,x,y);
    wire [7:0] gray;wire gv;
    gray_rgb_stream #(.PIXEL_FORMAT(1),.X_W(XB),.Y_W(YB)) grayconv(
        .clk(clk),.rst(rst),.in_valid(in_de&&in_vs),.in_sof(x==0&&y==0),.in_eol(x==W-1),.in_eof(x==W-1&&y==H-1),
        .in_x(x),.in_y(y),.pixel_in(in_rgb),.m_valid(gv),.m_sof(),.m_eol(),.m_eof(),.m_x(),.m_y(),.m_gray(gray),.m_acc());
    reg gh,gs,gd;reg [23:0] rgb;
    always @(posedge clk) begin
        if(rst)begin gh<=1;gs<=1;gd<=0;rgb<=0;end
        else begin gh<=in_hs;gs<=in_vs;gd<=in_de;rgb<=in_rgb;end
    end
    wire mh,ms,md,ah,as_,ad,sh,ss,sd;
    wire [7:0] mp,ap;wire [31:0] mm,am,sm;wire [13:0] sf;
    case4_raster_filter #(.W(W),.H(H),.HT(HT),.OP(0)) med(clk,rst,median_enable,gh,gs,gd,gray,{rgb,gray},mh,ms,md,mp,mm);
    case4_raster_filter #(.W(W),.H(H),.HT(HT),.OP(1)) gauss(clk,rst,canny_enable,mh,ms,md,mp,mm,ah,as_,ad,ap,am);
    case4_raster_gradient #(.W(W),.H(H),.HT(HT)) grad(clk,rst,ah,as_,ad,ap,am,threshold,sh,ss,sd,sf,sm);
    case4_raster_nms #(.W(W),.H(H),.HT(HT)) nms(clk,rst,sh,ss,sd,sf,sm,threshold,out_hs,out_vs,out_de,out_class,out_sobel,out_meta);
endmodule
