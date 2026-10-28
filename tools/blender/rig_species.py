"""Скелет + веса + анимации для вида существа (один набор на вид, общий для 6 стихий).

Запуск (Blender без интерфейса):
  blender -b --factory-startup -P tools/blender/rig_species.py -- <вид> <in.glb> <out.glb> [--template <образец.glb>] [--preview <png-префикс>]
Скелет вида — таблица опорных точек SKELETONS (координаты Blender: X вправо, Y вперёд-назад, Z вверх,
модель Pixal3D в своей единичной рамке). Веса — автоматические (heat) на сглаженной копии-прокси,
затем перенос на исходную сетку (у Pixal3D сетки не всегда цельные, heat по ним даёт дыры).
Клипы: idle (петля), roar, attack, hit — экспортируются в .glb как отдельные анимации.
Точки скелета заданы по модели-образцу вида (TEMPLATE); для других стихий скелет переносится подобием
(поворот+сдвиг+масштаб), найденным ICP по облакам точек образца и модели — стоят они немного по-разному.
"""
import math
import os
import sys

import bpy
from mathutils import Euler, Vector

# кость: (имя, голова, хвост, родитель, деформирует)
SKELETONS = {
    "dragnar": [
        ("root", (0.02, -0.08, -0.33), (0.02, -0.08, -0.25), None, False),
        ("hips", (0.02, -0.08, -0.20), (0.03, -0.12, -0.05), "root", True),
        ("chest", (0.03, -0.12, -0.05), (0.04, -0.15, 0.11), "hips", True),
        ("neck", (0.04, -0.15, 0.11), (0.06, -0.20, 0.19), "chest", True),
        ("head", (0.06, -0.20, 0.19), (0.08, -0.27, 0.22), "neck", True),
        ("thigh.L", (-0.06, -0.08, -0.20), (-0.08, -0.12, -0.27), "hips", True),
        ("shin.L", (-0.08, -0.12, -0.27), (-0.10, -0.15, -0.33), "thigh.L", True),
        ("thigh.R", (0.10, -0.08, -0.20), (0.14, -0.10, -0.27), "hips", True),
        ("shin.R", (0.14, -0.10, -0.27), (0.17, -0.12, -0.33), "thigh.R", True),
        ("arm.L", (-0.06, -0.14, 0.07), (-0.13, -0.17, -0.02), "chest", True),
        ("forearm.L", (-0.13, -0.17, -0.02), (-0.16, -0.18, -0.11), "arm.L", True),
        ("arm.R", (0.13, -0.14, 0.07), (0.20, -0.17, -0.03), "chest", True),
        ("forearm.R", (0.20, -0.17, -0.03), (0.24, -0.18, -0.125), "arm.R", True),
        ("wing.L", (-0.07, -0.05, 0.14), (-0.12, -0.10, 0.31), "chest", True),
        ("wingtip.L", (-0.12, -0.10, 0.31), (-0.38, -0.17, 0.07), "wing.L", True),
        ("wing.R", (0.15, -0.04, 0.14), (0.23, 0.00, 0.31), "chest", True),
        ("wingtip.R", (0.23, 0.00, 0.31), (0.43, 0.08, 0.05), "wing.R", True),
        ("tail1", (-0.02, -0.02, -0.25), (-0.12, 0.04, -0.29), "hips", True),
        ("tail2", (-0.12, 0.04, -0.29), (-0.25, 0.07, -0.24), "tail1", True),
        ("tail3", (-0.25, 0.07, -0.24), (-0.33, 0.10, -0.12), "tail2", True),
        ("tail4", (-0.33, 0.10, -0.12), (-0.34, 0.12, 0.00), "tail3", True),
    ],
    # Четвероногие: hips→chest — позвоночник от таза к плечам, лапы *.L при X<0.
    "klykar": [
        ("root", (-0.06, 0.00, -0.12), (-0.06, 0.00, -0.04), None, False),
        ("hips", (-0.06, 0.22, -0.03), (-0.06, 0.00, 0.00), "root", True),
        ("chest", (-0.06, 0.00, 0.00), (-0.06, -0.22, 0.03), "hips", True),
        ("neck", (-0.06, -0.22, 0.03), (-0.07, -0.31, 0.15), "chest", True),
        ("head", (-0.07, -0.31, 0.15), (-0.07, -0.45, 0.14), "neck", True),
        ("arm.L", (-0.20, -0.21, -0.06), (-0.24, -0.24, -0.20), "chest", True),
        ("forearm.L", (-0.24, -0.24, -0.20), (-0.27, -0.36, -0.32), "arm.L", True),
        ("arm.R", (0.06, -0.21, -0.06), (0.06, -0.24, -0.20), "chest", True),
        ("forearm.R", (0.06, -0.24, -0.20), (0.05, -0.36, -0.34), "arm.R", True),
        ("thigh.L", (-0.12, 0.20, -0.06), (-0.14, 0.25, -0.21), "hips", True),
        ("shin.L", (-0.14, 0.25, -0.21), (-0.16, 0.23, -0.31), "thigh.L", True),
        ("foot.L", (-0.16, 0.23, -0.31), (-0.17, 0.14, -0.37), "shin.L", True),
        ("thigh.R", (0.14, 0.20, -0.06), (0.15, 0.25, -0.21), "hips", True),
        ("shin.R", (0.15, 0.25, -0.21), (0.16, 0.23, -0.32), "thigh.R", True),
        ("foot.R", (0.16, 0.23, -0.32), (0.17, 0.14, -0.40), "shin.R", True),
        ("wing.L", (-0.12, -0.15, 0.10), (-0.20, 0.08, 0.38), "chest", True),
        ("wing.R", (0.02, -0.15, 0.10), (0.28, 0.08, 0.35), "chest", True),
        ("tail1", (-0.06, 0.22, -0.03), (-0.07, 0.36, -0.01), "hips", True),
        ("tail2", (-0.07, 0.36, -0.01), (-0.07, 0.46, 0.12), "tail1", True),
        ("tail3", (-0.07, 0.46, 0.12), (-0.07, 0.50, 0.24), "tail2", True),
    ],
    "grifalon": [
        ("root", (-0.09, -0.16, -0.24), (-0.09, -0.16, -0.17), None, False),
        ("hips", (-0.09, -0.14, -0.14), (-0.09, -0.20, 0.00), "root", True),
        ("chest", (-0.09, -0.20, 0.00), (-0.08, -0.24, 0.09), "hips", True),
        ("neck", (-0.08, -0.24, 0.09), (-0.07, -0.27, 0.22), "chest", True),
        ("head", (-0.07, -0.27, 0.22), (-0.07, -0.40, 0.19), "neck", True),
        ("thigh.L", (-0.15, -0.15, -0.14), (-0.22, -0.14, -0.24), "hips", True),
        ("shin.L", (-0.22, -0.14, -0.24), (-0.26, -0.20, -0.32), "thigh.L", True),
        ("thigh.R", (-0.03, -0.17, -0.14), (0.02, -0.20, -0.24), "hips", True),
        ("shin.R", (0.02, -0.20, -0.24), (0.04, -0.31, -0.33), "thigh.R", True),
        ("wing.L", (-0.18, -0.16, 0.08), (-0.27, -0.10, 0.16), "chest", True),
        ("wingtip.L", (-0.27, -0.10, 0.16), (-0.34, 0.04, -0.28), "wing.L", True),
        ("wing.R", (0.01, -0.16, 0.08), (0.14, -0.10, 0.16), "chest", True),
        ("wingtip.R", (0.14, -0.10, 0.16), (0.28, 0.04, -0.22), "wing.R", True),
        ("tail1", (-0.09, -0.12, -0.16), (-0.09, 0.02, -0.20), "hips", True),
        ("tail2", (-0.09, 0.02, -0.20), (-0.09, 0.18, -0.20), "tail1", True),
        ("tail3", (-0.09, 0.18, -0.20), (-0.09, 0.36, -0.08), "tail2", True),
        ("tail4", (-0.09, 0.36, -0.08), (-0.09, 0.50, 0.03), "tail3", True),
    ],
    "kolossar": [
        ("root", (0.02, -0.06, -0.15), (0.02, -0.06, -0.08), None, False),
        ("hips", (0.02, -0.04, -0.06), (0.03, -0.08, 0.10), "root", True),
        ("chest", (0.03, -0.08, 0.10), (0.04, -0.14, 0.20), "hips", True),
        ("neck", (0.04, -0.14, 0.20), (0.05, -0.18, 0.24), "chest", True),
        ("head", (0.05, -0.18, 0.24), (0.05, -0.22, 0.31), "neck", True),
        ("arm.L", (-0.18, -0.08, 0.16), (-0.29, -0.12, 0.07), "chest", True),
        ("forearm.L", (-0.29, -0.12, 0.07), (-0.32, -0.22, -0.05), "arm.L", True),
        ("arm.R", (0.27, -0.08, 0.16), (0.33, -0.12, 0.08), "chest", True),
        ("forearm.R", (0.33, -0.12, 0.08), (0.35, -0.22, -0.05), "arm.R", True),
        ("thigh.L", (-0.09, -0.06, -0.08), (-0.15, -0.12, -0.23), "hips", True),
        ("shin.L", (-0.15, -0.12, -0.23), (-0.19, -0.20, -0.35), "thigh.L", True),
        ("thigh.R", (0.13, -0.06, -0.08), (0.18, -0.12, -0.23), "hips", True),
        ("shin.R", (0.18, -0.12, -0.23), (0.24, -0.20, -0.37), "thigh.R", True),
        ("tail1", (0.00, 0.02, -0.18), (-0.15, 0.15, -0.20), "hips", True),
        ("tail2", (-0.15, 0.15, -0.20), (-0.34, 0.22, 0.06), "tail1", True),
    ],
    # Жук: панцирь — отдельная кость (приоткрывается при атаке), рог — жёсткий.
    "rogozhuk": [
        ("root", (0.00, 0.05, -0.20), (0.00, 0.05, -0.12), None, False),
        ("hips", (0.00, 0.32, 0.08), (0.00, 0.00, 0.05), "root", True),
        ("chest", (0.00, 0.00, 0.05), (0.00, -0.22, 0.00), "hips", True),
        ("shell", (0.00, 0.10, 0.12), (0.00, 0.00, 0.40), "hips", True),
        ("head", (0.00, -0.22, 0.00), (0.00, -0.39, 0.05), "chest", True),
        ("horn", (0.00, -0.39, 0.07), (0.00, -0.48, 0.30), "head", True),
        ("arm.L", (-0.20, -0.17, -0.06), (-0.26, -0.22, -0.20), "chest", True),
        ("forearm.L", (-0.26, -0.22, -0.20), (-0.28, -0.31, -0.33), "arm.L", True),
        ("arm.R", (0.20, -0.17, -0.06), (0.25, -0.22, -0.20), "chest", True),
        ("forearm.R", (0.25, -0.22, -0.20), (0.27, -0.31, -0.33), "arm.R", True),
        ("thigh.L", (-0.20, 0.08, -0.08), (-0.30, 0.12, -0.18), "hips", True),
        ("shin.L", (-0.30, 0.12, -0.18), (-0.33, 0.14, -0.33), "thigh.L", True),
        ("thigh.R", (0.20, 0.08, -0.08), (0.28, 0.12, -0.18), "hips", True),
        ("shin.R", (0.28, 0.12, -0.18), (0.30, 0.14, -0.33), "thigh.R", True),
    ],
    # Змей: кольцо тела на земле (coil1..6), из передней части поднимается шея.
    "levian": [
        ("root", (0.02, 0.20, -0.38), (0.02, 0.20, -0.32), None, False),
        ("hips", (0.02, -0.02, -0.30), (0.05, -0.34, -0.32), "root", True),
        ("neck1", (0.05, -0.34, -0.32), (0.05, -0.36, -0.15), "hips", True),
        ("neck2", (0.05, -0.36, -0.15), (0.06, -0.30, 0.01), "neck1", True),
        ("neck3", (0.06, -0.30, 0.01), (0.07, -0.33, 0.15), "neck2", True),
        ("head", (0.07, -0.33, 0.15), (0.08, -0.47, 0.16), "neck3", True),
        ("wing.L", (-0.02, -0.22, 0.05), (-0.13, -0.16, 0.27), "neck2", True),
        ("wingtip.L", (-0.13, -0.16, 0.27), (-0.35, -0.10, 0.08), "wing.L", True),
        ("wing.R", (0.10, -0.22, 0.05), (0.27, -0.16, 0.27), "neck2", True),
        ("wingtip.R", (0.27, -0.16, 0.27), (0.39, -0.10, 0.08), "wing.R", True),
        ("coil1", (0.02, -0.02, -0.3), (0.306, 0.09, -0.3), "hips", True),
        ("coil2", (0.306, 0.09, -0.3), (0.306, 0.31, -0.3), "coil1", True),
        ("coil3", (0.306, 0.31, -0.3), (0.02, 0.42, -0.3), "coil2", True),
        ("coil4", (0.02, 0.42, -0.3), (-0.266, 0.31, -0.3), "coil3", True),
        ("coil5", (-0.266, 0.31, -0.3), (-0.266, 0.09, -0.3), "coil4", True),
        ("coil6", (-0.266, 0.09, -0.3), (-0.065, -0.013, -0.3), "coil5", True),
        ("tail", (0.02, 0.42, -0.30), (0.08, 0.47, -0.08), "coil3", True),
    ],
    # Рыцарь: меч — жёсткая кость в руке .L, плащ — две кости за спиной.
    "ratnik": [
        ("root", (0.00, -0.02, -0.12), (0.00, -0.02, -0.05), None, False),
        ("hips", (0.00, -0.02, -0.06), (0.00, -0.02, 0.08), "root", True),
        ("chest", (0.00, -0.02, 0.08), (0.00, -0.03, 0.20), "hips", True),
        ("neck", (0.00, -0.03, 0.20), (0.00, -0.04, 0.25), "chest", True),
        ("head", (0.00, -0.04, 0.25), (0.00, -0.05, 0.40), "neck", True),
        ("arm.L", (-0.15, -0.02, 0.19), (-0.20, -0.06, 0.08), "chest", True),
        ("forearm.L", (-0.20, -0.06, 0.08), (-0.18, -0.12, -0.02), "arm.L", True),
        ("sword", (-0.18, -0.12, -0.02), (0.04, -0.52, -0.21), "forearm.L", True),
        ("arm.R", (0.16, -0.02, 0.19), (0.23, -0.02, 0.05), "chest", True),
        ("forearm.R", (0.23, -0.02, 0.05), (0.24, -0.06, -0.08), "arm.R", True),
        ("thigh.L", (-0.08, -0.02, -0.08), (-0.15, -0.04, -0.23), "hips", True),
        ("shin.L", (-0.15, -0.04, -0.23), (-0.20, -0.08, -0.37), "thigh.L", True),
        ("thigh.R", (0.08, -0.02, -0.08), (0.14, -0.04, -0.23), "hips", True),
        ("shin.R", (0.14, -0.04, -0.23), (0.18, 0.00, -0.37), "thigh.R", True),
        ("cape1", (0.00, 0.08, 0.18), (0.00, 0.24, -0.08), "chest", True),
        ("cape2", (0.00, 0.24, -0.08), (0.00, 0.40, -0.33), "cape1", True),
    ],
    "gorgul": [
        ("root", (0.03, -0.04, -0.20), (0.03, -0.04, -0.12), None, False),
        ("hips", (0.03, -0.04, -0.12), (0.03, -0.12, 0.06), "root", True),
        ("chest", (0.03, -0.12, 0.06), (0.03, -0.15, 0.17), "hips", True),
        ("neck", (0.03, -0.15, 0.17), (0.03, -0.17, 0.20), "chest", True),
        ("head", (0.03, -0.17, 0.20), (0.03, -0.24, 0.28), "neck", True),
        ("arm.L", (-0.08, -0.14, 0.14), (-0.18, -0.17, 0.03), "chest", True),
        ("forearm.L", (-0.18, -0.17, 0.03), (-0.21, -0.19, -0.07), "arm.L", True),
        ("arm.R", (0.14, -0.14, 0.14), (0.22, -0.17, 0.04), "chest", True),
        ("forearm.R", (0.22, -0.17, 0.04), (0.24, -0.19, -0.07), "arm.R", True),
        ("thigh.L", (-0.04, -0.04, -0.12), (-0.09, -0.08, -0.17), "hips", True),
        ("shin.L", (-0.09, -0.08, -0.17), (-0.10, -0.10, -0.27), "thigh.L", True),
        ("thigh.R", (0.10, -0.04, -0.12), (0.13, -0.05, -0.24), "hips", True),
        ("shin.R", (0.13, -0.05, -0.24), (0.15, -0.04, -0.37), "thigh.R", True),
        ("tail1", (0.06, 0.00, -0.16), (0.18, 0.12, -0.22), "hips", True),
        ("tail2", (0.18, 0.12, -0.22), (0.25, 0.18, -0.28), "tail1", True),
        ("wing.L", (-0.02, -0.08, 0.17), (-0.19, -0.06, 0.38), "chest", True),
        ("wingtip.L", (-0.19, -0.06, 0.38), (-0.46, 0.05, 0.00), "wing.L", True),
        ("wing.R", (0.08, -0.08, 0.17), (0.20, -0.06, 0.39), "chest", True),
        ("wingtip.R", (0.20, -0.06, 0.39), (0.48, 0.14, -0.01), "wing.R", True),
    ],
}

