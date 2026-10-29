"""Индивидуальная пластика восьми видов поверх rig v2. Геометрия и текстуры сохраняются.
python3 tools/models/creature_personality.py [--species klykar]
Оригиналы 0.2.4: /tmp/sfery-personality-base. Повторный запуск идемпотентен.
"""
import argparse,copy,json,shutil
from pathlib import Path
import numpy as np
from inspect_geometry import read_glb,accessor,triangles
from upgrade_rigs import Writer,globals_of,qmul,qconj,add_channel


def smooth(x):
 x=np.clip(x,0,1);return x*x*(3-2*x)


def strike(p):
 # Отведение → контакт на 1/3 → инерционный довод → стойка.
 return np.interp(p,[0,.18,1/3,.48,.72,1],[0,-.55,1,.75,.2,0])


def motion(sp,bone,clip,p):
 # Углы в осях тела: наклон, разведение/крен, поворот.
 out=np.zeros((len(p),3));side=1 if bone.endswith('.L') else -1
 attack=clip=='attack';idle=clip=='idle';s=strike(p) if attack else np.sin(np.pi*p)**2
 number=int(bone[-1]) if bone[-1:].isdigit() else 1
 if sp=='dragnar':
  if bone.startswith('wing.'):
   out[:,1]=side*(9*np.sin(2*np.pi*p) if idle else -24*s)
  elif bone.startswith(('wingtip.','wingfan.')):
   out[:,1]=side*(6*np.sin(2*np.pi*p-.5) if idle else -15*np.sin(np.pi*p)**2)
  elif bone.startswith('tail'):
   out[:,2]=(7 if idle else 15)*np.sin(2*np.pi*p-number*.5)*(1 if idle else np.sin(np.pi*p)**2)
   out[:,0]=(-4 if idle else -9)*np.sin(np.pi*p)**2
 elif sp=='klykar':
  if bone.startswith('tail'):
   out[:,2]=(14 if idle else 24)*np.sin((2 if idle else 1)*2*np.pi*p-number*.65)*(1 if idle else np.sin(np.pi*p)**2)
   out[:,0]=(-5 if idle else -14)*s
  elif bone.startswith('ear.'):
   twitch=np.exp(-((p-(.25 if side==1 else .68))/.07)**2)
   out[:,2]=side*(10*twitch if idle else -15*s)
   out[:,0]=(4*twitch if idle else -8*s)
  elif bone=='head':out[:,0]=(2*np.sin(2*np.pi*p) if idle else 7*s)
 elif sp=='ratnik':
  if bone=='arm.L':out[:,0]=-18*s if attack else -3*s
  elif bone=='forearm.L':out[:,2]=-12*s if attack else 0
  elif bone=='sword':out[:,2]=16*s if attack else 2*np.sin(2*np.pi*p)
  elif bone=='arm.R':out[:,2]=9*s if attack else 0
  elif bone.startswith('cape'):
   out[:,0]=(4 if idle else 16)*np.sin(2*np.pi*p-number*.45)*(1 if idle else np.sin(np.pi*p)**2)
 elif sp=='grifalon':
  if bone.startswith('wing.'):
   out[:,1]=side*(13*np.sin(4*np.pi*p) if idle else -30*s)
  elif bone.startswith(('wingtip.','wingfan.')):
   out[:,1]=side*(8*np.sin(4*np.pi*p-.5) if idle else -16*s)
  elif bone.startswith('tail'):out[:,2]=(4 if idle else 12)*np.sin(2*np.pi*p-number*.4)*(1 if idle else np.sin(np.pi*p)**2)
  elif bone=='head':out[:,0]=6*s if attack else 0
 elif sp=='kolossar':
  if bone=='chest':out[:,2]=7*s if attack else 0
  elif bone=='arm.R':out[:,0]=-9*s if attack else -2*s
  elif bone=='forearm.R':out[:,0]=-12*s if attack else 0
  elif bone=='arm.L':out[:,0]=-7*s if attack else 0
  elif bone.startswith('tail'):out[:,2]=4*np.sin(2*np.pi*p)*np.sin(np.pi*p)**2
 elif sp=='rogozhuk':
  if bone=='horn':out[:,0]=-18*s if attack else 3*np.sin(2*np.pi*p)
  elif bone=='head':out[:,0]=-8*s if attack else 0
  elif bone=='shell':out[:,0]=-11*np.sin(np.pi*p)**2 if not idle else -3*np.sin(2*np.pi*p)**2
 elif sp=='levian':
  if bone.startswith('neck'):
   out[:,0]=(5 if idle else 13)*np.sin(2*np.pi*p-number*.5)*(1 if idle else np.sin(np.pi*p)**2)
   out[:,2]=5*np.sin(2*np.pi*p-number*.6)*(1 if idle else np.sin(np.pi*p)**2)
  elif bone.startswith('coil'):out[:,2]=2.5*np.sin(2*np.pi*p-number*.6)*(1 if idle else np.sin(np.pi*p)**2)
  elif bone=='tail':out[:,2]=(8 if idle else 16)*np.sin(2*np.pi*p-1)*(1 if idle else np.sin(np.pi*p)**2)
  elif bone.startswith('wing.'):out[:,1]=side*6*np.sin(2*np.pi*p)
 elif sp=='gorgul':
  if bone.startswith('wing.'):out[:,1]=side*(11*np.sin(4*np.pi*p) if idle else -20*s)
  elif bone.startswith('wingtip.'):out[:,1]=side*7*np.sin(4*np.pi*p-.7)*(1 if idle else np.sin(np.pi*p)**2)
  elif bone.startswith('tail'):out[:,2]=11*np.sin(2*np.pi*p-number*.7)*(1 if idle else np.sin(np.pi*p)**2)
  elif bone.startswith('hand.'):out[:,0]=-10*s if attack else 0
 if clip=='hit':out*=.45
 if clip in ('roar','stance'):out*=.65
 return np.deg2rad(out)


