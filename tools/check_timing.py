"""Fail on negative setup/hold slack even when efx_run pnr reports PASS."""
import argparse
import re
from pathlib import Path

parser=argparse.ArgumentParser()
parser.add_argument('project',type=Path)
args=parser.parse_args()
report=args.project/'outflow'/'Case4_Ti60.timing.rpt'
text=report.read_text(encoding='utf-8')
try:
    setup=text.split('Setup (Max) Clock Relationship',1)[1]
    setup,hold=setup.split('Hold (Min) Clock Relationship',1)
    hold=hold.split('NOTE:',1)[0]
except (IndexError,ValueError):
    raise SystemExit('FAIL: setup or hold relationship summary is missing')
rows=[]
required={'clk_pixel','clk_sys','cmos_pclk','core_clk','tac_clk','twd_clk','tdqss_clk'}
for mode,section in [('setup',setup),('hold',hold)]:
    section_rows=[]
    for line in section.splitlines():
        m=re.match(r'\s*(\S+)\s+(\S+)\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+\(',line)
        if m: section_rows.append((mode,m[1],m[2],float(m[4])))
    covered={a for _,a,b,_ in section_rows if a==b}
    if not required.issubset(covered):
        raise SystemExit(f'FAIL: {mode} clocks missing: {sorted(required-covered)}')
    if not any(a=='core_clk' and b=='twd_clk' for _,a,b,_ in section_rows):
        raise SystemExit(f'FAIL: DDR core_clk -> twd_clk {mode} relationship is missing')
    rows.extend(section_rows)
failed=[r for r in rows if r[3]<0]
for mode,a,b,slack in failed: print(f'FAIL {mode} {a} -> {b}: slack {slack:.3f} ns')
if failed: raise SystemExit(1)
print(f'PASS: {len(rows)} setup/hold relationships, minimum slack {min(r[3] for r in rows):.3f} ns')
