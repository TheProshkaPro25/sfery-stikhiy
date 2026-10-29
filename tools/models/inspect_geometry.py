"""Диагностика GLB без переэкспорта: размеры, вырожденные грани, плоские области.
Не меняет исходники. Python + NumPy; отчёт JSON по всему игровому набору.
"""
import json, struct
from pathlib import Path
import numpy as np

def read_glb(path):
    raw=Path(path).read_bytes(); pos=12; doc=None; binary=None
    while pos<len(raw):
        size,kind=struct.unpack_from('<II',raw,pos); chunk=raw[pos+8:pos+8+size];pos+=8+size
        if kind==0x4e4f534a:doc=json.loads(chunk)
        elif kind==0x004e4942:binary=chunk
    return doc,binary

def accessor(doc,binary,index):
    a=doc['accessors'][index];view=doc['bufferViews'][a['bufferView']]
    dtype={5126:'<f4',5125:'<u4',5123:'<u2',5121:'u1'}[a['componentType']]
    width={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']]
    start=view.get('byteOffset',0)+a.get('byteOffset',0);item=np.dtype(dtype).itemsize
    return np.ndarray((a['count'],width),dtype=dtype,buffer=binary,offset=start,strides=(view.get('byteStride',width*item),item)).copy()

def triangles(doc,binary):
    for mesh in doc.get('meshes',[]):
        for p in mesh['primitives']:
            if p.get('mode',4)!=4 or 'indices' not in p:continue
            v=accessor(doc,binary,p['attributes']['POSITION'])
            f=accessor(doc,binary,p['indices']).reshape(-1,3)
            yield p,v,f

def inspect(path):
    doc,binary=read_glb(path);out={'model':path.stem,'primitives':[]}
    for prim,v,f in triangles(doc,binary):
        points=v[f];normal=np.cross(points[:,1]-points[:,0],points[:,2]-points[:,0]);area=np.linalg.norm(normal,axis=1)/2
        out['primitives'].append({'vertices':len(v),'triangles':len(f),'degenerate':int((area<1e-12).sum()),'finite':bool(np.isfinite(v).all()),'max_triangle_area':float(area.max()),'extent':(v.max(0)-v.min(0)).tolist()})
    return out

if __name__=='__main__':
    import sys
    root=Path(__file__).resolve().parents[2]
    report=[inspect(p) for p in sorted((root/'assets/creatures_hd').glob('*.glb')) if not p.stem.startswith(('glubinnik','sumrachnik'))]
    target=Path(sys.argv[1] if len(sys.argv)>1 else '/tmp/sfery-model-geometry.json')
    target.write_text(json.dumps(report,ensure_ascii=False,indent=2))
    print('Проверено моделей:',len(report),'нечисловых координат:',sum(not p['finite'] for r in report for p in r['primitives']))
