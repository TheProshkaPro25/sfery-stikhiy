"""Regression for shin collapse during Dragnar idle (requires Godot pose export).

Export all six variants for 12 seconds with sample-step=6. This checks the actual
skinned surface, rather than accepting a correct skeleton with crushed skin.
"""
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools/models'))
from leg_surface_distortion import measure
source=Path(sys.argv[1])
expected={'creature_dragnar_'+a for a in ['fire','gale','light','shadow','stone','tide']}
folders=[p for p in source.iterdir() if p.name in expected]
assert {p.name for p in folders}==expected,'all six variants are required'
for folder in sorted(folders):
    report=measure(folder)
    idle=[p for p in report['poses'] if p['action']=='idle']
    assert len(idle)>=121 and max(p['frame'] for p in idle)>=720,'full idle sweep missing'
    worst=min(idle,key=lambda p:p['min_area_ratio'])
    # The unmodified clip retains at least 87% in all six variants. A 65%
    # floor leaves room for normal motion but rejects the former 17–25% folds.
    assert worst['min_area_ratio']>=.65,(report['id'],'shin surface collapsed',worst)
    assert max(p['area_fraction_below_half'] for p in idle)==0,(report['id'],'crushed leg triangles')
    print(report['id'],len(idle),'idle samples; minimum area ratio',round(worst['min_area_ratio'],4),flush=True)
