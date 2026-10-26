`timescale 1ns/1ps
// STAGES registered stages, data sampled at N is visible at N+STAGES-1.
// Separate circular addresses for STAGES>=2; no memory initialization/reset.
// Just above 2048 stages, keep a power-of-two BRAM ring and put the short
// remainder in unreset shift registers. This avoids doubling the BRAM depth
// allocation for the 2206-stage native-1080p metadata delays.
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
        reg [WIDTH-1:0] tail[0:TAIL-1];
        integer i;
        // The ring is exactly 2048 registered stages. Its read and write
        // addresses always differ, including the 2047 -> 0 wrap.
        always @(posedge clk) if(!rst) begin
            mem[ptr]<=din;
            q<=mem[next_ptr];
            tail[0]<=q;
            for(i=1;i<TAIL;i=i+1) tail[i]<=tail[i-1];
        end
        // No data reset on either RAM or tail: Efinity can infer SRL8s.
        // Refill the entire composite delay after each reset before ready.
        always @(posedge clk) begin
            if(rst) begin ptr<=0;count<=0;end
            else begin
                ptr<=next_ptr;
                if(count<STAGES) count<=count+1'b1;
            end
        end
        assign dout=tail[TAIL-1];
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
