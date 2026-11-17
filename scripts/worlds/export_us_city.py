"""Blender worker: aerial terrain, source-footprint buildings, retained .blend."""
import hashlib
import json
from pathlib import Path
import sys

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
folder = Path(sys.argv[sys.argv.index("--")+1])
data = json.loads((folder / "prepared.json").read_bytes().decode("utf-8"))
output = ROOT / "game/assets/worlds" / data["id"]
output.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
image = bpy.data.images.load(str(folder / "aerial.jpg"))


def material(name, color, aerial=False):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, 1)
    shader.inputs["Roughness"].default_value = .9
    shader.inputs["Specular IOR Level"].default_value = .1
    if aerial:
        node = mat.node_tree.nodes.new("ShaderNodeTexImage")
        node.image = image
        mat.node_tree.links.new(node.outputs["Color"], shader.inputs["Base Color"])
    return mat


ground = material("USDA NAIP aerial · source georeferenced", (.5,.6,.5), True)
walls = [material("Simplified facade " + str(i), c) for i, c in enumerate([
    (.51,.46,.40), (.62,.59,.52), (.48,.47,.45), (.57,.54,.49), (.43,.45,.45)])]
stone = material("Light stone · mapped obelisk", (.82,.80,.73))
side = data["terrain"]["side"]
half = side/2


def mesh(name, vertices, faces, mats, indices=None, smooth=False):
    geo = bpy.data.meshes.new(name)
    geo.from_pydata(vertices, [], faces)
    geo.update()
    obj = bpy.data.objects.new(name, geo)
    bpy.context.collection.objects.link(obj)
    for mat in mats:
        geo.materials.append(mat)
    uv = geo.uv_layers.new(name="Georeferenced aerial UV")
    for poly in geo.polygons:
        if indices:
            poly.material_index = indices[poly.index]
        poly.use_smooth = smooth
        for loop in poly.loop_indices:
            vertex = geo.vertices[geo.loops[loop].vertex_index].co
            uv.data[loop].uv = ((vertex.x+half)/side, (vertex.y+half)/side)
    return obj


n = data["terrain"]["count"]
step = side/(n-1)
vertices = [(j*step-half, half-i*step, z) for i, row in enumerate(data["terrain"]["heights"]) for j, z in enumerate(row)]
faces = []
for i in range(n-1):
    for j in range(n-1):
        a = i*n+j
        faces.extend([(a,a+n,a+1), (a+1,a+n,a+n+1)])
mesh("USGS 3DEP terrain", vertices, faces, [ground], smooth=True)
# A few groups keep draw calls and static collider count bounded.
groups = [[] for _ in walls]
for building in data["buildings"]:
    index = int(building["osm"].split("/")[1]) % len(walls)
    groups[index].append(building)
for index, buildings in enumerate(groups):
    vertices, faces, indices = [], [], []
    for building in buildings:
        pyramid = building.get("roof_shape")=="pyramidal" and len(building["rings"])==1 and building.get("roof_height",0)>0
        wall_top = building["roof"] - building.get("roof_height",0) if pyramid else building["roof"]
        wall_index = 2 if building.get("obelisk",False) else 1
        for ring in building["rings"]:
            # Respect Shapely ring winding, including courtyards.
            for a, b in zip(ring, ring[1:] + ring[:1]):
                k = len(vertices)
                vertices.extend([(a[0],a[1],building["base"]), (b[0],b[1],building["base"]),
                                 (b[0],b[1],wall_top), (a[0],a[1],wall_top)])
                faces.append((k,k+1,k+2,k+3));indices.append(wall_index)
        if pyramid:
            ring = building["rings"][0]
            center = (sum(p[0] for p in ring)/len(ring), sum(p[1] for p in ring)/len(ring))
            for a,b in zip(ring,ring[1:]+ring[:1]):
                k = len(vertices)
                vertices.extend([(a[0],a[1],wall_top),(b[0],b[1],wall_top),(*center,building["roof"])])
                faces.append((k,k+1,k+2));indices.append(wall_index)
            continue
        for triangle in building["triangles"]:
            k = len(vertices)
            a,b,c = triangle
            if (b[0]-a[0])*(c[1]-a[1]) - (b[1]-a[1])*(c[0]-a[0]) < 0:
                triangle = [a,c,b]
            vertices.extend([(x,y,building["roof"]) for x,y in triangle])
            faces.append((k,k+1,k+2));indices.append(0)
    mesh("OSM source footprints · facades " + str(index), vertices, faces, [ground, walls[index], stone], indices)
bpy.ops.export_scene.gltf(filepath=str(output / "city.glb"), export_format="GLB",
    export_animations=False, export_cameras=False, export_lights=False)
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=str(folder / "city.blend"))
path = output / "city.glb"
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
receipt = {"id": data["id"], "blender": bpy.app.version_string, "scene_bytes": path.stat().st_size,
    "scene_sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "buildings": len(data["buildings"]),
    "mesh_parts": len(meshes), "triangles": sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in meshes),
    "height_counts": data["height_counts"], "spawn": data["spawn"], "anchor": data["anchor"]}
(folder / "build_receipt.json").write_bytes((json.dumps(receipt, indent=2)+"\n").encode("utf-8"))
# Offline render only: no desktop interaction or game screen capture.
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 12
scene.cycles.use_denoising = True
scene.world = bpy.data.worlds.new("City sky")
scene.world.use_nodes = True
scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (.4,.48,.6,1)
scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = .7
bpy.ops.object.light_add(type="SUN", location=(0,0,side))
sun = bpy.context.object;sun.data.energy = 2;sun.rotation_euler = (.45,-.35,-.5)
bpy.ops.object.camera_add(location=(side*.48,-side*.63,side*.58))
camera = bpy.context.object
camera.rotation_euler = (Vector((0,0,15))-camera.location).to_track_quat("-Z","Y").to_euler()
camera.data.type = "ORTHO";camera.data.ortho_scale = side*1.4;camera.data.clip_end = side*5
scene.camera = camera
scene.render.resolution_x = 1100;scene.render.resolution_y = 850;scene.render.resolution_percentage = 100
scene.render.filepath = str(ROOT / "outputs/US_Cities_20261117" / (data["id"] + ".png"))
bpy.ops.render.render(write_still=True)
print("CITY PACK COMPLETE", data["id"], receipt)