def sample_quaternions(times,values,target):
 idx=np.clip(np.searchsorted(times,target,side='right')-1,0,len(times)-2)
 a=values[idx];b=values[idx+1];b=np.where((a*b).sum(1,keepdims=True)<0,-b,b)
 t=np.clip((target-times[idx])/np.maximum(times[idx+1]-times[idx],1e-8),0,1)[:,None]
 q=a*(1-t)+b*t;return q/np.maximum(np.linalg.norm(q,axis=1,keepdims=True),1e-9)


def bind_soles(doc,writer,globals_,species):
 # Подошва держится на стопе, а не растягивается вместе с голенью.
 skin=doc['skins'][0];names={doc['nodes'][n]['name']:n for n in skin['joints']};parents={c:i for i,n in enumerate(doc['nodes']) for c in n.get('children',[])}
 families=[('thigh.','foot.')]+([('arm.','hand.')] if species in ('klykar','rogozhuk') else [])
 for prim,v,f in list(triangles(doc,writer.binary)):
  js=accessor(doc,writer.binary,prim['attributes']['JOINTS_0']).astype(int);ws=accessor(doc,writer.binary,prim['attributes']['WEIGHTS_0']).astype(float)
  w=np.zeros((len(v),len(skin['joints'])));np.add.at(w,(np.arange(len(v))[:,None],js),ws);height=float(np.ptp(v[:,1]))
  for first,last in families:
   for side in ('L','R'):
    root=names.get(first+side);tip=names.get(last+side)
    if root is None or tip is None:continue
    chain=[]
    for slot,node in enumerate(skin['joints']):
     p=node
     while p in parents and p!=root:p=parents[p]
     if p==root:chain.append(slot)
    influence=w[:,chain].sum(1);region=influence>.65
    if region.sum()<20:continue
    sole=float(np.quantile(v[region,1],.005));amount=(1-smooth((v[:,1]-(sole+height*.045))/(height*.035)))*region
    w*=1-amount[:,None];w[:,skin['joints'].index(tip)]+=amount
  _,uid=np.unique(np.round(v,6),axis=0,return_inverse=True);uid=uid.reshape(-1);sums=np.zeros((uid.max()+1,w.shape[1]));np.add.at(sums,uid,w);w=(sums/np.bincount(uid)[:,None])[uid]
  top=np.argsort(-w,axis=1)[:,:4];weights=np.take_along_axis(w,top,axis=1);weights/=weights.sum(1,keepdims=True)
  prim['attributes']['JOINTS_0']=writer.add(top,'VEC4',5123);prim['attributes']['WEIGHTS_0']=writer.add(weights,'VEC4')


