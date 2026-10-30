"""Remove residual false abdominal paddles, preserving the six actual legs.

Works from the saved 030 baseline and writes a review candidate only.
"""
from pathlib import Path
import numpy as np
from inspect_geometry import read_glb, accessor, triangles
from upgrade_rigs import Writer, globals_of
from repair_water_beetle import read_weights, cap_mesh
from repair_beetles import store_weights
from compact_glb import compact

def repair():
 d,b=read_glb('tools/_tmp/repair030/base/rogozhuk_light.glb');writer=Writer(d,b)
 parts=list(triangles(d,b));p,v,_=parts[0];f=np.concatenate([parts[0][2],parts[1][2]])
 n=accessor(d,b,p['attributes']['NORMAL']);uv=accessor(d,b,p['attributes']['TEXCOORD_0']);w=read_weights(d,b,p,len(d['skins'][0]['joints']))
 gs=globals_of(d);names={node['name']:i for i,node in enumerate(d['nodes'])}
 center=gs[names['chest']][:3,3];fw=gs[names['head']][:3,3]-center;fw[1]=0;fw/=np.linalg.norm(fw)
 frame=np.column_stack([np.cross([0,1,0],fw),[0,1,0],fw]);c=(v-center)@frame;c[:,1]=v[:,1]
 # The dangling plates sit behind the abdomen, beyond every real leg.
 remove=(c[:,2]<-.30)&(c[:,1]<.075)
 keep_mask=remove[f].mean(1)<.5
 retained_source=int(keep_mask[:len(parts[0][2])].sum())
 keep=f[keep_mask];base=len(keep)
 v,n,uv,w,closed,loops=cap_mesh(v,n,uv,w,keep)
 print('removed',len(f)-base,'cut loops',loops,flush=True)
 _,uid=np.unique(np.round(v,6),axis=0,return_inverse=True)
 normal=np.zeros((uid.max()+1,3));tri=v[closed];area=np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0])
 for k in range(3):np.add.at(normal,uid[closed[:,k]],area)
 normal/=np.maximum(np.linalg.norm(normal,axis=1,keepdims=True),1e-12)
 attrs={'POSITION':writer.add(v,'VEC3'),'NORMAL':writer.add(normal[uid],'VEC3'),'TEXCOORD_0':writer.add(uv,'VEC2')}
 outputs=[]
 for faces,mat in [(closed[:retained_source],p['material']),(closed[retained_source:],parts[1][0]['material'])]:
  out={'attributes':dict(attrs),'indices':writer.add(faces.ravel()[:,None],'SCALAR',5125),'material':mat};store_weights(writer,out,w);outputs.append(out)
 d['meshes'][0]['primitives']=outputs+[part[0] for part in parts[2:]]
 d['asset'].setdefault('extras',{})['light_rear_plates_removed']=1
 path=Path('tools/_tmp/repair030/beetles/rogozhuk_light.glb');path.parent.mkdir(parents=True,exist_ok=True);writer.save(path);compact(path)
if __name__=='__main__':repair()
