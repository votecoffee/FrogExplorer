"""Offscreen Blender review of the prepared glTF geometry and source photographs.

blender --background --python scripts/worlds/preview_city_mesh.py --
    --place lyon_bellecour --pack game/assets/worlds/lyon_bellecour/tiles_city_...
    --output outputs/lyon.png
This renders file data; it does not capture an application window.
"""
import argparse
import json
from pathlib import Path
import sys

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--place', required=True)
parser.add_argument('--pack', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args(sys.argv[sys.argv.index('--')+1:])
config = json.loads((ROOT/'config/worlds'/(args.place+'.json')).read_bytes())
plan = json.loads((args.pack/'build_plan.json').read_bytes())
cx, cz = config['spawn_xy']
bpy.ops.wm.read_factory_settings(use_empty=True)
for tile in plan['tiles']:
    x, _, z = tile['origin']
    distance = Vector((x+plan['tile_size']/2-cx, z+plan['tile_size']/2-cz)).length
    if distance > 650:continue
    level = 0 if distance < 200 else (1 if distance < 400 else 2)
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=str((args.pack/tile['lods'][level]['scene']).with_suffix('.gltf').resolve()))
    for obj in set(bpy.context.scene.objects)-before:
        if obj.parent is None:obj.location += Vector((x, -z, 0))
# The checked arrival height is saved separately by the preparation command.
entry_path = ROOT/'data/world_sources'/args.place/'catalog_entry.json'
height = json.loads(entry_path.read_bytes())['spawn'][1] if entry_path.exists() else 0
target = Vector((cx+45, -cz+25, height+12))
bpy.ops.object.camera_add(location=target+Vector((-290, -350, 330)))
camera = bpy.context.object;camera.rotation_euler=(target-camera.location).to_track_quat('-Z', 'Y').to_euler()
camera.data.lens=48;camera.data.clip_end=12000;bpy.context.scene.camera=camera
bpy.ops.object.light_add(type='SUN', location=(0, 0, 1000));sun=bpy.context.object
sun.rotation_euler=(.35, -.5, -.5);sun.data.energy=2;sun.data.angle=.12
world=bpy.data.worlds.new('Daylight');world.use_nodes=True
world.node_tree.nodes['Background'].inputs['Color'].default_value=(.65,.77,.9,1)
world.node_tree.nodes['Background'].inputs['Strength'].default_value=.65;bpy.context.scene.world=world
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=24;scene.cycles.use_denoising=True
scene.render.resolution_x=1100;scene.render.resolution_y=760;scene.render.resolution_percentage=100
scene.view_settings.view_transform='Standard'
args.output.parent.mkdir(parents=True,exist_ok=True);scene.render.filepath=str(args.output.resolve())
bpy.ops.render.render(write_still=True)
print('CITY_PREVIEW_SAVED',args.output,flush=True)
