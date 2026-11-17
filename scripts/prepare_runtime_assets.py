"""Inventory completed world tiles and approved frogs for public Git commits.

Run after tile_world.py --all --register. This updates the inventory and narrow
ignore exceptions; it neither stages files nor deletes previous local packs.
"""
import json
from pathlib import Path
import re

from runtime_assets import ROOT,MAX_FILE,asset_path
from manage_assets import sha256

FROGS={
    'montane':{'license':'CC-BY-4.0 (underlying scans); CC0 (RubenCUR rig contribution)','source':'https://blendswap.com/blend/29791','credit':'ffish.asia / floraZia.com; RubenCUR'},
    'toad':{'license':'CC-BY-4.0 (underlying scans); CC0 (RubenCUR rig contribution)','source':'https://blendswap.com/blend/29791','credit':'ffish.asia / floraZia.com; RubenCUR'},
    'american_toad':{'license':'CC-BY-4.0 (underlying toad lineage)','source':'https://blendswap.com/blend/29791','credit':'ffish.asia / floraZia.com; RubenCUR; FrogExplorer adaptation'},
    'bullfrog':{'license':'CC0-1.0 (scan)','source':'https://sketchfab.com/3d-models/12244c1e4f3a4bfdbc217acba90e8baa','credit':'ffish.asia / floraZia.com; FrogExplorer adaptation'},
    'whites':{'license':'CC-BY-NC-4.0 (scan and derived model)','source':'https://sketchfab.com/3d-models/model-23-whites-tree-frog-ed77b869c1aa49cfa1305724b28f3b94','credit':'DigitalLife3D; FrogExplorer adaptation'}
}


def main():
    catalog=json.loads((ROOT/'game/data/travel_places.json').read_bytes())
    files={};worlds=[];folders=[]
    def add(relative):
        path=asset_path(ROOT,relative)
        size=path.stat().st_size
        if not 0<size<MAX_FILE:raise ValueError('Asset does not fit ordinary Git: '+relative)
        digest=sha256(path)
        files[relative]={'path':relative,'size':size,'sha256':digest}
    for place in catalog['places']:
        if place.get('provider')!='local_mesh':continue
        manifest=place['tile_manifest'].removeprefix('res://');path=asset_path(ROOT,manifest)
        pack=json.loads(path.read_bytes());folder=Path(manifest).parent;folders.append(folder.as_posix())
        add(manifest)
        for name,digest in pack['files'].items():
            if Path(name).suffix not in ['.res','.tscn','.tres','.png','.jpg','.jpeg']:raise ValueError('Rebuild pack to remove intermediate files: '+place['id'])
            relative=(folder/name).as_posix();add(relative)
            if files[relative]['sha256']!=digest:raise ValueError('Tile pack checksum failed: '+relative)
        license_id=place.get('license',{}).get('id','cc-by-4.0')
        if place['id'] in ['rochester_high_falls','washington_national_mall','holland_downtown','norfolk_waterfront','lynchburg_riverfront']:license_id='USGS-USDA-source-terms; ODbL-1.0 footprints'
        worlds.append({'id':place['id'],'manifest':manifest,'license':license_id,'attribution':place['attribution'],'sources':place.get('source_urls',[place['source_url']]),'changes':'Rebased/scaled source, clipped tile geometry, shared materials, baked collision and simplified distant overview. Original coverage and limitations retained.'})
    frogs=[]
    for species,notice in FROGS.items():
        relative='assets/frogs/'+species+'.glb';add(relative);frogs.append({'species':species,'path':relative,**notice,'changes':'FrogExplorer geometry, skin, mouth and eye refinements; retargeted AFK CC0 animations and original added motions.'})
    inventory={'version':1,'description':'Public runtime assets; source licenses apply separately from MIT code. Full originals and build intermediates are excluded.','worlds':worlds,'frogs':frogs,'excluded_frogs':[{'species':'red_eye','reason':'Blendkit royalty-free terms prohibit publicly extractable model distribution. Local import remains supported.','source':'https://www.blendkit.com/terms-and-conditions-2026/'}],'files':[files[key] for key in sorted(files)]}
    (ROOT/'config/runtime_assets.lock.json').write_text(json.dumps(inventory,indent=2,ensure_ascii=False)+'\n',encoding='utf-8',newline='\n')
    ignore=ROOT/'.gitignore';text=ignore.read_text(encoding='utf-8')
    rules=['# BEGIN PUBLISHED RUNTIME ASSETS (prepare_runtime_assets.py)',*[f'!/game/assets/frogs/{name}.glb' for name in FROGS],
           '!/game/assets/worlds/*/','/game/assets/worlds/*/*',*[f'!/game/{folder}/' for folder in folders],
           '/game/assets/worlds/*/tiles_*/*','!/game/assets/worlds/*/tiles_*/manifest.json','!/game/assets/worlds/*/tiles_*/overview.tscn']
    for sub in ['detail','overview','shared']:
        prefix='/game/assets/worlds/*/tiles_*/'+sub
        rules.extend(['!'+prefix+'/',prefix+'/*'])
        for suffix in (['res','tscn'] if sub!='shared' else ['tres','png','jpg','jpeg']):rules.append('!'+prefix+'/*.'+suffix)
    rules.append('# END PUBLISHED RUNTIME ASSETS');block='\n'.join(rules)
    pattern=r'# BEGIN PUBLISHED RUNTIME ASSETS.*?# END PUBLISHED RUNTIME ASSETS'
    if re.search(pattern,text,re.S):text=re.sub(pattern,lambda _:block,text,flags=re.S)
    else:text=text.rstrip()+'\n\n'+block+'\n'
    ignore.write_text(text,encoding='utf-8',newline='\n')
    print(json.dumps({'worlds':len(worlds),'frogs':len(frogs),'files':len(files),'bytes':sum(e['size'] for e in files.values()),'largest_bytes':max(e['size'] for e in files.values())},indent=2))


if __name__=='__main__':main()
