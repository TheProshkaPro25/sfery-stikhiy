"""Individual anatomical reconstruction of Tide beetle's fused hind legs.

The generated U-shaped paddles are fused to the abdomen at both ends. Remove
those false appendages and close the cut abdomen with solid chitin. Reconstruct
the third pair from this same model's complete middle legs, retaining their
armour, claws, UVs and original texture; place three pivots per new hind leg.
Front/middle geometry and animation clips are retained. Run at repository root
following repair_beetles.py; the individual source is backed up once.
"""
import copy,io,json,shutil
from pathlib import Path
import numpy as np
from PIL import Image
from scipy.interpolate import CubicSpline
from scipy.spatial import cKDTree
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components
from scipy.spatial.transform import Rotation
from inspect_geometry import read_glb,accessor,triangles
from upgrade_rigs import Writer,globals_of
from repair_beetles import store_weights,smooth
from repair_skin import smooth_surface_weights

PATH=Path('assets/creatures_hd/rogozhuk_tide.glb')
BACKUP=Path('tools/_tmp/water-beetle027-base/rogozhuk_tide.glb')
# Measured in the model's anatomical frame (lateral, GLB height, forward).
OLD=np.array([[.230,.025,-.170],[.300,-.035,-.250],[.350,-.100,-.290],
              [.320,-.190,-.335],[.230,-.180,-.330],[.140,-.065,-.335]])

def read_weights(doc,binary,p,count):
 w=np.zeros((len(accessor(doc,binary,p['attributes']['POSITION'])),count))
 for group in (0,1):
  j=accessor(doc,binary,p['attributes']['JOINTS_'+str(group)]).astype(int)
  a=accessor(doc,binary,p['attributes']['WEIGHTS_'+str(group)])
  np.add.at(w,(np.arange(len(w))[:,None],j),a)
 return w

def cap_mesh(v,n,uv,w,f):
 """Close only the cut boundaries, welding UV seams for edge accounting."""
 _,uid=np.unique(np.round(v,6),axis=0,return_inverse=True);uid=uid.ravel()
 edge=np.concatenate((f[:,[0,1]],f[:,[1,2]],f[:,[2,0]]));key=np.sort(uid[edge],axis=1)
 _,inverse,counts=np.unique(key,axis=0,return_inverse=True,return_counts=True)
 boundary=edge[counts[inverse]==1];by_start={}
 existing_edges={tuple(e) for e in np.unique(key,axis=0)}
 for a,b in boundary:by_start.setdefault(int(uid[a]),[]).append((int(a),int(b)))
 rings=[];used=set()
 # A cut can leave two contours touching at one geometric vertex. Extract
 # simple directed cycles rather than making a self-intersecting polygon.
 for first in range(len(boundary)):
  a,b=map(int,boundary[first])
  if (int(uid[a]),int(uid[b])) in used:continue
  while (int(uid[a]),int(uid[b])) not in used:
   path=[];seen={};current=(a,b)
   for _ in range(len(boundary)+1):
    x,y=current;vertex=int(uid[x])
    if vertex in seen:
     cycle=path[seen[vertex]:];rings.append([e[0] for e in cycle])
     used.update((int(uid[x]),int(uid[y])) for x,y in cycle);break
    seen[vertex]=len(path);path.append(current)
    choices=[e for e in by_start.get(int(uid[y]),[]) if (int(uid[e[0]]),int(uid[e[1]])) not in used]
    assert choices,'open cut contour'
    current=choices[0]
   else:raise AssertionError('failed to extract cut contour')
 if not rings:return v,n,uv,w,f,0
 patches=[]
 for ring in rings:
  points=v[ring];normals=n[ring];count=len(ring)
  # Minimum-area 3D triangulation works for folded contours whose planar
  # projection self-overlaps. It uses the actual rim, without a centre fan.
  cost=np.full((count,count),np.inf);split=np.full((count,count),-1,int)
  for i in range(count-1):cost[i,i+1]=0
  for span in range(2,count):
   for i in range(count-span):
    j=i+span;ks=np.arange(i+1,j);cross=np.cross(points[ks]-points[i],points[j]-points[i]);area=np.linalg.norm(cross,axis=1)
    expected=normals[i]+normals[ks]+normals[j];expected/=np.maximum(np.linalg.norm(expected,axis=1,keepdims=True),1e-12)
    # Reversed winding closes the exterior's directed boundary.
    alignment=-(cross*expected).sum(1)/np.maximum(area,1e-12)
    perimeter=np.linalg.norm(points[ks]-points[i],axis=1)+np.linalg.norm(points[j]-points[ks],axis=1)+np.linalg.norm(points[j]-points[i])
    scores=cost[i,ks]+cost[ks,j]+area*(1+np.maximum(0,-alignment)*8)+.0002*perimeter
    if span<count-1 and tuple(sorted((int(uid[ring[i]]),int(uid[ring[j]])))) in existing_edges:continue
    best=int(np.argmin(scores));cost[i,j]=scores[best];split[i,j]=ks[best]
  assert np.isfinite(cost[0,count-1]),'cut contour cannot be sealed without crossing an existing edge'
  faces=[];pending=[(0,count-1)]
  while pending:
   i,j=pending.pop()
   if j<=i+1:continue
   k=int(split[i,j]);faces.append([i,k,j]);pending.extend([(i,k),(k,j)])
  patches.append(faces)
 caps=[]
 for ring,faces in zip(rings,patches):
  faces=np.asarray(ring)[np.asarray(faces)]
  # Tessellation winding can depend on the fitted plane. Every cap boundary
  # must oppose the corresponding exterior edge, not its estimated normal.
  boundary_set={(int(uid[ring[k]]),int(uid[ring[(k+1)%len(ring)]])) for k in range(len(ring))}
  same=opposite=0
  for tri in faces:
   for a,b in zip(tri,np.roll(tri,-1)):
    same+=(int(uid[a]),int(uid[b])) in boundary_set
    opposite+=(int(uid[b]),int(uid[a])) in boundary_set
  assert same==len(ring) or opposite==len(ring),(same,opposite,len(ring))
  if same:faces=faces[:,::-1]
  caps.extend(faces)
 f=np.concatenate([f,np.asarray(caps)])
 return v,n,uv,w,f,len(rings)

