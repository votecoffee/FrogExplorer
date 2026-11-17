"""Exact X/Z clipping and shared-texture tiles for static, single-surface GLBs.

The supported source is intentionally narrow: no skins, morphs or animation.
Unsupported inputs fail rather than silently losing source appearance.
"""
import copy
import json
from pathlib import Path
import struct

import numpy as np

COMPONENTS={5121:np.dtype('u1'),5123:np.dtype('<u2'),5125:np.dtype('<u4'),5126:np.dtype('<f4')}
WIDTHS={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}


def read_glb(path):
    raw=Path(path).read_bytes()
    magic,version,length=struct.unpack_from('<III',raw)
    if (magic,version,length)!=(0x46546c67,2,len(raw)):raise ValueError('Expected a complete GLB 2.0 file')
    chunks={};offset=12
    while offset<len(raw):
        size,kind=struct.unpack_from('<II',raw,offset);offset+=8
        chunks[kind]=raw[offset:offset+size];offset+=size
    doc=json.loads(chunks[0x4e4f534a]);binary=chunks[0x004e4942]
    if doc.get('skins') or doc.get('animations'):raise ValueError('Only static scenery is supported')
    primitives=[(node,doc['meshes'][node['mesh']]['primitives']) for node in doc['nodes'] if 'mesh' in node]
    if len(primitives)!=1 or len(primitives[0][1])!=1:raise ValueError('Tile source must have one mesh and one surface')
    node,prims=primitives[0];primitive=prims[0]
    if primitive.get('mode',4)!=4 or primitive.get('targets'):raise ValueError('Only static triangles are supported')
    # Existing world recipes bake all transforms. Reject transformed sources
    # rather than producing plausible-looking, geographically misplaced tiles.
    for n in doc['nodes']:
        if any(k in n for k in ('matrix','translation','rotation','scale')):
            if n.get('matrix',np.eye(4).flatten().tolist())!=np.eye(4).flatten().tolist() or n.get('translation',[0,0,0])!=[0,0,0] or n.get('rotation',[0,0,0,1])!=[0,0,0,1] or n.get('scale',[1,1,1])!=[1,1,1]:raise ValueError('Bake source node transforms before tiling')
    def accessor(index):
        a=doc['accessors'][index]
        if 'sparse' in a or a.get('normalized',False):raise ValueError('Sparse/normalized accessors need baking first')
        view=doc['bufferViews'][a['bufferView']];dtype=COMPONENTS[a['componentType']];width=WIDTHS[a['type']]
        return np.ndarray((a['count'],width),dtype=dtype,buffer=binary,offset=view.get('byteOffset',0)+a.get('byteOffset',0),strides=(view.get('byteStride',width*dtype.itemsize),dtype.itemsize)).copy()
    attrs={key:accessor(value).astype(np.float32) for key,value in primitive['attributes'].items()}
    if set(attrs)-{'POSITION','NORMAL','TANGENT','TEXCOORD_0','COLOR_0'}:raise ValueError('Unsupported vertex attributes')
    faces=accessor(primitive['indices']).reshape(-1,3).astype(np.int64) if 'indices' in primitive else np.arange(len(attrs['POSITION'])).reshape(-1,3)
    material=copy.deepcopy(doc.get('materials',[{}])[primitive.get('material',0)])
    images=[]
    for item in doc.get('images',[]):
        view=doc['bufferViews'][item['bufferView']]
        images.append((item.get('mimeType','image/png'),binary[view.get('byteOffset',0):view.get('byteOffset',0)+view['byteLength']]))
    return attrs,faces,material,images,copy.deepcopy(doc.get('textures',[])),copy.deepcopy(doc.get('samplers',[]))


def clip_triangle(vertices,cell,size):
    """Clip all attributes together; exact boundary positions close tile seams."""
    polygon=[v.astype(np.float64) for v in vertices]
    for axis,edge,sign in [(0,cell[0]*size,1),(0,(cell[0]+1)*size,-1),(2,cell[1]*size,1),(2,(cell[1]+1)*size,-1)]:
        result=[]
        for i,current in enumerate(polygon):
            previous=polygon[i-1];a=(previous[axis]-edge)*sign;b=(current[axis]-edge)*sign
            if (a>=0)!=(b>=0):
                hit=previous+(current-previous)*(a/(a-b));hit[axis]=edge;result.append(hit)
            if b>=0:result.append(current)
        polygon=result
        if len(polygon)<3:return np.empty((0,3,vertices.shape[1]),np.float32)
    triangles=np.array([[polygon[0],polygon[i],polygon[i+1]] for i in range(1,len(polygon)-1)])
    area=np.linalg.norm(np.cross(triangles[:,1,:3]-triangles[:,0,:3],triangles[:,2,:3]-triangles[:,0,:3]),axis=1)
    return triangles[area>1e-9].astype(np.float32)


