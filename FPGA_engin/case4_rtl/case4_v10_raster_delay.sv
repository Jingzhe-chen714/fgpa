`timescale 1ns/1ps
// STAGES registered stages, data sampled at N is visible at N+STAGES-1.
// Separate circular addresses for STAGES>=2; no memory initialization/reset.
// Just above 2048 stages, keep a power-of-two BRAM ring and put the short
// remainder in a second small synchronous RAM ring (V10). This avoids both
// doubling the large RAM depth and spending thousands of XLRs on SRL tails.
module case4_raster_delay #(parameter WIDTH=35, STAGES=1656)(
    input wire clk,rst, input wire [WIDTH-1:0] din,
    output wire [WIDTH-1:0] dout, output wire ready
);
    generate if(STAGES==1) begin:g_one
        reg [WIDTH-1:0] q; reg valid;
        always @(posedge clk) begin
            if(rst) begin q<=0;valid<=0;end
            else begin q<=din;valid<=1;end
        end
        assign dout=q;assign ready=valid;
    end else if(STAGES>2048 && STAGES<2304) begin:g_ram_srl
        localparam integer TAIL=STAGES-2048;
        localparam integer A=$clog2(STAGES);
        reg [WIDTH-1:0] mem[0:2047];
        reg [WIDTH-1:0] q;
        reg [10:0] ptr;
        wire [10:0] next_ptr=ptr+11'd1;
        reg [A:0] count;
        wire [WIDTH-1:0] tail_out;
        // The ring is exactly 2048 registered stages. Its read and write
        // addresses always differ, including the 2047 -> 0 wrap.
        always @(posedge clk) if(!rst) begin
            mem[ptr]<=din;
            q<=mem[next_ptr];
        end
        if(TAIL<32) begin:g_short_tail
            reg [WIDTH-1:0] tail[0:TAIL-1];
            integer i;
            always @(posedge clk) if(!rst) begin
                tail[0]<=q;
                for(i=1;i<TAIL;i=i+1) tail[i]<=tail[i-1];
            end
            assign tail_out=tail[TAIL-1];
        end else begin:g_tail_ram
            localparam integer TA=$clog2(TAIL);
            reg [WIDTH-1:0] tail_mem[0:TAIL-1];
            reg [WIDTH-1:0] tail_q;
            reg [TA-1:0] tail_ptr;
            wire [TA-1:0] tail_next=tail_ptr==TAIL-1 ? 0 : tail_ptr+1'b1;
            always @(posedge clk) if(!rst) begin
                tail_mem[tail_ptr]<=q;
                tail_q<=tail_mem[tail_next];
            end
            always @(posedge clk) begin
                if(rst) tail_ptr<=0;
                else tail_ptr<=tail_next;
            end
            assign tail_out=tail_q;
        end
        // Neither ring has data reset. Both refill before ready is asserted.
        // Refill the entire composite delay after each reset before ready.
        always @(posedge clk) begin
            if(rst) begin ptr<=0;count<=0;end
            else begin
                ptr<=next_ptr;
                if(count<STAGES) count<=count+1'b1;
            end
        end
        assign dout=tail_out;
        assign ready=count>=STAGES;
    end else begin:g_ram
        localparam A=$clog2(STAGES);
        reg [WIDTH-1:0] mem[0:STAGES-1];
        reg [WIDTH-1:0] q;
        reg [A-1:0] ptr;
        reg [A:0] count;
        wire [A-1:0] next_ptr=ptr==STAGES-1 ? 0 : ptr+1'b1;
        always @(posedge clk) if(!rst) begin mem[ptr]<=din;q<=mem[next_ptr];end
        always @(posedge clk) begin
            if(rst) begin ptr<=0;count<=0;end
            else begin ptr<=next_ptr;if(count<STAGES)count<=count+1'b1;end
        end
        assign dout=q;assign ready=count>=STAGES;
    end endgenerate
endmodule

module case4_raster_xy #(parameter W=1280,H=720,XB=$clog2(W),YB=$clog2(H))(
    input wire clk,rst,vs,de,output reg [XB-1:0] x,output reg [YB-1:0] y
);
    always @(posedge clk) begin
        if(rst || !vs) begin x<=0;y<=0;end
        else if(de) begin
            if(x==W-1) begin x<=0;y<=y==H-1?0:y+1'b1;end
            else x<=x+1'b1;
        end
    end
endmodule
