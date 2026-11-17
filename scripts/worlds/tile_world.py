"""Build an optional, derived streaming pack without modifying its source GLB."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

import numpy as np

from tile_geometry import partition,read_glb,simplify,write_gltf

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts'))
from engine import resolve_engine


def run_engine(*args):
    result=subprocess.run([resolve_engine(ROOT),'--headless','--path',str(ROOT/'game'),*args],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace')
    (ROOT/'.local/tiling').mkdir(parents=True,exist_ok=True)
    with (ROOT/'.local/tiling/build.log').open('a',encoding='utf-8') as log:log.write(result.stdout)
    if result.returncode or 'SCRIPT ERROR:' in result.stdout or 'ERROR:' in result.stdout:raise RuntimeError(result.stdout[-8000:])


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('place');parser.add_argument('--tile-size',type=float,default=128)
    parser.add_argument('--register',action='store_true',help='Add the optional manifest to the place catalog')
    args=parser.parse_args()
    if args.tile_size<16 or args.tile_size>512:parser.error('tile size must be 16..512 metres')
    catalog_path=ROOT/'game/data/travel_places.json';catalog=json.loads(catalog_path.read_bytes())
    item=next(p for p in catalog['places'] if p['id']==args.place)
    source=ROOT/'game'/item['scene'].removeprefix('res://')
    with source.open('rb') as file:source_hash=hashlib.file_digest(file,'sha256').hexdigest()
    pipeline_hash=hashlib.sha256(Path(__file__).read_bytes()+Path(__file__).with_name('tile_geometry.py').read_bytes()+Path(__file__).with_name('bake_tiles.gd').read_bytes()).hexdigest()
    digest=hashlib.sha256(f'3:{pipeline_hash}:{source_hash}:{args.tile_size}'.encode()).hexdigest()[:12]
    output=source.parent/f'tiles_{args.tile_size:g}_{digest}'
    output.mkdir(parents=True,exist_ok=True)
    if (output/'manifest.json').exists():
        print('Using completed pack:',output,flush=True)
    else:
        print('Reading',source,flush=True)
        attrs,faces,material,images,textures,samplers=read_glb(source)
        shared=output/'shared';shared.mkdir(exist_ok=True);names=[]
        for i,(mime,data) in enumerate(images):
            name=f'image_{i}'+('.jpg' if mime=='image/jpeg' else '.png');(shared/name).write_bytes(data);names.append(name)
        tiles=[];overview_count=0
        for cell,attributes,triangles in partition(attrs,faces,args.tile_size):
            ident=f'x{cell[0]}_z{cell[1]}'
            write_gltf(output/'detail'/f'{ident}.gltf',attributes,triangles,material,names,textures,samplers)
            voxel=max(1,args.tile_size/32)
            coarse,indices=simplify(attributes,triangles,voxel)
            while len(indices)>1400 and voxel<args.tile_size:
                voxel*=1.5;coarse,indices=simplify(attributes,triangles,voxel)
            if len(indices):write_gltf(output/'overview'/f'{ident}.gltf',coarse,indices,material,names,textures,samplers)
            tiles.append({'id':ident,'cell':[int(v) for v in cell],'origin':[float(cell[0]*args.tile_size),0,float(cell[1]*args.tile_size)],'scene':f'detail/{ident}.tscn','triangles':len(triangles),'overview':bool(len(indices))})
            overview_count+=len(indices)
            print(ident,len(triangles),'triangles; overview',len(indices),flush=True)
        plan={'version':1,'source_scene':item['scene'],'source_sha256':source_hash,'pipeline_sha256':pipeline_hash,'tile_size':args.tile_size,'bounds':item['bounds'],'overview_scene':'overview.tscn','detail_radius':args.tile_size*1.25,'tiles':tiles,'overview_triangles':overview_count,'source_triangles':len(faces)}
        (output/'build_plan.json').write_text(json.dumps(plan,indent=2)+'\n',encoding='utf-8',newline='\n')
        print('Importing derived geometry...',flush=True);run_engine('--editor','--import')
        relative=output.relative_to(ROOT/'game').as_posix()
        print('Baking collision...',flush=True)
        run_engine('--script','res://../scripts/worlds/bake_tiles.gd','--','--pack=res://'+relative)
        files=sorted(p for p in output.rglob('*') if p.is_file() and p.suffix not in ['.import','.uid'] and p.name not in ['manifest.json','build_plan.json'])
        plan['files']={}
        for p in files:
            with p.open('rb') as file:plan['files'][p.relative_to(output).as_posix()]=hashlib.file_digest(file,'sha256').hexdigest()
        (output/'manifest.json').write_text(json.dumps(plan,indent=2)+'\n',encoding='utf-8',newline='\n')
    manifest='res://'+(output/'manifest.json').relative_to(ROOT/'game').as_posix()
    if args.register:
        # Focused insertion preserves existing coordinates and JSON lexemes.
        text=catalog_path.read_text(encoding='utf-8')
        match=re.search(r'"id":\s*"'+re.escape(args.place)+r'"',text)
        start=text.rfind('{',0,match.start());end=text.find('"scene"',match.end())
        if end<0:raise RuntimeError('Catalog scene field missing')
        existing=re.search(r'"tile_manifest":\s*"[^"]*"',text[start:end])
        field='"tile_manifest": '+json.dumps(manifest)
        if existing:
            a=start+existing.start();b=start+existing.end();text=text[:a]+field+text[b:]
        else:text=text[:end]+field+',\n      '+text[end:]
        catalog_path.write_text(text,encoding='utf-8',newline='\n')
    print('Complete:',manifest,flush=True)


if __name__=='__main__':main()
