`timescale 1ns/1ps
`include "fifo_assertions.sv"

module tb #(
  parameter int unsigned DEPTH = 16,
  parameter int unsigned PTR_WIDTH = $clog2(DEPTH),
  parameter int unsigned DATA_WIDTH = 8,
  parameter int unsigned WR_HALF_NS = 5,
  parameter int unsigned RD_HALF_NS = 7,
  parameter int unsigned RD_PHASE_NS = 0
);
  typedef logic [DATA_WIDTH-1:0] data_t;
  logic wr_clk_i = 0, rd_clk_i = 0, rst_i = 1;
  logic wr_en_i = 0, rd_en_i = 0;
  data_t wdata_i = '0;
  wire full_o, overflow_o, empty_o, underflow_o;
  wire [DATA_WIDTH-1:0] rdata_o;

  async_fifo #(.DEPTH(DEPTH), .PTR_WIDTH(PTR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) dut (.*);
  fifo_assertions #(.PTR_WIDTH(PTR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) checks (
    .wr_clk(wr_clk_i), .rd_clk(rd_clk_i),
    .wr_reset(dut.wr_reset), .rd_reset(dut.rd_reset),
    .wr_en(wr_en_i), .rd_en(rd_en_i), .full(full_o), .empty(empty_o),
    .overflow(overflow_o), .underflow(underflow_o),
    .wr_bin(dut.wr_bin), .rd_bin(dut.rd_bin),
    .wr_gray(dut.wr_gray), .rd_gray(dut.rd_gray),
    .rd_gray_wsync1(dut.rd_gray_wsync1), .rd_gray_wsync2(dut.rd_gray_wsync2),
    .wr_gray_rsync1(dut.wr_gray_rsync1), .wr_gray_rsync2(dut.wr_gray_rsync2),
    .rdata(rdata_o)
  );

  initial forever #(WR_HALF_NS * 1ns) wr_clk_i = ~wr_clk_i;
  generate
    if (RD_PHASE_NS == 0) begin : no_read_phase
      initial forever #(RD_HALF_NS * 1ns) rd_clk_i = ~rd_clk_i;
    end else begin : shifted_read_clock
      initial begin
        #(RD_PHASE_NS * 1ns);
        forever #(RD_HALF_NS * 1ns) rd_clk_i = ~rd_clk_i;
      end
    end
  endgenerate

  // Reference contents depend only on observed accepted transfers, not DUT
  // pointers or memory. The lock serializes queue operations at coincident
  // edges. Valid simultaneous push/pop commute away from empty/full boundaries.
  data_t expected[$];
  semaphore queue_lock = new(1);
  data_t held_rdata = '0;
  int unsigned writes = 0, reads = 0, discarded = 0;
  int unsigned overflows = 0, underflows = 0, resets = 0;
  int unsigned write_wraps = 0, read_wraps = 0;
  int unsigned wr_position = 0, rd_position = 0;
  int unsigned wr_rng, rd_rng, seed = 1;
  string testname = "all";

  // Sample acceptance before the NBA region, check registered outputs after it.
  always @(posedge wr_clk_i) begin : score_write
    bit rejected;
    if (!rst_i && !dut.wr_reset) begin
      rejected = wr_en_i && full_o;
      if (wr_en_i && !full_o) begin
        queue_lock.get(1);
        if (expected.size() >= DEPTH)
          $fatal(1, "Scoreboard: accepted write into physically full FIFO");
        expected.push_back(wdata_i);
        writes++;
        wr_position++;
        if (wr_position == DEPTH) begin
          wr_position = 0;
          write_wraps++;
        end
        queue_lock.put(1);
      end
      if (rejected) overflows++;
      #1ps;
      if (overflow_o !== rejected)
        $fatal(1, "Scoreboard: incorrect overflow pulse");
    end
  end

  always @(posedge rd_clk_i) begin : score_read
    data_t wanted;
    bit rejected;
    if (rst_i || dut.rd_reset) begin
      held_rdata = '0;
    end else begin
      wanted = held_rdata;
      rejected = rd_en_i && empty_o;
      if (rd_en_i && !empty_o) begin
        queue_lock.get(1);
        if (expected.size() == 0)
          $fatal(1, "Scoreboard: accepted read from physically empty FIFO");
        wanted = expected.pop_front();
        reads++;
        rd_position++;
        if (rd_position == DEPTH) begin
          rd_position = 0;
          read_wraps++;
        end
        queue_lock.put(1);
      end
      if (rejected) underflows++;
      #1ps;
      if (rdata_o !== wanted)
        $fatal(1, "Scoreboard: data mismatch expected=%h actual=%h", wanted, rdata_o);
      if (underflow_o !== rejected)
        $fatal(1, "Scoreboard: incorrect underflow pulse");
      held_rdata = wanted;
    end
  end

  // Separate PRNG streams make stimulus reproducible even when clock events
  // coincide. Zero seeds are remapped to avoid the xorshift all-zero state.
  function automatic int unsigned next_random(input int unsigned state);
    int unsigned value;
    value = state;
    value ^= value << 13;
    value ^= value >> 17;
    value ^= value << 5;
    return value;
  endfunction

  task automatic reset_fifo;
    wr_en_i = 0;
    rd_en_i = 0;
    rst_i = 1;
    queue_lock.get(1);
    discarded += expected.size();
    expected.delete();
    wr_position = 0;
    rd_position = 0;
    queue_lock.put(1);
    resets++;
    repeat (4) @(negedge wr_clk_i);
    repeat (4) @(negedge rd_clk_i);
    // Deliberately release off-edge; each domain synchronizes release itself.
    #1ns;
    rst_i = 0;
    repeat (4) @(negedge wr_clk_i);
    repeat (4) @(negedge rd_clk_i);
    if (full_o !== 0 || empty_o !== 1 || rdata_o !== '0 ||
        overflow_o !== 0 || underflow_o !== 0)
      $fatal(1, "Incorrect reset outputs");
  endtask

  task automatic write_burst(input int unsigned count);
    repeat (count) begin
      @(negedge wr_clk_i);
      wr_rng = next_random(wr_rng);
      wr_en_i = 1;
      wdata_i = data_t'(wr_rng);
    end
    @(negedge wr_clk_i);
    wr_en_i = 0;
  endtask

  task automatic read_burst(input int unsigned count);
    repeat (count) begin
      @(negedge rd_clk_i);
      rd_en_i = 1;
    end
    @(negedge rd_clk_i);
    rd_en_i = 0;
  endtask

  task automatic wait_readable;
    int unsigned cycles;
    cycles = 0;
    while (empty_o) begin
      @(negedge rd_clk_i);
      cycles++;
      if (cycles > 8) $fatal(1, "Written data never became readable");
    end
  endtask

  task automatic drain;
    int unsigned cycles;
    cycles = 0;
    @(negedge rd_clk_i);
    rd_en_i = 1;
    while (expected.size() != 0) begin
      @(negedge rd_clk_i);
      cycles++;
      if (cycles > 8 * DEPTH + 32) $fatal(1, "Drain timeout");
    end
    rd_en_i = 0;
    repeat (4) @(negedge rd_clk_i);
    repeat (4) @(negedge wr_clk_i);
    if (empty_o !== 1 || full_o !== 0)
      $fatal(1, "Incorrect flags after drain");
    if (overflow_o !== 0 || underflow_o !== 0)
      $fatal(1, "Error pulses did not clear during idle");
  endtask

  task automatic test_full;
    $display("SCENARIO full_and_drain");
    reset_fifo();
    write_burst(DEPTH);
    if (full_o !== 1 || expected.size() != DEPTH)
      $fatal(1, "FIFO did not accept exactly DEPTH writes before full");
    drain();
  endtask

  task automatic test_empty;
    $display("SCENARIO empty_and_single_entry");
    reset_fifo();
    write_burst(1);
    wait_readable();
    read_burst(1);
    if (empty_o !== 1 || expected.size() != 0)
      $fatal(1, "FIFO did not become empty after the only read");
    drain();
  endtask

  task automatic test_overflow;
    int unsigned before_errors;
    $display("SCENARIO overflow");
    reset_fifo();
    before_errors = overflows;
    write_burst(DEPTH + 4);
    if (overflows - before_errors != 4 || expected.size() != DEPTH)
      $fatal(1, "Expected four rejected writes without overwriting stored data");
    drain();
  endtask

  task automatic test_underflow;
    int unsigned before_errors;
    $display("SCENARIO underflow");
    reset_fifo();
    before_errors = underflows;
    read_burst(4);
    write_burst(1);
    wait_readable();
    read_burst(1);
    read_burst(3);
    if (underflows - before_errors != 7 || expected.size() != 0)
      $fatal(1, "Expected seven rejected reads without changing read data");
    drain();
  endtask

  task automatic test_wrap;
    $display("SCENARIO repeated_wraparound");
    reset_fifo();
    repeat (10) begin
      write_burst(DEPTH);
      if (full_o !== 1) $fatal(1, "Missing full during wraparound test");
      drain();
    end
  endtask

  task automatic test_concurrent_wr_rd;
    $display("SCENARIO concurrent_random_traffic");
    reset_fifo();
    fork
      begin
        repeat (1500) begin
          @(negedge wr_clk_i);
          wr_rng = next_random(wr_rng);
          wr_en_i = (wr_rng[1:0] != 0);
          wdata_i = data_t'(wr_rng);
        end
        @(negedge wr_clk_i);
        wr_en_i = 0;
      end
      begin
        repeat (1500) begin
          @(negedge rd_clk_i);
          rd_rng = next_random(rd_rng);
          rd_en_i = (rd_rng[1:0] != 0);
        end
        @(negedge rd_clk_i);
        rd_en_i = 0;
      end
    join
    drain();
  endtask

  task automatic test_reset;
    int unsigned before_discarded;
    $display("SCENARIO reset_with_pending_data");
    reset_fifo();
    write_burst(DEPTH / 2);
    before_discarded = discarded;
    reset_fifo();
    if (discarded - before_discarded != DEPTH / 2)
      $fatal(1, "Reset did not discard the queued data");
    write_burst(DEPTH);
    drain();
  endtask

  initial begin
    if (WR_HALF_NS == 0 || RD_HALF_NS == 0)
      $fatal(1, "Clock half-periods must be positive");
    void'($value$plusargs("TEST=%s", testname));
    void'($value$plusargs("SEED=%d", seed));
    wr_rng = seed == 0 ? 32'h1234abcd : seed;
    rd_rng = wr_rng ^ 32'h9e3779b9;
    if (rd_rng == 0) rd_rng = 32'h87654321;
    $display("CONFIG test=%s depth=%0d width=%0d seed=%0d wr_half_ns=%0d rd_half_ns=%0d rd_phase_ns=%0d",
             testname, DEPTH, DATA_WIDTH, seed, WR_HALF_NS, RD_HALF_NS, RD_PHASE_NS);
    case (testname)
      "all": begin
        test_full();
        test_empty();
        test_overflow();
        test_underflow();
        test_wrap();
        test_concurrent_wr_rd();
        test_reset();
      end
      "test_full": test_full();
      "test_empty": test_empty();
      "test_overflow": test_overflow();
      "test_underflow": test_underflow();
      "test_wrap": test_wrap();
      "test_concurrent_wr_rd": test_concurrent_wr_rd();
      "test_reset": test_reset();
      default: $fatal(1, "Unknown TEST=%s", testname);
    endcase
    #1ns;
    if (expected.size() != 0 || writes != reads + discarded)
      $fatal(1, "Scoreboard accounting mismatch: writes=%0d reads=%0d discarded=%0d queued=%0d",
             writes, reads, discarded, expected.size());
    if (testname == "all" &&
        (overflows == 0 || underflows == 0 || write_wraps < 10 || read_wraps < 10 || discarded == 0))
      $fatal(1, "Required boundary/reset/wrap scenarios were not exercised");
    $display("PASS test=%s depth=%0d width=%0d seed=%0d writes=%0d reads=%0d discarded=%0d overflow=%0d underflow=%0d write_wraps=%0d read_wraps=%0d resets=%0d",
             testname, DEPTH, DATA_WIDTH, seed, writes, reads, discarded,
             overflows, underflows, write_wraps, read_wraps, resets);
    $finish;
  end

  initial begin
    #10ms;
    $fatal(1, "Simulation watchdog expired");
  end
endmodule
