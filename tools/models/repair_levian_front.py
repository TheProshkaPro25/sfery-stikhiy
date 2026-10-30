"""Repair the Levian neck bindings without changing skeletons or animation clips.

Requires the accepted tail031 models as --source; writes a separate --output.
The measured Tide foot sliver is the only positional exception. Godot pose
exports and Blender BVH audits remain required; this script is not acceptance.
"""
import argparse
import json
from pathlib import Path
import numpy as np
from inspect_geometry import read_glb, accessor, triangles
from upgrade_rigs import Writer, globals_of
from repair_beetles import store_weights, smooth
from repair_skin import smooth_surface_weights
from compact_glb import compact


def dense_weights(doc, data, primitive, count):
    weights = np.zeros((count, len(doc['skins'][0]['joints'])))
    for k in (0, 1):
        joints = accessor(doc, data, primitive['attributes'][f'JOINTS_{k}'])
        values = accessor(doc, data, primitive['attributes'][f'WEIGHTS_{k}'])
        np.add.at(weights, (np.arange(count)[:, None], joints), values)
    return weights


def soften_group(vertices, faces, weights, slots, sigma, blend):
    softened = smooth_surface_weights(vertices, faces, weights, sigma)[:, slots]
    mass = weights[:, slots].sum(1, keepdims=True)
    target = softened / np.maximum(softened.sum(1, keepdims=True), 1e-12) * mass
    weights[:, slots] = weights[:, slots] * (1 - blend[:, None]) + target * blend[:, None]


def adjust_authored_normals(vertices, changed, faces, values, uid, near):
    """Rotate authored normals by the local geometric change, preserving shading.

    Replacing imported custom normals with averaged face normals would change
    their authored direction by ~80 degrees around these tiny slivers. The
    actual geometric correction rotates the local average less than one degree.
    """
    pooled = []
    for positions in (vertices, changed):
        normals = np.zeros((uid.max() + 1, 3))
        tri = positions[faces]
        area = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
        for k in range(3):
            np.add.at(normals, uid[faces[:, k]], area)
        normals /= np.maximum(np.linalg.norm(normals, axis=1, keepdims=True), 1e-12)
        pooled.append(normals[uid[near]])
    before, after = pooled
    axis = np.cross(before, after)
    cosine = np.clip(np.sum(before * after, axis=1), -1, 1)
    assert np.min(cosine) > .999, 'Unexpectedly large local surface change'
    original = values[near].astype(float)
    rotated = original + np.cross(axis, original) + np.cross(axis, np.cross(axis, original)) / (1 + cosine[:, None])
    rotated /= np.maximum(np.linalg.norm(rotated, axis=1, keepdims=True), 1e-12)
    values = values.copy()
    values[near] = rotated
    return values


def tide_foot(writer, parts, data):
    primitive, vertices, _ = parts[0]
    target = np.array([-.10169771313667297, -.36870473623275757, .23471622169017792])
    triangle = np.array([
        [-.10300488770008087, -.3669070899486542, .23579281568527222],
        [-.10403567552566528, -.3699702024459839, .23374362289905548],
        [-.10027699917554855, -.36985838413238525, .23412400484085083],
    ])
    normal = np.cross(triangle[1] - triangle[0], triangle[2] - triangle[0])
    normal /= np.linalg.norm(normal)
    depth = float((target - triangle[0]) @ normal)
    delta = (.00001 - depth) * normal
    selected = np.linalg.norm(vertices - target, axis=1) < 1e-8
    assert np.flatnonzero(selected).tolist() == [22931, 22932, 22933], 'Unexpected Tide source topology'
    changed = vertices.copy()
    changed[selected] += delta
    faces = np.concatenate([part[2] for part in parts])
    _, uid = np.unique(np.round(vertices, 6), axis=0, return_inverse=True)
    affected = np.unique(uid[faces[np.any(selected[faces], axis=1)]])
    near = np.flatnonzero(np.isin(uid, affected))
    original_normals = accessor(writer.doc, data, primitive['attributes']['NORMAL'])
    values = adjust_authored_normals(vertices, changed, faces, original_normals, uid, near)
    changed_normals = np.flatnonzero(np.any(values != original_normals, axis=1))
    position_id = writer.add(changed, 'VEC3')
    normal_id = writer.add(values, 'VEC3')
    for primitive, _, _ in parts:
        primitive['attributes']['POSITION'] = position_id
        primitive['attributes']['NORMAL'] = normal_id
    return dict(position_indices=np.flatnonzero(selected).tolist(), original_position=target.tolist(),
                new_position=changed[np.flatnonzero(selected)[0]].tolist(), delta=delta.tolist(),
                max_displacement=float(np.linalg.norm(delta)), source_signed_penetration=depth,
                target_clearance=.00001, normal_indices=changed_normals.tolist(), normal_neighborhood_indices=near.tolist())


