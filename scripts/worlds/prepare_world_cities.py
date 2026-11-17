"""Acquire six bounded international city models from public archival GLBs."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import shutil
import subprocess

from prepare_landmarks import acquire
import requests

ROOT=Path(__file__).resolve().parents[2]
OUTPUT=ROOT/"outputs/World_Cities_20261117"
PLACES=[
    ("tokyo_imperial_palace","Tokyo · Imperial Palace area, Japan","JP",10352067),
    ("shanghai_lujiazui","Shanghai · Central skyline, China","CN",10319397),
    ("berlin_teufelsberg","Berlin · Teufelsberg, Germany","DE",10305982),
    ("moscow_andronikov","Moscow · Andronikov area, Russia","RU",10352255),
    ("montreal_sainte_elisabeth","Montréal · Rue Sainte-Élisabeth, Canada","CA",10316577),
    ("mexico_city_cathedral","Mexico City · Metropolitan Cathedral, Mexico","MX",10230968),
]


def prepare(config):
    place_id,name,country,record_id=config
    folder=ROOT/"data/world_sources"/place_id;folder.mkdir(parents=True,exist_ok=True)
    path=folder/"zenodo.json"
    if not path.exists():
        cached=OUTPUT/"research"/str(record_id)/"record.json"
        if cached.exists():shutil.copy2(cached,path)
        else:
            response=requests.get(f"https://zenodo.org/api/records/{record_id}",timeout=60);response.raise_for_status()
            path.write_bytes((json.dumps(response.json(),indent=2,ensure_ascii=False)+"\n").encode("utf-8"))
    record=json.loads(path.read_bytes().decode("utf-8"))
    entry=next(f for f in record["files"] if f["key"].endswith(".glb"))
    acquire((place_id,name,record_id,entry["key"].removesuffix(".glb")))
    build_config=folder/"build_config.json"
    recipe=ROOT/"config/worlds"/(place_id+".json")
    if not build_config.exists() and recipe.exists():shutil.copy2(recipe,build_config)
    if not build_config.exists():
        # Inspection must precede calibration/arrival selection. These initial
        # values are not export authorization; worker refuses an unchecked pack.
        data={"name":name,"country":country,"category":"city","scene_name":"city.glb","output_dir":"outputs/World_Cities_20261117",
              "scale":1,"target":[0,0],"budget":500000,"calibration":"Not calibrated yet", "reviewed":False,
              "description":"City source awaiting inspection.","kind":"Unreviewed source model",
              "credit":" / ".join(c["name"] for c in record["metadata"].get("creators",[]))}
        build_config.write_bytes((json.dumps(data,indent=2,ensure_ascii=False)+"\n").encode("utf-8"))
    return folder


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("--blender");parser.add_argument("--inspect",action="store_true")
    parser.add_argument("--city",choices=[c[0] for c in PLACES]);args=parser.parse_args()
    OUTPUT.mkdir(parents=True,exist_ok=True)
    with ThreadPoolExecutor(3) as pool:folders=list(pool.map(prepare,[c for c in PLACES if not args.city or c[0]==args.city]))
    if args.blender:
        for folder in folders:
            command=[args.blender,"--background","--python-exit-code","1","--python",str(ROOT/"scripts/worlds/build_landmark.py"),"--",str(folder),"--config="+str(folder/"build_config.json")]
            if args.inspect:command.append("--inspect")
            subprocess.run(command,check=True)


if __name__=="__main__":main()
