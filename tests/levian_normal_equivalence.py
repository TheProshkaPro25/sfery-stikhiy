"""Prove that final lighting cleanup changes only the measured custom normals.

All other GLB JSON and binary bytes must match the previously audited models.
Optional Godot exports also require identical imported surfaces and palettes.
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools/models'))
from inspect_geometry import read_glb, accessor, triangles

ALLOWED = {
    'levian_stone': [80726, 81173, 81346, 81347, 81485, 81486, 81580, 81581, 81582],
    'levian_tide': [22790, 22791, 22931, 22932, 22933, 23021, 23022, 23093, 23094, 23145, 23146],
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source', type=Path, required=True)
parser.add_argument('--models', type=Path, required=True)
parser.add_argument('--authored-source', type=Path, required=True)
parser.add_argument('--source-poses', type=Path)
parser.add_argument('--poses', type=Path)
parser.add_argument('--report', type=Path, required=True)
args = parser.parse_args()
rows = []
for path in sorted(args.models.glob('levian_*.glb')):
    doc, data = read_glb(path)
    old, old_data = read_glb(args.source / path.name)
    authored, authored_data = read_glb(args.authored_source / path.name)
    assert doc == old, (path.name, 'GLB metadata, topology, channels or accessor layout changed')
    new_parts = list(triangles(doc, data))
    attr = new_parts[0][0]['attributes']['NORMAL']
    values, previous = accessor(doc, data, attr), accessor(old, old_data, attr)
    changed = np.flatnonzero(np.any(values != previous, axis=1)).tolist()
    assert changed == ALLOWED.get(path.stem, []), (path.name, 'unexpected normal rows')
    # Erase only the exact changed normal scalars before comparing every byte.
    current_bytes, old_bytes = bytearray(data), bytearray(old_data)
    a = doc['accessors'][attr]
    view = doc['bufferViews'][a['bufferView']]
    assert a['componentType'] == 5126 and a['type'] == 'VEC3'
    start = view.get('byteOffset', 0) + a.get('byteOffset', 0)
    stride = view.get('byteStride', 12)
    for vertex in changed:
        offset = start + vertex * stride
        current_bytes[offset:offset + 12] = old_bytes[offset:offset + 12]
    assert current_bytes == old_bytes, (path.name, 'a non-normal binary value changed')
    angle = 0.0
    if changed:
        authored_attr = next(triangles(authored, authored_data))[0]['attributes']['NORMAL']
        reference = accessor(authored, authored_data, authored_attr)[changed].astype(float)
        actual = values[changed].astype(float)
        cosine = np.sum(reference * actual, axis=1) / (np.linalg.norm(reference, axis=1) * np.linalg.norm(actual, axis=1))
        angle = float(np.rad2deg(np.arccos(np.clip(cosine, -1, 1))).max())
        assert angle < 1, (path.name, 'authored shading changed excessively', angle)
    row = dict(model=path.stem, sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
               changed_normal_indices=changed, max_degrees_from_authored_normals=angle,
               all_other_json_and_binary_bytes_identical=True)
    if args.poses:
        folder = args.poses / ('creature_' + path.stem)
        baseline = args.source_poses / folder.name
        document = json.loads((folder / 'poses.json').read_text())
        assert document == json.loads((baseline / 'poses.json').read_text())
        for exported in folder.glob('*.bin'):
            assert exported.read_bytes() == (baseline / exported.name).read_bytes(), exported.name
        row['identical_actual_game_poses'] = len(document['poses'])
    rows.append(row)
    print(path.stem, 'PASS: only', len(changed), 'normal rows; authored angle', round(angle, 4), flush=True)
assert len(rows) == 6
args.report.write_text(json.dumps(rows, indent=2))
