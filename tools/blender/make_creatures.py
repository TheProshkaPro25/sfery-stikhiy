"""Процедурные модели существ «Сфер Стихий» (Blender 5.x).

Запуск:  blender -b --python tools/blender/make_creatures.py -- <out_dir> [--preview]
Каждый архетип -> <out_dir>/<name>.glb. Высота модели 1.0, основание на z=0, лицом к -Y (в Godot это +Z).
Материалы по именам перекрашиваются в Godot под стихию: Primary (основной цвет), Secondary (тёмный оттенок),
Metal, Glow (свечение цвета стихии), Eye (белок), Dark.
"""
import math
import os
import sys

import bpy
from mathutils import Vector

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(ARGS[0] if ARGS else "creatures")
PREVIEW = "--preview" in ARGS

PALETTE = {
	"Primary": ((0.75, 0.32, 0.18), 0.0, 0.55, 0.0),
	"Secondary": ((0.30, 0.12, 0.08), 0.0, 0.6, 0.0),
	"Metal": ((0.72, 0.72, 0.76), 0.0, 0.3, 1.0),
	"Glow": ((1.0, 0.75, 0.3), 4.0, 0.4, 0.0),
	"Eye": ((0.95, 0.93, 0.88), 0.0, 0.25, 0.0),
	"Dark": ((0.05, 0.05, 0.06), 0.0, 0.5, 0.0),
}


# ---------------------------------------------------------------- утилиты

def reset():
	bpy.ops.wm.read_factory_settings(use_empty=True)
	for name, (col, emit, rough, metal) in PALETTE.items():
		m = bpy.data.materials.new(name)
		m.use_nodes = True
		b = m.node_tree.nodes["Principled BSDF"]
		b.inputs["Base Color"].default_value = (*col, 1.0)
		b.inputs["Roughness"].default_value = rough
		b.inputs["Metallic"].default_value = metal
		if emit > 0.0:
			b.inputs["Emission Color"].default_value = (*col, 1.0)
			b.inputs["Emission Strength"].default_value = emit
		m.diffuse_color = (*col, 1.0)


def M(name):
	return bpy.data.materials[name]


def _finish(ob, mat, smooth=True):
	ob.data.materials.clear()
	ob.data.materials.append(M(mat))
	if smooth:
		for p in ob.data.polygons:
			p.use_smooth = True
	return ob


def _apply_mods(ob):
	bpy.ops.object.select_all(action="DESELECT")
	bpy.context.view_layer.objects.active = ob
	ob.select_set(True)
	bpy.ops.object.convert(target="MESH")
	return ob


def skin(pts, edges, mat, mirror=True, sub=2):
	"""Тело из «скелета»: pts = [(x, y, z, r) | (x, y, z, rx, ry)], рёбра по индексам."""
	me = bpy.data.meshes.new("skin")
	me.from_pydata([p[:3] for p in pts], edges, [])
	ob = bpy.data.objects.new("skin", me)
	bpy.context.collection.objects.link(ob)
	if mirror:
		mm = ob.modifiers.new("mirror", "MIRROR")
		mm.use_mirror_merge = True
		mm.merge_threshold = 0.001
	sk = ob.modifiers.new("skin", "SKIN")
	sk.use_smooth_shade = True
	for i, p in enumerate(pts):
		rx = p[3]
		ry = p[4] if len(p) > 4 else p[3]
		me.skin_vertices[0].data[i].radius = (rx, ry)
	me.skin_vertices[0].data[0].use_root = True
	ss = ob.modifiers.new("sub", "SUBSURF")
	ss.levels = sub
	ss.render_levels = sub
	_apply_mods(ob)
	return _finish(ob, mat)


def sphere(loc, r, mat, scale=(1, 1, 1), rot=(0, 0, 0), seg=24):
	bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=seg // 2, radius=r, location=loc, rotation=rot)
	ob = bpy.context.active_object
	ob.scale = scale
	return _finish(ob, mat)


