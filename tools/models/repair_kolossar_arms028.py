"""Reduce excessive right elbow/shoulder motion while preserving each rig's rest pose.
Only stance (appear) and attack rotation samples are changed; geometry is untouched.
"""
from pathlib import Path
import shutil
import numpy as np
from inspect_geometry import read_glb, accessor
from upgrade_rigs import Writer, qmul, qconj, qfraction

root = Path(__file__).resolve().parents[2]
backup = root / 'tools/_tmp/kolossar-arms028-base'
backup.mkdir(parents=True, exist_ok=True)
for path in sorted((root / 'assets/creatures_hd').glob('kolossar_*.glb')):
    original = backup / path.name
    if original.exists():
        raise RuntimeError(f'Backup already exists: {original}; refusing a second application')
    shutil.copy2(path, original)
    doc, data = read_glb(path)
    writer = Writer(doc, data)
    changes = []
    for animation in doc.get('animations', []):
        if animation.get('name') not in ('stance', 'attack'):
            continue
        for channel in animation['channels']:
            node = doc['nodes'][channel['target']['node']]
            name = node.get('name', '')
            if channel['target']['path'] != 'rotation' or name not in ('arm.R', 'forearm.R'):
                continue
            factor = 0.75 if name == 'arm.R' else 0.45
            sampler = animation['samplers'][channel['sampler']]
            values = accessor(doc, data, sampler['output'])
            rest = np.asarray(node.get('rotation', [0, 0, 0, 1]), dtype=float)
            rest /= np.linalg.norm(rest)
            delta = qmul(qconj(rest), values)
            result = qmul(rest, qfraction(delta, factor))
            sampler['output'] = writer.add(result, 'VEC4')
            changes.append((animation['name'], name, factor))
    if len(changes) != 4:
        raise RuntimeError(f'{path.name}: expected four channels, got {changes}')
    writer.save(path)
    print(path.name, changes)
