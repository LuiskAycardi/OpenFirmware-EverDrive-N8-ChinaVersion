#!/usr/bin/env python3
"""Six negative controls for misc4 only; originals are never modified.

Run: python3 hdl/sim/mutate_misc4.py
Requires iverilog and vvp. Each mutant must compile successfully and fail
at its designated assertion; a timeout or unrelated failure does not count.
All generated RTL/executables live in a temporary directory and are removed.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
RTL = ROOT / 'hdl/rtl/mapper_misc4.v'
TB = ROOT / 'hdl/sim/tb_misc4_direct.v'
MUTATIONS = (
    ('99_wrong_chr_bit', 'vs_bank<=cpu_d[2];', 'vs_bank<=cpu_d[1];', '99 PRG'),
    ('111_ignore_reads',
     '111: if(romsel_n && cpu_a[14] && cpu_a[12])',
     '111: if(romsel_n && !cpu_rw && cpu_a[14] && cpu_a[12])',
     '111 PRG/read latch'),
    ('111_mirror_bonus_ram',
     'ppu_a[13],ppu_a[12:10]};', 'ppu_a[13],1\'b0,ppu_a[11:10]};',
     '111 RAM/bonus RAM'),
    ('186_ignore_ram_bank',
     "else prg_a={4'd0,ram_bank[7:6],cpu_a[12:10]};",
     "else prg_a={6'd0,cpu_a[12:10]};", '186 8K RAM bank'),
    ('234_ignore_reads', '234: if(!romsel_n) begin',
     '234: if(!romsel_n && !cpu_rw) begin', '234 PRG modes'),
    ('234_accept_fff8', "cpu_a<=15'h7ff7", "cpu_a<=15'h7ff8",
     '234 FFF8 excluded'),
)


def run(command):
    result = subprocess.run(command, cwd=ROOT, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            timeout=30)
    return result.returncode, result.stdout


def compile_and_run(source, output):
    rc, log = run(['iverilog', '-g2012', '-Wall', '-s', 'tb_misc4_direct',
                   '-o', str(output), str(source), str(TB)])
    if rc or log.strip():
        raise RuntimeError(f'Compilation failed or produced warnings:\n{log}')
    return run(['vvp', str(output)])


def main():
    source = RTL.read_text()
    with tempfile.TemporaryDirectory(prefix='misc4-mutations-') as tmp:
        tmp = Path(tmp)
        rc, log = compile_and_run(RTL, tmp / 'baseline.vvp')
        if rc or 'PASS misc4_direct checks=' not in log or 'FAIL ' in log:
            raise RuntimeError(f'Baseline did not pass:\n{log}')
        print('BASELINE ' + next(line for line in log.splitlines()
                                 if line.startswith('PASS misc4_direct')))
        for name, before, after, assertion in MUTATIONS:
            if source.count(before) != 1:
                raise RuntimeError(f'{name}: expected exactly one mutation site')
            mutant = tmp / (name + '.v')
            mutant.write_text(source.replace(before, after, 1))
            rc, log = compile_and_run(mutant, tmp / (name + '.vvp'))
            failures = [line for line in log.splitlines() if line.startswith('FAIL ')]
            if rc == 0 or not failures or not failures[0].startswith(f'FAIL {assertion} check='):
                raise RuntimeError(f'{name}: survived or failed unexpectedly:\n{log}')
            print(f'KILLED {name}: {failures[0]}')
    print(f'PASS misc4 mutations killed={len(MUTATIONS)}/{len(MUTATIONS)}')


if __name__ == '__main__':
    main()
