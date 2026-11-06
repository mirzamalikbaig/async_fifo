`timescale 1ns/1ps
`include "fifo_assertions.sv"

module tb;
  parameter DEPTH = 16;
  parameter DATA_WIDTH = 8;
  localparam PTR_WIDTH = $clog2(DEPTH);

  logic wr_clk_i = 0;
  logic rd_clk_i = 0;
  logic rst_i = 1;
  logic wr_en_i = 0;
  logic rd_en_i = 0;
  logic [DATA_WIDTH-1:0] wdata_i = 0;
  logic [DATA_WIDTH-1:0] next_data = 0;
  wire [DATA_WIDTH-1:0] rdata_o;
  wire full_o, empty_o, overflow_o, underflow_o;

  async_fifo #(
    .DEPTH(DEPTH), .PTR_WIDTH(PTR_WIDTH), .DATA_WIDTH(DATA_WIDTH)
  ) dut (.*);

  // Write clock: 10 ns period. Read clock: 14 ns period.
  always #5 wr_clk_i = ~wr_clk_i;
  always #7 rd_clk_i = ~rd_clk_i;

  fifo_assertions #(.PTR_WIDTH(PTR_WIDTH)) checks (
    .wr_clk(wr_clk_i), .rd_clk(rd_clk_i),
    .wr_reset(dut.wr_reset), .rd_reset(dut.rd_reset),
    .wr_en(wr_en_i), .rd_en(rd_en_i),
    .full(full_o), .empty(empty_o),
    .overflow(overflow_o), .underflow(underflow_o),
    .wr_bin(dut.wr_bin), .rd_bin(dut.rd_bin),
    .wr_gray(dut.wr_gray), .rd_gray(dut.rd_gray)
  );

  // Simple scoreboard: remember accepted writes in an ordinary array.
  // write_count points to the next place to store expected data.
  // read_count points to the next expected value to compare.
  // Each monitor owns its own counter, so no queue or semaphore is needed.
  logic [DATA_WIDTH-1:0] expected_data [0:4095];
  integer write_count = 0;
  integer read_count = 0;
  integer overflow_count = 0;
  integer underflow_count = 0;
  logic [DATA_WIDTH-1:0] last_read_data = 0;
  string testname = "all";

  always @(posedge wr_clk_i) begin : write_monitor
    logic expected_overflow;
    if (!rst_i && !dut.wr_reset) begin
      expected_overflow = wr_en_i && full_o;
      if (wr_en_i && !full_o) begin
        if (write_count >= 4096)
          $fatal(1, "Scoreboard array is full; increase its size for longer tests");
        if (write_count - read_count >= DEPTH)
          $fatal(1, "DUT accepted a write when the stored data already filled the FIFO");
        expected_data[write_count] = wdata_i;
        write_count = write_count + 1;
      end
      if (expected_overflow) overflow_count = overflow_count + 1;
      #1ps; // Let the DUT's nonblocking assignments update its outputs.
      if (!rst_i && !dut.wr_reset && overflow_o !== expected_overflow)
        $fatal(1, "Wrong overflow output");
    end
  end

  always @(posedge rd_clk_i) begin : read_monitor
    logic [DATA_WIDTH-1:0] expected_value;
    logic expected_underflow;
    if (rst_i || dut.rd_reset) begin
      last_read_data = 0;
    end else begin
      expected_value = last_read_data;
      expected_underflow = rd_en_i && empty_o;
      if (rd_en_i && !empty_o) begin
        if (read_count >= write_count)
          $fatal(1, "DUT accepted a read with no stored data");
        expected_value = expected_data[read_count];
        read_count = read_count + 1;
      end
      if (expected_underflow) underflow_count = underflow_count + 1;
      #1ps;
      if (rst_i || dut.rd_reset) begin
        last_read_data = 0;
      end else begin
        if (rdata_o !== expected_value)
          $fatal(1, "Data mismatch: expected=%h actual=%h", expected_value, rdata_o);
        if (underflow_o !== expected_underflow)
          $fatal(1, "Wrong underflow output");
        last_read_data = expected_value;
      end
    end
  end

  task reset_fifo;
    wr_en_i = 0;
    rd_en_i = 0;
    rst_i = 1;
    // Drivers are idle during reset. Discard the old expected data by
    // restarting both counters; clearing the whole array is unnecessary.
    write_count = 0;
    read_count = 0;
    overflow_count = 0;
    underflow_count = 0;
    repeat (4) @(negedge wr_clk_i);
    repeat (4) @(negedge rd_clk_i);
    #1;
    rst_i = 0;
    repeat (4) @(negedge wr_clk_i);
    repeat (4) @(negedge rd_clk_i);
    if (full_o !== 0 || empty_o !== 1 || rdata_o !== 0 ||
        overflow_o !== 0 || underflow_o !== 0)
      $fatal(1, "Wrong outputs after reset");
  endtask

  task write_many(input integer count);
    repeat (count) begin
      @(negedge wr_clk_i);
      wr_en_i = 1;
      wdata_i = next_data;
      next_data = next_data + 1'b1; // Use a new value for the next request.
    end
    @(negedge wr_clk_i);
    wr_en_i = 0;
  endtask

  task read_many(input integer count);
    repeat (count) begin
      @(negedge rd_clk_i);
      rd_en_i = 1;
    end
    @(negedge rd_clk_i);
    rd_en_i = 0;
  endtask

  // Keep requesting reads until the scoreboard has no remaining data.
  // The DUT may initially be empty while the write pointer synchronizes.
  task drain_fifo;
    @(negedge rd_clk_i);
    while (read_count < write_count) begin
      rd_en_i = !empty_o;
      @(negedge rd_clk_i);
    end
    rd_en_i = 0;
    repeat (4) @(negedge rd_clk_i);
    repeat (4) @(negedge wr_clk_i);
    if (empty_o !== 1 || full_o !== 0 || write_count != read_count)
      $fatal(1, "FIFO did not drain correctly");
    if (overflow_o !== 0 || underflow_o !== 0)
      $fatal(1, "Error outputs did not clear while idle");
  endtask

  task run_test(input string name);
    $display("RUN %s", name);
    reset_fifo();
    case (name)
      "test_full": begin
        write_many(DEPTH);
        if (full_o !== 1 || write_count != DEPTH)
          $fatal(1, "Full flag or capacity is wrong");
      end
      "test_empty": begin
        write_many(1);
      end
      "test_overflow": begin
        write_many(DEPTH + 2);
        if (overflow_count != 2 || write_count != DEPTH || full_o !== 1)
          $fatal(1, "Expected exactly two rejected writes");
      end
      "test_underflow": begin
        read_many(2);
        if (underflow_count != 2 || read_count != 0)
          $fatal(1, "Expected exactly two rejected reads");
        write_many(1); // A valid transfer must still work afterward.
      end
      "test_wrap": begin
        repeat (4) begin
          write_many(DEPTH);
          if (full_o !== 1) $fatal(1, "Missing full flag during wrap test");
          drain_fifo();
        end
        if (write_count != 4 * DEPTH)
          $fatal(1, "Wrap test did not transfer all four batches");
      end
      "test_concurrent_wr_rd": begin
        // Two ordinary tasks run at the same time on different clocks.
        // Some requests may be blocked; the monitors check those too.
        fork
          write_many(4 * DEPTH);
          read_many(4 * DEPTH);
        join
      end
      "test_reset": begin
        write_many(DEPTH / 2);
        if (write_count != DEPTH / 2)
          $fatal(1, "Reset test did not place data in the FIFO");
        reset_fifo(); // Throw away pending data, then start again.
        write_many(DEPTH);
      end
      default: $fatal(1, "Unknown test name: %s", name);
    endcase
    drain_fifo();
    $display("PASS %s: writes=%0d reads=%0d rejected_writes=%0d rejected_reads=%0d",
             name, write_count, read_count, overflow_count, underflow_count);
  endtask

  initial begin
    if (!$value$plusargs("TEST=%s", testname)) testname = "all";
    if (testname == "all") begin
      run_test("test_full");
      run_test("test_empty");
      run_test("test_overflow");
      run_test("test_underflow");
      run_test("test_wrap");
      run_test("test_concurrent_wr_rd");
      run_test("test_reset");
    end else begin
      run_test(testname);
    end
    $display("SIMULATION PASS");
    $finish;
  end

  // A broken flag must not leave a test waiting forever.
  initial begin
    #100000;
    $fatal(1, "Timeout: a test did not finish");
  end
endmodule
