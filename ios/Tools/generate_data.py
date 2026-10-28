#!/usr/bin/env python3
"""Generate the bundled data files for the AstroHopper iOS app.

Produces, in the output directory:

- catalog.json - stars, DSOs, planets and constellations (same selection as
  the web app's jsdb.js, built by create_data.py from the git submodules)
- vsop87a.json - the truncated VSOP87A series used for planet positions,
  extracted from vsop87a_combined.js

Usage: generate_data.py <output-dir>   (run from anywhere; paths are resolved
relative to the repository root)
"""

import json
import os
import re
import sys

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))


def round_floats(v):
    if isinstance(v, float):
        r = round(v, 4)
        return int(r) if r == int(r) else r
    if isinstance(v, list):
        return [round_floats(x) for x in v]
    if isinstance(v, dict):
        return {k: round_floats(x) for k, x in v.items()}
    return v


def make_catalog():
    sys.path.insert(0, REPO_ROOT)
    import create_data

    objects = create_data.DSODB()
    create_data.get_OpenNGC_DSO(objects)
    create_data.get_planets(objects)
    mapping = create_data.get_stars(objects)
    cnames = create_data.get_constellation_names()
    lines = create_data.get_constellation_lines(mapping, cnames, objects)
    db, index, _ = objects.json
    return round_floats({
        'objects': db,
        'typeEnd': index,
        'lines': [[l['r0'], l['d0'], l['r1'], l['d1']] for l in lines],
    })


def make_vsop87():
    """Extract {body: {coord: [[power, [[A, B, C], ...]], ...]}} from the
    vsop87a_xsmall class (its Earth and EMB series are the 'large' ones)."""
    with open(os.path.join(REPO_ROOT, 'vsop87a_combined.js'), encoding='utf-8') as f:
        src = f.read()
    src = src[:src.index('class vsop87a_milli_velocities')]
    func = re.compile(r'static (\w+)_([xyz])\(t\)\{(.*?)\n   \}', re.S)
    term = re.compile(r'(\w+)_[xyz]_(\d+) \+= ([-0-9.e]+) \* Math\.cos\(([-0-9.e]+) \+ ([-0-9.e]+)\*t\);')
    result = {}
    for m in func.finditer(src):
        body, coord, text = m.group(1), m.group(2), m.group(3)
        series = {}
        for t in term.finditer(text):
            power = int(t.group(2))
            series.setdefault(power, []).append([float(t.group(3)), float(t.group(4)), float(t.group(5))])
        result.setdefault(body, {})[coord] = [[p, series[p]] for p in sorted(series)]
    return result


def write_if_changed(path, content):
    if os.path.exists(path):
        with open(path, encoding='utf-8') as f:
            if f.read() == content:
                return
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)
    print('Wrote %s' % path)


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(REPO_ROOT, 'ios', 'AstroHopper', 'Generated')
    os.makedirs(out_dir, exist_ok=True)
    os.chdir(REPO_ROOT)  # create_data.py uses paths relative to the repo root
    write_if_changed(os.path.join(out_dir, 'catalog.json'), json.dumps(make_catalog(), separators=(',', ':')))
    write_if_changed(os.path.join(out_dir, 'vsop87a.json'), json.dumps(make_vsop87(), separators=(',', ':')))


if __name__ == '__main__':
    main()
