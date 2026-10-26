`timescale 1ns/1ps
// Range bounds: native coordinate <=2047; model grid 0..127; Q8 projections
// have |bound|<=45974, span<=45974. Line dx/dy/rx/ry are -127..127,
// cross <=32258, tolerance product <=3810. No raster latency changes.
// Eight pixel-clock stages. Models change in blanking; video sidebands must
// travel through eight identical registers before the compositor consumes hits.
module case4_v11_overlay(
 input wire clk,rst,pixel_valid,edge_bit,input wire [10:0] x,y,
 input wire [4:0] valid,
 input wire [10:0] circle_x0,circle_x1,circle_y0,circle_y1,
 rect_x0,rect_x1,rect_y0,rect_y1,triangle_x0,triangle_x1,triangle_y0,triangle_y1,
 ellipse_x0,ellipse_x1,ellipse_y0,ellipse_y1,model_origin_x,model_origin_y,
 input wire [2:0] model_ds,input wire [4:0] rect_fit_angle,ellipse_fit_angle,
 input wire signed [18:0] rect_fit_umin,rect_fit_umax,rect_fit_vmin,rect_fit_vmax,
 ellipse_fit_umin,ellipse_fit_umax,ellipse_fit_vmin,ellipse_fit_vmax,
 input wire [10:0] parallel_x0,parallel_x1,parallel_y0,parallel_y1,
 input wire [55:0] parallel_vertices,input wire [3:0] parallel_tolerance,
 input wire [41:0] triangle_vertices,input wire [3:0] triangle_tolerance,
 output wire [4:0] outline
);
 function automatic signed [9:0] cosine(input [4:0] a);
 case(a)0:cosine=256;1:cosine=256;2:cosine=255;3:cosine=253;4:cosine=251;5:cosine=248;6:cosine=245;7:cosine=241;8:cosine=237;9:cosine=231;10:cosine=226;11:cosine=220;12:cosine=213;13:cosine=206;14:cosine=198;15:cosine=190;16:cosine=181;17:cosine=172;18:cosine=162;19:cosine=152;20:cosine=142;21:cosine=132;22:cosine=121;23:cosine=109;24:cosine=98;25:cosine=86;26:cosine=74;27:cosine=62;28:cosine=50;29:cosine=38;30:cosine=25;31:cosine=13;endcase
 endfunction
 function automatic signed [9:0] sine(input [4:0] a);
 case(a)0:sine=0;1:sine=13;2:sine=25;3:sine=38;4:sine=50;5:sine=62;6:sine=74;7:sine=86;8:sine=98;9:sine=109;10:sine=121;11:sine=132;12:sine=142;13:sine=152;14:sine=162;15:sine=172;16:sine=181;17:sine=190;18:sine=198;19:sine=206;20:sine=213;21:sine=220;22:sine=226;23:sine=231;24:sine=237;25:sine=241;26:sine=245;27:sine=248;28:sine=251;29:sine=253;30:sine=255;31:sine=256;endcase
 endfunction
 reg [4:0] gates[0:7];reg [6:0] ox,oy;
 reg signed [12:0] cdx,cdy;reg [11:0] ca,cb;reg [12:0] cdistance;
 reg [11:0] cradius;reg [9:0] cmargin;reg [4:0] chit;
 reg signed [9:0] rc,rs,ec,es;
 reg signed [15:0] rxx,ryy,rxy,ryx,exx,eyy,exy,eyx;reg signed [16:0] ru,rv,eu,ev;
 reg [10:0] rtol;reg signed [16:0] rumin_outer,rumax_outer,rvmin_outer,rvmax_outer,
 rumin_inner,rumax_inner,rvmin_inner,rvmax_inner;reg [4:0] rhit;
 reg signed [10:0] edx,edy;reg [10:0] eax,eay;reg [7:0] ew,eh;
 reg [15:0] eradius;reg [12:0] emargin;reg [17:0] enx,eny;reg [18:0] edistance;reg ehit;
 wire [6:0] vx[0:2],vy[0:2];
 assign vx[0]=triangle_vertices[13:7];assign vy[0]=triangle_vertices[6:0];
 assign vx[1]=triangle_vertices[27:21];assign vy[1]=triangle_vertices[20:14];
 assign vx[2]=triangle_vertices[41:35];assign vy[2]=triangle_vertices[34:28];
 wire signed [7:0] dx[0:2],dy[0:2];wire [7:0] adx[0:2],ady[0:2];
 wire [7:0] lo[0:2],hi[0:2],coord[0:2];
 reg signed [7:0] tdx[0:2],tdy[0:2],trx[0:2],try_[0:2];
 reg signed [15:0] cross_a[0:2],cross_b[0:2],tcross[0:2];reg [15:0] tabs[0:2];
 reg [11:0] tlimit[0:2];reg [3:0] tinrange[0:2];reg [2:0] thit[0:2];
 genvar g;generate for(g=0;g<3;g=g+1)begin:side
 localparam integer B=(g+1)%3;
 assign dx[g]=$signed({2'b0,vx[B]})-$signed({2'b0,vx[g]});
 assign dy[g]=$signed({2'b0,vy[B]})-$signed({2'b0,vy[g]});
 assign adx[g]=dx[g][7]?-dx[g]:dx[g];assign ady[g]=dy[g][7]?-dy[g]:dy[g];
 assign lo[g]=adx[g]>=ady[g]?(vx[g]<vx[B]?vx[g]:vx[B]):(vy[g]<vy[B]?vy[g]:vy[B]);
 assign hi[g]=adx[g]>=ady[g]?(vx[g]<vx[B]?vx[B]:vx[g]):(vy[g]<vy[B]?vy[B]:vy[g]);
 assign coord[g]=adx[g]>=ady[g]?ox:oy;
 end endgenerate
 wire [6:0] pvx[0:3],pvy[0:3];
 assign pvx[0]=parallel_vertices[13:7];assign pvy[0]=parallel_vertices[6:0];
 assign pvx[1]=parallel_vertices[27:21];assign pvy[1]=parallel_vertices[20:14];
 assign pvx[2]=parallel_vertices[41:35];assign pvy[2]=parallel_vertices[34:28];
 assign pvx[3]=parallel_vertices[55:49];assign pvy[3]=parallel_vertices[48:42];
 wire signed [7:0] pdx[0:3],pdy[0:3];wire [7:0] padx[0:3],pady[0:3];
 wire [7:0] plo[0:3],phi[0:3],pcoord[0:3];
 reg signed [7:0] pdxq[0:3],pdyq[0:3],prx[0:3],pry[0:3];
 reg signed [15:0] pcross_a[0:3],pcross_b[0:3],pcross[0:3];reg [15:0] pabs[0:3];
 reg [11:0] plimit[0:3];reg [3:0] pinrange[0:3];reg [2:0] phit[0:3];
 genvar pg;generate for(pg=0;pg<4;pg=pg+1)begin:parallel_side
 localparam integer B=(pg+1)%4;
 assign pdx[pg]=$signed({2'b0,pvx[B]})-$signed({2'b0,pvx[pg]});
 assign pdy[pg]=$signed({2'b0,pvy[B]})-$signed({2'b0,pvy[pg]});
 assign padx[pg]=pdx[pg][7]?-pdx[pg]:pdx[pg];assign pady[pg]=pdy[pg][7]?-pdy[pg]:pdy[pg];
 assign plo[pg]=padx[pg]>=pady[pg]?(pvx[pg]<pvx[B]?pvx[pg]:pvx[B]):(pvy[pg]<pvy[B]?pvy[pg]:pvy[B]);
 assign phi[pg]=padx[pg]>=pady[pg]?(pvx[pg]<pvx[B]?pvx[B]:pvx[pg]):(pvy[pg]<pvy[B]?pvy[B]:pvy[pg]);
 assign pcoord[pg]=padx[pg]>=pady[pg]?ox:oy;
 end endgenerate
 integer k;
 always @(posedge clk)begin
  if(rst)begin
   for(k=0;k<8;k=k+1)gates[k]<=0;
   ox<=0;oy<=0;cdx<=0;cdy<=0;ca<=0;cb<=0;cdistance<=0;cradius<=0;cmargin<=0;chit<=0;
   rc<=0;rs<=0;ec<=0;es<=0;rxx<=0;ryy<=0;rxy<=0;ryx<=0;exx<=0;eyy<=0;exy<=0;eyx<=0;ru<=0;rv<=0;eu<=0;ev<=0;
   rtol<=0;rumin_outer<=0;rumax_outer<=0;rvmin_outer<=0;rvmax_outer<=0;
   rumin_inner<=0;rumax_inner<=0;rvmin_inner<=0;rvmax_inner<=0;rhit<=0;
   edx<=0;edy<=0;eax<=0;eay<=0;ew<=0;eh<=0;eradius<=0;emargin<=0;enx<=0;eny<=0;edistance<=0;ehit<=0;
   for(k=0;k<3;k=k+1)begin tdx[k]<=0;tdy[k]<=0;trx[k]<=0;try_[k]<=0;cross_a[k]<=0;cross_b[k]<=0;tcross[k]<=0;tabs[k]<=0;tlimit[k]<=0;tinrange[k]<=0;thit[k]<=0;end
   for(k=0;k<4;k=k+1)begin pdxq[k]<=0;pdyq[k]<=0;prx[k]<=0;pry[k]<=0;pcross_a[k]<=0;pcross_b[k]<=0;pcross[k]<=0;pabs[k]<=0;plimit[k]<=0;pinrange[k]<=0;phit[k]<=0;end
  end else begin
   // Stage1: sample pixel coordinates and coarse gates. Preload frame-constant coefficients.
   gates[0]<=valid&{5{pixel_valid&&edge_bit}}&{
    x>=parallel_x0&&x<=parallel_x1&&y>=parallel_y0&&y<=parallel_y1,
    x>=ellipse_x0&&x<=ellipse_x1&&y>=ellipse_y0&&y<=ellipse_y1,
    x>=triangle_x0&&x<=triangle_x1&&y>=triangle_y0&&y<=triangle_y1,
    x>=rect_x0&&x<=rect_x1&&y>=rect_y0&&y<=rect_y1,
    x>=circle_x0&&x<=circle_x1&&y>=circle_y0&&y<=circle_y1};
   for(k=1;k<8;k=k+1)gates[k]<=gates[k-1];
   ox<=(x-model_origin_x)>>model_ds;oy<=(y-model_origin_y)>>model_ds;
   cdx<=$signed({1'b0,x,1'b0})-$signed({2'b0,circle_x0})-$signed({2'b0,circle_x1});
   cdy<=$signed({1'b0,y,1'b0})-$signed({2'b0,circle_y0})-$signed({2'b0,circle_y1});
   cradius<=(circle_x1-circle_x0+circle_y1-circle_y0+2)>>1;cmargin<=12+(cradius>>3);
   rc<=cosine(rect_fit_angle);rs<=sine(rect_fit_angle);ec<=cosine(ellipse_fit_angle);es<=sine(ellipse_fit_angle);
   rtol<=512+(((rect_fit_umax-rect_fit_umin)>(rect_fit_vmax-rect_fit_vmin)?rect_fit_umax-rect_fit_umin:rect_fit_vmax-rect_fit_vmin)>>5);
   rumin_outer<=$signed(rect_fit_umin)-$signed({1'b0,rtol});rumax_outer<=$signed(rect_fit_umax)+$signed({1'b0,rtol});
   rvmin_outer<=$signed(rect_fit_vmin)-$signed({1'b0,rtol});rvmax_outer<=$signed(rect_fit_vmax)+$signed({1'b0,rtol});
   rumin_inner<=$signed(rect_fit_umin)+$signed({1'b0,rtol});rumax_inner<=$signed(rect_fit_umax)-$signed({1'b0,rtol});
   rvmin_inner<=$signed(rect_fit_vmin)+$signed({1'b0,rtol});rvmax_inner<=$signed(rect_fit_vmax)-$signed({1'b0,rtol});
   ew<=(ellipse_fit_umax-ellipse_fit_umin+128)>>8;eh<=(ellipse_fit_vmax-ellipse_fit_vmin+128)>>8;
   eradius<=ew*eh;emargin<=(eradius>>3)+32;
   // Stage2: first products / triangle vector differences / absolute circle offsets.
   rxx<=$signed({1'b0,ox})*rc;ryy<=$signed({1'b0,oy})*rs;rxy<=-$signed({1'b0,ox})*rs;ryx<=$signed({1'b0,oy})*rc;
   exx<=$signed({1'b0,ox})*ec;eyy<=$signed({1'b0,oy})*es;exy<=-$signed({1'b0,ox})*es;eyx<=$signed({1'b0,oy})*ec;
   ca<=cdx[12]?-cdx:cdx;cb<=cdy[12]?-cdy:cdy;
   for(k=0;k<3;k=k+1)begin
    tdx[k]<=dx[k];tdy[k]<=dy[k];trx[k]<=$signed({2'b0,ox})-$signed({2'b0,vx[k]});try_[k]<=$signed({2'b0,oy})-$signed({2'b0,vy[k]});
    tinrange[k]<={tinrange[k][2:0],(adx[k]+ady[k]>=8&&coord[k]+triangle_tolerance>=lo[k]&&coord[k]<=hi[k]+triangle_tolerance)};
    tlimit[k]<=(adx[k]+ady[k])*triangle_tolerance;
    // Stage3: line cross products. Stage4 subtract, stage5 absolute, stage6 compare.
    cross_a[k]<=tdx[k]*try_[k];cross_b[k]<=tdy[k]*trx[k];tcross[k]<=cross_a[k]-cross_b[k];tabs[k]<=tcross[k][15]?-tcross[k]:tcross[k];
    thit[k]<={thit[k][1:0],(tinrange[k][3]&&tabs[k]<=tlimit[k])};
   end
   for(k=0;k<4;k=k+1)begin
    pdxq[k]<=pdx[k];pdyq[k]<=pdy[k];prx[k]<=$signed({2'b0,ox})-$signed({2'b0,pvx[k]});pry[k]<=$signed({2'b0,oy})-$signed({2'b0,pvy[k]});
    pinrange[k]<={pinrange[k][2:0],(padx[k]+pady[k]>=8&&pcoord[k]+parallel_tolerance>=plo[k]&&pcoord[k]<=phi[k]+parallel_tolerance)};
    plimit[k]<=(padx[k]+pady[k])*parallel_tolerance;
    // Stage3: line cross products. Stage4 subtract, stage5 absolute, stage6 compare.
    pcross_a[k]<=pdxq[k]*pry[k];pcross_b[k]<=pdyq[k]*prx[k];pcross[k]<=pcross_a[k]-pcross_b[k];pabs[k]<=pcross[k][15]?-pcross[k]:pcross[k];
    phit[k]<={phit[k][1:0],(pinrange[k][3]&&pabs[k]<=plimit[k])};
   end
   // Stage3 / Stage4 / Stage5 / Stage6 / Stage7 / Stage8.
   ru<=$signed({rxx[15],rxx})+$signed({ryy[15],ryy});rv<=$signed({rxy[15],rxy})+$signed({ryx[15],ryx});eu<=$signed({exx[15],exx})+$signed({eyy[15],eyy});ev<=$signed({exy[15],exy})+$signed({eyx[15],eyx});
   cdistance<=ca>cb?ca+(cb>>2)+(cb>>3):cb+(ca>>2)+(ca>>3);
   chit<={chit[3:0],(cdistance+cmargin>=cradius&&cdistance<=cradius+cmargin)};
   rhit<={rhit[3:0],(ru>=rumin_outer&&ru<=rumax_outer&&rv>=rvmin_outer&&rv<=rvmax_outer&&
    (ru<=rumin_inner||ru>=rumax_inner||rv<=rvmin_inner||rv>=rvmax_inner))};
   edx<=($signed(eu)*2-$signed(ellipse_fit_umin)-$signed(ellipse_fit_umax))>>>8;
   edy<=($signed(ev)*2-$signed(ellipse_fit_vmin)-$signed(ellipse_fit_vmax))>>>8;
   eax<=edx[10]?-edx:edx;eay<=edy[10]?-edy:edy;
   enx<=eax*eh;eny<=eay*ew;
   edistance<=enx>eny?enx+(eny>>2)+(eny>>3):eny+(enx>>2)+(enx>>3);
   ehit<=edistance+emargin>=eradius&&edistance<=eradius+emargin;
  end
 end
 assign outline=gates[7]&{(phit[0][2]||phit[1][2]||phit[2][2]||phit[3][2]),ehit,(thit[0][2]||thit[1][2]||thit[2][2]),rhit[4],chit[4]};
endmodule