def cyl(loc, r, depth, mat, rot=(0, 0, 0), verts=24, r2=None):
	if r2 is None:
		bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth, location=loc, rotation=rot)
	else:
		bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=r2, depth=depth, location=loc, rotation=rot)
	return _finish(bpy.context.active_object, mat, smooth=False)


def cone(base, tip, r, mat, verts=16):
	"""Конус от точки base к точке tip."""
	a, b = Vector(base), Vector(tip)
	d = b - a
	bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=0.0, depth=d.length, location=(a + b) / 2)
	ob = bpy.context.active_object
	ob.rotation_mode = "QUATERNION"
	ob.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d.normalized())
	return _finish(ob, mat)


def rod(a, b, r, mat, verts=12):
	a, b = Vector(a), Vector(b)
	d = b - a
	bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=d.length, location=(a + b) / 2)
	ob = bpy.context.active_object
	ob.rotation_mode = "QUATERNION"
	ob.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d.normalized())
	return _finish(ob, mat)


def box(loc, size, mat, rot=(0, 0, 0), bevel=0.04):
	bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rot)
	ob = bpy.context.active_object
	ob.scale = size
	bpy.ops.object.transform_apply(scale=True)
	if bevel > 0:
		bv = ob.modifiers.new("bevel", "BEVEL")
		bv.width = bevel
		bv.segments = 2
		_apply_mods(ob)
	return _finish(ob, mat, smooth=False)


def membrane(root, tips, mat, thick=0.015, mirror=True):
	"""Перепонка крыла: веер треугольников от root через tips, с толщиной и сглаживанием."""
	verts = [root] + list(tips)
	faces = [(0, i, i + 1) for i in range(1, len(tips))]
	me = bpy.data.meshes.new("wing")
	me.from_pydata(verts, [], faces)
	ob = bpy.data.objects.new("wing", me)
	bpy.context.collection.objects.link(ob)
	if mirror:
		ob.modifiers.new("mirror", "MIRROR")
	sd = ob.modifiers.new("solid", "SOLIDIFY")
	sd.thickness = thick
	ss = ob.modifiers.new("sub", "SUBSURF")
	ss.levels = 1
	_apply_mods(ob)
	return _finish(ob, mat)


def bat_wing(root, tips, body, mat, bone_mat="Dark", bone_r=0.03, sag=0.3):
	"""Крыло летучей мыши: кости-пальцы от root к tips, перепонка с фестонами между ними, задний край к body."""
	root, body = Vector(root), Vector(body)
	tips = [Vector(t) for t in tips]
	edge = []
	for i, t in enumerate(tips):
		edge.append(t)
		nxt = tips[i + 1] if i + 1 < len(tips) else body
		edge.append((t + nxt) / 2 + (root - (t + nxt) / 2) * sag)
	edge.append(body)
	for side in (1, -1):
		f = lambda v: (v.x * side, v.y, v.z)
		membrane(f(root), [f(v) for v in edge], mat, mirror=False)
		elbow = root + (tips[0] - root) * 0.45 + Vector((0, 0, 0.12))
		pts = [(*f(root), bone_r * 1.4), (*f(elbow), bone_r * 1.2)] + [(*f(t), bone_r * 0.6) for t in tips]
		edges = [(0, 1)] + [(1, 2 + i) for i in range(len(tips))]
		skin(pts, edges, bone_mat, mirror=False, sub=1)


