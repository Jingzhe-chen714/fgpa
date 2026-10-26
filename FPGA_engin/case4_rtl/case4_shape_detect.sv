`timescale 1ns/1ps
// Geometric demonstration detector for ONE isolated, stationary outline in
// the right-hand image ROI. It is not a general object recognizer. Two stable
// frames are required; clutter, incomplete outlines and boundary-touching
// shapes are rejected. Edges may be Sobel or Canny. Two one-bit historical row buffers
// remove isolated edge specks before bounding-box statistics; no frame RAM.
// pixel_valid must mark every raster pixel, including non-edge pixels.
// frame_start must be in vertical blanking, >=6 clocks after the last pixel.
// Results describe the preceding frame and stay fixed for the next frame.
module case4_shape_detect #(
    parameter integer IMG_WIDTH=1280,
    parameter integer IMG_HEIGHT=720,
    parameter integer MIN_SPAN=20,
    parameter integer MIN_POINTS=40
) (
    input wire clk, rst_n,
    input wire frame_start, pixel_valid,
    input wire [10:0] x,
    input wire [10:0] y,
    input wire edge_bit,
    output reg [1:0] shape,
    output reg [10:0] bbox_x0,bbox_x1,
    output reg [10:0] bbox_y0,bbox_y1
);
    localparam integer ROI_X0=IMG_WIDTH/2;
    localparam integer XB=$clog2(IMG_WIDTH),YB=$clog2(IMG_HEIGHT);
    wire window_valid;
    wire [XB-1:0] window_x;
    wire [YB-1:0] window_y;
    wire n00,n01,n02,n10,n11,n12,n20,n21,n22;
    case4_window3x3 #(.DATA_BITS(1),.IMG_WIDTH(IMG_WIDTH),.IMG_HEIGHT(IMG_HEIGHT)) despeckle(
        .clk(clk),.rst(!rst_n||frame_start),.in_valid(pixel_valid),
        .in_x(x[XB-1:0]),.in_y(y[YB-1:0]),.in_pixel(edge_bit),
        .out_valid(window_valid),.out_x(window_x),.out_y(window_y),
        .p00(n00),.p01(n01),.p02(n02),.p10(n10),.p11(n11),.p12(n12),
        .p20(n20),.p21(n21),.p22(n22));
    wire clean_edge=window_valid&&n11&&(n00||n01||n02||n10||n12||n20||n21||n22);
    wire [10:0] fx=window_x;
    wire [10:0] fy=window_y;
    reg [10:0] min_x,max_x,ref_x0,ref_x1;
    reg [10:0] min_y,max_y,ref_y0,ref_y1;
    reg have_ref;
    reg [19:0] count,side_count,ring_count;
    reg [19:0] left_count,right_count,top_count,bottom_count;
    reg [19:0] quadrant [0:3];
    reg [3:0] corner_seen;
    wire [10:0] width_now=max_x-min_x;
    wire [10:0] height_now=max_y-min_y;
    wire [11:0] wh_sum={1'b0,width_now}+{1'b0,height_now};
    wire [11:0] ref_wh_sum={1'b0,(ref_x1-ref_x0)}+{1'b0,(ref_y1-ref_y0)};
    wire [10:0] ref_radius=ref_wh_sum[11:1];
    reg [10:0] radius_lo,radius_hi;
    reg [21:0] radius_lo_sq,radius_hi_sq;
    reg [2:0] v;
    reg signed [12:0] dx0,dy0;
    reg [25:0] dx_sq1,dy_sq1;
    reg [10:0] x0,x1,x2;
    reg [10:0] y0,y1,y2;
    reg [3:0] sides0,sides1,sides2;
    reg [3:0] corner_sides0;
    reg corner1,corner2;
    reg [1:0] quadrant0,quadrant1,quadrant2;
    reg in_ring2;
    wire [26:0] distance_sq={1'b0,dx_sq1}+{1'b0,dy_sq1};
    wire stable_box=have_ref &&
        ({1'b0,min_x}+12'd2 >= {1'b0,ref_x0}) && ({1'b0,ref_x0}+12'd2 >= {1'b0,min_x}) &&
        ({1'b0,max_x}+12'd2 >= {1'b0,ref_x1}) && ({1'b0,ref_x1}+12'd2 >= {1'b0,max_x}) &&
        ({1'b0,min_y}+12'd2 >= {1'b0,ref_y0}) && ({1'b0,ref_y0}+12'd2 >= {1'b0,min_y}) &&
        ({1'b0,max_y}+12'd2 >= {1'b0,ref_y1}) && ({1'b0,ref_y1}+12'd2 >= {1'b0,max_y});
    wire [22:0] side_x5=({3'b0,side_count}<<2)+{3'b0,side_count};
    wire [22:0] ring_x5=({3'b0,ring_count}<<2)+{3'b0,ring_count};
    wire [22:0] count_x4={1'b0,count,2'b0};
    wire [10:0] largest_span=width_now>height_now?width_now:height_now;
    wire [10:0] span_difference=width_now>height_now?width_now-height_now:height_now-width_now;
    wire enough_outline=count>=MIN_POINTS && width_now>=MIN_SPAN && height_now>=MIN_SPAN &&
        count>=wh_sum && count<=({8'b0,wh_sum}<<3) &&
        min_x>ROI_X0+2 && max_x<IMG_WIDTH-3 && min_y>2 && max_y<IMG_HEIGHT-3;
    wire rectangle_fit=side_x5>=count_x4 &&
        left_count>=(height_now>>1) && right_count>=(height_now>>1) &&
        top_count>=(width_now>>1) && bottom_count>=(width_now>>1) &&
        (&corner_seen);
    wire circle_fit=ring_x5>=count_x4 && span_difference<=(largest_span>>3) &&
        quadrant[0]>=(count>>3) && quadrant[1]>=(count>>3) &&
        quadrant[2]>=(count>>3) && quadrant[3]>=(count>>3);
    integer q;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            v<=0; dx0<=0; dy0<=0; dx_sq1<=0; dy_sq1<=0;
            x0<=0;x1<=0;x2<=0;y0<=0;y1<=0;y2<=0;
            sides0<=0;sides1<=0;sides2<=0;
            corner_sides0<=0;corner1<=0;corner2<=0;
            quadrant0<=0;quadrant1<=0;quadrant2<=0;in_ring2<=0;
            radius_lo<=0;radius_hi<=0;radius_lo_sq<=0;radius_hi_sq<=0;
        end else begin
            // These configuration products settle during vertical blanking.
            radius_lo<=ref_radius>8?ref_radius-11'd8:0;
            radius_hi<=ref_radius+11'd8;
            radius_lo_sq<=radius_lo*radius_lo;
            radius_hi_sq<=radius_hi*radius_hi;
            v<={v[1:0],clean_edge && fx>=ROI_X0 && fx<IMG_WIDTH && fy<IMG_HEIGHT};
            dx0<=$signed({1'b0,fx,1'b0})-$signed({2'b0,ref_x0})-$signed({2'b0,ref_x1});
            dy0<=$signed({1'b0,fy,1'b0})-$signed({2'b0,ref_y0})-$signed({2'b0,ref_y1});
            dx_sq1<=dx0*dx0;
            dy_sq1<=dy0*dy0;
            in_ring2<=distance_sq>=radius_lo_sq && distance_sq<=radius_hi_sq;
            x0<=fx;x1<=x0;x2<=x1;y0<=fy;y1<=y0;y2<=y1;
            // Up to three-pixel Sobel thickness plus two-pixel frame jitter.
            sides0[0]<=({1'b0,fx}+12'd4 >= {1'b0,ref_x0}) && ({1'b0,ref_x0}+12'd4 >= {1'b0,fx});
            sides0[1]<=({1'b0,fx}+12'd4 >= {1'b0,ref_x1}) && ({1'b0,ref_x1}+12'd4 >= {1'b0,fx});
            sides0[2]<=({1'b0,fy}+12'd4 >= {1'b0,ref_y0}) && ({1'b0,ref_y0}+12'd4 >= {1'b0,fy});
            sides0[3]<=({1'b0,fy}+12'd4 >= {1'b0,ref_y1}) && ({1'b0,ref_y1}+12'd4 >= {1'b0,fy});
            sides1<=sides0;sides2<=sides1;
            // Widened side tolerance alone can confuse a small circle with
            // a square. Require evidence at all four tighter corner regions.
            corner_sides0[0]<=({1'b0,fx}+12'd2 >= {1'b0,ref_x0}) && ({1'b0,ref_x0}+12'd2 >= {1'b0,fx});
            corner_sides0[1]<=({1'b0,fx}+12'd2 >= {1'b0,ref_x1}) && ({1'b0,ref_x1}+12'd2 >= {1'b0,fx});
            corner_sides0[2]<=({1'b0,fy}+12'd2 >= {1'b0,ref_y0}) && ({1'b0,ref_y0}+12'd2 >= {1'b0,fy});
            corner_sides0[3]<=({1'b0,fy}+12'd2 >= {1'b0,ref_y1}) && ({1'b0,ref_y1}+12'd2 >= {1'b0,fy});
            corner1<=(|corner_sides0[1:0])&&(|corner_sides0[3:2]);
            corner2<=corner1;
            quadrant0<={({1'b0,fy,1'b0} >= ({2'b0,ref_y0}+{2'b0,ref_y1})),
                         ({1'b0,fx,1'b0} >= ({2'b0,ref_x0}+{2'b0,ref_x1}))};
            quadrant1<=quadrant0;quadrant2<=quadrant1;
            if(frame_start) v<=0;
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            shape<=0;bbox_x0<=0;bbox_x1<=0;bbox_y0<=0;bbox_y1<=0;
            min_x<=IMG_WIDTH-1;max_x<=0;min_y<=IMG_HEIGHT-1;max_y<=0;
            ref_x0<=0;ref_x1<=0;ref_y0<=0;ref_y1<=0;have_ref<=0;
            count<=0;side_count<=0;ring_count<=0;
            left_count<=0;right_count<=0;top_count<=0;bottom_count<=0;
            corner_seen<=0;
            for(q=0;q<4;q=q+1) quadrant[q]<=0;
        end else if(frame_start) begin
            shape<=0;
            if(stable_box && enough_outline) begin
                if(rectangle_fit) shape<=2;
                else if(circle_fit) shape<=1;
            end
            bbox_x0<=count!=0?min_x:0;bbox_x1<=count!=0?max_x:0;
            bbox_y0<=count!=0?min_y:0;bbox_y1<=count!=0?max_y:0;
            have_ref<=count>=MIN_POINTS;
            ref_x0<=min_x;ref_x1<=max_x;ref_y0<=min_y;ref_y1<=max_y;
            min_x<=IMG_WIDTH-1;max_x<=0;min_y<=IMG_HEIGHT-1;max_y<=0;
            count<=0;side_count<=0;ring_count<=0;
            left_count<=0;right_count<=0;top_count<=0;bottom_count<=0;
            corner_seen<=0;
            for(q=0;q<4;q=q+1) quadrant[q]<=0;
        end else if(v[2]) begin
            if(x2<min_x) min_x<=x2;
            if(x2>max_x) max_x<=x2;
            if(y2<min_y) min_y<=y2;
            if(y2>max_y) max_y<=y2;
            count<=count+1'b1;
            if(|sides2) side_count<=side_count+1'b1;
            if(sides2[0]) left_count<=left_count+1'b1;
            if(sides2[1]) right_count<=right_count+1'b1;
            if(sides2[2]) top_count<=top_count+1'b1;
            if(sides2[3]) bottom_count<=bottom_count+1'b1;
            if(in_ring2) ring_count<=ring_count+1'b1;
            quadrant[quadrant2]<=quadrant[quadrant2]+1'b1;
            if(corner2) corner_seen[quadrant2]<=1'b1;
        end
    end
endmodule
