`timescale 1ns/1ps
// One geometric/face target, updated ONLY on fresh observations. Bounding-box
// center is not an image-moment centroid. Positive direction is left -> right.
// Trail renderer returns original-coordinate points (radius TRAIL_RADIUS), not
// fabricated motion interpolation. Consumer can map age to a fading palette.
module case4_target_tracker #(
    parameter integer TRAIL_POINTS=16, LOST_SAMPLES=3,
    parameter integer HYSTERESIS_PX=12, MAX_JUMP_PX=240, TRAIL_RADIUS=2
)(
    input wire clk,rst_n,clear,invalidate,sample_tick,target_valid,
    input wire [10:0] bbox_x0,bbox_x1,bbox_y0,bbox_y1,line_x,
    input wire draw_valid,input wire [10:0] draw_x,draw_y,
    output reg track_valid,output reg [10:0] center_x,center_y,
    output reg [1:0] direction,
    output reg [15:0] count_in,count_out,
    output reg trail_hit,output reg [4:0] trail_age
);
    localparam integer LOST_BITS=LOST_SAMPLES<2?1:$clog2(LOST_SAMPLES+1);
    reg [LOST_BITS-1:0] missing;
    reg signed [1:0] side;
    reg [10:0] active_line;
    reg [10:0] trail_x[0:TRAIL_POINTS-1],trail_y[0:TRAIL_POINTS-1];
    reg [TRAIL_POINTS-1:0] trail_valid;
    wire [11:0] sx={1'b0,bbox_x0}+{1'b0,bbox_x1};
    wire [11:0] sy={1'b0,bbox_y0}+{1'b0,bbox_y1};
    wire [10:0] nx=sx[11:1],ny=sy[11:1];
    wire [11:0] dx=nx>center_x?nx-center_x:center_x-nx;
    wire [11:0] dy=ny>center_y?ny-center_y:center_y-ny;
    wire valid_box=target_valid&&bbox_x0<=bbox_x1&&bbox_y0<=bbox_y1;
    wire signed [1:0] new_side=({1'b0,nx}+HYSTERESIS_PX<{1'b0,line_x})?-2'sd1:
        ({1'b0,nx}>{1'b0,line_x}+HYSTERESIS_PX)?2'sd1:2'sd0;
    integer i;
    always @(posedge clk) begin
        if(!rst_n||clear) begin
            track_valid<=0;center_x<=0;center_y<=0;direction<=0;
            count_in<=0;count_out<=0;missing<=0;side<=0;active_line<=line_x;trail_valid<=0;
            for(i=0;i<TRAIL_POINTS;i=i+1) begin trail_x[i]<=0;trail_y[i]<=0;end
        end else if(invalidate) begin
            // Application/history changes break association without erasing
            // the user's accumulated entry/exit counts.
            track_valid<=0;center_x<=0;center_y<=0;direction<=0;
            missing<=0;side<=0;active_line<=line_x;trail_valid<=0;
        end else if(sample_tick) begin
            active_line<=line_x;
            if(valid_box) begin
                missing<=0;track_valid<=1;center_x<=nx;center_y<=ny;
                if(!track_valid||dx>MAX_JUMP_PX||dy>MAX_JUMP_PX||line_x!=active_line) begin
                    // Reacquisition, a scene cut, or moving the count line starts
                    // a new identity; none of those actions is a crossing.
                    side<=new_side;direction<=0;trail_valid<=1;
                    trail_x[0]<=nx;trail_y[0]<=ny;
                end else begin
                    direction<=nx>center_x?2'd1:nx<center_x?2'd2:direction;
                    if(new_side!=0) begin
                        if(side==-2'sd1&&new_side==2'sd1&&count_in!=16'hffff) count_in<=count_in+1'b1;
                        if(side==2'sd1&&new_side==-2'sd1&&count_out!=16'hffff) count_out<=count_out+1'b1;
                        side<=new_side;
                    end
                    for(i=TRAIL_POINTS-1;i>0;i=i-1) begin
                        trail_x[i]<=trail_x[i-1];trail_y[i]<=trail_y[i-1];trail_valid[i]<=trail_valid[i-1];
                    end
                    trail_x[0]<=nx;trail_y[0]<=ny;trail_valid[0]<=1;
                end
            end else begin
                direction<=0;
                // Any missed observation breaks the crossing association. A
                // short display hold is allowed, but reappearing on the other
                // side cannot be counted as a measured traversal.
                side<=0;
                if(missing<LOST_SAMPLES) missing<=missing+1'b1;
                if(missing>=LOST_SAMPLES-1) begin track_valid<=0;trail_valid<=0;end
            end
        end
    end
    integer j;
    always @* begin
        trail_hit=0;trail_age=0;
        for(j=TRAIL_POINTS-1;j>=0;j=j-1) begin
            if(draw_valid&&track_valid&&trail_valid[j]&&
               {1'b0,draw_x}+TRAIL_RADIUS>={1'b0,trail_x[j]}&&{1'b0,draw_x}<={1'b0,trail_x[j]}+TRAIL_RADIUS&&
               {1'b0,draw_y}+TRAIL_RADIUS>={1'b0,trail_y[j]}&&{1'b0,draw_y}<={1'b0,trail_y[j]}+TRAIL_RADIUS) begin
                trail_hit=1;trail_age=j;
            end
        end
    end
endmodule
