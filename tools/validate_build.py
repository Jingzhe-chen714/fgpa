"""Write evidence only for this staged V12 source, timing and programming files.

Run after compile.ps1 -Bitstream. This is not hardware validation.
"""
import argparse,hashlib,json,re,subprocess,sys
from datetime import datetime,timezone
from pathlib import Path
import xml.etree.ElementTree as ET

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser();p.add_argument('project',type=Path);p.add_argument('--repository-rtl',type=Path);p.add_argument('--efinity-root',type=Path,default=Path('D:/'));a=p.parse_args()
 project=a.project.resolve();out=project/'outflow';manifest_path=project/'v12_build_manifest.json';manifest=json.loads(manifest_path.read_text())
 staged_at=manifest_path.stat().st_mtime
 errors=[];source_hash={}
 for filename,want in manifest['source_sha256'].items():
  f=project/'case4_rtl'/filename
  if not f.is_file() or sha(f)!=want:errors.append('staged source changed: '+filename)
  elif a.repository_rtl and (a.repository_rtl/filename).is_file() and sha(a.repository_rtl/filename)!=want:errors.append('repository source differs: '+filename)
 if sha(project/'example_top.v')!=manifest['top_sha256']:errors.append('top changed since stage')
 implementation_files=manifest.get('implementation_files_sha256',{})
 for name,want in implementation_files.items():
  f=(project/name).resolve()
  if not f.is_relative_to(project) or not f.is_file():errors.append('missing or external implementation file: '+name)
  elif sha(f)!=want:errors.append('implementation file changed since stage: '+name)
  else:source_hash[name]=sha(f)
 settings_path=project/'efx_pnr_settings.ini';assignments=[]
 if implementation_files and not settings_path.is_file():errors.append('missing implementation settings file')
 if settings_path.is_file():
  if 'efx_pnr_settings.ini' not in implementation_files:errors.append('unmanifested implementation settings')
  settings=settings_path.read_text(encoding='utf-8-sig')
  assignments=re.findall(r'^\s*loc_assignment\s*=\s*(\S+)\s*$',settings,re.M)
  if len(assignments)!=1:errors.append('expected exactly one local loc_assignment')
  elif assignments[0] not in implementation_files:errors.append('physical placement file is not bound by manifest')
  elif not (project/assignments[0]).is_file():errors.append('physical placement file is missing')
 tree=ET.parse(project/'Case4_Ti60.xml');ns={'p':'http://www.efinixinc.com/enf_proj'}
 pnr_parameters={e.get('name'):e.get('value') for e in tree.findall('.//p:place_and_route/p:param',ns)}
 for key,expected in [('seed',manifest['seed']),('optimization_level',manifest.get('pnr_optimization','TIMING_2')),('placer_effort_level',manifest.get('placer_effort',3))]:
  if pnr_parameters.get(key)!=str(expected):errors.append('implementation parameter differs from manifest: '+key)
 for el in tree.findall('.//p:design_file',ns):
  name=el.get('name');f=(project/name).resolve()
  if not f.is_relative_to(project):errors.append('nonportable XML source: '+name)
  elif not f.is_file():errors.append('missing XML source: '+name)
  else:source_hash[name]=sha(f)
 for folder in ('src','ip','case4_rtl'):
  for f in (project/folder).rglob('*'):
   if f.is_file() and f.suffix.lower() in ('.v','.sv','.vh','.svh','.vhd','.vhdl','.hex','.mem','.mif','.bin'):
    source_hash[f.relative_to(project).as_posix()]=sha(f)
 report_hash={};map_counts={};placement={};relationships=[];physical_placement={}
 check=subprocess.run([sys.executable,str(Path(__file__).with_name('check_placement.py')),str(project),'--efinity-root',str(a.efinity_root)],input='',capture_output=True,text=True)
 if check.returncode:errors.append('physical placement check failed: '+(check.stdout+check.stderr).strip())
 physical_report=project/'v12_placement_check.json'
 if physical_report.is_file():
  physical_placement=json.loads(physical_report.read_text(encoding='utf-8-sig'))
  report_hash['v12_placement_check.json']=sha(physical_report)
  if implementation_files:
   if physical_placement.get('result')!='PASS':errors.append('physical placement was not confirmed applied')
   if physical_placement.get('requested_cells',0)<=0 or physical_placement.get('matched_cells')!=physical_placement.get('requested_cells'):errors.append('not every requested placement cell matched')
   if physical_placement.get('mismatches'):errors.append('physical placement contains mismatches')
   for name,want in implementation_files.items():
    if physical_placement.get('input_sha256',{}).get(name)!=want:errors.append('physical placement report did not bind implementation input: '+name)
   if len(assignments)==1 and (project/assignments[0]).is_file():
    requested_count=sum(bool(line.split('#',1)[0].strip()) for line in (project/assignments[0]).read_text(encoding='utf-8-sig').splitlines())
    if physical_placement.get('requested_cells')!=requested_count:errors.append('physical placement requested count differs from the constraint file')
   for name,want in physical_placement.get('input_sha256',{}).items():
    f=(project/name).resolve()
    if not f.is_relative_to(project) or not f.is_file() or sha(f)!=want:errors.append('physical placement evidence input mismatch: '+name)
    elif name.startswith('outflow/'):report_hash[name]=want
   actual_name=physical_placement.get('actual_dump','')
   actual=(project/actual_name).resolve()
   if not actual_name or not actual.is_relative_to(project) or not actual.is_file() or sha(actual)!=physical_placement.get('actual_dump_sha256'):errors.append('actual placement dump missing or changed')
   else:report_hash[actual_name]=sha(actual)
 elif implementation_files:errors.append('missing physical placement evidence')
 for name in ('Case4_Ti60.map.rpt','Case4_Ti60.place.rpt','Case4_Ti60.place.out','Case4_Ti60.route.rpt','Case4_Ti60.route.out','Case4_Ti60.timing.rpt','Case4_Ti60.pt.rpt','Case4_Ti60.pgm.out'):
  f=out/name
  if not f.is_file() or f.stat().st_size==0:errors.append('missing report: '+name)
  else:
   report_hash['outflow/'+name]=sha(f)
   if f.stat().st_mtime<staged_at:errors.append('report predates source staging: '+name)
 if (out/'Case4_Ti60.map.rpt').is_file():
  text=(out/'Case4_Ti60.map.rpt').read_text(encoding='utf-8')
  map_counts={k:int(v) for k,v in re.findall(r'^(EFX_\w+)\s*:\s*(\d+)',text,re.M)}
 if (out/'Case4_Ti60.place.rpt').is_file():
  text=(out/'Case4_Ti60.place.rpt').read_text(encoding='utf-8')
  for key,label in [('XLRs','XLRs'),('RAM10','Memory Blocks'),('DSP','DSP Blocks')]:
   m=re.search(r'^'+re.escape(label)+r':\s*(\d+)\s*/\s*(\d+)\s*\(([\d.]+)%\)',text,re.M)
   if m:placement[key]={'used':int(m[1]),'available':int(m[2]),'percent':float(m[3])}
 for key in ('XLRs','RAM10','DSP'):
  if key not in placement:errors.append('missing placement resource accounting: '+key)
  elif placement[key]['available']<=0 or placement[key]['used']>placement[key]['available']:errors.append('placement capacity exceeded: '+key)
 route_succeeded=False;route_final_overlap=None
 for name in ('Case4_Ti60.place.out','Case4_Ti60.route.out'):
  f=out/name
  if f.is_file():
   log=f.read_text(encoding='utf-8',errors='replace')
   if re.search(r'^\s*ERROR\s*:',log,re.M):errors.append('implementation reported an error: '+name)
   if name.endswith('route.out'):
    overlaps=re.findall(r'\bIter\s+\d+:\s+overlap=(\d+)',log)
    route_final_overlap=int(overlaps[-1]) if overlaps else None
    route_succeeded='Routing Succeeded' in log and 'Finished writing bitstream file' in log
    if not route_succeeded:errors.append('router did not confirm completed routing and core bitstream generation')
    if route_final_overlap!=0:errors.append('router final overlapping resource count is not confirmed zero')
 r=subprocess.run([sys.executable,str(Path(__file__).with_name('check_timing.py')),str(project)],input='',capture_output=True,text=True)
 if r.returncode:errors.append('timing check failed: '+(r.stdout+r.stderr).strip())
 if (out/'Case4_Ti60.timing.rpt').is_file():
  timing=(out/'Case4_Ti60.timing.rpt').read_text(encoding='utf-8')
  if 'Setup (Max) Clock Relationship' in timing and 'Hold (Min) Clock Relationship' in timing:
   setup,hold=timing.split('Setup (Max) Clock Relationship',1)[1].split('Hold (Min) Clock Relationship',1)
   for kind,section in [('setup',setup),('hold',hold.split('NOTE:',1)[0])]:
    for line in section.splitlines():
     m=re.match(r'\s*(\S+)\s+(\S+)\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+\(',line)
     if m:relationships.append({'kind':kind,'from':m[1],'to':m[2],'constraint_ns':float(m[3]),'slack_ns':float(m[4])})
 bitstreams={}
 for name in ('Case4_Ti60.bit','Case4_Ti60.hex','Case4_Ti60.bit.bin','Case4_Ti60.hex.bin'):
  f=out/name
  if not f.is_file() or f.stat().st_size==0:errors.append('missing programming file: '+name)
  else:
   bitstreams['outflow/'+name]={'sha256':sha(f),'bytes':f.stat().st_size}
   if f.stat().st_mtime<staged_at:errors.append('programming file predates source staging: '+name)
 for name in ('Case4_Ti60.xml','Case4_Ti60.peri.xml','Case4_Ti60.sdc','vendor_original.pt.sdc','native1080_clock_plan.json','v12_build_manifest.json'):
  f=project/name
  if f.is_file():source_hash[name]=sha(f)
 result={'variant':'V12','created_utc':datetime.now(timezone.utc).isoformat(),'result':'PASS' if not errors else 'FAIL',
  'hardware_tested':False,'scope':'Efinity synthesis, placement/routing and static timing; not camera/capture-card/physical-board test',
  'device':'Ti60F225','seed':manifest['seed'],'pnr_optimization':manifest.get('pnr_optimization','TIMING_2'),'placer_effort':manifest.get('placer_effort',3),
  'source_sha256':source_hash,'report_sha256':report_hash,
  'synthesis_primitives':map_counts,'placement_resources':placement,'physical_placement':physical_placement,'routing_succeeded':route_succeeded,'route_final_overlap':route_final_overlap,'timing_relationships':relationships,
  'minimum_slack_ns':min((r['slack_ns'] for r in relationships),default=None),'bitstreams':bitstreams,'errors':errors}
 (project/'v12_validation.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
 print(json.dumps({k:result[k] for k in ('result','placement_resources','minimum_slack_ns','errors')},indent=2))
 return bool(errors)
if __name__=='__main__':raise SystemExit(main())

