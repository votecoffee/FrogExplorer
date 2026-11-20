"""Measure transition endpoint continuity and planted toe-pad contact in Blender."""
import argparse
import json
from math import floor
from pathlib import Path
import sys

import bpy
import numpy as np


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input',type=Path,required=True)
    parser.add_argument('--report',type=Path,required=True)
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    bpy.ops.wm.open_mainfile(filepath=str(args.input.resolve()))
    arm = bpy.data.objects['Original_Red_Eye_Rig']
    parts = sorted([o for o in bpy.data.objects if o.type=='MESH'],key=lambda o:o.name)
    pads = [o for o in parts if 'adhesive disc' in o.name]
    required = {'Original continuous trunk and muzzle',
                'Articulated jaw and recessed oral floor', 'Gular breathing sac'}
    missing = required - {part.name for part in parts}
    assert not missing, f'Missing transition surfaces: {sorted(missing)}'
    assert len(pads)==18, f'Expected 18 adhesive discs, found {len(pads)}'

    def pose(clip,phase,objects):
        action = bpy.data.actions[clip];arm.animation_data.action = action;arm.animation_data.action_slot = action.slots[0]
        frame = float(action.frame_range[1])*phase
        bpy.context.scene.frame_set(floor(frame),subframe=frame-floor(frame))
        depsgraph = bpy.context.evaluated_depsgraph_get();result = {}
        for part in objects:
            obj = part.evaluated_get(depsgraph);mesh = obj.to_mesh()
            points = np.empty(len(mesh.vertices)*3,np.float32);mesh.vertices.foreach_get('co',points)
            matrix = np.asarray(obj.matrix_world)
            result[part.name] = points.reshape(-1,3)@matrix[:3,:3].T+matrix[:3,3]
            obj.to_mesh_clear()
        return result

    references = {clip:pose(clip,0,parts) for clip in ['Living_Idle','Swim']}
    endpoints = {};issues = []
    for clip,start,end in [('Big_Jump','Living_Idle','Living_Idle'),('Hop','Living_Idle','Living_Idle'),
                           ('Water_Entry','Living_Idle','Swim'),('Shore_Exit','Swim','Living_Idle')]:
        for phase,reference in [(0,start),(1,end)]:
            points = pose(clip,phase,parts)
            error = max(float(np.linalg.norm(points[name]-references[reference][name],axis=1).max()) for name in points)
            key = clip+(' start' if phase==0 else ' end')
            endpoints[key] = {'reference':reference+' frame 0','maximum_skin_displacement_m':error}
            if error>.00025:issues.append(key+': does not match its neighboring pose')
    contact = {};samples = 0
    for clip,windows in [('Big_Jump',[(0,.02),(.99,1)]),('Hop',[(0,.06),(.96,1)]),
                         ('Water_Entry',[(0,.04)]),('Shore_Exit',[(.94,1)])]:
        minimum = float('inf');gap = -float('inf');count = 0
        for first,last in windows:
            for phase in np.linspace(first,last,11):
                points = pose(clip,float(phase),pads);count += 1
                for values in points.values():
                    low = float(values[:,2].min());minimum = min(minimum,low);gap = max(gap,low)
        samples += count
        contact[clip] = {'sampled_contact_poses':count,'minimum_pad_height_m':minimum,'maximum_planted_pad_gap_m':gap}
        if minimum<-.00045:issues.append(clip+': planted pads enter the support plane')
        if gap>.0009:issues.append(clip+': planted pads leave the support plane')
    braces = {}
    rest = references['Living_Idle']
    for clip, key, phase, reach_limit, clearance in [
        ('Big_Jump', 'jump_brace', .85, .010, .004),
        ('Hop', 'hop_brace', .81, .006, .003),
    ]:
        brace = pose(clip, phase, pads)
        fore_reach = min(float(rest[name][:,1].mean()-values[:,1].mean())
                         for name,values in brace.items() if name.startswith('hand'))
        front_heights = [float(values[:,2].min()) for name,values in brace.items() if name.startswith('hand')]
        fore_gap = max(front_heights)
        hind_gap = min(float(values[:,2].min()) for name,values in brace.items() if name.startswith('foot'))
        if fore_reach<reach_limit:issues.append(f'{clip}: front pads do not reach ahead on descent')
        if min(front_heights)<-.00045 or fore_gap>.0009:issues.append(f'{clip}: reaching front pads miss the support plane')
        if hind_gap-fore_gap<clearance:issues.append(f'{clip}: hind pads do not clear the reaching front pads')
        braces[key] = {'phase':phase,'minimum_fore_pad_reach_m':fore_reach,
                       'maximum_fore_pad_gap_m':fore_gap,'minimum_hind_pad_gap_m':hind_gap}
    report = {'endpoints':endpoints,'contact':contact,'evaluated_meshes':len(parts),'contact_pose_samples':samples,
              **braces,
              'issues':issues,
              'scope':('All evaluated meshes at eight transition endpoints, 0.25 mm maximum neighbor-pose displacement. '
                       'Eighteen evaluated toe pads in 66 planted-phase poses, 0.45 mm penetration and 0.9 mm gap tolerances. '
                       'One descent pose per hop and big jump checks forefoot reach, front pad height and hind pad clearance. '
                       'Authored metre scale; no world collision or continuous-time guarantee.')}
    args.report.parent.mkdir(parents=True,exist_ok=True)
    args.report.write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8',newline='\n')
    print('ORIGINAL_TRANSITION_CHECK '+json.dumps(report),flush=True)
    assert not issues,issues


if __name__=='__main__':main()
