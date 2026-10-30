"""Validate the isolated hit/Stone-sliver delta against the neck-only candidate."""
import argparse
import json
import sys
from pathlib import Path
import numpy as np
import trimesh
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools/models'))
from inspect_geometry import read_glb, accessor, triangles

POINT = np.array([.22269491851329803, -.2676874101161957, -.13843266665935516], dtype=np.float32)
INDICES = [81485, 81486]
NORMALS = [80726, 81173, 81346, 81347, 81580, 81581, 81582]


def angular_distance(values, reference):
    values = values.astype(float)
    values /= np.linalg.norm(values, axis=1, keepdims=True)
    reference = reference.astype(float)
    reference /= np.linalg.norm(reference)
    return 2 * np.arccos(np.clip(np.abs(values @ reference), 0, 1))


def validate(source, candidate):
    if source.stem not in ('levian_light', 'levian_stone'):
        assert source.read_bytes() == candidate.read_bytes(), (source.name, 'unrelated model changed')
        return
    old, old_data = read_glb(source)
    doc, data = read_glb(candidate)
    for field in ('nodes', 'materials', 'textures', 'samplers'):
        assert doc.get(field) == old.get(field), (source.name, field)
    assert doc['asset']['extras']['sfery_hit_wing_clearance'] == 1
    assert len(doc['skins']) == len(old['skins'])
    for new_skin, old_skin in zip(doc['skins'], old['skins']):
        assert {k: v for k, v in new_skin.items() if k != 'inverseBindMatrices'} == {k: v for k, v in old_skin.items() if k != 'inverseBindMatrices'}
        assert np.array_equal(accessor(doc, data, new_skin['inverseBindMatrices']), accessor(old, old_data, old_skin['inverseBindMatrices']))
    # Embedded texture bytes, including mime metadata, must remain unchanged.
    for new_img, old_img in zip(doc['images'], old['images']):
        assert {k: v for k, v in new_img.items() if k != 'bufferView'} == {k: v for k, v in old_img.items() if k != 'bufferView'}
        nv, ov = doc['bufferViews'][new_img['bufferView']], old['bufferViews'][old_img['bufferView']]
        ns, os = nv.get('byteOffset', 0), ov.get('byteOffset', 0)
        assert data[ns:ns + nv['byteLength']] == old_data[os:os + ov['byteLength']]
    changed_channels = []
    assert len(doc['animations']) == len(old['animations'])
    for new_anim, old_anim in zip(doc['animations'], old['animations']):
        assert new_anim['name'] == old_anim['name'] and new_anim['channels'] == old_anim['channels']
        assert len(new_anim['samplers']) == len(old_anim['samplers'])
        for index, (ns, previous) in enumerate(zip(new_anim['samplers'], old_anim['samplers'])):
            assert ns.get('interpolation', 'LINEAR') == previous.get('interpolation', 'LINEAR')
            assert np.array_equal(accessor(doc, data, ns['input']), accessor(old, old_data, previous['input']))
            values, original = accessor(doc, data, ns['output']), accessor(old, old_data, previous['output'])
            if np.array_equal(values, original):
                continue
            targets = [c['target'] for c in new_anim['channels'] if c['sampler'] == index]
            assert len(targets) == 1
            target = targets[0]
            bone = doc['nodes'][target['node']]['name']
            factor = .5 if new_anim['name'] == 'hit' and bone == 'wing.R' else .75 if source.stem == 'levian_stone' and new_anim['name'] == 'stance' and bone == 'neck2' else None
            assert factor is not None and target['path'] == 'rotation'
            assert np.array_equal(values[[0, -1]], original[[0, -1]]), 'Hit entrance/exit changed'
            before, after = angular_distance(original, original[0]), angular_distance(values, original[0])
            factors = factor
            if new_anim['name'] == 'stance':
                times = accessor(old, old_data, previous['input']).ravel()
                progress = (times - times[0]) / (times[-1] - times[0])
                fade = np.clip((progress - .85) / .15, 0, 1)
                factors = factor + (1 - factor) * fade * fade * (3 - 2 * fade)
            assert np.max(np.abs(after - before * factors)) < 2e-6
            assert np.max(np.abs(np.linalg.norm(values, axis=1) - 1)) < 2e-6
            changed_channels.append((new_anim['name'], bone))
    expected = [('hit', 'wing.R')] + ([('stance', 'neck2')] if source.stem == 'levian_stone' else [])
    assert sorted(changed_channels) == sorted(expected)
    parts, old_parts = list(triangles(doc, data)), list(triangles(old, old_data))
    assert len(parts) == len(old_parts) == 2
    for (p, vertices, faces), (op, previous, old_faces) in zip(parts, old_parts):
        assert np.array_equal(faces, old_faces)
        changed = np.flatnonzero(np.any(vertices != previous, axis=1)).tolist()
        if source.stem == 'levian_stone':
            assert changed == INDICES and np.array_equal(vertices[INDICES], np.repeat(POINT[None], 2, axis=0))
            assert np.max(np.linalg.norm(vertices - previous, axis=1)) < .00012
        else:
            assert not changed
        for field in op['attributes']:
            if field == 'POSITION':
                continue
            values, original = accessor(doc, data, p['attributes'][field]), accessor(old, old_data, op['attributes'][field])
            if field == 'NORMAL' and source.stem == 'levian_stone':
                assert np.flatnonzero(np.any(values != original, axis=1)).tolist() == NORMALS
                assert np.max(np.abs(np.linalg.norm(values[NORMALS], axis=1) - 1)) < 1e-6
                a, b = values[NORMALS].astype(float), original[NORMALS].astype(float)
                cosine = np.sum(a * b, axis=1) / (np.linalg.norm(a, axis=1) * np.linalg.norm(b, axis=1))
                assert np.min(cosine) > np.cos(np.deg2rad(1)), 'Authored coil shading changed excessively'
            else:
                assert np.array_equal(values, original), (source.name, field, 'changed')
    mesh = trimesh.Trimesh(parts[0][1], np.concatenate([p[2] for p in parts]), process=True)
    assert mesh.is_watertight and mesh.is_winding_consistent and mesh.area_faces.min() > 0
    print(source.stem, 'PASS: exact reaction channels; bounded Stone point; weights, idle and other clips protected', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--models', type=Path, required=True)
    parser.add_argument('--pose-report', type=Path, action='append', default=[])
    args = parser.parse_args()
    paths = sorted(args.models.glob('levian_*.glb'))
    assert len(paths) == 6
    for path in paths:
        validate(args.source / path.name, path)
    for report_path in args.pose_report:
        report = json.loads(report_path.read_text())
        assert report and all(model['poses'] for model in report)
        assert all(p['pairs'] == 0 for model in report for p in model['poses']), str(report_path)
        print('PASS actual pose BVH:', report_path, sum(len(m['poses']) for m in report))
