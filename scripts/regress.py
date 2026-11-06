# Compile once, then run the seven FIFO tests one by one.
# Run this script from the repository directory.
import os
import subprocess
import sys

simulator = "verilator"
if len(sys.argv) > 1:
    simulator = sys.argv[1]
os.makedirs("build", exist_ok=True)

# subprocess.run executes a terminal command.
# check=True stops the script if compiling or running a test fails.
if simulator == "verilator":
    subprocess.run([
        "verilator", "--binary", "--timing", "--assert", "--top-module", "tb",
        "-Wno-DECLFILENAME", "-j", "2", "--Mdir", "build/obj_dir", "-I.",
        "design.sv", "testbench.sv"
    ], check=True)
    executable = "./build/obj_dir/Vtb"
elif simulator == "vcs":
    subprocess.run([
        "vcs", "-full64", "-sverilog", "-assert", "svaext", "+incdir+.",
        "design.sv", "testbench.sv", "-top", "tb", "-o", "build/simv"
    ], check=True)
    executable = "./build/simv"
else:
    sys.exit("Choose verilator or vcs")

tests = [
    "test_full", "test_empty", "test_overflow", "test_underflow",
    "test_wrap", "test_concurrent_wr_rd", "test_reset"
]

for test in tests:
    print("Running " + test, flush=True)
    subprocess.run([executable, "+TEST=" + test], check=True)

print("REGRESSION PASS: all 7 tests passed", flush=True)
