`timescale 1ns/1ps
// Two registered stages, eight independent native RGB565 pixels per AXI beat.
// Input at edge N appears at output after edge N+1; no ready/backpressure.
// Caller reserves enough FIFO space for a complete burst and pipeline tail.
module case4_frame_diff128 (
    input wire clk, reset, in_valid,
    input wire [127:0] in_selected, in_reference,
    input wire [7:0] threshold,
    output reg out_valid,
    output wire [127:0] out_data
);
    reg valid1;
    reg [7:0] threshold1;
    always @(posedge clk) begin
        if (reset) begin valid1<=0;out_valid<=0;threshold1<=0;end
        else begin valid1<=in_valid;out_valid<=valid1;threshold1<=threshold;end
    end
    genvar p;
    generate for(p=0;p<8;p=p+1) begin:pixel
        wire [15:0] a=in_selected[p*16 +: 16];
        wire [15:0] b=in_reference[p*16 +: 16];
        wire [7:0] ar={a[15:11],a[15:13]},br={b[15:11],b[15:13]};
        wire [7:0] ag={a[10:5],a[10:9]},bg={b[10:5],b[10:9]};
        wire [7:0] ab={a[4:0],a[4:2]},bb={b[4:0],b[4:2]};
        reg [7:0] dr,dg,db;
        reg [15:0] selected1,result2;
        always @(posedge clk) begin
            dr<=ar>=br?ar-br:br-ar;
            dg<=ag>=bg?ag-bg:bg-ag;
            db<=ab>=bb?ab-bb:bb-ab;
            selected1<=a;
            result2<=(dr>threshold1 || dg>threshold1 || db>threshold1)?16'hffe0:selected1;
        end
        assign out_data[p*16 +: 16]=result2;
    end endgenerate
endmodule
