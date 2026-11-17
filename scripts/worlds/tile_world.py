"""Build an optional, derived streaming pack without modifying its source GLB."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

from tile_geometry import merge_surfaces,partition,read_glb,simplify,write_gltf

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts'))
from engine import resolve_engine


def run_engine(*args):
    result=subprocess.run([resolve_engine(ROOT),'--headless','--path',str(ROOT/'game'),*args],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace')
    (ROOT/'.local/tiling').mkdir(parents=True,exist_ok=True)
    with (ROOT/'.local/tiling/build.log').open('a',encoding='utf-8') as log:log.write(result.stdout)
    if result.returncode or 'SCRIPT ERROR:' in result.stdout or 'ERROR:' in result.stdout:raise RuntimeError(result.stdout[-8000:])


def register_manifest(place,manifest):
    catalog_path=ROOT/'game/data/travel_places.json'
    # Focused insertion preserves existing coordinates and JSON lexemes.
    text=catalog_path.read_text(encoding='utf-8')
    match=re.search(r'"id":\s*"'+re.escape(place)+r'"',text)
    start=text.rfind('{',0,match.start());end=text.find('"scene"',match.end())
    if end<0:raise RuntimeError('Catalog scene field missing')
    existing=re.search(r'"tile_manifest":\s*"[^"]*"',text[start:end])
    field='"tile_manifest": '+json.dumps(manifest)
    if existing:
        a=start+existing.start();b=start+existing.end();text=text[:a]+field+text[b:]
    else:text=text[:end]+field+',\n      '+text[end:]
    catalog_path.write_text(text,encoding='utf-8',newline='\n')


def build(item,tile_size,register):
    source=ROOT/'game'/item['scene'].removeprefix('res://')
    with source.open('rb') as file:source_hash=hashlib.file_digest(file,'sha256').hexdigest()
    pipeline_hash=hashlib.sha256(Path(__file__).read_bytes()+Path(__file__).with_name('tile_geometry.py').read_bytes()+Path(__file__).with_name('bake_tiles.gd').read_bytes()).hexdigest()
    digest=hashlib.sha256(f'4:{pipeline_hash}:{source_hash}:{tile_size}'.encode()).hexdigest()[:12]
    output=source.parent/f'tiles_{tile_size:g}_{digest}'
    output.mkdir(parents=True,exist_ok=True)
    if (output/'manifest.json').exists():
        print('Using completed pack:',output,flush=True)
    else:
        print('Reading',source,flush=True)
        surfaces,materials,images,textures,samplers=read_glb(source)
        source_triangles=sum(len(s['faces']) for s in surfaces)
        source_surfaces=len(surfaces);surfaces=merge_surfaces(surfaces)
        shared=output/'shared';shared.mkdir(exist_ok=True);names=[]
        for i,(mime,data) in enumerate(images):
            name=f'image_{i}'+('.jpg' if mime=='image/jpeg' else '.png');(shared/name).write_bytes(data);names.append(name)
        tiles=[];overview_count=0;cells={}
        for surface in surfaces:
            for cell,attributes,triangles in partition(surface['attrs'],surface['faces'],tile_size):
                cells.setdefault(cell,[]).append({'attrs':attributes,'faces':triangles,'material':surface['material']})
        for cell,parts in sorted(cells.items()):
            ident=f'x{cell[0]}_z{cell[1]}'
            write_gltf(output/'detail'/f'{ident}.gltf',parts,materials,names,textures,samplers)
            distant=[]
            for part in parts:
                attributes=part['attrs'];triangles=part['faces'];voxel=max(.25,tile_size/32)
                coarse,indices=simplify(attributes,triangles,voxel)
                budget=max(40,1400//len(parts))
                while len(indices)>budget and voxel<tile_size:
                    voxel*=1.5;coarse,indices=simplify(attributes,triangles,voxel)
                if len(indices):distant.append({'attrs':coarse,'faces':indices,'material':part['material']})
            if distant:write_gltf(output/'overview'/f'{ident}.gltf',distant,materials,names,textures,samplers)
            detail_count=sum(len(p['faces']) for p in parts);far_count=sum(len(p['faces']) for p in distant)
            tiles.append({'id':ident,'cell':[int(v) for v in cell],'origin':[float(cell[0]*tile_size),0,float(cell[1]*tile_size)],'scene':f'detail/{ident}.tscn','triangles':detail_count,'materials':sorted({p['material'] for p in parts}),'overview':bool(distant)})
            overview_count+=far_count
            print(ident,detail_count,'triangles; overview',far_count,flush=True)
        plan={'version':1,'source_scene':item['scene'],'source_sha256':source_hash,'pipeline_sha256':pipeline_hash,'tile_size':tile_size,'bounds':item['bounds'],'overview_scene':'overview.tscn','detail_radius':tile_size*1.25,'tiles':tiles,'overview_triangles':overview_count,'source_triangles':source_triangles,'source_surfaces':source_surfaces,'source_materials':len(materials),'attribution':item.get('attribution',''),'source_urls':item.get('source_urls',[item.get('source_url','')]),'license':item.get('license',{})}
        (output/'build_plan.json').write_text(json.dumps(plan,indent=2)+'\n',encoding='utf-8',newline='\n')
        print('Importing derived geometry...',flush=True);run_engine('--editor','--import')
        relative=output.relative_to(ROOT/'game').as_posix()
        print('Baking collision...',flush=True)
        run_engine('--script','res://../scripts/worlds/bake_tiles.gd','--','--pack=res://'+relative)
        # Runtime dependency closure, without duplicate glTF authoring buffers.
        files=sorted(p for p in output.rglob('*') if p.is_file() and p.suffix in ['.tscn','.res','.tres','.png','.jpg','.jpeg'])
        plan['files']={}
        for p in files:
            with p.open('rb') as file:plan['files'][p.relative_to(output).as_posix()]=hashlib.file_digest(file,'sha256').hexdigest()
        (output/'manifest.json').write_text(json.dumps(plan,indent=2)+'\n',encoding='utf-8',newline='\n')
    manifest='res://'+(output/'manifest.json').relative_to(ROOT/'game').as_posix()
    if register:register_manifest(item['id'],manifest)
    print('Complete:',manifest,flush=True)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('place',nargs='?');parser.add_argument('--all',action='store_true')
    parser.add_argument('--tile-size',type=float,help='Override the per-place recipe')
    parser.add_argument('--register',action='store_true',help='Register completed manifests in the catalog')
    args=parser.parse_args()
    if bool(args.place)==args.all:parser.error('Choose one place ID or --all')
    if args.tile_size is not None and not 16<=args.tile_size<=512:parser.error('tile size must be 16..512 metres')
    catalog=json.loads((ROOT/'game/data/travel_places.json').read_bytes())
    sizes=json.loads((ROOT/'config/worlds/tiling.json').read_bytes())['tile_sizes']
    places=[p for p in catalog['places'] if p.get('provider')=='local_mesh' and (args.all or p['id']==args.place)]
    if not places:parser.error('No matching local-mesh place')
    for item in places:build(item,args.tile_size or sizes.get(item['id'],128),args.register)


if __name__=='__main__':main()
