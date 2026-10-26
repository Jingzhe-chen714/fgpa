`timescale 1ns/1ps
// V10 ROI-local bounded connected-component capture. No old release is changed.
// A 128x128 map uses equal x/y scaling selected from the ROI maximum span.
// All map entries are explicitly cleared before arming a fresh observation.
module case4_v11_components #(
 parameter integer IMG_WIDTH=1920,IMG_HEIGHT=1080,
 parameter integer GAP_CELLS=1,MAX_POINTS=1024,FIFO_DEPTH=1024,STORE_POINTS=1,SINGLE_MAP=1,
 parameter integer MAX_ANALYSIS_CYCLES=4000000,
 parameter integer GW=128, GH=128,
 parameter integer AB=$clog2(GW*GH),GX=$clog2(GW),GY=$clog2(GH),
 parameter integer PB=$clog2(MAX_POINTS),FB=$clog2(FIFO_DEPTH)
)(
 input wire clk,rst_n,clear,frame_start,sample_tick,pixel_valid,
 input wire [10:0] x,y,input wire mask_bit,
 input wire [10:0] roi_x0,roi_y0,roi_x1,roi_y1,
 output reg [10:0] active_roi_x0,active_roi_y0,active_roi_x1,active_roi_y1,
 output reg [2:0] ds_log2,
 output reg busy,overflow,frame_done,component_ready,
 output wire capture_started,capture_incomplete,
 input wire component_accept,
 output reg [10:0] bx0,bx1,by0,by1,
 output reg [PB:0] point_count,output reg component_too_large,
 input wire [PB-1:0] point_index,
 output reg [GX-1:0] point_x,output reg [GY-1:0] point_y
);
 localparam integer N=GW*GH;
 reg [AB-1:0] clear_address;
 reg [AB:0] expected_cells;
 wire [11:0] request_width={1'b0,roi_x1}-{1'b0,roi_x0}+1;
 wire [11:0] request_height={1'b0,roi_y1}-{1'b0,roi_y0}+1;
 wire [11:0] request_span=request_width>request_height?request_width:request_height;
 wire [2:0] requested_ds=request_span<=128?0:request_span<=256?1:request_span<=512?2:request_span<=1024?3:4;
 wire [11:0] request_step=12'd1<<requested_ds;
 wire [7:0] request_cols=(request_width+request_step-1)>>requested_ds;
 wire [7:0] request_rows=(request_height+request_step-1)>>requested_ds;
 wire [10:0] ds_mask=(11'd1<<ds_log2)-1;
 localparam integer MEMORY_DEPTH=STORE_POINTS&&MAX_POINTS>FIFO_DEPTH?MAX_POINTS:FIFO_DEPTH;
 localparam integer MB=$clog2(MEMORY_DEPTH);
 localparam [3:0] IDLE=0,SCAN_READ=1,SCAN_WAIT=2,POP_READ=3,POP_WAIT=4,
   NEIGH_READ=5,NEIGH_WAIT=6,COMPONENT=7,ADVANCE=8,FAILED=9,CLEAR_MAP=10;
 reg [3:0] state;
 reg map0[0:N-1],map1[0:N-1];
 // FIFO order is exactly the component traversal order. For a fitting-sized
 // component the consumed slots are retained as its point list. Oversized
 // components reuse the same circular FIFO while draining, and are not fitted.
 reg [GX+GY-1:0] fifo[0:MEMORY_DEPTH-1];
 reg [GW-1:0] column_or;
 // Preserve even a single boundary/tangent sample in every reduction cell.
 // The upstream edge/temporal stages handle isolated-pixel noise; irreversible
 // per-cell hit-count thresholds change curved envelopes with grid phase.
 reg capture_bank,process_bank,capture_active;
 reg [AB:0] capture_count;
 wire [10:0] local_x=x-active_roi_x0;
 wire [10:0] local_y=y-active_roi_y0;
 wire [GX-1:0] block_x=local_x>>ds_log2;
 wire take=capture_active&&pixel_valid&&x>=active_roi_x0&&x<=active_roi_x1&&y>=active_roi_y0&&y<=active_roi_y1;
 wire emit_cell=take&&((local_x&ds_mask)==ds_mask||x==active_roi_x1)&&
   ((local_y&ds_mask)==ds_mask||y==active_roi_y1);
 wire launch=frame_start&&capture_active&&capture_count==expected_cells&&!busy;
 assign capture_started=frame_start&&sample_tick&&(!SINGLE_MAP||(!busy&&!launch));
 assign capture_incomplete=frame_start&&capture_active&&capture_count!=expected_cells;
 reg [AB-1:0] scan_address,read_address;
 reg [GX-1:0] scan_x,cx,nx;
 reg [GY-1:0] scan_y,cy,ny;
 reg [4:0] neighbor;
 reg neighbor_ok;
 reg [FB:0] queued;
 reg [MB-1:0] head,tail;
 reg [GX+GY-1:0] fifo_q;
 reg map_q0,map_q1;
 wire map_q=SINGLE_MAP?map_q0:process_bank?map_q1:map_q0;
 wire read_map=state==SCAN_READ||(state==NEIGH_READ&&neighbor_ok);
 wire enqueue=(state==SCAN_WAIT&&map_q)||(state==NEIGH_WAIT&&neighbor_ok&&map_q);
 wire [GX-1:0] push_x=state==SCAN_WAIT?scan_x:nx;
 wire [GY-1:0] push_y=state==SCAN_WAIT?scan_y:ny;
 wire [AB-1:0] erase_address=state==SCAN_WAIT?scan_address:read_address;
 wire erase=enqueue&&queued<FIFO_DEPTH;
 wire capture_we=emit_cell&&capture_count<N;
 wire map0_capture=capture_we&&!capture_bank,map1_capture=capture_we&&capture_bank;
 wire map0_we=state==CLEAR_MAP||map0_capture||(erase&&!process_bank),map1_we=!SINGLE_MAP&&(map1_capture||(erase&&process_bank));
 wire [AB-1:0] capture_address=((local_y>>ds_log2)*GW)+block_x;
 wire [AB-1:0] map0_wa=state==CLEAR_MAP?clear_address:map0_capture?capture_address:erase_address;
 wire [AB-1:0] map1_wa=map1_capture?capture_count[AB-1:0]:erase_address;
 wire occupied_cell=column_or[block_x]||mask_bit;
 wire map0_wd=state!=CLEAR_MAP&&map0_capture&&occupied_cell;
 wire map1_wd=map1_capture&&occupied_cell;
 wire [MB-1:0] queue_write_address=state==SCAN_WAIT?{MB{1'b0}}:tail;
 wire point_read=STORE_POINTS&&state==COMPONENT;
 wire [MB-1:0] queue_read_address=point_read?point_index:head;
 // One muxed write port and synchronous read port per bitmap. SINGLE_MAP
 // removes the second bitmap at synthesis. No capture is armed during analysis;
 // a fresh observation arriving while busy is dropped, never partially mixed.
 // Dual-map builds retain the original capture/analysis overlap option.
 always @(posedge clk) begin
   if(map0_we)map0[map0_wa]<=map0_wd;
   if(map1_we)map1[map1_wa]<=map1_wd;
   if(read_map) begin map_q0<=map0[read_address];map_q1<=map1[read_address];end
   if(erase)fifo[queue_write_address]<={push_y,push_x};
   if(state==POP_READ||point_read)fifo_q<=fifo[queue_read_address];
   if(point_read)begin point_x<=fifo_q[GX-1:0];point_y<=fifo_q[GX+GY-1:GX];end
 end
 // Neighbor displacement is in [-3,3]; retain sign without 32-bit adders.
 reg signed [3:0] ox,oy;
 always @* begin
   ox=0;oy=0;
   case(neighbor)
    0:begin ox=-1;oy=-1;end 1:begin ox=0;oy=-1;end 2:begin ox=1;oy=-1;end
    3:begin ox=-1;oy=0;end 4:begin ox=1;oy=0;end
    5:begin ox=-1;oy=1;end 6:begin ox=0;oy=1;end 7:begin ox=1;oy=1;end
    8:begin ox=-2;oy=0;end 9:begin ox=2;oy=0;end
    10:begin ox=0;oy=-2;end 11:begin ox=0;oy=2;end
    12:begin ox=-2;oy=-2;end 13:begin ox=2;oy=-2;end
    14:begin ox=-2;oy=2;end 15:begin ox=2;oy=2;end
    // Complete Chebyshev radius-two ring. Oblique dropped samples can
    // be (2,1) apart; the previous axes/diagonals-only ring fragmented them.
    16:begin ox=-2;oy=-1;end 17:begin ox=2;oy=-1;end
    18:begin ox=-2;oy=1;end 19:begin ox=2;oy=1;end
    20:begin ox=-1;oy=-2;end 21:begin ox=1;oy=-2;end
    22:begin ox=-1;oy=2;end 23:begin ox=1;oy=2;end
    24:begin ox=-3;oy=0;end 25:begin ox=3;oy=0;end
    26:begin ox=0;oy=-3;end 27:begin ox=0;oy=3;end
    28:begin ox=-3;oy=-3;end 29:begin ox=3;oy=-3;end
    30:begin ox=-3;oy=3;end 31:begin ox=3;oy=3;end
   endcase
   nx=$signed({1'b0,cx})+ox;ny=$signed({1'b0,cy})+oy;
   neighbor_ok=($signed({1'b0,cx})+ox>=0)&&($signed({1'b0,cx})+ox<GW)&&
     ($signed({1'b0,cy})+oy>=0)&&($signed({1'b0,cy})+oy<GH);
   read_address=state==SCAN_READ?scan_address:ny*GW+nx;
 end
 reg [23:0] work_cycles;
 always @(posedge clk) begin
  if(!rst_n||clear) begin
   state<=CLEAR_MAP;clear_address<=0;busy<=1;overflow<=0;frame_done<=0;component_ready<=0;
   active_roi_x0<=0;active_roi_y0<=0;active_roi_x1<=0;active_roi_y1<=0;ds_log2<=0;expected_cells<=0;
   capture_bank<=0;process_bank<=0;capture_active<=0;capture_count<=0;column_or<=0;
   scan_address<=0;scan_x<=0;scan_y<=0;cx<=0;cy<=0;neighbor<=0;
   head<=0;tail<=0;queued<=0;point_count<=0;component_too_large<=0;
   bx0<=0;bx1<=0;by0<=0;by1<=0;work_cycles<=0;
  end else begin
   frame_done<=0;
   if(frame_start) begin
    capture_active<=sample_tick&&!busy&&!launch;capture_count<=0;column_or<=0;
    if(sample_tick&&!busy&&!launch)begin
      active_roi_x0<=roi_x0;active_roi_y0<=roi_y0;active_roi_x1<=roi_x1;active_roi_y1<=roi_y1;
      ds_log2<=requested_ds;expected_cells<=request_cols*request_rows;
    end
    if(launch) begin
      capture_bank<=SINGLE_MAP?1'b0:!capture_bank;process_bank<=capture_bank;busy<=1;overflow<=0;
      state<=SCAN_READ;scan_address<=0;scan_x<=0;scan_y<=0;work_cycles<=0;
    end
   end else if(take) begin
    column_or[block_x]<=emit_cell?1'b0:column_or[block_x]||mask_bit;
    if(emit_cell&&capture_count<N)capture_count<=capture_count+1'b1;
   end
   if(state==CLEAR_MAP)begin
    if(clear_address==N-1)begin state<=IDLE;busy<=0;clear_address<=0;end
    else clear_address<=clear_address+1'b1;
   end else if(busy)begin
    work_cycles<=work_cycles+1'b1;
    if(work_cycles>=MAX_ANALYSIS_CYCLES&&state!=FAILED)state<=FAILED;
    else case(state)
     SCAN_READ:state<=SCAN_WAIT;
     SCAN_WAIT:if(map_q)begin
       head<=0;tail<=1;queued<=1;point_count<=0;component_too_large<=0;
       bx0<=active_roi_x0+(scan_x<<ds_log2);bx1<=active_roi_x0+((scan_x+11'd1)<<ds_log2)-1;
       by0<=active_roi_y0+(scan_y<<ds_log2);by1<=active_roi_y0+((scan_y+11'd1)<<ds_log2)-1;
       state<=POP_READ;
      end else state<=ADVANCE;
     POP_READ:state<=POP_WAIT;
     POP_WAIT:begin
       cx<=fifo_q[GX-1:0];cy<=fifo_q[GX+GY-1:GX];head<=head+1'b1;queued<=queued-1'b1;
       if(point_count<MAX_POINTS)point_count<=point_count+1'b1;else component_too_large<=1;
       if(active_roi_x0+(fifo_q[GX-1:0]<<ds_log2)<bx0)bx0<=active_roi_x0+(fifo_q[GX-1:0]<<ds_log2);
       if(active_roi_x0+((fifo_q[GX-1:0]+11'd1)<<ds_log2)-1>bx1)bx1<=active_roi_x0+((fifo_q[GX-1:0]+11'd1)<<ds_log2)-1;
       if((active_roi_y0+(fifo_q[GX+GY-1:GX]<<ds_log2))<by0)by0<=active_roi_y0+(fifo_q[GX+GY-1:GX]<<ds_log2);
       if(active_roi_y0+((fifo_q[GX+GY-1:GX]+11'd1)<<ds_log2)-1>by1)by1<=active_roi_y0+((fifo_q[GX+GY-1:GX]+11'd1)<<ds_log2)-1;
       neighbor<=0;state<=NEIGH_READ;
      end
     NEIGH_READ:state<=NEIGH_WAIT;
     NEIGH_WAIT:begin
       if(neighbor_ok&&map_q)begin
         if(queued==FIFO_DEPTH)begin overflow<=1;state<=FAILED;end
         else begin tail<=tail+1'b1;queued<=queued+1'b1;end
       end
       if(!(neighbor_ok&&map_q&&queued==FIFO_DEPTH))begin
        if(neighbor==(GAP_CELLS>1?31:GAP_CELLS?23:7))begin
          if(queued!=0||(neighbor_ok&&map_q))state<=POP_READ;
          else begin state<=COMPONENT;component_ready<=1;end
        end else begin neighbor<=neighbor+1'b1;state<=NEIGH_READ;end
       end
      end
     COMPONENT:if(component_accept)begin component_ready<=0;state<=ADVANCE;end
     ADVANCE:if(scan_address==N-1)begin busy<=1;frame_done<=1;state<=CLEAR_MAP;clear_address<=0;end
      else begin scan_address<=scan_address+1'b1;if(scan_x==GW-1)begin scan_x<=0;scan_y<=scan_y+1'b1;end else scan_x<=scan_x+1'b1;state<=SCAN_READ;end
     FAILED:begin busy<=1;overflow<=1;component_ready<=0;frame_done<=1;state<=CLEAR_MAP;clear_address<=0;end
     default:state<=IDLE;
    endcase
   end
  end
 end
endmodule

module case4_v11_shape #( 
 parameter integer IMG_WIDTH=1920,IMG_HEIGHT=1080,
 parameter integer MIN_SPAN=24,MAX_POINTS=1024,CONFIRM_FRAMES=2,LOSS_FRAMES=3,SINGLE_MAP=1,
 parameter integer GW=128,GH=128,
 parameter integer PB=$clog2(MAX_POINTS),GX=$clog2(GW),GY=$clog2(GH)
)(
 input wire clk,rst_n,clear,enable,frame_start,sample_tick,pixel_valid,
 input wire [10:0] roi_x0,roi_y0,roi_x1,roi_y1,
 input wire [10:0] x,y,input wire edge_bit,
 // V12: circle/ellipse share ONE round-object track. The two valid bits
 // are mutually exclusive renderer-model selectors, not separate classes.
 // Public class/state is (circle_valid | ellipse_valid), always yellow.
 output reg circle_valid,rect_valid,triangle_valid,ellipse_valid,
 output reg [10:0] circle_x0,circle_x1,circle_y0,circle_y1,
 output reg [10:0] rect_x0,rect_x1,rect_y0,rect_y1,
 output wire circle_outline,rect_outline,triangle_outline,ellipse_outline,
 output reg [10:0] triangle_x0,triangle_x1,triangle_y0,triangle_y1,ellipse_x0,ellipse_x1,ellipse_y0,ellipse_y1,
 output reg [7:0] circle_score,rect_score,triangle_score,ellipse_score,
 output wire busy,overflow,output wire sample_accept,output reg result_tick,
 output reg [15:0] observed_count,analysis_count,timeout_count,dropped_count,
 output reg [7:0] candidate_count,circle_best_score,rect_best_score,
 output reg [2:0] reject_reason,
 // Published models for an external, pixel-clock-pipelined overlay renderer.
 // Coordinates/bounds are grid-local Q8 except the native pixel ROI origin.
 output wire [10:0] model_origin_x,model_origin_y,
 output wire [2:0] model_ds,
 output wire [4:0] rect_fit_angle,ellipse_fit_angle,
 output wire signed [18:0] rect_fit_umin,rect_fit_umax,rect_fit_vmin,rect_fit_vmax,
 output wire signed [18:0] ellipse_fit_umin,ellipse_fit_umax,ellipse_fit_vmin,ellipse_fit_vmax,
 output wire [41:0] triangle_vertices,
 output wire [3:0] triangle_tolerance,
 output reg parallel_valid,output reg [7:0] parallel_score,
 output reg [10:0] parallel_x0,parallel_x1,parallel_y0,parallel_y1,
 output wire parallel_outline,output wire [55:0] parallel_vertices,
 output wire [3:0] parallel_tolerance
);
 wire ready,done,oversize,capture_started,capture_incomplete;reg accept;
 // Only this pulse consumes a source ID. !busy alone is insufficient: at a
 // frame boundary an already captured frame can launch analysis while busy
 // still reads low, in which case a simultaneous new capture is not armed.
 assign sample_accept=capture_started&&rst_n&&!reset_fit;
 wire roi_valid=roi_x0<roi_x1&&roi_y0<roi_y1&&roi_x1<IMG_WIDTH&&roi_y1<IMG_HEIGHT;
 reg [43:0] roi_q;
 wire roi_change=frame_start&&roi_q!={roi_x0,roi_y0,roi_x1,roi_y1};
 wire reset_fit=clear||!enable||!roi_valid||roi_change;
 always @(posedge clk)if(!rst_n)roi_q<=0;else if(frame_start)roi_q<={roi_x0,roi_y0,roi_x1,roi_y1};
 wire [10:0] origin_x,origin_y,limit_x,limit_y;wire [2:0] ds;
 reg [10:0] publish_origin_x,publish_origin_y;reg [2:0] publish_ds;
 wire [10:0] bx0,bx1,by0,by1;wire [PB:0] count;
 reg [PB-1:0] index;
 wire [GX-1:0] px;wire [GY-1:0] py;
 case4_v11_components #(.IMG_WIDTH(IMG_WIDTH),.IMG_HEIGHT(IMG_HEIGHT),.MAX_POINTS(MAX_POINTS),.GAP_CELLS(1),.SINGLE_MAP(SINGLE_MAP)) components(
  .clk(clk),.rst_n(rst_n),.clear(reset_fit),.frame_start(frame_start),.sample_tick(sample_tick&&enable&&roi_valid&&!roi_change),
  .roi_x0(roi_x0),.roi_y0(roi_y0),.roi_x1(roi_x1),.roi_y1(roi_y1),
  .active_roi_x0(origin_x),.active_roi_y0(origin_y),.active_roi_x1(limit_x),.active_roi_y1(limit_y),.ds_log2(ds),.pixel_valid(pixel_valid),
  .x(x),.y(y),.mask_bit(edge_bit),.capture_started(capture_started),.capture_incomplete(capture_incomplete),.busy(busy),.overflow(overflow),.frame_done(done),.component_ready(ready),.component_accept(accept),
  .bx0(bx0),.bx1(bx1),.by0(by0),.by1(by1),.point_count(count),.component_too_large(oversize),.point_index(index),.point_x(px),.point_y(py));
 // Reuse sixteen orthogonal-line templates over [0,90), step 5.625 degrees.
 // The 32-entry coefficient LUT is stepped by two. This halves fitting time.
 // Only one pair of small coefficient multipliers is reused for all points.
 function automatic signed [9:0] cosine(input [4:0] angle);
  case(angle)0:cosine=256;1:cosine=256;2:cosine=255;3:cosine=253;4:cosine=251;5:cosine=248;6:cosine=245;7:cosine=241;8:cosine=237;9:cosine=231;10:cosine=226;11:cosine=220;12:cosine=213;13:cosine=206;14:cosine=198;15:cosine=190;16:cosine=181;17:cosine=172;18:cosine=162;19:cosine=152;20:cosine=142;21:cosine=132;22:cosine=121;23:cosine=109;24:cosine=98;25:cosine=86;26:cosine=74;27:cosine=62;28:cosine=50;29:cosine=38;30:cosine=25;31:cosine=13;endcase
 endfunction
 function automatic signed [9:0] sine(input [4:0] angle);
  case(angle)0:sine=0;1:sine=13;2:sine=25;3:sine=38;4:sine=50;5:sine=62;6:sine=74;7:sine=86;8:sine=98;9:sine=109;10:sine=121;11:sine=132;12:sine=142;13:sine=152;14:sine=162;15:sine=172;16:sine=181;17:sine=190;18:sine=198;19:sine=206;20:sine=213;21:sine=220;22:sine=226;23:sine=231;24:sine=237;25:sine=241;26:sine=245;27:sine=248;28:sine=251;29:sine=253;30:sine=255;31:sine=256;endcase
 endfunction
 function automatic [3:0] pop8(input [7:0] v);
  integer k;begin pop8=0;for(k=0;k<8;k=k+1)pop8=pop8+v[k];end
 endfunction
 // Genuine edge-to-line support test. Distance is bounded by cross product;
 // dominant-axis bins require coverage along each individual finite side.
 function automatic [3:0] line_support;
  input [6:0] qx,qy,ax0,ay0,bx0,by0;
  input [3:0] tolerance;
  reg signed [8:0] dx,dy,rx,ry;
  reg signed [18:0] line_cross;
  reg [18:0] cross_abs;
  reg [8:0] adx,ady,l1;
  reg [12:0] limit;
  reg [7:0] lo,hi,q,span,offset;
  reg [10:0] span_multiple;
  reg [2:0] bin;
  integer k;
  begin
   dx=$signed({2'b0,bx0})-$signed({2'b0,ax0});dy=$signed({2'b0,by0})-$signed({2'b0,ay0});
   rx=$signed({2'b0,qx})-$signed({2'b0,ax0});ry=$signed({2'b0,qy})-$signed({2'b0,ay0});
   line_cross=dx*ry-dy*rx;cross_abs=line_cross[18]?-line_cross:line_cross;
   adx=dx[8]?-dx:dx;ady=dy[8]?-dy:dy;l1=adx+ady;
   limit=l1*tolerance;
   if(adx>=ady)begin lo=ax0<bx0?ax0:bx0;hi=ax0<bx0?bx0:ax0;q=qx;end
   else begin lo=ay0<by0?ay0:by0;hi=ay0<by0?by0:ay0;q=qy;end
   span=hi-lo;offset=q>=lo?q-lo:0;bin=0;
   // span<=127 for the fixed 128-grid (even 255*7 fits eleven bits).
   for(k=1;k<8;k=k+1)begin span_multiple=span*k;if({offset,3'b0}>=span_multiple)bin=k;end
   line_support={l1>=8&&q+tolerance>=lo&&q<=hi+tolerance&&cross_abs<=limit,bin};
  end
 endfunction
 localparam [4:0] WAIT=0,POINT0=1,POINT1=2,POINT2=3,PROJECT=4,ACCUM=5,NEXT=6,FINISH=7,CIRCLE_SCAN=8,CIRCLE_EVAL=9,
  ELLIPSE_SQUARE=10,ELLIPSE_PRODUCT=11,ELLIPSE_SCAN=12,ELLIPSE_EVAL=13,
  TRI_DIFF=14,TRI_PRODUCT=15,TRI_CROSS=16,TRI_COMPARE=17,TRI_STORE=18,
  ELLIPSE_READ=19,ELLIPSE_TEST=20,RECT_COMMIT=21,ELLIPSE_COMMIT=22,
  PPREP=23,PPRODUCT=24,PCROSS=25,PDOT=26,PCHECK=27,PSTART=28,PCOMMIT=29,TCOMMIT=30;
 reg [4:0] state;reg [4:0] angle;reg fit_pass;
 // Exact fixed-128-grid bounds: |2*p-min-max|<=127; distance2<=32258.
 // Opposite sums<=64516. Width reduction changes no arithmetic predicate.
 reg [15:0] radial_profile[0:15];
 reg [15:0] profile_min,profile_max;
 reg [16:0] opposite_min,opposite_max;
 reg [3:0] opposite_coverage;
 wire [16:0] opposite_radius={1'b0,radial_profile[{1'b0,profile_index[2:0]}]}+
                              {1'b0,radial_profile[{1'b1,profile_index[2:0]}]};
 reg [3:0] profile_index;
 reg [4:0] profile_coverage;
 wire [2:0] quadrant_bin=ay*5<ax?0:ay*3<=ax*2?1:ax*5<ay?4:ax*3<=ay*2?3:2;
 wire [3:0] profile_bin=cdx[7]?(cdy[7]?4'd8+quadrant_bin:4'd8-quadrant_bin):
                                    (cdy[7]?4'd0-quadrant_bin:{1'b0,quadrant_bin});
 integer profile_reset;
 // Every valid grid projection has |value|<=127*(cs+sn)<=45974.
 // Keep seventeen signed bits internally; public models sign-extend to 19.
 reg signed [16:0] u,v,umin,umax,vmin,vmax;
 reg signed [9:0] cs,sn;
 reg [6:0] rad;reg [15:0] distance2,rlo2,rhi2;
 reg [PB:0] ring_hits,side_hits,circle_corner_hits;
 reg [PB:0] ellipse_hits,triangle_hits,triangle_strict_hits;
 reg line_strict_q;reg [2:0] triangle_strict_sides;
 // cs+sn<=362; projection span<=127*362=45974 (Q8).
 // Thus |ellipse_dx/dy|<=ceil(45974/256)=180 and w/h<=180.
 // Squares<=32400; individual products<=1049760000 and their sum<=2099520000.
 // Use sixteen-bit squares, thirty-two-bit products and a 33-bit sum guard.
 reg [32:0] ellipse_profile[0:15],ellipse_min,ellipse_max;
 reg [4:0] ellipse_coverage;
 reg [3:0] ellipse_scan,ellipse_clear_index;reg ellipse_clear_active;
 reg signed [8:0] ellipse_dx,ellipse_dy;
 reg [7:0] ellipse_w,ellipse_h;
 reg [15:0] ellipse_dx2,ellipse_dy2,ellipse_w2,ellipse_h2;
 reg [32:0] ellipse_value;reg [31:0] ellipse_reference;
 wire [7:0] ellipse_ax=ellipse_dx[8]?-ellipse_dx:ellipse_dx;
 wire [7:0] ellipse_ay=ellipse_dy[8]?-ellipse_dy:ellipse_dy;
 reg [15:0] ellipse_nx,ellipse_ny;
 reg [31:0] ellipse_product_x,ellipse_product_y;
 reg [32:0] ellipse_profile_q;
 reg ellipse_point_fit_q,ellipse_profile_grow_q;
 // One synchronous-read, muxed-write 16 x 33 envelope RAM. Sequential
 // clearing runs during the first 16 clocks of each bounding pass, before
 // any envelope access. Every accepted component has >=12 points, each with
 // six point cycles, so the clear always finishes before the fitting pass.
 // Scan prefetch preserves the
 // previous one-bin-per-cycle min/max/coverage calculation exactly.
 wire ellipse_profile_write=rst_n&&!reset_fit&&(ellipse_clear_active||
   (state==ACCUM&&triangle_phase==0&&fit_pass&&ellipse_profile_grow_q));
 wire [3:0] ellipse_profile_wa=ellipse_clear_active?ellipse_clear_index:ellipse_bin;
 wire [32:0] ellipse_profile_wd=ellipse_clear_active?33'd0:ellipse_value;
 wire [3:0] ellipse_profile_ra=state==ELLIPSE_READ?ellipse_bin:
   state==RECT_COMMIT?4'd0:ellipse_scan+4'd1;
 always @(posedge clk)begin
  if(ellipse_profile_write)ellipse_profile[ellipse_profile_wa]<=ellipse_profile_wd;
  if(state==ELLIPSE_READ||state==RECT_COMMIT||state==ELLIPSE_SCAN)
   ellipse_profile_q<=ellipse_profile[ellipse_profile_ra];
 end

 wire [2:0] ellipse_quadrant=ellipse_ny*5<ellipse_nx?0:ellipse_ny*3<=ellipse_nx*2?1:
                              ellipse_nx*5<ellipse_ny?4:ellipse_nx*3<=ellipse_ny*2?3:2;
 wire [3:0] ellipse_bin_next=ellipse_dx[8]?(ellipse_dy[8]?4'd8+ellipse_quadrant:4'd8-ellipse_quadrant):
                                      (ellipse_dy[8]?4'd0-ellipse_quadrant:{1'b0,ellipse_quadrant});
 reg [3:0] ellipse_bin;
 wire ellipse_point_fit=// Retain the outer conic envelope and angular coverage tests. Only the
 // inward stroke band widens, allowing paired boundaries of thick screen
 // strokes to support the SAME outer conic instead of rejecting its inside.
 ellipse_value>=(ellipse_reference>>1)&&
                         ellipse_value<=ellipse_reference+(ellipse_reference>>2)+(ellipse_reference>>4);
 reg [2:0] triangle_phase;
 reg [6:0] tax,tay,tbx,tby,tcx,tcy;
 // A single two-multiplier engine handles vertex search and all three finite
 // sides. Differences, products, cross/limit, comparison, and bin encoding
 // are registered separately. This removes the former bbox -> tolerance ->
 // line multiplier -> hit-enable path without relaxing any matching rule.
 // Coordinates are 0..127: differences need signed 8 bits; products signed
 // 16 bits; cross/squared-distance magnitude is at most 32258.
 reg [15:0] triangle_farthest,triangle_distance,triangle_cross_abs;
 // Grid extent is 1..128; area<=16384, quarter-area<=4096.
 // Existing read stages separate ds variable-shifts from multiplication and
 // the final triangle decision. The integer predicate is bit-for-bit unchanged.
 reg [7:0] triangle_grid_w_q,triangle_grid_h_q;
 reg [12:0] triangle_area_q;
 wire [8:0] triangle_span_sum={1'b0,triangle_grid_w_q}+{1'b0,triangle_grid_h_q};
 wire [9:0] stroke_count_floor={triangle_span_sum,1'b0}+{3'b0,triangle_span_sum[8:2]};
 reg triangle_dense_q;
 // Model-register enables see only a registered fit/grade, not a constant
 // multiply, score priority encoder, fit conjunction and wide CE fanout.
 reg rectangle_fit_q;reg [2:0] rectangle_grade_q;
 reg ellipse_fit_q;reg [2:0] ellipse_grade_q;
 reg [3:0] triangle_tol,triangle_ab,triangle_bc,triangle_ca;
 reg [1:0] triangle_side;
 // A and C are opposite farthest vertices. B/D are signed extrema on
 // opposite sides of AC. This is a genuine four finite-line model, not a bbox.
 reg [6:0] pbx,pby,pdx,pdy;
 reg [15:0] positive_cross,negative_cross;
 reg [3:0] parallel_ab,parallel_bc,parallel_cd,parallel_da;
 reg [7:0] parallel_cov_a,parallel_cov_b,parallel_cov_c,parallel_cov_d;
 reg [PB:0] parallel_hits;
 reg [2:0] component_p,best_p,pending_p;
 reg [55:0] best_pvertices,pending_pvertices,pub_pvertices;
 reg [10:0] best_px0,best_px1,best_py0,best_py1,pending_px0,pending_px1,pending_py0,pending_py1;
 reg [10:0] candidate_px,candidate_py;
 reg [7:0] p_hits,p_miss;
 reg [8:0] p_mid_error_x,p_mid_error_y;
 reg [16:0] p_cross,p_dot;
 reg [7:0] p_length_a,p_length_d;
 reg parallel_geometry_q,parallel_fit_q,triangle_fit_q;
 reg [2:0] parallel_grade_q,triangle_grade_q;
 wire signed [8:0] p_mid_x=$signed({2'b0,tax})+$signed({2'b0,tbx})-$signed({2'b0,pbx})-$signed({2'b0,pdx});
 wire signed [8:0] p_mid_y=$signed({2'b0,tay})+$signed({2'b0,tby})-$signed({2'b0,pby})-$signed({2'b0,pdy});
 wire signed [16:0] p_dot_value=$signed({line_product_a_q[15],line_product_a_q})+$signed({line_product_b_q[15],line_product_b_q});
 wire [11:0] new_px=({1'b0,pending_px0}+pending_px1)>>1,new_py=({1'b0,pending_py0}+pending_py1)>>1;
 wire p_same=(new_px>candidate_px?new_px-candidate_px:candidate_px-new_px)<=32&&
             (new_py>candidate_py?new_py-candidate_py:candidate_py-new_py)<=32;
 wire parallel_fit=parallel_geometry_q&&component_r==0&&support_percent>=n90&&
   pop8(parallel_cov_a)>=6&&pop8(parallel_cov_b)>=6&&pop8(parallel_cov_c)>=6&&pop8(parallel_cov_d)>=6;

 wire [6:0] line_ax=triangle_phase==4?(triangle_side==0?tax:triangle_side==1?pbx:triangle_side==2?tbx:pdx):(triangle_side==0?tax:triangle_side==1?tbx:tcx);
 wire [6:0] line_ay=triangle_phase==4?(triangle_side==0?tay:triangle_side==1?pby:triangle_side==2?tby:pdy):(triangle_side==0?tay:triangle_side==1?tby:tcy);
 wire [6:0] line_bx=triangle_phase==4?(triangle_side==0?pbx:triangle_side==1?tbx:triangle_side==2?pdx:tax):(triangle_side==0?tbx:triangle_side==1?tcx:tax);
 wire [6:0] line_by=triangle_phase==4?(triangle_side==0?pby:triangle_side==1?tby:triangle_side==2?pdy:tay):(triangle_side==0?tby:triangle_side==1?tcy:tay);
 reg signed [7:0] line_dx_q,line_dy_q,line_rx_q,line_ry_q;
 reg signed [15:0] line_product_a_q,line_product_b_q;
 reg signed [16:0] line_cross_q;
 wire [16:0] line_cross_abs=line_cross_q[16]?-line_cross_q:line_cross_q;
 wire [6:0] line_adx=line_dx_q[7]?-line_dx_q:line_dx_q;
 wire [6:0] line_ady=line_dy_q[7]?-line_dy_q:line_dy_q;
 reg [7:0] line_l1_q;
 reg [11:0] line_limit_q;
 reg [6:0] line_lo_q,line_hi_q,line_q_q,line_span_q,line_offset_q;
 reg line_segment_q,line_fit_q;
 reg [7:1] line_bin_tests_q;
 reg [2:0] line_bin;integer line_bin_index,line_test_index;
 function automatic [9:0] line_part(input [6:0] span,input [2:0] part);
  begin line_part=span*part;end
 endfunction
 always @* begin
  line_bin=0;
  for(line_bin_index=1;line_bin_index<8;line_bin_index=line_bin_index+1)
   if(line_bin_tests_q[line_bin_index])line_bin=line_bin_index;
 end
 reg [7:0] triangle_cov_a,triangle_cov_b,triangle_cov_c;
 reg [7:0] sectors,cov_l,cov_r,cov_t,cov_b;reg [3:0] corners;
 reg [2:0] sector;
 reg [10:0] bw,bh;reg [PB:0] n;
 reg [10:0] save_x0,save_x1,save_y0,save_y1;
 reg [2:0] best_c,best_r,pending_c,pending_r;
 reg publish_pending;
 reg [7:0] candidate_work;reg [2:0] raw_c_work,raw_r_work;
 reg [10:0] pending_cx0,pending_cx1,pending_cy0,pending_cy1,pending_rx0,pending_rx1,pending_ry0,pending_ry1;
 reg [4:0] pending_angle;
 reg signed [16:0] pending_umin,pending_umax,pending_vmin,pending_vmax;
 reg [10:0] candidate_cx,candidate_cy,candidate_rx,candidate_ry;
 wire [11:0] new_cx=(pending_cx0+{1'b0,pending_cx1})>>1;
 wire [11:0] new_cy=(pending_cy0+{1'b0,pending_cy1})>>1;
 wire [11:0] new_rx=(pending_rx0+{1'b0,pending_rx1})>>1;
 wire [11:0] new_ry=(pending_ry0+{1'b0,pending_ry1})>>1;
 wire c_same=(new_cx>candidate_cx?new_cx-candidate_cx:candidate_cx-new_cx)<=32&&
             (new_cy>candidate_cy?new_cy-candidate_cy:candidate_cy-new_cy)<=32;
 wire r_same=(new_rx>candidate_rx?new_rx-candidate_rx:candidate_rx-new_rx)<=32&&
             (new_ry>candidate_ry?new_ry-candidate_ry:candidate_ry-new_ry)<=32;

 reg [2:0] component_c,component_r,component_t,component_e;
 reg [2:0] best_t,best_e,pending_t,pending_e;
 reg [10:0] best_tx0,best_tx1,best_ty0,best_ty1;
 reg [10:0] pending_tx0,pending_tx1,pending_ty0,pending_ty1;
 reg [6:0] best_tax,best_tay,best_tbx,best_tby,best_tcx,best_tcy;
 reg [6:0] pending_tax,pending_tay,pending_tbx,pending_tby,pending_tcx,pending_tcy;
 reg [6:0] pub_tax,pub_tay,pub_tbx,pub_tby,pub_tcx,pub_tcy;
 reg [4:0] component_eangle,best_eangle,pending_eangle,publish_eangle;
 reg signed [16:0] component_eumin,component_eumax,component_evmin,component_evmax;
 reg signed [16:0] best_eumin,best_eumax,best_evmin,best_evmax;
 reg signed [16:0] pending_eumin,pending_eumax,pending_evmin,pending_evmax;
 reg signed [16:0] pub_eumin,pub_eumax,pub_evmin,pub_evmax;
 reg [7:0] t_hits,t_miss;
 reg [10:0] candidate_tx,candidate_ty;
 wire [11:0] new_tx=({1'b0,pending_tx0}+pending_tx1)>>1,new_ty=({1'b0,pending_ty0}+pending_ty1)>>1;
 wire t_same=(new_tx>candidate_tx?new_tx-candidate_tx:candidate_tx-new_tx)<=32&&
              (new_ty>candidate_ty?new_ty-candidate_ty:candidate_ty-new_ty)<=32;
 reg [4:0] component_angle;
 reg signed [16:0] component_umin,component_umax,component_vmin,component_vmax;
 reg [10:0] best_cx0,best_cx1,best_cy0,best_cy1,best_rx0,best_rx1,best_ry0,best_ry1;
 reg [4:0] best_angle,publish_angle;
 reg signed [16:0] best_umin,best_umax,best_vmin,best_vmax,pub_umin,pub_umax,pub_vmin,pub_vmax;
 reg [7:0] c_hits,r_hits,c_miss,r_miss;
 reg signed [7:0] cdx,cdy;
 reg [6:0] ax,ay;
 wire [15:0] uw=umax-umin,vh=vmax-vmin;
 // Bound -> span -> tolerance -> side-limit -> comparison is spread over
 // existing point-read stages. No long tolerance chain drives hit enables.
 reg [16:0] rect_tol_q,corner_tol_q;
 reg signed [16:0] near_umin_q,near_umax_q,near_vmin_q,near_vmax_q;
 reg signed [16:0] corner_umin_q,corner_umax_q,corner_vmin_q,corner_vmax_q;
 reg near_l,near_r,near_t,near_b,corner_l,corner_r,corner_t,corner_b;
 // Reuse the existing point-read latency to prepare exact eighth-span
 // boundaries. The three arithmetic stages and bin register remove span /
 // multiply / add / priority encoding from the coverage register enables.
 reg [15:0] span_u_q,span_v_q,offset_u_q[1:7],offset_v_q[1:7];
 reg signed [16:0] origin_u_q,origin_v_q;
 reg signed [17:0] boundary_u_q[1:7],boundary_v_q[1:7];
 reg [2:0] ubin,vbin,ubin_next,vbin_next;integer j,boundary_index;
 function automatic [15:0] eighth_span(input [15:0] span,input [2:0] part);
  reg [18:0] product;
  begin product={3'b0,span}*part;eighth_span=product[18:3];end
 endfunction
 always @* begin
  ubin_next=0;vbin_next=0;
  for(j=1;j<8;j=j+1)begin
   if($signed({u[16],u})>=boundary_u_q[j])ubin_next=j;
   if($signed({v[16],v})>=boundary_v_q[j])vbin_next=j;
  end
 end
 wire [11:0] width_diff=bw>bh?bw-bh:bh-bw;
 wire circle_fit=width_diff<=((bw>bh?bw:bh)>>2)+2&&pop8(sectors)>=6&&support_percent>=n*7'd82&&circle_corner_hits*10<=n&&
   profile_coverage>=11&&profile_max-profile_min<=(profile_max>>2)&&opposite_coverage>=5&&
   opposite_max-opposite_min<=(opposite_max>>3)+(rad<<1);
 wire rectangle_fit=uw>=(MIN_SPAN*256>>ds)&&vh>=(MIN_SPAN*256>>ds)&&
    uw<=4*vh&&vh<=4*uw&&support_percent>=n84&&pop8({4'b0,corners})>=3&&
    pop8(cov_l)>=5&&pop8(cov_r)>=5&&pop8(cov_t)>=5&&pop8(cov_b)>=5;
 wire ellipse_eccentric=(ellipse_w*10>=ellipse_h*12||ellipse_h*10>=ellipse_w*12);
 // Near-round conics previously fell into a dead zone: radial circle matching
 // could fail before the old ellipse aspect-ratio >=1.2 gate became true.
 // Admit this bridge only with STRONGER normalized conic evidence: >=94%
 // point support, >=14/16 angular sectors, <=1/8 envelope variation. General
 // ellipses retain the V11 86%,13/16,1/4 requirements unchanged. This is a
 // bounded conic test, never a blanket lowering of matching thresholds.
 wire ellipse_fit=ellipse_w>=12&&ellipse_h>=12&&ellipse_w<=4*ellipse_h&&ellipse_h<=4*ellipse_w&&
    (ellipse_eccentric?(support_percent>=n*7'd86&&ellipse_coverage>=13&&
                       ellipse_max-ellipse_min<=(ellipse_reference>>2)):
                      (support_percent>=n94&&ellipse_coverage>=14&&
                       ellipse_max-ellipse_min<=(ellipse_reference>>3)));
 // Thick strokes must still trace ALL eight narrow outer-edge segments
 // on EACH side. Wider interior support alone cannot turn a concave outline
 // into a triangle. Thin contours keep the original strict-point criterion.
 wire triangle_fit=triangle_farthest>triangle_area_q&&
   (triangle_dense_q?(support_percent>=n*7'd95&&triangle_cov_a==8'hff&&triangle_cov_b==8'hff&&triangle_cov_c==8'hff):
    (support_percent>=n89&&triangle_strict_hits*100>=n*95&&pop8(triangle_cov_a)>=6&&pop8(triangle_cov_b)>=6&&pop8(triangle_cov_c)>=6));
 // All five classifications are evaluated in disjoint FSM phases. Reuse one
 // exact support percentage datapath. No division or threshold rounding.
 // Internal scores are a monotone three-bit encoding; public bytes retain
 // exactly {0,50,70,80,85,90,95,100}. This preserves every tie/priority test.
 wire score_circle=state==CIRCLE_SCAN||state==CIRCLE_EVAL;
 wire score_ellipse=state==ELLIPSE_SCAN||state==ELLIPSE_EVAL||state==ELLIPSE_COMMIT;
 wire score_triangle=triangle_phase==3;
 wire score_parallel=triangle_phase==4;
 wire [PB:0] score_hits=score_circle?ring_hits:score_ellipse?ellipse_hits:
                       score_triangle?triangle_hits:score_parallel?parallel_hits:side_hits;
 localparam integer SCORE_W=PB+8; // (2^(PB+1)-1)*100 fits PB+8 bits.
 wire [SCORE_W-1:0] support_percent=score_hits*7'd100;
 wire [SCORE_W-1:0] n98=n*7'd98,n94=n*7'd94,n90=n*7'd90,n89=n*7'd89,
                         n84=n*7'd84,n79=n*7'd79,n69=n*7'd69,n49=n*7'd49;
 // Thresholds are ordered and fit SCORE_W without overflow. Encode each
 // grade bit directly to avoid a serial priority mux; all scores are unchanged.
 wire score_ge98=support_percent>=n98,score_ge94=support_percent>=n94;
 wire score_ge_hi=support_percent>=(score_parallel?n90:n89);
 wire score_ge84=support_percent>=n84,score_ge79=support_percent>=n79;
 wire score_ge69=support_percent>=n69,score_ge49=support_percent>=n49;
 wire score_low=!(score_triangle||score_parallel||score_ellipse);
 wire [2:0] support_grade;
 assign support_grade[2]=(score_triangle||score_parallel)?score_ge_hi:score_ge84;
 assign support_grade[1]=score_ge94||(score_low&&score_ge69&&!score_ge84);
 assign support_grade[0]=score_ge98||(score_ge_hi&&!score_ge94)||
                         (score_low&&score_ge79&&!score_ge84)||
                         (score_low&&score_ge49&&!score_ge69);
 wire [2:0] c_grade=support_grade,r_grade=support_grade,e_grade=support_grade,
            t_grade=support_grade,p_grade=support_grade;
 function automatic [7:0] score_byte(input [2:0] rank);
  case(rank)0:score_byte=0;1:score_byte=50;2:score_byte=70;3:score_byte=80;
    4:score_byte=85;5:score_byte=90;6:score_byte=95;7:score_byte=100;endcase
 endfunction
 wire geometry_ok=!oversize&&count>=12&&bx1-bx0+1>=MIN_SPAN&&by1-by0+1>=MIN_SPAN&&
   bx0>origin_x&&bx1<limit_x&&by0>origin_y&&by1<limit_y&&
   ((bx1-bx0)>>ds)>=12&&((by1-by0)>>ds)>=12;
 // Overlay is geometric support only, never every edge inside a oversize bbox.
 wire signed [12:0] odx=$signed({1'b0,x,1'b0})-$signed({2'b0,circle_x0})-$signed({2'b0,circle_x1});
 wire signed [12:0] ody=$signed({1'b0,y,1'b0})-$signed({2'b0,circle_y0})-$signed({2'b0,circle_y1});
 wire [12:0] oa=odx[12]?-odx:odx,ob=ody[12]?-ody:ody;
 // Octagonal radial approximation is for highlighting only, not recognition.
 wire [13:0] oradius=(circle_x1-circle_x0+circle_y1-circle_y0+2)>>1;
 wire [13:0] odistance=oa>ob?oa+(ob>>2)+(ob>>3):ob+(oa>>2)+(oa>>3);
 wire [13:0] omargin=12+(oradius>>3);
 wire [GX-1:0] ox=(x-publish_origin_x)>>publish_ds;wire [GY-1:0] oy=(y-publish_origin_y)>>publish_ds;
 wire signed [18:0] ou=$signed({1'b0,ox})*cosine(publish_angle)+$signed({1'b0,oy})*sine(publish_angle);
 wire signed [18:0] ov=-$signed({1'b0,ox})*sine(publish_angle)+$signed({1'b0,oy})*cosine(publish_angle);
 wire [18:0] otol=512+(((pub_umax-pub_umin)>(pub_vmax-pub_vmin)?pub_umax-pub_umin:pub_vmax-pub_vmin)>>5);
 assign circle_outline=pixel_valid&&edge_bit&&circle_valid&&x>=circle_x0&&x<=circle_x1&&y>=circle_y0&&y<=circle_y1&&
   odistance+omargin>=oradius&&odistance<=oradius+omargin;
 assign rect_outline=pixel_valid&&edge_bit&&rect_valid&&x>=rect_x0&&x<=rect_x1&&y>=rect_y0&&y<=rect_y1&&
   ou>=pub_umin-$signed(otol)&&ou<=pub_umax+$signed(otol)&&ov>=pub_vmin-$signed(otol)&&ov<=pub_vmax+$signed(otol)&&
   (ou<=pub_umin+$signed(otol)||ou>=pub_umax-$signed(otol)||ov<=pub_vmin+$signed(otol)||ov>=pub_vmax-$signed(otol));
 wire [3:0] pub_ttol=1+(((triangle_x1-triangle_x0)>(triangle_y1-triangle_y0)?
                       triangle_x1-triangle_x0:triangle_y1-triangle_y0)>>(publish_ds+5));
 assign model_origin_x=publish_origin_x;assign model_origin_y=publish_origin_y;assign model_ds=publish_ds;
 assign rect_fit_angle=publish_angle;
 assign rect_fit_umin=pub_umin;assign rect_fit_umax=pub_umax;assign rect_fit_vmin=pub_vmin;assign rect_fit_vmax=pub_vmax;
 assign ellipse_fit_angle=publish_eangle;
 assign ellipse_fit_umin=pub_eumin;assign ellipse_fit_umax=pub_eumax;assign ellipse_fit_vmin=pub_evmin;assign ellipse_fit_vmax=pub_evmax;
 assign triangle_vertices={pub_tcx,pub_tcy,pub_tbx,pub_tby,pub_tax,pub_tay};
 assign triangle_tolerance=pub_ttol;
 assign parallel_vertices=pub_pvertices;
 assign parallel_tolerance=1+(((parallel_x1-parallel_x0)>(parallel_y1-parallel_y0)?
                               parallel_x1-parallel_x0:parallel_y1-parallel_y0)>>(publish_ds+5));
 wire [3:0] opab=line_support(ox,oy,pub_pvertices[13:7],pub_pvertices[6:0],pub_pvertices[27:21],pub_pvertices[20:14],parallel_tolerance);
 wire [3:0] opbc=line_support(ox,oy,pub_pvertices[27:21],pub_pvertices[20:14],pub_pvertices[41:35],pub_pvertices[34:28],parallel_tolerance);
 wire [3:0] opcd=line_support(ox,oy,pub_pvertices[41:35],pub_pvertices[34:28],pub_pvertices[55:49],pub_pvertices[48:42],parallel_tolerance);
 wire [3:0] opda=line_support(ox,oy,pub_pvertices[55:49],pub_pvertices[48:42],pub_pvertices[13:7],pub_pvertices[6:0],parallel_tolerance);
 assign parallel_outline=pixel_valid&&edge_bit&&parallel_valid&&x>=parallel_x0&&x<=parallel_x1&&y>=parallel_y0&&y<=parallel_y1&&
                         (opab[3]||opbc[3]||opcd[3]||opda[3]);
 wire [3:0] overlay_tab=triangle_valid?line_support(ox,oy,pub_tax,pub_tay,pub_tbx,pub_tby,pub_ttol):4'd0;
 wire [3:0] overlay_tbc=triangle_valid?line_support(ox,oy,pub_tbx,pub_tby,pub_tcx,pub_tcy,pub_ttol):4'd0;
 wire [3:0] overlay_tca=triangle_valid?line_support(ox,oy,pub_tcx,pub_tcy,pub_tax,pub_tay,pub_ttol):4'd0;
 assign triangle_outline=pixel_valid&&edge_bit&&triangle_valid&&x>=triangle_x0&&x<=triangle_x1&&
    y>=triangle_y0&&y<=triangle_y1&&(overlay_tab[3]||overlay_tbc[3]||overlay_tca[3]);
 wire signed [18:0] oeu=$signed({1'b0,ox})*cosine(publish_eangle)+$signed({1'b0,oy})*sine(publish_eangle);
 wire signed [18:0] oev=-$signed({1'b0,ox})*sine(publish_eangle)+$signed({1'b0,oy})*cosine(publish_eangle);
 wire signed [10:0] oedx=($signed(oeu)*2-$signed(pub_eumin)-$signed(pub_eumax))>>>8;
 wire signed [10:0] oedy=($signed(oev)*2-$signed(pub_evmin)-$signed(pub_evmax))>>>8;
 wire [10:0] oeax=oedx[10]?-oedx:oedx,oeay=oedy[10]?-oedy:oedy;
 wire [9:0] oew=(pub_eumax-pub_eumin+128)>>8,oeh=(pub_evmax-pub_evmin+128)>>8;
 wire [20:0] oenx=oeax*oeh,oeny=oeay*oew;
 wire [21:0] oedistance=oenx>oeny?oenx+(oeny>>2)+(oeny>>3):oeny+(oenx>>2)+(oenx>>3);
 wire [19:0] oeradius=oew*oeh;
 wire [20:0] oemargin=(oeradius>>3)+32;
 assign ellipse_outline=pixel_valid&&edge_bit&&ellipse_valid&&x>=ellipse_x0&&x<=ellipse_x1&&
    y>=ellipse_y0&&y<=ellipse_y1&&oedistance+oemargin>=oeradius&&oedistance<=oeradius+oemargin;
 always @(posedge clk)begin
  if(!rst_n||reset_fit)begin
   parallel_valid<=0;parallel_score<=0;parallel_x0<=0;parallel_x1<=0;parallel_y0<=0;parallel_y1<=0;
   pbx<=0;pby<=0;pdx<=0;pdy<=0;positive_cross<=0;negative_cross<=0;
   parallel_ab<=0;parallel_bc<=0;parallel_cd<=0;parallel_da<=0;
   parallel_cov_a<=0;parallel_cov_b<=0;parallel_cov_c<=0;parallel_cov_d<=0;parallel_hits<=0;
   component_p<=0;best_p<=0;pending_p<=0;best_pvertices<=0;pending_pvertices<=0;pub_pvertices<=0;
   best_px0<=0;best_px1<=0;best_py0<=0;best_py1<=0;pending_px0<=0;pending_px1<=0;pending_py0<=0;pending_py1<=0;
   candidate_px<=0;candidate_py<=0;p_hits<=0;p_miss<=0;p_mid_error_x<=0;p_mid_error_y<=0;
   p_cross<=0;p_dot<=0;p_length_a<=0;p_length_d<=0;parallel_geometry_q<=0;parallel_fit_q<=0;triangle_fit_q<=0;
   parallel_grade_q<=0;triangle_grade_q<=0;
   state<=WAIT;accept<=0;index<=0;angle<=0;fit_pass<=0;cs<=256;sn<=0;
   span_u_q<=0;span_v_q<=0;origin_u_q<=0;origin_v_q<=0;ubin<=0;vbin<=0;
   rect_tol_q<=0;corner_tol_q<=0;
   near_umin_q<=0;near_umax_q<=0;near_vmin_q<=0;near_vmax_q<=0;
   corner_umin_q<=0;corner_umax_q<=0;corner_vmin_q<=0;corner_vmax_q<=0;
   near_l<=0;near_r<=0;near_t<=0;near_b<=0;corner_l<=0;corner_r<=0;corner_t<=0;corner_b<=0;
   for(boundary_index=1;boundary_index<8;boundary_index=boundary_index+1)begin
    offset_u_q[boundary_index]<=0;offset_v_q[boundary_index]<=0;
    boundary_u_q[boundary_index]<=0;boundary_v_q[boundary_index]<=0;
   end
   circle_valid<=0;rect_valid<=0;circle_score<=0;rect_score<=0;result_tick<=0;
   triangle_valid<=0;ellipse_valid<=0;triangle_score<=0;ellipse_score<=0;
   triangle_x0<=0;triangle_x1<=0;triangle_y0<=0;triangle_y1<=0;
   ellipse_x0<=0;ellipse_x1<=0;ellipse_y0<=0;ellipse_y1<=0;
   triangle_phase<=0;tax<=0;tay<=0;tbx<=0;tby<=0;tcx<=0;tcy<=0;
   triangle_grid_w_q<=0;triangle_grid_h_q<=0;triangle_area_q<=0;triangle_dense_q<=0;rectangle_fit_q<=0;rectangle_grade_q<=0;ellipse_fit_q<=0;ellipse_grade_q<=0;
   triangle_farthest<=0;triangle_hits<=0;triangle_strict_hits<=0;triangle_strict_sides<=0;line_strict_q<=0;triangle_cov_a<=0;triangle_cov_b<=0;triangle_cov_c<=0;
   triangle_distance<=0;triangle_cross_abs<=0;triangle_tol<=0;triangle_ab<=0;triangle_bc<=0;triangle_ca<=0;triangle_side<=0;
   line_dx_q<=0;line_dy_q<=0;line_rx_q<=0;line_ry_q<=0;line_product_a_q<=0;line_product_b_q<=0;line_cross_q<=0;
   line_l1_q<=0;line_limit_q<=0;line_lo_q<=0;line_hi_q<=0;line_q_q<=0;line_span_q<=0;line_offset_q<=0;
   line_segment_q<=0;line_fit_q<=0;line_bin_tests_q<=0;
   ellipse_hits<=0;ellipse_min<=0;ellipse_max<=0;ellipse_coverage<=0;ellipse_scan<=0;ellipse_clear_index<=0;ellipse_clear_active<=0;
   ellipse_dx<=0;ellipse_dy<=0;ellipse_w<=0;ellipse_h<=0;
   ellipse_dx2<=0;ellipse_dy2<=0;ellipse_w2<=0;ellipse_h2<=0;ellipse_value<=0;ellipse_reference<=0;
   ellipse_nx<=0;ellipse_ny<=0;ellipse_product_x<=0;ellipse_product_y<=0;
   ellipse_point_fit_q<=0;ellipse_profile_grow_q<=0;ellipse_bin<=0;
   component_t<=0;component_e<=0;best_t<=0;best_e<=0;pending_t<=0;pending_e<=0;
   t_hits<=0;t_miss<=0;candidate_tx<=0;candidate_ty<=0;
   best_tx0<=0;best_tx1<=0;best_ty0<=0;best_ty1<=0;
   pending_tx0<=0;pending_tx1<=0;pending_ty0<=0;pending_ty1<=0;
   best_tax<=0;best_tay<=0;best_tbx<=0;best_tby<=0;best_tcx<=0;best_tcy<=0;
   pending_tax<=0;pending_tay<=0;pending_tbx<=0;pending_tby<=0;pending_tcx<=0;pending_tcy<=0;
   pub_tax<=0;pub_tay<=0;pub_tbx<=0;pub_tby<=0;pub_tcx<=0;pub_tcy<=0;
   component_eangle<=0;best_eangle<=0;pending_eangle<=0;publish_eangle<=0;
   component_eumin<=0;component_eumax<=0;component_evmin<=0;component_evmax<=0;
   best_eumin<=0;best_eumax<=0;best_evmin<=0;best_evmax<=0;
   pending_eumin<=0;pending_eumax<=0;pending_evmin<=0;pending_evmax<=0;
   pub_eumin<=0;pub_eumax<=0;pub_evmin<=0;pub_evmax<=0;
   publish_origin_x<=0;publish_origin_y<=0;publish_ds<=0;
   circle_x0<=0;circle_x1<=0;circle_y0<=0;circle_y1<=0;rect_x0<=0;rect_x1<=0;rect_y0<=0;rect_y1<=0;
   best_c<=0;best_r<=0;pending_c<=0;pending_r<=0;publish_pending<=0;c_hits<=0;r_hits<=0;c_miss<=0;r_miss<=0;
   publish_angle<=0;pub_umin<=0;pub_umax<=0;pub_vmin<=0;pub_vmax<=0;
   best_cx0<=0;best_cx1<=0;best_cy0<=0;best_cy1<=0;best_rx0<=0;best_rx1<=0;best_ry0<=0;best_ry1<=0;
   best_angle<=0;best_umin<=0;best_umax<=0;best_vmin<=0;best_vmax<=0;
   observed_count<=0;analysis_count<=0;timeout_count<=0;dropped_count<=0;candidate_count<=0;
   circle_best_score<=0;rect_best_score<=0;reject_reason<=0;
   candidate_work<=0;raw_c_work<=0;raw_r_work<=0;
   candidate_cx<=0;candidate_cy<=0;candidate_rx<=0;candidate_ry<=0;
   pending_cx0<=0;pending_cx1<=0;pending_cy0<=0;pending_cy1<=0;
   pending_rx0<=0;pending_rx1<=0;pending_ry0<=0;pending_ry1<=0;
   pending_angle<=0;pending_umin<=0;pending_umax<=0;pending_vmin<=0;pending_vmax<=0;
  end else begin
   accept<=0;result_tick<=0;
   if(ellipse_clear_active)begin
    if(ellipse_clear_index==15)ellipse_clear_active<=0;
    else ellipse_clear_index<=ellipse_clear_index+1'b1;
   end
   if(capture_started&&observed_count!=65535)observed_count<=observed_count+1'b1;
   if(frame_start&&sample_tick&&!capture_started&&dropped_count!=65535)dropped_count<=dropped_count+1'b1;
   if(capture_incomplete)reject_reason<=4;
   if(done)begin
    if(analysis_count!=65535)analysis_count<=analysis_count+1'b1;
    if(overflow&&timeout_count!=65535)timeout_count<=timeout_count+1'b1;
    candidate_count<=candidate_work;circle_best_score<=score_byte(raw_c_work);rect_best_score<=score_byte(raw_r_work);
    reject_reason<=overflow?3:candidate_work==0?1:(best_c==0&&best_r==0&&best_t==0&&best_e==0&&best_p==0)?2:0;
    candidate_work<=0;raw_c_work<=0;raw_r_work<=0;
    // FINISH already selected one merged round-class winner. best_c stores
    // its score/bbox; best_e is nonzero only for an elliptic renderer model.
    // Both model families enter the SAME center/confirmation/loss history.
    pending_cx0<=best_cx0;pending_cx1<=best_cx1;pending_cy0<=best_cy0;pending_cy1<=best_cy1;
    pending_rx0<=best_rx0;pending_rx1<=best_rx1;pending_ry0<=best_ry0;pending_ry1<=best_ry1;
    pending_angle<=best_angle;pending_umin<=best_umin;pending_umax<=best_umax;pending_vmin<=best_vmin;pending_vmax<=best_vmax;
    pending_c<=overflow?0:best_c;pending_r<=overflow?0:best_r;
    pending_p<=overflow?0:best_p;pending_px0<=best_px0;pending_px1<=best_px1;pending_py0<=best_py0;pending_py1<=best_py1;
    pending_pvertices<=best_pvertices;best_p<=0;
    pending_t<=overflow?0:best_t;pending_e<=overflow?0:best_e;
    pending_tx0<=best_tx0;pending_tx1<=best_tx1;pending_ty0<=best_ty0;pending_ty1<=best_ty1;
    pending_tax<=best_tax;pending_tay<=best_tay;pending_tbx<=best_tbx;pending_tby<=best_tby;pending_tcx<=best_tcx;pending_tcy<=best_tcy;
    pending_eangle<=best_eangle;pending_eumin<=best_eumin;pending_eumax<=best_eumax;pending_evmin<=best_evmin;pending_evmax<=best_evmax;
    best_t<=0;best_e<=0;
    best_c<=0;best_r<=0;publish_pending<=1;
   end
   if(frame_start&&publish_pending)begin
    publish_origin_x<=origin_x;publish_origin_y<=origin_y;publish_ds<=ds;
    publish_pending<=done;
    if(pending_c!=0)begin
      c_miss<=0;candidate_cx<=new_cx;candidate_cy<=new_cy;
      if(c_hits==0||!c_same)c_hits<=1;else if(c_hits<CONFIRM_FRAMES)c_hits<=c_hits+1'b1;
      if(CONFIRM_FRAMES<=1||(c_same&&c_hits>=CONFIRM_FRAMES-1))begin
        circle_valid<=pending_e==0;ellipse_valid<=pending_e!=0;
        circle_score<=pending_e==0?score_byte(pending_c):0;
        ellipse_score<=pending_e!=0?score_byte(pending_c):0;
        circle_x0<=pending_cx0;circle_x1<=pending_cx1;circle_y0<=pending_cy0;circle_y1<=pending_cy1;
        ellipse_x0<=pending_cx0;ellipse_x1<=pending_cx1;ellipse_y0<=pending_cy0;ellipse_y1<=pending_cy1;
        publish_eangle<=pending_eangle;pub_eumin<=pending_eumin;pub_eumax<=pending_eumax;
        pub_evmin<=pending_evmin;pub_evmax<=pending_evmax;
      end
    end else begin
      c_hits<=0;if(c_miss<LOSS_FRAMES)c_miss<=c_miss+1'b1;
      if(c_miss>=LOSS_FRAMES-1)begin circle_valid<=0;ellipse_valid<=0;circle_score<=0;ellipse_score<=0;end
    end
    if(pending_r!=0)begin
      r_miss<=0;candidate_rx<=new_rx;candidate_ry<=new_ry;
      if(r_hits==0||!r_same)r_hits<=1;else if(r_hits<CONFIRM_FRAMES)r_hits<=r_hits+1'b1;
      if(CONFIRM_FRAMES<=1||(r_same&&r_hits>=CONFIRM_FRAMES-1))begin rect_valid<=1;rect_score<=score_byte(pending_r);rect_x0<=pending_rx0;rect_x1<=pending_rx1;rect_y0<=pending_ry0;rect_y1<=pending_ry1;
        publish_angle<=pending_angle;pub_umin<=pending_umin;pub_umax<=pending_umax;pub_vmin<=pending_vmin;pub_vmax<=pending_vmax;end
    end else begin r_hits<=0;if(r_miss<LOSS_FRAMES)r_miss<=r_miss+1'b1;if(r_miss>=LOSS_FRAMES-1)begin rect_valid<=0;rect_score<=0;end end
    if(pending_t!=0)begin
      t_miss<=0;candidate_tx<=new_tx;candidate_ty<=new_ty;
      if(t_hits==0||!t_same)t_hits<=1;else if(t_hits<CONFIRM_FRAMES)t_hits<=t_hits+1'b1;
      if(CONFIRM_FRAMES<=1||(t_same&&t_hits>=CONFIRM_FRAMES-1))begin
        triangle_valid<=1;triangle_score<=score_byte(pending_t);triangle_x0<=pending_tx0;triangle_x1<=pending_tx1;triangle_y0<=pending_ty0;triangle_y1<=pending_ty1;
        pub_tax<=pending_tax;pub_tay<=pending_tay;pub_tbx<=pending_tbx;pub_tby<=pending_tby;pub_tcx<=pending_tcx;pub_tcy<=pending_tcy;
      end
    end else begin t_hits<=0;if(t_miss<LOSS_FRAMES)t_miss<=t_miss+1'b1;if(t_miss>=LOSS_FRAMES-1)begin triangle_valid<=0;triangle_score<=0;end end
    if(pending_p!=0)begin
      p_miss<=0;candidate_px<=new_px;candidate_py<=new_py;
      if(p_hits==0||!p_same)p_hits<=1;else if(p_hits<CONFIRM_FRAMES)p_hits<=p_hits+1'b1;
      if(CONFIRM_FRAMES<=1||(p_same&&p_hits>=CONFIRM_FRAMES-1))begin
        parallel_valid<=1;parallel_score<=score_byte(pending_p);parallel_x0<=pending_px0;parallel_x1<=pending_px1;parallel_y0<=pending_py0;parallel_y1<=pending_py1;
        pub_pvertices<=pending_pvertices;
      end
    end else begin p_hits<=0;if(p_miss<LOSS_FRAMES)p_miss<=p_miss+1'b1;if(p_miss>=LOSS_FRAMES-1)begin parallel_valid<=0;parallel_score<=0;end end
    result_tick<=1;
   end
   case(state)
    WAIT:if(ready&&!accept)begin
      if(!geometry_ok)accept<=1;
      else begin
       if(candidate_work!=255)candidate_work<=candidate_work+1'b1;
       save_x0<=bx0;save_x1<=bx1;save_y0<=by0;save_y1<=by1;bw<=bx1-bx0+1;bh<=by1-by0+1;n<=count;
       ellipse_clear_index<=0;ellipse_clear_active<=1;
       index<=0;angle<=0;cs<=256;sn<=0;fit_pass<=0;ring_hits<=0;circle_corner_hits<=0;sectors<=0;component_c<=0;
       component_p<=0;positive_cross<=0;negative_cross<=0;pbx<=0;pby<=0;pdx<=0;pdy<=0;
       component_t<=0;component_e<=0;triangle_phase<=0;tax<=0;tay<=0;triangle_farthest<=0;
       for(profile_reset=0;profile_reset<16;profile_reset=profile_reset+1)radial_profile[profile_reset]<=0;component_r<=0;
       // Match centers of occupied cells, not their inflated outer extents.
       rad<=((bx1-bx0+by1-by0+2)>>(ds+1))-1'b1;
       umin<=65535;umax<=-65536;vmin<=65535;vmax<=-65536;
       state<=POINT0;
      end
     end
    POINT0:begin
      triangle_grid_w_q<=bw>>ds;triangle_grid_h_q<=bh>>ds;
      triangle_tol<=1+((bw>bh?bw:bh)>>(ds+5));
      if(triangle_phase==3&&triangle_dense_q&&((bw>bh?bw:bh)>>(ds+5))<2)triangle_tol<=3;
      if(fit_pass)begin span_u_q<=uw;span_v_q<=vh;origin_u_q<=umin;origin_v_q<=vmin;end
      rlo2<=(rad>5+(rad>>4)?rad-5-(rad>>4):0)*(rad>5+(rad>>4)?rad-5-(rad>>4):0);
      rhi2<=(rad+5+(rad>>4))*(rad+5+(rad>>4));state<=POINT1;
     end
    POINT1:begin
      triangle_area_q<=({8'b0,triangle_grid_w_q}*{8'b0,triangle_grid_h_q})>>2;
      triangle_dense_q<=n>=stroke_count_floor;
      if(fit_pass)begin
       rect_tol_q<=17'd384+((span_u_q>span_v_q?span_u_q:span_v_q)>>4);
       corner_tol_q<=17'd256+((span_u_q>span_v_q?span_u_q:span_v_q)>>5);
       for(boundary_index=1;boundary_index<8;boundary_index=boundary_index+1)begin
        offset_u_q[boundary_index]<=eighth_span(span_u_q,boundary_index[2:0]);
        offset_v_q[boundary_index]<=eighth_span(span_v_q,boundary_index[2:0]);
       end
      end
      state<=POINT2;
     end
    POINT2:begin
      if(triangle_phase==1)begin
       line_dx_q<=$signed({1'b0,px})-$signed({1'b0,tax});line_ry_q<=$signed({1'b0,px})-$signed({1'b0,tax});
       line_dy_q<=$signed({1'b0,py})-$signed({1'b0,tay});line_rx_q<=$signed({1'b0,py})-$signed({1'b0,tay});
      end else if(triangle_phase==2)begin
       line_dx_q<=$signed({1'b0,tbx})-$signed({1'b0,tax});line_ry_q<=$signed({1'b0,py})-$signed({1'b0,tay});
       line_dy_q<=$signed({1'b0,tby})-$signed({1'b0,tay});line_rx_q<=$signed({1'b0,px})-$signed({1'b0,tax});
      end
      if(fit_pass)begin
       near_umin_q<=umin+$signed(rect_tol_q);near_umax_q<=umax-$signed(rect_tol_q);
       near_vmin_q<=vmin+$signed(rect_tol_q);near_vmax_q<=vmax-$signed(rect_tol_q);
       corner_umin_q<=umin+$signed(corner_tol_q);corner_umax_q<=umax-$signed(corner_tol_q);
       corner_vmin_q<=vmin+$signed(corner_tol_q);corner_vmax_q<=vmax-$signed(corner_tol_q);
       for(boundary_index=1;boundary_index<8;boundary_index=boundary_index+1)begin
        boundary_u_q[boundary_index]<=$signed({origin_u_q[16],origin_u_q})+$signed({2'b0,offset_u_q[boundary_index]});
        boundary_v_q[boundary_index]<=$signed({origin_v_q[16],origin_v_q})+$signed({2'b0,offset_v_q[boundary_index]});
       end
      end
      cdx<=$signed({1'b0,px,1'b0})-$signed((save_x0-origin_x)>>ds)-$signed((save_x1-origin_x)>>ds);
      cdy<=$signed({1'b0,py,1'b0})-$signed((save_y0-origin_y)>>ds)-$signed((save_y1-origin_y)>>ds);
      u<=$signed({1'b0,px})*cs+$signed({1'b0,py})*sn;
      v<=-$signed({1'b0,px})*sn+$signed({1'b0,py})*cs;state<=PROJECT;
     end
    PROJECT:begin
      if(fit_pass)begin
       ubin<=ubin_next;vbin<=vbin_next;
       near_l<=u<=near_umin_q;near_r<=u>=near_umax_q;near_t<=v<=near_vmin_q;near_b<=v>=near_vmax_q;
       corner_l<=u<=corner_umin_q;corner_r<=u>=corner_umax_q;corner_t<=v<=corner_vmin_q;corner_b<=v>=corner_vmax_q;
      end
      distance2<=cdx*cdx+cdy*cdy;
      ax<=cdx[7]?-cdx:cdx;ay<=cdy[7]?-cdy:cdy;state<=ACCUM;
      if(fit_pass&&triangle_phase==0)begin
        ellipse_dx<=($signed(u)*2-$signed(umin)-$signed(umax))>>>8;
        ellipse_dy<=($signed(v)*2-$signed(vmin)-$signed(vmax))>>>8;
        ellipse_w<=(uw+128)>>8;ellipse_h<=(vh+128)>>8;
        state<=ELLIPSE_SQUARE;
      end
      if(triangle_phase==1||triangle_phase==2)state<=TRI_PRODUCT;
      else if(triangle_phase>=3)begin triangle_side<=0;state<=TRI_DIFF;end
     end
    TRI_DIFF:begin
      line_dx_q<=$signed({1'b0,line_bx})-$signed({1'b0,line_ax});
      line_dy_q<=$signed({1'b0,line_by})-$signed({1'b0,line_ay});
      line_rx_q<=$signed({1'b0,px})-$signed({1'b0,line_ax});
      line_ry_q<=$signed({1'b0,py})-$signed({1'b0,line_ay});
      state<=TRI_PRODUCT;
     end
    TRI_PRODUCT:begin
      line_product_a_q<=line_dx_q*line_ry_q;line_product_b_q<=line_dy_q*line_rx_q;
      if(triangle_phase>=3)begin
       line_l1_q<={1'b0,line_adx}+{1'b0,line_ady};
       if(line_adx>=line_ady)begin
        line_lo_q<=line_ax<line_bx?line_ax:line_bx;line_hi_q<=line_ax<line_bx?line_bx:line_ax;line_q_q<=px;
       end else begin
        line_lo_q<=line_ay<line_by?line_ay:line_by;line_hi_q<=line_ay<line_by?line_by:line_ay;line_q_q<=py;
       end
      end
      state<=TRI_CROSS;
     end
    TRI_CROSS:begin
      line_cross_q<=$signed({line_product_a_q[15],line_product_a_q})-$signed({line_product_b_q[15],line_product_b_q});
      triangle_distance<=$unsigned(line_product_a_q)+$unsigned(line_product_b_q);
      if(triangle_phase>=3)begin
       line_limit_q<=line_l1_q*triangle_tol;
       line_span_q<=line_hi_q-line_lo_q;
       line_offset_q<=line_q_q>=line_lo_q?line_q_q-line_lo_q:7'd0;
       line_segment_q<=line_l1_q>=8&&({1'b0,line_q_q}+triangle_tol)>={1'b0,line_lo_q}&&
                         {1'b0,line_q_q}<=({1'b0,line_hi_q}+triangle_tol);
      end
      state<=TRI_COMPARE;
     end
    TRI_COMPARE:begin
      triangle_cross_abs<=line_cross_abs[15:0];
      if(triangle_phase>=3)begin
       line_fit_q<=line_segment_q&&line_cross_abs<=line_limit_q;
       // Narrow evidence always uses one grid cell. Dense strokes may use
       // the wider band for their interior pixels, but only this narrow
       // evidence is allowed to fill their outer-side coverage masks.
       line_strict_q<=line_segment_q&&line_cross_abs<=line_l1_q;
       for(line_test_index=1;line_test_index<8;line_test_index=line_test_index+1)
        line_bin_tests_q[line_test_index]<={line_offset_q,3'b0}>=line_part(line_span_q,line_test_index[2:0]);
       state<=TRI_STORE;
      end else state<=ACCUM;
     end
    TRI_STORE:begin
      if(triangle_phase==4)begin
       case(triangle_side)
        0:parallel_ab<={line_fit_q,line_bin};1:parallel_bc<={line_fit_q,line_bin};
        2:parallel_cd<={line_fit_q,line_bin};3:parallel_da<={line_fit_q,line_bin};
       endcase
      end else begin
       case(triangle_side)
        0:triangle_ab<={line_fit_q,line_bin};1:triangle_bc<={line_fit_q,line_bin};2:triangle_ca<={line_fit_q,line_bin};
       endcase
       triangle_strict_sides[triangle_side]<=line_strict_q;
      end
      if(triangle_side==(triangle_phase==4?3:2))state<=ACCUM;
      else begin triangle_side<=triangle_side+1'b1;state<=TRI_DIFF;end
     end
    ELLIPSE_SQUARE:begin
      ellipse_dx2<=ellipse_dx*ellipse_dx;ellipse_dy2<=ellipse_dy*ellipse_dy;
      ellipse_w2<=ellipse_w*ellipse_w;ellipse_h2<=ellipse_h*ellipse_h;
      ellipse_nx<=ellipse_ax*ellipse_h;ellipse_ny<=ellipse_ay*ellipse_w;
      state<=ELLIPSE_PRODUCT;
     end
    ELLIPSE_PRODUCT:begin
      ellipse_product_x<=ellipse_dx2*ellipse_h2;ellipse_product_y<=ellipse_dy2*ellipse_w2;
      ellipse_reference<=ellipse_w2*ellipse_h2;ellipse_bin<=ellipse_bin_next;state<=ELLIPSE_READ;
     end
    ELLIPSE_READ:begin
      ellipse_value<={1'b0,ellipse_product_x}+{1'b0,ellipse_product_y};
      state<=ELLIPSE_TEST;
     end
    ELLIPSE_TEST:begin
      ellipse_point_fit_q<=ellipse_point_fit;
      ellipse_profile_grow_q<=ellipse_value>ellipse_profile_q;state<=ACCUM;
     end
    ACCUM:begin
      if(triangle_phase!=0)begin
        if(triangle_phase==2)begin
          if(!line_cross_q[16]&&triangle_cross_abs>positive_cross)begin positive_cross<=triangle_cross_abs;pbx<=px;pby<=py;end
          if(line_cross_q[16]&&triangle_cross_abs>negative_cross)begin negative_cross<=triangle_cross_abs;pdx<=px;pdy<=py;end
        end
        if(triangle_phase==4)begin
          if(parallel_ab[3]||parallel_bc[3]||parallel_cd[3]||parallel_da[3])parallel_hits<=parallel_hits+1'b1;
          if(parallel_ab[3])parallel_cov_a[parallel_ab[2:0]]<=1;
          if(parallel_bc[3])parallel_cov_b[parallel_bc[2:0]]<=1;
          if(parallel_cd[3])parallel_cov_c[parallel_cd[2:0]]<=1;
          if(parallel_da[3])parallel_cov_d[parallel_da[2:0]]<=1;
        end else if(triangle_phase==1&&triangle_distance>triangle_farthest)begin
          triangle_farthest<=triangle_distance;tbx<=px;tby<=py;
        end else if(triangle_phase==2&&triangle_cross_abs>triangle_farthest)begin
          triangle_farthest<=triangle_cross_abs;tcx<=px;tcy<=py;
        end else if(triangle_phase==3)begin
          if(|triangle_strict_sides)triangle_strict_hits<=triangle_strict_hits+1'b1;
          if(triangle_ab[3]||triangle_bc[3]||triangle_ca[3])triangle_hits<=triangle_hits+1'b1;
          if(triangle_ab[3]&&(!triangle_dense_q||triangle_strict_sides[0]))triangle_cov_a[triangle_ab[2:0]]<=1;
          if(triangle_bc[3]&&(!triangle_dense_q||triangle_strict_sides[1]))triangle_cov_b[triangle_bc[2:0]]<=1;
          if(triangle_ca[3]&&(!triangle_dense_q||triangle_strict_sides[2]))triangle_cov_c[triangle_ca[2:0]]<=1;
        end
      end else if(!fit_pass)begin
        if(u<umin)umin<=u;if(u>umax)umax<=u;if(v<vmin)vmin<=v;if(v>vmax)vmax<=v;
        // A farthest point from the bbox center lies at a convex vertex.
        // Unlike a lexicographic leftmost point, this does not choose the
        // middle of a sloping edge quantized into a vertical grid column.
        if(angle==0&&distance2>triangle_farthest)begin tax<=px;tay<=py;triangle_farthest<=distance2;end
        // A printed outline has two physical boundaries. At a gap these
        // become one component, so retain a bounded stroke-width annulus.
        // Reject square-like corner occupancy independently of radial support.
        if(angle==0&&distance2>radial_profile[profile_bin])radial_profile[profile_bin]<=distance2;
        if(angle==0&&ax*4>=rad*3&&ay*4>=rad*3)circle_corner_hits<=circle_corner_hits+1'b1;
        if(angle==0&&distance2>=rlo2&&distance2<=rhi2)begin
          ring_hits<=ring_hits+1'b1;
          if(ay*2<ax)sectors[cdx[7]?4:0]<=1;
          else if(ax*2<ay)sectors[cdy[7]?6:2]<=1;
          else sectors[cdy[7]?(cdx[7]?5:7):(cdx[7]?3:1)]<=1;
        end
      end else begin
        // Envelope write uses the single muxed RAM port above.
        if(ellipse_point_fit_q)ellipse_hits<=ellipse_hits+1'b1;
        if(near_l||near_r||near_t||near_b)side_hits<=side_hits+1'b1;
        if(near_l)cov_l[vbin]<=1;if(near_r)cov_r[vbin]<=1;if(near_t)cov_t[ubin]<=1;if(near_b)cov_b[ubin]<=1;
        if(corner_l&&corner_t)corners[0]<=1;if(corner_r&&corner_t)corners[1]<=1;if(corner_l&&corner_b)corners[2]<=1;if(corner_r&&corner_b)corners[3]<=1;
      end
      state<=NEXT;
     end
    NEXT:if(index==n-1)begin
      if(triangle_phase!=0)begin
        index<=0;
        if(triangle_phase==1)begin triangle_phase<=2;triangle_farthest<=0;state<=POINT0;end
        else if(triangle_phase==2)begin
          triangle_phase<=3;triangle_hits<=0;triangle_strict_hits<=0;triangle_cov_a<=0;triangle_cov_b<=0;triangle_cov_c<=0;state<=POINT0;
        end else if(triangle_phase==3)begin triangle_fit_q<=triangle_fit;triangle_grade_q<=t_grade;state<=TCOMMIT;end
        else begin parallel_fit_q<=parallel_fit;parallel_grade_q<=p_grade;state<=PCOMMIT;end
      end else if(!fit_pass)begin
        
        fit_pass<=1;index<=0;side_hits<=0;cov_l<=0;cov_r<=0;cov_t<=0;cov_b<=0;corners<=0;state<=POINT0;
        ellipse_hits<=0;
        if(angle==0)begin
          profile_index<=0;profile_min<=16'hffff;profile_max<=0;profile_coverage<=0;
          opposite_min<=17'h1ffff;opposite_max<=0;opposite_coverage<=0;state<=CIRCLE_SCAN;
        end
      end else begin
        rectangle_fit_q<=rectangle_fit;rectangle_grade_q<=r_grade;state<=RECT_COMMIT;
      end
     end else begin index<=index+1'b1;state<=POINT0;end
    TCOMMIT:begin
      if(triangle_fit_q)component_t<=triangle_grade_q;
      // Any accepted rectangle takes precedence; no second quadrilateral label.
      if(component_r!=0)state<=FINISH;else state<=PPREP;
    end
    PPREP:begin
      line_dx_q<=$signed({1'b0,pbx})-$signed({1'b0,tax});line_dy_q<=$signed({1'b0,pby})-$signed({1'b0,tay});
      line_rx_q<=$signed({1'b0,pdx})-$signed({1'b0,tax});line_ry_q<=$signed({1'b0,pdy})-$signed({1'b0,tay});
      p_mid_error_x<=p_mid_x[8]?-p_mid_x:p_mid_x;p_mid_error_y<=p_mid_y[8]?-p_mid_y:p_mid_y;
      state<=PPRODUCT;
    end
    PPRODUCT:begin
      line_product_a_q<=line_dx_q*line_ry_q;line_product_b_q<=line_dy_q*line_rx_q;
      p_length_a<={1'b0,line_adx}+{1'b0,line_ady};
      p_length_d<=(line_rx_q[7]?-$signed(line_rx_q):line_rx_q)+(line_ry_q[7]?-$signed(line_ry_q):line_ry_q);
      state<=PCROSS;
    end
    PCROSS:begin
      line_cross_q<=$signed({line_product_a_q[15],line_product_a_q})-$signed({line_product_b_q[15],line_product_b_q});
      // Reuse the same two multipliers for dot product in the next cycle.
      line_rx_q<=line_ry_q;line_ry_q<=line_rx_q;state<=PDOT;
    end
    PDOT:begin
      line_product_a_q<=line_dx_q*line_ry_q;line_product_b_q<=line_dy_q*line_rx_q;
      p_cross<=line_cross_abs;state<=PCHECK;
    end
    PCHECK:begin p_dot<=p_dot_value[16]?-p_dot_value:p_dot_value;state<=PSTART;end
    PSTART:begin
      // Diagonals must bisect (equivalently both opposite side vectors
      // cancel); bounded error accounts for OR-grid vertex quantisation.
      // Reject near-right and acute/degenerate cases independently of support.
      parallel_geometry_q<=positive_cross!=0&&negative_cross!=0&&
        p_mid_error_x<=triangle_tol&&p_mid_error_y<=triangle_tol&&
        p_length_a>=8&&p_length_d>=8&&p_length_a<=4*p_length_d&&p_length_d<=4*p_length_a&&
        p_cross>triangle_area_q&&p_dot*8>p_cross&&p_dot<=3*p_cross;
      triangle_phase<=4;index<=0;parallel_hits<=0;
      parallel_cov_a<=0;parallel_cov_b<=0;parallel_cov_c<=0;parallel_cov_d<=0;state<=POINT0;
    end
    PCOMMIT:begin if(parallel_fit_q)component_p<=parallel_grade_q;state<=FINISH;end
    RECT_COMMIT:begin
      if(rectangle_grade_q>raw_r_work)raw_r_work<=rectangle_grade_q;
      if(rectangle_fit_q&&rectangle_grade_q>component_r)begin component_r<=rectangle_grade_q;
        component_angle<=angle;component_umin<=umin;component_umax<=umax;component_vmin<=vmin;component_vmax<=vmax;end
      ellipse_scan<=0;ellipse_min<=33'h1ffffffff;ellipse_max<=0;ellipse_coverage<=0;state<=ELLIPSE_SCAN;
     end
    CIRCLE_SCAN:begin
      // The outer envelope is almost constant with angle for a circle even
      // when a black printed stroke contributes two connected boundaries.
      // A polygon or jagged blob has a varying outer-radius profile.
      if(radial_profile[profile_index]!=0)begin
       profile_coverage<=profile_coverage+1'b1;
       if(radial_profile[profile_index]<profile_min)profile_min<=radial_profile[profile_index];
       if(radial_profile[profile_index]>profile_max)profile_max<=radial_profile[profile_index];
      end
      // Opposite-angle sums cancel first-order center quantization error.
      // A true circular envelope stays constant, whereas hexagonal straight
      // sides produce a substantial periodic radius change. The +2*radius
      // allowance accounts for a bounded one-grid-cell discretization error.
      if(!profile_index[3]&&radial_profile[{1'b0,profile_index[2:0]}]!=0&&
          radial_profile[{1'b1,profile_index[2:0]}]!=0)begin
        opposite_coverage<=opposite_coverage+1'b1;
        if(opposite_radius<opposite_min)opposite_min<=opposite_radius;
        if(opposite_radius>opposite_max)opposite_max<=opposite_radius;
      end
      if(profile_index==15)state<=CIRCLE_EVAL;else profile_index<=profile_index+1'b1;
    end
    CIRCLE_EVAL:begin
      if(c_grade>raw_c_work)raw_c_work<=c_grade;
      if(circle_fit)component_c<=c_grade;
      state<=POINT0;
    end
    ELLIPSE_SCAN:begin
      if(ellipse_profile_q!=0)begin
        ellipse_coverage<=ellipse_coverage+1'b1;
        if(ellipse_profile_q<ellipse_min)ellipse_min<=ellipse_profile_q;
        if(ellipse_profile_q>ellipse_max)ellipse_max<=ellipse_profile_q;
      end
      if(ellipse_scan==15)state<=ELLIPSE_EVAL;else ellipse_scan<=ellipse_scan+1'b1;
    end
    ELLIPSE_EVAL:begin
      ellipse_fit_q<=ellipse_fit;ellipse_grade_q<=e_grade;state<=ELLIPSE_COMMIT;
    end
    ELLIPSE_COMMIT:begin
      if(ellipse_grade_q>raw_c_work)raw_c_work<=ellipse_grade_q;
      if(ellipse_fit_q&&ellipse_grade_q>component_e)begin
        component_e<=ellipse_grade_q;component_eangle<=angle;
        component_eumin<=umin;component_eumax<=umax;component_evmin<=vmin;component_evmax<=vmax;
      end
      if(angle==30)begin triangle_phase<=1;triangle_farthest<=0;index<=0;state<=POINT0;end
      else begin ellipse_clear_index<=0;ellipse_clear_active<=1;angle<=angle+5'd2;cs<=cosine(angle+5'd2);sn<=sine(angle+5'd2);fit_pass<=0;index<=0;
        umin<=65535;umax<=-65536;vmin<=65535;vmax<=-65536;state<=POINT0;end
    end
    FINISH:begin
      // One connected component cannot be both shape classes. Compare support
      // quality before publishing; independent objects can still report both.
      // Select one round candidate here, sharing bbox and grade storage. A
      // circle wins an equal-score cross-component tie, preserving the former
      // frame-level selection without a second bbox bank or frame-end mux.
      if(component_c>component_r&&component_c>=component_t&&component_c>=component_e&&component_c>=component_p&&
         (component_c>best_c||(component_c==best_c&&best_e!=0)))begin
        best_c<=component_c;best_e<=0;best_cx0<=save_x0;best_cx1<=save_x1;best_cy0<=save_y0;best_cy1<=save_y1;
      end
      if(component_r>=component_c&&component_r>=component_t&&component_r>=component_e&&component_r>best_r)begin best_r<=component_r;best_rx0<=save_x0;best_rx1<=save_x1;best_ry0<=save_y0;best_ry1<=save_y1;
        best_angle<=component_angle;best_umin<=component_umin;best_umax<=component_umax;best_vmin<=component_vmin;best_vmax<=component_vmax;end
      if(component_t>component_c&&component_t>component_r&&component_t>=component_e&&component_t>=component_p&&component_t>best_t)begin
        best_t<=component_t;best_tx0<=save_x0;best_tx1<=save_x1;best_ty0<=save_y0;best_ty1<=save_y1;
        best_tax<=tax;best_tay<=tay;best_tbx<=tbx;best_tby<=tby;best_tcx<=tcx;best_tcy<=tcy;
      end
      if(component_e>component_c&&component_e>component_r&&component_e>component_t&&component_e>=component_p&&component_e>best_c)begin
        best_c<=component_e;best_e<=component_e;best_cx0<=save_x0;best_cx1<=save_x1;best_cy0<=save_y0;best_cy1<=save_y1;
        best_eangle<=component_eangle;best_eumin<=component_eumin;best_eumax<=component_eumax;best_evmin<=component_evmin;best_evmax<=component_evmax;
      end
      if(component_p>component_c&&component_p>component_t&&component_p>component_e&&component_r==0&&component_p>best_p)begin
        best_p<=component_p;best_px0<=save_x0;best_px1<=save_x1;best_py0<=save_y0;best_py1<=save_y1;
        best_pvertices<={pdx,pdy,tbx,tby,pbx,pby,tax,tay};
      end
      accept<=1;state<=WAIT;
     end
    default:state<=WAIT;
   endcase
   if(done&&overflow)state<=WAIT;
  end
 end
endmodule

