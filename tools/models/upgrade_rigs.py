"""Rig v2: плавные каналы, опорные кости и нормализованные локальные веса.
Сохраняет исходную геометрию, UV, текстуры и старые глобальные позы покоя.
Использование: python3 tools/models/upgrade_rigs.py --species kolossar
Оригиналы сохраняются вне проекта в /tmp/sfery-rig-v1; повторный запуск идемпотентен.
"""
import argparse, copy, json, shutil, struct
from pathlib import Path
import numpy as np
from inspect_geometry import read_glb, accessor, triangles


def qmul(a,b):
    x,y,z,w=np.moveaxis(np.asarray(a),-1,0);X,Y,Z,W=np.moveaxis(np.asarray(b),-1,0)
    return np.stack((w*X+x*W+y*Z-z*Y,w*Y-x*Z+y*W+z*X,w*Z+x*Y-y*X+z*W,w*W-x*X-y*Y-z*Z),axis=-1)


def qconj(q):
    return np.asarray(q)*np.array([-1,-1,-1,1])


def qfraction(q,k):
    q=np.asarray(q).copy();q/=np.maximum(np.linalg.norm(q,axis=-1,keepdims=True),1e-12)
    q=np.where(q[...,-1:]<0,-q,q);angle=np.arccos(np.clip(q[...,3],-1,1));s=np.sin(angle)
    factor=np.divide(np.sin(angle*k),s,out=np.full_like(s,k),where=np.abs(s)>1e-7)
    return np.concatenate((q[...,:3]*factor[...,None],np.cos(angle*k)[...,None]),axis=-1)


def matrix(node):
    if 'matrix' in node:return np.array(node['matrix']).reshape(4,4).T
    x,y,z,w=node.get('rotation',[0,0,0,1]);r=np.array([[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],[2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],[2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]])
    out=np.eye(4);out[:3,:3]=r@np.diag(node.get('scale',[1,1,1]));out[:3,3]=node.get('translation',[0,0,0]);return out


def globals_of(doc):
    nodes=doc['nodes'];parent={c:i for i,n in enumerate(nodes) for c in n.get('children',[])};cache={}
    def get(i):
        if i not in cache:cache[i]=(get(parent[i]) if i in parent else np.eye(4))@matrix(nodes[i])
        return cache[i]
    return [get(i) for i in range(len(nodes))]


class Writer:
    def __init__(self,doc,binary):self.doc=doc;self.binary=bytearray(binary)
    def add(self,array,kind,component=5126):
        dtype={5126:'<f4',5123:'<u2',5125:'<u4'}[component];a=np.asarray(array,dtype=dtype)
        self.binary.extend(b'\0'*((-len(self.binary))%4));offset=len(self.binary);data=a.tobytes();self.binary.extend(data)
        view=len(self.doc['bufferViews']);self.doc['bufferViews'].append({'buffer':0,'byteOffset':offset,'byteLength':len(data)})
        index=len(self.doc['accessors']);self.doc['accessors'].append({'bufferView':view,'componentType':component,'count':len(a),'type':kind})
        return index
    def save(self,path):
        self.doc['buffers'][0]['byteLength']=len(self.binary);raw=json.dumps(self.doc,separators=(',',':')).encode();raw+=b' '*((-len(raw))%4);self.binary.extend(b'\0'*((-len(self.binary))%4))
        result=struct.pack('<III',0x46546c67,2,28+len(raw)+len(self.binary))+struct.pack('<II',len(raw),0x4e4f534a)+raw+struct.pack('<II',len(self.binary),0x004e4942)+self.binary
        if not path.exists() or path.read_bytes()!=result:path.write_bytes(result)


def add_channel(writer,animation,node,path,input_index,values):
    idx=writer.add(values,'VEC4' if path=='rotation' else 'VEC3');sampler=len(animation['samplers'])
    animation['samplers'].append({'input':input_index,'output':idx,'interpolation':'LINEAR'})
    animation['channels'].append({'sampler':sampler,'target':{'node':node,'path':path}})


