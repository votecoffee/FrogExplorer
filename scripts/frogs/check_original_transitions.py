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
    assert len(parts)==69 and len(pads)==18

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
    for clip,start,end in [('Hop','Living_Idle','Living_Idle'),('Water_Entry','Living_Idle','Swim'),('Shore_Exit','Swim','Living_Idle')]:
        for phase,reference in [(0,start),(1,end)]:
            points = pose(clip,phase,parts)
            error = max(float(np.linalg.norm(points[name]-references[reference][name],axis=1).max()) for name in points)
            key = clip+(' start' if phase==0 else ' end')
            endpoints[key] = {'reference':reference+' frame 0','maximum_skin_displacement_m':error}
            if error>.00025:issues.append(key+': does not match its neighboring pose')
    contact = {};samples = 0
    for clip,windows in [('Hop',[(0,.06),(.96,1)]),('Water_Entry',[(0,.04)]),('Shore_Exit',[(.94,1)])]:
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
    report = {'endpoints':endpoints,'contact':contact,'contact_pose_samples':samples,'issues':issues,
              'scope':'All 69 evaluated meshes at six transition endpoints, 0.25 mm maximum neighbor-pose displacement. Eighteen evaluated toe pads in 44 planted-phase poses, 0.45 mm penetration and 0.9 mm gap tolerances. Authored metre scale; no world collision or continuous-time guarantee.'}
    args.report.parent.mkdir(parents=True,exist_ok=True)
    args.report.write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8',newline='\n')
    print('ORIGINAL_TRANSITION_CHECK '+json.dumps(report),flush=True)
    assert not issues,issues


if __name__=='__main__':main()