FPS = 24
# Модель, по которой сняты точки скелета вида.
TEMPLATE = {sp: f"tools/ai_models/meshes_species/{sp}_fire.glb" for sp in SKELETONS}
# Поворот образца вокруг Z (градусы), в котором сняты точки скелета: головой к -Y (inspect_mesh.py --yaw).
YAW = {"klykar": -54, "grifalon": -45, "rogozhuk": -25, "ratnik": -30}


def _cloud(obj, n=4000):
    import numpy as np
    co = np.array([obj.matrix_world @ v.co for v in obj.data.vertices])
    rng = np.random.default_rng(0)
    return co[rng.choice(len(co), min(n, len(co)), replace=False)]


def icp_similarity(src, dst, iters=40):
    """Подобие (s, R, t): s·R·src + t ≈ dst. Старт — совмещение центров и масштаба, затем ICP (Умеяма)."""
    import numpy as np
    from mathutils.kdtree import KDTree
    tree = KDTree(len(dst))
    for i, p in enumerate(dst):
        tree.insert(p, i)
    tree.balance()
    s = float(np.sqrt(((dst - dst.mean(0)) ** 2).sum(1).mean() / ((src - src.mean(0)) ** 2).sum(1).mean()))
    R = np.eye(3)
    t = dst.mean(0) - s * src.mean(0)
    for _ in range(iters):
        cur = s * src @ R.T + t
        idx = np.array([tree.find(p)[1] for p in cur])
        m = dst[idx]
        mu_a, mu_b = src.mean(0), m.mean(0)
        a, b = src - mu_a, m - mu_b
        U, S, Vt = np.linalg.svd(b.T @ a / len(a))
        D = np.eye(3)
        D[2, 2] = np.sign(np.linalg.det(U @ Vt))
        R = U @ D @ Vt
        s = float(np.trace(np.diag(S) @ D) / (a ** 2).sum(1).mean())
        t = mu_b - s * R @ mu_a
    err = float(np.linalg.norm(s * src @ R.T + t - m, axis=1).mean())
    return s, R, t, err


