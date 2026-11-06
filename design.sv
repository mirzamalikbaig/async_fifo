`timescale 1ns/1ps

module async_fifo #(
  parameter int unsigned DEPTH = 16,
  parameter int unsigned PTR_WIDTH = $clog2(DEPTH),
  parameter int unsigned DATA_WIDTH = 8
) (
  input  logic                  wr_clk_i,
  input  logic                  rd_clk_i,
  input  logic                  rst_i,
  input  logic                  wr_en_i,
  input  logic [DATA_WIDTH-1:0] wdata_i,
  output logic                  full_o,
  output logic                  overflow_o,
  input  logic                  rd_en_i,
  output logic [DATA_WIDTH-1:0] rdata_o,
  output logic                  empty_o,
  output logic                  underflow_o
);

  // Binary pointers select memory addresses. The extra bit records a lap
  // around the FIFO, so a full FIFO can be distinguished from an empty one.
  // For DEPTH=16 the pointers are 5 bits and FULL_MASK is 5'b11000.
  // XOR with this mask flips the top two bits for the full comparison.
  localparam logic [PTR_WIDTH:0] FULL_MASK = {2'b11, {(PTR_WIDTH-1){1'b0}}};
  logic [PTR_WIDTH:0] wr_bin, wr_bin_next, wr_gray, wr_gray_next;
  logic [PTR_WIDTH:0] rd_bin, rd_bin_next, rd_gray, rd_gray_next;
  logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];
  logic full_next, empty_next;
  logic wr_reset, rd_reset;

  // Reset goes high immediately. After rst_i goes low, each clock shifts
  // two zeros through its reset pipe before that side starts operating.
  (* ASYNC_REG = "TRUE" *) logic [1:0] wr_reset_pipe, rd_reset_pipe;
  always_ff @(posedge wr_clk_i or posedge rst_i) begin
    if (rst_i) wr_reset_pipe <= '1;
    else       wr_reset_pipe <= {wr_reset_pipe[0], 1'b0};
  end
  always_ff @(posedge rd_clk_i or posedge rst_i) begin
    if (rst_i) rd_reset_pipe <= '1;
    else       rd_reset_pipe <= {rd_reset_pipe[0], 1'b0};
  end
  assign wr_reset = wr_reset_pipe[1];
  assign rd_reset = rd_reset_pipe[1];

  // Only registered Gray pointers cross clock domains. Never use stage 1
  // for flags or memory addresses; stage 2 is the synchronized observation.
  (* ASYNC_REG = "TRUE" *) logic [PTR_WIDTH:0] rd_gray_wsync1, rd_gray_wsync2;
  (* ASYNC_REG = "TRUE" *) logic [PTR_WIDTH:0] wr_gray_rsync1, wr_gray_rsync2;
  always_ff @(posedge wr_clk_i or posedge wr_reset) begin
    if (wr_reset) begin
      rd_gray_wsync1 <= '0;
      rd_gray_wsync2 <= '0;
    end else begin
      rd_gray_wsync1 <= rd_gray;
      rd_gray_wsync2 <= rd_gray_wsync1;
    end
  end
  always_ff @(posedge rd_clk_i or posedge rd_reset) begin
    if (rd_reset) begin
      wr_gray_rsync1 <= '0;
      wr_gray_rsync2 <= '0;
    end else begin
      wr_gray_rsync1 <= wr_gray;
      wr_gray_rsync2 <= wr_gray_rsync1;
    end
  end

  assign wr_bin_next  = (wr_en_i && !full_o) ? wr_bin + 1'b1 : wr_bin;
  assign rd_bin_next  = (rd_en_i && !empty_o) ? rd_bin + 1'b1 : rd_bin;
  // Convert the next binary values to Gray code using shift and XOR.
  assign wr_gray_next = (wr_bin_next >> 1) ^ wr_bin_next;
  assign rd_gray_next = (rd_bin_next >> 1) ^ rd_bin_next;
  // In Gray space, full requires inversion of the TOP TWO pointer bits.
  assign full_next  = (wr_gray_next == (rd_gray_wsync2 ^ FULL_MASK));
  assign empty_next = (rd_gray_next == wr_gray_rsync2);

  always_ff @(posedge wr_clk_i or posedge wr_reset) begin
    if (wr_reset) begin
      wr_bin     <= '0;
      wr_gray    <= '0;
      full_o     <= 1'b0;
      overflow_o <= 1'b0;
    end else begin
      wr_bin     <= wr_bin_next;
      wr_gray    <= wr_gray_next;
      full_o     <= full_next;
      overflow_o <= wr_en_i && full_o;
    end
  end

  // One writer and one reader; reset invalidates contents via the pointers.
  // Omitting a memory reset loop permits dual-port RAM inference.
  always_ff @(posedge wr_clk_i) begin
    if (!wr_reset && wr_en_i && !full_o)
      mem[wr_bin[PTR_WIDTH-1:0]] <= wdata_i;
  end
  always_ff @(posedge rd_clk_i or posedge rd_reset) begin
    if (rd_reset) begin
      rd_bin      <= '0;
      rd_gray     <= '0;
      empty_o     <= 1'b1;
      underflow_o <= 1'b0;
      rdata_o     <= '0;
    end else begin
      rd_bin      <= rd_bin_next;
      rd_gray     <= rd_gray_next;
      empty_o     <= empty_next;
      underflow_o <= rd_en_i && empty_o;
      if (rd_en_i && !empty_o)
        rdata_o <= mem[rd_bin[PTR_WIDTH-1:0]];
    end
  end

  // synopsys translate_off
  initial begin
    if (DEPTH < 2 || (DEPTH & (DEPTH-1)) != 0)
      $fatal(1, "DEPTH must be a power of two and at least 2");
    if (PTR_WIDTH != $clog2(DEPTH) || DATA_WIDTH < 1)
      $fatal(1, "PTR_WIDTH must equal clog2(DEPTH); DATA_WIDTH must be positive");
  end
  // synopsys translate_on
endmodule
