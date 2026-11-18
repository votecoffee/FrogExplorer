"""Read the static glTF 1/2 photomesh payloads used by the reviewed city feeds.

Coordinates remain float64 until ECEF positions have been rebased to a local
east/up/south frame. This is an offline importer, not a general 3D Tiles client.
"""
import copy
import json
import math
from pathlib import Path
import struct

import numpy as np

from tile_geometry import COMPONENTS, WIDTHS

Y_TO_Z = np.array([[1, 0, 0, 0], [0, 0, -1, 0], [0, 1, 0, 0], [0, 0, 0, 1]], float)


def local_frame(longitude, latitude, height=0):
    lon, lat = np.radians([longitude, latitude])
    a = 6378137.0
    e2 = 6.6943799901413165e-3
    n = a / math.sqrt(1 - e2 * math.sin(lat) ** 2)
    origin = np.array([(n + height) * math.cos(lat) * math.cos(lon),
                       (n + height) * math.cos(lat) * math.sin(lon),
                       (n * (1 - e2) + height) * math.sin(lat)])
    rotation = np.array([[-math.sin(lon), math.cos(lon), 0],
                         [math.cos(lat)*math.cos(lon), math.cos(lat)*math.sin(lon), math.sin(lat)],
                         [math.sin(lat)*math.cos(lon), math.sin(lat)*math.sin(lon), -math.cos(lat)]])
    return origin, rotation


def node_matrix(node):
    if 'matrix' in node:
        return np.asarray(node['matrix'], float).reshape(4, 4).T
    x, y, z, w = node.get('rotation', [0, 0, 0, 1])
    rotation = np.array([[1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)],
                         [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)],
                         [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)]])
    result = np.eye(4)
    result[:3, :3] = rotation @ np.diag(node.get('scale', [1, 1, 1]))
    result[:3, 3] = node.get('translation', [0, 0, 0])
    return result


def glb_chunks(raw):
    magic, version, length = struct.unpack_from('<III', raw)
    if magic != 0x46546c67 or length > len(raw):
        raise ValueError('Invalid binary glTF header')
    if version == 1:
        size, kind = struct.unpack_from('<II', raw, 12)
        if kind != 0:
            raise ValueError('Expected glTF 1 JSON content')
        return json.loads(raw[20:20+size].rstrip(b'\0 ')), raw[20+size:length]
    if version != 2:
        raise ValueError('Only binary glTF 1 and 2 are supported')
    chunks = {}
    offset = 12
    while offset < length:
        size, kind = struct.unpack_from('<II', raw, offset)
        offset += 8
        if offset + size > length:
            raise ValueError('Truncated glTF chunk')
        chunks[kind] = raw[offset:offset+size]
        offset += size
    return json.loads(chunks[0x4e4f534a]), chunks[0x004e4942]


def read_b3dm(path, origin, rotation, tile_transform=None):
    raw = Path(path).read_bytes()
    magic, version, length, fj, fb, bj, bb = struct.unpack_from('<4s6I', raw)
    if magic != b'b3dm' or version != 1 or length != len(raw):
        raise ValueError('Expected a complete 28-byte-header b3dm 1.0 tile')
    feature = json.loads(raw[28:28+fj].rstrip(b'\0 ')) if fj else {}
    if isinstance(feature.get('RTC_CENTER'), dict):
        start = 28 + fj + feature['RTC_CENTER']['byteOffset']
        feature['RTC_CENTER'] = list(struct.unpack_from('<3f', raw, start))
    doc, binary = glb_chunks(raw[28+fj+fb+bj+bb:])
    return read_document(doc, binary, origin, rotation, tile_transform, feature.get('RTC_CENTER'))