def unyaw(spec, yaw):
    """Точки, снятые в повёрнутой на yaw системе, — обратно в систему модели."""
    if not yaw:
        return spec
    from mathutils import Matrix
    m = Matrix.Rotation(math.radians(-yaw), 3, "Z")
    f = lambda p: tuple(m @ Vector(p))
    return [(n, f(h), f(t), par, d) for n, h, t, par, d in spec]


def fit_spec(spec, template_path, mesh):
    """Перенести точки скелета с образца на модель подобием из ICP."""
    import numpy as np
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=template_path)
    tmpl = next(o for o in set(bpy.data.objects) - before if o.type == "MESH")
    s, R, t, err = icp_similarity(_cloud(tmpl), _cloud(mesh))
    for o in set(bpy.data.objects) - before:
        bpy.data.objects.remove(o, do_unlink=True)
    ang = math.degrees(math.acos(max(-1.0, min(1.0, (np.trace(R) - 1) / 2))))
    print(f"FIT scale={s:.3f} rot={ang:.1f}deg err={err:.4f}")
    f = lambda p: tuple(s * R @ np.array(p) + t)
    return [(n, f(h), f(tl), par, d) for n, h, tl, par, d in spec]


def build_armature(spec):
    arm = bpy.data.armatures.new("rig")
    obj = bpy.data.objects.new("rig", arm)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    for name, head, tail, parent, deform in spec:
        b = arm.edit_bones.new(name)
        b.head, b.tail = Vector(head), Vector(tail)
        b.use_deform = deform
        if parent:
            b.parent = arm.edit_bones[parent]
            b.use_connect = (Vector(head) - arm.edit_bones[parent].tail).length < 1e-4
    bpy.ops.object.mode_set(mode="OBJECT")
    return obj