def cloak(top_z, bot_z, top_w, bot_w, y0, y1, mat, cols=10, rows=12):
	"""Плащ за спиной: полоса ткани, расширяется книзу, отходит назад и волнится."""
	verts, faces = [], []
	for r in range(rows + 1):
		t = r / rows
		z = top_z + (bot_z - top_z) * t
		w = top_w + (bot_w - top_w) * t
		for c in range(cols + 1):
			u = c / cols * 2.0 - 1.0
			x = u * w
			y = y0 + (y1 - y0) * t + 0.12 * (1.0 - u * u) * t + 0.03 * math.sin(u * 7.0 + t * 3.0) * t
			verts.append((x, y, z))
	for r in range(rows):
		for c in range(cols):
			i = r * (cols + 1) + c
			faces.append((i, i + 1, i + cols + 2, i + cols + 1))
	me = bpy.data.meshes.new("cloak")
	me.from_pydata(verts, [], faces)
	ob = bpy.data.objects.new("cloak", me)
	bpy.context.collection.objects.link(ob)
	sd = ob.modifiers.new("solid", "SOLIDIFY")
	sd.thickness = 0.025
	ss = ob.modifiers.new("sub", "SUBSURF")
	ss.levels = 1
	_apply_mods(ob)
	return _finish(ob, mat)


def mirror_x(fn, *a, **k):
	"""Вызвать построитель для правой стороны и зеркально для левой (первый аргумент — точка/точки)."""
	fn(*a, **k)
	def flip(v):
		if isinstance(v, (tuple, list)) and len(v) == 3 and all(isinstance(c, (int, float)) for c in v):
			return (-v[0], v[1], v[2])
		return v
	fn(*[flip(x) for x in a], **k)


def eyes(x, y, z, r, mat="Glow"):
	sphere((x, y, z), r, mat)
	sphere((-x, y, z), r, mat)


# ---------------------------------------------------------------- архетипы

def knight():
	"""Воин в плаще: шлем с гребнем, наплечники, меч и щит."""
	skin([
		(0, 0, 1.0, 0.2, 0.15), (0, 0, 1.45, 0.27, 0.19), (0, 0, 1.72, 0.09),
		(0.13, 0, 0.95, 0.11), (0.15, -0.02, 0.52, 0.09), (0.16, 0, 0.1, 0.075), (0.16, -0.16, 0.05, 0.065),
		(0.3, 0, 1.57, 0.1), (0.43, 0.02, 1.22, 0.08), (0.46, -0.1, 0.95, 0.07),
	], [(0, 1), (1, 2), (0, 3), (3, 4), (4, 5), (5, 6), (1, 7), (7, 8), (8, 9)], "Primary")
	sphere((0, -0.01, 1.9), 0.17, "Secondary")
	sphere((0, 0, 1.93), 0.2, "Metal", scale=(1, 1.05, 1.05))
	box((0, -0.19, 1.9), (0.22, 0.04, 0.035), "Glow", bevel=0.01)
	cone((0, 0.02, 2.1), (0, 0.18, 2.32), 0.05, "Secondary")
	mirror_x(sphere, (0.33, 0, 1.62), 0.13, "Metal", scale=(1.1, 1, 0.8))
	sphere((0, -0.06, 1.48), 0.26, "Metal", scale=(1.05, 0.75, 0.9))
	cyl((0, 0, 1.02), 0.21, 0.09, "Dark")
	mirror_x(sphere, (0.16, -0.03, 0.55), 0.1, "Metal", scale=(1, 1, 0.8))
	cloak(1.65, 0.18, 0.3, 0.5, 0.17, 0.42, "Secondary")
	# меч в правой руке, клинок вниз-вперёд
	rod((0.47, -0.12, 1.0), (0.47, -0.12, 0.88), 0.025, "Dark")
	box((0.47, -0.12, 0.86), (0.2, 0.05, 0.035), "Metal", bevel=0.01)
	box((0.47, -0.2, 0.5), (0.06, 0.02, 0.7), "Metal", rot=(math.radians(-12), 0, 0), bevel=0.008)
	# щит в левой руке
	cyl((-0.52, -0.2, 1.0), 0.27, 0.05, "Primary", rot=(math.radians(90), 0, math.radians(-15)), verts=6)
	sphere((-0.53, -0.24, 1.0), 0.07, "Glow")


