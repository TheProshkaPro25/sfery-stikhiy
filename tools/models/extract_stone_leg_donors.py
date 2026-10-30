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
from mathutils import Vector
for sign,side in [(-1,'L'),(1,'R')]:
 o=bpy.data.objects.new('donor_'+side,m.copy());bpy.context.collection.objects.link(o);o.data.materials.append(bpy.data.materials.new('source'));cap=bpy.data.materials.new('cut');o.data.materials.append(cap)
 origin=(g[ns['thigh.'+side]][:3,3]-ce)@fr;mid=(g[ns['shin.'+side]][:3,3]-ce)@fr;foot=(g[ns['foot.'+side]][:3,3]-ce)@fr;axis=mid-origin;axis/=np.linalg.norm(axis)
 bpy.ops.mesh.primitive_cube_add(size=4,location=origin+axis*(2+.055));cut=bpy.context.object;cut.rotation_mode='QUATERNION';cut.rotation_quaternion=Vector((0,0,1)).rotation_difference(Vector(axis));bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);cut.data.materials.append(cap)
 bpy.context.view_layer.objects.active=o;mod=o.modifiers.new('clean_femur_section','BOOLEAN');mod.operation='INTERSECT';mod.solver='EXACT';mod.object=cut;bpy.ops.object.modifier_apply(modifier=mod.name);bpy.data.objects.remove(cut,do_unlink=True)
 bpy.ops.mesh.primitive_cube_add(size=1,location=(sign*1.06,-.5,-.115));cut=bpy.context.object;cut.scale=(1.88,2.,.31);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);cut.data.materials.append(cap)
 bpy.context.view_layer.objects.active=o;mod=o.modifiers.new('isolate_middle_leg','BOOLEAN');mod.operation='INTERSECT';mod.solver='EXACT';mod.object=cut;bpy.ops.object.modifier_apply(modifier=mod.name);bpy.data.objects.remove(cut,do_unlink=True)
 # Trim the false back strap fused to the left middle femur; keep the distal boot.
 normal=np.array([0.,-.30,1.]);normal/=np.linalg.norm(normal);point=np.array([0.,0.,-.18])
 bpy.ops.mesh.primitive_cube_add(size=4,location=point+normal*2);cut=bpy.context.object;cut.rotation_mode='QUATERNION';cut.rotation_quaternion=Vector((0,0,1)).rotation_difference(Vector(normal));cut.data.materials.append(cap)
 bpy.context.view_layer.objects.active=o;mod=o.modifiers.new('remove_donor_back_strap','BOOLEAN');mod.operation='INTERSECT';mod.solver='EXACT';mod.object=cut;bpy.ops.object.modifier_apply(modifier=mod.name);bpy.data.objects.remove(cut,do_unlink=True)
 bm=bmesh.new();bm.from_mesh(o.data);unseen=set(bm.verts);components=[]
 while unseen:
  seed=unseen.pop();component={seed};queue=[seed]
  while queue:
   vtx=queue.pop()
   for edge in vtx.link_edges:
    neighbor=edge.other_vert(vtx)
    if neighbor in unseen:unseen.remove(neighbor);component.add(neighbor);queue.append(neighbor)
  components.append(component)
 keep=min(components,key=lambda co:min((np.linalg.norm(np.array(v.co)-foot) for v in co)))
 print(side,'components',[len(co) for co in components],'chosen',len(keep),flush=True)
 bmesh.ops.delete(bm,geom=[v for co in components if co is not keep for v in co],context='VERTS');bmesh.ops.triangulate(bm,faces=[f for f in bm.faces if f.material_index==1]);bmesh.ops.dissolve_degenerate(bm,dist=1e-6,edges=[e for e in bm.edges if any(f.material_index==1 for f in e.link_faces)]);bm.to_mesh(o.data);bm.free()
 mesh=o.data
 for poly in mesh.polygons:poly.use_smooth=True
 mesh.update();mesh.calc_loop_triangles();v=np.array([q.co[:] for q in mesh.vertices]);weights=np.column_stack([np.array([q.value for q in mesh.attributes['skin_%02d'%k].data]) for k in range(w.shape[1])]);faces=np.array([t.vertices[:] for t in mesh.loop_triangles]);loops=np.array([t.loops[:] for t in mesh.loop_triangles]);tex=np.array([q.uv[:] for q in mesh.uv_layers.active.data])[loops.ravel()];norm=np.array([q.vector[:] for q in mesh.corner_normals])[loops.ravel()]@fr.T;mat=np.array([t.material_index for t in mesh.loop_triangles]);ix=faces.ravel();cap_points=v[np.unique(faces[mat==1])];print(side,'cap along range',np.quantile((cap_points-origin)@axis,[0,.5,1]),flush=True)
 vv=v@fr.T+ce
 np.savez('tools/_tmp/repair034/donor-'+side+'.npz',v=vv[ix],w=weights[ix],n=norm,uv=tex,f=np.arange(len(ix)).reshape(-1,3),mat=mat)
 bpy.data.objects.remove(o,do_unlink=True)

import os
sys.stdout.flush()
os._exit(0)
