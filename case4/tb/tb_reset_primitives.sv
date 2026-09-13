`timescale 1ns/1ps
// Public-port reset contract for the full Sobel/threshold/overlay chain plus
// the separate RGB565 overlay and binary-to-gray display primitive.
module tb_reset_primitives;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0,iv=0;
    wire pv,pw,ps,pl,pe,pedge,v565,w565,s565,l565,e565,edge565,v8,w8,s8,l8,e8,edge8;
    wire [3:0] px,py,x565,y565,x8,y8;
    wire [23:0] rgb;
    wire [15:0] rgb565;
    wire [7:0] gray8;
    wire signed [11:0] gx,gy;
    wire [10:0] magnitude;
    case4_sobel_edge_pipeline #(.X_W(4),.Y_W(4)) pipeline (
        .clk(clk),.rst_n(rst_n),.in_valid(iv),.in_win_valid(iv),.in_sof(iv),.in_eol(iv),.in_eof(iv),
        .in_x(4'd3),.in_y(4'd4),.in_rgb(24'h123456),.threshold(11'd100),
        .p00(8'd0),.p01(8'd0),.p02(8'd255),.p10(8'd0),.p11(8'd0),.p12(8'd255),.p20(8'd0),.p21(8'd0),.p22(8'd255),
        .out_valid(pv),.out_win_valid(pw),.out_sof(ps),.out_eol(pl),.out_eof(pe),.out_x(px),.out_y(py),.out_rgb(rgb),.out_gx(gx),.out_gy(gy),.out_magnitude(magnitude),.out_edge(pedge));
    case4_edge_overlay_rgb565 #(.X_W(4),.Y_W(4)) overlay565 (
        .clk(clk),.rst_n(rst_n),.in_valid(iv),.in_win_valid(iv),.in_sof(iv),.in_eol(iv),.in_eof(iv),.in_x(4'd3),.in_y(4'd4),.in_rgb565(16'h1234),.in_edge(iv),
        .out_valid(v565),.out_win_valid(w565),.out_sof(s565),.out_eol(l565),.out_eof(e565),.out_x(x565),.out_y(y565),.out_rgb565(rgb565),.out_edge(edge565));
    case4_edge_expand8 #(.X_W(4),.Y_W(4)) expand8 (
        .clk(clk),.rst_n(rst_n),.in_valid(iv),.in_win_valid(iv),.in_sof(iv),.in_eol(iv),.in_eof(iv),.in_x(4'd3),.in_y(4'd4),.in_edge(iv),
        .out_valid(v8),.out_win_valid(w8),.out_sof(s8),.out_eol(l8),.out_eof(e8),.out_x(x8),.out_y(y8),.out_edge(edge8),.out_edge8(gray8));
    wire [255:0] observed={pv,pw,ps,pl,pe,pedge,px,py,rgb,gx,gy,magnitude,
        v565,w565,s565,l565,e565,edge565,x565,y565,rgb565,v8,w8,s8,l8,e8,edge8,x8,y8,gray8};
    reg [255:0] saved;
    task automatic expect_active;
        if({pv,pw,ps,pl,pe,pedge,v565,w565,s565,l565,e565,edge565,v8,w8,s8,l8,e8,edge8} !== {18{1'b1}}
            || rgb!==24'hff0000 || rgb565!==16'hf800 || gray8!==8'hff || gx!==12'sd1020 || gy!==12'sd0 || magnitude!==11'd1020)
            $fatal(1,"RESET_ACTIVE_SETUP");
    endtask
    initial begin
        repeat(3) @(negedge clk);
        rst_n=1;iv=1;
        repeat(7) @(negedge clk);
        expect_active();saved=observed;
        #1 rst_n=0;
        #1;
        if(observed!==saved) $fatal(1,"RESET_ASYNC_PRIMITIVE_LEAK");
        rst_n=1;
        @(posedge clk);#1;expect_active();
        @(negedge clk);rst_n=0;
        @(posedge clk);#1;
        if(observed!=='0) $fatal(1,"RESET_SYNC_CLEAR");
        @(negedge clk);rst_n=1;iv=0;
        repeat(7) begin
            @(posedge clk);#1;
            if({pv,v565,v8,pedge,edge565,edge8}!=='0) $fatal(1,"RESET_GHOST_OUTPUT");
        end
        @(negedge clk);iv=1;
        repeat(7) @(negedge clk);
        expect_active();
        $display("RESET_PRIMITIVES_PASS");$finish;
    end
    initial begin #10000;$fatal(1,"RESET_TIMEOUT");end
endmodule
