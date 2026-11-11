#!/usr/bin/env python3
"""Negative controls for MMC5 memory/PPU behavior; no production RTL modifications."""
from pathlib import Path
import subprocess,tempfile
ROOT=Path(__file__).resolve().parents[1]
s=(ROOT/'rtl/mapper_mmc5.v').read_text()
mutants={
 'ExRAM readonly mode':('exram_mode!=3',"1'b1"),
 'fill palette':('{4{fill_color}}',"8'h00"),
 'extended attribute bank':('ex_ppu_q[5:0]',"6'd0"),
 'scanline vs tile IRQ':('if(repeated_nt==2)', 'if(nt_tile)'),
 'IRQ status open bus mask':("ra==12'h204 ? 8'hc0", "ra==12'h204 ? 8'hff"),
 'sprite size from PPUCTRL':('sprite8x16 <= cpu_d[5]', "sprite8x16 <= 1'b0"),
}
for name,(a,b) in mutants.items():
 if s.count(a)!=1:raise SystemExit(f'nonunique mutant: {name}')
 with tempfile.TemporaryDirectory(prefix='mmc5-ppu-mut-') as tmp:
  d=Path(tmp);(d/'mapper.v').write_text(s.replace(a,b))
  subprocess.run(['iverilog','-g2005','-s','tb_mmc5_ext','-o',str(d/'sim.vvp'),str(ROOT/'sim/tb_mmc5_ext.v'),str(d/'mapper.v'),str(ROOT/'rtl/mmc5_exram.v'),str(ROOT/'rtl/snd_mmc5.v')],check=True,capture_output=True)
  r=subprocess.run(['vvp','-n',str(d/'sim.vvp')],capture_output=True,text=True,errors='replace',timeout=60)
  if not r.returncode or 'FALLO:' not in r.stdout:raise SystemExit(f'undetected mutant: {name}')
  print(f'DETECTED: {name}',flush=True)
print(f'{len(mutants)}/{len(mutants)} detected')
