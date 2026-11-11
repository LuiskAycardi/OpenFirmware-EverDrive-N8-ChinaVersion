#!/usr/bin/env python3
"""Run self-checking vvp benches; propagate fatal exits and legacy FALLO output."""
import re,subprocess,sys
from pathlib import Path
failed=[]
for argument in sys.argv[1:]:
 path=Path(argument).resolve()
 print(f'== {path.stem}',flush=True)
 result=subprocess.run(['vvp','-n',str(path)],cwd=path.parent,capture_output=True,text=True,errors='replace')
 output=result.stdout+result.stderr
 for line in output.splitlines():
  if 'VCD info' not in line and '$finish' not in line:print(line)
 if result.returncode or re.search(r'\b(?:FALLO|FALLARON|FATAL)\b',output):failed.append(path.stem)
if failed:print('Failed benches: '+', '.join(failed),file=sys.stderr)
raise SystemExit(bool(failed))