def centaur():
	"""Кентавр: конское тело, человеческий торс, копьё."""
	skin([
		(0, 0, 1.0, 0.24, 0.27), (0, 0.72, 1.02, 0.26, 0.27),
		(0.15, -0.02, 0.88, 0.11), (0.16, -0.05, 0.45, 0.065), (0.16, -0.06, 0.06, 0.06),
		(0.16, 0.74, 0.92, 0.13), (0.17, 0.86, 0.48, 0.065), (0.17, 0.78, 0.06, 0.06),
		(0, -0.12, 1.32, 0.19, 0.15), (0, -0.14, 1.62, 0.25, 0.17), (0, -0.14, 1.84, 0.08),
		(0.28, -0.14, 1.74, 0.085), (0.4, -0.26, 1.5, 0.065), (0.36, -0.44, 1.42, 0.055),
	], [(0, 1), (0, 2), (2, 3), (3, 4), (1, 5), (5, 6), (6, 7), (0, 8), (8, 9), (9, 10), (9, 11), (11, 12), (12, 13)], "Primary")
	skin([(0, 0.98, 1.08, 0.07), (0, 1.15, 0.85, 0.06), (0, 1.18, 0.55, 0.035)], [(0, 1), (1, 2)], "Secondary", mirror=False)
	sphere((0, -0.15, 2.0), 0.14, "Secondary")
	sphere((0, -0.14, 2.03), 0.16, "Metal", scale=(1, 1.05, 1.1))
	box((0, -0.3, 2.0), (0.16, 0.03, 0.03), "Glow", bevel=0.01)
	cone((0, -0.1, 2.15), (0, 0.15, 2.28), 0.04, "Secondary")
	sphere((0, -0.2, 1.62), 0.24, "Metal", scale=(1.05, 0.7, 0.9))
	mirror_x(sphere, (0.28, -0.14, 1.78), 0.1, "Metal", scale=(1.1, 1, 0.8))
	for x, y in ((0.16, -0.06), (-0.16, -0.06), (0.17, 0.78), (-0.17, 0.78)):
		cyl((x, y, 0.05), 0.075, 0.1, "Dark")
	# попона
	cloak(1.25, 0.72, 0.2, 0.28, 0.3, 0.55, "Secondary", cols=8, rows=6)
	# копьё
	rod((0.36, 0.25, 1.05), (0.36, -1.0, 1.85), 0.025, "Dark")
	cone((0.36, -1.0, 1.85), (0.36, -1.22, 1.99), 0.05, "Glow")


def cyclops():
	"""Циклоп: массивное тело, один огромный глаз, рог, дубина."""
	skin([
		(0, 0, 0.92, 0.3, 0.24), (0, -0.04, 1.28, 0.42, 0.36), (0, 0, 1.62, 0.4, 0.3), (0, -0.02, 1.86, 0.18),
		(0.2, 0, 0.86, 0.17), (0.25, -0.06, 0.46, 0.15), (0.26, 0, 0.11, 0.13), (0.26, -0.18, 0.07, 0.11),
		(0.47, 0, 1.72, 0.2), (0.66, 0.02, 1.26, 0.17), (0.7, -0.1, 0.86, 0.2),
	], [(0, 1), (1, 2), (2, 3), (0, 4), (4, 5), (5, 6), (6, 7), (2, 8), (8, 9), (9, 10)], "Primary")
	sphere((0, -0.06, 2.06), 0.3, "Primary", scale=(1, 0.95, 0.95))
	sphere((0, -0.27, 2.1), 0.15, "Eye")
	sphere((0, -0.39, 2.1), 0.085, "Glow", scale=(1, 0.5, 1))
	sphere((0, -0.43, 2.1), 0.04, "Dark", scale=(1, 0.5, 1.4))
	box((0, -0.32, 2.27), (0.34, 0.08, 0.06), "Secondary", bevel=0.02)
	cone((0, -0.05, 2.3), (0, 0.05, 2.62), 0.08, "Secondary")
	box((0, -0.1, 0.88), (0.5, 0.36, 0.22), "Secondary", bevel=0.05)
	mirror_x(sphere, (0.42, 0, 1.78), 0.16, "Secondary", scale=(1.1, 1, 0.7))
	# дубина в правой руке
	cyl((0.7, -0.14, 0.52), 0.07, 0.75, "Dark", r2=0.14)
	for a in range(5):
		ang = a * 1.26
		cone((0.7, -0.14, 0.3), (0.7 + 0.24 * math.cos(ang), -0.14 + 0.24 * math.sin(ang), 0.26), 0.035, "Metal")


