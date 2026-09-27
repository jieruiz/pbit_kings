#!/usr/bin/env python3
"""Prepare an isolated 3x3 simulation; never modify synthesis RTL."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil


def prepare(source, dest, test):
    source, dest = Path(source).resolve(), Path(dest).resolve()
    if test not in ('rw', 'run3x3'):
        raise ValueError('Unknown test')
    if dest.exists() or dest == source or source / 'rtl' in dest.parents:
        raise ValueError('Destination must be a new isolated directory')
    mac = (source / 'rtl/new_version/mac.sv').read_text()
    if 'contrib_ff' not in mac or '(bias_rand_w < bias_prob_i)' not in mac:
        raise ValueError('Expected pipeline RTL with bias <')
    shutil.copytree(str(source / 'rtl'), str(dest / 'rtl'))
    target = dest / 'rtl'
    pkg = target / 'new_version/pbit_pkg.sv'
    text = pkg.read_text()
    for name in ('ROWS', 'COLS'):
        pattern = r'(parameter\s+int\s+' + name + r'\s*=\s*)\d+(\s*;)'
        text, count = re.subn(pattern, lambda m: m[1] + '3' + m[2], text)
        if count != 1:
            raise ValueError('Expected one parameter ' + name)
    pkg.write_text(text)
    tb = 'tb_rw_pipeline.sv' if test == 'rw' else 'tb_run3x3.sv'
    shutil.copyfile(str(source / 'pipeline_tb' / tb), str(target / 'tb' / tb))
    (target / 'test.f').write_text('-f filelist_pbit_top_chimera.f\ntb/' + tb + '\n')
    manifest = {'test': test, 'rows': 3, 'cols': 3, 'pbits': 72, 'files': []}
    for folder in ('new_version', 'common'):
        for path in sorted((target / folder).glob('*.sv')):
            original = source / 'rtl' / path.relative_to(target)
            before, after = original.read_bytes(), path.read_bytes()
            if path != pkg and before != after:
                raise ValueError('Unexpected RTL change')
            manifest['files'].append({'file': path.relative_to(target).as_posix(),
                                      'source_sha256': hashlib.sha256(before).hexdigest(),
                                      'simulation_sha256': hashlib.sha256(after).hexdigest()})
    (dest / 'manifest.json').write_text(json.dumps(manifest, indent=2))
    print('Prepared %s: %s' % (test, target))


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source', type=Path, required=True)
    p.add_argument('--dest', type=Path, required=True)
    p.add_argument('--test', choices=('rw', 'run3x3'), required=True)
    a = p.parse_args()
    prepare(a.source, a.dest, a.test)
