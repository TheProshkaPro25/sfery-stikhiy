"""Separate the fused Levian tip and bind each cut surface to its own chain.

Blender CLI, from the repository root. Immutable input: repair029/base (pre-cut
0.2.8 source). Output is an isolated candidate; never installs assets itself.
Run: blender -b --factory-startup -P tools/models/repair_levian_binding.py -- levian_fire
Validate with levian_binding_integrity.py and actual Godot pose intersections.
"""
import bpy,sys,json,copy,numpy as np
from pathlib import Path
sys.path.insert(0,str(Path.cwd()/'tools/models'))
from inspect_geometry import read_glb,accessor,triangles
def read_weights(d,b,p,count):
 w=np.zeros((len(accessor(d,b,p['attributes']['POSITION'])),count))
 for k in [0,1]:
  j=accessor(d,b,p['attributes']['JOINTS_'+str(k)]);a=accessor(d,b,p['attributes']['WEIGHTS_'+str(k)]);np.add.at(w,(np.arange(len(w))[:,None],j),a)
 return w

def store_weights(writer,p,w):
 top=np.argsort(-w,axis=1)[:,:8];a=np.take_along_axis(w,top,axis=1);a/=a.sum(1,keepdims=True)
 for k in [0,1]:
  p['attributes']['JOINTS_'+str(k)]=writer.add(top[:,k*4:k*4+4],'VEC4',5123)
  p['attributes']['WEIGHTS_'+str(k)]=writer.add(a[:,k*4:k*4+4],'VEC4')
