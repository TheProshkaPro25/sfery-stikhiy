"""Independent rear legs and a closed chitin body below the moving beetle armour.
Preserves the original exterior, UVs and textures. NumPy/SciPy, run at repo root.
"""
from pathlib import Path
import copy,shutil,numpy as np
from scipy.spatial.transform import Rotation
from scipy.spatial import cKDTree
from inspect_geometry import read_glb,accessor,triangles
from repair_skin import smooth_surface_weights
from upgrade_rigs import Writer,globals_of,qfraction,qmul,qconj

def smooth(x):
 x=np.clip(x,0,1);return x*x*(3-2*x)

def store_weights(writer,prim,w):
 top=np.argsort(-w,axis=1)[:,:8];ws=np.take_along_axis(w,top,axis=1);ws/=np.maximum(ws.sum(1,keepdims=True),1e-12)
 for k in range(2):
  prim['attributes']['JOINTS_'+str(k)]=writer.add(top[:,k*4:k*4+4],'VEC4',5123)
  prim['attributes']['WEIGHTS_'+str(k)]=writer.add(ws[:,k*4:k*4+4],'VEC4')

def repair(path):
 doc,binary=read_glb(path)
 if doc['asset'].get('extras',{}).get('sfery_beetle_body',0)>=7:return
 if doc['asset'].get('extras',{}).get('sfery_beetle_body'):
  doc,binary=read_glb(Path('tools/_tmp/beetles027-base')/path.name)
 backup=Path('tools/_tmp/beetles027-base');backup.mkdir(exist_ok=True,parents=True);
 if not (backup/path.name).exists():shutil.copy2(path,backup/path.name)
 writer=Writer(doc,binary);skin=doc['skins'][0];gs=globals_of(doc);named={doc['nodes'][n]['name']:n for n in skin['joints']};slots={name:skin['joints'].index(n) for name,n in named.items()}
 base_count=len(skin['joints']);center=gs[named['chest']][:3,3];fw=gs[named['head']][:3,3]-center;fw[1]=0;fw/=np.linalg.norm(fw);right=np.cross([0,1,0],fw)
 frame=np.column_stack([right,[0,1,0],fw])
 def world(p):return center+frame@np.asarray(p)
 source=next(triangles(doc,binary));prim,v,f=source
 c=(v-center)@frame;c[:,1]=v[:,1]  # floor coordinates are absolute GLB Y
 def wp(p):
  p=np.asarray(p);out=center+frame@p;out[1]=p[1];return out
 rear=[]
 for sign,side in [(-1,'L'),(1,'R')]:
  candidates=c[(c[:,0]*sign>.18)&(c[:,2]<-.23)&(c[:,1]<-.07)]
  if len(candidates)<200:continue  # Do not put a phantom leg on an absent generated appendage.
  tip=np.median(candidates[candidates[:,1]<np.quantile(candidates[:,1],.25)],axis=0)
  knee=np.array([np.quantile(candidates[:,0]*sign,.82)*sign,np.quantile(candidates[:,1],.45),np.quantile(candidates[:,2],.25)])
  root=np.array([sign*.22,-.055,-.16])
  group=[];parent=named['hips']
  for prefix,point in zip(['rear_thigh.','rear_shin.','rear_foot.'],[root,knee,tip]):
   desired=np.eye(4);desired[:3,3]=wp(point);local=np.linalg.inv(gs[parent])@desired
   node=len(doc['nodes']);name=prefix+side
   doc['nodes'].append({'name':name,'translation':local[:3,3].tolist(),'rotation':Rotation.from_matrix(local[:3,:3]).as_quat().tolist()})
   doc['nodes'][parent].setdefault('children',[]).append(node);skin['joints'].append(node);gs.append(desired);named[name]=node;slots[name]=len(skin['joints'])-1;group.append(slots[name]);parent=node
  rear.append((sign,root,knee,tip,group))
 for prim,v,f in list(triangles(doc,binary)):
  c=(v-center)@frame;c[:,1]=v[:,1]
  w=np.zeros((len(v),len(skin['joints'])))
  for k in [0,1]:
   if 'JOINTS_'+str(k) not in prim['attributes']:continue
   js=accessor(doc,binary,prim['attributes']['JOINTS_'+str(k)]).astype(int);ws=accessor(doc,binary,prim['attributes']['WEIGHTS_'+str(k)]);np.add.at(w,(np.arange(len(v))[:,None],js),ws)
  # Old proximity skinning leaked leg weights into the upper thorax and face.
  # Keep a broad attachment blend, but never pull high armour with a ground leg.
  leg_slots=[slot for name,slot in slots.items() if name.startswith(('arm.','forearm.','hand.','thigh.','shin.','foot.','rear_'))]
  upper=smooth((c[:,1]+.035)/.09)
  removed=w[:,leg_slots].sum(1)*upper
  w[:,leg_slots]*=1-upper[:,None]
  head_share=smooth((c[:,2]-.10)/.15)
  shell_share=(1-head_share)*smooth((c[:,1]+.01)/.15)*(1-smooth((c[:,2]-.05)/.18))
  w[:,slots['head']]+=removed*head_share
  w[:,slots['shell']]+=removed*shell_share
  w[:,slots['chest']]+=removed*(1-head_share-shell_share)
  for sign,root,knee,tip,group in rear:
   # Select the rear appendage outside the rounded abdomen; blend at its attachment.
   outward=c[:,0]*sign
   amount=smooth((outward-.19)/.07)*smooth((-c[:,2]-.18)/.08)*smooth((.005-c[:,1])/.075)
   shell_share=w[:,slots['shell']]
   amount*=1-smooth((shell_share-.08)/.45)
   # Keep the head and horn separate. The old thigh weights also cover these rear legs.
   protected=w[:,[slots[n] for n in ['head','horn']]].sum(1)
   amount*=1-smooth((protected-.12)/.65)
   # Longitudinal transitions distribute flex across both joints and the claw.
   progress=np.clip((-c[:,2]-.18)/max(-tip[2]-.18,.08),0,1)
   thigh=1-smooth((progress-.2)/.45);foot=smooth((progress-.75)/.25);shin=1-thigh-foot
   w*=1-amount[:,None]
   for j,factor in zip(group,[thigh,shin,foot]):w[:,j]+=amount*factor
  w=smooth_surface_weights(v,f,w,np.ptp(v[:,1])*.022)
  store_weights(writer,prim,w)
 # A beetle's solid exoskeleton should not open as if it had a hollow chest.
 for animation in doc['animations']:
  for ch in animation['channels']:
   if ch['target']['path']!='rotation' or ch['target']['node']!=named['shell']:continue
   sampler=animation['samplers'][ch['sampler']];q=accessor(doc,binary,sampler['output'])
   rest=np.asarray(doc['nodes'][named['shell']].get('rotation',[0,0,0,1]))
   sampler['output']=writer.add(qmul(rest,qfraction(qmul(qconj(rest),q),.18)),'VEC4')
 # Add a small, closed inner volume: it remains inside the armour and closes views through seams.
 # It follows the torso, never the shell or legs. The original colour texture supplies chitin detail.
 mat=copy.deepcopy(doc['materials'][prim.get('material',0)])
 palette={'fire':[.29,.075,.035,1],'gale':[.055,.22,.105,1],'light':[.32,.22,.07,1],'shadow':[.13,.075,.18,1],'stone':[.19,.16,.13,1],'tide':[.065,.18,.22,1]}
 mat['pbrMetallicRoughness']={'baseColorFactor':palette[path.stem.split('_')[-1]],'roughnessFactor':1,'metallicFactor':0}
 doc['materials'].append(mat);mat_index=len(doc['materials'])-1
 for origin,radii in [([0,-.005,-.065],[.145,.105,.165]),([0,-.005,.12],[.10,.075,.095])]:
  vv=[];nn=[];ff=[];rings=20;sides=40
  # Use single vertices at poles so the new body is watertight even after welding.
  unit=[[0,-1,0]]
  for r in range(1,rings):
   lat=-np.pi/2+np.pi*r/rings
   for s in range(sides):
    a=2*np.pi*s/sides;unit.append([np.cos(lat)*np.cos(a),np.sin(lat),np.cos(lat)*np.sin(a)])
  unit.append([0,1,0]);unit=np.asarray(unit);local=unit*np.asarray(radii)+origin
  for p in local:vv.append(wp(p))
  normal=unit/np.asarray(radii);normal=normal@frame.T;normal/=np.linalg.norm(normal,axis=1,keepdims=True)
  for s in range(sides):ff.append([0,1+(s+1)%sides,1+s])
  for r in range(rings-2):
   a=1+r*sides;b=a+sides
   for s in range(sides):t=(s+1)%sides;ff.extend([[a+s,a+t,b+t],[a+s,b+t,b+s]])
  last=len(unit)-1;a=1+(rings-2)*sides
  for s in range(sides):ff.append([last,a+s,a+(s+1)%sides])
  vv=np.asarray(vv);_,near=cKDTree(v).query(vv);uv=accessor(doc,binary,prim['attributes']['TEXCOORD_0'])[near]
  body={'attributes':{'POSITION':writer.add(vv,'VEC3'),'NORMAL':writer.add(normal,'VEC3'),'TEXCOORD_0':writer.add(uv,'VEC2')},'indices':writer.add(np.array(ff).ravel()[:,None],'SCALAR',5125),'material':mat_index}
  w=np.zeros((len(vv),len(skin['joints'])))
  chest=smooth((local[:,2]+.22)/.3);head=smooth((local[:,2]-.13)/.12)*.7
  w[:,slots['hips']]=1-chest;w[:,slots['chest']]=chest*(1-head);w[:,slots['head']]=chest*head
  store_weights(writer,body,w);doc['meshes'][0]['primitives'].append(body)
 # Preserve every old inverse bind exactly, add inverse binds for the new chains.
 inv=accessor(doc,binary,skin['inverseBindMatrices']).reshape(-1,16)
 extra=np.array([np.linalg.inv(gs[n]).T.ravel() for n in skin['joints'][base_count:]])
 if len(extra):skin['inverseBindMatrices']=writer.add(np.concatenate([inv,extra]),'MAT4')
 doc['asset'].setdefault('extras',{})['sfery_beetle_body']=7
 writer.save(path);print(path.stem,'rear chains',len(rear),'inner body added',flush=True)
if __name__=='__main__':
 for path in sorted(Path('assets/creatures_hd').glob('rogozhuk_*.glb')):repair(path)
