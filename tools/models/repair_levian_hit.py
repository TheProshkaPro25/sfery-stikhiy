"""Limit the Light/Stone hit wing closure and Stone's stance neck curl.

Input is the separately validated front-binding candidate. Idle and all other
clips except Stone stance remain byte-for-byte equal. Stone also receives one measured raw-rest
coil sliver correction, including its two UV copies and nine local normals.
Writes a separate output directory; never installs production assets.
"""
import argparse
import json
import shutil
from pathlib import Path
import numpy as np
from inspect_geometry import read_glb, accessor, triangles
from upgrade_rigs import Writer, qmul, qconj, qfraction
from compact_glb import compact
from repair_beetles import smooth
from repair_levian_front import adjust_authored_normals


def stone_sliver(writer, data):
    parts = list(triangles(writer.doc, data))
    primitive, vertices, _ = parts[0]
    target = np.array([.22277632355690002, -.26772135496139526, -.13850851356983185])
    # Supporting plane through the opposite A1-A2 edge and B1. Moving B2
    # merely across A's face plane does not remove the edge intersection.
    plane = np.array([
        [.2205793261528015, -.273883581161499, -.13795995712280273],
        [.22176013886928558, -.26638662815093994, -.14004915952682495],
        [.22341793775558472, -.2710171341896057, -.13619638979434967],
    ])
    normal = np.cross(plane[1] - plane[0], plane[2] - plane[0])
    normal /= np.linalg.norm(normal)
    depth = float((target - plane[0]) @ normal)
    delta = (-.00002 - depth) * normal
    selected = np.linalg.norm(vertices - target, axis=1) < 1e-8
    assert np.flatnonzero(selected).tolist() == [81485, 81486]
    changed = vertices.copy()
    changed[selected] += delta
    assert np.linalg.norm(delta) < .00012
    faces = np.concatenate([part[2] for part in parts])
    _, uid = np.unique(np.round(vertices, 6), axis=0, return_inverse=True)
    affected = np.unique(uid[faces[np.any(selected[faces], axis=1)]])
    near = np.flatnonzero(np.isin(uid, affected))
    original_normals = accessor(writer.doc, data, primitive['attributes']['NORMAL'])
    values = adjust_authored_normals(vertices, changed, faces, original_normals, uid, near)
    changed_normals = np.flatnonzero(np.any(values != original_normals, axis=1))
    position_id, normal_id = writer.add(changed, 'VEC3'), writer.add(values, 'VEC3')
    for primitive, _, _ in parts:
        primitive['attributes']['POSITION'] = position_id
        primitive['attributes']['NORMAL'] = normal_id
    return dict(position_indices=np.flatnonzero(selected).tolist(), original_position=target.tolist(),
                new_position=changed[np.flatnonzero(selected)[0]].tolist(), delta=delta.tolist(),
                max_displacement=float(np.linalg.norm(delta)), edge_plane_distance=depth,
                target_clearance=-.00002, normal_indices=changed_normals.tolist(), normal_neighborhood_indices=near.tolist())


def repair(source, output):
    if source.stem not in ('levian_light', 'levian_stone'):
        shutil.copy2(source, output)
        return {'model': source.stem, 'unchanged': True}
    doc, data = read_glb(source)
    assert doc['asset']['extras'].get('sfery_front_binding_repair') == 1
    assert not doc['asset']['extras'].get('sfery_hit_wing_clearance')
    writer = Writer(doc, data)
    specs = [('hit', 'wing.R', .5)]
    if source.stem == 'levian_stone':
        specs.append(('stance', 'neck2', .75))
    found = 0
    for clip, bone, factor in specs:
        animation = next(a for a in doc['animations'] if a['name'] == clip)
        for channel in animation['channels']:
            node = doc['nodes'][channel['target']['node']]
            if node['name'] != bone or channel['target']['path'] != 'rotation':
                continue
            sampler = animation['samplers'][channel['sampler']]
            values = accessor(doc, data, sampler['output'])
            first = values[0].astype(float)
            # Constrain excursion relative to the clip entrance, NOT skeletal rest.
            # Hit starts 10 degrees open and closes to almost rest. Stone stance
            # previously curled the upper neck into the torso between frames40/48.
            factors = factor
            if clip == 'stance':
                times = accessor(doc, data, sampler['input']).ravel()
                progress = (times - times[0]) / (times[-1] - times[0])
                # Preserve the original exit with a smooth final15% transition,
                # rather than restoring only the last key and creating a jerk.
                factors = factor + (1 - factor) * smooth((progress - .85) / .15)
            result = qmul(first, qfraction(qmul(qconj(first), values), factors))
            result[0], result[-1] = values[0], values[-1]
            sampler['output'] = writer.add(result, 'VEC4')
            found += 1
    assert found == len(specs)
    report = {'model': source.stem, 'channels': [dict(clip=c, bone=b, excursion_factor=f) for c, b, f in specs]}
    if source.stem == 'levian_stone':
        report['coil_exception'] = stone_sliver(writer, data)
        report['channels'][-1]['restore_original_exit_after_fraction'] = .85
        doc['asset']['extras']['sfery_stone_coil_sliver_repair'] = 1
        doc['asset']['extras']['sfery_stone_stance_clearance'] = 1
    doc['asset']['extras']['sfery_hit_wing_clearance'] = 1
    writer.save(output)
    compact(output)
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    assert args.source.resolve() != args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    result = [repair(p, args.output / p.name) for p in sorted(args.source.glob('levian_*.glb'))]
    assert len(result) == 6
    (args.output / 'hit-repair-manifest.json').write_text(json.dumps(result, indent=2))