def repair(source, output, shadow_sigma):
    doc, data = read_glb(source)
    assert doc['asset'].get('extras', {}).get('sfery_tail_separation') == 2
    assert not doc['asset'].get('extras', {}).get('sfery_front_binding_repair'), 'Use preserved tail031 source'
    parts = list(triangles(doc, data))
    assert len(parts) == 2 and parts[0][0]['attributes']['POSITION'] == parts[1][0]['attributes']['POSITION']
    primitive, vertices, faces = parts[0]
    names = [doc['nodes'][n]['name'] for n in doc['skins'][0]['joints']]
    neck2 = globals_of(doc)[doc['skins'][0]['joints'][names.index('neck2')]][:3, 3]
    weights = dense_weights(doc, data, primitive, len(vertices))
    original = weights.copy()
    x, y, z = vertices.T
    # Preserve torso support, routing only early neck2 influence through neck1.
    # The left edge stops before every tail031 cap vertex, including Gale's rim.
    amount = smooth((y + .29) / .07) * smooth((z - .07) / .06) * smooth((x + .06) / .06)
    transition = smooth((y - (neck2[1] - .055)) / .11)
    move = weights[:, names.index('neck2')] * (1 - transition) * amount
    weights[:, names.index('neck2')] -= move
    weights[:, names.index('neck1')] += move
    # The central neck collar must not be pulled apart by opposite wing roots.
    collar = (smooth((.14 - np.abs(x - neck2[0])) / .055) * smooth((.10 - y) / .12)
              * smooth((y + .23) / .08) * smooth((z - .04) / .05))
    for wing in ('wing.L', 'wing.R'):
        move = weights[:, names.index(wing)] * collar
        weights[:, names.index(wing)] -= move
        weights[:, names.index('neck1')] += move * (1 - transition)
        weights[:, names.index('neck2')] += move * transition
    blend = (smooth((y + .32) / .11) * smooth((-.065 - y) / .055)
             * smooth((z - .01) / .11) * smooth((x + .06) / .06))
    soften_group(vertices, faces, weights, [names.index(n) for n in ('hips', 'neck1', 'neck2')], .035, blend)
    if source.stem == 'levian_shadow' and shadow_sigma:
        mask = smooth((.14 - np.linalg.norm(vertices - np.array([.25, .025, .08]), axis=1)) / .06)
        soften_group(vertices, faces, weights,
                     [names.index(n) for n in ('wing.R', 'wingtip.R', 'wingfan.R')], shadow_sigma, mask)
    cap_used = np.unique(parts[1][2])
    assert np.max(np.abs(weights[cap_used] - original[cap_used])) < 1e-12, 'Tail031 cap changed'
    writer = Writer(doc, data)
    store_weights(writer, primitive, weights)
    # Both surfaces share the same vertices and preserved rim weights.
    for key in ('JOINTS_0', 'JOINTS_1', 'WEIGHTS_0', 'WEIGHTS_1'):
        parts[1][0]['attributes'][key] = primitive['attributes'][key]
    report = dict(model=source.stem, changed_weight_vertices=int((np.abs(weights - original).max(1) > 1e-6).sum()),
                  shadow_sigma=shadow_sigma if source.stem == 'levian_shadow' else 0)
    if source.stem == 'levian_tide':
        report['foot_exception'] = tide_foot(writer, parts, data)
        doc['asset']['extras']['sfery_tide_foot_sliver_repair'] = 1
    doc['asset']['extras']['sfery_front_binding_repair'] = 1
    output.parent.mkdir(parents=True, exist_ok=True)
    writer.save(output)
    compact(output)
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--shadow-sigma', type=float, default=.1)
    args = parser.parse_args()
    assert args.source.resolve() != args.output.resolve()
    report = []
    for path in sorted(args.source.glob('levian_*.glb')):
        report.append(repair(path, args.output / path.name, args.shadow_sigma))
        print(report[-1]['model'], report[-1]['changed_weight_vertices'], flush=True)
    assert len(report) == 6, 'Expected all six accepted source models'
    (args.output / 'repair-manifest.json').write_text(json.dumps(report, indent=2))
