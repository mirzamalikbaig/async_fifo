`ifndef FIFO_ASSERTIONS_SV
`define FIFO_ASSERTIONS_SV
`timescale 1ns/1ps

// Simulation checker. A synchronized destination pointer can skip Gray codes;
// the one-bit-transition property applies ONLY to each source-domain pointer.
module fifo_assertions #(
  parameter int unsigned PTR_WIDTH = 4,
  parameter int unsigned DATA_WIDTH = 8
) (
  input logic wr_clk, rd_clk, wr_reset, rd_reset,
  input logic wr_en, rd_en, full, empty, overflow, underflow,
  input logic [PTR_WIDTH:0] wr_bin, rd_bin, wr_gray, rd_gray,
  input logic [PTR_WIDTH:0] rd_gray_wsync1, rd_gray_wsync2,
  input logic [PTR_WIDTH:0] wr_gray_rsync1, wr_gray_rsync2,
  input logic [DATA_WIDTH-1:0] rdata
);
  bit wr_past_valid, rd_past_valid;
  always @(posedge wr_clk or posedge wr_reset)
    if (wr_reset) wr_past_valid <= 0;
    else          wr_past_valid <= 1;
  always @(posedge rd_clk or posedge rd_reset)
    if (rd_reset) rd_past_valid <= 0;
    else          rd_past_valid <= 1;

  a_wr_gray_step: assert property (@(posedge wr_clk)
    disable iff (wr_reset || !wr_past_valid)
    $onehot0(wr_gray ^ $past(wr_gray)))
    else $fatal(1, "Write Gray pointer changed multiple bits");
  a_rd_gray_step: assert property (@(posedge rd_clk)
    disable iff (rd_reset || !rd_past_valid)
    $onehot0(rd_gray ^ $past(rd_gray)))
    else $fatal(1, "Read Gray pointer changed multiple bits");

  a_wr_gray_encoding: assert property (@(posedge wr_clk) disable iff (wr_reset)
    wr_gray == ((wr_bin >> 1) ^ wr_bin))
    else $fatal(1, "Write binary/Gray encoding mismatch");
  a_rd_gray_encoding: assert property (@(posedge rd_clk) disable iff (rd_reset)
    rd_gray == ((rd_bin >> 1) ^ rd_bin))
    else $fatal(1, "Read binary/Gray encoding mismatch");

  a_write_advance: assert property (@(posedge wr_clk) disable iff (wr_reset)
    (wr_en && !full) |=> wr_bin == ($past(wr_bin) + {{PTR_WIDTH{1'b0}}, 1'b1}))
    else $fatal(1, "Accepted write did not advance pointer by one");
  a_write_hold: assert property (@(posedge wr_clk) disable iff (wr_reset)
    (!wr_en || full) |=> $stable(wr_bin))
    else $fatal(1, "Write pointer moved without an accepted write");
  a_read_advance: assert property (@(posedge rd_clk) disable iff (rd_reset)
    (rd_en && !empty) |=> rd_bin == ($past(rd_bin) + {{PTR_WIDTH{1'b0}}, 1'b1}))
    else $fatal(1, "Accepted read did not advance pointer by one");
  a_read_hold: assert property (@(posedge rd_clk) disable iff (rd_reset)
    (!rd_en || empty) |=> $stable(rd_bin))
    else $fatal(1, "Read pointer moved without an accepted read");

  a_overflow_pulse: assert property (@(posedge wr_clk)
    disable iff (wr_reset || !wr_past_valid)
    overflow == $past(wr_en && full))
    else $fatal(1, "Overflow does not match the rejected write");
  a_underflow_pulse: assert property (@(posedge rd_clk)
    disable iff (rd_reset || !rd_past_valid)
    underflow == $past(rd_en && empty))
    else $fatal(1, "Underflow does not match the rejected read");
  a_read_data_hold: assert property (@(posedge rd_clk) disable iff (rd_reset)
    (!rd_en || empty) |=> $stable(rdata))
    else $fatal(1, "Read output changed without an accepted read");

  a_r2w_stage2: assert property (@(posedge wr_clk)
    disable iff (wr_reset || !wr_past_valid)
    rd_gray_wsync2 == $past(rd_gray_wsync1))
    else $fatal(1, "Read-pointer synchronizer stage 2 mismatch");
  a_w2r_stage2: assert property (@(posedge rd_clk)
    disable iff (rd_reset || !rd_past_valid)
    wr_gray_rsync2 == $past(wr_gray_rsync1))
    else $fatal(1, "Write-pointer synchronizer stage 2 mismatch");
endmodule
`endif
