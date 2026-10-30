"""Keep Ratnik's steel rigid during the wrist/sword sweep; leave fingers and forearm flexible."""
from pathlib import Path
import shutil,numpy as np
from inspect_geometry import read_glb,accessor,triangles
from upgrade_rigs import Writer,globals_of

def fix(path,backup):
 current,_=read_glb(path)
 if current.get('asset',{}).get('extras',{}).get('sfery_skin_repair',0):
  raise ValueError('Do not harden repaired skins: sword/body transitions must remain continuous')
 if current.get('asset',{}).get('extras',{}).get('sfery_rigid_blade')==1:return 0
 backup.mkdir(parents=True,exist_ok=True);source=backup/path.name
 if not source.exists():shutil.copy2(path,source)
 doc,binary=read_glb(source);writer=Writer(doc,binary)
 skin=doc['skins'][0];joint=next(i for i,n in enumerate(skin['joints']) if doc['nodes'][n].get('name')=='sword')
 transform=globals_of(doc)[skin['joints'][joint]];axis=transform[:3,1];axis/=np.linalg.norm(axis)
 count=0
 for prim,v,_ in triangles(doc,binary):
  js=accessor(doc,binary,prim['attributes']['JOINTS_0']);ws=accessor(doc,binary,prim['attributes']['WEIGHTS_0'])
  strength=np.where(js==joint,ws,0).sum(1)
  height=np.ptp(v[:,1]);along=(v-transform[:3,3])@axis
  select=(strength>.65)|((strength>.1)&(along>height*.08))
  changed=select&(strength<.9999);count+=int(changed.sum())
  js[select]=joint;ws[select]=[1,0,0,0]
  prim['attributes']['JOINTS_0']=writer.add(js,'VEC4',5123)
  prim['attributes']['WEIGHTS_0']=writer.add(ws,'VEC4')
 doc['asset'].setdefault('extras',{})['sfery_rigid_blade']=1
 writer.save(path);return count
if __name__=='__main__':
 for path in sorted(Path('assets/creatures_hd').glob('ratnik_*.glb')):
  print(path.name,fix(path,Path('tools/_tmp/blades026-base')),flush=True)
