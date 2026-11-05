# Asynchronous FIFO

A SystemVerilog FIFO practice project with separate write and read clocks. The default FIFO is 16 entries deep with 8-bit data. The write clock period is 10 ns and the read clock period is 14 ns.

## Files

- [design.sv](design.sv): FIFO design, pointers, toggle flags, and status flags.
- [testbench.sv](testbench.sv): clock generation, reset, write/read tasks, and test selection.
- [results/test_full.log](results/test_full.log): simulation output excerpt from the supplied VCS run on November 5, 2026.

## Run

With Synopsys VCS installed:

```bash
vcs -sverilog design.sv testbench.sv -top tb -o simv
./simv
```

The default test is `test_full`. Change `testname` in `testbench.sv` to select `test_empty`, `test_overflow`, `test_underflow`, or `test_concurrent_wr_rd`.

## Simulation result

The recorded `test_full` run writes 16 values and reads the same values back in order. `full` becomes 1 after the last write, and `empty` becomes 1 after the last read. Overflow and underflow remain 0. The simulation ends at 506 ns.

The saved output comes from the supplied run; it was not rerun during upload. The testbench prints activity and flags but does not have an automatic scoreboard. Other test cases are included, but their results are not recorded here. The current `test_underflow` case performs equal numbers of writes and reads, so it does not deliberately trigger underflow.

## Current limitations

This is a learning version. It uses single-stage binary-pointer crossings and assigns some registers from multiple procedural blocks. CDC, reset, and flag timing need further work before hardware use.
