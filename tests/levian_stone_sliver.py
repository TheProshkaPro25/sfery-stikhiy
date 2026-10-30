"""Blender negative/positive control for the intrinsic Stone coil overlap.

blender -b --factory-startup -P tests/levian_stone_sliver.py -- BEFORE.glb AFTER.glb REPORT.json
Tests raw rest triangles, independently of game animation and skin palettes.
"""
import json
import os
import sys
from pathlib import Path
import numpy as np
from mathutils.bvhtree import BVHTree
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools/models'))
from inspect_geometry import read_glb, triangles


def raw_pairs(path):
    doc, data = read_glb(path)
    _, vertices, faces = next(triangles(doc, data))
    faces = faces[vertices[faces, 1].max(1) < -.10]
    _, uid = np.unique(np.round(vertices, 6), axis=0, return_inverse=True)
    tree = BVHTree.FromPolygons(vertices.tolist(), faces.tolist(), all_triangles=True, epsilon=0)
    pairs = [(a, b) for a, b in tree.overlap(tree) if a < b and not set(uid[faces[a]]) & set(uid[faces[b]])]
    return {'pairs': len(pairs), 'triangles': len(faces), 'coordinates': vertices[faces[np.asarray(pairs, dtype=int).reshape(-1, 2)]].tolist()}


args = sys.argv[sys.argv.index('--') + 1:]
before, after = raw_pairs(args[0]), raw_pairs(args[1])
report = {'before': before, 'after': after, 'pass': before['pairs'] == 1 and after['pairs'] == 0}
Path(args[2]).write_text(json.dumps(report, indent=2))
print('Stone raw rest control:', before['pairs'], '->', after['pairs'], flush=True)
sys.stdout.flush()
os._exit(0 if report['pass'] else 1)
