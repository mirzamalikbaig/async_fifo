# Asynchronous FIFO

I built this as a learning project with two clocks, Gray-coded pointers, two-flop synchronizers, a simple scoreboard, and six short SVA checks.

The FIFO holds **16 words of 8 bits** by default. The write clock period is **10 ns** and the read clock period is **14 ns**.

## Start here

| File | What to learn |
| --- | --- |
| `design.sv` | Memory, binary/Gray pointers, synchronizers, full and empty flags |
| `testbench.sv` | Clock generation, tasks, expected-data array, and seven tests |
| `fifo_assertions.sv` | Six short checks, with comments explaining the SVA syntax |
| `scripts/regress.py` | Compile once, then run the tests in a Python `for` loop |
| `.github/workflows/verify.yml` | Run the same regression automatically on GitHub |

A regression means running a collection of tests again after changing the code.

## How the FIFO works

1. A write is accepted on a write-clock rising edge when write enable is high and the FIFO is not full.
2. A read is accepted on a read-clock rising edge when read enable is high and the FIFO is not empty.
3. Binary pointers select memory locations. Each pointer has an extra bit to track wrapping around the memory.
4. Gray pointers represent the same positions using `gray = binary ^ (binary >> 1)`.
5. Each Gray pointer passes through two registers in the other clock domain. Full and empty use the second register.
6. Each side updates its own pointer and flag on its own clock.

The output data is registered: it changes after an accepted read edge and otherwise holds its previous value.

A write request while full is blocked and produces `overflow_o`. A read request while empty is blocked and produces `underflow_o`. These flags clear on the next local clock cycle without a rejected request. Repeated rejected requests keep the corresponding flag high.

`rst_i` is active high. Reset clears the pointers and output data, discarding pending entries. Each clock domain releases reset through two local reset registers. Both clocks must run to finish reset release.

The full/empty flags take time to reflect activity on the other clock. That delay comes from the synchronizers and registered flag logic. The testbench waits for the local flags before draining the FIFO.

Gray-code CDC is the main design concept to study here. The RTL keeps this architecture; simplifying the test code does not remove the synchronizers.

## Simple scoreboard

The scoreboard uses an ordinary array:

```systemverilog
logic [DATA_WIDTH-1:0] expected_data [0:4095];
integer write_count = 0;
integer read_count = 0;
```

On an accepted write, it stores the input value at `expected_data[write_count]` and increases `write_count`. On an accepted read, it compares the DUT's output against `expected_data[read_count]` and increases `read_count`.

Each monitor updates its own counter. The counters are reset while the drivers are idle. The scoreboard also checks that blocked reads hold the output data and that the overflow/underflow outputs are correct.

The `#1ps` delay in the monitors lets the DUT's nonblocking assignments update before comparing its registered outputs. A mismatch calls `$fatal` and stops the test. A timeout catches a test that never finishes.

The expected-data array supports up to 4096 accepted writes between resets. It is testbench storage, separate from the FIFO's 16-entry memory.

## Six assertions

| Check | Meaning |
| --- | --- |
| Full blocks write | A blocked write must leave the write pointer unchanged |
| Empty blocks read | A blocked read must leave the read pointer unchanged |
| Overflow | Writing while full must produce an overflow indication |
| Underflow | Reading while empty must produce an underflow indication |
| Write Gray value | The write Gray pointer must match its binary pointer |
| Read Gray value | The read Gray pointer must match its binary pointer |

For example:

```systemverilog
@(posedge wr_clk) disable iff (wr_reset)
(full && wr_en) |=> $stable(wr_bin)
```

Read this as: on a write-clock rising edge, skip the check during reset; if a write is requested while full, the write pointer must still have the same value at the next write-clock edge.

These checks introduce clock sampling, `disable iff`, `|=>`, and `$stable`. The two Gray-value assertions use only shift, XOR, and equality.

## Seven tests

| Test name | What happens |
| --- | --- |
| `test_full` | Fill the FIFO, check full, then read and compare every value |
| `test_empty` | Write one value, read it, and check empty |
| `test_overflow` | Try two extra writes while full; stored data must remain correct |
| `test_underflow` | Try two reads while empty, then check a valid transfer |
| `test_wrap` | Fill and drain four times so the pointers wrap around |
| `test_concurrent_wr_rd` | Run write/read tasks together using `fork...join` |
| `test_reset` | Reset with pending data, then verify a new fill/drain |

The stimulus uses increasing data values. There are no random seeds, configuration matrices, or injected bugs in this version. Concurrent requests can be blocked by full/empty; the scoreboard checks accepted transfers and the rejected-request outputs.

## Run one test

With Synopsys VCS:

```bash
vcs -full64 -sverilog -assert svaext +incdir+. \
  design.sv testbench.sv -top tb -o simv
./simv +TEST=test_full
```

With Verilator 5.x:

```bash
verilator --binary --timing --assert --top-module tb \
  -Wno-DECLFILENAME -I. design.sv testbench.sv
./obj_dir/Vtb +TEST=test_full
```

Use `+TEST=all`, or omit `+TEST`, to run all seven tests in one simulation. Any unknown test name fails with `$fatal`.

`testbench.sv` includes `fifo_assertions.sv`; keep all three SystemVerilog files together. Compile `design.sv` and `testbench.sv` only.

## Run the regression

From the repository directory:

```bash
python3 scripts/regress.py verilator
```

Or, with licensed VCS available:

```bash
python3 scripts/regress.py vcs
```

The Python script uses `subprocess.run` to execute terminal commands. `check=True` stops it when compilation or a test fails. Its `for` loop runs each test in a fresh simulation. The final message is `REGRESSION PASS: all 7 tests passed`.

GitHub Actions runs the Verilator regression and keeps a log. The default combined `all` run is checked as well.

## Validation and limits

My simplified version passed all seven individual tests and the combined `all` run with the six assertions enabled. See the [verification run](https://github.com/mirzamalikbaig/async_fifo/actions/runs/42154577883) for the results and downloadable logs. These runs used Verilator; I have not rerun this simplified version with VCS.

The old [VCS log](results/test_full.log) is from the original binary-pointer version and remains as history. It does not describe the current design.

`DEPTH` must be a power of two and at least 2. `PTR_WIDTH` must equal `$clog2(DEPTH)` and `DATA_WIDTH` must be positive. The beginner regression uses the default depth, data width, and clock periods.

Simulation checks digital behavior. Hardware use still needs CDC analysis, Gray-bus timing constraints, and implementation checks. Reset is common to both sides; independent one-sided resets are outside this design's contract.
