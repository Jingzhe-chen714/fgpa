"""Verify requested placement against a fresh official export of the PNR database.

This runs only efx_export (never MAP/PNR). Evidence is written to the project
root and outflow; no RTL, constraints, implementation settings, or database is
changed. A project without loc_assignment explicitly reports SKIP.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def parse_locations(path: Path) -> dict[str, tuple[int, int, int]]:
    result = {}
    occupied = {}
    for number, raw in enumerate(path.read_text(encoding='utf-8-sig').splitlines(), 1):
        fields = raw.split('#', 1)[0].split()
        if not fields:
            continue
        if len(fields) != 4:
            raise ValueError(f'{path.name}:{number}: expected cell x y subblk')
        name = fields[0]
        try:
            position = tuple(int(v) for v in fields[1:])
        except ValueError as exc:
            raise ValueError(f'{path.name}:{number}: non-integer coordinate') from exc
        if any(v < 0 for v in position):
            raise ValueError(f'{path.name}:{number}: negative coordinate')
        if name in result:
            raise ValueError(f'{path.name}:{number}: duplicate cell {name}')
        if position in occupied:
            raise ValueError(f'{path.name}:{number}: subblock already occupied by {occupied[position]}')
        result[name] = position
        occupied[position] = name
    if not result:
        raise ValueError(f'{path.name}: no placement cells')
    return result


def compare_locations(requested, actual):
    mismatches = []
    matched = 0
    for name, want in requested.items():
        have = actual.get(name)
        if have == want:
            matched += 1
        else:
            mismatches.append({'cell': name, 'requested': list(want),
                               'actual': list(have) if have is not None else None,
                               'reason': 'missing_cell' if have is None else 'coordinate_mismatch'})
    return matched, mismatches


def local_file(project: Path, name: str) -> Path:
    path = (project / name).resolve()
    if not path.is_relative_to(project):
        raise ValueError(f'input must be inside project: {name}')
    if not path.is_file():
        raise ValueError(f'missing input: {name}')
    return path


def check(project: Path, efinity_root: Path) -> dict:
    project = project.resolve()
    report = {'result': 'FAIL', 'requested_cells': 0, 'matched_cells': 0,
              'input_sha256': {}, 'actual_dump': '', 'actual_dump_sha256': '',
              'mismatches': [], 'errors': [],
              'scope': 'Actual physical coordinates only; does not establish timing or hardware operation.'}
    try:
        if not project.is_dir():
            raise ValueError('project directory does not exist')
        ini = project / 'efx_pnr_settings.ini'
        if not ini.is_file():
            report.update(result='SKIP', reason='No efx_pnr_settings.ini; no manual placement configured.')
            return report
        report['input_sha256']['efx_pnr_settings.ini'] = sha(ini)
        assignments = []
        for line in ini.read_text(encoding='utf-8-sig').splitlines():
            line = line.split('#', 1)[0].strip()
            if not line or line.startswith(';'):
                continue
            match = re.fullmatch(r'loc_assignment\s*=\s*(.*?)\s*', line)
            if match:
                assignments.append(match[1].strip('"\''))
            elif line.startswith('loc_assignment'):
                raise ValueError('malformed loc_assignment setting')
        if not assignments:
            report.update(result='SKIP', reason='No loc_assignment configured.')
            return report
        if len(assignments) != 1 or not assignments[0]:
            raise ValueError('expected exactly one nonempty loc_assignment')
        requested_path = local_file(project, assignments[0])
        requested_name = requested_path.relative_to(project).as_posix()
        report['input_sha256'][requested_name] = sha(requested_path)
        requested = parse_locations(requested_path)
        report['requested_cells'] = len(requested)
        xml = local_file(project, 'Case4_Ti60.xml')
        circuit = ET.parse(xml).getroot().get('name')
        if not circuit or not re.fullmatch(r'[A-Za-z0-9_.-]+', circuit):
            raise ValueError('invalid or missing circuit name in project XML')
        out = project / 'outflow'
        # Database files are required: a stale hand-copied .placeloc alone is
        # deliberately insufficient. Export reads these implementation outputs.
        required = [xml, local_file(project, f'outflow/{circuit}.place'),
                    local_file(project, f'outflow/{circuit}.netlist')]
        optional = [out / f'{circuit}.map.v', out / f'{circuit}.place.rpt',
                    out / f'{circuit}.timing.rpt']
        for path in required + [p for p in optional if p.is_file()]:
            report['input_sha256'][path.relative_to(project).as_posix()] = sha(path)
        # Official efx_export requires primplace in pnr_work_dir, even when
        # outflow .place/.netlist exist. Preserve just its small read-only input
        # databases under outflow so release packages may omit work_pnr.
        work = project / 'work_pnr'
        portable = out / 'placement_db'
        actual_path = out / f'{circuit}.verified.placeloc'
        if requested_path == actual_path or requested_path.is_relative_to(portable):
            raise ValueError('constraint file overlaps generated placement-check outputs')
        binding_path = portable / 'binding.json'
        db_names = [f'{circuit}.primplace', f'{circuit}.net_proto']
        watched = [work / name for name in db_names if (work / name).is_file()]
        work_hash = {p: sha(p) for p in watched}
        binding_inputs = {p.relative_to(project).as_posix(): sha(p) for p in required}
        if len(watched) == len(db_names):
            portable.mkdir(exist_ok=True)
            for source in watched:
                shutil.copyfile(source, portable / source.name)
            binding = {'format': 1, 'origin': 'official_pnr_work_database',
                       'input_sha256': binding_inputs,
                       'database_sha256': {p.name: work_hash[p] for p in watched}}
            binding_path.write_text(json.dumps(binding, indent=2) + '\n', encoding='utf-8')
            report['database_source'] = 'fresh_copy_of_work_pnr'
        elif watched:
            raise ValueError('incomplete work_pnr database; refuse a stale portable fallback')
        else:
            if not binding_path.is_file():
                raise ValueError('no work_pnr database and no verified portable placement_db')
            binding = json.loads(binding_path.read_text(encoding='utf-8'))
            report['database_source'] = 'portable_copy_bound_to_current_implementation'
        if binding.get('input_sha256') != binding_inputs:
            raise ValueError('portable placement database belongs to different implementation outputs')
        for name in db_names:
            path = portable / name
            if not path.is_file() or sha(path) != binding.get('database_sha256', {}).get(name):
                raise ValueError('portable placement database missing or changed: ' + name)
            report['input_sha256'][path.relative_to(project).as_posix()] = sha(path)
        report['input_sha256'][binding_path.relative_to(project).as_posix()] = sha(binding_path)
        exe = efinity_root.resolve() / 'bin' / ('efx_export.exe' if os.name == 'nt' else 'efx_export')
        if not exe.is_file():
            raise ValueError(f'official export utility not found: {exe}')
        report['exporter_sha256'] = sha(exe)
        env = os.environ.copy()
        env['EFINITY_HOME'] = str(efinity_root.resolve())
        # Export into a new temporary path, then publish. A failed export can
        # never accidentally reuse a previous PASS file.
        with tempfile.TemporaryDirectory(prefix='.placement-check-', dir=out) as tmp:
            fresh = Path(tmp) / 'actual.placeloc'
            command = [str(exe), '--prj', str(xml), '--pnr_work_dir', str(portable),
                       '--pnr_output_dir', str(out), '--placeloc', str(fresh)]
            completed = subprocess.run(command, cwd=tmp, env=env, capture_output=True,
                                       text=True, encoding='utf-8', errors='replace', timeout=120)
            report['export_returncode'] = completed.returncode
            report['export_log'] = (completed.stdout + completed.stderr).strip()[-12000:]
            if completed.returncode != 0 or not fresh.is_file():
                raise ValueError('official placement export failed; no actual coordinate evidence')
            actual = parse_locations(fresh)
            fresh.replace(actual_path)
        report['actual_dump'] = actual_path.relative_to(project).as_posix()
        report['actual_dump_sha256'] = sha(actual_path)
        report['actual_cells'] = len(actual)
        report['matched_cells'], report['mismatches'] = compare_locations(requested, actual)
        for name, before in report['input_sha256'].items():
            if sha(project / name) != before:
                report['errors'].append(f'input changed during export: {name}')
        for path, before in work_hash.items():
            if not path.is_file() or sha(path) != before:
                report['errors'].append('implementation database changed during export: ' + path.name)
        if report['matched_cells'] == len(requested) and not report['mismatches'] and not report['errors']:
            report['result'] = 'PASS'
        elif report['mismatches']:
            report['errors'].append('requested coordinates differ from actual exported placement')
    except (OSError, ValueError, ET.ParseError, subprocess.SubprocessError) as exc:
        report['errors'].append(str(exc))
    finally:
        if project.is_dir():
            (project / 'v12_placement_check.json').write_text(
                json.dumps(report, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('project', type=Path)
    parser.add_argument('--efinity-root', type=Path, default=Path('D:/'))
    args = parser.parse_args()
    result = check(args.project, args.efinity_root)
    print(json.dumps({key: result[key] for key in
                     ('result', 'requested_cells', 'matched_cells', 'actual_dump', 'mismatches', 'errors')},
                    indent=2, ensure_ascii=False))
    return 0 if result['result'] in ('PASS', 'SKIP') else 1


if __name__ == '__main__':
    raise SystemExit(main())
