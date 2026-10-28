"""Ортопроекции модели с сеткой 0.1 — для снятия точек скелета (rig_species.py SKELETONS).

  blender -b --factory-startup -P tools/blender/inspect_mesh.py -- <in.glb> <png-префикс> [--yaw <градусы>] [--rig <вид>]
--rig рисует поверх кости из SKELETONS (в системе после --yaw): голова кости жёлтая, тело кости зелёное.
--yaw поворачивает модель вокруг Z (головой к -Y) — точки скелета снимаются в этой системе, см. YAW в rig_species.py.
Даёт <префикс>_front.png (X–Z, смотрим с -Y), _side.png (Y–Z, смотрим с +X), _top.png (X–Y, сверху).
Подписи сетки: каждые 0.1, жирные линии через 0.5 не нужны — рамка модели около 1.
"""
import math
import os
import sys

import bpy
from mathutils import Euler

args = sys.argv[sys.argv.index("--") + 1:]
src, prefix = args[0], args[1]
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.import_scene.gltf(filepath=src)
mesh = next(o for o in bpy.data.objects if o.type == "MESH")
if "--yaw" in args:
    from mathutils import Matrix
    mesh.matrix_world = Matrix.Rotation(math.radians(float(args[args.index("--yaw") + 1])), 4, "Z") @ mesh.matrix_world
    bpy.context.view_layer.update()
co = [mesh.matrix_world @ v.co for v in mesh.data.vertices]
lo = [min(c[i] for c in co) for i in range(3)]
hi = [max(c[i] for c in co) for i in range(3)]
print("BBOX", [round(x, 3) for x in lo], [round(x, 3) for x in hi])

sc = bpy.context.scene
sc.render.engine = "BLENDER_WORKBENCH"
sc.display.shading.color_type = "TEXTURE"
sc.display.shading.show_xray = True
sc.display.shading.xray_alpha = 0.75
sc.render.resolution_x = sc.render.resolution_y = 900
sc.render.film_transparent = False
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
bpy.context.collection.objects.link(cam)
sc.camera = cam
cam.data.type = "ORTHO"
cam.data.ortho_scale = 1.2
cam.data.clip_end = 100

# Сетка: тонкие цилиндры-линии каждые 0.1 в трёх плоскостях, ось 0 — красная.
def mat(name, rgb):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*rgb, 1)
    return m
grey, red = mat("g", (0.15, 0.15, 0.15)), mat("r", (1, 0, 0))

def line(p, rot, length, m):
    bpy.ops.mesh.primitive_cylinder_add(radius=0.0018, depth=length, location=p, rotation=rot, vertices=6)
    o = bpy.context.object
    o.data.materials.append(m)
    o.color = m.diffuse_color
    return o

ticks = [i / 10 for i in range(-6, 7)]
views = {
    # имя: (позиция камеры, поворот камеры, функция: координата тика -> две линии)
    "front": ((0, -5, 0), (90, 0, 0)),
    "side": ((5, 0, 0), (90, 0, 90)),
    "top": ((0, 0, 5), (0, 0, 0)),
}
grid = {}
for v in views:
    objs = []
    for t in ticks:
        m = red if abs(t) < 1e-6 else grey
        if v == "front":
            objs.append(line((t, -1, 0), (0, 0, 0), 1.2, m))            # вертикаль X=t
            objs.append(line((0, -1, t), (0, math.pi / 2, 0), 1.2, m))  # горизонталь Z=t
        elif v == "side":
            objs.append(line((1, t, 0), (0, 0, 0), 1.2, m))
            objs.append(line((1, 0, t), (math.pi / 2, 0, 0), 1.2, m))
        else:
            objs.append(line((t, 0, 1), (math.pi / 2, 0, 0), 1.2, m))
            objs.append(line((0, t, 1), (0, math.pi / 2, 0), 1.2, m))
    grid[v] = objs
if "--rig" in args:
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import rig_species
    from mathutils import Vector
    yel, grn = mat("y", (1, 0.9, 0)), mat("gr", (0, 1, 0.2))
    for name, h, t, _p, _d in rig_species.SKELETONS[args[args.index("--rig") + 1]]:
        h, t = Vector(h), Vector(t)
        d = t - h
        bpy.ops.mesh.primitive_cylinder_add(radius=0.006, depth=d.length, location=(h + t) / 2, vertices=6)
        o = bpy.context.object
        o.rotation_mode = "QUATERNION"
        o.rotation_quaternion = d.to_track_quat("Z", "Y")
        o.data.materials.append(grn)
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.012, location=h, segments=8, ring_count=6)
        bpy.context.object.data.materials.append(yel)
    sc.display.shading.color_type = "MATERIAL"  # кости видны цветом; модель — серым силуэтом
for v, (loc, rot) in views.items():
    for k, objs in grid.items():
        for o in objs:
            o.hide_render = k != v
    cam.location = loc
    cam.rotation_euler = Euler([math.radians(a) for a in rot])
    sc.render.filepath = f"{prefix}_{v}.png"
    bpy.ops.render.render(write_still=True)
