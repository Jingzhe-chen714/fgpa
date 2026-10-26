`timescale 1ns/1ps
// V8 isolated-component feature matching. Raster input never stalls. Analysis
// is bounded and uses a separate captured map; only fresh camera observations
// enter the temporal confirmation logic. Coordinates always remain native.
// The generic extractor below is also used by case4_v8_face.
module case4_v8_components #(
 parameter integer IMG_WIDTH=1920,IMG_HEIGHT=1080,DS_LOG2=2,
 parameter integer GAP_CELLS=1,MAX_POINTS=2048,FIFO_DEPTH=2048,STORE_POINTS=1,
 parameter integer MAX_ANALYSIS_CYCLES=IMG_WIDTH*IMG_HEIGHT*2,
 parameter integer GW=(IMG_WIDTH/2+(1<<DS_LOG2)-1)>>DS_LOG2,
 parameter integer GH=(IMG_HEIGHT+(1<<DS_LOG2)-1)>>DS_LOG2,
 parameter integer AB=$clog2(GW*GH),GX=$clog2(GW),GY=$clog2(GH),
 parameter integer PB=$clog2(MAX_POINTS),FB=$clog2(FIFO_DEPTH)
)(
 input wire clk,rst_n,clear,frame_start,sample_tick,pixel_valid,
 input wire [10:0] x,y,input wire mask_bit,
 output reg busy,overflow,frame_done,component_ready,
 input wire component_accept,
 output reg [10:0] bx0,bx1,by0,by1,
 output reg [PB:0] point_count,output reg component_too_large,
 input wire [PB-1:0] point_index,
 output reg [GX-1:0] point_x,output reg [GY-1:0] point_y
);
 localparam integer N=GW*GH,ROI=IMG_WIDTH/2,DS=1<<DS_LOG2;
 localparam integer MEMORY_DEPTH=STORE_POINTS&&MAX_POINTS>FIFO_DEPTH?MAX_POINTS:FIFO_DEPTH;
 localparam integer MB=$clog2(MEMORY_DEPTH);
 localparam [3:0] IDLE=0,SCAN_READ=1,SCAN_WAIT=2,POP_READ=3,POP_WAIT=4,
   NEIGH_READ=5,NEIGH_WAIT=6,COMPONENT=7,ADVANCE=8,FAILED=9;
 reg [3:0] state;
 reg map0[0:N-1],map1[0:N-1];
 // FIFO order is exactly the component traversal order. For a fitting-sized
 // component the consumed slots are retained as its point list. Oversized
 // components reuse the same circular FIFO while draining, and are not fitted.
 reg [GX+GY-1:0] fifo[0:MEMORY_DEPTH-1];
 reg [GW-1:0] column_or;
 reg capture_bank,process_bank,capture_active;
 reg [AB:0] capture_count;
 wire [10:0] local_x=x-ROI;
 wire [GX-1:0] block_x=local_x>>DS_LOG2;
 wire take=capture_active&&pixel_valid&&x>=ROI&&x<IMG_WIDTH&&y<IMG_HEIGHT;
 wire emit_cell=take&&((local_x&(DS-1))==DS-1||x==IMG_WIDTH-1)&&
   ((y&(DS-1))==DS-1||y==IMG_HEIGHT-1);
 wire launch=frame_start&&capture_active&&capture_count==N&&!busy;
 reg [AB-1:0] scan_address,read_address;
 reg [GX-1:0] scan_x,cx,nx;
 reg [GY-1:0] scan_y,cy,ny;
 reg [4:0] neighbor;
 reg neighbor_ok;
 reg [FB:0] queued;
 reg [MB-1:0] head,tail;
 reg [GX+GY-1:0] fifo_q;
 reg map_q0,map_q1;
 wire map_q=process_bank?map_q1:map_q0;
 wire read_map=state==SCAN_READ||(state==NEIGH_READ&&neighbor_ok);
 wire enqueue=(state==SCAN_WAIT&&map_q)||(state==NEIGH_WAIT&&neighbor_ok&&map_q);
 wire [GX-1:0] push_x=state==SCAN_WAIT?scan_x:nx;
 wire [GY-1:0] push_y=state==SCAN_WAIT?scan_y:ny;
 wire [AB-1:0] erase_address=state==SCAN_WAIT?scan_address:read_address;
 wire erase=enqueue&&queued<FIFO_DEPTH;
 wire capture_we=emit_cell&&capture_count<N;
 wire map0_capture=capture_we&&!capture_bank,map1_capture=capture_we&&capture_bank;
 wire map0_we=map0_capture||(erase&&!process_bank),map1_we=map1_capture||(erase&&process_bank);
 wire [AB-1:0] map0_wa=map0_capture?capture_count[AB-1:0]:erase_address;
 wire [AB-1:0] map1_wa=map1_capture?capture_count[AB-1:0]:erase_address;
 wire map0_wd=map0_capture&&(column_or[block_x]||mask_bit);
 wire map1_wd=map1_capture&&(column_or[block_x]||mask_bit);
 wire [MB-1:0] queue_write_address=state==SCAN_WAIT?{MB{1'b0}}:tail;
 wire point_read=STORE_POINTS&&state==COMPONENT;
 wire [MB-1:0] queue_read_address=point_read?point_index:head;
 // One muxed write port per bitmap, one synchronous read port. Capture and
 // flood erasure always address opposite banks while busy.
 always @(posedge clk) begin
   if(map0_we)map0[map0_wa]<=map0_wd;
   if(map1_we)map1[map1_wa]<=map1_wd;
   if(read_map) begin map_q0<=map0[read_address];map_q1<=map1[read_address];end
   if(erase)fifo[queue_write_address]<={push_y,push_x};
   if(state==POP_READ||point_read)fifo_q<=fifo[queue_read_address];
   if(point_read)begin point_x<=fifo_q[GX-1:0];point_y<=fifo_q[GX+GY-1:GX];end
 end
 integer ox,oy;
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
   endcase
   nx=$signed({1'b0,cx})+ox;ny=$signed({1'b0,cy})+oy;
   neighbor_ok=($signed({1'b0,cx})+ox>=0)&&($signed({1'b0,cx})+ox<GW)&&
     ($signed({1'b0,cy})+oy>=0)&&($signed({1'b0,cy})+oy<GH);
   read_address=state==SCAN_READ?scan_address:ny*GW+nx;
 end
 reg [23:0] work_cycles;
 always @(posedge clk) begin
  if(!rst_n||clear) begin
   state<=IDLE;busy<=0;overflow<=0;frame_done<=0;component_ready<=0;
   capture_bank<=0;process_bank<=0;capture_active<=0;capture_count<=0;column_or<=0;
   scan_address<=0;scan_x<=0;scan_y<=0;cx<=0;cy<=0;neighbor<=0;
   head<=0;tail<=0;queued<=0;point_count<=0;component_too_large<=0;
   bx0<=0;bx1<=0;by0<=0;by1<=0;work_cycles<=0;
  end else begin
   frame_done<=0;
   if(frame_start) begin
    capture_active<=sample_tick;capture_count<=0;column_or<=0;
    if(launch) begin
      capture_bank<=!capture_bank;process_bank<=capture_bank;busy<=1;overflow<=0;
      state<=SCAN_READ;scan_address<=0;scan_x<=0;scan_y<=0;work_cycles<=0;
    end
   end else if(take) begin
    column_or[block_x]<=emit_cell?1'b0:column_or[block_x]||mask_bit;
    if(emit_cell&&capture_count<N)capture_count<=capture_count+1'b1;
   end
   if(busy)begin
    work_cycles<=work_cycles+1'b1;
    if(work_cycles>=MAX_ANALYSIS_CYCLES&&state!=FAILED)state<=FAILED;
    else case(state)
     SCAN_READ:state<=SCAN_WAIT;
     SCAN_WAIT:if(map_q)begin
       head<=0;tail<=1;queued<=1;point_count<=0;component_too_large<=0;
       bx0<=ROI+(scan_x<<DS_LOG2);bx1<=ROI+((scan_x+11'd1)<<DS_LOG2)-1;
       by0<=scan_y<<DS_LOG2;by1<=((scan_y+11'd1)<<DS_LOG2)-1;
       state<=POP_READ;
      end else state<=ADVANCE;
     POP_READ:state<=POP_WAIT;
     POP_WAIT:begin
       cx<=fifo_q[GX-1:0];cy<=fifo_q[GX+GY-1:GX];head<=head+1'b1;queued<=queued-1'b1;
       if(point_count<MAX_POINTS)point_count<=point_count+1'b1;else component_too_large<=1;
       if(ROI+(fifo_q[GX-1:0]<<DS_LOG2)<bx0)bx0<=ROI+(fifo_q[GX-1:0]<<DS_LOG2);
       if(ROI+((fifo_q[GX-1:0]+11'd1)<<DS_LOG2)-1>bx1)bx1<=ROI+((fifo_q[GX-1:0]+11'd1)<<DS_LOG2)-1;
       if((fifo_q[GX+GY-1:GX]<<DS_LOG2)<by0)by0<=fifo_q[GX+GY-1:GX]<<DS_LOG2;
       if(((fifo_q[GX+GY-1:GX]+11'd1)<<DS_LOG2)-1>by1)by1<=((fifo_q[GX+GY-1:GX]+11'd1)<<DS_LOG2)-1;
       neighbor<=0;state<=NEIGH_READ;
      end
     NEIGH_READ:state<=NEIGH_WAIT;
     NEIGH_WAIT:begin
       if(neighbor_ok&&map_q)begin
         if(queued==FIFO_DEPTH)begin overflow<=1;state<=FAILED;end
         else begin tail<=tail+1'b1;queued<=queued+1'b1;end
       end
       if(!(neighbor_ok&&map_q&&queued==FIFO_DEPTH))begin
        if(neighbor==(GAP_CELLS?15:7))begin
          if(queued!=0||(neighbor_ok&&map_q))state<=POP_READ;
          else begin state<=COMPONENT;component_ready<=1;end
        end else begin neighbor<=neighbor+1'b1;state<=NEIGH_READ;end
       end
      end
     COMPONENT:if(component_accept)begin component_ready<=0;state<=ADVANCE;end
     ADVANCE:if(scan_address==N-1)begin busy<=0;frame_done<=1;state<=IDLE;end
      else begin scan_address<=scan_address+1'b1;if(scan_x==GW-1)begin scan_x<=0;scan_y<=scan_y+1'b1;end else scan_x<=scan_x+1'b1;state<=SCAN_READ;end
     FAILED:begin busy<=0;overflow<=1;component_ready<=0;frame_done<=1;state<=IDLE;end
     default:state<=IDLE;
    endcase
   end
  end
 end
endmodule

module case4_v8_shape #(
 parameter integer IMG_WIDTH=1920,IMG_HEIGHT=1080,DS_LOG2=2,
 parameter integer MIN_SPAN=32,MAX_POINTS=2048,CONFIRM_FRAMES=2,LOSS_FRAMES=3,
 parameter integer GW=(IMG_WIDTH/2+(1<<DS_LOG2)-1)>>DS_LOG2,
 parameter integer GH=(IMG_HEIGHT+(1<<DS_LOG2)-1)>>DS_LOG2,
 parameter integer PB=$clog2(MAX_POINTS),GX=$clog2(GW),GY=$clog2(GH)
)(
 input wire clk,rst_n,clear,frame_start,sample_tick,pixel_valid,
 input wire [10:0] x,y,input wire edge_bit,
 output reg circle_valid,rect_valid,
 output reg [10:0] circle_x0,circle_x1,circle_y0,circle_y1,
 output reg [10:0] rect_x0,rect_x1,rect_y0,rect_y1,
 output wire circle_outline,rect_outline,
 output reg [7:0] circle_score,rect_score,
 output wire busy,overflow,output reg result_tick
);
 wire ready,done,oversize;reg accept;
 wire [10:0] bx0,bx1,by0,by1;wire [PB:0] count;
 reg [PB-1:0] index;
 wire [GX-1:0] px;wire [GY-1:0] py;
 case4_v8_components #(.IMG_WIDTH(IMG_WIDTH),.IMG_HEIGHT(IMG_HEIGHT),.DS_LOG2(DS_LOG2),.MAX_POINTS(MAX_POINTS)) components(
  .clk(clk),.rst_n(rst_n),.clear(clear),.frame_start(frame_start),.sample_tick(sample_tick),.pixel_valid(pixel_valid),
  .x(x),.y(y),.mask_bit(edge_bit),.busy(busy),.overflow(overflow),.frame_done(done),.component_ready(ready),.component_accept(accept),
  .bx0(bx0),.bx1(bx1),.by0(by0),.by1(by1),.point_count(count),.component_too_large(oversize),.point_index(index),.point_x(px),.point_y(py));
 // 32 orthogonal-line templates span [0,90) in 2.8125-degree steps.
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
 localparam [3:0] WAIT=0,POINT0=1,POINT1=2,POINT2=3,PROJECT=4,ACCUM=5,NEXT=6,FINISH=7;
 reg [3:0] state;reg [4:0] angle;reg fit_pass;
 reg signed [18:0] u,v,umin,umax,vmin,vmax;
 reg signed [9:0] cs,sn;
 reg [12:0] dx,dy,rad;reg [25:0] distance2,rlo2,rhi2;
 reg [PB:0] ring_hits,side_hits;
 reg [7:0] sectors,cov_l,cov_r,cov_t,cov_b;reg [3:0] corners;
 reg [2:0] sector;
 reg [10:0] bw,bh;reg [PB:0] n;
 reg [10:0] save_x0,save_x1,save_y0,save_y1;
 reg [7:0] best_c,best_r,pending_c,pending_r;
 reg publish_pending;
 reg [7:0] component_c,component_r;
 reg [4:0] component_angle;
 reg signed [18:0] component_umin,component_umax,component_vmin,component_vmax;
 reg [10:0] best_cx0,best_cx1,best_cy0,best_cy1,best_rx0,best_rx1,best_ry0,best_ry1;
 reg [4:0] best_angle,publish_angle;
 reg signed [18:0] best_umin,best_umax,best_vmin,best_vmax,pub_umin,pub_umax,pub_vmin,pub_vmax;
 reg [7:0] c_hits,r_hits,c_miss,r_miss;
 reg signed [13:0] cdx,cdy;
 reg [12:0] ax,ay;
 wire [18:0] uw=umax-umin,vh=vmax-vmin;
 wire [18:0] tol=19'd384+((uw>vh?uw:vh)>>5);
 wire near_l=u<=umin+$signed(tol),near_r=u>=umax-$signed(tol);
 wire near_t=v<=vmin+$signed(tol),near_b=v>=vmax-$signed(tol);
 reg [2:0] ubin,vbin;integer j;
 always @* begin
  ubin=0;vbin=0;
  for(j=1;j<8;j=j+1)begin if(u>=umin+$signed((uw*j)>>3))ubin=j;if(v>=vmin+$signed((vh*j)>>3))vbin=j;end
 end
 wire [11:0] width_diff=bw>bh?bw-bh:bh-bw;
 wire circle_fit=width_diff<=((bw>bh?bw:bh)>>3)+2&&pop8(sectors)>=7&&ring_hits*10>=n*9;
 wire rectangle_fit=uw>=MIN_SPAN*256/(1<<DS_LOG2)&&vh>=MIN_SPAN*256/(1<<DS_LOG2)&&
    uw<=4*vh&&vh<=4*uw&&side_hits*10>=n*9&&pop8({4'b0,corners})>=3&&
    pop8(cov_l)>=6&&pop8(cov_r)>=6&&pop8(cov_t)>=6&&pop8(cov_b)>=6;
 // Normalized support counts: grades 90..100 only for accepted fits. Division
 // is deliberately absent from the hardware critical path.
 wire [7:0] c_grade=(ring_hits==n)?100:(ring_hits*20>=n*19)?95:90;
 wire [7:0] r_grade=(side_hits==n)?100:(side_hits*20>=n*19)?95:90;
 wire geometry_ok=!oversize&&count>=12&&bx1-bx0+1>=MIN_SPAN&&by1-by0+1>=MIN_SPAN&&
   bx0>IMG_WIDTH/2&&bx1<IMG_WIDTH-1&&by0>0&&by1<IMG_HEIGHT-1;
 // Overlay is geometric support only, never every edge inside a oversize bbox.
 wire signed [12:0] odx=$signed({1'b0,x,1'b0})-$signed({2'b0,circle_x0})-$signed({2'b0,circle_x1});
 wire signed [12:0] ody=$signed({1'b0,y,1'b0})-$signed({2'b0,circle_y0})-$signed({2'b0,circle_y1});
 wire [12:0] oa=odx[12]?-odx:odx,ob=ody[12]?-ody:ody;
 // Octagonal radial approximation is for highlighting only, not recognition.
 wire [13:0] oradius=(circle_x1-circle_x0+circle_y1-circle_y0+2)>>1;
 wire [13:0] odistance=oa>ob?oa+(ob>>2)+(ob>>3):ob+(oa>>2)+(oa>>3);
 wire [13:0] omargin=12+(oradius>>3);
 wire [GX-1:0] ox=(x-IMG_WIDTH/2)>>DS_LOG2;wire [GY-1:0] oy=y>>DS_LOG2;
 wire signed [18:0] ou=$signed({1'b0,ox})*cosine(publish_angle)+$signed({1'b0,oy})*sine(publish_angle);
 wire signed [18:0] ov=-$signed({1'b0,ox})*sine(publish_angle)+$signed({1'b0,oy})*cosine(publish_angle);
 wire [18:0] otol=512+(((pub_umax-pub_umin)>(pub_vmax-pub_vmin)?pub_umax-pub_umin:pub_vmax-pub_vmin)>>5);
 assign circle_outline=pixel_valid&&edge_bit&&circle_valid&&x>=circle_x0&&x<=circle_x1&&y>=circle_y0&&y<=circle_y1&&
   odistance+omargin>=oradius&&odistance<=oradius+omargin;
 assign rect_outline=pixel_valid&&edge_bit&&rect_valid&&x>=rect_x0&&x<=rect_x1&&y>=rect_y0&&y<=rect_y1&&
   ou>=pub_umin-$signed(otol)&&ou<=pub_umax+$signed(otol)&&ov>=pub_vmin-$signed(otol)&&ov<=pub_vmax+$signed(otol)&&
   (ou<=pub_umin+$signed(otol)||ou>=pub_umax-$signed(otol)||ov<=pub_vmin+$signed(otol)||ov>=pub_vmax-$signed(otol));
 always @(posedge clk)begin
  if(!rst_n||clear)begin
   state<=WAIT;accept<=0;index<=0;angle<=0;fit_pass<=0;cs<=256;sn<=0;
   circle_valid<=0;rect_valid<=0;circle_score<=0;rect_score<=0;result_tick<=0;
   circle_x0<=0;circle_x1<=0;circle_y0<=0;circle_y1<=0;rect_x0<=0;rect_x1<=0;rect_y0<=0;rect_y1<=0;
   best_c<=0;best_r<=0;pending_c<=0;pending_r<=0;publish_pending<=0;c_hits<=0;r_hits<=0;c_miss<=0;r_miss<=0;
   publish_angle<=0;pub_umin<=0;pub_umax<=0;pub_vmin<=0;pub_vmax<=0;
   best_cx0<=0;best_cx1<=0;best_cy0<=0;best_cy1<=0;best_rx0<=0;best_rx1<=0;best_ry0<=0;best_ry1<=0;
   best_angle<=0;best_umin<=0;best_umax<=0;best_vmin<=0;best_vmax<=0;
  end else begin
   accept<=0;result_tick<=0;
   if(done)begin
    pending_c<=overflow?0:best_c;pending_r<=overflow?0:best_r;
    best_c<=0;best_r<=0;publish_pending<=1;
   end
   if(frame_start&&publish_pending)begin
    publish_pending<=done;
    if(pending_c!=0)begin
      c_miss<=0;if(c_hits<CONFIRM_FRAMES)c_hits<=c_hits+1'b1;
      if(c_hits>=CONFIRM_FRAMES-1)begin circle_valid<=1;circle_score<=pending_c;circle_x0<=best_cx0;circle_x1<=best_cx1;circle_y0<=best_cy0;circle_y1<=best_cy1;end
    end else begin c_hits<=0;if(c_miss<LOSS_FRAMES)c_miss<=c_miss+1'b1;if(c_miss>=LOSS_FRAMES-1)begin circle_valid<=0;circle_score<=0;end end
    if(pending_r!=0)begin
      r_miss<=0;if(r_hits<CONFIRM_FRAMES)r_hits<=r_hits+1'b1;
      if(r_hits>=CONFIRM_FRAMES-1)begin rect_valid<=1;rect_score<=pending_r;rect_x0<=best_rx0;rect_x1<=best_rx1;rect_y0<=best_ry0;rect_y1<=best_ry1;
        publish_angle<=best_angle;pub_umin<=best_umin;pub_umax<=best_umax;pub_vmin<=best_vmin;pub_vmax<=best_vmax;end
    end else begin r_hits<=0;if(r_miss<LOSS_FRAMES)r_miss<=r_miss+1'b1;if(r_miss>=LOSS_FRAMES-1)begin rect_valid<=0;rect_score<=0;end end
    result_tick<=1;
   end
   case(state)
    WAIT:if(ready&&!accept)begin
      if(!geometry_ok)accept<=1;
      else begin
       save_x0<=bx0;save_x1<=bx1;save_y0<=by0;save_y1<=by1;bw<=bx1-bx0+1;bh<=by1-by0+1;n<=count;
       index<=0;angle<=0;cs<=256;sn<=0;fit_pass<=0;ring_hits<=0;sectors<=0;component_c<=0;component_r<=0;
       // Match centers of occupied cells, not their inflated outer extents.
       rad<=((bx1-bx0+by1-by0+2)>>(DS_LOG2+1))-1'b1;
       umin<=262143;umax<=-262144;vmin<=262143;vmax<=-262144;
       state<=POINT0;
      end
     end
    POINT0:begin
      rlo2<=(rad>2+(rad>>5)?rad-2-(rad>>5):0)*(rad>2+(rad>>5)?rad-2-(rad>>5):0);
      rhi2<=(rad+2+(rad>>5))*(rad+2+(rad>>5));state<=POINT1;
     end
    POINT1:state<=POINT2;
    POINT2:begin
      cdx<=$signed({1'b0,px,1'b0})-$signed((save_x0-IMG_WIDTH/2)>>DS_LOG2)-$signed((save_x1-IMG_WIDTH/2)>>DS_LOG2);
      cdy<=$signed({1'b0,py,1'b0})-$signed(save_y0>>DS_LOG2)-$signed(save_y1>>DS_LOG2);
      u<=$signed({1'b0,px})*cs+$signed({1'b0,py})*sn;
      v<=-$signed({1'b0,px})*sn+$signed({1'b0,py})*cs;state<=PROJECT;
     end
    PROJECT:begin
      distance2<=cdx*cdx+cdy*cdy;
      ax<=cdx[13]?-cdx:cdx;ay<=cdy[13]?-cdy:cdy;state<=ACCUM;
     end
    ACCUM:begin
      if(!fit_pass)begin
        if(u<umin)umin<=u;if(u>umax)umax<=u;if(v<vmin)vmin<=v;if(v>vmax)vmax<=v;
        if(angle==0&&distance2>=rlo2&&distance2<=rhi2)begin
          ring_hits<=ring_hits+1'b1;
          if(ay*2<ax)sectors[cdx[13]?4:0]<=1;
          else if(ax*2<ay)sectors[cdy[13]?6:2]<=1;
          else sectors[cdy[13]?(cdx[13]?5:7):(cdx[13]?3:1)]<=1;
        end
      end else begin
        if(near_l||near_r||near_t||near_b)side_hits<=side_hits+1'b1;
        if(near_l)cov_l[vbin]<=1;if(near_r)cov_r[vbin]<=1;if(near_t)cov_t[ubin]<=1;if(near_b)cov_b[ubin]<=1;
        if(near_l&&near_t)corners[0]<=1;if(near_r&&near_t)corners[1]<=1;if(near_l&&near_b)corners[2]<=1;if(near_r&&near_b)corners[3]<=1;
      end
      state<=NEXT;
     end
    NEXT:if(index==n-1)begin
      if(!fit_pass)begin
        if(angle==0&&circle_fit)component_c<=c_grade;
        fit_pass<=1;index<=0;side_hits<=0;cov_l<=0;cov_r<=0;cov_t<=0;cov_b<=0;corners<=0;state<=POINT0;
      end else begin
        if(rectangle_fit&&r_grade>component_r)begin component_r<=r_grade;
          component_angle<=angle;component_umin<=umin;component_umax<=umax;component_vmin<=vmin;component_vmax<=vmax;end
        if(angle==31)state<=FINISH;
        else begin angle<=angle+1'b1;cs<=cosine(angle+1'b1);sn<=sine(angle+1'b1);fit_pass<=0;index<=0;
          umin<=262143;umax<=-262144;vmin<=262143;vmax<=-262144;state<=POINT0;end
      end
     end else begin index<=index+1'b1;state<=POINT0;end
    FINISH:begin
      // One connected component cannot be both shape classes. Compare support
      // quality before publishing; independent objects can still report both.
      if(component_c>component_r&&component_c>best_c)begin best_c<=component_c;best_cx0<=save_x0;best_cx1<=save_x1;best_cy0<=save_y0;best_cy1<=save_y1;end
      if(component_r>=component_c&&component_r>best_r)begin best_r<=component_r;best_rx0<=save_x0;best_rx1<=save_x1;best_ry0<=save_y0;best_ry1<=save_y1;
        best_angle<=component_angle;best_umin<=component_umin;best_umax<=component_umax;best_vmin<=component_vmin;best_vmax<=component_vmax;end
      accept<=1;state<=WAIT;
     end
    default:state<=WAIT;
   endcase
   if(done&&overflow)state<=WAIT;
  end
 end
endmodule