def read_document(doc, binary, origin, rotation, tile_transform=None, rtc=None):
    legacy = float(doc['asset']['version']) < 2
    if doc.get('skins') or doc.get('animations'):
        raise ValueError('Only static photomesh payloads are supported')
    if set(doc.get('extensionsRequired', [])) - {'KHR_materials_unlit'}:
        raise ValueError('Required compression/extensions need an explicit decoder')
    def table(name):
        return doc.get(name, {} if legacy else [])
    def values(name):
        data = table(name)
        return list(data.values()) if legacy else data
    def ref(name, key):
        return table(name)[key]
    def accessor(key):
        item = ref('accessors', key)
        if 'sparse' in item:
            raise ValueError('Sparse accessors are unsupported')
        view = ref('bufferViews', item['bufferView'])
        dtype = COMPONENTS[item['componentType']]
        width = WIDTHS[item['type']]
        stride = item.get('byteStride', view.get('byteStride', width*dtype.itemsize))
        offset = view.get('byteOffset', 0) + item.get('byteOffset', 0)
        array = np.ndarray((item['count'], width), dtype=dtype, buffer=binary,
                           offset=offset, strides=(stride, dtype.itemsize)).copy()
        if item.get('normalized'):
            array = np.maximum(array.astype(float) / np.iinfo(dtype).max, -1)
        return array
    images = []
    for image in values('images'):
        image = image.get('extensions', {}).get('KHR_binary_glTF', image)
        view = ref('bufferViews', image['bufferView'])
        start = view.get('byteOffset', 0)
        mime = image.get('mimeType')
        if mime not in ['image/png', 'image/jpeg']:
            raise ValueError('Expected embedded JPEG/PNG photograph')
        images.append((mime, binary[start:start+view['byteLength']]))
    image_keys = list(table('images')) if legacy else list(range(len(images)))
    sampler_keys = list(table('samplers')) if legacy else list(range(len(values('samplers'))))
    textures = []
    for texture in values('textures'):
        value = {'source': image_keys.index(texture['source'])}
        if 'sampler' in texture:
            value['sampler'] = sampler_keys.index(texture['sampler'])
        textures.append(value)
    material_keys = list(table('materials')) if legacy else list(range(len(values('materials'))))
    texture_keys = list(table('textures')) if legacy else list(range(len(textures)))
    materials = []
    for index, material in enumerate(values('materials')):
        if legacy:
            diffuse = material.get('values', {}).get('diffuse', [1, 1, 1, 1])
            pbr = {'metallicFactor': 0, 'roughnessFactor': 1}
            if isinstance(diffuse, str):
                pbr['baseColorTexture'] = {'index': texture_keys.index(diffuse)}
            else:
                pbr['baseColorFactor'] = diffuse
            material = {'pbrMetallicRoughness': pbr}
        else:
            material = copy.deepcopy(material)
        material['name'] = f'FrogExplorerMaterial_{index:05d}'
        materials.append(material)
    center = doc.get('extensions', {}).get('CESIUM_RTC', {}).get('center')
    if rtc is not None and center is not None:
        raise ValueError('Ambiguous duplicate RTC centers')
    translation = np.eye(4)
    translation[:3, 3] = rtc if rtc is not None else (center or [0, 0, 0])
    world = (np.eye(4) if tile_transform is None else tile_transform) @ translation @ Y_TO_Z
    surfaces = []
    def visit(key, parent):
        node = ref('nodes', key)
        transform = parent @ node_matrix(node)
        meshes = node.get('meshes', []) if legacy else ([node['mesh']] if 'mesh' in node else [])
        for mesh_key in meshes:
            for primitive in ref('meshes', mesh_key)['primitives']:
                if primitive.get('mode', 4) != 4 or primitive.get('targets') or primitive.get('extensions'):
                    raise ValueError('Expected uncompressed static triangles')
                if set(primitive['attributes']) - {'POSITION', 'NORMAL', 'TANGENT', 'TEXCOORD_0', 'COLOR_0', '_BATCHID'}:
                    raise ValueError('Unsupported photomesh vertex attributes')
                attrs = {name: accessor(value) for name, value in primitive['attributes'].items()
                         if name in ['POSITION', 'NORMAL', 'TANGENT', 'TEXCOORD_0', 'COLOR_0']}
                positions = attrs['POSITION'].astype(float)
                positions = positions @ transform[:3, :3].T + transform[:3, 3]
                attrs['POSITION'] = ((positions - origin) @ rotation.T).astype(np.float32)
                linear = rotation @ transform[:3, :3]
                for name in ['NORMAL', 'TANGENT']:
                    if name in attrs:
                        normals = attrs[name][:, :3] @ (linear.T if name == 'TANGENT' else np.linalg.inv(linear))
                        normals /= np.maximum(np.linalg.norm(normals, axis=1, keepdims=True), 1e-12)
                        attrs[name] = attrs[name].astype(np.float32)
                        attrs[name][:, :3] = normals
                        if name == 'TANGENT':
                            attrs[name][:, 3] *= np.sign(np.linalg.det(linear))
                if not all(np.isfinite(value).all() for value in attrs.values()):
                    raise ValueError('Nonfinite vertex data')
                faces = (accessor(primitive['indices']).reshape(-1, 3).astype(np.uint32)
                         if 'indices' in primitive else np.arange(len(positions), dtype=np.uint32).reshape(-1, 3))
                if np.linalg.det(linear) < 0:
                    faces = faces[:, [0, 2, 1]]
                material = material_keys.index(primitive['material'])
                surfaces.append({'attrs': {k: v.astype(np.float32) for k, v in attrs.items()},
                                 'faces': faces, 'material': material})
        for child in node.get('children', []):
            visit(child, transform)
    scene = doc.get('scene', next(iter(table('scenes'))) if legacy else 0)
    for key in ref('scenes', scene)['nodes']:
        visit(key, world)
    if not surfaces:
        raise ValueError('No triangle geometry')
    return surfaces, materials, images, textures, values('samplers')
