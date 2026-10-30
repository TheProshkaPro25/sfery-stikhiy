"""Reject retained-body folds in a dense, independently reset Godot pose audit."""
from pathlib import Path
import json
import sys

folder = Path(sys.argv[1]) / 'creature_rogozhuk_stone'
poses = json.loads((folder / 'poses.json').read_text())['poses']
samples = {(p['action'], p['frame']) for p in poses}
assert {a for a, _ in samples} == {'idle', 'appear', 'roar', 'attack', 'hit', 'brace', 'ability'}
for action in {a for a, _ in samples}:
    frames = sorted(f for a, f in samples if a == action)
    assert frames[0] == 0 and len(frames) > 2
    assert max(b - a for a, b in zip(frames, frames[1:])) <= 3, 'sparse pose audit'
    if action == 'idle':
        assert frames[-1] >= 720, 'sample at least twelve seconds of idle'
report = json.loads(Path(sys.argv[2]).read_text())
body = next(m for m in report if m['id'] == 'creature_rogozhuk_stone')
assert body['region'] == 'body', 'must measure both complete body surfaces'
assert {(p['action'], p['frame']) for p in body['poses']} == samples
assert max(p['pairs'] for p in body['poses']) == 0, 'body skin intersects itself'
print('Stone body:', len(samples), 'engine poses; no self-intersections')
