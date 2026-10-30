"""Protect tail031, mesh appearance, skeleton and clips during front-binding repair.

Use --source for the immutable accepted031 copies and --models for a candidate.
Optional --neck-audit and --lower-audit consume actual Godot/Blender reports.
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path
import numpy as np
import trimesh

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools/models'))
from inspect_geometry import read_glb, accessor, triangles
from repair_levian_front import dense_weights

TIDE_POINT = np.array([-.10170020163059235, -.36872413754463196, .23474648594856262], dtype=np.float32)
TIDE_INDICES = [22931, 22932, 22933]
TIDE_NORMALS = [22790, 22791, 23021, 23022, 23093, 23094, 23145, 23146]


def embedded_images(doc, binary):
    result = []
    for image in doc['images']:
        view = doc['bufferViews'][image['bufferView']]
        offset = view.get('byteOffset', 0)
        result.append(hashlib.sha256(binary[offset:offset + view['byteLength']]).hexdigest())
    return result


def validate(source, path):
    old, old_data = read_glb(source)
    doc, data = read_glb(path)
    assert doc['asset']['extras']['sfery_front_binding_repair'] == 1
    assert doc['nodes'] == old['nodes'], (path.name, 'skeleton or rest transforms changed')
    assert doc['materials'] == old['materials']
    assert doc['textures'] == old['textures']
    assert embedded_images(doc, data) == embedded_images(old, old_data), (path.name, 'texture changed')
    for new_skin, old_skin in zip(doc['skins'], old['skins']):
        assert {k: v for k, v in new_skin.items() if k != 'inverseBindMatrices'} == {k: v for k, v in old_skin.items() if k != 'inverseBindMatrices'}
        assert np.array_equal(accessor(doc, data, new_skin['inverseBindMatrices']), accessor(old, old_data, old_skin['inverseBindMatrices']))
    assert len(doc['animations']) == len(old['animations'])
    for new_anim, old_anim in zip(doc['animations'], old['animations']):
        assert new_anim['channels'] == old_anim['channels'] and new_anim.get('name') == old_anim.get('name')
        assert len(new_anim['samplers']) == len(old_anim['samplers'])
        for new_sampler, old_sampler in zip(new_anim['samplers'], old_anim['samplers']):
            assert new_sampler.get('interpolation', 'LINEAR') == old_sampler.get('interpolation', 'LINEAR')
            for field in ('input', 'output'):
                assert np.array_equal(accessor(doc, data, new_sampler[field]), accessor(old, old_data, old_sampler[field])), (path.name, 'clip changed')
    parts, old_parts = list(triangles(doc, data)), list(triangles(old, old_data))
    assert len(parts) == len(old_parts) == 2
    for number, ((primitive, vertices, faces), (old_primitive, old_vertices, old_faces)) in enumerate(zip(parts, old_parts)):
        assert np.array_equal(faces, old_faces), (path.name, 'triangles changed')
        assert primitive.get('material') == old_primitive.get('material')
        changed = np.flatnonzero(np.any(vertices != old_vertices, axis=1)).tolist()
        if path.stem == 'levian_tide':
            assert changed == TIDE_INDICES
            assert np.array_equal(vertices[TIDE_INDICES], np.repeat(TIDE_POINT[None], 3, axis=0))
            assert np.linalg.norm(vertices - old_vertices, axis=1).max() < .000037
        else:
            assert not changed, (path.name, 'unexpected position edit')
        for attr in old_primitive['attributes']:
            if attr.startswith(('JOINTS_', 'WEIGHTS_')) or attr == 'POSITION':
                continue
            new_values = accessor(doc, data, primitive['attributes'][attr])
            old_values = accessor(old, old_data, old_primitive['attributes'][attr])
            if attr == 'NORMAL' and path.stem == 'levian_tide':
                assert np.flatnonzero(np.any(new_values != old_values, axis=1)).tolist() == TIDE_NORMALS
                assert np.max(np.abs(np.linalg.norm(new_values[TIDE_NORMALS], axis=1) - 1)) < 1e-6
                a, b = new_values[TIDE_NORMALS].astype(float), old_values[TIDE_NORMALS].astype(float)
                cosine = np.sum(a * b, axis=1) / (np.linalg.norm(a, axis=1) * np.linalg.norm(b, axis=1))
                assert np.min(cosine) > np.cos(np.deg2rad(1)), 'Authored foot shading changed excessively'
            else:
                assert np.array_equal(new_values, old_values), (path.name, attr)
        weights = dense_weights(doc, data, primitive, len(vertices))
        previous = dense_weights(old, old_data, old_primitive, len(vertices))
        assert np.isfinite(weights).all() and np.min(weights) >= 0
        assert np.max(np.abs(weights.sum(1) - 1)) < 2e-6
        # Coil/tail influences are invariant everywhere, including blended joins.
        names = [doc['nodes'][n]['name'] for n in doc['skins'][0]['joints']]
        tail_slots = [i for i, name in enumerate(names) if name.startswith('coil') or name == 'tail']
        assert np.max(np.abs(weights[:, tail_slots] - previous[:, tail_slots])) < 2e-6
        # Left tail, cap rim, low feet and actual upper-head skin are protected.
        # Upper left/right wing roots are deliberately included in the collar repair.
        protected = ((old_vertices[:, 0] <= -.06) & (old_vertices[:, 1] < -.1)) | (old_vertices[:, 1] <= -.32)
        protected |= (old_vertices[:, 1] >= .10) & (previous[:, names.index('head')] > .5)
        if number == 1:
            protected[np.unique(faces)] = True
        assert np.max(np.abs(weights[protected] - previous[protected])) < 2e-6, (path.name, 'protected skin changed')
        _, uid = np.unique(np.round(vertices, 6), axis=0, return_inverse=True)
        order = np.argsort(uid)
        adjacent = uid[order[1:]] == uid[order[:-1]]
        assert np.max(np.abs(weights[order[1:][adjacent]] - weights[order[:-1][adjacent]])) < 2e-6, (path.name, 'UV seam split')
    mesh = trimesh.Trimesh(parts[0][1], np.concatenate([p[2] for p in parts]), process=True)
    assert mesh.is_watertight and mesh.is_winding_consistent
    assert mesh.area_faces.min() > 0
    print(path.stem, 'PASS: protected tail and seams; geometry exception bounded; original rig, clips and texture retained', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--models', type=Path, required=True)
    parser.add_argument('--neck-audit', type=Path)
    parser.add_argument('--lower-audit', type=Path)
    args = parser.parse_args()
    paths = sorted(args.models.glob('levian_*.glb'))
    assert len(paths) == 6
    for path in paths:
        validate(args.source / path.name, path)
    if args.neck_audit:
        report = json.loads(args.neck_audit.read_text())
        assert len(report) == 6
        for model in report:
            assert len(model['poses']) == 67
            assert max(p['pairs'] for p in model['poses']) == 0, model['id']
        print('PASS: bounded neck/collar/Shadow wing-root region, 402 actual game poses')
    if args.lower_audit:
        report = json.loads(args.lower_audit.read_text())
        assert len(report) == 6
        for model in report:
            assert len(model['poses']) == 67
            assert max(p['pairs_touching_caps'] for p in model['poses']) == 0
            assert max(p['pairs_touching_tail_tip'] for p in model['poses']) == 0
            print(model['id'], 'remaining lower-region maximum', max(p['pairs'] for p in model['poses']))
        print('PASS: tail031 cap/tip retained; other lower-region intersections reported separately')