from upgrade_rigs import Writer
from compact_glb import compact
CAP_SAMPLES={'levian_gale': [0.597900390625, 0.508056640625], 'levian_tide': [0.543701171875, 0.287353515625], 'levian_fire': [0.157958984375, 0.874755859375], 'levian_light': [0.162841796875, 0.038330078125], 'levian_shadow': [0.236572265625, 0.511474609375], 'levian_stone': [0.579833984375, 0.924560546875]}
ids=sys.argv[sys.argv.index('--')+1:]
for ident in ids:
 bpy.ops.wm.read_factory_settings(use_empty=True)
 d,b=read_glb('tools/_tmp/repair029/base/'+ident+'.glb');p,v,f=next(triangles(d,b));uv=accessor(d,b,p['attributes']['TEXCOORD_0']);w=read_weights(d,b,p,len(d['skins'][0]['joints']))
 unique,first,uid=np.unique(np.round(v,6),axis=0,return_index=True,return_inverse=True);unique=v[first]
 mesh=bpy.data.meshes.new('original');mesh.from_pydata(unique.tolist(),[],uid[f].tolist());mesh.update()
 layer=mesh.uv_layers.new(name='UVMap');layer.data.foreach_set('uv',uv[f.ravel()].ravel())
 for k in range(w.shape[1]):
  attr=mesh.attributes.new('skin_%02d'%k,'FLOAT','POINT');attr.data.foreach_set('value',w[first,k].astype(np.float32))
 obj=bpy.data.objects.new('levian',mesh);bpy.context.collection.objects.link(obj);bpy.context.view_layer.objects.active=obj;obj.select_set(True)
 original_mat=bpy.data.materials.new('original');cap_mat=bpy.data.materials.new('cap');mesh.materials.append(original_mat);mesh.materials.append(cap_mat)
 bpy.ops.mesh.primitive_cube_add(size=1,location=(-.55,-.65,.11));cutter=bpy.context.object;cutter.scale=(.93,1.,.14);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 cutter.data.materials.append(cap_mat)
 bpy.context.view_layer.objects.active=obj
 mod=obj.modifiers.new('complete_tail_separation','BOOLEAN');mod.operation='DIFFERENCE';mod.solver='EXACT';mod.object=cutter
 bpy.ops.object.modifier_apply(modifier=mod.name);bpy.data.objects.remove(cutter,do_unlink=True)
 import bmesh
 bm=bmesh.new();bm.from_mesh(obj.data)
 bmesh.ops.triangulate(bm,faces=[face for face in bm.faces if face.material_index==1],quad_method='BEAUTY',ngon_method='BEAUTY')
 cap_edges=[edge for edge in bm.edges if any(face.material_index==1 for face in edge.link_faces)]
 bmesh.ops.dissolve_degenerate(bm,dist=0.00001,edges=cap_edges)
 # Boolean plane cuts can insert collinear rim points. Remove only points
 # less than one millionth of a model unit from the opposite segment, preserving the surface.
 for cleanup_pass in range(3):
  dissolve=set()
  for face in bm.faces:
   if face.material_index!=1 or len(face.verts)!=3:continue
   points=[vert.co.copy() for vert in face.verts]
   for k in range(3):
    a=points[(k+1)%3];bpoint=points[(k+2)%3];axis=bpoint-a
    if axis.length_squared<1e-18:continue
    fraction=(points[k]-a).dot(axis)/axis.length_squared
    height=(points[k]-a-axis*fraction).length
    if 0.0001<fraction<.9999 and height<.000001:dissolve.add(face.verts[k]);break
  if not dissolve:break
  bmesh.ops.dissolve_verts(bm,verts=list(dissolve),use_face_split=False,use_boundary_tear=False)
  bmesh.ops.triangulate(bm,faces=[face for face in bm.faces if face.material_index==1],quad_method='BEAUTY',ngon_method='BEAUTY')

 # Discard only tiny newly cut islands, never original separate details.
 unseen=set(bm.verts);removed_fragments=[]
 while unseen:
  first_vertex=unseen.pop();component={first_vertex};pending=[first_vertex]
  while pending:
   vertex=pending.pop()
   for edge in vertex.link_edges:
    other=edge.other_vert(vertex)
    if other in unseen:unseen.remove(other);component.add(other);pending.append(other)
  if len(component)<300 and any(face.material_index==1 for vertex in component for face in vertex.link_faces):
   coords=np.array([vertex.co[:] for vertex in component])
   if (coords[:,0]<-.08).all() and (coords[:,1]<.05).all() and (coords[:,2]>-.04).all() and (coords[:,2]<.22).all():
    removed_fragments.append(len(component));bmesh.ops.delete(bm,geom=list(component),context='VERTS')
 print(ident,'removed cut fragments',removed_fragments,flush=True)
 bm.to_mesh(obj.data);bm.free()
 m=obj.data
 for poly in m.polygons:poly.use_smooth=True
 m.update();m.calc_loop_triangles()
 vv=np.array([q.co[:] for q in m.vertices]);ww=np.column_stack([np.array([q.value for q in m.attributes['skin_%02d'%k].data]) for k in range(w.shape[1])]);print(ident,'verts',len(vv),'weights',ww.sum(1).min(),ww.sum(1).max(),flush=True)
 if (ww.sum(1)<.99).any():
  from mathutils.kdtree import KDTree
  tree=KDTree(len(unique))
  for i,pt in enumerate(unique):tree.insert(pt,i)
  tree.balance()
  for i in np.flatnonzero(ww.sum(1)<.99):ww[i]=w[first[tree.find(vv[i])[1]]]
 names=[d['nodes'][node]['name'] for node in d['skins'][0]['joints']]
 hips=names.index('hips');coil=names.index('coil6')
 body=((vv[:,2]>.04001)|(vv[:,0]>-.14))&(vv[:,2]>-.04)
 for name in ['coil5','coil6']:
  slot=names.index(name);ww[body,hips]+=ww[body,slot];ww[body,slot]=0
 tail=~body
 t=np.clip((vv[:,2]+.12)/.16,0,1);amount=t*t*(3-2*t)*tail
 for name in ['hips','neck1','neck2']:
  slot=names.index(name);move=ww[:,slot]*amount;ww[:,slot]-=move;ww[:,coil]+=move
 # The two cut sections follow their own final bone; blend the seam into
 # adjacent source skin along mesh edges instead of mixing across the air gap.
 import heapq
 adjacency=[[] for _ in vv]
 for edge in m.edges:
  i,j=edge.vertices;length=float(np.linalg.norm(vv[i]-vv[j]));adjacency[i].append((j,length));adjacency[j].append((i,length))
 cap_vertices=np.unique(np.array([t.vertices[:] for t in m.loop_triangles if t.material_index==1]))
 # Classify complete connected cut surfaces, never individual rim points:
 # variant proportions can put part of one tail section across an x threshold.
 cap_links={int(i):set() for i in cap_vertices}
 for triangle in m.loop_triangles:
  if triangle.material_index!=1:continue
  i,j,k=map(int,triangle.vertices)
  cap_links[i].update([j,k]);cap_links[j].update([i,k]);cap_links[k].update([i,j])
 pending_caps=set(cap_links);tail_points=set()
 while pending_caps:
  seed=pending_caps.pop();component={seed};queue=[seed]
  while queue:
   vertex=queue.pop()
   for neighbor in cap_links[vertex]:
    if neighbor in pending_caps:pending_caps.remove(neighbor);component.add(neighbor);queue.append(neighbor)
  points=vv[list(component)]
  if np.median(np.abs(points[:,2]-.04))<.0001 and points[:,0].mean()<-.15:tail_points.update(component)
 tail_cap=np.array(sorted(tail_points),dtype=int)
 assert len(tail_cap)>20,'missing complete tail cross-section'
 body_cap=np.setdiff1d(cap_vertices,tail_cap)
 for seeds,slot in [(tail_cap,coil),(body_cap,hips)]:
  radius=.8 if slot==coil else .06
  distances=np.full(len(vv),np.inf);distances[seeds]=0.;queue=[(0.,int(i)) for i in seeds];heapq.heapify(queue)
  while queue:
   distance,i=heapq.heappop(queue)
   if distance>distances[i] or distance>radius:continue
   for j,length in adjacency[i]:
    next_distance=distance+length
    if next_distance<distances[j] and next_distance<radius:distances[j]=next_distance;heapq.heappush(queue,(next_distance,j))
  t=np.clip(1-distances/.06,0,1);amount=t*t*(3-2*t)
  ww*=1-amount[:,None];ww[:,slot]+=amount
  if slot==coil:tail_distance=distances.copy()
 # Taper cross-sections of the separated tip; the z coordinate stays monotonic.
 t=np.clip((vv[:,2]+.16)/.20,0,1);amount=t*t*(3-2*t)
 region=(vv[:,0]<-.085)&(vv[:,2]<.04001)
 assert not ((tail_distance>.65)&(tail_distance<.8)&region&(amount>0)).any(),'taper boundary crosses tail'
 amount*=region&(tail_distance<.8)
 centers=[]
 for z in np.linspace(-.16,.04,12):
  near=(abs(vv[:,2]-z)<.012)&(tail_distance<.4)
  if near.sum()>5:centers.append([z,*np.median(vv[near,:2],axis=0)])
 centers=np.array(centers)
 for axis in [0,1]:
  curve=np.polyfit(centers[:,0],centers[:,axis+1],2)
  center=np.polyval(curve,vv[:,2]);vv[:,axis]=center+(vv[:,axis]-center)*(1-.75*amount)
 m.vertices.foreach_set('co',vv.ravel());m.update();m.calc_loop_triangles()
 ff=np.array([t.vertices[:] for t in m.loop_triangles]);loops=np.array([t.loops[:] for t in m.loop_triangles]);material=np.array([t.material_index for t in m.loop_triangles]);uu=np.array([q.uv[:] for q in m.uv_layers.active.data]);normals=np.array([q.vector[:] for q in m.corner_normals])
 indices=ff.ravel();corner_uv=uu[loops.ravel()]
 _,first_corner,corner_ids=np.unique(np.column_stack([indices,corner_uv]),axis=0,return_index=True,return_inverse=True)
 point_ids=indices[first_corner]
 writer=Writer(d,b);attrs={'POSITION':writer.add(vv[point_ids],'VEC3'),'NORMAL':writer.add(normals[loops.ravel()[first_corner]],'VEC3'),'TEXCOORD_0':writer.add(corner_uv[first_corner],'VEC2')};tmp={'attributes':attrs};store_weights(writer,tmp,ww[point_ids])
 d['materials'].append(copy.deepcopy(d['materials'][p['material']]))
 d['materials'][-1]['name']='tail repair matching source texture'
 d['meshes'][0]['primitives']=[]
 for mat in [0,1]:
  ix=corner_ids.reshape(-1,3)[material==mat]
  primitive_attrs=dict(attrs)
  if mat==1:primitive_attrs['TEXCOORD_0']=writer.add(np.tile(CAP_SAMPLES[ident],(len(point_ids),1)),'VEC2')
  d['meshes'][0]['primitives'].append({'attributes':primitive_attrs,'indices':writer.add(ix.ravel()[:,None],'SCALAR',5125),'material':p['material'] if mat==0 else len(d['materials'])-1})
 d['asset'].setdefault('extras',{})['sfery_tail_separation']=2
 out=Path('tools/_tmp/repair031/rebuilt')/(ident+'.glb');out.parent.mkdir(parents=True,exist_ok=True);writer.save(out);compact(out)
 print(ident,'faces',len(ff),'cap',int((material==1).sum()),flush=True)
