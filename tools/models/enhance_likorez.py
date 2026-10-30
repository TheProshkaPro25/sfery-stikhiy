"""Likorez 0.2.8 choreography; edits animation data only, never rebinds the mesh.

Run with Python + numpy/scipy. The immutable 0.2.7 backup makes reruns stable.
Pitch, spread and twist use the character's axes, transformed into each joint's
rest frame. All clips share the same opening/closing guard. Idle is C1 periodic.
"""
import copy
import json
from pathlib import Path

import numpy as np
from scipy.spatial.transform import Rotation

from inspect_geometry import accessor, read_glb, triangles
from upgrade_rigs import Writer, add_channel, globals_of, matrix

ROOT = Path(__file__).resolve().parents[2]
TARGET = ROOT / 'assets/creatures_hd/likorez_shadow.glb'
BACKUP = ROOT / 'tools/_tmp/likorez028-base/likorez_shadow.glb'


def ease(t):
    t = np.clip(t, 0, 1)
    return t*t*(3-2*t)


def envelope(t, points):
    """Smooth anticipation, fast cut, held follow-through, controlled recovery."""
    for (a, va), (b, vb) in zip(points, points[1:]):
        if t <= b:
            return va+(vb-va)*ease((t-a)/(b-a))
    return points[-1][1]


def guard(t):
    phase = t*4*np.pi
    poses = {
        'hips': (2*np.sin(phase), 0, 4*np.sin(phase)),
        'chest': (-3*np.sin(phase+.35), 0, -7*np.sin(phase)),
        'neck': (1.5*np.sin(phase), 0, 3*np.sin(phase+.2)),
        'head': (3*np.sin(phase+.2), 0, 6*np.sin(phase+.7)),
    }
    for row in range(3):
        for side, sign in [('L', 1), ('R', -1)]:
            p = phase+row*1.25+sign*.6
            poses[f'arm{row}.{side}'] = (11*np.sin(p), 4*np.sin(p+.5), 8*np.sin(p+.7))
            poses[f'forearm{row}.{side}'] = (13*np.sin(p-.6), 0, 6*np.sin(p-.3))
            poses[f'hand{row}.{side}'] = (6*np.sin(p-1), 0, 8*np.sin(p+.9))
            poses[f'blade{row}.{side}'] = (0, 0, 0)
    for side, sign in [('L', 1), ('R', -1)]:
        # Two one-legged transfer cycles. The planted leg compresses slightly;
        # the free knee snaps up and unfolds through a smooth, broad apex.
        lift = max(0, sign*np.sin(phase))**2
        compression = max(0, -sign*np.sin(phase))**2
        poses['thigh.'+side] = (-31*lift+5*compression, 7*lift, 5*lift)
        poses['shin.'+side] = (46*lift-6*compression, 0, 0)
        poses['foot.'+side] = (-16*lift, 0, -5*lift)
    translation = np.array([.065*np.sin(phase), .045*np.sin(phase*2)**2, .018*np.sin(phase*2)])
    return poses, translation


