"""Read photographed Helsinki OBJ parts directly, preserving their source UVs."""
import posixpath

import numpy as np


def read_obj(archive, name, offset):
    positions, uvs, normals = [], [], []
    keys = {}
    vertices = []
    groups = {}
    material = None
    library = None
    for line in archive.read(name).decode('utf-8-sig').splitlines():
        fields = line.split()
        if not fields:
            continue
        kind = fields[0]
        if kind == 'v':
            positions.append([float(x) for x in fields[1:4]])
        elif kind == 'vt':
            uvs.append([float(fields[1]), 1-float(fields[2])])
        elif kind == 'vn':
            normals.append([float(x) for x in fields[1:4]])
        elif kind == 'mtllib':
            library = ' '.join(fields[1:])
        elif kind == 'usemtl':
            material = ' '.join(fields[1:])
        elif kind == 'f':
            polygon = []
            for value in fields[1:]:
                parts = value.split('/')
                index = tuple((int(v)-1 if int(v)>0 else [len(positions),len(uvs),len(normals)][i]+int(v))
                              if v else -1 for i,v in enumerate(parts))
                index += (-1,) * (3-len(index))
                if index not in keys:
                    keys[index] = len(keys)
                    vertices.append(index)
                polygon.append(keys[index])
            for i in range(1, len(polygon)-1):
                groups.setdefault(material, []).append([polygon[0], polygon[i], polygon[i+1]])
    # Municipal archives contain zero-byte parts over empty source cells.
    if not groups:
        return [], [], [], [], []
    if library is None:
        raise ValueError('Expected textured Helsinki OBJ triangles')
    folder = posixpath.dirname(name)
    mtl_name = posixpath.normpath(posixpath.join(folder, library))
    if not mtl_name.startswith(folder+'/'):
        raise ValueError('MTL leaves its source cell')
    definitions = {}
    current = None
    for line in archive.read(mtl_name).decode('utf-8-sig').splitlines():
        fields = line.split()
        if not fields:
            continue
        if fields[0] == 'newmtl':
            current = ' '.join(fields[1:])
            definitions[current] = {'color': [1, 1, 1, 1]}
        elif fields[0] == 'map_Kd':
            definitions[current]['photograph'] = ' '.join(fields[1:])
        elif fields[0] == 'Kd':
            definitions[current]['color'][:3] = [float(v) for v in fields[1:4]]
        elif fields[0] == 'd':
            definitions[current]['color'][3] = float(fields[1])
    indices = np.asarray(vertices)
    source = np.asarray(positions, float)[indices[:, 0]] - np.asarray(offset)
    source = source[:, [0, 2, 1]] * [1, 1, -1]
    attrs = {'POSITION': source.astype(np.float32)}
    if uvs:
        uv = np.zeros((len(indices), 2), np.float32)
        valid = indices[:, 1] >= 0
        uv[valid] = np.asarray(uvs, np.float32)[indices[valid, 1]]
        attrs['TEXCOORD_0'] = uv
    faces = np.concatenate([np.asarray(f, np.uint32) for f in groups.values()])
    if normals and np.all(indices[:, 2] >= 0):
        n = np.asarray(normals, np.float32)[indices[:, 2]][:, [0, 2, 1]] * [1, 1, -1]
    else:
        n = np.zeros_like(source)
        normal = np.cross(source[faces[:, 1]]-source[faces[:, 0]], source[faces[:, 2]]-source[faces[:, 0]])
        for corner in range(3):
            np.add.at(n, faces[:, corner], normal)
    n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
    attrs['NORMAL'] = n.astype(np.float32)
    surfaces, materials, images, textures = [], [], [], []
    for material, source_faces in groups.items():
        definition = definitions[material]
        pbr = {'metallicFactor': 0, 'roughnessFactor': 1, 'baseColorFactor': definition['color']}
        faces = np.asarray(source_faces, np.uint32)
        if 'photograph' in definition:
            photograph = definition['photograph']
            if photograph.startswith('-') or np.any(indices[faces.ravel(), 1] < 0):
                raise ValueError('Expected simple photograph mapping and complete face UVs')
            image_name = posixpath.normpath(posixpath.join(folder, photograph))
            if not image_name.startswith(folder+'/'):
                raise ValueError('Photograph leaves its source cell')
            image = archive.read(image_name)
            mime = 'image/png' if image.startswith(b'\x89PNG') else 'image/jpeg'
            pbr['baseColorTexture'] = {'index': len(textures)}
            textures.append({'source': len(images)})
            images.append((mime, image))
        index = len(materials)
        materials.append({'name': f'FrogExplorerMaterial_{index}', 'pbrMetallicRoughness': pbr})
        surfaces.append({'attrs': attrs, 'faces': faces, 'material': index})
    return surfaces, materials, images, textures, []
