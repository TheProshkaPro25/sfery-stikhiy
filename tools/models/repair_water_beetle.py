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
from scipy.spatial.transform import Rotation
from inspect_geometry import read_glb,accessor,triangles
from upgrade_rigs import Writer,globals_of
from repair_beetles import store_weights,smooth

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
 for a,b in boundary:by_start.setdefault(int(uid[a]),[]).append((int(a),int(b)))
 extra_v=[];extra_n=[];extra_uv=[];extra_w=[];extra_f=[];used=set();loops=0
 for first in range(len(boundary)):
  a,b=map(int,boundary[first]);start=int(uid[a])
  if (int(uid[a]),int(uid[b])) in used:continue
  ring=[];current=(a,b)
  for _ in range(len(boundary)+1):
   a,b=current;key=(int(uid[a]),int(uid[b]))
   if key in used:break
   used.add(key);ring.append((a,b))
   if int(uid[b])==start:break
   choices=[e for e in by_start.get(int(uid[b]),[]) if (int(uid[e[0]]),int(uid[e[1]])) not in used]
   if not choices:break
   current=choices[0]
  if not ring or int(uid[ring[-1][1]])!=start:continue
  ix=np.array([e[0] for e in ring]);center=v[ix].mean(0);normal=n[ix].mean(0);normal/=max(np.linalg.norm(normal),1e-9)
  ci=len(v)+len(extra_v);extra_v.append(center);extra_n.append(normal);extra_uv.append(uv[ix].mean(0));extra_w.append(w[ix].mean(0))
  extra_f.extend([[b,a,ci] for a,b in ring]);loops+=1
 if extra_v:
  v=np.concatenate([v,extra_v]);n=np.concatenate([n,extra_n]);uv=np.concatenate([uv,extra_uv]);w=np.concatenate([w,extra_w]);f=np.concatenate([f,extra_f])
 return v,n,uv,w,f,loops

