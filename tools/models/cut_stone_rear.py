"""Prepare exact closed Stone surfaces with Blender CLI; see repair_stone_rear.py.

Preserves UVs and interpolates skin attributes. Never writes installed assets.
"""
import bpy,bmesh,sys,numpy as np
from pathlib import Path
sys.path.insert(0,'tools/models')
from inspect_geometry import read_glb,accessor,triangles
from upgrade_rigs import globals_of
Path('tools/_tmp/repair034').mkdir(parents=True,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
d,b=read_glb('tools/_tmp/repair033/crown-rebuilt/rogozhuk_stone.glb');p,v,f=next(triangles(d,b));uv=accessor(d,b,p['attributes']['TEXCOORD_0']);g=globals_of(d);ns={n.get('name'):i for i,n in enumerate(d['nodes'])};ce=g[ns['chest']][:3,3].copy();ce[1]=0
fw=g[ns['head']][:3,3]-g[ns['chest']][:3,3];fw[1]=0;fw/=np.linalg.norm(fw);fr=np.column_stack([np.cross([0,1,0],fw),[0,1,0],fw])
w=np.zeros((len(v),len(d['skins'][0]['joints'])))
for k in [0,1]:
 j=accessor(d,b,p['attributes']['JOINTS_'+str(k)]);a=accessor(d,b,p['attributes']['WEIGHTS_'+str(k)]);np.add.at(w,(np.arange(len(w))[:,None],j),a)
_,first,uid=np.unique(np.round(v,6),axis=0,return_index=True,return_inverse=True);u=v[first];coords=(u-ce)@fr
m=bpy.data.meshes.new('stone');m.from_pydata(coords.tolist(),[],uid[f].tolist());m.update();m.uv_layers.new(name='UVMap').data.foreach_set('uv',uv[f.ravel()].ravel())
for k in range(w.shape[1]):m.attributes.new('skin_%02d'%k,'FLOAT','POINT').data.foreach_set('value',w[first,k].astype(np.float32))
o=bpy.data.objects.new('stone',m);bpy.context.collection.objects.link(o);m.materials.append(bpy.data.materials.new('source'));cap=bpy.data.materials.new('cut');m.materials.append(cap)
from mathutils import Vector
# The oblique rear cut leaves the middle toes, which extend farther back at ground level.
for sign in [-1,1]:
 bpy.ops.mesh.primitive_cube_add(size=1,location=(sign*1.05,-.9925,-1.0));cut=bpy.context.object;cut.scale=(1.9,2.015,2.);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);cut.data.materials.append(cap)
 normal=np.array([0.,-.30,1.]);normal/=np.linalg.norm(normal);point=np.array([0.,0.,-.18])
 bpy.ops.mesh.primitive_cube_add(size=4,location=point-normal*2);half=bpy.context.object;half.rotation_mode='QUATERNION';half.rotation_quaternion=Vector((0,0,1)).rotation_difference(Vector(normal));half.data.materials.append(cap)
 bpy.context.view_layer.objects.active=cut;mod=cut.modifiers.new('protect_middle_toes','BOOLEAN');mod.operation='INTERSECT';mod.solver='EXACT';mod.object=half;bpy.ops.object.modifier_apply(modifier=mod.name);bpy.data.objects.remove(half,do_unlink=True)
 bpy.context.view_layer.objects.active=o;mod=o.modifiers.new('remove_fused_rear_loop','BOOLEAN');mod.operation='DIFFERENCE';mod.solver='EXACT';mod.object=cut;bpy.ops.object.modifier_apply(modifier=mod.name);bpy.data.objects.remove(cut,do_unlink=True)
bm=bmesh.new();bm.from_mesh(o.data);bmesh.ops.triangulate(bm,faces=[f for f in bm.faces if f.material_index==1]);bmesh.ops.dissolve_degenerate(bm,dist=1e-6,edges=[e for e in bm.edges if any(f.material_index==1 for f in e.link_faces)]);bm.to_mesh(o.data);bm.free()
m=o.data
for poly in m.polygons:poly.use_smooth=True
m.update();m.calc_loop_triangles();v=np.array([q.co[:] for q in m.vertices])@fr.T+ce;w=np.column_stack([np.array([q.value for q in m.attributes['skin_%02d'%k].data]) for k in range(w.shape[1])]);f=np.array([t.vertices[:] for t in m.loop_triangles]);loops=np.array([t.loops[:] for t in m.loop_triangles]);uv=np.array([q.uv[:] for q in m.uv_layers.active.data])[loops.ravel()];norm=np.array([q.vector[:] for q in m.corner_normals])[loops.ravel()]@fr.T;mat=np.array([t.material_index for t in m.loop_triangles]);ix=f.ravel()
np.savez('tools/_tmp/repair034/body.npz',v=v[ix],w=w[ix],n=norm,uv=uv,f=np.arange(len(ix)).reshape(-1,3),mat=mat)
print('CUT',len(v),len(f),'caps',int((mat==1).sum()),'weight range',w.sum(1).min(),w.sum(1).max(),flush=True)

import os
sys.stdout.flush()
os._exit(0)
