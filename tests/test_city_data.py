"""Coordinate, appearance and source-selection invariants for municipal maps."""
import io
import json
import struct
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

try:
    import numpy as np
    import requests
except ImportError:
    raise unittest.SkipTest('Optional city preparation tests require numpy and requests')
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'scripts/worlds'))
from city_data import Y_TO_Z, local_frame, read_document, read_b3dm
from city_obj import read_obj
from city_pack import CityPack
from city_sources import Tileset
from tile_geometry import write_gltf
import prepare_city_mesh


class CityDataTests(unittest.TestCase):
    def fixture(self):
        origin, rotation = local_frame(4.8338, 45.75784)
        local = np.array([[0, 0, 0], [.01, 0, 0], [0, 0, -.02]])
        positions = (local @ rotation).astype('<f4')
        normals = np.tile(rotation[1], (3, 1)).astype('<f4')
        binary = positions.tobytes()+normals.tobytes()
        doc = {'asset': {'version': '2.0'}, 'scene': 0, 'scenes': [{'nodes': [0]}],
               'nodes': [{'matrix': np.linalg.inv(Y_TO_Z).T.ravel().tolist(), 'mesh': 0}],
               'meshes': [{'primitives': [{'attributes': {'POSITION': 0, 'NORMAL': 1}, 'material': 0}]}],
               'materials': [{'pbrMetallicRoughness': {'baseColorFactor': [.2, .3, .4, 1]}}],
               'bufferViews': [{'byteOffset': 0, 'byteLength': 36}, {'byteOffset': 36, 'byteLength': 36}],
               'accessors': [{'bufferView': i, 'count': 3, 'componentType': 5126, 'type': 'VEC3'} for i in range(2)]}
        return doc, binary, origin, rotation, local

    def test_centimetre_offsets_survive_ecef_rebasing_and_axis_changes(self):
        doc, binary, origin, rotation, local = self.fixture()
        result = read_document(doc, binary, origin, rotation, rtc=origin)
        np.testing.assert_allclose(result[0][0]['attrs']['POSITION'], local, atol=1e-7)
        np.testing.assert_allclose(result[0][0]['attrs']['NORMAL'], [[0, 1, 0]]*3, atol=1e-7)
        self.assertEqual(result[1][0]['pbrMetallicRoughness']['baseColorFactor'], [.2, .3, .4, 1])

    def test_parent_and_node_transforms_are_applied_before_rebasing(self):
        doc, binary, origin, rotation, local = self.fixture()
        transform = np.eye(4)
        transform[:3, 3] = np.array([3, 2, -4]) @ rotation
        result = read_document(doc, binary, origin, rotation, transform, origin)
        np.testing.assert_allclose(result[0][0]['attrs']['POSITION'], local+[3, 2, -4], atol=1e-6)

    def test_legacy_b3dm_keeps_rtc_positions_and_embedded_photograph(self):
        doc, binary, origin, rotation, local = self.fixture()
        doc['asset']['version']='1.0'
        doc['nodes'][0]['meshes']=['mesh'];del doc['nodes'][0]['mesh']
        doc['nodes']={'node':doc['nodes'][0]}
        doc['scenes']={'scene':{'nodes':['node']}};doc['scene']='scene'
        primitive=doc['meshes'][0]['primitives'][0]
        primitive['attributes']={k:str(v) for k,v in primitive['attributes'].items()};primitive['material']='material'
        doc['meshes']={'mesh':{'primitives':[primitive]}}
        doc['accessors']={str(i):dict(a,bufferView=str(a['bufferView'])) for i,a in enumerate(doc['accessors'])}
        doc['bufferViews']={str(i):v for i,v in enumerate(doc['bufferViews'])}
        photo=b'JPEG photograph fixture';doc['bufferViews']['photo']={'byteOffset':len(binary),'byteLength':len(photo)}
        doc['images']={'image':{'extensions':{'KHR_binary_glTF':{'bufferView':'photo','mimeType':'image/jpeg'}}}}
        doc['textures']={'texture':{'source':'image'}}
        doc['materials']={'material':{'values':{'diffuse':'texture'}}}
        doc['extensions']={'CESIUM_RTC':{'center':origin.tolist()}}
        binary+=photo;header=json.dumps(doc).encode();header+=b' '*(-len(header)%4)
        glb=struct.pack('<5I',0x46546c67,1,20+len(header)+len(binary),len(header),0)+header+binary
        wrapped=struct.pack('<4s6I',b'b3dm',1,28+len(glb),0,0,0,0)+glb
        with tempfile.TemporaryDirectory() as temporary:
            path=Path(temporary)/'legacy.b3dm';path.write_bytes(wrapped)
            result=read_b3dm(path,origin,rotation)
        np.testing.assert_allclose(result[0][0]['attrs']['POSITION'],local,atol=1e-7)
        self.assertEqual(result[2],[('image/jpeg',photo)])
        self.assertEqual(result[1][0]['pbrMetallicRoughness']['baseColorTexture'],{'index':0})

    def test_unknown_required_geometry_extension_is_refused(self):
        doc, binary, origin, rotation, _ = self.fixture()
        doc['extensionsRequired'] = ['KHR_draco_mesh_compression']
        with self.assertRaisesRegex(ValueError, 'decoder'):
            read_document(doc, binary, origin, rotation, rtc=origin)

    def test_unlit_source_material_survives_export(self):
        doc, binary, origin, rotation, _ = self.fixture()
        doc['extensionsRequired'] = ['KHR_materials_unlit']
        doc['materials'][0]['extensions'] = {'KHR_materials_unlit': {}}
        geometry = read_document(doc, binary, origin, rotation, rtc=origin)
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary)/'tile.gltf'
            write_gltf(path, geometry[0], geometry[1], [], [], [])
            written = json.loads(path.read_bytes())
            self.assertEqual(written['extensionsUsed'], ['KHR_materials_unlit'])
            self.assertIn('KHR_materials_unlit', written['materials'][0]['extensions'])

    def test_obj_keeps_photographed_and_untextured_faces_with_uv_orientation(self):
        raw = io.BytesIO()
        with zipfile.ZipFile(raw, 'w') as archive:
            archive.writestr('cell/p.obj', 'mtllib p.mtl\nv 100 200 3\nv 101 200 3\nv 100 201 3\nvt 0 .2\nvt 1 .2\nvt 0 .8\nusemtl photo\nf 1/1 2/2 3/3\nusemtl grey\nf -1 -2 -3\n')
            archive.writestr('cell/p.mtl', 'newmtl photo\nKd 1 1 1\nmap_Kd p.jpg\nnewmtl grey\nKd .5 .5 .5\n')
            archive.writestr('cell/p.jpg', b'photograph fixture')
        with zipfile.ZipFile(raw) as archive:
            surfaces, materials, images, *_ = read_obj(archive, 'cell/p.obj', [100, 200, 3])
        self.assertEqual(len(surfaces), 2)
        self.assertEqual(images[0][1], b'photograph fixture')
        self.assertNotIn('baseColorTexture', materials[1]['pbrMetallicRoughness'])
        np.testing.assert_allclose(surfaces[0]['attrs']['TEXCOORD_0'][:3, 1], [.8, .8, .2])
        self.assertTrue(np.isfinite(surfaces[0]['attrs']['NORMAL']).all())

    def test_empty_municipal_obj_part_has_no_geometry(self):
        raw = io.BytesIO()
        with zipfile.ZipFile(raw, 'w') as archive:
            archive.writestr('cell/empty.obj', b'')
        with zipfile.ZipFile(raw) as archive:
            self.assertEqual(read_obj(archive, 'cell/empty.obj', [0, 0, 0]), ([], [], [], [], []))

    def test_clipped_city_cells_serialize_and_preserve_collision_policy(self):
        attrs = {'POSITION': np.array([[15, 0, 1], [17, 0, 1], [15, 0, 3]], np.float32)}
        geometry = ([{'attrs': attrs, 'faces': np.array([[0, 1, 2]]), 'material': 0}], [{}], [], [], [])
        with tempfile.TemporaryDirectory() as temporary:
            pack = CityPack(temporary, 16, [0, 0, 32, 16], [16, 32])
            for level in range(3):pack.add(geometry, level, 'fixture')
            config = {'attribution': 'fixture', 'license': {}, 'source_urls': []}
            pack.prepare(config, {})
            plan = json.loads((Path(temporary)/'build_plan.json').read_bytes())
            self.assertEqual([t['cell'] for t in plan['tiles']], [[0, 0], [1, 0]])
            self.assertTrue(all([l['collision'] for l in t['lods']] == [True, False] for t in plan['tiles']))
            self.assertGreater(plan['overview_triangles'], 0)

    def test_source_frontier_replaces_parent_and_composes_external_transform(self):
        region = [0, 0, .01, .01, 0, 100]
        parent = np.eye(4);parent[0, 3] = 10
        child = np.eye(4);child[1, 3] = 20
        documents = {'https://city.test/data/root.json': {'root': {
            'boundingVolume': {'region': region}, 'geometricError': 10,
            'transform': parent.T.ravel().tolist(), 'content': {'uri': 'coarse.b3dm'},
            'children': [{'boundingVolume': {'region': region}, 'geometricError': 2,
                          'content': {'uri': 'fine/index.json'}}]}},
            'https://city.test/data/fine/index.json': {'root': {
                'boundingVolume': {'region': region}, 'geometricError': 0,
                'transform': child.T.ravel().tolist(), 'content': {'uri': 'tile.b3dm'}}}}
        class MemoryCache:
            def json(self, url):return documents[url]
        source = Tileset(MemoryCache(), 'https://city.test/data/root.json', .1, .1, 100)
        coarse = source.frontier(20);fine = source.frontier(1)
        self.assertEqual([x['url'] for x in coarse], ['https://city.test/data/coarse.b3dm'])
        self.assertEqual([x['url'] for x in fine], ['https://city.test/data/fine/tile.b3dm'])
        np.testing.assert_array_equal(np.asarray(fine[0]['transform']), parent@child)

    def test_optional_registration_preserves_bundled_place_bytes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);path=root/'game/data/travel_places.json';path.parent.mkdir(parents=True)
            retained='{"id":"original","spawn":[1.2300,2,3]}'
            path.write_text('{"places":['+retained+']}\n',encoding='utf-8')
            entry={'id':'new_city','distribution':'optional_download','spawn':[4,5,6]}
            with patch.object(prepare_city_mesh,'ROOT',root):
                prepare_city_mesh.register(entry)
                entry['spawn']=[7,8,9];prepare_city_mesh.register(entry)
                with self.assertRaisesRegex(ValueError,'bundled'):
                    prepare_city_mesh.register({'id':'original','distribution':'optional_download'})
            self.assertIn(retained,path.read_text(encoding='utf-8'))
            data=json.loads(path.read_bytes())['places']
            self.assertEqual(len(data),2)
            self.assertEqual(data[1]['spawn'],[7,8,9])


if __name__ == '__main__':unittest.main()
