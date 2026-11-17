"""Refine limb and cheek transitions in the locally supplied shape v4 frog.

Run in Blender with --input V4.blend --output DIRECTORY. The input is preserved;
only body vertex coordinates change. No model or texture data is included here.
"""
import argparse
import json
from pathlib import Path
import sys

import bpy
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from refine_red_eye_shape import fingerprint, gaussian, smooth


def preserve_orientation(source, coords, faces, edges):
    """Locally reduce displacement if a triangle folds over its old normal."""
    normals = np.cross(source[faces[:, 1]] - source[faces[:, 0]],
                       source[faces[:, 2]] - source[faces[:, 0]])
    area_squared = np.sum(normals ** 2, axis=1)
    valid = area_squared > 1e-20
    delta = coords - source
    factors = np.ones(len(coords))
    for iteration in range(60):
        current = np.cross(coords[faces[:, 1]] - coords[faces[:, 0]],
                           coords[faces[:, 2]] - coords[faces[:, 0]])
        folded = valid & (np.sum(current * normals, axis=1) < area_squared * .01)
        if not np.any(folded):
            return coords, iteration
        affected = np.unique(faces[folded])
        mask = np.zeros(len(coords), bool)
        mask[affected] = True
        neighbors = edges[np.any(mask[edges], axis=1)].ravel()
        factors[np.unique(neighbors)] *= .92
        factors[affected] *= .75
        coords = source + delta * factors[:, None]
    raise ValueError('Could not preserve triangle orientation')