SIGMA = 0.035  # ширина мягкого перехода весов между соседними костями (в единицах модели ~1)


def skin(mesh, rig, spec):
    """Веса по расстоянию до отрезков костей: две ближайшие кости, гауссово смешивание.
    Heat-веса Blender на сетках Pixal3D (не цельных, 150k треугольников) не находят решения."""
    import numpy as np
    bones = [(n, np.array(h), np.array(t)) for n, h, t, _p, d in spec if d]
    co = np.array([mesh.matrix_world @ v.co for v in mesh.data.vertices])
    dist = np.empty((len(co), len(bones)))
    for j, (_n, a, b) in enumerate(bones):
        ab = b - a
        t = np.clip(((co - a) @ ab) / max(ab @ ab, 1e-9), 0.0, 1.0)
        dist[:, j] = np.linalg.norm(co - (a + t[:, None] * ab), axis=1)
    near = np.argsort(dist, axis=1)[:, :2]
    d2 = np.take_along_axis(dist, near, axis=1)
    w = np.exp(-((d2 - d2[:, :1]) / SIGMA) ** 2)  # ближайшая кость = 1, вторая затухает с разницей расстояний
    w /= w.sum(axis=1, keepdims=True)
    groups = [mesh.vertex_groups.new(name=n) for n, _a, _b in bones]
    for j, g in enumerate(groups):
        for k in range(2):
            idx = np.nonzero((near[:, k] == j) & (w[:, k] > 0.01))[0]
            for wv in np.unique(np.round(w[idx, k], 2)):
                sel = idx[np.round(w[idx, k], 2) == wv]
                g.add(sel.tolist(), float(wv), "REPLACE")
    mesh.parent = rig
    am = mesh.modifiers.new("rig", "ARMATURE")
    am.object = rig


