"""Smooth transferred skin weights on the reconstructed exterior, retaining its atlas."""
from pathlib import Path
import shutil,sys,numpy as np
from inspect_geometry import read_glb,accessor,triangles
from upgrade_rigs import Writer
from repair_capes import weights_of
from repair_skin import smooth_surface_weights
from repair_beetles import store_weights,smooth
from compact_glb import compact
path=Path('assets/creatures_hd/rogozhuk_stone.glb');backup=Path(sys.argv[1] if len(sys.argv)>1 else 'tools/_tmp/stone028-atlas-base')/path.name;backup.parent.mkdir(parents=True,exist_ok=True)
if not backup.exists():shutil.copy2(path,backup)
d,b=read_glb(backup);writer=Writer(d,b);skin=d['skins'][0];names=[d['nodes'][node]['name'] for node in skin['joints']]
for p,v,f in triangles(d,b):
 original=weights_of(d,b,p,len(names));w=smooth_surface_weights(v,f,original,.035)
 strongest=np.zeros(len(v))
 for prefixes in [('arm.','forearm.','hand.'),('thigh.','shin.','foot.'),('rear_thigh.','rear_shin.','rear_foot.')]:
  for side in ['L','R']:
   group=[names.index(prefix+side) for prefix in prefixes if prefix+side in names]
   strongest=np.maximum(strongest,original[:,group].sum(1))
 # The ground-contact ends already passed the engine's sole test. Smooth the
 # new torso bridges without diffusing those distal weights into the torso.
 preserve=smooth((strongest-.40)/.20)*smooth((-.08-v[:,1])/.12)
 w=w*(1-preserve[:,None])+original*preserve[:,None]
 limbs=[i for i,n in enumerate(names) if n.startswith(('arm.','forearm.','hand.','thigh.','shin.','foot.','rear_'))]
 upper=smooth((v[:,1]+.025)/.12);mass=w[:,limbs].sum(1)*upper;w[:,limbs]*=1-upper[:,None];w[:,names.index('chest')]+=mass
 store_weights(writer,p,w)
d['asset']['extras']['stone_exterior_weight_smoothing']=2;writer.save(path);compact(path)
