"""Check archived source integrity and actual exported offline landmark packs."""
import hashlib
import json
from pathlib import Path
import struct

import numpy as np
import trimesh

ROOT=Path(__file__).resolve().parents[2]
IDS=["machu_picchu","great_wall_china","giza_pyramids","rome_colosseum"]


def main():
    checks=[]
    def check(value,label):
        checks.append({"test":label,"passed":bool(value)})
        print(("PASS " if value else "FAIL ")+label)
    catalog=json.loads((ROOT/"game/data/travel_places.json").read_bytes().decode("utf-8"))["places"]
    for place_id in IDS:
        folder=ROOT/"data/world_sources"/place_id
        source=(folder/"source.glb").read_bytes()
        receipt=json.loads((folder/"source_receipt.json").read_bytes().decode("utf-8"))
        build=json.loads((folder/"build_receipt.json").read_bytes().decode("utf-8"))
        item=next(p for p in catalog if p["id"]==place_id)
        path=ROOT/"game"/item["scene"].removeprefix("res://")
        raw=path.read_bytes()
        check(hashlib.md5(source).hexdigest()==receipt["source_md5"].split(":")[1] and len(source)==receipt["bytes"],place_id+": archive MD5 and byte length")
        check(hashlib.sha256(source).hexdigest()==receipt["source_sha256"]==build["source_sha256"],place_id+": preserved original SHA256")
        check(raw[:4]==b"glTF" and struct.unpack_from("<II",raw,4)==(2,len(raw)),place_id+": complete binary glTF 2")
        check(hashlib.sha256(raw).hexdigest()==build["glb_sha256"] and len(raw)==build["glb_bytes"],place_id+": export matches build receipt")
        scene=trimesh.load(path,force="scene",process=False)
        count=sum(len(m.faces) for m in scene.geometry.values())
        ceiling=1600000 if place_id=="rome_colosseum" else 250000
        check(count==build["export_triangles"] and count<=ceiling,place_id+": measured triangle budget")
        bounds=scene.bounds;expected=np.array([[item["bounds"][0]-.25,item["vertical_bounds"][0],item["bounds"][1]-.25],[item["bounds"][2]+.25,item["vertical_bounds"][1],item["bounds"][3]+.25]])
        check(np.isfinite(bounds).all() and np.allclose(bounds,expected,atol=.005),place_id+": actual GLB axes/bounds match runtime metadata")
        check(item==build["entry"],place_id+": runtime entry matches checked build")
        check(item["category"]=="history" and item["random_eligible"] and item["profiles"]==["windows"],place_id+": history filtering and device qualification")
        check(item["anchor"]["horizontal_crs"]=="LOCAL_MODEL" and not item["anchor"]["georeferenced"] and item["anchor"]["scale_accuracy"],place_id+": scale assumptions and missing georeference explicit")
        json_length=struct.unpack_from("<I",raw,12)[0];gltf=json.loads(raw[20:20+json_length])
        check(bool(gltf.get("images")) and all("bufferView" in image for image in gltf["images"]),place_id+": original textures embedded for offline play")
    report={"checks":checks,"failures":[c["test"] for c in checks if not c["passed"]]}
    (ROOT/"outputs/Landmarks_20261117/source_validation.json").write_bytes((json.dumps(report,indent=2)+"\n").encode("utf-8"))
    print("SOURCE_VALIDATION",len(checks),len(report["failures"]))
    if report["failures"]:raise SystemExit(1)


if __name__=="__main__":main()
