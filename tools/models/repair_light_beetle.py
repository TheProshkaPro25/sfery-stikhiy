"""Rebuild the Light beetle's false hind appendages from its own middle legs.

Source: tools/_tmp/repair029/base/rogozhuk_light.glb.
Output candidate: tools/_tmp/repair029/light-anatomy.glb.
Validate with beetle_integrity and beetle_attachment (including engine poses)
and view all six exterior surfaces before installing the candidate.
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

PATH=Path('tools/_tmp/repair029/light-anatomy.glb')
BACKUP=Path('tools/_tmp/repair029/base/rogozhuk_light.glb')
# Measured in the model's anatomical frame (lateral, GLB height, forward).
OLD=np.array([[.230,.025,-.170],[.300,-.035,-.250],[.350,-.100,-.290],
              [.320,-.190,-.335],[.230,-.180,-.330],[.140,-.065,-.335]])

from repair_water_beetle import read_weights, cap_mesh
from compact_glb import compact

def repair():
 # Always rebuild this candidate from the preserved source.
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
  region|=(canonical[:,0]>.17)&(canonical[:,2]<-.18)&(canonical[:,1]<.06)
  remove|=region[f].mean(1)>.5
 # Tiny cut surfaces use solid chitin, avoiding radial UV fans over the repair.
 for name,color in [('Light repaired abdominal chitin',[.43,.24,.035,1]),('Light joint end chitin',[.045,.085,.095,1])]:
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
 torso=np.maximum(smooth((.30-np.abs(c[:,0]))/.14)*smooth((-.06-c[:,2])/.12)*smooth((.13-c[:,1])/.10)*smooth((c[:,1]+.27)/.10), smooth((-.17-c[:,2])/.10)*smooth((.13-c[:,1])/.10))
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
  offset=frame@np.array([-sign*.140,0,-.120])
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
  reports.append({'side':side,'leg_vertices':len(ii),'root_caps':loops,'copied_from':'actual middle leg, original textured geometry','offset_anatomical':[-sign*.140,0,-.120]})
 # Close the actual cut exterior above; discard the old inner masking volumes.
 doc['meshes'][0]['primitives']=outputs
 new_globals=globals_of(doc);inverse=accessor(doc,binary,skin['inverseBindMatrices']).copy()
 for name in names:
  if name.startswith('rear_'):inverse[slots[name]]=np.linalg.inv(new_globals[names[name]]).T.ravel()
 skin['inverseBindMatrices']=writer.add(inverse,'MAT4');doc['asset'].setdefault('extras',{})['sfery_light_beetle_anatomy']=13
 writer.save(PATH);compact(PATH);Path('tools/_tmp/repair029/light-reconstruction.json').write_text(json.dumps(reports,indent=2));print(json.dumps(reports,indent=2))
if __name__=='__main__':repair()