def flying_eye():
	"""Летающий глаз: глазное яблоко, крылья летучей мыши, щупальца."""
	sphere((0, 0, 1.2), 0.48, "Primary")
	sphere((0, -0.24, 1.2), 0.36, "Eye")
	sphere((0, -0.52, 1.2), 0.17, "Glow", scale=(1, 0.35, 1))
	sphere((0, -0.58, 1.2), 0.08, "Dark", scale=(0.5, 0.3, 1.2))
	# веки
	sphere((0, -0.15, 1.42), 0.4, "Secondary", scale=(1, 0.9, 0.35))
	sphere((0, -0.15, 0.98), 0.4, "Secondary", scale=(1, 0.9, 0.3))
	for i in range(5):
		a = math.radians(-60 + i * 30)
		cone((0.4 * math.sin(a), 0.1, 1.2 + 0.4 * math.cos(a)), (0.62 * math.sin(a), 0.25, 1.2 + 0.62 * math.cos(a)), 0.06, "Secondary")
	bat_wing((0.38, 0.18, 1.3), [(0.85, 0.3, 2.1), (1.3, 0.38, 1.75), (1.4, 0.42, 1.25)], (0.42, 0.25, 0.95), "Secondary")
	for x, y, ph in ((0.18, 0.12, 0.0), (-0.18, 0.12, 1.5), (0.1, -0.12, 3.0), (-0.1, -0.12, 4.5), (0, 0.22, 2.2)):
		pts = []
		for k in range(6):
			t = k / 5
			pts.append((x * (1 + 0.6 * t) + 0.08 * math.sin(ph + t * 5), y * (1 + 0.6 * t) + 0.06 * math.cos(ph + t * 4), 0.8 - 0.72 * t, 0.08 * (1 - t) + 0.015))
		skin(pts, [(i, i + 1) for i in range(5)], "Primary", mirror=False, sub=1)


def dragon():
	"""Дракон: четыре лапы, крылья, длинная шея и хвост, рога."""
	skin([
		(0, -0.1, 0.66, 0.36, 0.32), (0, 0.45, 0.62, 0.32, 0.29),
		(0, -0.4, 0.92, 0.21), (0, -0.52, 1.16, 0.18), (0, -0.66, 1.26, 0.22, 0.19), (0, -0.98, 1.18, 0.13, 0.1),
		(0, 0.85, 0.52, 0.2), (0, 1.25, 0.36, 0.13), (0, 1.6, 0.26, 0.07), (0, 1.85, 0.3, 0.03),
		(0.27, -0.12, 0.55, 0.16), (0.31, -0.18, 0.28, 0.12), (0.31, -0.3, 0.07, 0.11),
		(0.26, 0.45, 0.55, 0.19), (0.32, 0.55, 0.28, 0.13), (0.32, 0.42, 0.07, 0.11),
	], [(0, 1), (0, 2), (2, 3), (3, 4), (4, 5), (1, 6), (6, 7), (7, 8), (8, 9), (0, 10), (10, 11), (11, 12), (1, 13), (13, 14), (14, 15)], "Primary")
	sphere((0, -0.88, 1.06), 0.13, "Secondary", scale=(0.8, 1.6, 0.45))
	mirror_x(cone, (0.1, -0.6, 1.4), (0.18, -0.3, 1.66), 0.06, "Secondary")
	mirror_x(cone, (0.07, -0.95, 1.28), (0.09, -0.92, 1.38), 0.025, "Secondary")
	eyes(0.12, -0.84, 1.33, 0.04)
	for x in (0.31, -0.31):
		for y in (-0.3, 0.42):
			for k in (-1, 0, 1):
				cone((x + 0.05 * k, y - 0.08, 0.05), (x + 0.08 * k, y - 0.2, 0.02), 0.025, "Metal")
	bat_wing((0.22, 0.05, 0.9), [(0.75, -0.05, 1.75), (1.25, 0.25, 1.55), (1.45, 0.55, 1.05)], (0.3, 0.55, 0.75), "Secondary", bone_r=0.04)
	for i in range(8):
		t = i / 7
		y = -0.45 + 2.0 * t
		z = 1.05 - 0.6 * t + 0.08 * math.sin(t * 3)
		cone((0, y, z), (0, y + 0.1, z + 0.2 * (1 - 0.7 * t)), 0.055, "Secondary")
	sphere((0, -0.1, 0.42), 0.3, "Secondary", scale=(0.95, 1.6, 0.45))


