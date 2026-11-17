"""Acquire four public landmark models with integrity/provenance receipts.

Zenodo distributes these as open Objaverse/Sketchfab archival assets. No viewer
extraction, account download automation or runtime network access is used.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess

import requests

ROOT=Path(__file__).resolve().parents[2]
PLACES=[
    ("machu_picchu","Machu Picchu · Peru",10326006,"d59370ac4a444628b95081f5bb7bbd02"),
    ("great_wall_china","Great Wall · Huanghuacheng area, China",10219301,"3ce0cc3108e54097862ea735309d9292"),
    ("giza_pyramids","Pyramids of Giza · Egypt",10239232,"20fa1b7c608a43e1814c3744641732a4"),
    ("rome_colosseum","Colosseum · Rome, Italy",10386979,"535dc96e586f40bd956ea3cbff810055"),
]


def write(path,data):
    path.write_bytes((json.dumps(data,indent=2,ensure_ascii=False)+"\n").encode("utf-8"))


def acquire(config):
    place_id,name,record_id,uid=config
    folder=ROOT/"data/world_sources"/place_id
    folder.mkdir(parents=True,exist_ok=True)
    metadata_path=folder/"zenodo.json"
    if not metadata_path.exists():
        response=requests.get(f"https://zenodo.org/api/records/{record_id}",timeout=60);response.raise_for_status();write(metadata_path,response.json())
    metadata=json.loads(metadata_path.read_bytes().decode("utf-8"))
    entry=next(f for f in metadata["files"] if f["key"]==uid+".glb")
    path=folder/"source.glb"
    if not path.exists():
        response=requests.get(entry["links"]["self"],stream=True,timeout=120);response.raise_for_status()
        temporary=folder/"source.glb.part"
        with temporary.open("wb") as output:
            for chunk in response.iter_content(1024*1024):output.write(chunk)
        if temporary.stat().st_size!=entry["size"]:raise ValueError("Incomplete download: "+place_id)
        if hashlib.md5(temporary.read_bytes()).hexdigest()!=entry["checksum"].split(":",1)[1]:raise ValueError("Checksum mismatch: "+place_id)
        temporary.replace(path)
    if path.stat().st_size!=entry["size"] or hashlib.md5(path.read_bytes()).hexdigest()!=entry["checksum"].split(":",1)[1]:raise ValueError("Cached source failed integrity: "+place_id)
    original=folder/"sketchfab_metadata.json"
    if not original.exists():
        response=requests.get("https://api.sketchfab.com/v3/models/"+uid,timeout=60)
        if response.ok:write(original,response.json())
    write(folder/"source_receipt.json",{"id":place_id,"name":name,"record_id":record_id,"archive_url":f"https://zenodo.org/records/{record_id}","original_url":"https://sketchfab.com/3d-models/"+uid,"prepared_utc":datetime.now(timezone.utc).isoformat(),"license":metadata["metadata"].get("license"),"creators":metadata["metadata"].get("creators"),"description":metadata["metadata"].get("description"),"bytes":path.stat().st_size,"source_md5":entry["checksum"],"source_sha256":hashlib.sha256(path.read_bytes()).hexdigest()})
    print("SOURCE READY",place_id,path.stat().st_size,flush=True)
    return folder


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--blender")
    parser.add_argument("--inspect",action="store_true")
    parser.add_argument("--city",choices=[x[0] for x in PLACES])
    args=parser.parse_args()
    configs=[p for p in PLACES if not args.city or p[0]==args.city]
    with ThreadPoolExecutor(4) as pool:folders=list(pool.map(acquire,configs))
    if args.blender:
        for folder in folders:
            command=[args.blender,"--background","--python-exit-code","1","--python",str(ROOT/"scripts/worlds/build_landmark.py"),"--",str(folder)]
            if args.inspect:command.append("--inspect")
            subprocess.run(command,check=True)


if __name__=="__main__":main()
