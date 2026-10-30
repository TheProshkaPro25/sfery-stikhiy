"""Require complete Light action/idle coverage and no body/rear self-intersections.

Usage: python tests/light_motion_integrity.py EXPORT_ROOT AUDIT_PART [AUDIT_PART...]
Audit parts come from audit_light_rest035.py. Deliberate body/root attachment
contacts are measured separately by beetle_attachment.py, not by a zero cross
count here.
"""
import json
from pathlib import Path
import sys

folder = Path(sys.argv[1]) / 'creature_rogozhuk_light'
source = json.loads((folder / 'poses.json').read_text())
expected = {(p['action'], p['frame']) for p in source['poses']}
actions = {'idle', 'appear', 'roar', 'attack', 'hit', 'brace', 'ability'}
assert {a for a, _ in expected} == actions, 'missing action coverage'
for action in actions:
    frames = sorted(f for a, f in expected if a == action)
    assert frames[0] == 0
    if action == 'idle':
        assert frames[-1] >= 720, 'sample at least twelve seconds of idle'
        assert max(b - a for a, b in zip(frames, frames[1:])) <= 6
    else:
        assert frames[-1] >= 30 and frames == list(range(frames[-1] + 1)), 'audit every action frame'
measured = {}
for path in sys.argv[2:]:
    for row in json.loads(Path(path).read_text()):
        key = (row['action'], row['frame'])
        value = (row['body'], row['rear'])
        assert key not in measured or measured[key] == value, 'inconsistent duplicate audit row'
        measured[key] = value
assert set(measured) == expected | {('rest', 0)}, 'pose exports and audit parts differ'
assert all(value == (0, 0) for value in measured.values()), 'body or rear surface intersects itself'
print('Light:', len(expected), 'engine poses plus raw rest; no body/rear self-intersections')