def refine(body, arm, strength):
    source = np.asarray([v.co[:] for v in body.data.vertices])
    coords = source.copy()
    groups = {g.index: g.name for g in body.vertex_groups}
    weights = [{groups[g.group]: g.weight for g in v.groups}
               for v in body.data.vertices]
    eyes = [arm.data.bones['FX_eye.' + side].head_local.copy()
            for side in ['L', 'R']]
    segments = []
    joints = []
    for side in ['L', 'R']:
        for kind in ['upper_arm', 'forearm', 'thigh', 'shin']:
            prefix = 'DEF-' + kind + '.' + side
            start = arm.data.bones[prefix].head_local.copy()
            end = arm.data.bones[prefix + '.001'].tail_local.copy()
            segments.append((kind, prefix, np.asarray(start), np.asarray(end)))
        for proximal, distal, radius, amount in [
            ('upper_arm', 'forearm', .012, .30),
            ('thigh', 'shin', .014, .28),
            ('shin', 'foot', .010, .12),
        ]:
            name = 'DEF-' + distal + '.' + side
            center = np.asarray(arm.data.bones[name].head_local)
            names = ['DEF-' + kind + '.' + side for kind in [proximal, distal]]
            joints.append((center, names, radius, amount))

    polish = np.zeros(len(source))
    limb_count = cheek_count = mouth_count = 0
    for index, (point, w) in enumerate(zip(source, weights)):
        delta = np.zeros(3)
        for kind, prefix, start, end in segments:
            weight = w.get(prefix, 0) + w.get(prefix + '.001', 0)
            if weight == 0:
                continue
            axis = end - start
            t = float(np.clip((point - start) @ axis / (axis @ axis), 0, 1))
            center = start + axis * t
            radial = point - center
            # Retain a soft muscle belly and taper toward the tendons; avoid
            # repeating the earlier global narrowing of every limb and trunk.
            if kind == 'thigh':
                scale = .045 * gaussian(t, .35, .24) - .13 * smooth(.58, 1, t)
            elif kind == 'shin':
                scale = .025 * gaussian(t, .30, .20) - .08 * smooth(.62, 1, t)
            elif kind == 'upper_arm':
                scale = .035 * gaussian(t, .40, .25) - .09 * smooth(.66, 1, t)
            else:
                scale = .075 * gaussian(t, .32, .23) - .085 * smooth(.58, 1, t)
            delta += radial * (strength * weight * scale)
            polish[index] = max(polish[index], strength * weight * .45)
        for center, prefixes, radius, amount in joints:
            weight = sum(w.get(name + suffix, 0)
                         for name in prefixes for suffix in ['', '.001'])
            distance = np.linalg.norm(point - center)
            influence = gaussian(distance, 0, radius)
            # Pull the projecting joint cap inward, with a broad falloff so
            # that an elbow/knee does not read as a separate attached sphere.
            delta += (center - point) * strength * weight * amount * influence
            polish[index] = max(polish[index], strength * weight * influence)
        if np.linalg.norm(delta) > 1e-9:
            limb_count += 1

        head = w.get('FX_gape_lift', 0)
        jaw = w.get('FX_jaw', 0)
        trunk = sum(value for name, value in w.items() if name.startswith('DEF-spine'))
        clearance = min(np.linalg.norm(point - np.asarray(eye)) for eye in eyes)
        socket_guard = smooth(.013, .018, clearance)
        cheek = (gaussian(abs(point[0]), .020, .009)
                 * gaussian(point[1], -.024, .014)
                 * smooth(.080, .088, point[2]) * socket_guard)
        # Blend the broad rear cheek into the shoulder, keeping the orbital
        # contact ring and the lips/palate outside this mask.
        influence = strength * head * cheek
        delta[0] -= point[0] * .07 * influence
        delta[2] -= .0005 * influence
        if influence > .01:
            cheek_count += 1
        # Flatten the exaggerated upturn at the mouth corner. Move upper and
        # lower lip together, so this is a contour change rather than a gape.
        mouth = (gaussian(abs(point[0]), .0215, .007)
                 * gaussian(point[1], -.029, .012)
                 * gaussian(point[2], .080, .005))
        lip_influence = strength * (head + jaw) * mouth
        delta[2] -= .0015 * lip_influence
        if lip_influence > .01:
            mouth_count += 1
        shoulder = (gaussian(point[1], -.013, .018)
                    * gaussian(abs(point[0]), .017, .012)
                    * smooth(.077, .087, point[2]))
        polish[index] = max(polish[index], strength * .45
                            * (head * socket_guard + trunk) * shoulder)
        coords[index] += delta

    # Local, masked Taubin fairing removes angular transitions without
    # smoothing the skin detail across the whole animal or touching toe pads.
    edges = np.asarray([edge.vertices[:] for edge in body.data.edges], dtype=np.int64)
    counts = np.bincount(edges.ravel(), minlength=len(coords)).clip(1)
    for _ in range(8):
        for step in [.40, -.41]:
            neighbors = np.zeros_like(coords)
            np.add.at(neighbors, edges[:, 0], coords[edges[:, 1]])
            np.add.at(neighbors, edges[:, 1], coords[edges[:, 0]])
            coords += step * polish[:, None] * (neighbors / counts[:, None] - coords)

    faces = np.asarray([p.vertices[:] for p in body.data.polygons], dtype=np.int64)
    assert faces.shape[1] == 3, 'Expected the prepared triangulated body'
    coords, repairs = preserve_orientation(source, coords, faces, edges)
    for vertex, point in zip(body.data.vertices, coords):
        vertex.co = point
    body.data.update()
    if body.data.has_custom_normals:
        body.data.normals_split_custom_set([(0, 0, 0)] * len(body.data.loops))
    distances = np.linalg.norm(coords - source, axis=1)
    return {
        'body_vertices_changed': int(np.count_nonzero(distances > 1e-9)),
        'limb_profile_vertices': limb_count,
        'cheek_vertices': cheek_count,
        'mouth_corner_vertices': mouth_count,
        'masked_fairing_cycles': 8,
        'local_orientation_repair_steps': repairs,
        'maximum_displacement_m': float(distances.max()),
        'mean_displacement_m': float(distances.mean()),
        'strength': strength,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--strength', type=float, default=1)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    args.input = args.input.resolve()
    args.output = args.output.resolve()
    if not 0 <= args.strength <= 1:
        parser.error('strength must be between 0 and 1')
    output = args.output / 'Red_Eyed_Tree_Frog_Shape_v5'
    if args.input == output.with_suffix('.blend'):
        parser.error('Choose a different output directory to preserve the input')
    args.output.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.open_mainfile(filepath=str(args.input))
    scene = bpy.context.scene
    arm = next(o for o in scene.objects if o.type == 'ARMATURE')
    body = bpy.data.objects['Red_Eyed_Tree_FrogBody']
    assert len(arm.data.bones) == 111 and len(bpy.data.actions) == 28
    before = fingerprint(arm)
    metrics = refine(body, arm, args.strength)
    after = fingerprint(arm)
    for name in ['animation', 'skeleton', 'packed_images']:
        assert before[name] == after[name], name
    for name, old in before['meshes'].items():
        for key in old:
            if name == body.name and key == 'positions':
                continue
            assert old[key] == after['meshes'][name][key], (name, key)
    action = bpy.data.actions['Living_Idle']
    arm.animation_data.action = action
    arm.animation_data.action_slot = action.slots[0]
    scene.frame_set(0)
    bpy.context.view_layer.update()
    for track in arm.animation_data.nla_tracks:
        track.mute = True
    bpy.ops.object.select_all(action='DESELECT')
    for obj in scene.objects:
        if obj.type in ['MESH', 'ARMATURE']:
            obj.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.wm.save_as_mainfile(filepath=str(output.with_suffix('.blend')), compress=True)
    bpy.ops.export_scene.gltf(
        filepath=str(output.with_suffix('.glb')), export_format='GLB',
        use_selection=True, export_animations=True, export_animation_mode='ACTIONS',
        export_force_sampling=True, export_skins=True, export_influence_nb=4,
        export_image_format='AUTO', export_tangents=True,
        export_optimize_animation_size=True,
        export_optimize_animation_keep_anim_armature=False,
        export_cameras=False, export_lights=False,
    )
    report = {
        'revision': 'red-eyed shape v5 continuing v4', 'metrics': metrics,
        'animation_joint_rest_uv_weights_and_packed_images_unchanged': True,
        'eye_lid_tongue_geometry_unchanged': True,
        'baseline': before, 'candidate': after,
        'source_terms': 'Local derivative; original source terms still apply.',
    }
    (args.output / 'shape_validation.json').write_text(
        json.dumps(report, indent=2) + '\n', encoding='utf-8', newline='\n')
    print('RED_EYE_ANATOMY_SAVED', json.dumps(metrics), flush=True)


if __name__ == '__main__':
    main()
