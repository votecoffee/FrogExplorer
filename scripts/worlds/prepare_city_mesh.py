"""Prepare optional large city photomesh packs with independent source LODs.

Examples: python scripts/worlds/prepare_city_mesh.py lyon_bellecour --register
          python scripts/worlds/prepare_city_mesh.py helsinki_city_center --register
Original downloads and intermediates remain local; registration occurs after bake.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import time
import zipfile
from concurrent.futures import ThreadPoolExecutor

import numpy as np
import requests

from city_data import local_frame, read_b3dm
from city_obj import read_obj
from city_pack import CityPack, ROOT
from city_sources import Cache, Tileset

PLACES = ['helsinki_city_center', 'lyon_bellecour', 'strasbourg_cathedral']


def prepare_credits(folder, config):
    """Retain the original logos required by the source's distribution notice."""
    for item in config.get('credit_images', []):
        target = folder/'credits'/item['name']
        if target.exists():continue
        response = requests.get(item['url'], timeout=(20, 60))
        response.raise_for_status()
        raw = response.content
        if hashlib.sha256(raw).hexdigest() != item['sha256']:
            raise ValueError('Source credit artwork changed: '+item['name'])
        if 'member' in item:
            with zipfile.ZipFile(io.BytesIO(raw)) as archive:raw = archive.read(item['member'])
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(raw)


def archive_file(folder, url, expected=None):
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / url.rsplit('/', 1)[1]
    if not path.exists():
        size = int(requests.head(url, timeout=30).headers['Content-Length'])
        part = path.with_suffix('.zip.part')
        for attempt in range(5):
            try:
                start = part.stat().st_size if part.exists() else 0
                with part.open('ab' if start else 'wb') as file:
                    while start < size:
                        end = min(size, start+8*1024*1024)-1
                        response = requests.get(url, headers={'Range': f'bytes={start}-{end}'}, timeout=(20, 60))
                        response.raise_for_status()
                        if response.status_code != 206 or len(response.content) != end-start+1:
                            raise IOError('Archive source did not honor byte ranges')
                        file.write(response.content)
                        file.flush()
                        start = end+1
                if part.stat().st_size != size:
                    raise IOError('Incomplete archive')
                part.replace(path)
                break
            except requests.RequestException:
                if attempt == 4:
                    raise
                time.sleep(attempt+1)
    with path.open('rb') as file:
        digest = hashlib.file_digest(file, 'sha256').hexdigest()
    if expected and digest != expected:
        raise ValueError('Reviewed Helsinki source archive changed: '+path.name)
    return path, {'url': url, 'bytes': path.stat().st_size, 'sha256': digest}


def prepare_helsinki(pack, config, cache):
    receipts = []
    for code in config['archives']:
        name = f'Helsinki3D_2017_OBJ_{code}x2.zip'
        path, receipt = archive_file(cache/'archives', config['archive_base']+name,
                                     config.get('archive_sha256', {}).get(code))
        receipts.append(receipt)
        with zipfile.ZipFile(path) as archive:
            metadata = archive.read('metadata.xml')
            if b'EPSG:3879+5773' not in metadata or b'25490000,6668000,0' not in metadata:
                raise ValueError('Source CRS or origin changed')
            for level, source_level in enumerate(config['source_levels']):
                names = sorted(n for n in archive.namelist() if n.endswith('.obj') and f'_L{source_level}' in n)
                if not names:
                    raise ValueError('Source archive lacks requested LOD')
                print('HELSINKI_LOD', code, source_level, len(names), 'parts', flush=True)
                for index, name in enumerate(names):
                    geometry = read_obj(archive, name, config['source_offset'])
                    key = hashlib.sha256((code+'/'+name).encode()).hexdigest()[:16]
                    pack.add(geometry, level, key)
                    if index % 100 == 0:
                        print('HELSINKI_PROGRESS', code, source_level, index, len(names), flush=True)
    return {'source_archives': receipts, 'source_levels': config['source_levels'],
            'source_coordinate_system': 'EPSG:3879+5773; declared source origin retained in config'}