def apply(path,backup_dir):
 backup=backup_dir/path.name
 current,_=read_glb(path)
 if not backup.exists():
  if current.get('asset',{}).get('extras',{}).get('sfery_personality_version'):return {'model':path.stem,'skipped':True}
  shutil.copy2(path,backup)
 elif not current.get('asset',{}).get('extras',{}).get('sfery_personality_version') and path.read_bytes()!=backup.read_bytes():
  raise ValueError(f'{path.name}: базовый риг изменён; используйте новую папку --backup')
 doc,binary=read_glb(backup);original=copy.deepcopy(doc);writer=Writer(doc,binary);gs=globals_of(doc)
 sp=path.stem.rsplit('_',1)[0];skin=doc['skins'][0];names={doc['nodes'][n]['name']:n for n in skin['joints']};added=[]
 # Меч должен двигаться вместе с кистью, а не оставаться на предплечье при сгибе запястья.
 if sp=='ratnik' and 'sword' in names and 'hand.L' in names:
  sword=names['sword'];hand=names['hand.L'];parent=next(i for i,n in enumerate(doc['nodes']) if sword in n.get('children',[]))
  oldlocal=doc['nodes'][sword].get('translation',[0,0,0]);local=np.linalg.inv(gs[hand])@gs[sword]
  doc['nodes'][parent]['children'].remove(sword);doc['nodes'][hand].setdefault('children',[]).append(sword)
  doc['nodes'][sword]['translation']=local[:3,3].tolist();offset=np.array(oldlocal)-local[:3,3]
  for a in doc['animations']:
   for ch in a['channels']:
    if ch['target']=={'node':sword,'path':'translation'}:
     sampler=a['samplers'][ch['sampler']];sampler['output']=writer.add(accessor(original,binary,sampler['output'])-offset,'VEC3')
 # Уши Клыкаря — отдельные небольшие области над головой, с плавным корнем.
 if sp=='klykar':
  head=names['head'];hips=names['hips'];forward=gs[head][:3,3]-gs[hips][:3,3];forward[1]=0;forward/=np.linalg.norm(forward);up=np.array([0.,1.,0.]);side=np.cross(forward,up)
  primitives=list(triangles(doc,binary));ear_specs=[]
  for sign,label in [(1,'L'),(-1,'R')]:
   candidates=[]
   for prim,v,f in primitives:
    js=accessor(original,binary,prim['attributes']['JOINTS_0']);ws=accessor(original,binary,prim['attributes']['WEIGHTS_0']);weight=np.where(js==skin['joints'].index(head),ws,0).sum(1);p=v[weight>.65]
    if len(p):candidates.append(p)
   p=np.concatenate(candidates);height=np.quantile(p[:,1],.65);lateral=(p-gs[head][:3,3])@side*sign
   selected=p[(p[:,1]>height)&(lateral>np.quantile(lateral,.7))]
   center=np.median(selected,axis=0);root=center.copy();root[1]-=.025
   node=len(doc['nodes']);local=np.linalg.inv(gs[head])@np.append(root,1)
   doc['nodes'].append({'name':'ear.'+label,'translation':local[:3].tolist()});doc['nodes'][head].setdefault('children',[]).append(node);skin['joints'].append(node)
   ear_specs.append((node,center,sign,side));added.append(node)
  for prim,v,f in primitives:
   js=accessor(original,binary,prim['attributes']['JOINTS_0']).astype(int);ws=accessor(original,binary,prim['attributes']['WEIGHTS_0']).astype(float);w=np.zeros((len(v),len(skin['joints'])));np.add.at(w,(np.arange(len(v))[:,None],js),ws)
   slot=skin['joints'].index(head)
   for node,center,sign,side in ear_specs:
    r=np.linalg.norm(v-center,axis=1);strength=(1-smooth((r-.015)/.065))*smooth((v[:,1]-(center[1]-.05))/.05)
    strength*=smooth(((v-gs[head][:3,3])@side*sign)/.03);moved=w[:,slot]*strength*.9;w[:,slot]-=moved;w[:,skin['joints'].index(node)]+=moved
   _,uid=np.unique(np.round(v,6),axis=0,return_inverse=True);uid=uid.reshape(-1);sums=np.zeros((uid.max()+1,w.shape[1]));np.add.at(sums,uid,w);w=(sums/np.bincount(uid)[:,None])[uid]
   top=np.argsort(-w,axis=1)[:,:4];weights=np.take_along_axis(w,top,axis=1);weights/=weights.sum(1,keepdims=True)
   prim['attributes']['JOINTS_0']=writer.add(top,'VEC4',5123);prim['attributes']['WEIGHTS_0']=writer.add(weights,'VEC4')
  gs=globals_of(doc);skin['inverseBindMatrices']=writer.add(np.array([np.linalg.inv(gs[n]).T.reshape(16) for n in skin['joints']]),'MAT4')
 if sp in ('kolossar','ratnik','klykar','rogozhuk'):bind_soles(doc,writer,gs,sp)
 names={doc['nodes'][n]['name']:n for n in skin['joints']};up=np.array([0.,1.,0.]);head=names.get('head');hips=names.get('hips')
 forward=gs[head][:3,3]-gs[hips][:3,3];forward[1]=0;forward/=max(np.linalg.norm(forward),1e-8);side=np.cross(forward,up)
 modified=0
 for a,old_a in zip(doc['animations'],original['animations']):
  old_channels={(ch['target']['node'],ch['target']['path']):ch for ch in old_a['channels']}
  duration=max(float(accessor(original,binary,s['input'])[-1,0]) for s in old_a['samplers']);start=min(float(accessor(original,binary,s['input'])[0,0]) for s in old_a['samplers'])
  times=np.linspace(start,duration,61);p=(times-start)/max(duration-start,1e-8);input_index=writer.add(times[:,None],'SCALAR')
  for name,node in names.items():
   angles=motion(sp,name,a['name'],p)
   if np.abs(angles).max()<1e-8:continue
   channel=old_channels.get((node,'rotation'));rest=np.array(doc['nodes'][node].get('rotation',[0,0,0,1]))
   values=np.tile(rest,(len(times),1))
   if channel:
    sampler=old_a['samplers'][channel['sampler']];values=sample_quaternions(accessor(original,binary,sampler['input']).reshape(-1),accessor(original,binary,sampler['output']),times)
   axes=[-side,-forward,up];rotation=gs[node][:3,:3];rotation/=np.linalg.norm(rotation,axis=0)
   for column,axis in enumerate(axes):
    local=rotation.T@axis;local/=max(np.linalg.norm(local),1e-8);angle=angles[:,column]/2;delta=np.concatenate((np.sin(angle)[:,None]*local,np.cos(angle)[:,None]),axis=1);values=qmul(values,delta)
   values/=np.linalg.norm(values,axis=1,keepdims=True)
   # Ровно один rotation-канал на сустав в клипе.
   existing=next((ch for ch in a['channels'] if ch['target']=={'node':node,'path':'rotation'}),None)
   if existing:
    existing['sampler']=len(a['samplers']);a['samplers'].append({'input':input_index,'output':writer.add(values,'VEC4'),'interpolation':'LINEAR'})
   else:add_channel(writer,a,node,'rotation',input_index,values)
   modified+=1
 for i,g in enumerate(globals_of(original)):
  assert np.abs(globals_of(doc)[i]-g).max()<2e-5,(path.name,'rest pose')
 doc['asset']['extras']['sfery_personality_version']=1;writer.save(path)
 return {'model':path.stem,'individual_channels':modified,'added':[doc['nodes'][n]['name'] for n in added]}

if __name__=='__main__':
 parser=argparse.ArgumentParser();parser.add_argument('--species');parser.add_argument('--backup',default='/tmp/sfery-personality-base');args=parser.parse_args();base=Path(args.backup);base.mkdir(parents=True,exist_ok=True);root=Path(__file__).resolve().parents[2];report=[]
 for p in sorted((root/'assets/creatures_hd').glob('*.glb')):
  if p.stem.startswith(('glubinnik','sumrachnik','likorez')) or (args.species and not p.stem.startswith(args.species+'_')):continue
  result=apply(p,base);report.append(result);print(json.dumps(result,ensure_ascii=False),flush=True)
 Path('/tmp/sfery-personality-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