def repair():
 current,_=read_glb(PATH)
 if current.get('asset',{}).get('extras',{}).get('sfery_water_beetle_anatomy')==6:return
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
  selected=f[selection];indices=np.unique(selected);mapping=np.full(len(v),-1);mapping[indices]=np.arange(len(indices))
  return indices,mapping[selected]
 body_w=w.copy();rear_slots=[slot for name,slot in slots.items() if name.startswith('rear_')]
 removed=body_w[:,rear_slots].sum(1);body_w[:,rear_slots]=0;body_w[:,slots['hips']]+=removed
 # The abdomen stays on the torso, regardless of the six independently moving legs.
 torso=yellow&(c[:,2]<-.08)&(c[:,1]<.13)&(c[:,1]>-.25)&(np.abs(c[:,0])<.29)
 limb=[slot for name,slot in slots.items() if name.startswith(('arm.','forearm.','hand.','thigh.','shin.','foot.'))]
 removed=body_w[:,limb].sum(1)*torso;body_w[:,limb]*=1-torso[:,None];body_w[:,slots['hips']]+=removed
 ii,faces=subset(~remove);emit(v[ii],n[ii],uv[ii],body_w[ii],faces,None)
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
  region&=(distance<.070)|(c[:,1]<-.265)
  selection=region[f].mean(1)>.5
  ii,faces=subset(selection)
  offset=frame@np.array([sign*.045,0,-.205])
  vv=v[ii]+offset;nn=n[ii].copy();uu=uv[ii].copy();ww=np.zeros((len(ii),len(skin['joints'])))
  mass=w[ii][:,source_slots];mass/=np.maximum(mass.sum(1,keepdims=True),1e-12)
  for k,prefix in enumerate(('rear_thigh.','rear_shin.','rear_foot.')):ww[:,slots[prefix+side]]=mass[:,k]
  for old_prefix,new_prefix in zip(('thigh.','shin.','foot.'),('rear_thigh.','rear_shin.','rear_foot.')):
   node=names[new_prefix+side];target=gs[names[old_prefix+side]].copy();target[:3,3]+=offset
   parent=next(k for k,nod in enumerate(doc['nodes']) if node in nod.get('children',[]));local=np.linalg.inv(gs[parent])@target
   doc['nodes'][node]['translation']=local[:3,3].tolist();doc['nodes'][node]['rotation']=Rotation.from_matrix(local[:3,:3]).as_quat().tolist();gs[node]=target
  loops=emit(vv,nn,uu,ww,faces,dark)
  reports.append({'side':side,'leg_vertices':len(ii),'root_caps':loops,'copied_from':'actual middle leg, original textured geometry','offset_anatomical':[sign*.045,0,-.205]})
 # The cut U-paddles were fused along a broad abdomen surface. Rebuild the
 # missing wall with a smooth closed chitin core, inside the surviving exterior;
 # do not fan-triangulate a highly concave wound across the former U shape.
 unit=[[0,-1,0]];faces=[];rings=96;sides=96
 for r in range(1,rings):
  lat=-np.pi/2+np.pi*r/rings
  for k in range(sides):
   a=2*np.pi*k/sides;unit.append([np.cos(lat)*np.cos(a),np.sin(lat),np.cos(lat)*np.sin(a)])
 unit.append([0,1,0])
 for k in range(sides):faces.append([0,1+k,1+(k+1)%sides])
 for r in range(rings-2):
  a0=1+r*sides;b0=a0+sides
  for k in range(sides):
   a=a0+k;b=a0+(k+1)%sides;c1=b0+k;dd=b0+(k+1)%sides;faces.extend([[a,dd,b],[a,c1,dd]])
 last=len(unit)-1;a0=1+(rings-2)*sides
 for k in range(sides):faces.append([last,a0+(k+1)%sides,a0+k])
 unit=np.array(unit);local=unit*np.array([.255,.190,.185])+[0,-.055,-.240]
 vv=local@frame.T+center;vv[:,1]=local[:,1]
 normals=unit/np.array([.255,.190,.185]);normals=normals@frame.T;normals/=np.linalg.norm(normals,axis=1,keepdims=True)
 attrs={'POSITION':writer.add(vv,'VEC3'),'NORMAL':writer.add(normals,'VEC3'),'TEXCOORD_0':writer.add(np.zeros((len(vv),2)),'VEC2')}
 # Subtle segment ridges continue the original yellow abdomen's dark bands.
 angle=np.arctan2(unit[:,2],unit[:,0]);ridge=np.zeros(len(unit))
 for height in (.050,-.025,-.105,-.185):
  ridge=np.maximum(ridge,np.exp(-((local[:,1]-height-.003*np.sin(3*angle))/.0035)**2))
 colors=np.ones((len(unit),4));colors[:,:3]=1-ridge[:,None]*np.array([.75,.78,.80])
 attrs['COLOR_0']=writer.add(colors,'VEC4')
 output={'attributes':attrs,'indices':writer.add(np.array(faces).ravel()[:,None],'SCALAR',5125),'material':gold}
 weights=np.zeros((len(vv),len(skin['joints'])));weights[:,slots['hips']]=1;store_weights(writer,output,weights);outputs.append(output)
 doc['meshes'][0]['primitives']=outputs+doc['meshes'][0]['primitives'][1:]
 new_globals=globals_of(doc);inverse=accessor(doc,binary,skin['inverseBindMatrices']).copy()
 for name in names:
  if name.startswith('rear_'):inverse[slots[name]]=np.linalg.inv(new_globals[names[name]]).T.ravel()
 skin['inverseBindMatrices']=writer.add(inverse,'MAT4');doc['asset'].setdefault('extras',{})['sfery_water_beetle_anatomy']=6
 writer.save(PATH);Path('/tmp/sfery-water-beetle027.json').write_text(json.dumps(reports,indent=2));print(json.dumps(reports,indent=2))
if __name__=='__main__':repair()
