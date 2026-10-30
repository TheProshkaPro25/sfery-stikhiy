"""Rebuild the Stone hind pair and stabilize its solid stone limb skin.

Run from the repository root, using the saved crown-rebuilt033 source:
  blender -b --factory-startup -P tools/models/cut_stone_rear.py
  blender -b --factory-startup -P tools/models/extract_stone_leg_donors.py
  <python-with-scipy-pillow> tools/models/repair_stone_rear.py
Writes tools/_tmp/repair034/candidate only. Review actual Godot poses, attachment,
surface preservation and support before installing. The rigid-limb GLTF metadata
is consumed by CreatureSupport; it preserves the sculpt while planting each foot.
The six rear bone binds are rebuilt together; existing non-rear clips stay intact.
"""
from pathlib import Path
import sys,io,numpy as np
from PIL import Image
from scipy.spatial import cKDTree
from scipy.spatial.transform import Rotation
sys.path.insert(0,'tools/models')
from inspect_geometry import read_glb,accessor,triangles
from upgrade_rigs import Writer,globals_of
from repair_water_beetle import read_weights
from repair_beetles import store_weights,smooth
from compact_glb import compact
source='tools/_tmp/repair033/crown-rebuilt/rogozhuk_stone.glb';d,b=read_glb(source);writer=Writer(d,b);p,v,f=next(triangles(d,b));n=accessor(d,b,p['attributes']['NORMAL']);uv=accessor(d,b,p['attributes']['TEXCOORD_0']);skin=d['skins'][0];w=read_weights(d,b,p,len(skin['joints']));gs=globals_of(d);names={d['nodes'][node]['name']:node for node in skin['joints']};slots={name:skin['joints'].index(node) for name,node in names.items()};center=gs[names['chest']][:3,3].copy();center[1]=0;fw=gs[names['head']][:3,3]-gs[names['chest']][:3,3];fw[1]=0;fw/=np.linalg.norm(fw);frame=np.column_stack([np.cross([0,1,0],fw),[0,1,0],fw]);c=(v-center)@frame
# A solid section samples the original texture with its existing colour space.
mat=d['materials'][p['material']];im=d['images'][d['textures'][mat['pbrMetallicRoughness']['baseColorTexture']['index']]['source']];bv=d['bufferViews'][im['bufferView']];pixels=np.array(Image.open(io.BytesIO(b[bv['byteOffset']:bv['byteOffset']+bv['byteLength']])).convert('RGB'));near=(c[:,1]>.015)&(c[:,1]<.06)&(c[:,2]<-.22);sample_uv=uv[near];rgb=pixels[np.clip((sample_uv[:,1]*len(pixels)).astype(int),0,len(pixels)-1),np.clip((sample_uv[:,0]*pixels.shape[1]).astype(int),0,pixels.shape[1]-1)];target=np.median(rgb,axis=0);cap_uv=sample_uv[np.linalg.norm(rgb-target,axis=1).argmin()];print('cap UV',cap_uv,'colour',target,flush=True)
outputs=[]
def emit(vv,nn,uu,ww,faces,cap_flags):
 for cap in [False,True]:
  ff=faces[cap_flags==cap]
  if not len(ff):continue
  used,remap=np.unique(ff,return_inverse=True)
  sampled_uv=np.tile(cap_uv,(len(used),1)) if cap else uu[used]
  _,first,joined=np.unique(np.column_stack([vv[used],sampled_uv]),axis=0,return_index=True,return_inverse=True)
  remap=joined[remap];used=used[first];sampled_uv=sampled_uv[first]
  attrs={'POSITION':writer.add(vv[used],'VEC3'),'NORMAL':writer.add(nn[used],'VEC3'),'TEXCOORD_0':writer.add(sampled_uv,'VEC2')}
  pr={'attributes':attrs,'indices':writer.add(remap.ravel()[:,None],'SCALAR',5125),'material':p['material']};store_weights(writer,pr,ww[used]);outputs.append(pr)
body=np.load('tools/_tmp/repair034/body.npz');bw=body['w'].copy();missing=bw.sum(1)<.99;bw[missing]=w[cKDTree(v).query(body['v'][missing])[1]]
rear=[slot for name,slot in slots.items() if name.startswith('rear_')];bw[:,slots['hips']]+=bw[:,rear].sum(1);bw[:,rear]=0;assert bw.sum(1).min()>.99
bc=(body['v']-center)@frame
shell=smooth((bc[:,1]+.10)/.06)*smooth((.18-bc[:,2])/.10)
core=smooth((.22-np.abs(bc[:,0]))/.06)*smooth((-.13-bc[:,2])/.08)*smooth((bc[:,1]+.24)/.05)
torso=np.maximum(shell,core);bw*=1-torso[:,None];bw[:,slots['hips']]+=torso
for side in ['L','R']:
 for root_prefix,children in [('thigh.',['shin.','foot.']),('arm.',['forearm.','hand.'])]:
  for prefix in children:bw[:,slots[root_prefix+side]]+=bw[:,slots[prefix+side]];bw[:,slots[prefix+side]]=0
