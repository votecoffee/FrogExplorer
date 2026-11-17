"""Check original archive integrity and six actual international city exports."""
import hashlib
import json
from pathlib import Path
import struct

import numpy as np
import trimesh

ROOT=Path(__file__).resolve().parents[2]
IDS=["tokyo_imperial_palace","shanghai_lujiazui","berlin_teufelsberg","moscow_andronikov","montreal_sainte_elisabeth","mexico_city_cathedral"]


def main():
    checks=[]
    def check(value,label):
        checks.append({"test":label,"passed":bool(value)})
        print(("PASS " if value else "FAIL ")+label)
    catalog=json.loads((ROOT/"game/data/travel_places.json").read_bytes().decode("utf-8"))["places"]
    for place_id in IDS:
        folder=ROOT/"data/world_sources"/place_id
        source=(folder/"source.glb").read_bytes();receipt=json.loads((folder/"source_receipt.json").read_bytes().decode("utf-8"))
        build=json.loads((folder/"build_receipt.json").read_bytes().decode("utf-8"));config=json.loads((folder/"build_config.json").read_bytes().decode("utf-8"))
        item=next(p for p in catalog if p["id"]==place_id);path=ROOT/"game"/item["scene"].removeprefix("res://");raw=path.read_bytes()
        check(hashlib.md5(source).hexdigest()==receipt["source_md5"].split(":")[1] and len(source)==receipt["bytes"],place_id+": archive MD5 and byte length")
        check(hashlib.sha256(source).hexdigest()==receipt["source_sha256"]==build["source_sha256"],place_id+": preserved original SHA256")
        check(raw[:4]==b"glTF" and struct.unpack_from("<II",raw,4)==(2,len(raw)),place_id+": complete binary glTF 2")
        check(hashlib.sha256(raw).hexdigest()==build["glb_sha256"] and len(raw)==build["glb_bytes"],place_id+": export matches build receipt")
        scene=trimesh.load(path,force="scene",process=False);count=sum(len(m.faces) for m in scene.geometry.values())
        check(count==build["export_triangles"] and count<=config["budget"]*1.05,place_id+": measured triangle budget")
        bounds=scene.bounds;expected=np.array([[item["bounds"][0]-.25,item["vertical_bounds"][0],item["bounds"][1]-.25],[item["bounds"][2]+.25,item["vertical_bounds"][1],item["bounds"][3]+.25]])
        check(np.isfinite(bounds).all() and np.allclose(bounds,expected,atol=.005),place_id+": actual GLB axes/bounds match runtime metadata")
        check(item==build["entry"],place_id+": runtime entry matches checked build")
        check(item["category"]=="city" and item["random_eligible"] and item["profiles"]==["windows"],place_id+": city filtering and device qualification")
        check(item["country"]==config["country"] and item["country"] in ["JP","CN","DE","RU","CA","MX"],place_id+": requested country identified")
        check(item["license"]==receipt["license"] and receipt["license"]["id"] in item["attribution"],place_id+": archive license identifier retained without relabeling")
        check(item["anchor"]["horizontal_crs"]=="LOCAL_MODEL" and not item["anchor"]["georeferenced"] and item["anchor"]["scale_accuracy"],place_id+": scale assumptions and missing georeference explicit")
        length=struct.unpack_from("<I",raw,12)[0];gltf=json.loads(raw[20:20+length]);images=gltf.get("images",[])
        check(all("bufferView" in image for image in images) and all("uri" not in b for b in gltf.get("buffers",[])),place_id+": offline export has no external buffer/texture dependencies")
        inspected=json.loads((folder/"inspection.json").read_bytes().decode("utf-8"))
        check(bool(images) if inspected["images"] else config["kind"].startswith("Simplified"),place_id+": textures retained or plain architecture explicitly declared")
        if place_id=="berlin_teufelsberg":
            check("Sphere_Material.001_0" in config.get("exclude_meshes",[]) and np.max(bounds[1]-bounds[0])<300,place_id+": giant source sky sphere excluded from playable geometry")
    report={"checks":checks,"failures":[c["test"] for c in checks if not c["passed"]]}
    (ROOT/"outputs/World_Cities_20261117/source_validation.json").write_bytes((json.dumps(report,indent=2)+"\n").encode("utf-8"));print("SOURCE_VALIDATION",len(checks),len(report["failures"]))
    if report["failures"]:raise SystemExit(1)


if __name__=="__main__":main()