def golem():
	"""Голем: каменные блоки, светящееся ядро и кристаллы."""
	box((0, 0, 1.22), (0.9, 0.58, 0.78), "Primary", rot=(0, 0, math.radians(3)), bevel=0.09)
	box((0, 0.02, 0.76), (0.58, 0.42, 0.28), "Secondary", bevel=0.06)
	box((0, -0.12, 1.78), (0.34, 0.3, 0.3), "Primary", bevel=0.06)
	eyes(0.08, -0.27, 1.8, 0.035)
	sphere((0, -0.3, 1.26), 0.12, "Glow")
	for s in (1, -1):
		sphere((0.6 * s, 0, 1.5), 0.24, "Primary", scale=(1, 0.9, 0.85))
		box((0.68 * s, 0, 1.08), (0.28, 0.28, 0.46), "Secondary", rot=(0, math.radians(8 * s), 0), bevel=0.05)
		box((0.72 * s, -0.06, 0.62), (0.4, 0.4, 0.38), "Primary", rot=(0, 0, math.radians(10 * s)), bevel=0.07)
		box((0.22 * s, 0, 0.38), (0.3, 0.3, 0.6), "Primary", bevel=0.06)
		box((0.23 * s, -0.06, 0.06), (0.34, 0.42, 0.12), "Secondary", bevel=0.04)
		cone((0.55 * s, 0.05, 1.68), (0.62 * s, 0.1, 2.02), 0.07, "Glow", verts=6)
		cone((0.68 * s, 0.1, 1.62), (0.86 * s, 0.15, 1.86), 0.05, "Glow", verts=6)
	cone((0, 0.25, 1.55), (0, 0.4, 1.95), 0.08, "Glow", verts=6)
	cone((0.15, 0.28, 1.45), (0.25, 0.48, 1.8), 0.06, "Glow", verts=6)


def serpent():
	"""Морской змей: кольца тела, плавники, гребень."""
	pts = []
	n = 16
	for i in range(n):
		t = i / (n - 1)
		ang = t * 3.4 * math.pi
		rad = 0.42 * (1.0 - 0.75 * t)
		z = 0.13 + 0.55 * t
		r = 0.06 + 0.17 * math.sin(min(1.0, t * 1.6) * math.pi * 0.5)
		pts.append((rad * math.cos(ang), rad * math.sin(ang), z, r))
	last = pts[-1]
	neck = [(last[0] * 0.5, last[1] - 0.05, 1.0, 0.15), (0, -0.12, 1.32, 0.14), (0, -0.2, 1.55, 0.13), (0, -0.42, 1.62, 0.2, 0.16), (0, -0.72, 1.56, 0.11, 0.09)]
	sphere((0, -0.6, 1.47), 0.12, "Secondary", scale=(0.8, 1.6, 0.45))
	pts += neck
	skin(pts, [(i, i + 1) for i in range(len(pts) - 1)], "Primary", mirror=False)
	eyes(0.09, -0.5, 1.68, 0.035)
	for s in (1, -1):
		membrane((0.1 * s, -0.36, 1.66), [(0.42 * s, -0.25, 1.92), (0.48 * s, -0.12, 1.66), (0.36 * s, -0.1, 1.48)], "Secondary", mirror=False)
	for i in range(1, len(pts) - 2, 2):
		x, y, z = pts[i][:3]
		cone((x, y, z + pts[i][3] * 0.7), (x * 1.05, y * 1.05, z + pts[i][3] + 0.15), 0.05, "Secondary")
	cone((0, -0.3, 1.74), (0, -0.05, 1.98), 0.05, "Glow")


