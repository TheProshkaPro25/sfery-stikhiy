"""Rebuild Light rear sockets with planar, tapered, closed roots. Blender CLI.

Run: blender -b --factory-startup -P tools/models/repair_light_sockets035.py -- INPUT.glb OUTPUT.glb
Writes a candidate only; never selects or installs a game asset implicitly.
"""
import bpy,bmesh,sys,os,heapq,numpy as np
from pathlib import Path
from mathutils import Vector
from mathutils.kdtree import KDTree
sys.path.insert(0,'tools/models')
from inspect_geometry import read_glb,accessor,triangles
from upgrade_rigs import Writer,globals_of
from compact_glb import compact
args=sys.argv[sys.argv.index('--')+1:];assert len(args)==2,'INPUT.glb OUTPUT.glb required';src=Path(args[0]);d,b=read_glb(src);parts=list(triangles(d,b));g=globals_of(d);ns={n.get('name'):i for i,n in enumerate(d['nodes'])};skin=d['skins'][0];slots={d['nodes'][node]['name']:i for i,node in enumerate(skin['joints'])};writer=Writer(d,b);outputs=d['meshes'][0]['primitives'][:2]
for side,start in [('L',2),('R',4)]:
 bpy.ops.wm.read_factory_settings(use_empty=True);p,v,f=parts[start];f=np.concatenate([f,parts[start+1][2]]);uv=accessor(d,b,p['attributes']['TEXCOORD_0']);weights=np.zeros((len(v),len(slots)))
 for k in [0,1]:
  j=accessor(d,b,p['attributes']['JOINTS_'+str(k)]);w=accessor(d,b,p['attributes']['WEIGHTS_'+str(k)]);np.add.at(weights,(np.arange(len(v))[:,None],j),w)
 _,first,uid=np.unique(np.round(v,6),axis=0,return_index=True,return_inverse=True);u=v[first];m=bpy.data.meshes.new('source_leg');m.from_pydata(u.tolist(),[],uid[f].tolist());m.update();m.uv_layers.new(name='UVMap').data.foreach_set('uv',uv[f.ravel()].ravel())
 for k in range(len(slots)):m.attributes.new('skin_%02d'%k,'FLOAT','POINT').data.foreach_set('value',weights[first,k].astype(np.float32))
 m.materials.append(bpy.data.materials.new('source'));cap=bpy.data.materials.new('cap');m.materials.append(cap)
 for poly in list(m.polygons)[len(parts[start][2]):]:poly.material_index=1
 obj=bpy.data.objects.new('clean_rear_'+side,m);bpy.context.collection.objects.link(obj);origin=g[ns['rear_thigh.'+side]][:3,3];axis=g[ns['rear_shin.'+side]][:3,3]-origin;axis/=np.linalg.norm(axis)
 bpy.ops.mesh.primitive_cube_add(size=4,location=origin+axis*(2+.07));cut=bpy.context.object;cut.rotation_mode='QUATERNION';cut.rotation_quaternion=Vector((0,0,1)).rotation_difference(Vector(axis));cut.data.materials.append(cap);bpy.context.view_layer.objects.active=obj;mod=obj.modifiers.new('replace_folded_socket','BOOLEAN');mod.operation='INTERSECT';mod.solver='EXACT';mod.object=cut;bpy.ops.object.modifier_apply(modifier=mod.name);bpy.data.objects.remove(cut,do_unlink=True)
 bm=bmesh.new();bm.from_mesh(obj.data);bmesh.ops.triangulate(bm,faces=[f for f in bm.faces if f.material_index==1]);bmesh.ops.dissolve_degenerate(bm,dist=1e-6,edges=[e for e in bm.edges if any(f.material_index==1 for f in e.link_faces)]);bm.to_mesh(obj.data);bm.free();m=obj.data
 vv=np.array([q.co[:] for q in m.vertices]);ww=np.column_stack([np.array([q.value for q in m.attributes['skin_%02d'%k].data]) for k in range(len(slots))]);tree=KDTree(len(u))
 for i,pt in enumerate(u):tree.insert(pt,i)
 tree.balance()
 for i in np.flatnonzero(ww.sum(1)<.99):ww[i]=weights[first[tree.find(vv[i])[1]]]
 m.calc_loop_triangles();cap_ids=np.unique([i for t in m.loop_triangles if t.material_index==1 for i in t.vertices]);assert len(cap_ids)>10
 along=(vv-origin)@axis;print(side,'cap plane range',along[cap_ids].min(),along[cap_ids].max(),flush=True);assert np.max(abs(along[cap_ids]-.07))<1e-5
 # Longitudinal extension is monotonic. Scale whole cross-sections, not rim vertices.
 x=np.clip((along-.07)/.07,0,1);blend=1-x*x*(3-2*x);vv-=.055*blend[:,None]*axis
 center=np.median(vv[cap_ids],axis=0);t=(vv-center)@axis;centerline=center+t[:,None]*axis;vv=centerline+(vv-centerline)*(1-.55*blend[:,None])
 # Keep the complete root section on the abdomen with a continuous surface transition.
 edges=np.array([e.vertices[:] for e in m.edges]);adj=[[] for _ in vv]
 for i,j in edges:
  length=float(np.linalg.norm(vv[i]-vv[j]));adj[i].append((j,length));adj[j].append((i,length))
 dist=np.full(len(vv),np.inf);dist[cap_ids]=0;queue=[(0.,int(i)) for i in cap_ids];heapq.heapify(queue)
 while queue:
  distance,i=heapq.heappop(queue)
  if distance>dist[i] or distance>.06:continue
  for j,length in adj[i]:
   nd=distance+length
   if nd<dist[j] and nd<.06:dist[j]=nd;heapq.heappush(queue,(nd,j))
 x=np.clip(1-dist/.06,0,1);blend=x*x*(3-2*x);ww*=1-blend[:,None];ww[:,slots['hips']]+=blend
 # Collapse submicron Boolean slivers consistently with geometric seam welding.
 _,first_clean,uid_clean=np.unique(np.round(vv,6),axis=0,return_index=True,return_inverse=True);vv=vv[first_clean[uid_clean]]
 m.vertices.foreach_set('co',vv.ravel())
 for poly in m.polygons:poly.use_smooth=True
 m.update();m.calc_loop_triangles();f=np.array([t.vertices[:] for t in m.loop_triangles]);loops=np.array([t.loops[:] for t in m.loop_triangles]);material=np.array([t.material_index for t in m.loop_triangles]);tex=np.array([q.uv[:] for q in m.uv_layers.active.data])[loops.ravel()];nn=np.array([q.vector[:] for q in m.corner_normals])[loops.ravel()];indices=f.ravel();_,ix,remap=np.unique(np.column_stack([indices,tex]),axis=0,return_index=True,return_inverse=True);point=indices[ix];attrs={'POSITION':writer.add(vv[point],'VEC3'),'NORMAL':writer.add(nn[ix],'VEC3'),'TEXCOORD_0':writer.add(tex[ix],'VEC2')};mass=ww[point];top=np.argsort(-mass,axis=1)[:,:8];w=np.take_along_axis(mass,top,axis=1);w/=w.sum(1,keepdims=True)
 for k in [0,1]:attrs['JOINTS_'+str(k)]=writer.add(top[:,4*k:4*k+4],'VEC4',5123);attrs['WEIGHTS_'+str(k)]=writer.add(w[:,4*k:4*k+4],'VEC4')
 valid=np.array([len(set(q))==3 for q in uid_clean[f]])
 for mat in [0,1]:outputs.append({'attributes':dict(attrs),'indices':writer.add(remap.reshape(-1,3)[(material==mat)&valid].ravel()[:,None],'SCALAR',5125),'material':parts[start+mat][0]['material']})
d['meshes'][0]['primitives']=outputs;d['asset'].setdefault('extras',{})['light_socket_repair']=1;out=Path(args[1]);out.parent.mkdir(parents=True,exist_ok=True);writer.save(out);compact(out);sys.stdout.flush();os._exit(0)
