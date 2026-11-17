"""Build five bounded offline city packs from OSM, USGS 3DEP and USDA NAIP.

Run in tools/world_data_env with requirements.txt, then pass --blender PATH.
Original responses, requests, timestamps, hashes and height provenance are kept.
These are aerial-textured terrain plus extruded footprints, not photogrammetry.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess

import numpy as np
from PIL import Image
from pyproj import Transformer
import requests
from shapely import constrained_delaunay_triangles, make_valid
from shapely.geometry import LineString, Point, Polygon, box
from shapely.geometry.polygon import orient
from shapely.ops import polygonize, unary_union

ROOT = Path(__file__).resolve().parents[2]
NAIP = "https://imagery.nationalmap.gov/arcgis/rest/services/USGSNAIPImagery/ImageServer"
DEM = "https://elevation.nationalmap.gov/arcgis/rest/services/3DEPElevation/ImageServer"
OSM_MAP = "https://api.openstreetmap.org/api/0.6/map.json"
PLACES = [
    ("rochester_high_falls", "Rochester, NY · High Falls", 43.1626, -77.6158, 1000, 32618),
    ("washington_national_mall", "Washington, DC · National Mall", 38.8895, -77.0353, 1600, 32618),
    ("holland_downtown", "Holland, MI · Downtown & Centennial Park", 42.7890, -86.1071, 1000, 32616),
    ("norfolk_waterfront", "Norfolk, VA · Downtown waterfront", 36.8470, -76.2917, 1000, 32618),
    ("lynchburg_riverfront", "Lynchburg, VA · Downtown riverfront", 37.4154, -79.1415, 1000, 32617),
]
HEADERS = {"User-Agent": "FrogExplorer/0.1 offline city pack preparation"}


def write_json(path, data):
    path.write_bytes((json.dumps(data, indent=2, ensure_ascii=False) + "\n").encode("utf-8"))


def fetch_json(url, params):
    response = requests.get(url, params=params, headers=HEADERS, timeout=120)
    response.raise_for_status()
    result = response.json()
    if "error" in result or "remark" in result:
        raise RuntimeError(str(result.get("error", result.get("remark"))))
    return result


def image_export(service, folder, name, bbox, crs, count, elevation=False):
    path = folder / name
    if path.exists() and (folder / (name + ".request.json")).exists():
        return
    params = dict(f="json", bbox=",".join(map(str, bbox)), bboxSR=crs,
                  imageSR=crs, size=f"{count},{count}", format="tiff" if elevation else "jpg",
                  renderingRule=json.dumps({"rasterFunction": "None" if elevation else "NaturalColor"}),
                  interpolation="RSP_BilinearInterpolation", adjustAspectRatio="false")
    if elevation:
        params.update(pixelType="F32", noData=-999999)
    result = fetch_json(service + "/exportImage", params)
    extent = result["extent"]
    # Refuse a server-adjusted extent: every mesh vertex and UV relies on this grid.
    actual = [extent[k] for k in ("xmin", "ymin", "xmax", "ymax")]
    if not np.allclose(actual, bbox, atol=.01, rtol=0):
        raise ValueError(f"Unexpected export extent: {actual} vs {bbox}")
    response = requests.get(result["href"], headers=HEADERS, timeout=120)
    response.raise_for_status()
    path.write_bytes(response.content)
    with Image.open(path) as image:
        if image.size != (count, count):
            raise ValueError("Unexpected raster dimensions")
    write_json(folder / (name + ".request.json"), {"service": service, "parameters": params,
               "response": result, "retrieved_utc": datetime.now(timezone.utc).isoformat()})


def polygons(geometry):
    if geometry.geom_type == "Polygon":
        return [geometry]
    return [p for g in getattr(geometry, "geoms", []) for p in polygons(g)]


def number(value):
    if not value:
        return None
    match = re.fullmatch(r"\s*([\d.]+)\s*(m|ft|feet|'|metres|meters)?\s*", str(value))
    if not match:
        return None
    try:
        return float(match[1]) * (.3048 if match[2] in ("ft", "feet", "'") else 1)
    except ValueError:
        return None


def prepare(config, blender):
    place_id, name, lat, lon, side, epsg = config
    print("PREPARE", place_id, flush=True)
    folder = ROOT / "data/world_sources" / place_id
    folder.mkdir(parents=True, exist_ok=True)
    project = Transformer.from_crs(4326, epsg, always_xy=True)
    geographic = Transformer.from_crs(epsg, 4326, always_xy=True)
    east, north = project.transform(lon, lat)
    half = side / 2
    extent = [east-half, north-half, east+half, north+half]
    corners = [geographic.transform(x, y) for x, y in
               [(extent[0], extent[1]), (extent[0], extent[3]), (extent[2], extent[1]), (extent[2], extent[3])]]
    west, south = np.min(corners, axis=0)
    east_geo, north_geo = np.max(corners, axis=0)
    bbox = f"{west:.6f},{south:.6f},{east_geo:.6f},{north_geo:.6f}"
    # Five small one-off map extracts, cached permanently. Do not use the main
    # editing API as a runtime world-streaming backend or for larger regions.
    raw_path = folder / "osm_api.json"
    if not raw_path.exists():
        write_json(raw_path, fetch_json(OSM_MAP, {"bbox": bbox}))
        write_json(folder / "osm_api.request.json", {"endpoint": OSM_MAP, "bbox": bbox,
                   "retrieved_utc": datetime.now(timezone.utc).isoformat()})
    raw = json.loads(raw_path.read_bytes().decode("utf-8"))
    nodes = {e["id"]: e for e in raw["elements"] if e["type"] == "node"}
    ways = {e["id"]: e for e in raw["elements"] if e["type"] == "way"}
    for way in ways.values():
        way["geometry"] = [{"lat": nodes[n]["lat"], "lon": nodes[n]["lon"]} for n in way["nodes"]]
    complete = list(ways.values())
    incomplete_relations = 0
    for element in raw["elements"]:
        if element["type"] != "relation":
            continue
        members = [m for m in element["members"] if m["type"] == "way"]
        if any(m["ref"] not in ways for m in members):
            incomplete_relations += 1
            continue
        for member in members:
            member["geometry"] = ways[member["ref"]]["geometry"]
        complete.append(element)
    osm_path = folder / "osm.json"
    write_json(osm_path, {"elements": complete, "incomplete_relations_skipped": incomplete_relations})
    count = 129
    step = side / (count-1)
    dem_bbox = [extent[0]-step/2, extent[1]-step/2, extent[2]+step/2, extent[3]+step/2]
    # Only two bounded raster requests per city. No live requests during play.
    with ThreadPoolExecutor(2) as pool:
        futures = [pool.submit(image_export, DEM, folder, "elevation.tif", dem_bbox, epsg, count, True),
                   pool.submit(image_export, NAIP, folder, "aerial.jpg", extent, epsg, 2048)]
        for future in futures:
            future.result()
    for service, title in [(DEM, "dem"), (NAIP, "naip")]:
        path = folder / (title + ".service.json")
        if not path.exists():
            write_json(path, fetch_json(service, {"f": "json"}))
    # Retain actual intersecting imagery records, including acquisition years.
    catalog_path = folder / "naip.catalog.json"
    if not catalog_path.exists():
        write_json(catalog_path, fetch_json(NAIP + "/query", dict(f="json", where="Category=1",
            geometry=",".join(map(str, extent)), geometryType="esriGeometryEnvelope", inSR=epsg,
            spatialRel="esriSpatialRelIntersects", outFields="*", returnGeometry="false")))
    heights = np.array(Image.open(folder / "elevation.tif"), dtype=float)
    if heights.shape != (count, count) or not np.isfinite(heights).all() or heights.min() < -500 or heights.max() > 4500:
        raise ValueError("Invalid or missing elevation samples; refusing a flat replacement")

    def height(x, y):
        col = min(count-1.000001, max(0, (x+half)/step))
        row = min(count-1.000001, max(0, (half-y)/step))
        i, j = int(row), int(col)
        a, b = row-i, col-j
        return float((1-a)*((1-b)*heights[i,j]+b*heights[i,j+1]) + a*((1-b)*heights[i+1,j]+b*heights[i+1,j+1]))

    baseline = height(0, 0)
    clip = box(-half, -half, half, half)

    def coords(points):
        result = []
        for p in points:
            if "lon" in p and "lat" in p:
                x, y = project.transform(p["lon"], p["lat"])
                result.append((x-east, y-north))
        return result

    def areas(element):
        if element["type"] == "way":
            ring = coords(element.get("geometry", []))
            return make_valid(Polygon(ring)) if len(ring) >= 4 and ring[0] == ring[-1] else Polygon()
        outer, inner = [], []
        for member in element.get("members", []):
            ring = coords(member.get("geometry", []))
            if len(ring) >= 2:
                (inner if member.get("role") == "inner" else outer).append(LineString(ring))
        outside = unary_union(list(polygonize(unary_union(outer))))
        holes = unary_union(list(polygonize(unary_union(inner))))
        return make_valid(outside.difference(holes))

    elements = json.loads(osm_path.read_bytes().decode("utf-8"))["elements"]
    buildings, forbidden, paths, landmarks = [], [], [], []
    building_elements = [(e, areas(e)) for e in elements if
                         e.get("tags", {}).get("building", "no") != "no" or "building:part" in e.get("tags", {})]
    # Relations often repeat their member ways. Discard the duplicate standalone footprints.
    members = {m["ref"] for e, g in building_elements if e["type"] == "relation" for m in e.get("members", [])}
    part_union = unary_union([g for e, g in building_elements if "building:part" in e.get("tags", {})])
    height_counts = {"height_tag": 0, "levels_tag": 0, "estimated": 0}
    for element, geometry in building_elements:
        if element["type"] == "way" and element["id"] in members:
            continue
        tags = element.get("tags", {})
        if "building:part" not in tags:
            geometry = geometry.difference(part_union)
        geometry = make_valid(geometry).intersection(clip)
        tagged = number(tags.get("height"))
        levels = number(tags.get("building:levels"))
        source = "height_tag" if tagged is not None else "levels_tag" if levels is not None else "estimated"
        h = tagged if tagged is not None else levels*3.2 if levels is not None else (4 if tags.get("building") in ("garage", "garages", "shed") else 9)
        h = max(.5, min(200, h))
        bottom = number(tags.get("min_height")) or (number(tags.get("building:min_level")) or 0)*3.2
        for polygon in polygons(geometry):
            if polygon.area < 2:
                continue
            polygon = orient(polygon, sign=1)
            forbidden.append(polygon)
            rings = [list(polygon.exterior.coords)[:-1]] + [list(r.coords)[:-1] for r in polygon.interiors]
            base = min(height(x, y) for ring in rings for x, y in ring) - baseline - .15
            roof = max(base+bottom+.3, base+h)
            triangles = [list(t.exterior.coords)[:3] for t in constrained_delaunay_triangles(polygon).geoms]
            buildings.append(dict(osm=f'{element["type"]}/{element["id"]}', name=tags.get("name", ""),
                height_source=source, height=h, base=base+bottom, roof=roof, rings=rings, triangles=triangles,
                roof_shape=tags.get("roof:shape", "flat"), roof_height=number(tags.get("roof:height")) or 0,
                obelisk=tags.get("man_made")=="obelisk"))
            height_counts[source] += 1
            if tags.get("name"):
                landmarks.append({"name": tags["name"], "osm": buildings[-1]["osm"]})
    for element in elements:
        tags = element.get("tags", {})
        if tags.get("natural") == "water" or tags.get("waterway") == "riverbank":
            forbidden.extend(polygons(areas(element).intersection(clip)))
        highway = tags.get("highway", "")
        if highway in ("footway", "pedestrian", "path", "living_street", "residential", "service") and not tags.get("bridge") and not tags.get("tunnel"):
            points = coords(element.get("geometry", []))
            if len(points) > 1:
                line = LineString(points).intersection(clip.buffer(-25))
                for segment in ([line] if line.geom_type == "LineString" else getattr(line, "geoms", [])):
                    if segment.geom_type == "LineString":
                        paths.extend(segment.interpolate(d) for d in np.arange(0, segment.length, 8))
    obstruction = unary_union(forbidden)
    candidates = []
    for point in sorted(paths, key=lambda p: p.distance(Point(0, 0))):
        x, y = point.x, point.y
        slope = max(abs(height(x+2,y)-height(x-2,y)), abs(height(x,y+2)-height(x,y-2))) / 4
        if obstruction.distance(point) >= 5 and slope < .18 and all(point.distance(Point(p[0], -p[2])) > 8 for p in candidates):
            candidates.append([x, height(x,y)-baseline+.04, -y])
            if len(candidates) == 12:
                break
    if not buildings or len(candidates) < 3:
        raise ValueError("Insufficient mapped buildings or dry, gently sloping arrival candidates")
    terrain = {"side": side, "count": count, "heights": (heights-baseline).tolist()}
    anchor = {"longitude": lon, "latitude": lat, "horizontal_crs": f"EPSG:{epsg}",
              "anchor_projected": [east, north, baseline], "local_axes": "X east, Y up, Z south",
              "elevation_source": DEM, "vertical_conversion": "none; native 3DEP service elevations, see dem.service.json"}
    build = dict(id=place_id, name=name, anchor=anchor, terrain=terrain, buildings=buildings,
                 spawn=candidates[0], spawn_candidates=candidates[1:], height_counts=height_counts, landmarks=landmarks)
    write_json(folder / "prepared.json", build)
    sources = [p for p in folder.iterdir() if p.suffix in (".json", ".jpg", ".tif") and p.name not in ("build_receipt.json", "source_receipt.json")]
    write_json(folder / "source_receipt.json", {"prepared_utc": datetime.now(timezone.utc).isoformat(),
        "bbox_wgs84": [float(west), float(south), float(east_geo), float(north_geo)], "anchor": anchor,
        "sources": {"osm": OSM_MAP, "terrain": DEM, "imagery": NAIP}, "height_counts": height_counts,
        "incomplete_boundary_relations_skipped": incomplete_relations,
        "limitation": "Extruded mapped footprints; unknown heights estimated at 9m (sheds/garages 4m). No photogrammetry, facades, tree trunks, swimming or bridge decks.",
        "sha256": {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}})
    print("DATA READY", place_id, len(buildings), "buildings", height_counts, "spawn", candidates[0], flush=True)
    if blender:
        subprocess.run([blender, "--background", "--python-exit-code", "1", "--python", str(ROOT / "scripts/worlds/export_us_city.py"), "--", str(folder)], check=True)
    return build


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--blender")
    parser.add_argument("--city", choices=[c[0] for c in PLACES])
    args = parser.parse_args()
    for config in PLACES:
        if not args.city or config[0] == args.city:
            prepare(config, args.blender)


if __name__ == "__main__":
    main()
