# Asynchronous FIFO

I upgraded this SystemVerilog FIFO with registered Gray-coded pointers, two-flop pointer synchronizers, a self-checking scoreboard, and 13 SVA checks.

The default configuration is **16 entries × 8 bits**, with a 10 ns write clock and a 14 ns read clock. The module name, port names, active-high reset, and registered read-data interface are preserved.

## Design

- Each domain owns its binary pointer, Gray pointer, and local status outputs. All sequential RTL uses nonblocking assignments.
- Binary pointers have one extra wrap bit. Memory addressing uses their lower bits; only the registered Gray pointers cross between clock domains.
- Two `ASYNC_REG` stages synchronize each pointer into the opposite domain. Flags use the second stage.
- The write domain registers `full_o` from the next write Gray pointer and the synchronized read Gray pointer with its top two bits inverted. The read domain registers `empty_o` from next-read/synchronized-write pointer equality.
- `rst_i` asserts reset asynchronously. Two local reset flops synchronize its release separately for each clock domain. Reset flushes the FIFO; both clocks must run to complete reset release.
- Memory has one write-clock writer and one read-clock reader. Reset clears pointers and the registered read output, without clearing the RAM array. Old entries are invalid after reset.

`DEPTH` must be a power of two and at least 2. `PTR_WIDTH` must equal `$clog2(DEPTH)`; `DATA_WIDTH` must be positive. Simulation checks reject unsupported settings.

## Interface behavior

A write is accepted on a write-clock rising edge when `wr_en_i && !full_o` and local reset is inactive. A read is accepted on a read-clock rising edge when `rd_en_i && !empty_o` and local reset is inactive. `rdata_o` updates after an accepted read edge and otherwise holds its previous value.

A write request while full is rejected and asserts `overflow_o` for that write-clock cycle. A read request while empty is rejected and asserts `underflow_o` for that read-clock cycle. These indicators are not sticky: repeated rejected requests keep them high, and the next non-rejected local cycle clears them.

Full and empty are local, conservative flags. A remote transfer takes synchronization and flag-registration cycles to become visible. A consumer must wait for local `empty_o` to clear; a producer must wait for local `full_o` to clear. Reset release also has local latency.

## Verification

The scoreboard queues accepted write data, compares every accepted read in FIFO order, and checks read-data hold behavior and error pulses. It uses external transfers and flags for reference contents, not the DUT's memory or pointers. A semaphore serializes reference-queue operations when clock edges coincide. Reset discards queued reference data, and final accounting requires `writes == reads + discarded` with an empty queue. Any mismatch or timeout ends the run with `$fatal`.

| Test | Check |
| --- | --- |
| `test_full` | Fill exactly to capacity, then compare all data during drain |
| `test_empty` | Single-entry transfer and return to empty |
| `test_overflow` | Reject four writes beyond capacity without overwriting data |
| `test_underflow` | Reject seven empty reads and preserve the output data |
| `test_wrap` | Ten complete fill/drain rounds across pointer wraparound |
| `test_concurrent_wr_rd` | Concurrent pseudo-random requests on independent clocks, followed by drain |
| `test_reset` | Flush a half-full FIFO, then verify a new fill/drain |

The default `+TEST=all` runs all seven. `+SEED=<number>` controls independent reproducible write/read PRNG streams.

The 13 assertions check source-domain Gray transitions, binary/Gray consistency, accepted pointer advances, pointer holds on idle or blocked requests, overflow/underflow pulses, read-data stability, and the second synchronizer stages. A destination may skip source Gray states, so I do not assert one-bit transitions on destination-synchronized pointers.

## Run

With Verilator 5.x supporting timing and assertions:

```bash
python3 scripts/regress.py
```

The regression builds four configurations and runs three seeds per configuration, plus all seven individually selectable tests on the default configuration: **19 positive simulations**. It also compiles two temporary RTL mutations: corrupted read data must trip the scoreboard, and an incorrectly encoded write pointer must trip SVA. These are **expected failures** that verify the checkers are active.

| Configuration | Depth | Data bits | Write period | Read period | Read phase |
| --- | ---: | ---: | ---: | ---: | ---: |
| Default | 16 | 8 | 10 ns | 14 ns | 0 ns |
| Minimum depth | 2 | 8 | 10 ns | 14 ns | 0 ns |
| Reader faster | 8 | 13 | 14 ns | 6 ns | 1 ns |
| Coincident edges | 32 | 16 | 8 ns | 8 ns | 0 ns |

Seeds: `1`, `42`, and `2026`. Build output and per-run logs go under `build/`. The GitHub Actions workflow runs this regression and uploads its logs.

For one run:

```bash
verilator --binary --timing --assert --top-module tb \
  -Wno-DECLFILENAME -I. design.sv testbench.sv
./obj_dir/Vtb +TEST=all +SEED=42
```

With Synopsys VCS:

```bash
vcs -full64 -sverilog -assert svaext +incdir+. \
  design.sv testbench.sv -top tb -o simv
./simv +TEST=all +SEED=42
```

`testbench.sv` includes `fifo_assertions.sv`; do not compile that included file a second time.

## Results and scope

My upgraded regression passed on GitHub Actions on November 5, 2026: **19 positive simulations and both expected-failure checker tests passed**. The 13 SVA checks were enabled. See the [verification run](https://github.com/mirzamalikbaig/async_fifo/actions/runs/42044672600) for the result and downloadable logs.

The old [VCS `test_full` log](results/test_full.log) belongs to the original binary-pointer version and is retained as history; it does not validate this upgrade.

Simulation checks ordering and control behavior. It does not model analog metastability or replace CDC analysis, implementation timing constraints, or hardware validation. Gray-bus skew/max-delay constraints and tool-specific synchronizer placement must be reviewed for the target technology. RAM inference also depends on the synthesis target. This implementation uses a common reset for both sides; independent one-sided resets are outside its contract.

Design background: [Jason Yu, Dual-Clock Asynchronous FIFO in SystemVerilog](https://www.verilogpro.com/asynchronous-fifo-design/), describing the Cummings Gray-pointer architecture and its physical timing requirements.
