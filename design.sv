`timescale 1ns/1ps

module async_fifo(
  wr_clk_i, rd_clk_i, rst_i,
  wr_en_i, wdata_i, full_o, overflow_o,
  rd_en_i, rdata_o, empty_o, underflow_o
);

  parameter DEPTH = 16;
  parameter PTR_WIDTH = $clog2(DEPTH);
  parameter DATA_WIDTH = 8;

  input wr_clk_i, rd_clk_i, rst_i, wr_en_i, rd_en_i;
  input [DATA_WIDTH-1:0] wdata_i;

  output reg full_o, overflow_o, empty_o, underflow_o;
  output reg [DATA_WIDTH-1:0] rdata_o;

  reg [PTR_WIDTH-1:0] wr_ptr, rd_ptr;
  reg wr_toggle_f, rd_toggle_f;

  reg [PTR_WIDTH-1:0] wr_ptr_rd_clk, rd_ptr_wr_clk;
  reg wr_toggle_f_rd_clk, rd_toggle_f_wr_clk;

  integer i;
  reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

  // Write
  always @(posedge wr_clk_i) begin
    if (rst_i) begin
      full_o      = 1'b0;
      rdata_o     = {DATA_WIDTH{1'b0}};
      overflow_o  = 1'b0;
      empty_o     = 1'b1;
      underflow_o = 1'b0;
      wr_ptr      = '0;
      rd_ptr      = '0;
      wr_toggle_f = 1'b0;
      rd_toggle_f = 1'b0;

      for (i = 0; i < DEPTH; i = i + 1) begin
        mem[i] = '0;
      end
    end else begin
      overflow_o = 1'b0;

      if (wr_en_i) begin
        if (full_o == 1'b1) begin
          overflow_o = 1'b1;
        end else begin
          mem[wr_ptr] = wdata_i;

          if (wr_ptr == (DEPTH - 1)) begin
            wr_toggle_f = ~wr_toggle_f;
            wr_ptr = '0;
          end else begin
            wr_ptr = wr_ptr + 1'b1;
          end
        end
      end
    end
  end

  // Read
  always @(posedge rd_clk_i) begin
    if (rst_i == 0) begin
      underflow_o = 1'b0;

      if (rd_en_i) begin
        if (empty_o == 1'b1) begin
          underflow_o = 1'b1;
        end else begin
          rdata_o = mem[rd_ptr];

          if (rd_ptr == (DEPTH - 1)) begin
            rd_toggle_f = ~rd_toggle_f;
            rd_ptr = '0;
          end else begin
            rd_ptr = rd_ptr + 1'b1;
          end
        end
      end
    end
  end

  // Write pointer into read domain
  always @(posedge rd_clk_i) begin
    wr_ptr_rd_clk      <= wr_ptr;
    wr_toggle_f_rd_clk <= wr_toggle_f;
  end

  // Read pointer into write domain
  always @(posedge wr_clk_i) begin
    rd_ptr_wr_clk      <= rd_ptr;
    rd_toggle_f_wr_clk <= rd_toggle_f;
  end

  // Full condition
  always @(posedge wr_clk_i) begin
    full_o = 1'b0;

    if ((wr_ptr == rd_ptr_wr_clk) &&
        (wr_toggle_f != rd_toggle_f_wr_clk)) begin
      full_o = 1'b1;
    end
  end

  // Empty condition
  always @(*) begin
    empty_o = 1'b0;

    if ((wr_ptr_rd_clk == rd_ptr) &&
        (wr_toggle_f_rd_clk == rd_toggle_f)) begin
      empty_o = 1'b1;
    end
  end

endmodule
