#!/usr/bin/env python3
"""Audit source routing against local official MAPROUT; routing is not certification."""
import json,re,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/n8sim'))
import simtop
text=(ROOT/'hdl/rtl/n8_top.v').read_text()
table=simtop.mapper_table(text);table[0]='bus_000'
# Track groups only after the default-defines preamble.
rbf=100;groups={0:100};pending=[]
body=text.split('case (mapper_id)',1)[1].split('endcase',1)[0]
for line in body.splitlines():
 m=re.search(r'`ifdef N8_RBF_(\d+)',line)
 if m:rbf=int(m[1])
 line=line.split('//',1)[0]
 pending += [int(n) for n in re.findall(r"8'd(\d+)",line)]
 if re.search(r'g\s*=\s*bus_',line):
  for n in pending:groups[n]=rbf
  pending=[]
official_path=ROOT/'ref/krikzz-n8-os/v1.26/EDFC/MAPROUT.BIN'
official={i for i,v in enumerate(official_path.read_bytes()[:254]) if v!=255}
report={'note':'Source routing only; see documented feature limits and actual test reports.',
 'routed_ids':len(table),'official_routed':len(official & table.keys()),
 'official_missing':sorted(official-table.keys()),'extra_ids':sorted(table.keys()-official),
 'partial_ids':{'5':'MMC5 split fine-Y limited by SRAM wiring; see docs/mmc5-validacion.md',
'99':'VS peripherals/palette/dual CPU not emulated',
 '111':'GTROM flash programming/LED/GTMP3 absent','176':'submapper0 only',
 '186':'StudyBox banks without tape drive','220':'legacy N8 alias of MMC3, not independent hardware',
 '234':'only the first 512KB PRG/CHR pair physically fits'},
 'routing':{str(n):{'rbf':groups[n],'bus':table[n]} for n in sorted(table)}}
print(json.dumps(report,indent=2))