def key(rig, frame, poses):
    """poses: {кость: (rx, ry, rz) в градусах, локально}; остальные кости — в покое на этом кадре."""
    for pb in rig.pose.bones:
        pb.rotation_mode = "XYZ"
        r = poses.get(pb.name, (0, 0, 0))
        pb.rotation_euler = Euler([math.radians(a) for a in r])
        pb.keyframe_insert("rotation_euler", frame=frame)


def mirror(d):
    """Симметричная поза: значения для .L копируются в .R с отражением Y/Z-поворотов."""
    out = dict(d)
    for k, (x, y, z) in d.items():
        if k.endswith(".L"):
            out.setdefault(k[:-2] + ".R", (x, -y, -z))
    return out


def clips_dragnar():
    rest = {}
    breathe = mirror({"chest": (-3, 0, 0), "neck": (-2, 0, 0), "wing.L": (0, 0, -8), "wingtip.L": (0, 0, -6),
                      "tail2": (0, 0, 6), "tail3": (0, 0, 8), "tail4": (0, 0, 8)})
    breathe2 = mirror({"chest": (2, 0, 0), "neck": (2, 0, 0), "wing.L": (0, 0, 6), "wingtip.L": (0, 0, 5),
                       "tail2": (0, 0, -6), "tail3": (0, 0, -8), "tail4": (0, 0, -8)})
    roar = mirror({"chest": (-12, 0, 0), "neck": (-22, 0, 0), "head": (-18, 0, 0), "wing.L": (0, 0, 18),
                   "wingtip.L": (0, 0, 14), "arm.L": (0, 0, 15), "tail3": (12, 0, 0)})
    windup = mirror({"chest": (-10, 0, 0), "neck": (-8, 0, 0), "wing.L": (0, 0, 12), "arm.L": (0, 0, 10)})
    strike = dict(mirror({"chest": (22, 0, 0), "neck": (14, 0, 0), "head": (8, 0, 0), "wing.L": (0, 0, -10),
                          "tail2": (-8, 0, 0)}), **{"arm.R": (-35, 0, -20), "forearm.R": (-25, 0, 0)})
    hit = mirror({"hips": (-6, 0, 0), "chest": (-16, 0, 0), "neck": (-14, 0, 0), "head": (-10, 0, 8),
                  "wing.L": (0, 0, -14), "wingtip.L": (0, 0, -10), "tail2": (8, 0, 0)})
    return {
        "idle": [(1, rest), (13, breathe), (37, breathe2), (49, rest)],
        "roar": [(1, rest), (8, windup), (14, roar), (26, roar), (34, rest)],
        "attack": [(1, rest), (7, windup), (12, strike), (20, strike), (28, rest)],
        "hit": [(1, rest), (4, hit), (12, hit), (22, rest)],
    }