emit(body['v'],body['n'],body['uv'],bw,body['f'],body['mat']==1)
reports=[]
for sign,side in [(-1,'L'),(1,'R')]:
 donor=np.load('tools/_tmp/repair034/donor-'+side+'.npz');vv=donor['v'].copy();nn=donor['n'];uu=donor['uv'];faces=donor['f'];origin=gs[names['thigh.'+side]][:3,3];mid=gs[names['shin.'+side]][:3,3];foot=gs[names['foot.'+side]][:3,3];axis=mid-origin;axis/=np.linalg.norm(axis);progress=(vv-origin)@axis
 # Extend the clean section back into its socket without flattening adjacent faces.
 extension=.055*(1-smooth((progress-.055)/.065));vv-=extension[:,None]*axis
 progress=(vv-origin)@axis
 cap_indices=np.unique(faces[donor['mat']==1]);root_cap=cap_indices[progress[cap_indices]<.002];socket=np.mean(np.unique(vv[root_cap],axis=0),axis=0)
 along=(vv-socket)@axis;centerline=socket+along[:,None]*axis;scale=1-.7*(1-smooth(progress/.06));vv=centerline+(vv-centerline)*scale[:,None]
 unique=np.unique(vv,axis=0)
 for joint in [mid,foot]:
  section=unique[np.abs(unique[:,1]-joint[1])<.015];joint[[0,2]]=np.median(section,axis=0)[[0,2]]
 upper_axis=(mid-origin)/np.linalg.norm(mid-origin);lower_axis=(foot-mid)/np.linalg.norm(foot-mid);joint_axis=upper_axis+lower_axis;joint_axis/=np.linalg.norm(joint_axis)
 shin=smooth(((vv-mid)@joint_axis+.06)/.12);ankle=smooth(((vv-foot)@lower_axis+.04)/.08)
 ww=np.zeros((len(vv),len(skin['joints'])))
 for prefix,mass in [('rear_thigh.',1-shin),('rear_shin.',shin*(1-ankle)),('rear_foot.',shin*ankle)]:ww[:,slots[prefix+side]]=mass
 ww[:]=0;ww[:,slots['rear_thigh.'+side]]=1
 offset=frame@np.array([-sign*.10,0,-.165]);vv+=offset
 for old,new in zip(['thigh.','shin.','foot.'],['rear_thigh.','rear_shin.','rear_foot.']):
  node=names[new+side];target=gs[names[old+side]].copy()
  if old=='thigh.':
   cap_indices=np.unique(faces[donor['mat']==1]);root_cap=cap_indices[progress[cap_indices]<.002];target[:3,3]=np.mean(np.unique(vv[root_cap]-offset,axis=0),axis=0)
  if old!='thigh.':
   unique=np.unique(vv-offset,axis=0);section=unique[np.abs(unique[:,1]-target[1,3])<.015];centerline=np.median(section,axis=0);target[[0,2],3]=centerline[[0,2]]
  target[:3,3]+=offset;parent=next(i for i,nod in enumerate(d['nodes']) if node in nod.get('children',[]));local=np.linalg.inv(gs[parent])@target;d['nodes'][node]['translation']=local[:3,3].tolist();d['nodes'][node]['rotation']=Rotation.from_matrix(local[:3,:3]).as_quat().tolist();gs[node]=target
 _,uid=np.unique(np.round(vv,6),axis=0,return_inverse=True);normal=np.zeros((uid.max()+1,3));t=vv[faces];area=np.cross(t[:,1]-t[:,0],t[:,2]-t[:,0])
 for k in range(3):np.add.at(normal,uid[faces[:,k]],area)
 normal/=np.maximum(np.linalg.norm(normal,axis=1,keepdims=True),1e-12);nn=normal[uid]
 emit(vv,nn,uu,ww,faces,donor['mat']==1);reports.append({'side':side,'faces':len(faces),'rigid_bone':'rear_thigh.'+side,'cap_faces':int(np.count_nonzero(donor['mat']==1))})
new_globals=globals_of(d);inverse=accessor(d,b,skin['inverseBindMatrices']).copy()
for name,node in names.items():
 if name.startswith('rear_'):inverse[slots[name]]=np.linalg.inv(new_globals[node]).T.ravel()
for clip in d['animations']:
 assert not any(ch['target']['node'] in [names[n] for n in names if n.startswith('rear_')] for ch in clip['channels']),'retarget existing rear clips before changing their rest'
for node in d['nodes']:
 if 'mesh' in node:node.setdefault('extras',{})['sfery_rigid_limbs']=True
skin['inverseBindMatrices']=writer.add(inverse,'MAT4');d['meshes'][0]['primitives']=outputs;d['asset']['extras']['sfery_stone_rear_rebuild']=3
out=Path('tools/_tmp/repair034/candidate/rogozhuk_stone.glb');out.parent.mkdir(parents=True,exist_ok=True);writer.save(out);compact(out);print(reports,flush=True)
