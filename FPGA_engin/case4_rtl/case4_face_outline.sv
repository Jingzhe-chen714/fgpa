`timescale 1ns/1ps
// Rule-based, SINGLE prominent frontal-face candidate in the right half ROI.
// This is not a trained general face detector and does not identify people.
// Evidence: broad warm chroma + plausible head aspect/density + two separate
// dark eye zones + a lower dark mouth zone, with REAL edge support in all three
// zones and four perimeter sectors. A skin-colored oval alone cannot pass.
// Frame protocol: frame_start begins a raster; sample_tick marks a NEW camera
// observation. Repeated display frames do not update evidence or timeouts.
// Leave >=6 idle clocks after the last accepted pixel before frame_start.
// Leave >=34 clocks between frame_start and first pixel (serial mean divider).
// First new frame acquires a box; following new frames validate it. At least
// CONFIRM_FRAMES successful validations are needed. Output changes in blanking.
// face_outline is ONLY an input edge inside a confirmed face box; no synthetic
// ellipse/box is reported as detected contour. A caller can draw a separate UI.
module case4_face_outline #(
    parameter integer IMG_WIDTH=1920,IMG_HEIGHT=1080,
    parameter integer MIN_FACE_WIDTH=48,MIN_FACE_HEIGHT=56,
    parameter integer CONFIRM_FRAMES=2,LOSS_FRAMES=3,
    parameter integer MIN_SKIN_RUN=(MIN_FACE_WIDTH/8<3?3:MIN_FACE_WIDTH/8)
)(
    input wire clk,rst_n,clear,frame_start,sample_tick,pixel_valid,
    input wire [10:0] x,y,input wire [23:0] rgb,input wire edge_bit,
    output reg face_valid,output reg [10:0] bbox_x0,bbox_x1,bbox_y0,bbox_y1,
    output wire face_outline,output reg [7:0] score,
    output reg observation_valid,result_tick
);
    wire [7:0] r=rgb[23:16],g=rgb[15:8],b=rgb[7:0];
    wire [9:0] luma_sum={2'b0,r}+{1'b0,g,1'b0}+{2'b0,b};
    wire [7:0] luma=luma_sum[9:2];
    // Wide warm chroma ranges include bright/medium/dark synthetic skin samples.
    // Very low light, colored illumination, and neutral/occluded faces can fail.
    wire skin=({1'b0,r}+8>={1'b0,g})&&({1'b0,r}+8>={1'b0,b})&&
        ({1'b0,g}+16>={1'b0,b})&&({1'b0,r}<={1'b0,g}+100)&&
        ({1'b0,g}<={1'b0,b}+90)&&({1'b0,r}>={1'b0,b}+4)&&luma>=12&&luma<=248;
    wire in_roi=pixel_valid&&x>IMG_WIDTH/2+2&&x<IMG_WIDTH-3&&y>2&&y<IMG_HEIGHT-3;
    reg capture_active;
    reg [10:0] dx0,dx1,dy0,dy1,run_start;
    reg [11:0] run_length;
    reg found;
    reg [20:0] skin_count;
    reg [31:0] skin_sum;
    // These statistics are consumed only at the end-of-frame boundary.
    // Pipeline continuously; six trailing idle clocks let all final counters,
    // dimensions and evidence settle coherently before frame_start consumes them.
    // No timing exception or reduced pixel throughput is required.
    reg [11:0] dw,dh;
    reg [23:0] detected_area;
    reg geometry,verified;
    reg analysis_valid;
    reg [10:0] ax0,ax1,ay0,ay1;
    reg [11:0] aw,ah;
    reg [23:0] area;
    reg [7:0] skin_mean;
    wire [7:0] dark_limit=skin_mean-(skin_mean>>2);
    wire in_box=in_roi&&analysis_valid&&x>=ax0&&x<=ax1&&y>=ay0&&y<=ay1;
    wire eye_y=y>=ay0+((ah*5)>>4)&&y<=ay0+((ah*9)>>4);
    wire eye_l=in_box&&eye_y&&x>=ax0+((aw*3)>>4)&&x<=ax0+((aw*7)>>4);
    wire eye_r=in_box&&eye_y&&x>=ax0+((aw*9)>>4)&&x<=ax0+((aw*13)>>4);
    wire mouth=in_box&&x>=ax0+((aw*5)>>4)&&x<=ax0+((aw*11)>>4)&&y>=ay0+((ah*10)>>4)&&y<=ay0+((ah*14)>>4);
    wire dark=luma<dark_limit;
    reg [20:0] dark_l,dark_r,dark_m,edge_l,edge_r,edge_m;
    reg [20:0] boundary_l,boundary_r,boundary_t,boundary_b;
    wire [23:0] min_dark=(area>>10)<3?24'd3:(area>>10);
    wire [23:0] min_edge=(area>>12)<2?24'd2:(area>>12);
    wire good_l=dark_l>=min_dark&&dark_l<((area>>5)+(area>>6))&&edge_l>=min_edge;
    wire good_r=dark_r>=min_dark&&dark_r<((area>>5)+(area>>6))&&edge_r>=min_edge;
    wire good_m=dark_m>=min_dark&&dark_m<(area>>4)&&edge_m>=min_edge;
    wire good_border=boundary_l>=min_edge&&boundary_r>=min_edge&&boundary_t>=min_edge&&boundary_b>=min_edge;
    wire [12:0] old_cx={2'b0,ax0}+{2'b0,ax1},new_cx={2'b0,dx0}+{2'b0,dx1};
    wire [12:0] old_cy={2'b0,ay0}+{2'b0,ay1},new_cy={2'b0,dy0}+{2'b0,dy1};
    wire [12:0] move_x=old_cx>new_cx?old_cx-new_cx:new_cx-old_cx;
    wire [12:0] move_y=old_cy>new_cy?old_cy-new_cy:new_cy-old_cy;
    wire aligned=move_x<=(aw>>1)+4&&move_y<=(ah>>1)+4&&4*dw>=3*aw&&4*dw<=5*aw&&4*dh>=3*ah&&4*dh<=5*ah;
    always @(posedge clk) begin
        if(!rst_n||clear) begin
            dw<=0;dh<=0;detected_area<=0;geometry<=0;verified<=0;
        end else begin
            dw<={1'b0,dx1}-{1'b0,dx0}+12'd1;
            dh<={1'b0,dy1}-{1'b0,dy0}+12'd1;
            detected_area<=dw*dh;
            geometry<=found&&dw>=MIN_FACE_WIDTH&&dh>=MIN_FACE_HEIGHT&&
                2*dw>=dh&&4*dw<=5*dh&&skin_count>=(detected_area>>2)&&
                skin_count<(detected_area-(detected_area>>6));
            verified<=analysis_valid&&geometry&&aligned&&good_l&&good_r&&good_m&&good_border;
        end
    end
    reg [7:0] confirmations,misses;
    // A once-per-frame restoring divider avoids a large combinational divider
    // on the pixel path. Average is bounded [0,255]; no floating point / DSP.
    reg divide_busy;reg [5:0] divide_left;
    reg [31:0] dividend,quotient,divisor,remainder;
    wire [32:0] shifted_remainder={remainder,dividend[31]};
    wire subtract_ok=shifted_remainder>={1'b0,divisor};
    wire [31:0] next_quotient={quotient[30:0],subtract_ok};
    assign face_outline=face_valid&&pixel_valid&&edge_bit&&x>=bbox_x0&&x<=bbox_x1&&y>=bbox_y0&&y<=bbox_y1;
    always @(posedge clk) begin
        if(!rst_n||clear) begin
            capture_active<=0;face_valid<=0;score<=0;observation_valid<=0;result_tick<=0;bbox_x0<=0;bbox_x1<=0;bbox_y0<=0;bbox_y1<=0;
            dx0<=2047;dx1<=0;dy0<=2047;dy1<=0;run_start<=0;run_length<=0;found<=0;
            skin_count<=0;skin_sum<=0;analysis_valid<=0;ax0<=0;ax1<=0;ay0<=0;ay1<=0;aw<=0;ah<=0;area<=0;skin_mean<=128;
            dark_l<=0;dark_r<=0;dark_m<=0;edge_l<=0;edge_r<=0;edge_m<=0;
            boundary_l<=0;boundary_r<=0;boundary_t<=0;boundary_b<=0;confirmations<=0;misses<=0;
            divide_busy<=0;divide_left<=0;dividend<=0;quotient<=0;divisor<=1;remainder<=0;
        end else begin
            result_tick<=0;
            if(divide_busy) begin
                dividend<={dividend[30:0],1'b0};quotient<=next_quotient;
                remainder<=subtract_ok?shifted_remainder-{1'b0,divisor}:shifted_remainder;
                divide_left<=divide_left-1'b1;
                if(divide_left==1) begin skin_mean<=next_quotient[7:0];divide_busy<=0;end
            end
            if(frame_start) begin
                capture_active<=sample_tick;
                if(capture_active) begin
                    // A held display box is not a new motion measurement.
                    result_tick<=1;
                    observation_valid<=verified&&confirmations>=CONFIRM_FRAMES-1;
                    analysis_valid<=geometry;ax0<=dx0;ax1<=dx1;ay0<=dy0;ay1<=dy1;aw<=dw;ah<=dh;area<=detected_area;
                    if(skin_count!=0) begin
                        divide_busy<=1;divide_left<=32;dividend<=skin_sum;divisor<=skin_count;quotient<=0;remainder<=0;
                    end
                    score<=({7'b0,geometry}+{7'b0,aligned}+{7'b0,good_l}+{7'b0,good_r}+{7'b0,good_m}+{7'b0,good_border})*8'd32;
                    if(verified) begin
                        misses<=0;
                        if(confirmations<CONFIRM_FRAMES) confirmations<=confirmations+1'b1;
                        if(confirmations>=CONFIRM_FRAMES-1) begin
                            face_valid<=1;bbox_x0<=dx0;bbox_x1<=dx1;bbox_y0<=dy0;bbox_y1<=dy1;
                        end
                    end else begin
                        confirmations<=0;
                        if(misses<LOSS_FRAMES) misses<=misses+1'b1;
                        if(misses>=LOSS_FRAMES-1) face_valid<=0;
                    end
                end
                dx0<=2047;dx1<=0;dy0<=2047;dy1<=0;found<=0;run_length<=0;run_start<=0;skin_count<=0;skin_sum<=0;
                dark_l<=0;dark_r<=0;dark_m<=0;edge_l<=0;edge_r<=0;edge_m<=0;boundary_l<=0;boundary_r<=0;boundary_t<=0;boundary_b<=0;
            end else if(capture_active) begin
                if(in_roi&&skin) begin
                    skin_count<=skin_count+1'b1;skin_sum<=skin_sum+luma;
                    if(run_length==0) run_start<=x;
                    run_length<=run_length+1'b1;
                    if(run_length>=MIN_SKIN_RUN-1) begin
                        found<=1;
                        if(run_start<dx0) dx0<=run_start;
                        if(x>dx1) dx1<=x;
                        if(y<dy0) dy0<=y;
                        if(y>dy1) dy1<=y;
                    end
                end else run_length<=0;
                if(in_box) begin
                    if(eye_l) begin if(dark) dark_l<=dark_l+1'b1;if(edge_bit) edge_l<=edge_l+1'b1;end
                    if(eye_r) begin if(dark) dark_r<=dark_r+1'b1;if(edge_bit) edge_r<=edge_r+1'b1;end
                    if(mouth) begin if(dark) dark_m<=dark_m+1'b1;if(edge_bit) edge_m<=edge_m+1'b1;end
                    if(edge_bit) begin
                        if(x<=ax0+(aw>>2)&&y>=ay0+(ah>>2)&&y<=ay0+((ah*3)>>2)) boundary_l<=boundary_l+1'b1;
                        if(x>=ax1-(aw>>2)&&y>=ay0+(ah>>2)&&y<=ay0+((ah*3)>>2)) boundary_r<=boundary_r+1'b1;
                        if(y<=ay0+(ah>>2)&&x>=ax0+(aw>>2)&&x<=ax0+((aw*3)>>2)) boundary_t<=boundary_t+1'b1;
                        if(y>=ay1-(ah>>2)&&x>=ax0+(aw>>2)&&x<=ax0+((aw*3)>>2)) boundary_b<=boundary_b+1'b1;
                    end
                end
            end
        end
    end
endmodule