def pose(clip, t):
    if clip == 'idle':
        return guard(t)
    poses, _ = guard(0)
    poses = {k: np.array(v, dtype=float) for k, v in poses.items()}
    movement = np.zeros(3)
    if clip == 'attack':
        wind = envelope(t, [(0, 0), (.19, 1), (.26, 1), (.36, 0), (1, 0)])
        drive = envelope(t, [(0, 0), (.23, 0), (.34, 1), (.57, 1), (1, 0)])
        poses['hips'] += [7*wind-6*drive, 0, -8*wind+10*drive]
        poses['chest'] += [-12*wind+20*drive, 0, 15*wind-22*drive]
        poses['head'] += [5*wind-12*drive, 0, -8*wind+10*drive]
        for row in range(3):
            for side, sign in [('L', 1), ('R', -1)]:
                delay = row*.035 + (0 if side == 'L' else .025)
                cut = envelope(t, [(0, 0), (.23+delay, 0), (.335+delay, 1), (.49+delay, 1), (1, 0)])
                poses[f'arm{row}.{side}'] += [19*wind-49*cut, 8*wind-12*cut, sign*(-12*wind+20*cut)]
                poses[f'forearm{row}.{side}'] += [17*wind-29*cut, 0, sign*9*cut]
                poses[f'hand{row}.{side}'] += [10*wind-16*cut, 0, -sign*14*cut]
        poses['thigh.L'] += [-15*drive, 3*drive, 0]
        poses['shin.L'] += [23*drive, 0, 0]
        poses['thigh.R'] += [8*drive, 0, 0]
        poses['shin.R'] += [-10*drive, 0, 0]
        movement = np.array([-.025*wind+.04*drive, .015*wind, .07*drive])
    else:
        env = np.sin(np.pi*t)**2
        if clip == 'hit':
            recoil = envelope(t, [(0, 0), (.2, 1), (.39, .8), (1, 0)])
            poses['hips'] += [-7*recoil, 0, 6*recoil]
            poses['chest'] += [-15*recoil, 0, -12*recoil]
            poses['head'] += [-10*recoil, 0, 15*recoil]
            movement[2] = -.035*recoil
        else:
            poses['chest'] += [-10*env, 0, 8*np.sin(2*np.pi*t)*env]
            poses['head'] += [-12*env, 0, -10*np.sin(2*np.pi*t)*env]
            poses['hips'] += [4*env, 0, 0]
        for row in range(3):
            for side, sign in [('L', 1), ('R', -1)]:
                poses[f'arm{row}.{side}'] += [-9*env if clip == 'hit' else 12*env, 10*env, sign*(row-1)*7*env]
                poses[f'forearm{row}.{side}'] += [14*env, 0, sign*6*env]
    return poses, movement