def repair():
 current,_=read_glb(PATH)
 if current.get('asset',{}).get('extras',{}).get('sfery_water_beetle_anatomy')==13:return
 BACKUP.parent.mkdir(parents=True,exist_ok=True)
 if not BACKUP.exists():shutil.copy2(PATH,BACKUP)
 doc,binary=read_glb(BACKUP);writer=Writer(doc,binary);skin=doc['skins'][0];gs=globals_of(doc)
 names={doc['nodes'][node]['name']:node for node in skin['joints']};slots={name:skin['joints'].index(node) for name,node in names.items()}
 center=gs[names['chest']][:3,3];fw=gs[names['head']][:3,3]-center;fw[1]=0;fw/=np.linalg.norm(fw)
 frame=np.column_stack([np.cross([0,1,0],fw),[0,1,0],fw])
 p,v,f=next(triangles(doc,binary));n=accessor(doc,binary,p['attributes']['NORMAL']);uv=accessor(doc,binary,p['attributes']['TEXCOORD_0']);w=read_weights(doc,binary,p,len(skin['joints']))
 c=(v-center)@frame;c[:,1]=v[:,1]
 material=doc['materials'][p['material']];texture=material['pbrMetallicRoughness']['baseColorTexture']['index'];im=doc['images'][doc['textures'][texture]['source']];bv=doc['bufferViews'][im['bufferView']]
 pixels=np.array(Image.open(io.BytesIO(binary[bv['byteOffset']:bv['byteOffset']+bv['byteLength']])).convert('RGB'))
 rgb=pixels[np.clip((uv[:,1]*len(pixels)).astype(int),0,len(pixels)-1),np.clip((uv[:,0]*pixels.shape[1]).astype(int),0,pixels.shape[1]-1)].astype(float)
 yellow=(rgb[:,0]>rgb[:,2]*1.7)&(rgb[:,1]>rgb[:,2]*1.3)
 t=np.r_[0,np.cumsum(np.linalg.norm(np.diff(OLD,axis=0),axis=1))];path=CubicSpline(t,OLD)(np.linspace(0,t[-1],600))
 remove=np.zeros(len(f),dtype=bool)
 for sign in (-1,1):
  canonical=c.copy();canonical[:,0]*=sign;distance,_=cKDTree(path).query(canonical)
  # Entire erroneous paddle, including red hinges and its body-side false tip.
  region=(canonical[:,0]>.085)&(canonical[:,2]<-.13)&(canonical[:,1]<.065)&(distance<.095)
  region&=(~yellow)|(canonical[:,0]>.29)
  remove|=region[f].mean(1)>.5
 # Tiny cut surfaces use solid chitin, avoiding radial UV fans over the repair.
 for name,color in [('Tide repaired abdominal chitin',[.43,.24,.035,1]),('Tide joint end chitin',[.045,.085,.095,1])]:
  doc['materials'].append({'name':name,'doubleSided':True,'pbrMetallicRoughness':{'baseColorFactor':color,'roughnessFactor':.75,'metallicFactor':0}})
 gold=len(doc['materials'])-2;dark=gold+1
 outputs=[];reports=[]
 def emit(vv,nn,uu,ww,faces,cap_material):
  original_faces=len(faces);loops=0
  if cap_material is not None:vv,nn,uu,ww,faces,loops=cap_mesh(vv,nn,uu,ww,faces)
  attrs={'POSITION':writer.add(vv,'VEC3'),'NORMAL':writer.add(nn,'VEC3'),'TEXCOORD_0':writer.add(uu,'VEC2')}
  for facegroup,material in [(faces[:original_faces],p['material']),(faces[original_faces:],cap_material)]:
   if not len(facegroup):continue
   output={'attributes':dict(attrs),'indices':writer.add(facegroup.ravel()[:,None],'SCALAR',5125),'material':material};store_weights(writer,output,ww);outputs.append(output)
  return loops
 def subset(selection):
  selected=f[selection]
  # Remove disconnected scraps of the deleted paddles, rather than capping
  # each sliver into a tiny zero-volume shell beside the real leg/body.
  _,geometric=np.unique(np.round(v,6),axis=0,return_inverse=True)
  edges=np.concatenate((geometric[selected[:,[0,1]]],geometric[selected[:,[1,2]]],geometric[selected[:,[2,0]]]))
  graph=coo_matrix((np.ones(len(edges)),edges.T),shape=(geometric.max()+1,geometric.max()+1))
  _,labels=connected_components(graph,directed=False);face_labels=labels[geometric[selected[:,0]]]
  groups,counts=np.unique(face_labels,return_counts=True);selected=selected[face_labels==groups[counts.argmax()]]
  indices=np.unique(selected);mapping=np.full(len(v),-1);mapping[indices]=np.arange(len(indices))
  return indices,mapping[selected]
 body_w=w.copy();rear_slots=[slot for name,slot in slots.items() if name.startswith('rear_')]
 removed=body_w[:,rear_slots].sum(1);body_w[:,rear_slots]=0;body_w[:,slots['hips']]+=removed
 # The abdomen stays on the torso, regardless of the six independently moving legs.
 torso=smooth((.30-np.abs(c[:,0]))/.14)*smooth((-.06-c[:,2])/.12)*smooth((.13-c[:,1])/.10)*smooth((c[:,1]+.27)/.10)
 limb=[slot for name,slot in slots.items() if name.startswith(('arm.','forearm.','hand.','thigh.','shin.','foot.'))]
 removed=body_w[:,limb].sum(1)*torso;body_w[:,limb]*=1-torso[:,None];body_w[:,slots['hips']]+=removed
 ii,faces=subset(~remove)
 body_weights=smooth_surface_weights(v[ii],faces,body_w[ii],.025)
 emit(v[ii],n[ii],uv[ii],body_weights,faces,gold)
 for sign,side in [(-1,'L'),(1,'R')]:
  source_slots=[slots[prefix+side] for prefix in ('thigh.','shin.','foot.')]
  influence=w[:,source_slots].sum(1)
  # This model's complete middle leg: actual boot, claw, tibia and femur.
  region=(influence>.18)&(c[:,0]*sign>.17)&(c[:,1]<-.070)&(c[:,2]>-.280)&(c[:,2]<.025)
  anatomical=np.array([((gs[names[prefix+side]][:3,3]-center)@frame) for prefix in ('thigh.','shin.','foot.')])
  for k,prefix in enumerate(('thigh.','shin.','foot.')):anatomical[k,1]=gs[names[prefix+side]][1,3]
  distance=np.full(len(c),10.)
  for a1,b1 in zip(anatomical[:-1],anatomical[1:]):
   direction=b1-a1;fraction=np.clip(((c-a1)@direction)/(direction@direction),0,1);distance=np.minimum(distance,np.linalg.norm(c-a1-fraction[:,None]*direction,axis=1))
  axis=anatomical[1]-anatomical[0];axis/=np.linalg.norm(axis)
  along=(c-anatomical[0])@axis
  distal=(c[:,1]<-.21)&(c[:,0]*sign>.19)&(c[:,2]>-.26)&(c[:,2]<.04)
  region=((distance<.110)|distal)&(along>.015)
  selection=region[f].mean(1)>.5
  ii,faces=subset(selection)
  # Rear hips sit inside the abdomen, narrower than the middle pair. The old
  # outward/back offset left a detached capped limb floating beside the body.
  offset=frame@np.array([-sign*.070,0,-.160])
  vv=v[ii].copy();nn=n[ii].copy();uu=uv[ii].copy();ww=np.zeros((len(ii),len(skin['joints'])))
  # The donor root is cut perpendicular to its femur, not along an irregular
  # weight threshold. Put its cut rim on that plane before closing it.
  _,uid=np.unique(np.round(vv,6),axis=0,return_inverse=True)
  edges=np.concatenate([faces[:,[0,1]],faces[:,[1,2]],faces[:,[2,0]]]);keys=np.sort(uid[edges],axis=1)
  _,inv,counts=np.unique(keys,axis=0,return_inverse=True,return_counts=True);rim=np.unique(edges[counts[inv]==1])
  rim=np.flatnonzero(np.isin(uid,np.unique(uid[rim])))
  cut_axis=frame@axis;cut_origin=frame@anatomical[0]+center;cut_origin[1]=anatomical[0,1]
  delta=(vv[rim]-cut_origin)@cut_axis-.015
  print('DONOR ROOT',side,'rim',len(rim),'plane offsets',np.quantile(delta,[0,.5,1]).tolist(),flush=True)
  assert np.abs(delta).max()<.065,'donor selection cut into the distal leg'
  vv[rim]-=delta[:,None]*cut_axis
  vv+=offset
  mass=w[ii][:,source_slots];mass/=np.maximum(mass.sum(1,keepdims=True),1e-12)
  for k,prefix in enumerate(('rear_thigh.','rear_shin.','rear_foot.')):ww[:,slots[prefix+side]]=mass[:,k]
  progress=(vv-offset-cut_origin)@cut_axis
  attachment=1-smooth((progress-.015)/.060)
  ww*=1-attachment[:,None];ww[:,slots['hips']]+=attachment
  for old_prefix,new_prefix in zip(('thigh.','shin.','foot.'),('rear_thigh.','rear_shin.','rear_foot.')):
   node=names[new_prefix+side];target=gs[names[old_prefix+side]].copy();target[:3,3]+=offset
   parent=next(k for k,nod in enumerate(doc['nodes']) if node in nod.get('children',[]));local=np.linalg.inv(gs[parent])@target
   doc['nodes'][node]['translation']=local[:3,3].tolist();doc['nodes'][node]['rotation']=Rotation.from_matrix(local[:3,:3]).as_quat().tolist();gs[node]=target
  loops=emit(vv,nn,uu,ww,faces,dark)
  reports.append({'side':side,'leg_vertices':len(ii),'root_caps':loops,'copied_from':'actual middle leg, original textured geometry','offset_anatomical':[-sign*.070,0,-.160]})
 # Close the actual cut exterior above; discard the old inner masking volumes.
 doc['meshes'][0]['primitives']=outputs
 new_globals=globals_of(doc);inverse=accessor(doc,binary,skin['inverseBindMatrices']).copy()
 for name in names:
  if name.startswith('rear_'):inverse[slots[name]]=np.linalg.inv(new_globals[names[name]]).T.ravel()
 skin['inverseBindMatrices']=writer.add(inverse,'MAT4');doc['asset'].setdefault('extras',{})['sfery_water_beetle_anatomy']=13
 writer.save(PATH);Path('tools/_tmp/review028/water-reconstruction.json').write_text(json.dumps(reports,indent=2));print(json.dumps(reports,indent=2))
if __name__=='__main__':repair()
