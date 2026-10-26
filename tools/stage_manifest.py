"""Bind the diagnostic sources before compiling; never re-use release evidence."""
from pathlib import Path
import hashlib
import json
import xml.etree.ElementTree as ET
import sys

project = Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path(__file__).resolve().parents[1] / 'FPGA_engin'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
ns = {'p': 'http://www.efinixinc.com/enf_proj'}
tree = ET.parse(project / 'Case4_Ti60.xml')
params = {e.get('name'): e.get('value') for e in tree.findall('.//p:place_and_route/p:param', ns)}
manifest = {
    'variant': 'V12_PLUS_FIX, 20261025',
    'hardware_tested': False,
    'baseline': 'shipped Case4_Ti60_1080p_V12_PLUS_20261025 ZIP 75b17aa91bd35a7a28c39e07660ccf43c1780d5c2769d69bae41f883e9bd8216',
    'scope': '4 KiB boundary splitting in edge-map DDR DMA only; all other production RTL and PC software retained. Public protocol 12. No hardware test.',
    'seed': int(params['seed']),
    'pnr_optimization': params['optimization_level'],
    'placer_effort': int(params['placer_effort_level']),
    'implementation_files_sha256': {n: sha(project / n) for n in ('case4_ddr_cluster.placeloc', 'efx_pnr_settings.ini')},
    'source_sha256': {p.name: sha(p) for p in sorted((project / 'case4_rtl').iterdir()) if p.is_file()},
    'top_sha256': sha(project / 'example_top.v'),
}
(project / 'v12_build_manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
print('Staged', len(manifest['source_sha256']), 'RTL/assets; seed', manifest['seed'])
