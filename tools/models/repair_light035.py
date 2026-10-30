"""Reproduce the reviewed035 Light repair without installing game assets.

Run at repository root with the scientific Python environment:
  python tools/models/repair_light035.py --base BASE030.glb --original PRE029.glb --out OUTPUT_DIR
Blender must be on PATH. Intermediate candidates and a source/hash manifest are
retained in OUTPUT_DIR; validation and installation are separate explicit steps.
"""
import argparse,hashlib,json,subprocess,sys
from pathlib import Path

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--base',required=True,type=Path)
parser.add_argument('--original',required=True,type=Path)
parser.add_argument('--out',required=True,type=Path)
args=parser.parse_args()
assert args.base.is_file() and args.original.is_file()
args.out.mkdir(parents=True,exist_ok=True)
for name in ['sockets','ankles','motion','candidate']:(args.out/name).mkdir(exist_ok=True)
paths={name:args.out/name/'rogozhuk_light.glb' for name in ['sockets','ankles','motion','candidate']}
commands=[
 ['blender','-b','--factory-startup','-t','2','-P','tools/models/repair_light_sockets035.py','--',str(args.base),str(paths['sockets'])],
 [sys.executable,'tools/models/restore_light_ankles035.py',str(paths['sockets']),str(args.original),str(paths['ankles'])],
 [sys.executable,'tools/models/repair_light_motion035.py',str(paths['ankles']),str(args.base),str(paths['motion'])],
 [sys.executable,'tools/models/repair_light_surface035.py',str(paths['motion']),str(paths['candidate'])],
]
for command in commands:subprocess.run(command,check=True)
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
manifest={'base':{'path':str(args.base.resolve()),'sha256':digest(args.base)},'original':{'path':str(args.original.resolve()),'sha256':digest(args.original)},'stages':{name:{'path':str(path.resolve()),'sha256':digest(path)} for name,path in paths.items()},'commands':commands,'installed':False}
(args.out/'manifest.json').write_text(json.dumps(manifest,indent=2))
print('Candidate:',paths['candidate'])
