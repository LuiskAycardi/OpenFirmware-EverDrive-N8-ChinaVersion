#!/usr/bin/env python3
"""Run focused negative controls against the directed MMC5 core testbench."""
from pathlib import Path
import subprocess,tempfile
ROOT=Path(__file__).resolve().parents[1]
original=(ROOT/'rtl/mapper_mmc5.v').read_text()
mutations={
 'multiplier addition':('wire [15:0] prod = mul_a * mul_b;', 'wire [15:0] prod = mul_a + mul_b;'),
 'wrong RAM key':("ram_prot2 == 2'b01", "ram_prot2 == 2'b10"),
 '16KB bank alignment':("{pbk[6:1], cpu_a[13]}", "{pbk[6:1], 1'b0}"),
 '4KB CHR half selection':("ppu_a[12] ? chr_a_set[7] : chr_a_set[3]", "ppu_a[12] ? chr_a_set[3] : chr_a_set[7]"),
}
for name,(old,new) in mutations.items():
 if original.count(old)!=1:raise SystemExit(f'not a unique mutation: {name}')
 with tempfile.TemporaryDirectory(prefix='mmc5-mut-') as tmp:
  d=Path(tmp);rtl=d/'mapper.v';out=d/'test.vvp'
  rtl.write_text(original.replace(old,new))
  subprocess.run(['iverilog','-g2005','-s','tb_mmc5','-o',str(out),str(ROOT/'sim/tb_mmc5.v'),str(rtl),str(ROOT/'rtl/mmc5_exram.v'),str(ROOT/'rtl/snd_mmc5.v')],check=True,capture_output=True,text=True)
  r=subprocess.run(['vvp','-n',str(out)],capture_output=True,text=True,errors="replace",timeout=60)
  if r.returncode==0 or 'FALLO:' not in r.stdout:raise SystemExit(f'mutation not detected: {name}')
  print(f'DETECTED: {name}',flush=True)
print(f'{len(mutations)}/{len(mutations)} negative controls detected')