def partition(attrs,faces,size):
    keys=['POSITION']+[k for k in attrs if k!='POSITION'];widths=[attrs[k].shape[1] for k in keys]
    packed=np.concatenate([attrs[k] for k in keys],axis=1)
    positions=attrs['POSITION'][faces][:,:,[0,2]]
    low=np.floor(positions.min(axis=1)/size).astype(int)
    # A face ending exactly on a boundary belongs to its lower cell. A vertical
    # face lying on a boundary belongs to the positive cell, exactly once.
    upper=positions.max(axis=1);lower=positions.min(axis=1)
    high=np.floor(np.where(upper>lower,np.nextafter(upper,-np.inf,dtype=np.float32),upper)/size).astype(int)
    interior=np.all(low==high,axis=1);groups={}
    for cell in np.unique(low[interior],axis=0):
        chosen=faces[interior & np.all(low==cell,axis=1)]
        groups[tuple(cell)]=[packed[chosen].reshape(-1,packed.shape[1])]
    for i in np.flatnonzero(~interior):
        for x in range(low[i,0],high[i,0]+1):
            for z in range(low[i,1],high[i,1]+1):
                clipped=clip_triangle(packed[faces[i]],(x,z),size)
                if len(clipped):groups.setdefault((x,z),[]).append(clipped.reshape(-1,packed.shape[1]))
    for cell,parts in sorted(groups.items()):
        values=np.concatenate(parts);values,indices=np.unique(values,axis=0,return_inverse=True)
        result={};offset=0
        for key,width in zip(keys,widths):result[key]=values[:,offset:offset+width].copy();offset+=width
        result['POSITION']-=np.array([cell[0]*size,0,cell[1]*size],np.float32)
        for key in ['NORMAL','TANGENT']:
            if key in result:
                v=result[key][:,:3];v/=np.maximum(np.linalg.norm(v,axis=1,keepdims=True),1e-12)
        yield cell,result,indices.reshape(-1,3).astype(np.uint32)


def simplify(attrs,faces,voxel):
    """Vertex clustering for a distant, non-colliding overview only."""
    pos=attrs['POSITION'];bins=np.floor(pos/voxel).astype(np.int64)
    # Keep opposing sides apart, including thin walls and roof undersides.
    if 'NORMAL' in attrs:
        normals=attrs['NORMAL'];axis=np.argmax(np.abs(normals),axis=1)
        side=axis*2+(normals[np.arange(len(normals)),axis]<0)
        bins=np.column_stack((bins,side))
    _,mapping=np.unique(bins,axis=0,return_inverse=True);count=np.bincount(mapping)
    result={key:np.column_stack([np.bincount(mapping,weights=values[:,j])/count for j in range(values.shape[1])]).astype(np.float32) for key,values in attrs.items()}
    for key in ['NORMAL','TANGENT']:
        if key in result:
            vectors=result[key][:,:3];vectors/=np.maximum(np.linalg.norm(vectors,axis=1,keepdims=True),1e-12)
    remapped=mapping[faces];valid=np.all(np.diff(np.sort(remapped,axis=1),axis=1)!=0,axis=1)
    return result,remapped[valid].astype(np.uint32)


def write_gltf(path,attrs,faces,material,images,textures,samplers):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    doc={'asset':{'version':'2.0','generator':'FrogExplorer tile packer'},'scene':0,'scenes':[{'nodes':[0]}],'nodes':[{'mesh':0}],'buffers':[],'bufferViews':[],'accessors':[],'materials':[material],'meshes':[{'primitives':[{'attributes':{},'material':0}]}]}
    binary=bytearray();primitive=doc['meshes'][0]['primitives'][0]
    for name,values in [*attrs.items(),('indices',faces.reshape(-1,1))]:
        while len(binary)%4:binary.append(0)
        values=np.asarray(values,dtype='<u4' if name=='indices' else '<f4');start=len(binary);binary.extend(values.tobytes())
        doc['bufferViews'].append({'buffer':0,'byteOffset':start,'byteLength':values.nbytes,'target':34963 if name=='indices' else 34962})
        access={'bufferView':len(doc['bufferViews'])-1,'componentType':5125 if name=='indices' else 5126,'count':len(values),'type':{1:'SCALAR',2:'VEC2',3:'VEC3',4:'VEC4'}[values.shape[1]]}
        if name=='POSITION':access.update(min=values.min(axis=0).tolist(),max=values.max(axis=0).tolist())
        doc['accessors'].append(access)
        if name=='indices':primitive['indices']=len(doc['accessors'])-1
        else:primitive['attributes'][name]=len(doc['accessors'])-1
    doc['buffers']=[{'uri':path.with_suffix('.bin').name,'byteLength':len(binary)}]
    if images:doc.update(images=[{'uri':'../shared/'+name} for name in images],textures=textures,samplers=samplers)
    path.with_suffix('.bin').write_bytes(binary);path.write_text(json.dumps(doc,separators=(',',':'))+'\n',encoding='utf-8',newline='\n')
