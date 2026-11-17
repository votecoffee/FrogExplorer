"""Check retained source integrity, geographic rebasing and exported city bounds."""
import hashlib
import json
from pathlib import Path
import struct

import numpy as np
from PIL import Image
from pyproj import Transformer

from prepare_us_cities import PLACES, ROOT


def read(path):
    return json.loads(path.read_bytes().decode("utf-8"))


def main():
    checks = []
    def check(ok, label):
        checks.append({"test": label, "passed": bool(ok)})
        print(("PASS " if ok else "FAIL ") + label)
    catalog = read(ROOT / "game/data/travel_places.json")["places"]
    for place_id, name, lat, lon, side, epsg in PLACES:
        folder = ROOT / "data/world_sources" / place_id
        prepared = read(folder / "prepared.json")
        receipt = read(folder / "source_receipt.json")
        exported = read(folder / "build_receipt.json")
        item = next(p for p in catalog if p["id"] == place_id)
        check(all(hashlib.sha256((folder/k).read_bytes()).hexdigest()==v for k,v in receipt["sha256"].items()), place_id+": retained source hashes match")
        blob = (ROOT / "game/assets/worlds" / place_id / "city.glb").read_bytes()
        magic, version, length, chunk_length, chunk_type = struct.unpack_from("<4sIIII", blob)
        check(magic==b"glTF" and version==2 and length==len(blob) and chunk_type==0x4e4f534a, place_id+": complete GLB v2 container")
        gltf = json.loads(blob[20:20+chunk_length])
        check(hashlib.sha256(blob).hexdigest()==exported["scene_sha256"], place_id+": GLB matches build receipt")
        positions = [gltf["accessors"][p["attributes"]["POSITION"]] for m in gltf["meshes"] for p in m["primitives"]]
        bounds = [min(a["min"][axis] for a in positions) for axis in range(3)], [max(a["max"][axis] for a in positions) for axis in range(3)]
        check(np.allclose([bounds[0][0],bounds[0][2],bounds[1][0],bounds[1][2]],[-side/2,-side/2,side/2,side/2],atol=.01), place_id+": exported X/Z extents are meter-based and rebased")
        anchor = item["anchor"]
        east,north = Transformer.from_crs(4326,epsg,always_xy=True).transform(lon,lat)
        check(np.allclose(anchor["anchor_projected"][:2],[east,north],atol=.001,rtol=0) and anchor==prepared["anchor"],place_id+": UTM anchor agrees with WGS84 reference")
        pixels = np.array(Image.open(folder/"aerial.jpg"))
        check(pixels.shape==(2048,2048,3) and pixels.std()>15,place_id+": aerial texture has actual RGB imagery")
        dem = np.array(Image.open(folder/"elevation.tif"))
        check(np.allclose(np.array(prepared["terrain"]["heights"])+anchor["anchor_projected"][2],dem,atol=1e-5),place_id+": terrain preserves native DEM heights")
        check(item["spawn"]==prepared["spawn"] and item["spawn_candidates"]==prepared["spawn_candidates"] and len(item["spawn_candidates"])>=2,place_id+": runtime arrivals match dry source candidates")
        check(sum(prepared["height_counts"].values())==len(prepared["buildings"]) and exported["buildings"]==len(prepared["buildings"]),place_id+": height provenance covers every footprint part")
    report = {"checks":checks,"failures":[c["test"] for c in checks if not c["passed"]]}
    (ROOT/"outputs/US_Cities_20261117/source_validation.json").write_bytes((json.dumps(report,indent=2)+"\n").encode("utf-8"))
    raise SystemExit(1 if report["failures"] else 0)


if __name__=="__main__":
    main()