def prepare_tiles(pack, config, cache_folder, maximum, plan_only):
    cache = Cache(cache_folder, config['allowed_prefix'], maximum)
    half_size = max(abs(v) for v in config['bounds'])
    source = Tileset(cache, config['tileset_url'], config['longitude'], config['latitude'], half_size)
    origin, rotation = local_frame(config['longitude'], config['latitude'])
    levels = []
    for error in config['source_errors']:
        level = source.frontier(error)
        levels.append(level)
        print('SOURCE_LEVEL', error, len(level), 'payloads;', len(source.documents), 'metadata documents', flush=True)
    index_path = cache_folder.parent/'selection.json'
    index_path.write_text(json.dumps({'config': config, 'levels': levels}, indent=2)+'\n', encoding='utf-8', newline='\n')
    if plan_only:
        return {'plan_only': True, 'selection': str(index_path)}
    with ThreadPoolExecutor(6) as pool:
        for level, entries in enumerate(levels):
            for start in range(0, len(entries), 24):
                batch = entries[start:start+24]
                # Deduplicate network work; transformed instances still retain
                # their own geometry below. Keep only a bounded batch in flight.
                paths = dict(zip(dict.fromkeys(e['url'] for e in batch),
                                 pool.map(cache.get, dict.fromkeys(e['url'] for e in batch))))
                for offset, entry in enumerate(batch):
                    geometry = read_b3dm(paths[entry['url']], origin, rotation, np.asarray(entry['transform']))
                    key = hashlib.sha256((entry['url']+str(entry['transform'])).encode()).hexdigest()[:16]
                    pack.add(geometry, level, key)
                print('CITY_SOURCE_PROGRESS', level, start+len(batch), len(entries), 'network bytes', cache.downloaded, flush=True)
    return {'source_payloads': list(cache.receipts.values()), 'source_errors': config['source_errors'],
            'coordinate_frame': {'ecef_origin': origin.tolist(), 'ecef_to_east_up_south': rotation.tolist()},
            'conversion': 'glTF 1/2 node hierarchy, y-up to z-up, RTC translation, tile hierarchy, then float64 local rebasing'}


def height_at(parts, point):
    highest = None
    for part in parts:
        triangle = part['attrs']['POSITION'][part['faces']].astype(float)
        a, b, c = triangle[:, 0], triangle[:, 1], triangle[:, 2]
        v0, v1 = b-a, c-a
        denominator = v0[:, 0]*v1[:, 2]-v1[:, 0]*v0[:, 2]
        valid = abs(denominator) > 1e-10
        denominator = np.where(valid, denominator, 1)
        dx, dz = point[0]-a[:, 0], point[1]-a[:, 2]
        u = (dx*v1[:, 2]-v1[:, 0]*dz)/denominator
        v = (v0[:, 0]*dz-dx*v0[:, 2])/denominator
        normal = np.cross(v0, v1)
        slope = abs(normal[:, 1])/np.maximum(np.linalg.norm(normal, axis=1), 1e-12)
        valid &= (u >= -1e-6) & (v >= -1e-6) & (u+v <= 1+1e-6) & (slope > .8)
        heights = a[:, 1]+u*v0[:, 1]+v*v1[:, 1]
        if valid.any():
            value = float(heights[valid].max())
            highest = value if highest is None else max(highest, value)
    return highest


def arrivals(pack, config):
    result = []
    for dx, dz in [(0, 0), (10, 0), (-10, 0), (0, 10), (0, -10), (20, 20), (-20, -20)]:
        point = np.asarray(config['spawn_xy'])+[dx, dz]
        cell = tuple(np.floor(point/pack.size).astype(int))
        local = point-np.asarray(cell)*pack.size
        height = height_at(pack.geometry(0, cell), local)
        if height is not None:
            result.append([float(point[0]), height+.04, float(point[1])])
    if not result:
        raise ValueError('No photographed walkable arrival surface near the requested anchor')
    return result


def catalog_entry(config, folder, spawns, plan):
    heights = []
    for path in folder.glob('authoring/l0_*.npz'):
        with np.load(path) as part:
            y = part['POSITION'][:, 1]
            heights.extend([float(y.min()), float(y.max())])
    anchor = config.get('anchor', {'longitude': config.get('longitude'), 'latitude': config.get('latitude'),
                                  'horizontal_crs': 'WGS84 ECEF -> local east/up/south', 'source_origin_height_m': 0,
                                  'height_reference': 'source ellipsoidal heights', 'source_year': 2023 if config['id'].startswith('lyon') else 2022})
    relative = folder.relative_to(ROOT/'game').as_posix()
    return {'id': config['id'], 'name': config['name'], 'category': 'city', 'provider': 'local_mesh',
            'status': 'ready', 'profiles': ['windows'], 'random_eligible': True,
            'distribution': 'optional_download', 'tile_manifest': 'res://'+relative+'/manifest.json',
            'scene': 'res://assets/worlds/'+config['id']+'/source_only.glb',
            'spawn': spawns[0], 'spawn_candidates': spawns[1:], 'heading_degrees': config['heading_degrees'],
            'bounds': [config['bounds'][0]+1, config['bounds'][1]+1, config['bounds'][2]-1, config['bounds'][3]-1],
            'vertical_bounds': [min(heights), max(heights)], 'size_range': [.25, 16], 'camera_far': 6500,
            'fog_density': .00012, 'attribution': config['attribution'], 'license': config['license'],
            'credit_logos': ['res://'+relative+'/credits/'+item['name'] for item in config.get('credit_images', [])],
            'source_url': config['source_urls'][0], 'source_urls': config['source_urls'], 'anchor': anchor,
            'description': config['description'], 'capabilities': ['walking', 'jumping', 'balloon', 'driving'],
            'quality': 'Original municipal photomesh LODs; source holes, photographed water/vegetation and aerial facade limitations remain. No authored swimming or climbable trees.',
            'qualification': {'windows': 'Prepared native multi-LOD pack; run city pack acceptance before use.',
                              'linux': 'untested', 'pi5': 'untested'}}