def enhance():
    BACKUP.parent.mkdir(parents=True, exist_ok=True)
    if not BACKUP.exists():
        BACKUP.write_bytes(TARGET.read_bytes())
    doc, binary = read_glb(BACKUP)
    original = copy.deepcopy(doc)
    rest = globals_of(doc)
    names = {n.get('name'): i for i, n in enumerate(doc['nodes'])}
    joints = doc['skins'][0]['joints']
    parent = {c: i for i, n in enumerate(doc['nodes']) for c in n.get('children', [])}
    inverse = accessor(doc, binary, doc['skins'][0]['inverseBindMatrices']).reshape(-1, 4, 4).transpose(0, 2, 1)
    geometry = []
    for prim, v, _ in triangles(doc, binary):
        geometry.append((np.c_[v, np.ones(len(v))], accessor(doc, binary, prim['attributes']['JOINTS_0']).astype(int), accessor(doc, binary, prim['attributes']['WEIGHTS_0'])))
    writer = Writer(doc, binary)
    report = {}
    doc['animations'] = []
    for clip, seconds in [('idle', 2), ('attack', 1.2), ('hit', .8), ('roar', 1.1), ('stance', 1.1)]:
        times = np.linspace(0, seconds, round(seconds*60)+1)
        rotations = {j: [] for j in joints}
        translations = []
        feet = []
        for time in times:
            poses, movement = pose(clip, time/seconds)
            local = [matrix(n) for n in doc['nodes']]
            for name, i in names.items():
                if i not in rotations:
                    continue
                pitch, spread, twist = poses.get(name, (0, 0, 0))
                sign = 1 if rest[i][0, 3] <= 0 else -1
                # glTF Y-up: pitch about +X, spread about -Z (forward), twist Y.
                world = Rotation.from_euler('XYZ', [pitch, sign*twist, -sign*spread], degrees=True).as_matrix()
                r = rest[i][:3, :3]
                delta = r.T@world@r
                local[i][:3, :3] = local[i][:3, :3]@delta
            if clip == 'idle':
                # The photographed legs have unequal depth/length. Equal Euler
                # bends lifted one foot 3x more than the other. Solve the authored
                # ankle lift geometrically, keeping the original knee pole.
                hip = names['hips']
                hip_world = local[names['root']]@local[hip]
                transform = hip_world@np.linalg.inv(rest[hip])
                def turn(a, b):
                    a = a/np.linalg.norm(a)
                    b = b/np.linalg.norm(b)
                    cross = np.cross(a, b)
                    angle = np.arctan2(np.linalg.norm(cross), np.dot(a, b))
                    return Rotation.from_rotvec(cross/max(np.linalg.norm(cross), 1e-12)*angle).as_matrix()
                for side, sign in [('L', 1), ('R', -1)]:
                    a, b, c = [names[p+side] for p in ['thigh.', 'shin.', 'foot.']]
                    reference = [transform@rest[j] for j in [a, b, c]]
                    A, B, C = [m[:3, 3] for m in reference]
                    lift = max(0, sign*np.sin(time/seconds*4*np.pi))**2
                    target = C+np.array([0, .20*lift, .035*lift])
                    upper, lower = np.linalg.norm(B-A), np.linalg.norm(C-B)
                    direction = target-A
                    distance = np.clip(np.linalg.norm(direction), abs(upper-lower)+1e-5, upper+lower-1e-5)
                    direction /= np.linalg.norm(direction)
                    pole = B-A-direction*np.dot(B-A, direction)
                    pole /= np.linalg.norm(pole)
                    along = (upper**2-lower**2+distance**2)/(2*distance)
                    knee = A+direction*along+pole*np.sqrt(max(0, upper**2-along**2))
                    ra = turn(B-A, knee-A)@reference[0][:3, :3]
                    rb = turn(C-B, target-knee)@reference[1][:3, :3]
                    local[a][:3, :3] = hip_world[:3, :3].T@ra
                    local[b][:3, :3] = ra.T@rb
                    local[c][:3, :3] = rb.T@reference[2][:3, :3]
            for i in joints:
                rotations[i].append(Rotation.from_matrix(local[i][:3, :3]).as_quat())
            cache = {}
            def global_at(i):
                if i not in cache:
                    cache[i] = (global_at(parent[i]) if i in parent else np.eye(4))@local[i]
                return cache[i]
            mats = np.array([global_at(j) for j in joints])@inverse
            floor = float('inf')
            for v, js, ws in geometry:
                skinned = np.zeros((len(v), 3))
                for slot in range(4):
                    skinned += np.einsum('nij,nj->ni', mats[js[:, slot]], v)[:, :3]*ws[:, slot, None]
                floor = min(floor, float(skinned[:, 1].min()))
            movement[1] -= floor
            translations.append(movement)
            feet.append([(global_at(names['foot.'+s])[:3, 3]+movement).tolist() for s in ['L', 'R']])
        animation = {'name': clip, 'samplers': [], 'channels': []}
        input_index = writer.add(times[:, None], 'SCALAR')
        doc['accessors'][input_index].update(min=[0], max=[seconds])
        for j, values in rotations.items():
            values = np.array(values)
            for f in range(1, len(values)):
                if np.dot(values[f-1], values[f]) < 0:
                    values[f] *= -1
            add_channel(writer, animation, j, 'rotation', input_index, values)
        add_channel(writer, animation, names['root'], 'translation', input_index, translations)
        doc['animations'].append(animation)
        feet = np.array(feet)
        report[clip] = {'frames': len(times), 'root_range': np.ptp(translations, axis=0).round(5).tolist(), 'foot_height_ranges': np.ptp(feet[:, :, 1], axis=0).round(5).tolist(), 'end_rotation_error': max(float(1-abs(np.dot(v[0], v[-1]))) for v in rotations.values()), 'end_position_error': float(np.linalg.norm(np.array(translations)[0]-np.array(translations)[-1]))}
    # All old byte ranges remain untouched; only new animation buffers append.
    assert bytes(writer.binary[:len(binary)]) == binary
    for key in ['meshes', 'skins', 'nodes', 'images', 'textures', 'materials']:
        assert doc.get(key) == original.get(key), key
    doc['asset'].setdefault('extras', {})['likorez_motion_version'] = '0.2.8'
    writer.save(TARGET)
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    enhance()
