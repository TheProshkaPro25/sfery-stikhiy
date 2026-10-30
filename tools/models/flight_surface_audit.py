"""Measure actual animated leg surfaces, rather than only bone/foot orientation.

Input is an export from tools/deformation_audit.gd. Reports every sampled pose
on edges substantially attached to a leg, excluding tiny tessellation edges.
These measurements diagnose deformation; they do not approve artistic quality.
"""
import json
import sys
from pathlib import Path
import numpy as np


def measure(folder):
    doc = json.loads((folder / 'poses.json').read_text())
    results = []
    for mesh in doc['meshes']:
        prefix = folder / mesh['prefix']
        def read(name, dtype):
            return np.fromfile(str(prefix) + '_' + name + '.bin', dtype)
        vertices = read('vertices', np.float32).reshape(-1, 3)
        joints = read('joints', np.int32).reshape(-1, mesh['stride'])
        weights = read('weights', np.float32).reshape(joints.shape)
        faces = read('indices', np.int32).reshape(-1, 3)
        edges = np.unique(np.sort(np.concatenate([faces[:, [0, 1]], faces[:, [1, 2]], faces[:, [2, 0]]]), axis=1), axis=0)
        lengths = np.linalg.norm(vertices[edges[:, 0]] - vertices[edges[:, 1]], axis=1)
        leg = np.array([name.startswith(('thigh.', 'shin.', 'foot.', 'toe.')) for name in mesh['bones']])
        influence = (leg[joints] * weights).sum(1)
        selected = (lengths > np.ptp(vertices, axis=0).max() * .001) & (influence[edges].max(1) > .7)
        edges, lengths = edges[selected], lengths[selected]
        if not len(edges):
            continue
        for pose in doc['poses']:
            palette = np.asarray(pose['palettes'][mesh['mi']]).reshape(-1, 3, 4)
            deformed = np.zeros_like(vertices)
            for k in range(joints.shape[1]):
                matrices = palette[joints[:, k]]
                deformed += (np.einsum('nij,nj->ni', matrices[:, :, :3], vertices) + matrices[:, :, 3]) * weights[:, k, None]
            ratio = np.linalg.norm(deformed[edges[:, 0]] - deformed[edges[:, 1]], axis=1) / lengths
            results.append(dict(action=pose['action'], frame=pose['frame'], max=float(ratio.max()), p999=float(np.quantile(ratio, .999)), edges=int(len(edges))))
    return dict(id=doc['id'], worst=sorted(results, key=lambda row: row['max'], reverse=True)[:8])


if __name__ == '__main__':
    root = Path(sys.argv[1])
    report = [measure(folder) for folder in sorted(root.iterdir()) if (folder / 'poses.json').exists()]
    Path(str(root) + '-legs.json').write_text(json.dumps(report, indent=2))
    for item in report:
        print(item['id'], item['worst'][:1], flush=True)