def register(entry):
    path = ROOT/'game/data/travel_places.json'
    text = path.read_text(encoding='utf-8')
    existing = next((p for p in json.loads(text)['places'] if p['id'] == entry['id']), None)
    if existing:
        if existing.get('distribution') != 'optional_download':
            raise ValueError('Preserving an existing bundled place: '+entry['id'])
        match = re.search(r'"id":\s*"'+re.escape(entry['id'])+r'"', text)
        start = text.rfind('{', 0, match.start())
        _, length = json.JSONDecoder().raw_decode(text[start:])
        replacement = json.dumps(entry, indent=2, ensure_ascii=False).replace('\n', '\n    ')
        path.write_text(text[:start]+replacement+text[start+length:], encoding='utf-8', newline='\n')
        return
    closing = text.rfind(']')
    prior = text[:closing].rstrip()
    text = prior+',\n'+''.join('    '+line+'\n' for line in json.dumps(entry, indent=2, ensure_ascii=False).splitlines())+'  '+text[closing:]
    path.write_text(text, encoding='utf-8', newline='\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('place', choices=PLACES)
    parser.add_argument('--register', action='store_true')
    parser.add_argument('--plan-only', action='store_true')
    parser.add_argument('--prepare-only', action='store_true')
    parser.add_argument('--prepared-folder', type=Path, help='Finish a retained prepared pack without rebuilding its geometry')
    parser.add_argument('--max-download-gb', type=float, default=8)
    args = parser.parse_args()
    config = json.loads((ROOT/'config/worlds'/(args.place+'.json')).read_bytes())
    cache = ROOT/'data/world_sources'/args.place
    cache.mkdir(parents=True, exist_ok=True)
    pipeline = b''.join((Path(__file__).parent/name).read_bytes() for name in
                        ['prepare_city_mesh.py', 'city_pack.py', 'city_sources.py', 'city_data.py', 'city_obj.py', 'tile_geometry.py', 'bake_city_tiles.gd'])
    digest = hashlib.sha256(pipeline+json.dumps(config, sort_keys=True).encode()).hexdigest()[:12]
    folder = ROOT/'game/assets/worlds'/args.place/('tiles_city_'+digest)
    if args.prepared_folder:
        folder = args.prepared_folder.resolve()
        if not folder.is_relative_to((ROOT/'game/assets/worlds'/args.place).resolve()):
            parser.error('Prepared folder must belong to this city under game/assets/worlds')
    if (folder/'manifest.json').exists():
        entry_path = folder/'catalog_entry.json'
        entry = json.loads((entry_path if entry_path.exists() else cache/'catalog_entry.json').read_bytes())
        if entry['tile_manifest'] != 'res://'+folder.relative_to(ROOT/'game').as_posix()+'/manifest.json':
            raise ValueError('The retained catalog entry belongs to a different completed pack')
        if args.register:
            register(entry)
        print('USING_COMPLETED_CITY', folder)
        return
    pack = CityPack(folder, config['tile_size'], config['bounds'], config['lod_distances'])
    if not args.plan_only:prepare_credits(folder, config)
    if (folder/'build_plan.json').exists() and ((folder/'catalog_entry.json').exists() or (cache/'catalog_entry.json').exists()):
        entry_path = folder/'catalog_entry.json'
        entry = json.loads((entry_path if entry_path.exists() else cache/'catalog_entry.json').read_bytes())
        expected = 'res://'+folder.relative_to(ROOT/'game').as_posix()+'/manifest.json'
        if entry['tile_manifest'] != expected:
            raise ValueError('The retained catalog entry belongs to a different prepared pack')
        if not args.prepare_only:
            pack.bake()
            if args.register:
                register(entry)
        print('FINISHED_PREPARED_CITY', args.place, folder, flush=True)
        return
    if config['source_type'] == 'helsinki_obj':
        if args.plan_only:
            print(json.dumps(config, indent=2));return
        provenance = prepare_helsinki(pack, config, cache)
    else:
        provenance = prepare_tiles(pack, config, cache/'http', int(args.max_download_gb*1e9), args.plan_only)
        if args.plan_only:
            return
    spawns = arrivals(pack, config)
    plan = pack.prepare(config, provenance)
    entry = catalog_entry(config, folder, spawns, plan)
    (cache/'catalog_entry.json').write_text(json.dumps(entry, indent=2)+'\n', encoding='utf-8', newline='\n')
    (folder/'catalog_entry.json').write_text(json.dumps(entry, indent=2)+'\n', encoding='utf-8', newline='\n')
    if not args.prepare_only:
        pack.bake()
        if args.register:
            register(entry)
    print('CITY_PREPARED', args.place, len(plan['tiles']), 'cells', folder, flush=True)


if __name__ == '__main__':
    main()
