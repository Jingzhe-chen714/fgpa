`timescale 1ns/1ps
// Independent integer convolution scoreboard; exercises minimum/widened widths.
module tb_sobel_widths #(
    parameter integer P=8, PART=P+3, GRAD=P+4, MAG=P+3
);
    localparam integer MAX_PIXEL=(1<<P)-1;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0, iv=0, iw=0;
    reg [P-1:0] p[0:8];
    reg [3:0] x=0,y=0;
    wire ov,ow;
    wire signed [GRAD-1:0] gx,gy;
    wire [MAG-1:0] mag;
    wire [3:0] ox,oy;
    case4_sobel3x3 #(.PIX_W(P),.PART_W(PART),.GRAD_W(GRAD),.MAG_W(MAG),.X_W(4),.Y_W(4)) dut (
        .clk(clk),.rst_n(rst_n),.in_valid(iv),.in_win_valid(iw),
        .in_sof(1'b0),.in_eol(1'b0),.in_eof(1'b0),.in_x(x),.in_y(y),.in_rgb(24'd0),
        .p00(p[0]),.p01(p[1]),.p02(p[2]),.p10(p[3]),.p11(p[4]),.p12(p[5]),.p20(p[6]),.p21(p[7]),.p22(p[8]),
        .out_valid(ov),.out_win_valid(ow),.out_x(ox),.out_y(oy),.out_gx(gx),.out_gy(gy),.out_magnitude(mag));
    integer qgx[0:2],qgy[0:2],qmag[0:2], qx[0:2],qy[0:2];
    bit qv[0:2],qw[0:2];
    integer count=0,cycle=0, peak=0;
    int unsigned rng=32'h93471acd;
    function automatic int unsigned next_rand(input int unsigned value);
        int unsigned v;
        begin v=value^(value<<13);v=v^(v>>17);next_rand=v^(v<<5);end
    endfunction
    always @(posedge clk) begin
        if (!rst_n) begin
            for(integer i=0;i<3;i++) begin qv[i]=0;qw[i]=0;qgx[i]=0;qgy[i]=0;qmag[i]=0;qx[i]=0;qy[i]=0;end
        end else begin
            for(integer i=2;i>0;i--) begin
                qv[i]=qv[i-1];qw[i]=qw[i-1];qgx[i]=qgx[i-1];qgy[i]=qgy[i-1];qmag[i]=qmag[i-1];qx[i]=qx[i-1];qy[i]=qy[i-1];
            end
            qv[0]=iv;qw[0]=iv && iw;qx[0]=x;qy[0]=y;
            // Cast BEFORE subtracting, with a reference width unrelated to DUT.
            qgx[0]=-int'(p[0])+int'(p[2])-2*int'(p[3])+2*int'(p[5])-int'(p[6])+int'(p[8]);
            qgy[0]=-int'(p[0])-2*int'(p[1])-int'(p[2])+int'(p[6])+2*int'(p[7])+int'(p[8]);
            qmag[0]=(qgx[0]<0 ? -qgx[0]:qgx[0])+(qgy[0]<0 ? -qgy[0]:qgy[0]);
        end
        #1;
        if(ov!==qv[2] || ow!==qw[2]) $fatal(1,"WIDTH_VALID P=%0d cycle=%0d",P,cycle);
        if(ov) begin
            if(ox!==4'(qx[2]) || oy!==4'(qy[2])) $fatal(1,"WIDTH_COORD");
            count++;
        end
        if(qw[2]) begin
            if($signed(gx)!==qgx[2] || $signed(gy)!==qgy[2] || mag!==MAG'(qmag[2]))
                $fatal(1,"WIDTH_DATA P=%0d MAG=%0d got=%0d,%0d,%h expected=%0d,%0d,%0d",P,MAG,gx,gy,mag,qgx[2],qgy[2],qmag[2]);
            if(qmag[2]>peak) peak=qmag[2];
        end else if({gx,gy,mag} !== '0) $fatal(1,"WIDTH_INVALID_DATA");
        cycle++;
    end
    initial begin
        for(integer i=0;i<9;i++) p[i]=0;
        repeat(3) @(negedge clk);
        for(integer n=0;n<2512;n++) begin
            rst_n=1; iv=(n<512 || n%7!==0);iw=(n<512 || n%11!==0);x=n%16;y=(n/16)%16;
            for(integer i=0;i<9;i++) begin
                rng=next_rand(rng);
                p[i]=(n<512) ? (((n>>i)&1) ? MAX_PIXEL : 0) : rng;
            end
            @(negedge clk);
        end
        iv=0;iw=0;
        repeat(5) @(negedge clk);
        if(peak!==6*MAX_PIXEL) $fatal(1,"WIDTH_EXTREME_NOT_COVERED peak=%0d",peak);
        $display("SOBEL_WIDTH_PASS P=%0d PART=%0d GRAD=%0d MAG=%0d transactions=%0d peak=%0d",P,PART,GRAD,MAG,count,peak);
        $finish;
    end
    initial begin #100000; $fatal(1,"WIDTH_TIMEOUT");end
endmodule
