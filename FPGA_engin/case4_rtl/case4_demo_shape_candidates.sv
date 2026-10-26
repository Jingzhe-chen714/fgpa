`timescale 1ns/1ps
// V7: independent component candidates followed by full-resolution outline fits.
// Locating maps are downsampled; display pixels and fitting are NEVER resized.
// Supports one best approximately circular or axis-aligned rectangular outline
// among separate background components. Connected occlusion is not segmentation.
// frame_start must occur in blanking >=6 cycles after the final valid pixel.
// Output changes only within the first three clocks of frame blanking.
module case4_demo_shape_candidates #(
    parameter integer IMG_WIDTH=1920, IMG_HEIGHT=1080,
    parameter integer MIN_SPAN=32, MIN_POINTS=48,
    parameter integer DS_LOG2=2, CANDIDATES=4, MAX_LABELS=512
)(
    input wire clk,rst_n,frame_start,pixel_valid,
    input wire [10:0] x,y,input wire edge_bit,
    output reg [1:0] shape,
    output reg [10:0] bbox_x0,bbox_x1,bbox_y0,bbox_y1,
    output reg [7:0] confidence,
    output wire candidate_overflow,
    output reg observation_valid,result_tick
);
    wire toggle,busy;
    wire [CANDIDATES-1:0] acquired_valid;
    wire [10:0] acquired_x0[0:CANDIDATES-1],acquired_x1[0:CANDIDATES-1];
    wire [10:0] acquired_y0[0:CANDIDATES-1],acquired_y1[0:CANDIDATES-1];
    case4_component_candidates #(.IMG_WIDTH(IMG_WIDTH),.IMG_HEIGHT(IMG_HEIGHT),
        .DS_LOG2(DS_LOG2),.CANDIDATES(CANDIDATES),.MAX_LABELS(MAX_LABELS),.MIN_SPAN(MIN_SPAN)) acquire(
        .clk(clk),.rst_n(rst_n),.frame_start(frame_start),.pixel_valid(pixel_valid),
        .x(x),.y(y),.edge_bit(edge_bit),.candidate_toggle(toggle),.busy(busy),
        .overflow(candidate_overflow),.candidate_valid(acquired_valid),
        .box_x0(acquired_x0),.box_x1(acquired_x1),.box_y0(acquired_y0),.box_y1(acquired_y1));
    reg [1:0] frame_pipe;
    reg seen_toggle;
    reg [1:0] age;
    reg [CANDIDATES-1:0] active;
    reg [10:0] rx0[0:CANDIDATES-1],rx1[0:CANDIDATES-1],ry0[0:CANDIDATES-1],ry1[0:CANDIDATES-1];
    wire [CANDIDATES-1:0] circle_fit,rect_fit;
    wire [15:0] circle_score[0:CANDIDATES-1],rect_score[0:CANDIDATES-1];
    function automatic has_seven(input [7:0] mask);
        reg [7:0] holes;
        begin holes=~mask;has_seven=(holes&(holes-8'd1))==0;end
    endfunction
    genvar g;
    generate for(g=0;g<CANDIDATES;g=g+1) begin: fit
        wire [11:0] w={1'b0,rx1[g]}-{1'b0,rx0[g]}+12'd1;
        wire [11:0] h={1'b0,ry1[g]}-{1'b0,ry0[g]}+12'd1;
        wire [11:0] span=w>h?w:h;
        wire [11:0] difference=w>h?w-h:h-w;
        wire [12:0] sum={1'b0,w}+{1'b0,h};
        wire [11:0] margin=(1<<DS_LOG2)+4+(span>>5);
        wire [11:0] radius=sum>>1; // radius in doubled-coordinate units
        reg [11:0] radius_lo,radius_hi;
        reg [23:0] lo_sq,hi_sq,box_area;
        always @(posedge clk) begin
            if(frame_pipe[0]) begin
                radius_lo<=radius>2*margin?radius-2*margin:0;radius_hi<=radius+2*margin;box_area<=w*h;
            end
            if(frame_pipe[1]) begin lo_sq<=radius_lo*radius_lo;hi_sq<=radius_hi*radius_hi;end
        end
        wire [11:0] xx={1'b0,x},yy={1'b0,y};
        wire [11:0] ax0={1'b0,rx0[g]},ax1={1'b0,rx1[g]};
        wire [11:0] ay0={1'b0,ry0[g]},ay1={1'b0,ry1[g]};
        wire region=xx+margin>=ax0 && xx<=ax1+margin && yy+margin>=ay0 && yy<=ay1+margin;
        wire [11:0] dl=xx>ax0?xx-ax0:ax0-xx,dr=xx>ax1?xx-ax1:ax1-xx;
        wire [11:0] dt=yy>ay0?yy-ay0:ay0-yy,db=yy>ay1?yy-ay1:ay1-yy;
        wire [3:0] near_side={db<=margin,dt<=margin,dr<=margin,dl<=margin};
        wire [3:0] wide_side={db<=2*margin,dt<=2*margin,dr<=2*margin,dl<=2*margin};
        wire signed [12:0] dx=$signed({1'b0,x,1'b0})-$signed({1'b0,rx0[g]})-$signed({1'b0,rx1[g]});
        wire signed [12:0] dy=$signed({1'b0,y,1'b0})-$signed({1'b0,ry0[g]})-$signed({1'b0,ry1[g]});
        wire [12:0] adx=dx[12]?-dx:dx,ady=dy[12]?-dy:dy;
        wire [2:0] sector=(ady*2<adx)?(dx[12]?3'd4:3'd0):
            (adx*2<ady)?(dy[12]?3'd6:3'd2):
            dy[12]?(dx[12]?3'd5:3'd7):(dx[12]?3'd3:3'd1);
        // Eight spatial bins per side measure coverage rather than thickness.
        // A thick fragment cannot compensate for a long missing contour segment.
        wire [11:0] step_x=w>>3,step_y=h>>3;
        wire [2:0] bin_x=xx>=ax0+7*step_x?7:xx>=ax0+6*step_x?6:xx>=ax0+5*step_x?5:
            xx>=ax0+4*step_x?4:xx>=ax0+3*step_x?3:xx>=ax0+2*step_x?2:xx>=ax0+step_x?1:0;
        wire [2:0] bin_y=yy>=ay0+7*step_y?7:yy>=ay0+6*step_y?6:yy>=ay0+5*step_y?5:
            yy>=ay0+4*step_y?4:yy>=ay0+3*step_y?3:yy>=ay0+2*step_y?2:yy>=ay0+step_y?1:0;
        reg [2:0] bin_x0,bin_x1,bin_x2,bin_y0,bin_y1,bin_y2;
        reg [7:0] coverage[0:3];
        reg signed [12:0] dx0,dy0;
        reg [25:0] sx1,sy1;
        reg [2:0] valid,sector0,sector1,sector2;
        reg [3:0] side0,side1,side2;
        reg wide0,wide1,wide2,ring2,outer2;
        wire [26:0] distance_sq={1'b0,sx1}+{1'b0,sy1};
        reg [15:0] count,ring_count,outer_count,side_count,wide_count;
        reg [15:0] sides[0:3],sectors[0:7];
        reg [3:0] corners;
        integer j;
        always @(posedge clk) begin
            if(!rst_n||frame_start) begin
                valid<=0;count<=0;ring_count<=0;outer_count<=0;side_count<=0;wide_count<=0;corners<=0;
                for(j=0;j<4;j=j+1) begin sides[j]<=0;coverage[j]<=0;end
                for(j=0;j<8;j=j+1) sectors[j]<=0;
            end else begin
                valid<={valid[1:0],active[g]&&pixel_valid&&edge_bit&&region};
                if(pixel_valid&&edge_bit) begin dx0<=dx;dy0<=dy;side0<=near_side;wide0<=|wide_side;sector0<=sector;bin_x0<=bin_x;bin_y0<=bin_y;end
                if(valid[0]) begin sx1<=dx0*dx0;sy1<=dy0*dy0;side1<=side0;wide1<=wide0;sector1<=sector0;bin_x1<=bin_x0;bin_y1<=bin_y0;end
                if(valid[1]) begin ring2<=distance_sq>=lo_sq&&distance_sq<=hi_sq;
                outer2<=distance_sq>=lo_sq;
                side2<=side1;wide2<=wide1;sector2<=sector1;bin_x2<=bin_x1;bin_y2<=bin_y1;end
                if(valid[2]) begin
                    if(count!=16'hffff) count<=count+1'b1;
                    if(outer2&&outer_count!=16'hffff) outer_count<=outer_count+1'b1;
                    if(ring2) begin
                        if(ring_count!=16'hffff) ring_count<=ring_count+1'b1;
                        if(sectors[sector2]!=16'hffff) sectors[sector2]<=sectors[sector2]+1'b1;
                    end
                    if(wide2&&wide_count!=16'hffff) wide_count<=wide_count+1'b1;
                    if(|side2) begin
                        if(side_count!=16'hffff) side_count<=side_count+1'b1;
                        for(j=0;j<4;j=j+1) if(side2[j]&&sides[j]!=16'hffff) sides[j]<=sides[j]+1'b1;
                        if(side2[0]) coverage[0][bin_y2]<=1;
                        if(side2[1]) coverage[1][bin_y2]<=1;
                        if(side2[2]) coverage[2][bin_x2]<=1;
                        if(side2[3]) coverage[3][bin_x2]<=1;
                        if(side2[0]&&side2[2]) corners[0]<=1;
                        if(side2[1]&&side2[2]) corners[1]<=1;
                        if(side2[0]&&side2[3]) corners[2]<=1;
                        if(side2[1]&&side2[3]) corners[3]<=1;
                    end
                end
            end
        end
        wire enough=active[g]&&w>=MIN_SPAN&&h>=MIN_SPAN&&count>=MIN_POINTS&&
            count>=(sum>>1)&&{8'b0,count}<=(box_area>>1)&&rx0[g]>IMG_WIDTH/2+2&&rx1[g]<IMG_WIDTH-3&&
            ry0[g]>2&&ry1[g]<IMG_HEIGHT-3;
        wire sectors_ok=sectors[0]>=(span>>5)&&sectors[1]>=(span>>5)&&
            sectors[2]>=(span>>5)&&sectors[3]>=(span>>5)&&sectors[4]>=(span>>5)&&
            sectors[5]>=(span>>5)&&sectors[6]>=(span>>5)&&sectors[7]>=(span>>5);
        assign circle_fit[g]=enough&&difference<=(span>>3)&&sectors_ok&&
            ring_count>=sum&&({4'b0,ring_count}*10)>=( {4'b0,outer_count}*7);
        // Corners plus long support on all four sides reject circular extrema.
        assign rect_fit[g]=enough&&(&corners)&&side_count>=sum&&
            has_seven(coverage[0])&&has_seven(coverage[1])&&has_seven(coverage[2])&&has_seven(coverage[3])&&
            sides[0]>=(h>>1)&&sides[1]>=(h>>1)&&sides[2]>=(w>>1)&&sides[3]>=(w>>1)&&
            ({4'b0,side_count}*10)>=({4'b0,wide_count}*8);
        assign circle_score[g]=ring_count;assign rect_score[g]=side_count;
    end endgenerate
    reg [CANDIDATES-1:0] evaluated_circle,evaluated_rect;
    reg [15:0] evaluated_score[0:CANDIDATES-1];
    reg [10:0] evaluated_x0[0:CANDIDATES-1],evaluated_x1[0:CANDIDATES-1];
    reg [10:0] evaluated_y0[0:CANDIDATES-1],evaluated_y1[0:CANDIDATES-1];
    reg [1:0] picked_shape,pending_shape;
    reg [15:0] picked_score;
    reg [10:0] picked_x0,picked_x1,picked_y0,picked_y1;
    reg [10:0] pending_x0,pending_x1,pending_y0,pending_y1;
    reg [1:0] miss_count;
    wire [11:0] pending_w={1'b0,pending_x1}-{1'b0,pending_x0}+12'd1;
    wire [11:0] pending_h={1'b0,pending_y1}-{1'b0,pending_y0}+12'd1;
    wire [11:0] move_tolerance=12'd8+((pending_w>pending_h?pending_w:pending_h)>>3);
    wire consistent=picked_shape==pending_shape&&picked_shape!=0&&
        ({1'b0,picked_x0}+move_tolerance>={1'b0,pending_x0})&&({1'b0,pending_x0}+move_tolerance>={1'b0,picked_x0})&&
        ({1'b0,picked_x1}+move_tolerance>={1'b0,pending_x1})&&({1'b0,pending_x1}+move_tolerance>={1'b0,picked_x1})&&
        ({1'b0,picked_y0}+move_tolerance>={1'b0,pending_y0})&&({1'b0,pending_y0}+move_tolerance>={1'b0,picked_y0})&&
        ({1'b0,picked_y1}+move_tolerance>={1'b0,pending_y1})&&({1'b0,pending_y1}+move_tolerance>={1'b0,picked_y1});
    integer i;
    reg [15:0] best_score;
    always @(posedge clk) begin
        if(!rst_n) begin
            active<=0;seen_toggle<=0;age<=0;shape<=0;confidence<=0;observation_valid<=0;result_tick<=0;
            bbox_x0<=0;bbox_x1<=0;bbox_y0<=0;bbox_y1<=0;
            frame_pipe<=0;evaluated_circle<=0;evaluated_rect<=0;
            picked_shape<=0;pending_shape<=0;picked_score<=0;miss_count<=0;
            picked_x0<=0;picked_x1<=0;picked_y0<=0;picked_y1<=0;
            pending_x0<=0;pending_x1<=0;pending_y0<=0;pending_y1<=0;
            for(i=0;i<CANDIDATES;i=i+1) begin
                rx0[i]<=0;rx1[i]<=0;ry0[i]<=0;ry1[i]<=0;evaluated_score[i]<=0;
                evaluated_x0[i]<=0;evaluated_x1[i]<=0;evaluated_y0[i]<=0;evaluated_y1[i]<=0;
            end
        end else begin
            result_tick<=0;
            frame_pipe<={frame_pipe[0],frame_start};
            if(frame_start) begin
                evaluated_circle<=circle_fit;evaluated_rect<=rect_fit;
                for(i=0;i<CANDIDATES;i=i+1) begin
                    evaluated_score[i]<=rect_fit[i]?rect_score[i]:circle_score[i];
                    evaluated_x0[i]<=rx0[i];evaluated_x1[i]<=rx1[i];
                    evaluated_y0[i]<=ry0[i];evaluated_y1[i]<=ry1[i];
                end
                if(toggle!=seen_toggle) begin
                    seen_toggle<=toggle;active<=acquired_valid;age<=0;
                    for(i=0;i<CANDIDATES;i=i+1) begin
                        rx0[i]<=acquired_x0[i];rx1[i]<=acquired_x1[i];
                        ry0[i]<=acquired_y0[i];ry1[i]<=acquired_y1[i];
                    end
                end else if(age==2) active<=0;else age<=age+1'b1;
            end
            if(frame_pipe[0]) begin
                best_score=0;picked_shape<=0;picked_score<=0;
                for(i=0;i<CANDIDATES;i=i+1) if((evaluated_rect[i]||evaluated_circle[i])&&evaluated_score[i]>best_score) begin
                    best_score=evaluated_score[i];picked_score<=evaluated_score[i];
                    picked_shape<=evaluated_rect[i]?2:1;
                    picked_x0<=evaluated_x0[i];picked_x1<=evaluated_x1[i];
                    picked_y0<=evaluated_y0[i];picked_y1<=evaluated_y1[i];
                end
            end
            if(frame_pipe[1]) begin
                // Keep UI smoothing separate from actual measured observations.
                result_tick<=1;observation_valid<=consistent;
                pending_shape<=picked_shape;
                pending_x0<=picked_x0;pending_x1<=picked_x1;pending_y0<=picked_y0;pending_y1<=picked_y1;
                if(consistent) begin
                    shape<=picked_shape;bbox_x0<=picked_x0;bbox_x1<=picked_x1;bbox_y0<=picked_y0;bbox_y1<=picked_y1;
                    confidence<=picked_score>1020?8'hff:picked_score[9:2];miss_count<=0;
                end else if(miss_count<1) miss_count<=miss_count+1'b1;
                else begin shape<=0;confidence<=0;end
            end
        end
    end
endmodule



