"""Check nonadjacent surface triangle overlaps in exported Godot poses.

Run with Blender: blender -b --factory-startup -P this_file -- ROOT REPORT
Optional third argument: tail (otherwise leg skin). Reports all exported poses,
including zero counts. This is a geometric diagnostic, not visual acceptance.
"""
import json
import sys
from pathlib import Path
import numpy as np
from mathutils.bvhtree import BVHTree

args = sys.argv[sys.argv.index('--') + 1:]
root, output = map(Path, args[:2])
region = args[2] if len(args) > 2 else 'legs'
report = []
for folder in sorted(root.iterdir()):
    if not (folder / 'poses.json').exists():
        continue
    doc = json.loads((folder / 'poses.json').read_text())
    meshes, faces, original, offset = [], [], [], 0
    cap_faces, tip_faces = [], []
    for mesh in doc['meshes']:
        prefix = folder / mesh['prefix']
        def read(name, dtype):
            return np.fromfile(str(prefix) + '_' + name + '.bin', dtype)
        v = read('vertices', np.float32).reshape(-1, 3)
        j = read('joints', np.int32).reshape(-1, mesh['stride'])
        w = read('weights', np.float32).reshape(j.shape)
        f = read('indices', np.int32).reshape(-1, 3)
        if region == 'body':
            # Reconstructed beetles store the body exterior and its caps first;
            # new rear limbs deliberately overlap the body at their roots.
            selected = np.full(len(f), len(meshes) < 2)
        elif region == 'rear':
            if len(doc['meshes']) == 6:
                selected = np.full(len(f), len(meshes) >= 2)
            else:
                leg = np.array([n.startswith('rear_') for n in mesh['bones']])
                selected = ((leg[j] * w).sum(1)[f].max(1) > .5)
        elif region == 'tail':
            selected = (v[f, 1].max(1) < -.10)
        else:
            leg = np.array([n.startswith(('thigh.', 'shin.', 'foot.')) for n in mesh['bones']])
            selected = ((leg[j] * w).sum(1)[f].max(1) > .5)
        if region == 'tail':
            cap_faces.append(np.full(int(selected.sum()), mesh['prefix'].endswith('_1')))
            # Coordinates use the exported mesh-local vertex frame. Do not
            # assume that scene-axis conversion reflects these vertex arrays.
            tip = (v[:, 0] < -.14) & (v[:, 1] < -.15) & (v[:, 2] > -.041) & (v[:, 2] < .22)
            tip_faces.append(tip[f[selected]].any(1))
        # Imported shared accessors can repeat the full mesh for a tiny cap.
        # Skin only vertices referenced by the measured region.
        used, remapped = np.unique(f[selected], return_inverse=True)
        faces.append(remapped.reshape(-1, 3) + offset)
        original.append(v[used])
        meshes.append((mesh, v[used], j[used], w[used]))
        offset += len(used)
    faces = np.concatenate(faces)
    _, uid = np.unique(np.round(np.concatenate(original), 6), axis=0, return_inverse=True)
    changed = None
    if len(args) > 3:
        baseline = Path(args[3]) / folder.name
        old_doc = json.loads((baseline / 'poses.json').read_text())
        old_v, old_f, old_offset = [], [], 0
        for mesh in old_doc['meshes'][:2]:
            prefix = baseline / mesh['prefix']
            v = np.fromfile(str(prefix) + '_vertices.bin', np.float32).reshape(-1, 3)
            f = np.fromfile(str(prefix) + '_indices.bin', np.int32).reshape(-1, 3)
            old_v.append(v); old_f.append(f + old_offset); old_offset += len(v)
        current_v = np.concatenate(original)
        _, combined = np.unique(np.round(np.concatenate([current_v] + old_v), 6), axis=0, return_inverse=True)
        old_keys = set(map(tuple, np.sort(combined[len(current_v):][np.concatenate(old_f)], axis=1)))
        changed = np.array([tuple(key) not in old_keys for key in np.sort(combined[:len(current_v)][faces], axis=1)])
    rows = []
    for pose in doc['poses']:
        vertices = []
        for mesh, v, j, w in meshes:
            palette = np.asarray(pose['palettes'][mesh['mi']]).reshape(-1, 3, 4)
            pos = np.zeros_like(v)
            for k in range(j.shape[1]):
                matrices = palette[j[:, k]]
                pos += (np.einsum('nij,nj->ni', matrices[:, :, :3], v) + matrices[:, :, 3]) * w[:, k, None]
            vertices.append(pos)
        vertices = np.concatenate(vertices)
        tree = BVHTree.FromPolygons(vertices.tolist(), faces.tolist(), all_triangles=True, epsilon=0)
        pairs = np.array([(a, b) for a, b in tree.overlap(tree) if a < b], dtype=int).reshape(-1, 2)
        if len(pairs):
            adjacent = (uid[faces[pairs[:, 0]]][:, :, None] == uid[faces[pairs[:, 1]]][:, None, :]).any((1, 2))
            pairs = pairs[~adjacent]
        row = dict(action=pose['action'], frame=pose['frame'], pairs=len(pairs))
        if region == 'tail':
            row['pairs_touching_caps'] = int(np.concatenate(cap_faces)[pairs].any(1).sum())
            row['pairs_touching_tail_tip'] = int(np.concatenate(tip_faces)[pairs].any(1).sum())
        if changed is not None:
            row['pairs_touching_changed_faces'] = int(changed[pairs].any(1).sum())
        rows.append(row)
    report.append(dict(id=doc['id'], region=region, poses=rows))
    print(doc['id'], 'poses', len(rows), 'worst', max(rows, key=lambda r: r['pairs']), flush=True)
output.write_text(json.dumps(report, indent=2))
# Batch Blender can hang in audio/backend teardown in the headless environment.
# All report data has been written; do not leave an idle Blender process behind.
import os
sys.stdout.flush()
os._exit(0)
