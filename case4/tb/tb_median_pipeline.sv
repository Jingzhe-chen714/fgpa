`timescale 1ns/1ps
// Independent full-sort oracle; check combinational, one-stage and three-stage
// implementations concurrently, including exact cycle/metadata and flushes.
module tb_median_pipeline #(parameter integer P=8);
    reg clk=0;
    always #5 clk=~clk;
    reg rst=1,iv=0,sof=0,eol=0,eof=0;
    reg [9:0] x=0,y=0;
    reg [P-1:0] pixels[0:8];
    wire [2:0] ov,os,ol,oe;
    wire [9:0] ox[0:2],oy[0:2];
    wire [P-1:0] data[0:2];
    for(genvar d=0;d<3;d++) begin:g
        localparam integer STAGES=(d==2)?3:d;
        median3x3_u8 #(.PIXEL_BITS(P),.X_BITS(10),.Y_BITS(10),.REGISTER_OUTPUT(STAGES!==0),.PIPELINE_STAGES(STAGES)) dut (
            .clk(clk),.rst(rst),.in_valid(iv),.in_sof(sof),.in_eol(eol),.in_eof(eof),.in_x(x),.in_y(y),
            .in_p00(pixels[0]),.in_p01(pixels[1]),.in_p02(pixels[2]),.in_p10(pixels[3]),.in_p11(pixels[4]),.in_p12(pixels[5]),.in_p20(pixels[6]),.in_p21(pixels[7]),.in_p22(pixels[8]),
            .out_valid(ov[d]),.out_sof(os[d]),.out_eol(ol[d]),.out_eof(oe[d]),.out_x(ox[d]),.out_y(oy[d]),.out_pixel(data[d]));
    end
    logic [24+P-1:0] queue[0:2],input_expected,observed;
    integer ordered[0:8],tmp;
    integer counts[0:2]='{0,0,0};
    int unsigned rng=32'hbd631c37;
    integer resets=0;
    function automatic int unsigned next_rand(input int unsigned value);
        int unsigned v;
        begin v=value^(value<<13);v=v^(v>>17);next_rand=v^(v<<5);end
    endfunction
    always @(posedge clk) begin
        for(integer i=0;i<9;i++) ordered[i]=pixels[i];
        // Insertion sort is intentionally not the implementation's network.
        for(integer i=1;i<9;i++) begin
            for(integer j=i;j>0;j--) begin
                if(ordered[j]<ordered[j-1]) begin tmp=ordered[j];ordered[j]=ordered[j-1];ordered[j-1]=tmp;end
            end
        end
        input_expected={iv,iv&&sof,iv&&eol,iv&&eof,x,y,P'(ordered[4])};
        if(rst) begin for(integer i=0;i<3;i++)queue[i]='0;resets++;end
        else begin queue[2]=queue[1];queue[1]=queue[0];queue[0]=input_expected;end
        #1;
        for(integer d=0;d<3;d++) begin
            observed={ov[d],os[d],ol[d],oe[d],ox[d],oy[d],data[d]};
            if(observed !== ((d==0)?input_expected:queue[(d==1)?0:2]))
                $fatal(1,"MEDIAN_DATA P=%0d mode=%0d got=%h expected=%h",P,d,observed,((d==0)?input_expected:queue[(d==1)?0:2]));
            if(ov[d])counts[d]++;
        end
    end
    initial begin
        for(integer i=0;i<9;i++) pixels[i]=0;
        repeat(3) @(negedge clk);
        for(integer n=0;n<100512;n++) begin
            rst=(n>=512 && n%997==0);iv=(n<512 || n%5!==0);
            sof=(n%103==0);eol=(n%17==0);eof=(n%307==0);x=n%1024;y=(n/1024)%1024;
            for(integer i=0;i<9;i++) begin
                rng=next_rand(rng);
                if(n<512) pixels[i]=((n>>i)&1)?'1:'0;
                else if(n%3==0) pixels[i]=rng%5; // many duplicate values
                else pixels[i]=rng;
            end
            @(negedge clk);
        end
        rst=0;iv=0;sof=0;eol=0;eof=0;
        repeat(5) @(negedge clk);
        if(counts[2]<70000 || resets<100) $fatal(1,"MEDIAN_COVERAGE");
        $display("MEDIAN_PIPELINE_PASS P=%0d comb=%0d one=%0d three=%0d reset_cycles=%0d",P,counts[0],counts[1],counts[2],resets);
        $finish;
    end
    initial begin #2000000; $fatal(1,"MEDIAN_TIMEOUT");end
endmodule