def clips_biped(sword=False):
    """Прямоходящие (Колоссар, Ратник, Горгул, Грифалон): как у Драгнара, без лишних костей."""
    c = clips_dragnar()
    breathe = mirror({"chest": (-3, 0, 0), "neck": (-2, 0, 0), "arm.L": (0, 0, 4), "wing.L": (0, 0, -8),
                      "wingtip.L": (0, 0, -6), "tail1": (0, 0, 6), "tail2": (0, 0, 8), "cape1": (-3, 0, 0),
                      "cape2": (-4, 0, 0)})
    breathe2 = mirror({"chest": (2, 0, 0), "neck": (2, 0, 0), "arm.L": (0, 0, -3), "wing.L": (0, 0, 6),
                       "wingtip.L": (0, 0, 5), "tail1": (0, 0, -6), "tail2": (0, 0, -8), "cape1": (3, 0, 0),
                       "cape2": (4, 0, 0)})
    c["idle"] = [(1, {}), (13, breathe), (37, breathe2), (49, {})]
    if sword:  # удар мечом сверху вниз рукой .L, плащ отлетает назад
        windup = mirror({"chest": (-8, 0, 0), "cape1": (-10, 0, 0)})
        windup.update({"arm.L": (-70, 0, 0), "forearm.L": (-30, 0, 0)})
        strike = mirror({"chest": (16, 0, 0), "neck": (6, 0, 0), "cape1": (-20, 0, 0), "cape2": (-12, 0, 0)})
        strike.update({"arm.L": (30, 0, 0), "forearm.L": (10, 0, 0)})
        c["attack"] = [(1, {}), (8, windup), (13, strike), (20, strike), (28, {})]
    return c


