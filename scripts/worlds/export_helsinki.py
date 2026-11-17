"""Blender worker for prepare_helsinki.py; source vertices are already rebased."""
import json
import hashlib
from pathlib import Path
import sys

import bpy

source, root = map(Path, sys.argv[sys.argv.index("--") + 1:])
output = root / "game/assets/worlds/helsinki_senate_square"
output.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
for path in sorted(source.glob("*.obj")):
    bpy.ops.wm.obj_import(filepath=str(path), forward_axis="Y", up_axis="Z")
for material in bpy.data.materials:
    material.use_nodes = True
    shader = material.node_tree.nodes.get("Principled BSDF")
    if shader:
        shader.inputs["Roughness"].default_value = 1
        shader.inputs["Specular IOR Level"].default_value = .1
for obj in bpy.data.objects:
    if obj.type == "MESH":
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
bpy.ops.export_scene.gltf(filepath=str(output / "senate_square.glb"), export_format="GLB",
                          export_animations=False, export_cameras=False, export_lights=False)
# Pack texture references so the retained source is independent of the cache path.
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=str(root / "data/world_sources/helsinki_senate_square/senate_square.blend"))
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
pack_path = output / "senate_square.glb"
receipt = {"blender": bpy.app.version_string, "mesh_parts": len(meshes),
           "triangles": sum(len(o.data.polygons) for o in meshes),
           "packed_images": sum(image.packed_file is not None for image in bpy.data.images),
           "scene_bytes": pack_path.stat().st_size,
           "scene_sha256": hashlib.sha256(pack_path.read_bytes()).hexdigest()}
(root / "data/world_sources/helsinki_senate_square/build_receipt.json").write_text(
    json.dumps(receipt, indent=2) + "\n", encoding="utf-8", newline="\n")
