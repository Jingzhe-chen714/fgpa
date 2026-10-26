`timescale 1ns/1ps
// V6 candidate acquisition only: ping-pong block-OR maps and bounded exact
// 8-connected component labeling. Output boxes are in ORIGINAL coordinates.
// No raster backpressure. A busy analysis skips a snapshot; label/path/budget
// overflow publishes no candidates instead of reusing ambiguous labels.
module case4_component_candidates #(
    parameter integer IMG_WIDTH=1920, IMG_HEIGHT=1080, DS_LOG2=2,
    parameter integer CANDIDATES=4, MAX_LABELS=512, MIN_SPAN=32,
    parameter integer MAX_ANALYSIS_CYCLES=IMG_WIDTH*IMG_HEIGHT,
    parameter integer GW=(IMG_WIDTH/2+(1<<DS_LOG2)-1)>>DS_LOG2,
    parameter integer GH=(IMG_HEIGHT+(1<<DS_LOG2)-1)>>DS_LOG2,
    parameter integer GX=$clog2(GW), GY=$clog2(GH), LB=$clog2(MAX_LABELS),
    parameter integer AB=$clog2(GW*GH)
)(
    input wire clk,rst_n,frame_start,pixel_valid,
    input wire [10:0] x,y,input wire edge_bit,
    output reg candidate_toggle,output reg busy,overflow,
    output reg [CANDIDATES-1:0] candidate_valid,
    output reg [10:0] box_x0[0:CANDIDATES-1],
    output reg [10:0] box_x1[0:CANDIDATES-1],
    output reg [10:0] box_y0[0:CANDIDATES-1],
    output reg [10:0] box_y1[0:CANDIDATES-1]
);
    localparam integer ROI=IMG_WIDTH/2, DS=1<<DS_LOG2, N=GW*GH;
    localparam integer REC=4+17+2*GX+2*GY;
    typedef struct packed {
        logic [3:0] rank;
        logic [16:0] count;
        logic [GX-1:0] x0,x1;
        logic [GY-1:0] y0,y1;
    } record_t;
    reg map0[0:N-1],map1[0:N-1];
    reg [GW-1:0] column_or;
    reg capture_bank,process_bank;
    reg [AB:0] capture_count;
    wire take=pixel_valid && x>=ROI && x<IMG_WIDTH && y<IMG_HEIGHT;
    wire [10:0] local_x=x-ROI;
    wire [GX-1:0] block_x=local_x>>DS_LOG2;
    wire emit_cell=take && ((local_x&(DS-1))==DS-1 || x==IMG_WIDTH-1) &&
                         ((y&(DS-1))==DS-1 || y==IMG_HEIGHT-1);
    wire start=frame_start && capture_count==N && !busy;
    always @(posedge clk) if(rst_n && emit_cell && capture_count<N) begin
        if(capture_bank) map1[capture_count[AB-1:0]]<=column_or[block_x]||edge_bit;
        else map0[capture_count[AB-1:0]]<=column_or[block_x]||edge_bit;
    end
    always @(posedge clk) begin
        if(!rst_n) begin column_or<=0;capture_bank<=0;capture_count<=0;end
        else if(frame_start) begin
            column_or<=0;capture_count<=0;
            if(start) capture_bank<=!capture_bank;
        end else if(take) begin
            column_or[block_x]<=emit_cell ? 1'b0 : column_or[block_x]||edge_bit;
            if(emit_cell && capture_count<N) capture_count<=capture_count+1'b1;
        end
    end
    localparam [3:0] IDLE=0,PIX_READ=1,PIX_WAIT=2,NEIGH_ISSUE=3,NEIGH_WAIT=4,
        FIND_ISSUE=5,FIND_WAIT=6,MERGE=7,COMMIT=8,ADVANCE=9,
        ENUM_ISSUE=10,ENUM_WAIT=11,FINISH=12,FAILED=13;
    reg [3:0] state;
    reg [AB-1:0] address;
    reg [GX-1:0] gx;
    reg [GY-1:0] gy;
    reg map_q0,map_q1,foreground;
    wire map_q=process_bank?map_q1:map_q0;
    always @(posedge clk) if(state==PIX_READ) begin
        if(process_bank) map_q1<=map1[address];else map_q0<=map0[address];
    end
    reg [LB-1:0] row0[0:GW-1],row1[0:GW-1];
    reg [LB-1:0] row_q0,row_q1,left_label;
    reg [1:0] neighbor;
    wire neighbor_in_range=gy!=0 && !(neighbor==1&&gx==0) && !(neighbor==3&&gx==GW-1);
    wire [GX-1:0] neighbor_x=neighbor==1?gx-1'b1:neighbor==3?gx+1'b1:gx;
    wire [LB-1:0] neighbor_q=gy[0]?row_q0:row_q1;
    always @(posedge clk) if(state==NEIGH_ISSUE && neighbor!=0 && neighbor_in_range) begin
        if(gy[0]) row_q0<=row0[neighbor_x];else row_q1<=row1[neighbor_x];
    end
    reg [LB-1:0] parent[0:MAX_LABELS-1];
    // Plain packed-vector storage is required for Efinity block-RAM inference.
    reg [REC-1:0] records[0:MAX_LABELS-1];
    reg [LB-1:0] parent_q,lookup,selected,enum_label;
    reg [LB:0] next_label;
    record_t record_q,selected_record,merged,committed;
    reg [4:0] path_depth;
    reg [31:0] work_cycles;
    reg [16:0] candidate_score[0:CANDIDATES-1];
    reg [CANDIDATES-1:0] work_valid;
    reg [10:0] work_x0[0:CANDIDATES-1],work_x1[0:CANDIDATES-1];
    reg [10:0] work_y0[0:CANDIDATES-1],work_y1[0:CANDIDATES-1];
    wire table_read=state==FIND_ISSUE || state==ENUM_ISSUE;
    wire [LB-1:0] table_address=state==ENUM_ISSUE?enum_label:lookup;
    always @(posedge clk) if(table_read) begin
        parent_q<=parent[table_address];record_q<=records[table_address];
    end
    wire winner_selected=selected_record.rank>=record_q.rank;
    wire [LB-1:0] winner=winner_selected?selected:lookup;
    wire [LB-1:0] loser=winner_selected?lookup:selected;
    wire [LB-1:0] assigned_label=selected!=0?selected:next_label[LB-1:0];
    wire label_full=foreground && selected==0 && next_label>=MAX_LABELS;
    always @* begin
        merged=selected_record;
        merged.rank=winner_selected?selected_record.rank:record_q.rank;
        if(selected_record.rank==record_q.rank) merged.rank=selected_record.rank+1'b1;
        merged.count=selected_record.count+record_q.count;
        merged.x0=selected_record.x0<record_q.x0?selected_record.x0:record_q.x0;
        merged.x1=selected_record.x1>record_q.x1?selected_record.x1:record_q.x1;
        merged.y0=selected_record.y0<record_q.y0?selected_record.y0:record_q.y0;
        merged.y1=selected_record.y1>record_q.y1?selected_record.y1:record_q.y1;
        committed=selected_record;
        if(selected==0) begin
            committed.rank=0;committed.count=1;
            committed.x0=gx;committed.x1=gx;committed.y0=gy;committed.y1=gy;
        end else begin
            committed.count=selected_record.count+1'b1;
            if(gx<selected_record.x0) committed.x0=gx;
            if(gx>selected_record.x1) committed.x1=gx;
            if(gy<selected_record.y0) committed.y0=gy;
            if(gy>selected_record.y1) committed.y1=gy;
        end
    end
    // One explicitly multiplexed write port per table; these operations never
    // coincide. Splitting them into separate procedural writes infers FF muxes
    // in Efinity even though the state predicates are mutually exclusive.
    wire record_we=state==MERGE || (state==COMMIT&&!label_full&&foreground);
    wire [LB-1:0] record_wa=state==MERGE?winner:assigned_label;
    wire [REC-1:0] record_wd=state==MERGE?merged:committed;
    wire parent_we=state==MERGE || (state==COMMIT&&!label_full&&foreground&&selected==0);
    wire [LB-1:0] parent_wa=state==MERGE?loser:assigned_label;
    wire [LB-1:0] parent_wd=state==MERGE?winner:assigned_label;
    always @(posedge clk) begin
        if(parent_we) parent[parent_wa]<=parent_wd;
        if(record_we) records[record_wa]<=record_wd;
        if(state==COMMIT && !label_full) begin
            if(gy[0]) row1[gx]<=foreground?assigned_label:0;
            else row0[gx]<=foreground?assigned_label:0;
        end
    end
    task next_neighbor;
        begin
            if(neighbor==3) state<=COMMIT;
            else begin neighbor<=neighbor+1'b1;state<=NEIGH_ISSUE;end
        end
    endtask
    wire [11:0] component_w=(record_q.x1-record_q.x0+12'd1)<<DS_LOG2;
    wire [11:0] component_h=(record_q.y1-record_q.y0+12'd1)<<DS_LOG2;
    wire [18:0] component_perimeter=(record_q.x1-record_q.x0+19'd1)+(record_q.y1-record_q.y0+19'd1);
    wire eligible=parent_q==enum_label && record_q.count>=6 &&
        component_w>=MIN_SPAN && component_h>=MIN_SPAN &&
        component_w<=4*component_h && component_h<=4*component_w &&
        record_q.count<=4*component_perimeter &&
        record_q.x0!=0 && record_q.x1!=GW-1 && record_q.y0!=0 && record_q.y1!=GH-1;
    integer i,j,insert_at;
    always @(posedge clk) begin
        if(!rst_n) begin
            state<=IDLE;busy<=0;overflow<=0;candidate_toggle<=0;candidate_valid<=0;
            process_bank<=0;address<=0;gx<=0;gy<=0;foreground<=0;neighbor<=0;
            left_label<=0;lookup<=0;selected<=0;selected_record<='0;
            next_label<=1;enum_label<=1;path_depth<=0;work_cycles<=0;work_valid<=0;
            for(i=0;i<CANDIDATES;i=i+1) begin
                box_x0[i]<=0;box_x1[i]<=0;box_y0[i]<=0;box_y1[i]<=0;
                work_x0[i]<=0;work_x1[i]<=0;work_y0[i]<=0;work_y1[i]<=0;candidate_score[i]<=0;
            end
        end else if(start) begin
            process_bank<=capture_bank;busy<=1;overflow<=0;state<=PIX_READ;
            address<=0;gx<=0;gy<=0;left_label<=0;next_label<=1;work_cycles<=0;work_valid<=0;
            for(i=0;i<CANDIDATES;i=i+1) candidate_score[i]<=0;
        end else begin
            if(busy) work_cycles<=work_cycles+1'b1;
            case(state)
                PIX_READ: state<=PIX_WAIT;
                PIX_WAIT: begin
                    foreground<=map_q;selected<=0;selected_record<='0;neighbor<=0;
                    state<=map_q?NEIGH_ISSUE:COMMIT;
                end
                NEIGH_ISSUE: begin
                    path_depth<=0;
                    if(neighbor==0) begin
                        if(left_label==0) next_neighbor();
                        else begin lookup<=left_label;state<=FIND_ISSUE;end
                    end else if(!neighbor_in_range) next_neighbor();
                    else state<=NEIGH_WAIT;
                end
                NEIGH_WAIT: begin
                    if(neighbor_q==0) next_neighbor();
                    else begin lookup<=neighbor_q;state<=FIND_ISSUE;end
                end
                FIND_ISSUE: state<=FIND_WAIT;
                FIND_WAIT: begin
                    if(parent_q!=lookup) begin
                        if(path_depth>=15) state<=FAILED;
                        else begin lookup<=parent_q;path_depth<=path_depth+1'b1;state<=FIND_ISSUE;end
                    end else if(selected==0) begin selected<=lookup;selected_record<=record_q;next_neighbor();end
                    else if(lookup==selected) next_neighbor();
                    else state<=MERGE;
                end
                MERGE: begin selected<=winner;selected_record<=merged;next_neighbor();end
                COMMIT: begin
                    if(label_full) state<=FAILED;
                    else begin
                        left_label<=foreground?assigned_label:0;
                        if(foreground&&selected==0) next_label<=next_label+1'b1;
                        state<=ADVANCE;
                    end
                end
                ADVANCE: begin
                    address<=address+1'b1;
                    if(gx==GW-1) begin
                        gx<=0;left_label<=0;
                        if(gy==GH-1) begin enum_label<=1;state<=ENUM_ISSUE;end
                        else begin gy<=gy+1'b1;state<=PIX_READ;end
                    end else begin gx<=gx+1'b1;state<=PIX_READ;end
                end
                ENUM_ISSUE: begin
                    if(enum_label>=next_label) state<=FINISH;else state<=ENUM_WAIT;
                end
                ENUM_WAIT: begin
                    insert_at=CANDIDATES;
                    for(i=0;i<CANDIDATES;i=i+1)
                        if(insert_at==CANDIDATES && eligible && (!work_valid[i]||record_q.count>candidate_score[i])) insert_at=i;
                    for(i=0;i<CANDIDATES;i=i+1) begin
                        if(i==insert_at) begin
                            work_valid[i]<=1;candidate_score[i]<=record_q.count;
                            work_x0[i]<=ROI+(record_q.x0<<DS_LOG2);
                            work_x1[i]<=ROI+((record_q.x1+12'd1)<<DS_LOG2)-1'b1;
                            work_y0[i]<=record_q.y0<<DS_LOG2;
                            work_y1[i]<=((record_q.y1+12'd1)<<DS_LOG2)-1'b1;
                        end else if(i>insert_at) begin
                            work_valid[i]<=work_valid[i-1];candidate_score[i]<=candidate_score[i-1];
                            work_x0[i]<=work_x0[i-1];work_x1[i]<=work_x1[i-1];
                            work_y0[i]<=work_y0[i-1];work_y1[i]<=work_y1[i-1];
                        end
                    end
                    if(enum_label==next_label-1) state<=FINISH;
                    else begin enum_label<=enum_label+1'b1;state<=ENUM_ISSUE;end
                end
                FINISH: begin
                    candidate_valid<=work_valid;
                    for(i=0;i<CANDIDATES;i=i+1) begin
                        box_x0[i]<=work_x0[i];box_x1[i]<=work_x1[i];box_y0[i]<=work_y0[i];box_y1[i]<=work_y1[i];
                    end
                    candidate_toggle<=!candidate_toggle;busy<=0;state<=IDLE;
                end
                FAILED: begin
                    candidate_valid<=0;candidate_toggle<=!candidate_toggle;busy<=0;overflow<=1;state<=IDLE;
                end
                default: state<=IDLE;
            endcase
            if(busy && work_cycles>=MAX_ANALYSIS_CYCLES && state!=FAILED) state<=FAILED;
        end
    end
endmodule