def scaled(clips, k):
    """Умножить повороты костей на k: {кость-префикс: коэффициент}."""
    def f(name, r):
        m = next((v for pre, v in k.items() if name.startswith(pre)), 1.0)
        return tuple(a * m for a in r)
    return {c: [(fr, {b: f(b, r) for b, r in p.items()}) for fr, p in keys] for c, keys in clips.items()}


def clips_quadruped():
    """Клыкарь: дыхание и хвост, рёв с задранной головой, бросок с укусом, отдача."""
    breathe = mirror({"chest": (-2, 0, 0), "neck": (-3, 0, 0), "wing.L": (0, 0, -6), "tail2": (0, 0, 8),
                      "tail3": (0, 0, 10)})
    breathe2 = mirror({"chest": (1, 0, 0), "neck": (2, 0, 0), "wing.L": (0, 0, 5), "tail2": (0, 0, -8),
                       "tail3": (0, 0, -10)})
    roar = mirror({"hips": (-4, 0, 0), "chest": (-6, 0, 0), "neck": (-22, 0, 0), "head": (-14, 0, 0),
                   "wing.L": (0, 0, 16), "tail1": (12, 0, 0), "tail2": (10, 0, 0)})
    windup = mirror({"hips": (3, 0, 0), "neck": (8, 0, 0), "head": (6, 0, 0), "thigh.L": (-10, 0, 0),
                     "arm.L": (10, 0, 0), "tail1": (-6, 0, 0)})
    strike = mirror({"hips": (-6, 0, 0), "chest": (6, 0, 0), "neck": (14, 0, 0), "head": (16, 0, 0),
                     "arm.L": (-30, 0, 0), "forearm.L": (20, 0, 0), "thigh.L": (14, 0, 0), "tail1": (10, 0, 0)})
    hit = mirror({"hips": (6, 0, 0), "chest": (-10, 0, 0), "neck": (-16, 0, 0), "head": (-8, 0, 10),
                  "wing.L": (0, 0, -12), "tail1": (-14, 0, 0)})
    return {
        "idle": [(1, {}), (13, breathe), (37, breathe2), (49, {})],
        "roar": [(1, {}), (8, windup), (14, roar), (26, roar), (34, {})],
        "attack": [(1, {}), (7, windup), (12, strike), (20, strike), (28, {})],
        "hit": [(1, {}), (4, hit), (12, hit), (22, {})],
    }


def clips_beetle():
    """Рогожук: панцирь приоткрывается, рог поддевает снизу вверх."""
    breathe = mirror({"shell": (-3, 0, 0), "head": (2, 0, 0), "arm.L": (0, 0, 3)})
    breathe2 = mirror({"shell": (2, 0, 0), "head": (-2, 0, 0), "arm.L": (0, 0, -3)})
    roar = mirror({"chest": (-8, 0, 0), "head": (-18, 0, 0), "shell": (-14, 0, 0), "arm.L": (-15, 0, 0)})
    windup = mirror({"chest": (8, 0, 0), "head": (14, 0, 0), "hips": (-4, 0, 0), "thigh.L": (-8, 0, 0)})
    strike = mirror({"chest": (-10, 0, 0), "head": (-26, 0, 0), "shell": (-10, 0, 0), "arm.L": (-20, 0, 0),
                     "thigh.L": (12, 0, 0)})
    hit = mirror({"chest": (-6, 0, 0), "head": (-12, 0, 8), "shell": (6, 0, 0), "hips": (4, 0, 0)})
    return {
        "idle": [(1, {}), (13, breathe), (37, breathe2), (49, {})],
        "roar": [(1, {}), (8, windup), (14, roar), (26, roar), (34, {})],
        "attack": [(1, {}), (7, windup), (12, strike), (20, strike), (28, {})],
        "hit": [(1, {}), (4, hit), (12, hit), (22, {})],
    }


