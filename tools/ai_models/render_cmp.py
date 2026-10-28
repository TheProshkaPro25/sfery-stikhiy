"""Рендер .glb для сравнения моделей (Cycles на CPU — не мешает генерации на GPU).

blender -b -P tools/ai_models/render_cmp.py -- <out.png> <a.glb> [b.glb ...]
Каждая модель — 2 ракурса (спереди-сбоку и сзади-сбоку), в ряд.
"""
import math
import sys

import bpy
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
out, models = args[0], args[1:]
S = 512

sc = bpy.context.scene
try:
    sc.render.engine = "CYCLES"
except TypeError:
    pass
sc.cycles.device = "CPU"
sc.cycles.samples = 24
sc.cycles.use_denoising = True
sc.render.resolution_x = S
sc.render.resolution_y = S
sc.render.film_transparent = False
world = bpy.data.worlds.new("w")
sc.world = world
world.use_nodes = True
bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
bg.inputs[0].default_value = (0.55, 0.57, 0.62, 1)
bg.inputs[1].default_value = 0.9

frames = []
for mi, path in enumerate(models):
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    # как в игре (_fix_hd_materials): у TRELLIS металл из карты x0.3, иначе без окружения модель чёрная
    for o in meshes:
        for slot in o.material_slots:
            nt = slot.material.node_tree
            bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
            met = bsdf.inputs["Metallic"]
            if met.is_linked:
                src = met.links[0].from_socket
                mul = nt.nodes.new("ShaderNodeMath")
                mul.operation = "MULTIPLY"
                mul.inputs[1].default_value = 0.3
                nt.links.new(src, mul.inputs[0])
                nt.links.new(mul.outputs[0], met)
            else:
                met.default_value = 0.0
    pts = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    ctr, size = (lo + hi) / 2, max(hi - lo)
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(50), 0, math.radians(30))
    bpy.context.collection.objects.link(sun)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    bpy.context.collection.objects.link(cam)
    sc.camera = cam
    for vi, ang in enumerate((-35, 145)):
        a = math.radians(ang)
        d = size * 1.9
        # glTF: Y вверх -> в Blender Z вверх, «перед» модели смотрит в -Y
        cam.location = ctr + Vector((math.sin(a) * d, -math.cos(a) * d, size * 0.45))
        cam.rotation_euler = (ctr - cam.location).to_track_quat("-Z", "Y").to_euler()
        f = f"{out}.{mi}_{vi}.png"
        sc.render.filepath = f
        bpy.ops.render.render(write_still=True)
        frames.append(f)
print("FRAMES", " ".join(frames))