def upgrade(path,backup_dir):
    backup=backup_dir/path.name
    current,_=read_glb(path)
    is_v2=current.get('asset',{}).get('extras',{}).get('sfery_rig_version')==2
    if not backup.exists():
        if is_v2:return {'model':path.stem,'skipped':'уже v2; оригинал v1 не найден'}
        shutil.copy2(path,backup)
    elif not is_v2 and path.read_bytes()!=backup.read_bytes():
        raise ValueError(f'{path.name}: исходник изменён; выберите новую папку --backup')
    doc,binary=read_glb(backup);original=copy.deepcopy(doc);old_global=globals_of(doc);writer=Writer(doc,binary)
    skin=doc['skins'][0];old_joints=list(skin['joints']);names={doc['nodes'][n].get('name',''):n for n in old_joints}
    joint_slot={n:i for i,n in enumerate(old_joints)};new_specs=[];clavicles=[]
    primitives=list(triangles(doc,binary))
    # Каналы STEP никогда не оставляем в игровом скелете.
    step_count=0
    for animation in doc.get('animations',[]):
        for sampler in animation['samplers']:
            if sampler.get('interpolation')=='STEP':sampler['interpolation']='LINEAR';step_count+=1
    # Плечевой пояс остаётся в прежней точке; глобальная поза старых костей не меняется.
    if path.stem.startswith(('kolossar','ratnik')):
        for side in ['L','R']:
            arm=names.get('arm.'+side);chest=names.get('chest')
            if arm is None or chest is None:continue
            offset=np.array(doc['nodes'][arm].get('translation',[0,0,0]));node=len(doc['nodes'])
            doc['nodes'].append({'name':'clavicle.'+side,'translation':offset.tolist(),'children':[arm]})
            doc['nodes'][chest]['children']=[node if c==arm else c for c in doc['nodes'][chest]['children']]
            doc['nodes'][arm]['translation']=[0,0,0];skin['joints'].append(node);joint_slot[node]=len(joint_slot)
            clavicles.append((node,arm,offset));new_specs.append(('clavicle',node,arm,0.0))
            # Blender экспортирует и постоянные translation-каналы — переносим их вместе с суставом.
            for animation in doc['animations']:
                for channel in list(animation['channels']):
                    if channel['target'].get('node')!=arm:continue
                    sampler=animation['samplers'][channel['sampler']]
                    values=accessor(original,binary,sampler['output'])
                    if channel['target']['path']=='translation':sampler['output']=writer.add(values-offset,'VEC3')
                    elif channel['target']['path']=='rotation':
                        rest=np.array(original['nodes'][arm].get('rotation',[0,0,0,1]));delta=qmul(qconj(rest),values)
                        share=qmul(qmul(rest,qfraction(delta,0.18)),qconj(rest))
                        sampler['output']=writer.add(qmul(qconj(share),values),'VEC4')
                        add_channel(writer,animation,node,'rotation',sampler['input'],share)
    # Дистальные кости выделяются из реально привязанных вершин, а не из общего шаблона вида.
    for prefix,new_prefix in [('forearm.','hand.'),('shin.','foot.'),('wingtip.','wingfan.')]:
        for side in ['L','R']:
            donor=names.get(prefix+side);target_name=new_prefix+side
            # У четвероногих стопа уже есть: добавляем пальцевую опору к ней, не дублируем сустав.
            if target_name in names:
                donor=names[target_name]
                target_name=({'foot.':'toes.','hand.':'fingers.','wingfan.':'feathers.'}[new_prefix])+side
            if donor is None or target_name in names:continue
            local_y=[];donor_slot=old_joints.index(donor);inverse=np.linalg.inv(old_global[donor])
            for prim,v,f in primitives:
                js=accessor(original,binary,prim['attributes']['JOINTS_0']);ws=accessor(original,binary,prim['attributes']['WEIGHTS_0'])
                weight=np.where(js==donor_slot,ws,0).sum(1);selected=v[weight>.4]
                if len(selected):local_y.extend((selected@inverse[:3,:3].T+inverse[:3,3])[:,1].tolist())
            if len(local_y)<20:continue
            positive=np.array(local_y);positive=positive[positive>0.005]
            if len(positive)<20:continue
            length=float(np.quantile(positive,0.68));length=max(length,0.012)
            node=len(doc['nodes']);doc['nodes'].append({'name':target_name,'translation':[0,length,0]})
            doc['nodes'][donor].setdefault('children',[]).append(node);skin['joints'].append(node);joint_slot[node]=len(joint_slot)
            new_specs.append((new_prefix[:-1],node,donor,length))
    new_global=globals_of(doc)
    rest_error=max(float(np.abs(new_global[i]-m).max()) for i,m in enumerate(old_global))
    if rest_error>2e-5:raise ValueError(f'Поза покоя сместилась: {path.name} {rest_error}')
    parents={c:i for i,n in enumerate(doc['nodes']) for c in n.get('children',[])}
    allowed=np.eye(len(old_joints),dtype=bool)
    # Веса разрешены только между костями одной локальной цепочки. Убирает перенос крыла на руку.
    for a,node in enumerate(old_joints):
        for b,other in enumerate(old_joints):
            ancestors={node};p=node
            for _ in range(2):p=parents.get(p,-1);ancestors.add(p)
            reverse={other};p=other
            for _ in range(2):p=parents.get(p,-1);reverse.add(p)
            allowed[a,b]=other in ancestors or node in reverse
    seam_groups=0;max_weight_error=0.0
    for prim,v,f in primitives:
        js=accessor(original,binary,prim['attributes']['JOINTS_0']).astype(int);ws=accessor(original,binary,prim['attributes']['WEIGHTS_0']).astype(float)
        w=np.zeros((len(v),len(skin['joints'])),dtype=float)
        np.add.at(w,(np.arange(len(v))[:,None],js),ws)
        dominant=w[:,:len(old_joints)].argmax(1);w[:,:len(old_joints)]*=allowed[dominant]
        for kind,node,donor,length in new_specs:
            slot=joint_slot[node];old_slot=old_joints.index(donor);inv=np.linalg.inv(old_global[donor]);y=(v@inv[:3,:3].T+inv[:3,3])[:,1]
            if kind=='clavicle':
                # Плечевая броня следует поясу, локоть и кисть остаются на своей ветви.
                factor=np.clip(1-y/0.07,0,1)*0.65
            else:
                factor=np.clip((y-length*.72)/max(length*.55,0.01),0,1);factor=factor*factor*(3-2*factor)
            moved=w[:,old_slot]*factor;w[:,old_slot]-=moved;w[:,slot]+=moved
        # Одинаковые точки на UV-швах получают строго одинаковую привязку.
        _,uid=np.unique(np.round(v,6),axis=0,return_inverse=True);uid=uid.reshape(-1);counts=np.bincount(uid)
        sums=np.zeros((len(counts),w.shape[1]));np.add.at(sums,uid,w);w=(sums/counts[:,None])[uid];seam_groups+=int((counts>1).sum())
        top=np.argsort(-w,axis=1)[:,:4];weights=np.take_along_axis(w,top,axis=1);weights[weights<.005]=0
        sums=weights.sum(1);missing=sums<1e-8
        if missing.any():weights[missing,0]=1;top[missing,0]=dominant[missing]
        weights/=weights.sum(1,keepdims=True);max_weight_error=max(max_weight_error,float(np.abs(weights.sum(1)-1).max()))
        prim['attributes']['JOINTS_0']=writer.add(top,'VEC4',5123)
        prim['attributes']['WEIGHTS_0']=writer.add(weights,'VEC4')
    # Мягкие дополнительные сгибы кистей и стоп. Центр контакта — 1/3 клипа атаки.
    for kind,node,donor,length in new_specs:
        if kind=='clavicle':continue
        for animation in doc['animations']:
            source_animation=next(a for a in original['animations'] if a.get('name')==animation.get('name'))
            first=max(source_animation['samplers'],key=lambda s:original['accessors'][s['input']]['count'])
            times=accessor(original,binary,first['input']).reshape(-1);duration=max(float(times[-1]-times[0]),1e-5);p=(times-times[0])/duration
            name=animation.get('name','');amplitude=0.0
            if kind=='hand':amplitude={'attack':12,'hit':-6,'roar':-4,'stance':-3}.get(name,0)
            elif kind=='foot':amplitude={'attack':4,'hit':-3,'stance':-2}.get(name,0)
            elif kind=='wingfan':amplitude={'attack':5,'hit':-3,'idle':2,'roar':4,'stance':3}.get(name,0)
            pulse=np.sin(np.clip(p/(1/3),0,1)*np.pi/2) if name=='attack' else np.sin(p*np.pi)
            if name=='attack':pulse=np.where(p<=1/3,pulse,np.cos(np.clip((p-1/3)/(2/3),0,1)*np.pi/2))
            angle=np.deg2rad(amplitude)*pulse;values=np.zeros((len(times),4));values[:,0]=np.sin(angle/2);values[:,3]=np.cos(angle/2)
            add_channel(writer,animation,node,'rotation',first['input'],values)
    inverse=np.array([np.linalg.inv(new_global[n]).T.reshape(16) for n in skin['joints']])
    skin['inverseBindMatrices']=writer.add(inverse,'MAT4')
    doc.setdefault('asset',{}).setdefault('extras',{})['sfery_rig_version']=2
    writer.save(path)
    return {'model':path.stem,'bones_before':len(old_joints),'bones_after':len(skin['joints']),'step_channels_fixed':step_count,'rest_error':rest_error,'weight_error':max_weight_error,'welded_seams':seam_groups,'added':[doc['nodes'][n]['name'] for _,n,_,_ in new_specs]}


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--species');parser.add_argument('--backup',default='/tmp/sfery-rig-v1');args=parser.parse_args()
    root=Path(__file__).resolve().parents[2];backup=Path(args.backup);backup.mkdir(parents=True,exist_ok=True);report=[]
    for path in sorted((root/'assets/creatures_hd').glob('*.glb')):
        if path.stem.startswith(('glubinnik','sumrachnik','likorez')) or (args.species and not path.stem.startswith(args.species+'_')):continue
        result=upgrade(path,backup);report.append(result);print(json.dumps(result,ensure_ascii=False),flush=True)
    Path('/tmp/sfery-rig-v2-report'+('-'+args.species if args.species else '')+'.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
