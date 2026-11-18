"""Assemble independent source detail levels into bounded native Godot tiles."""
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import sys

import numpy as np

from tile_geometry import partition, write_gltf

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'scripts'))
from engine import resolve_engine


class CityPack:
    def __init__(self, folder, size, bounds, distances):
        self.folder = Path(folder)
        self.size = size
        self.bounds = bounds
        self.distances = distances
        self.work = self.folder/'authoring'
        self.work.mkdir(parents=True, exist_ok=True)
        (self.work/'.gdignore').touch()
        (self.folder/'shared').mkdir(exist_ok=True)
        self.materials = []
        self.images = []
        self.textures = []
        self.samplers = []
        self.parts = {}
        self.source_triangles = [0] * (len(distances)+1)

    def add(self, geometry, level, key):
        surfaces, materials, images, textures, samplers = geometry
        material_offset = len(self.materials)
        image_offset = len(self.images)
        texture_offset = len(self.textures)
        sampler_offset = len(self.samplers)
        for mime, data in images:
            digest = hashlib.sha256(data).hexdigest()
            name = digest + ('.jpg' if mime == 'image/jpeg' else '.png')
            target = self.folder/'shared'/name
            if not target.exists():
                target.write_bytes(data)
            self.images.append(name)
        for original in textures:
            texture = copy.deepcopy(original)
            texture['source'] += image_offset
            if 'sampler' in texture:
                texture['sampler'] += sampler_offset
            self.textures.append(texture)
        self.samplers.extend(copy.deepcopy(samplers))
        def reindex(value):
            if isinstance(value, dict):
                for name, child in value.items():
                    if name.endswith('Texture') and isinstance(child, dict) and 'index' in child:
                        child['index'] += texture_offset
                    else:
                        reindex(child)
            elif isinstance(value, list):
                for child in value:
                    reindex(child)
        for index, original in enumerate(materials):
            material = copy.deepcopy(original)
            reindex(material)
            material['name'] = f'FrogExplorerMaterial_{material_offset+index:06d}'
            self.materials.append(material)
        for primitive, surface in enumerate(surfaces):
            attrs = surface['attrs']
            faces = surface['faces']
            points = attrs['POSITION'][faces]
            lo, hi = points.min(axis=1), points.max(axis=1)
            a, b, c, d = self.bounds
            faces = faces[(hi[:, 0] >= a) & (lo[:, 0] <= c)
                          & (hi[:, 2] >= b) & (lo[:, 2] <= d)]
            self.source_triangles[level] += len(faces)
            if not len(faces):
                continue
            for cell, attributes, triangles in partition(attrs, faces, self.size):
                cell = tuple(int(v) for v in cell)
                if not (a <= cell[0]*self.size < c and b <= cell[1]*self.size < d):
                    continue
                path = self.work/f'l{level}_x{cell[0]}_z{cell[1]}_{key}_{primitive}.npz'
                np.savez(path, faces=triangles, **attributes)
                self.parts.setdefault((level, cell), []).append((path, material_offset+surface['material']))

    def geometry(self, level, cell):
        parts = []
        for path, material in self.parts.get((level, cell), []):
            with np.load(path) as data:
                parts.append({'attrs': {k: data[k] for k in data.files if k != 'faces'},
                              'faces': data['faces'], 'material': material})
        return parts

    def prepare(self, config, provenance):
        tiles = []
        overview_triangles = 0
        for cell in sorted({cell for level, cell in self.parts if level == 0}):
            ident = f'x{cell[0]}_z{cell[1]}'
            lods = []
            fine_materials = []
            for level in range(len(self.distances)):
                parts = self.geometry(level, cell)
                if not parts:
                    # Source coverage can differ slightly between levels. Retain
                    # actual finest geometry instead of leaving a visual hole.
                    parts = self.geometry(0, cell)
                name = f'{ident}_lod{level}'
                write_gltf(self.folder/'detail'/(name+'.gltf'), parts, self.materials,
                           self.images, self.textures, self.samplers)
                count = sum(len(p['faces']) for p in parts)
                lods.append({'scene': 'detail/'+name+'.tscn', 'triangles': count,
                             'collision': level == 0})
                if level == 0:
                    fine_materials = sorted({p['material'] for p in parts})
            far = self.geometry(len(self.distances), cell)
            if not far:
                far = self.geometry(len(self.distances)-1, cell) or self.geometry(0, cell)
            write_gltf(self.folder/'overview'/(ident+'.gltf'), far, self.materials,
                       self.images, self.textures, self.samplers)
            overview_triangles += sum(len(p['faces']) for p in far)
            tiles.append({'id': ident, 'cell': list(cell), 'origin': [cell[0]*self.size, 0, cell[1]*self.size],
                          'scene': lods[0]['scene'], 'triangles': lods[0]['triangles'],
                          'lods': lods, 'overview': True, 'materials': fine_materials})
        if not tiles:
            raise ValueError('No finest-level cells were built')
        plan = {'version': 1, 'tile_size': self.size, 'bounds': self.bounds,
                'detail_radius': self.distances[-1], 'lod_distances': self.distances,
                'overview_scene': 'overview.tscn', 'overview_triangles': overview_triangles,
                'source_triangles_by_lod': self.source_triangles, 'tiles': tiles,
                'attribution': config['attribution'], 'license': config['license'],
                'source_urls': config['source_urls'], 'provenance': provenance,
                'geometry_policy': 'Original independent source LODs; no global triangle decimation. Exact grid clipping.'}
        (self.folder/'build_plan.json').write_text(json.dumps(plan, indent=2)+'\n', encoding='utf-8', newline='\n')
        return plan

    def bake(self, engine=None):
        engine = engine or resolve_engine(ROOT)
        relative = self.folder.relative_to(ROOT/'game').as_posix()
        log_folder = ROOT/'.local/world_upgrade'
        log_folder.mkdir(parents=True, exist_ok=True)
        for name, args in [('import', ['--editor', '--import']),
                           ('bake', ['--script', 'res://../scripts/worlds/bake_city_tiles.gd', '--', '--pack=res://'+relative])]:
            with (log_folder/(self.folder.parent.name+'_'+name+'.log')).open('wb') as log:
                result = subprocess.run([str(engine), '--headless', '--path', str(ROOT/'game'), *args], stdout=log, stderr=subprocess.STDOUT)
            text = (log_folder/(self.folder.parent.name+'_'+name+'.log')).read_text(encoding='utf-8', errors='replace')
            if result.returncode or any(token in text for token in ['SCRIPT ERROR:', 'ERROR:', 'Parse Error']):
                raise RuntimeError('Godot city preparation failed: '+text[-2500:])
        plan = json.loads((self.folder/'build_plan.json').read_bytes())
        files = {}
        for path in sorted(self.folder.rglob('*')):
            if path.is_file() and 'authoring' not in path.parts and path.suffix in ['.tscn', '.res', '.tres', '.png', '.jpg', '.jpeg', '.svg']:
                with path.open('rb') as file:
                    files[path.relative_to(self.folder).as_posix()] = hashlib.file_digest(file, 'sha256').hexdigest()
        plan['files'] = files
        (self.folder/'manifest.json').write_text(json.dumps(plan, indent=2)+'\n', encoding='utf-8', newline='\n')
        return plan
