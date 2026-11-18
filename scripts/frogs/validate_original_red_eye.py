"""Check the authored GLB's geometry, weights, embedded data and clip contract."""
import argparse
import json
from pathlib import Path
import struct

import numpy as np

CLIPS = {'Big_Jump', 'Breakdance', 'Catch_Fly', 'Catch_Fly_Swallow', 'Climb',
         'Croak', 'Death', 'Disco_Frog', 'Face_Wipe', 'Foot_Wave', 'Hit', 'Hop',
         'Idle', 'Land', 'Living_Idle', 'Puff_Up', 'Shore_Exit', 'Slow_Walk',
         'Splat', 'Swallow', 'Swamp_Shuffle', 'Swim', 'Toe_Tap', 'Tongue_Snap',
         'Turn_Left', 'Turn_Right', 'Victory_Ribbit', 'Water_Entry'}


def validate(path):
    raw = Path(path).read_bytes()
    magic, version, size = struct.unpack_from('<4sII', raw)
    assert (magic, version, size) == (b'glTF', 2, len(raw))
    length, kind = struct.unpack_from('<I4s', raw, 12);assert kind == b'JSON'
    doc = json.loads(raw[20:20+length])
    length2, kind = struct.unpack_from('<I4s', raw, 20+length);assert kind == b'BIN\x00'
    binary = raw[28+length:28+length+length2]
    assert all('uri' not in b for b in doc['buffers'])
    assert all('bufferView' in i and 'uri' not in i for i in doc['images'])
    assert len(doc['skins']) == 1
    joints = doc['skins'][0]['joints']
    names = {doc['nodes'][index]['name'] for index in joints}
    assert {'root', 'DEF-spine.003', 'Head', 'FX-jaw', 'Throat', 'Tongue'} <= names
    animations = doc['animations'];assert {a['name'] for a in animations} == CLIPS

    def array(index):
        entry = doc['accessors'][index];assert 'sparse' not in entry
        view = doc['bufferViews'][entry['bufferView']]
        dtype = np.dtype({5120:'i1', 5121:'u1', 5122:'<i2', 5123:'<u2', 5125:'<u4', 5126:'<f4'}[entry['componentType']])
        components = {'SCALAR':1, 'VEC2':2, 'VEC3':3, 'VEC4':4, 'MAT4':16}[entry['type']]
        offset = view.get('byteOffset', 0)+entry.get('byteOffset', 0)
        stride = view.get('byteStride', dtype.itemsize*components)
        result = np.ndarray((entry['count'], components), dtype=dtype, buffer=binary,
                            offset=offset, strides=(stride, dtype.itemsize)).copy()
        assert np.isfinite(result).all()
        if entry.get('normalized') and dtype.kind in 'iu':result = result.astype(float)/np.iinfo(dtype).max
        return result

    vertices = triangles = 0
    for mesh in doc['meshes']:
        for primitive in mesh['primitives']:
            attrs = primitive['attributes']
            assert {'POSITION', 'NORMAL', 'TEXCOORD_0', 'JOINTS_0', 'WEIGHTS_0'} <= attrs.keys(), mesh['name']
            position = array(attrs['POSITION']);normal = array(attrs['NORMAL'])
            weight = array(attrs['WEIGHTS_0']);joint = array(attrs['JOINTS_0'])
            assert np.allclose(weight.sum(axis=1), 1, atol=1e-5), mesh['name']
            assert (weight >= 0).all() and (joint < len(joints)).all()
            assert np.allclose(np.linalg.norm(normal, axis=1), 1, atol=1e-3)
            faces = array(primitive['indices']).reshape(-1, 3)
            p = position[faces]
            areas = np.linalg.norm(np.cross(p[:, 1]-p[:, 0], p[:, 2]-p[:, 0]), axis=1)
            assert (areas > 1e-16).all(), 'Degenerate triangles: '+mesh['name']
            vertices += len(position);triangles += len(faces)
    for animation in animations:
        for sampler in animation['samplers']:
            times = array(sampler['input']).ravel()
            assert len(times)>1 and (np.diff(times)>0).all()
            array(sampler['output'])
    return {'meshes':len(doc['meshes']), 'bones':len(joints), 'clips':len(animations),
            'vertices_with_uv_seams':vertices, 'triangles':triangles,
            'embedded_images':len(doc['images']), 'bytes':len(raw),
            'checks':'Embedded dependencies, complete 28-clip contract, finite arrays, nondegenerate triangles, unit normals, normalized weights and valid joints'}


def main():
    parser = argparse.ArgumentParser(description=__doc__);parser.add_argument('glb', type=Path)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args();result = validate(args.glb)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8', newline='\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':main()
