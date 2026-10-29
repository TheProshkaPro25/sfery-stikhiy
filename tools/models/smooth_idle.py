"""Close idle loops with periodic rotation curves, preserving mesh, textures and bone rests.
Stored source backup makes repeated application deterministic. Does not affect attacks or Likorez's nervous gait.
"""
import argparse,shutil
from pathlib import Path
import numpy as np
from inspect_geometry import read_glb,accessor
from upgrade_rigs import Writer,qmul,qconj
from creature_personality import sample_quaternions


def periodic(values, harmonics):
 n=len(values);phase=np.arange(n)/n
 matrix=np.column_stack([np.ones(n)]+[f(phase*k*2*np.pi) for k in range(1,harmonics+1) for f in [np.cos,np.sin]])
 coeff=np.linalg.lstsq(matrix,values,rcond=None)[0]
 # Dampen higher frequencies without introducing a seam or flattening the main motion.
 for k in range(1,harmonics+1):coeff[2*k-1:2*k+1]/=1+0.0003*k**4
 target=np.linspace(0,1,121)
 output=np.column_stack([np.ones(len(target))]+[f(target*k*2*np.pi) for k in range(1,harmonics+1) for f in [np.cos,np.sin]])@coeff
 output += values[0]-output[0]
 output[-1]=output[0]
 return output


def smooth_file(path,backup):

 current,_=read_glb(path)
 if current.get('asset',{}).get('extras',{}).get('sfery_idle_loop_version')==2:return 0
 backup.mkdir(parents=True,exist_ok=True)
 source=backup/path.name
 if not source.exists():shutil.copy2(path,source)
 doc,binary=read_glb(source)
 if doc.get('asset',{}).get('extras',{}).get('sfery_idle_loop_version')==2:return 0
 writer=Writer(doc,binary);idle=next(a for a in doc['animations'] if a['name']=='idle')
 source_length=max(float(accessor(doc,binary,s['input'])[-1,0]) for s in idle['samplers'])
 # Godot imports these scenes at 30 Hz. A fractional last interval breaks cubic
 # loop tangents even when both source pose and source velocity are periodic.
 length=round(source_length*30)/30
 sample_times=np.arange(240)/240*source_length
 time_index=writer.add(np.linspace(0,length,121).reshape(-1,1),'SCALAR')
 changed=0
 for channel in idle['channels']:
  sampler=idle['samplers'][channel['sampler']]
  times=accessor(doc,binary,sampler['input']).reshape(-1);raw=accessor(doc,binary,sampler['output'])
  if channel['target']['path']!='rotation' or len(raw)<3:
   mapped=(times-times[0])/max(float(times[-1]-times[0]),1e-8)*length
   sampler['input']=writer.add(mapped.reshape(-1,1),'SCALAR')
   continue
  q=raw.copy();q/=np.linalg.norm(q,axis=1,keepdims=True)
  if np.max(1-np.abs(q@q[0]))<1e-7:
   mapped=(times-times[0])/max(float(times[-1]-times[0]),1e-8)*length
   sampler['input']=writer.add(mapped.reshape(-1,1),'SCALAR')
   continue
  uniform=sample_quaternions(times,q,sample_times)
  relative=qmul(qconj(q[0]),uniform)
  relative=np.where(relative[:,3:]<0,-relative,relative)
  lengths=np.linalg.norm(relative[:,:3],axis=1)
  angle=2*np.arctan2(lengths,relative[:,3])
  vectors=relative[:,:3]*np.divide(angle,lengths,out=np.full_like(angle,2),where=lengths>1e-8)[:,None]
  name=doc['nodes'][channel['target']['node']].get('name','')
  h=8 if name.startswith('ear.') else 4
  filtered=periodic(vectors,h)
  angle=np.linalg.norm(filtered,axis=1);factor=np.divide(np.sin(angle/2),angle,out=np.full_like(angle,.5),where=angle>1e-8)
  delta=np.column_stack((filtered*factor[:,None],np.cos(angle/2)))
  values=qmul(q[0],delta);values/=np.linalg.norm(values,axis=1,keepdims=True)
  values[-1]=values[0]
  channel['sampler']=len(idle['samplers'])
  idle['samplers'].append({'input':time_index,'output':writer.add(values,'VEC4'),'interpolation':'LINEAR'})
  changed+=1
 used=sorted({c['sampler'] for c in idle['channels']})
 remap={old:new for new,old in enumerate(used)}
 idle['samplers']=[idle['samplers'][index] for index in used]
 for channel in idle['channels']:channel['sampler']=remap[channel['sampler']]
 doc.setdefault('asset',{}).setdefault('extras',{})['sfery_idle_loop_version']=2
 writer.save(path)
 return changed

if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--backup',default='tools/_tmp/idle026-base');p.add_argument('--model');args=p.parse_args()
 for path in sorted(Path('assets/creatures_hd').glob('*.glb')):
  if path.stem.startswith(('likorez','glubinnik','sumrachnik')) or args.model and path.stem!=args.model:continue
  print(path.stem,smooth_file(path,Path(args.backup)),flush=True)
