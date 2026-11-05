#!/usr/bin/env python3
"""Build and run the FIFO scoreboard and SVA regression with Verilator."""
from pathlib import Path
import os
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
CONFIGS = [
    ('default', 16, 8, 5, 7, 0),
    ('minimum_depth', 2, 8, 5, 7, 0),
    ('reader_faster', 8, 13, 7, 3, 1),
    ('coincident_edges', 32, 16, 4, 4, 0),
]
SEEDS = (1, 42, 2026)
DIRECTED = ('test_full', 'test_empty', 'test_overflow', 'test_underflow',
            'test_wrap', 'test_concurrent_wr_rd', 'test_reset')


def execute(command, logfile, *, expected_failure=False, marker=None):
    result = subprocess.run(command, cwd=ROOT, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=180)
    logfile.parent.mkdir(parents=True, exist_ok=True)
    logfile.write_text(result.stdout)
    if expected_failure:
        if result.returncode == 0 or (marker and marker not in result.stdout):
            raise RuntimeError(f'Negative test did not fail as expected: {logfile}\n{result.stdout}')
    elif result.returncode:
        raise RuntimeError(f'Command failed: {command}\n{result.stdout}')
    return result.stdout


def build(name, depth, width, wr_half, rd_half, phase, *, source=None):
    directory = BUILD / name
    directory.mkdir(parents=True, exist_ok=True)
    execute(['verilator', '--binary', '--timing', '--assert', '--top-module', 'tb',
             '-Wno-DECLFILENAME', '-j', '2', '--Mdir', str(directory),
             f'-GDEPTH={depth}', f'-GDATA_WIDTH={width}',
             f'-GWR_HALF_NS={wr_half}', f'-GRD_HALF_NS={rd_half}', f'-GRD_PHASE_NS={phase}',
             '-I' + str(ROOT), str(source or ROOT / 'design.sv'), str(ROOT / 'testbench.sv')],
            directory / 'compile.log')
    return directory / 'Vtb'


def main():
    if not shutil.which('verilator'):
        raise RuntimeError('verilator must be installed and on PATH (version 5.x with --timing support)')
    BUILD.mkdir(exist_ok=True)
    version = subprocess.check_output(['verilator', '--version'], text=True).strip()
    summaries = [version]
    count = 0
    for config in CONFIGS:
        name = config[0]
        binary = build(*config)
        for seed in SEEDS:
            output = execute([str(binary), '+TEST=all', f'+SEED={seed}'],
                             BUILD / name / f'seed_{seed}.log')
            passed = [line for line in output.splitlines() if line.startswith('PASS test=all ')]
            if len(passed) != 1:
                raise RuntimeError(f'PASS summary missing for {name}, seed {seed}')
            summary = f'{name}: {passed[0]}'
            summaries.append(summary)
            print(summary, flush=True)
            count += 1
        if name == 'default':
            for test in DIRECTED:
                output = execute([str(binary), f'+TEST={test}', '+SEED=42'],
                                 BUILD / name / f'{test}.log')
                if f'PASS test={test} ' not in output:
                    raise RuntimeError(f'PASS summary missing for {test}')
                count += 1

    # Prove the checkers are active: corrupt only temporary RTL copies.
    source = (ROOT / 'design.sv').read_text()
    mutations = [
        ('bad_data', 'rdata_o <= mem[rd_bin[PTR_WIDTH-1:0]];',
         "rdata_o <= mem[rd_bin[PTR_WIDTH-1:0]] ^ {{(DATA_WIDTH-1){1'b0}}, 1'b1};",
         'Scoreboard: data mismatch'),
        ('bad_gray', 'wr_gray    <= wr_gray_next;', 'wr_gray    <= wr_bin_next;',
         'Write binary/Gray encoding mismatch'),
    ]
    for name, old, new, marker in mutations:
        if source.count(old) != 1:
            raise RuntimeError(f'Mutation target is ambiguous for {name}')
        mutant = BUILD / f'{name}.sv'
        mutant.write_text(source.replace(old, new))
        binary = build(name, 16, 8, 5, 7, 0, source=mutant)
        execute([str(binary), '+TEST=test_full'], BUILD / name / 'expected_failure.log',
                expected_failure=True, marker=marker)
        summaries.append(f'NEGATIVE PASS {name}: detected {marker}')
        print(summaries[-1], flush=True)

    summaries.append(f'REGRESSION PASS: {count} simulations, 2 expected-failure checker tests')
    (BUILD / 'regression_summary.log').write_text('\n'.join(summaries) + '\n')
    print(summaries[-1], flush=True)
    if os.getenv('GITHUB_STEP_SUMMARY'):
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as stream:
            stream.write('### FIFO regression\n\n```text\n' + '\n'.join(summaries) + '\n```\n')


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, subprocess.SubprocessError) as error:
        message = str(error)
        print(message, file=sys.stderr)
        # Surface the first actionable diagnostic in the read-only CI job name.
        lines = message.splitlines()
        diagnostic = next((line for line in lines if '%Error' in line or
                           'Assertion failed' in line or 'Scoreboard:' in line), lines[0])
        if os.getenv('GITHUB_OUTPUT'):
            with open(os.environ['GITHUB_OUTPUT'], 'a') as stream:
                stream.write('diagnostic=' + diagnostic[:220] + '\n')
        sys.exit(1)