def clips_serpent():
    """Левиан: шея-волна, кольцо почти неподвижно, хвост покачивается."""
    breathe = mirror({"neck1": (-3, 0, 0), "neck2": (4, 0, 0), "neck3": (-4, 0, 0), "wing.L": (0, 0, -8),
                      "wingtip.L": (0, 0, -6), "tail": (0, 0, 10)})
    breathe2 = mirror({"neck1": (3, 0, 0), "neck2": (-4, 0, 0), "neck3": (4, 0, 0), "wing.L": (0, 0, 6),
                       "wingtip.L": (0, 0, 5), "tail": (0, 0, -10)})
    roar = mirror({"neck1": (-8, 0, 0), "neck2": (-10, 0, 0), "neck3": (-16, 0, 0), "head": (-14, 0, 0),
                   "wing.L": (0, 0, 18), "wingtip.L": (0, 0, 12), "tail": (14, 0, 0)})
    windup = mirror({"neck1": (-10, 0, 0), "neck2": (-12, 0, 0), "neck3": (-8, 0, 0), "wing.L": (0, 0, 10)})
    strike = mirror({"neck1": (14, 0, 0), "neck2": (16, 0, 0), "neck3": (14, 0, 0), "head": (10, 0, 0),
                     "wing.L": (0, 0, -10)})
    hit = mirror({"neck1": (-8, 0, 0), "neck2": (-12, 0, 0), "neck3": (-10, 0, 10), "head": (-8, 0, 0),
                  "wing.L": (0, 0, -14), "tail": (-10, 0, 0)})
    return {
        "idle": [(1, {}), (13, breathe), (37, breathe2), (49, {})],
        "roar": [(1, {}), (8, windup), (14, roar), (26, roar), (34, {})],
        "attack": [(1, {}), (7, windup), (12, strike), (20, strike), (28, {})],
        "hit": [(1, {}), (4, hit), (12, hit), (22, {})],
    }


CLIPS = {"dragnar": clips_dragnar, "klykar": clips_quadruped,
         # у Грифалона крылья сложены вдоль тела — большой взмах проводит их сквозь грудь
         "grifalon": lambda: scaled(clips_biped(), {"wing": 0.35}),
         # Колоссар тяжёлый: корпус почти не гнётся, работают руки
         "kolossar": lambda: scaled(clips_biped(), {"chest": 0.5, "neck": 0.4, "head": 0.5, "arm": 1.3}),
         "ratnik": lambda: clips_biped(sword=True), "gorgul": clips_biped, "rogozhuk": clips_beetle,
         "levian": clips_serpent}


def make_actions(rig, species):
    rig.animation_data_create()
    for name, keys in CLIPS[species]().items():
        act = bpy.data.actions.new(name)
        rig.animation_data.action = act
        for frame, poses in keys:
            key(rig, frame, poses)
        track = rig.animation_data.nla_tracks.new()
        track.name = name
        strip = track.strips.new(name, 1, act)
        if hasattr(strip, "action_slot") and act.slots:  # Blender 5: у действия слоты, без слота клип пустой
            strip.action_slot = act.slots[0]
        rig.animation_data.action = None


def preview(rig, prefix):
    """Кадры клипов спереди и сбоку для проверки деформаций."""
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.color_type = "TEXTURE"
    sc.render.resolution_x = sc.render.resolution_y = 420
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    bpy.context.collection.objects.link(cam)
    sc.camera = cam
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 1.15
    shots = {"rest": None, "idle": 13, "roar": 20, "attack": 14, "hit": 8}
    for clip, frame in shots.items():
        act = bpy.data.actions.get(clip) if frame else None
        rig.animation_data.action = act
        if act is not None and act.slots:
            rig.animation_data.action_slot = act.slots[0]
        for t in rig.animation_data.nla_tracks:
            t.mute = True
        sc.frame_set(frame or 1)
        if not frame:
            for pb in rig.pose.bones:
                pb.rotation_euler = (0, 0, 0)
        for view, (loc, rot) in {"front": ((0.02, -2, 0), (90, 0, 0)), "side": ((2, -0.06, 0), (90, 0, 90))}.items():
            cam.location = loc
            cam.rotation_euler = Euler([math.radians(a) for a in rot])
            sc.render.filepath = f"{prefix}_{clip}_{view}.png"
            bpy.ops.render.render(write_still=True)
    rig.animation_data.action = None
    for t in rig.animation_data.nla_tracks:
        t.mute = False


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    species, src, dst = args[0], args[1], args[2]
    prev = args[args.index("--preview") + 1] if "--preview" in args else None
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.import_scene.gltf(filepath=src)
    mesh = next(o for o in bpy.data.objects if o.type == "MESH")
    bpy.context.scene.render.fps = FPS
    spec = unyaw(SKELETONS[species], YAW.get(species, 0))
    tmpl = args[args.index("--template") + 1] if "--template" in args else TEMPLATE.get(species)
    if tmpl and os.path.abspath(tmpl) != os.path.abspath(src):
        spec = fit_spec(spec, tmpl, mesh)
    rig = build_armature(spec)
    skin(mesh, rig, spec)
    make_actions(rig, species)
    if prev:
        preview(rig, prev)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_animations=True,
                              export_animation_mode="NLA_TRACKS", export_apply=False)
    print("RIGGED", dst)


if __name__ == "__main__":
    main()