def bird():
	"""Грифон-птица: раскрытые крылья, клюв, хохолок, хвостовые перья."""
	skin([
		(0, 0.1, 0.78, 0.33, 0.3), (0, 0.45, 0.72, 0.16), (0, -0.2, 0.95, 0.33), (0, -0.3, 1.25, 0.18), (0, -0.36, 1.45, 0.2),
		(0.15, 0.02, 0.55, 0.13), (0.17, -0.04, 0.25, 0.07), (0.17, -0.12, 0.05, 0.06),
	], [(0, 1), (0, 2), (2, 3), (3, 4), (0, 5), (5, 6), (6, 7)], "Primary")
	cone((0, -0.52, 1.46), (0, -0.8, 1.36), 0.09, "Metal")
	eyes(0.12, -0.5, 1.54, 0.04)
	for i in range(4):
		cone((0, -0.32 + i * 0.07, 1.62), (0, -0.02 + i * 0.13, 1.88 - i * 0.04), 0.045, "Secondary")
	for side in (1, -1):
		for i in range(7):
			a = math.radians(15 + i * 18)
			base = Vector((0.25 * side, 0.05 + 0.03 * i, 1.0 + 0.02 * i))
			ln = 0.75 + 0.35 * math.sin(i / 6 * math.pi)
			tip = base + Vector((math.sin(a) * ln * side, 0.15 + 0.04 * i, math.cos(a) * ln))
			cone(tuple(base), tuple(tip), 0.09, "Secondary" if i % 2 else "Primary", verts=8)
	for i in range(5):
		a = -0.5 + i * 0.25
		cone((0, 0.5, 0.72), (math.sin(a) * 0.4, 1.0, 0.55 + 0.06 * (i % 2)), 0.08, "Secondary")
	for x in (0.14, -0.14):
		for k in (-1, 0, 1):
			cone((x, -0.12, 0.06), (x + 0.07 * k, -0.24, 0.02), 0.012, "Dark")


def wolf():
	"""Волк: стоит на четырёх лапах, грива, уши, пушистый хвост."""
	skin([
		(0, -0.15, 0.66, 0.3, 0.28), (0, 0.42, 0.6, 0.25, 0.23), (0, -0.4, 0.86, 0.2), (0, -0.55, 1.02, 0.22, 0.2), (0, -0.86, 0.95, 0.11, 0.09),
		(0, 0.65, 0.66, 0.11), (0, 0.95, 0.8, 0.13), (0, 1.15, 0.78, 0.05),
		(0.18, -0.16, 0.5, 0.12), (0.19, -0.19, 0.24, 0.085), (0.19, -0.28, 0.06, 0.08),
		(0.18, 0.42, 0.5, 0.15), (0.2, 0.52, 0.24, 0.09), (0.2, 0.42, 0.06, 0.08),
	], [(0, 1), (0, 2), (2, 3), (3, 4), (1, 5), (5, 6), (6, 7), (0, 8), (8, 9), (9, 10), (1, 11), (11, 12), (12, 13)], "Primary")
	mirror_x(cone, (0.11, -0.5, 1.15), (0.15, -0.46, 1.42), 0.075, "Primary")
	eyes(0.1, -0.7, 1.08, 0.04)
	sphere((0, -0.97, 0.97), 0.045, "Dark")
	sphere((0, -0.82, 0.86), 0.08, "Secondary", scale=(0.9, 1.4, 0.5))
	for i in range(11):
		a = -1.5 + i * 0.3
		cone((0.2 * math.sin(a), -0.36, 0.86 + 0.2 * math.cos(a)), (0.36 * math.sin(a), -0.08, 0.9 + 0.38 * math.cos(a)), 0.09, "Secondary")
	sphere((0, 1.0, 0.8), 0.17, "Secondary", scale=(0.8, 1.7, 0.85))
	cone((0, 1.2, 0.8), (0, 1.45, 0.86), 0.1, "Secondary")


