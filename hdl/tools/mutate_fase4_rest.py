#!/usr/bin/env python3
"""Negative controls for new mapper families, isolated from production files."""
from pathlib import Path
import subprocess,tempfile
ROOT=Path(__file__).resolve().parents[1]
mutants=[
 ('56 ROM select','mapper_irqcpu.v','use_rom56<=cpu_d[2]',"use_rom56<=1'b0"),
 ('56 CHR bank','mapper_irqcpu.v','3:ch[cpu_a[2:0]]<=cpu_d',"3:ch[cpu_a[2:0]]<=0"),
 ('91 threshold','mapper_scan4.v','counter[5:0]==63','counter[5:0]==62'),
 ('91 outer PRG','mapper_scan4.v','outer<=cpu_d[2:1]','outer<=0'),
 ('117 exact decode','mapper_scan4.v',"cpu_a[14:2]==13'h0000","cpu_a[14:12]==0"),
 ('117 terminal IRQ','mapper_scan4.v','if(counter==1)','if(counter==2)'),
 ('222 terminal IRQ','mapper_scan4.v','if(counter>=239)','if(counter>=238)'),
 ('105 startup unlock','mapper_nwc105.v','if(init_stage==2)','if(init_stage==3)'),
 ('105 timer terminal','mapper_nwc105.v',"timer_count==TIMER_LIMIT-1'b1","timer_count==TIMER_LIMIT-2'd2"),
 ('105 WRAM disable','mapper_nwc105.v','m2 && !prg[4]',"m2 && 1'b1"),
]
for name,filename,old,new in mutants:
 src=(ROOT/'rtl'/filename).read_text()
 if src.count(old)!=1:raise SystemExit(f'Nonunique mutation: {name}')
 with tempfile.TemporaryDirectory(prefix='n8-rest-mut-') as tmp:
  d=Path(tmp);m=d/filename;m.write_text(src.replace(old,new))
  rtl=[str(x) for x in sorted((ROOT/'rtl').glob('*.v')) if x.name!=filename]+[str(m)]
  subprocess.run(['iverilog','-g2005','-DN8_RBF_104','-s','tb_fase4_rest','-I',str(ROOT/'sim'),'-o',str(d/'sim.vvp'),str(ROOT/'sim/tb_fase4_rest.v')]+rtl,check=True,capture_output=True)
  r=subprocess.run(['vvp','-n',str(d/'sim.vvp')],capture_output=True,text=True,errors='replace',timeout=60)
  if 'FALLO' not in r.stdout and not r.returncode:raise SystemExit(f'Undetected: {name}')
  print(f'DETECTED: {name}',flush=True)
print(f'{len(mutants)}/{len(mutants)} detected')
