`timescale 1ns/1ps

module tb();

  parameter DEPTH = 16;
  parameter PTR_WIDTH = $clog2(DEPTH);
  parameter DATA_WIDTH = 8;

  reg wr_clk_i, rd_clk_i, rst_i;
  reg wr_en_i, rd_en_i;
  reg [DATA_WIDTH-1:0] wdata_i;

  wire full_o, overflow_o, empty_o, underflow_o;
  wire [DATA_WIDTH-1:0] rdata_o;

  integer i, j, k, wr_dly, rd_dly;
  string testname = "test_full";

  async_fifo #(
    .DEPTH(DEPTH),
    .PTR_WIDTH(PTR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH)
  ) dut(.*);

  // write clock
  initial begin
    wr_clk_i = 0;
    forever #5 wr_clk_i = ~wr_clk_i;
  end

  // read clock
  initial begin
    rd_clk_i = 0;
    forever #7 rd_clk_i = ~rd_clk_i;
  end

  task rst;
    begin
      rst_i = 1;
      wr_en_i = 0;
      rd_en_i = 0;
      wdata_i = 0;

      @(negedge wr_clk_i);
      rst_i = 0;

      $display("reset done: full=%b empty=%b", full_o, empty_o);
    end
  endtask

  task write_mem;
    input integer num_writes;
    begin
      for (i = 0; i < num_writes; i = i + 1) begin
        @(negedge wr_clk_i);
        wr_en_i = 1;
        wdata_i = $random;

        @(posedge wr_clk_i);
        #1;
        $display("write: data=%h full=%b overflow=%b",
                 wdata_i, full_o, overflow_o);
      end

      @(negedge wr_clk_i);
      wr_en_i = 0;
      wdata_i = 0;
    end
  endtask

  task read_mem;
    input integer num_reads;
    begin
      @(negedge rd_clk_i);
      rd_en_i = 1;

      repeat (num_reads) begin
        @(posedge rd_clk_i);
        #1;
        $display("read:  data=%h empty=%b underflow=%b",
                 rdata_o, empty_o, underflow_o);
      end

      @(negedge rd_clk_i);
      rd_en_i = 0;
    end
  endtask

  initial begin
    $display("running %s", testname);
    rst;

    case (testname)
      "test_full": begin
        write_mem(DEPTH);
        read_mem(DEPTH);
      end

      "test_empty": begin
        write_mem(10);
        read_mem(10);
      end

      "test_overflow": begin
        write_mem(DEPTH + 1);
        read_mem(DEPTH + 1);
      end

      "test_underflow": begin
        write_mem(DEPTH - 1);
        read_mem(DEPTH - 1);
      end

      "test_concurrent_wr_rd": begin
        fork
          begin
            for (j = 0; j < 10; j = j + 1) begin
              write_mem(1);
              wr_dly = $urandom_range(1, 10);
              repeat (wr_dly) @(posedge wr_clk_i);
            end
          end

          begin
            for (k = 0; k < 10; k = k + 1) begin
              read_mem(1);
              rd_dly = $urandom_range(1, 10);
              repeat (rd_dly) @(posedge rd_clk_i);
            end
          end
        join
      end

      default: $display("wrong testname");
    endcase

    #100;
    $display("simulation done: full=%b empty=%b", full_o, empty_o);
    $finish;
  end

endmodule
