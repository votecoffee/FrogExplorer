"""Build a wholly authored, redistributable red-eyed tree frog with Blender.

blender --background --python scripts/frogs/build_original_red_eye.py --
  --output .local/red_eye_original/candidate
No existing frog files are opened. Output is never installed automatically.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys

import bpy
import bmesh

sys.path.insert(0, str(Path(__file__).resolve().parent))
from original_red_eye_geometry import Frog
from original_red_eye_motion import animate, CLIPS


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    output = args.output.resolve();output.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    frog = Frog().build()
    for obj in frog.meshes:
        bm = bmesh.new();bm.from_mesh(obj.data)
        bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-8)
        bmesh.ops.dissolve_degenerate(bm, edges=list(bm.edges), dist=1e-10)
        bmesh.ops.triangulate(bm, faces=[face for face in bm.faces if len(face.verts)>4])
        # Closed components face out; explicitly oriented open ocular caps retain
        # the analytic winding. There are no negative object scales.
        if 'corneal' not in obj.name and 'eyelid' not in obj.name:
            bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        bm.to_mesh(obj.data);bm.free();obj.data.update()
    # Pad undersides meet the gameplay floor at rest; the physical capsule is
    # owned by Godot and no world/root travel is baked into the motion clips.
    frog.arm.location.z = -.00335
    animate(frog)
    blend = output/'Original_Red_Eyed_Tree_Frog.blend'
    bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    glb = output/'red_eye_original.glb'
    bpy.ops.export_scene.gltf(filepath=str(glb), export_format='GLB',
        export_animations=True, export_animation_mode='ACTIONS',
        export_force_sampling=True, export_skins=True, export_influence_nb=4,
        export_tangents=True, export_image_format='AUTO',
        export_optimize_animation_size=True, export_cameras=False,
        export_lights=False, export_extras=True)
    report = {'model':'FrogExplorer original red-eyed tree frog', 'license':'MIT',
              'revision':frog.arm['model_revision'],
              'input_assets':[], 'geometry':'Original analytic lofts and surfaces',
              'textures':'Original deterministic painted color, normal, roughness and iris pixels',
              'rig':'Original bone layout and skin weights',
              'animations':'Original analytic motion keys, no retargeted actions',
              'clips':CLIPS, 'bones':len(frog.arm.data.bones),
              'mesh_objects':len(frog.meshes),
              'vertices':sum(len(o.data.vertices) for o in frog.meshes),
              'triangles':sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in frog.meshes),
              'images':len(bpy.data.images), 'glb_bytes':glb.stat().st_size,
              'glb_sha256':hashlib.sha256(glb.read_bytes()).hexdigest(),
              'build_sources':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in
                  [Path(__file__), Path(__file__).with_name('original_red_eye_geometry.py'),
                   Path(__file__).with_name('original_red_eye_motion.py')]}}
    (output/'build_receipt.json').write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8', newline='\n')
    print('ORIGINAL_FROG_BUILD '+json.dumps(report), flush=True)


if __name__ == '__main__':main()
