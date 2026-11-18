"""Offscreen review of the authored Blender model; never captures a desktop."""
import argparse
from math import pi
from pathlib import Path
import sys

import bpy
from mathutils import Vector


def aim(obj, target):obj.rotation_euler = (Vector(target)-obj.location).to_track_quat('-Z', 'Y').to_euler()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--view', choices=['three_quarter', 'side', 'front', 'top'], default='three_quarter')
    parser.add_argument('--clip', default='Living_Idle')
    parser.add_argument('--frame', type=int, default=0)
    parser.add_argument('--clay', action='store_true')
    parser.add_argument('--frames', type=int, default=0, help='Render a numbered loop for a GIF')
    parser.add_argument('--size', type=int, default=960)
    parser.add_argument('--face', action='store_true', help='Frame the eyes and mouth for inspection')
    parser.add_argument('--feet', action='store_true', help='Frame the right front hand and wrist')
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    args.output = args.output.resolve()
    bpy.ops.wm.open_mainfile(filepath=str(args.input.resolve()))
    scene = bpy.context.scene
    arm = bpy.data.objects['Original_Red_Eye_Rig'];arm.animation_data.action = bpy.data.actions[args.clip]
    arm.animation_data.action_slot = bpy.data.actions[args.clip].slots[0]
    scene.frame_set(args.frame)
    bpy.ops.object.camera_add()
    camera = bpy.context.object;camera.name = 'Review camera';scene.camera = camera
    camera.data.type = 'ORTHO';camera.data.ortho_scale = .265
    positions = {'three_quarter':(.23, -.32, .17), 'side':(.32, -.035, .115),
                 'front':(0, -.35, .13), 'top':(0, -.025, .40)}
    camera.location = positions[args.view];aim(camera, (0, -.006, .042))
    if args.face:
        camera.data.ortho_scale = .135;aim(camera, (0, -.049, .060))
    if args.feet:
        camera.data.ortho_scale = .090;camera.location = (.18,-.20,.17);aim(camera, (.074,-.082,.010))
    for name, location, energy, size, color in [
        ('Large softbox', (.10, -.16, .25), 1.0, .18, (1.0, .95, .83)),
        ('Cool fill', (-.18, -.09, .14), .4, .20, (.77, .88, 1.0)),
        ('Edge softbox', (.04, .19, .19), 1.4, .13, (.92, 1.0, .89))]:
        bpy.ops.object.light_add(type='AREA', location=location);lamp = bpy.context.object
        lamp.name = name;lamp.data.energy = energy;lamp.data.shape = 'DISK';lamp.data.size = size;lamp.data.color = color;aim(lamp, (0, 0, .04))
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, 0));floor = bpy.context.object;floor.name = 'Review ground'
    mat = bpy.data.materials.new('Review neutral ground');mat.diffuse_color = (.055, .077, .071, 1);mat.use_nodes = True
    mat.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value = (.055, .077, .071, 1)
    mat.node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value = .82;floor.data.materials.append(mat)
    scene.world = bpy.data.worlds.new('Review studio');scene.world.use_nodes = True
    scene.world.node_tree.nodes.get('Background').inputs[0].default_value = (.17, .20, .19, 1)
    scene.world.node_tree.nodes.get('Background').inputs[1].default_value = .35
    if args.clay:
        clay = bpy.data.materials.new('Neutral shape review');clay.use_nodes = True
        shader = clay.node_tree.nodes.get('Principled BSDF');shader.inputs['Base Color'].default_value = (.44, .47, .43, 1);shader.inputs['Roughness'].default_value = .62
        scene.view_layers[0].material_override = clay
    scene.render.engine = 'CYCLES';scene.cycles.device = 'CPU';scene.cycles.samples = 24 if not args.frames else 12
    scene.cycles.use_denoising = True;scene.render.resolution_x = args.size;scene.render.resolution_y = int(args.size*.80);scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = 'AgX';scene.render.image_settings.file_format = 'PNG'
    args.output.parent.mkdir(parents=True, exist_ok=True)
    if args.frames:
        count = args.frames;duration = bpy.data.actions[args.clip].frame_range[1]
        for i in range(count):
            scene.frame_set(int(duration*i/count));scene.render.filepath = str(args.output.parent/(args.output.stem+f'_{i:03d}.png'));bpy.ops.render.render(write_still=True)
    else:
        scene.render.filepath = str(args.output.resolve());bpy.ops.render.render(write_still=True)


if __name__ == '__main__':main()
