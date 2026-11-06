`ifndef FIFO_ASSERTIONS_SV
`define FIFO_ASSERTIONS_SV
`timescale 1ns/1ps

module fifo_assertions #(parameter PTR_WIDTH = 4) (
  input logic wr_clk, rd_clk, wr_reset, rd_reset,
  input logic wr_en, rd_en, full, empty, overflow, underflow,
  input logic [PTR_WIDTH:0] wr_bin, rd_bin, wr_gray, rd_gray
);
  // How to read these checks:
  // @(posedge clk)       = check on a rising clock edge.
  // disable iff (reset)  = skip the check during reset.
  // A |=> B             = if A is true now, B must be true next clock.
  // $stable(pointer)    = pointer has the same value as last clock.

  // 1. A full FIFO must not advance its write pointer.
  a_full_blocks_write: assert property (
    @(posedge wr_clk) disable iff (wr_reset)
    (full && wr_en) |=> $stable(wr_bin)
  ) else $fatal(1, "Write pointer moved while full");

  // 2. An empty FIFO must not advance its read pointer.
  a_empty_blocks_read: assert property (
    @(posedge rd_clk) disable iff (rd_reset)
    (empty && rd_en) |=> $stable(rd_bin)
  ) else $fatal(1, "Read pointer moved while empty");

  // 3. A write request while full must produce an overflow indication.
  a_overflow: assert property (
    @(posedge wr_clk) disable iff (wr_reset)
    (full && wr_en) |=> overflow
  ) else $fatal(1, "Missing overflow indication");

  // 4. A read request while empty must produce an underflow indication.
  a_underflow: assert property (
    @(posedge rd_clk) disable iff (rd_reset)
    (empty && rd_en) |=> underflow
  ) else $fatal(1, "Missing underflow indication");

  // 5 and 6. Gray code = binary XOR (binary shifted right by one).
  // These two checks compare values at the current clock edge.
  a_write_gray: assert property (
    @(posedge wr_clk) disable iff (wr_reset)
    wr_gray == (wr_bin ^ (wr_bin >> 1))
  ) else $fatal(1, "Wrong write Gray code");

  a_read_gray: assert property (
    @(posedge rd_clk) disable iff (rd_reset)
    rd_gray == (rd_bin ^ (rd_bin >> 1))
  ) else $fatal(1, "Wrong read Gray code");
endmodule
`endif
