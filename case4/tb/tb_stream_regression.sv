`timescale 1ns/1ps
module tb_stream_regression #(
    parameter integer W=7, H=9, FORMAT=1,
    parameter integer MAG=11,
    parameter DIRECTORY="",
    parameter integer CYCLES=0,N0=0,N1=0,N2=0,N3=0
);
    localparam integer XB=$clog2(W), YB=$clog2(H);
    logic clk=0;
    always #5 clk=~clk;
    logic rst=1, iv=0, sof=0, eol=0, eof=0;
    logic [9:0] x=0,y=0;
    logic [23:0] pixel=0;
    logic [10:0] threshold=0;
    wire [3:0] ov, ow, os, ol, oe, edgebit;
    wire [XB-1:0] ox[0:3];
    wire [YB-1:0] oy[0:3];
    wire signed [11:0] gx[0:3], gy[0:3];
    wire [MAG-1:0] mag[0:3];
    for(genvar d=0; d<4; d++) begin : g
        if(d<2) begin
            case4_gray_sobel_core #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.PIXEL_FORMAT(FORMAT),.MAG_W(MAG),.WINDOW_BACKEND(d)) dut (
                .clk(clk),.rst(rst),.in_valid(iv),.in_sof(sof),.in_eol(eol),.in_eof(eof),.in_x(x[XB-1:0]),.in_y(y[YB-1:0]),.in_pixel(pixel),.threshold(MAG'(threshold)),
                .out_valid(ov[d]),.out_win_valid(ow[d]),.out_sof(os[d]),.out_eol(ol[d]),.out_eof(oe[d]),.out_x(ox[d]),.out_y(oy[d]),.out_gx(gx[d]),.out_gy(gy[d]),.out_magnitude(mag[d]),.out_edge(edgebit[d]));
        end else begin
            case4_gray_median_sobel_core #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.PIXEL_FORMAT(FORMAT),.MAG_W(MAG),.WINDOW_BACKEND(d-2)) dut (
                .clk(clk),.rst(rst),.in_valid(iv),.in_sof(sof),.in_eol(eol),.in_eof(eof),.in_x(x[XB-1:0]),.in_y(y[YB-1:0]),.in_pixel(pixel),.threshold(MAG'(threshold)),
                .out_valid(ov[d]),.out_win_valid(ow[d]),.out_sof(os[d]),.out_eol(ol[d]),.out_eof(oe[d]),.out_x(ox[d]),.out_y(oy[d]),.out_gx(gx[d]),.out_gy(gy[d]),.out_magnitude(mag[d]),.out_edge(edgebit[d]));
        end
    end
    string directory;
    integer cycles, n[0:3], fd, efd[0:3], count[0:3], rc;
    logic [59:0] input_word, observed;
    logic [95:0] expected[0:3];
    logic [255:0] pulse_hold[0:3];
    integer ignored_reset_pulses=0;
    initial begin
        directory=DIRECTORY;
        cycles=CYCLES;
        n[0]=N0; n[1]=N1; n[2]=N2; n[3]=N3;
        fd=$fopen({directory,"/input.hex"},"r");
        if (!fd) $fatal(1,"input missing");
        for(integer d=0;d<4;d++) begin
            efd[d]=$fopen($sformatf("%s/expected%0d.hex",directory,d),"r");
            if (!efd[d]) $fatal(1,"expected missing");
            count[d]=0;
            rc=$fscanf(efd[d],"%h",expected[d]);
            if(rc!==1) $fatal(1,"empty expected");
        end
        for(integer tick=0;tick<cycles;tick++) begin
            @(negedge clk);
            rc=$fscanf(fd,"%h",input_word);
            if(rc!==1) $fatal(1,"short stimulus");
            {rst,iv,sof,eol,eof,x,y,pixel,threshold}=input_word;
            // A synchronous reset must have NO effect between rising edges.
            // Test through legal public inputs; no forcing internal DUT state.
            if(!rst && tick%257==128) begin
                #1;
                for(integer d=0;d<4;d++)
                    pulse_hold[d]={ov[d],ow[d],os[d],ol[d],oe[d],edgebit[d],ox[d],oy[d],gx[d],gy[d],mag[d]};
                rst=1;
                #1;
                for(integer d=0;d<4;d++)
                    if(pulse_hold[d] !== {ov[d],ow[d],os[d],ol[d],oe[d],edgebit[d],ox[d],oy[d],gx[d],gy[d],mag[d]})
                        $fatal(1,"STREAM_ASYNC_RESET_LEAK variant=%0d tick=%0d",d,tick);
                rst=0;
                ignored_reset_pulses++;
            end
            @(posedge clk); #1;
            for(integer d=0;d<4;d++) begin
                if (ov[d] !== (count[d]<n[d] && expected[d][95:60]==tick))
                    $fatal(1,"AUDIT_VALID variant=%0d tick=%0d count=%0d got=%b next_due=%0d",d,tick,count[d],ov[d],expected[d][95:60]);
                if(ov[d]) begin
                    observed={ow[d],os[d],ol[d],oe[d],{{(10-XB){1'b0}},ox[d]},{{(10-YB){1'b0}},oy[d]},gx[d],gy[d],mag[d][10:0],1'b0};
                    if(observed !== expected[d][59:0])
                        $fatal(1,"AUDIT_DATA variant=%0d tick=%0d count=%0d got=%h exp=%h",d,tick,count[d],observed,expected[d][59:0]);
                    if(edgebit[d] !== (mag[d]>=threshold))
                        $fatal(1,"AUDIT_THRESHOLD variant=%0d tick=%0d",d,tick);
                    if(mag[d] !== MAG'(expected[d][11:1]))
                        $fatal(1,"STREAM_MAG_EXTENSION variant=%0d tick=%0d",d,tick);
                    count[d]++;
                    if(count[d]<n[d]) begin
                        rc=$fscanf(efd[d],"%h",expected[d]);
                        if(rc!==1) $fatal(1,"short expected");
                    end
                end else if ({ow[d],os[d],ol[d],oe[d],edgebit[d]} !== 5'b0)
                    $fatal(1,"AUDIT_INVALID_FLAGS variant=%0d tick=%0d",d,tick);
            end
        end
        for(integer d=0;d<4;d++) begin
            if(count[d]!==n[d]) $fatal(1,"AUDIT_COUNT variant=%0d",d);
            $display("STREAM_PASS variant=%0d W=%0d H=%0d FORMAT=%0d MAG=%0d exact_transactions=%0d ignored_reset_pulses=%0d",d,W,H,FORMAT,MAG,count[d],ignored_reset_pulses);
        end
        if(ignored_reset_pulses==0) $fatal(1,"STREAM_RESET_PULSE_COVERAGE");
        $finish;
    end
    initial begin #100000000; $fatal(1,"AUDIT_TIMEOUT"); end
endmodule
