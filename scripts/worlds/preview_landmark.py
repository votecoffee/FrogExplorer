"""Render the exported GLB itself, independently of the source Blender scene."""
import importlib.util
from pathlib import Path
import sys
import bpy

worker=Path(__file__).with_name("build_landmark.py")
spec=importlib.util.spec_from_file_location("landmark_worker",worker)
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
place_id=sys.argv[sys.argv.index("--")+1]
config=module.ROOT/"data/world_sources"/place_id/"build_config.json"
settings=module.json.loads(config.read_bytes().decode("utf-8")) if config.exists() else {}
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(module.ROOT/"game/assets/worlds"/place_id/settings.get("scene_name","landmark.glb")))
print("EXPORTED_IMAGES",[(im.name,list(im.size),bool(im.packed_file),im.filepath) for im in bpy.data.images])
output=Path(settings.get("output_dir",module.ROOT/"outputs/Landmarks_20261117"))
if not output.is_absolute():output=module.ROOT/output
module.render([o for o in bpy.context.scene.objects if o.type=="MESH"],output/(place_id+"_ready.png"))
