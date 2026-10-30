"""Bake original base colour onto a repaired mesh; export UV loops, never rig/animations.
blender -b -t 8 -P ... -- SOURCE.glb REPAIRED.glb OUTPUT_PREFIX [resolution]
"""
import bpy,sys,json
from pathlib import Path
from mathutils import Matrix
args=sys.argv[sys.argv.index('--')+1:];source,target,prefix=map(lambda s:Path(s).resolve(),args[:3]);resolution=int(args[3]) if len(args)>3 else 4096
bpy.ops.wm.read_factory_settings(use_empty=True)
def load(path):
 # Blender RNA wrapper hashes can change when another import renames IDs.
 before={o.as_pointer() for o in bpy.data.objects};bpy.ops.import_scene.gltf(filepath=str(path));objects=[o for o in bpy.data.objects if o.as_pointer() not in before]
 print('IMPORTED',path,[(o.name,o.type) for o in objects],flush=True)
 for obj in objects:
  obj.animation_data_clear()
  if obj.type=='ARMATURE':
   for bone in obj.pose.bones:bone.matrix_basis=Matrix.Identity(4)
 return objects
src=load(source);dst=load(target)
# glTF's armature importer also creates an Icosphere bone-display mesh.
def skinned(objects):return [o for o in objects if o.type=='MESH' and any(m.type=='ARMATURE' for m in o.modifiers)]
source_meshes=skinned(src);target_meshes=skinned(dst)
assert len(target_meshes)==1,'Only one repaired mesh supported'
obj=target_meshes[0]
# Original primitive0 is the exterior; later primitives were the rejected inner covers.
for mesh in source_meshes:
 if len(mesh.material_slots)>1:
  import bmesh
  bm=bmesh.new();bm.from_mesh(mesh.data);bmesh.ops.delete(bm,geom=[f for f in bm.faces if f.material_index>0],context='FACES');bm.to_mesh(mesh.data);bm.free()
 for slot in mesh.material_slots:
  mat=slot.material
  if not mat:continue
  mat.use_nodes=True;nodes=mat.node_tree.nodes;links=mat.node_tree.links
  principled=next((n for n in nodes if n.type=='BSDF_PRINCIPLED'),None)
  output=next(n for n in nodes if n.type=='OUTPUT_MATERIAL')
  emission=nodes.new('ShaderNodeEmission');emission.inputs['Strength'].default_value=1
  if principled:
   colour=principled.inputs['Base Color'];emission.inputs['Color'].default_value=colour.default_value
   if colour.is_linked:links.new(colour.links[0].from_socket,emission.inputs['Color'])
  links.new(emission.outputs[0],output.inputs['Surface'])
bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
# Weld old UV-only duplicates before making a new continuous atlas.
bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.mesh.remove_doubles(threshold=0.0000005)
bpy.ops.uv.smart_project(angle_limit=1.151917,island_margin=.003,area_weight=.5,correct_aspect=True,scale_to_bounds=True)
bpy.ops.object.mode_set(mode='OBJECT');mesh=obj.data
image=bpy.data.images.new('RepairedColour',width=resolution,height=resolution,alpha=True);image.generated_color=(0,0,0,0);image.colorspace_settings.name='sRGB'
mat=bpy.data.materials.new('BakedRepair');mat.use_nodes=True;tex=mat.node_tree.nodes.new('ShaderNodeTexImage');tex.image=image;mat.node_tree.nodes.active=tex
mesh.materials.clear();mesh.materials.append(mat)
for face in mesh.polygons:face.material_index=0
bpy.ops.object.select_all(action='DESELECT')
for o in source_meshes:o.select_set(True)
obj.select_set(True);bpy.context.view_layer.objects.active=obj
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=1;scene.cycles.device='CPU';scene.render.bake.use_selected_to_active=True;scene.render.bake.use_clear=True;scene.render.bake.margin=16;scene.render.bake.cage_extrusion=.045;scene.render.bake.max_ray_distance=.085
print('BAKE_START',len(mesh.vertices),len(mesh.polygons),flush=True)
bpy.ops.object.bake(type='EMIT')
image.filepath_raw=str(prefix)+'.png';image.file_format='PNG';image.save()
uv=mesh.uv_layers.active.data
loops=[]
mesh.calc_loop_triangles()
for tri in mesh.loop_triangles:
 for loop_index in tri.loops:
  p=mesh.vertices[mesh.loops[loop_index].vertex_index].co;loops.append([float(p.x),float(p.z),float(-p.y),float(uv[loop_index].uv.x),float(uv[loop_index].uv.y)])
Path(str(prefix)+'-loops.json').write_text(json.dumps(loops,separators=(',',':')))
print('BAKE_DONE',len(loops),'loops',flush=True)
