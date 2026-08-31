`timescale 1ns/1ps

module tb_c2_csr_cmd_bridge;
  localparam int PAGE_W = 1;
  logic clk = 1'b0;
  always #5 clk = ~clk;
  logic rst_n = 1'b0;
  logic csr_valid, csr_write;
  logic [11:0] csr_addr;
  logic [31:0] csr_wdata, csr_rdata;
  logic csr_ready;
  logic cmd_valid, cmd_ready;
  logic [255:0] cmd_data;
  logic page_req_valid, page_req_ready;
  logic page_req_page;
  logic [15:0] cmd_fifo_level;
  logic parser_busy, engine_busy, display_busy, display_underflow, mem_error;
  logic page_flip_pending, active_page, pending_page;
  logic [31:0] accepted_count, completed_count, parser_memory_error_count;
  logic [31:0] dropped_count, engine_request_count, engine_pixel_count;
  logic [31:0] display_pixel_count, display_error_count;
  logic [31:0] mem_read_count, mem_write_count, mem_response_count;
  logic parser_error_valid;
  logic [3:0] parser_error_code;
  logic [31:0] parser_error_seq;
  logic [31:0] submit_count, page_submit_count;
  logic [31:0] status_word;
  integer cmd_seen, page_seen;
  logic [255:0] cmd_seen_data;

  c2_csr_cmd_bridge #(.PAGE_W(PAGE_W)) dut (
    .clk, .rst_n, .csr_valid, .csr_write, .csr_addr, .csr_wdata,
    .csr_rdata, .csr_ready, .cmd_valid, .cmd_ready, .cmd_data,
    .page_req_valid, .page_req_ready, .page_req_page,
    .cmd_fifo_full(1'b0), .cmd_fifo_level, .parser_busy, .engine_busy,
    .display_busy, .display_underflow, .mem_error, .page_flip_pending,
    .active_page, .pending_page, .accepted_count, .completed_count,
    .parser_memory_error_count, .dropped_count, .engine_request_count,
    .engine_pixel_count, .display_pixel_count, .display_error_count,
    .mem_read_count, .mem_write_count, .mem_response_count,
    .parser_error_valid, .parser_error_code, .parser_error_seq,
    .submit_count, .page_submit_count
  );

  always @(posedge clk) begin
    if (rst_n && cmd_valid && cmd_ready) begin
      cmd_seen = cmd_seen + 1;
      cmd_seen_data = cmd_data;
    end
    if (rst_n && page_req_valid && page_req_ready)
      page_seen = page_seen + 1;
  end

  task automatic csr_write_word(input logic [11:0] addr,
                                input logic [31:0] data);
    begin
      @(negedge clk);
      csr_addr = addr; csr_wdata = data; csr_write = 1'b1; csr_valid = 1'b1;
      while (!csr_ready)
        @(negedge clk);
      @(posedge clk);
      @(negedge clk);
      csr_valid = 1'b0; csr_write = 1'b0;
    end
  endtask

  task automatic csr_read_word(input logic [11:0] addr,
                               output logic [31:0] data);
    begin
      @(negedge clk);
      csr_addr = addr; csr_wdata = '0; csr_write = 1'b0; csr_valid = 1'b1;
      while (!csr_ready)
        @(negedge clk);
      #1 data = csr_rdata;
      @(posedge clk);
      @(negedge clk);
      csr_valid = 1'b0;
    end
  endtask

  initial begin
    csr_valid = 1'b0; csr_write = 1'b0; csr_addr = '0; csr_wdata = '0;
    cmd_ready = 1'b0; page_req_ready = 1'b0;
    cmd_seen = 0; page_seen = 0; cmd_seen_data = '0;
    parser_busy = 1'b1; engine_busy = 1'b0; display_busy = 1'b0;
    display_underflow = 1'b0; mem_error = 1'b0; page_flip_pending = 1'b1;
    active_page = 1'b0; pending_page = 1'b1;
    accepted_count = 32'd7; completed_count = 32'd5;
    parser_memory_error_count = 32'd2; dropped_count = 32'd1;
    engine_request_count = 32'd11; engine_pixel_count = 32'd9;
    display_pixel_count = 32'd13; display_error_count = 32'd3;
    mem_read_count = 32'd17; mem_write_count = 32'd19; mem_response_count = 32'd23;
    parser_error_valid = 1'b1; parser_error_code = 4'hA; parser_error_seq = 32'h55;

    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    for (integer k = 0; k < 8; k = k + 1)
      csr_write_word(12'h000 + k*4, 32'hA000_0000 + k);
    csr_write_word(12'h020, 32'h1);
    repeat (3) @(posedge clk);
    if (cmd_seen != 0 || !cmd_valid)
      $fatal(1, "submit pending was not held");
    cmd_ready = 1'b1;
    repeat (2) @(posedge clk);
    if (cmd_seen != 1 || cmd_seen_data !== {
        32'hA000_0007,32'hA000_0006,32'hA000_0005,32'hA000_0004,
        32'hA000_0003,32'hA000_0002,32'hA000_0001,32'hA000_0000})
      $fatal(1, "command assembly mismatch seen=%0d data=%h", cmd_seen,
             cmd_seen_data);

    csr_write_word(12'h028, 32'd1);
    if (!page_req_valid || page_seen != 0)
      $fatal(1, "page request was not queued");
    page_req_ready = 1'b1;
    repeat (2) @(posedge clk);
    if (page_seen != 1)
      $fatal(1, "page request was not consumed");

    csr_read_word(12'h024, status_word);
    if (!status_word[1] || !status_word[6] || status_word[0])
      $fatal(1, "status read mismatch %h", status_word);
    if (submit_count != 1 || page_submit_count != 1)
      $fatal(1, "bridge counters submit=%0d page=%0d", submit_count,
             page_submit_count);

    $display("TB_C2_CSR_CMD_BRIDGE_PASS cmd=%0d page=%0d", cmd_seen, page_seen);
    $finish;
  end
endmodule