def beetle():
	"""Жук-рыцарь: панцирь-надкрылья, рог, шесть лап."""
	sphere((0, 0.3, 0.62), 0.38, "Secondary", scale=(1, 1.35, 0.75))
	mirror_x(sphere, (0.17, 0.28, 0.75), 0.24, "Primary", scale=(0.85, 1.6, 0.6))
	sphere((0, -0.22, 0.7), 0.23, "Primary")
	sphere((0, -0.45, 0.74), 0.16, "Secondary")
	eyes(0.1, -0.56, 0.8, 0.04)
	skin([(0, -0.5, 0.86, 0.06), (0, -0.66, 1.05, 0.05), (0, -0.7, 1.3, 0.035), (0, -0.62, 1.45, 0.015)], [(0, 1), (1, 2), (2, 3)], "Metal", mirror=False, sub=1)
	mirror_x(cone, (0.08, -0.6, 0.7), (0.16, -0.78, 0.66), 0.03, "Metal")
	for y0, y1 in ((-0.28, -0.5), (-0.15, 0.0), (-0.02, 0.45)):
		skin([(0.15, y0, 0.62, 0.065), (0.42, (y0 + y1) / 2, 0.72, 0.055), (0.55, y1, 0.05, 0.04)], [(0, 1), (1, 2)], "Dark", sub=1)
	sphere((0, 0.78, 0.6), 0.09, "Glow")


ARCHETYPES = {
	"knight": knight, "centaur": centaur, "cyclops": cyclops, "flying_eye": flying_eye, "dragon": dragon,
	"golem": golem, "serpent": serpent, "bird": bird, "wolf": wolf, "beetle": beetle,
}


# ---------------------------------------------------------------- сборка, нормализация, экспорт

def normalize():
	"""Объединить всё в один меш, высота 1.0, основание на z=0, центр по XY."""
	obs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
	bpy.ops.object.select_all(action="DESELECT")
	for o in obs:
		o.select_set(True)
	bpy.context.view_layer.objects.active = obs[0]
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
	bpy.ops.object.join()
	ob = bpy.context.active_object
	vs = [v.co for v in ob.data.vertices]
	lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
	hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
	k = 1.0 / (hi.z - lo.z)
	c = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
	for v in ob.data.vertices:
		v.co = (v.co - c) * k
	bpy.ops.object.shade_auto_smooth(angle=math.radians(50))
	return ob


def preview(path):
	scn = bpy.context.scene
	scn.render.engine = "BLENDER_WORKBENCH"
	scn.display.shading.light = "STUDIO"
	scn.display.shading.color_type = "MATERIAL"
	scn.display.shading.show_cavity = True
	scn.display.shading.show_shadows = True
	scn.render.resolution_x = scn.render.resolution_y = 480
	scn.render.film_transparent = False
	cam_data = bpy.data.cameras.new("cam")
	cam = bpy.data.objects.new("cam", cam_data)
	scn.collection.objects.link(cam)
	cam.location = (1.35, -1.75, 1.05)
	d = Vector((0, 0, 0.5)) - cam.location
	cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
	cam_data.lens = 40
	scn.camera = cam
	scn.render.filepath = path
	bpy.ops.render.render(write_still=True)


def main():
	os.makedirs(OUT, exist_ok=True)
	for name, fn in ARCHETYPES.items():
		reset()
		fn()
		normalize()
		bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, name + ".glb"), export_format="GLB", export_apply=True)
		if PREVIEW:
			preview(os.path.join(OUT, "preview_" + name + ".png"))
		print("OK", name, flush=True)


main()
