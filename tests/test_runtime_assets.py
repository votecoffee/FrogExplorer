import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
sys.path.insert(0,str(ROOT/'ros2_ws/src/frog_explorer'))
from runtime_assets import asset_path,verify
from frog_explorer.asset_files import game_files


class RuntimeAssetTests(unittest.TestCase):
    def test_asset_inventory_rejects_same_length_corruption(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);path=root/'game/assets/frogs/bullfrog.glb';path.parent.mkdir(parents=True);path.write_bytes(b'frog')
            (root/'config').mkdir()
            data={'version':1,'worlds':[],'frogs':[],'files':[{'path':'assets/frogs/bullfrog.glb','size':4,'sha256':hashlib.sha256(b'frog').hexdigest()}]}
            (root/'config/runtime_assets.lock.json').write_text(json.dumps(data))
            self.assertEqual(verify(root)['files'],1)
            path.write_bytes(b'xxxx')
            with self.assertRaisesRegex(ValueError,'checksum'):verify(root)

    def test_inventory_paths_cannot_escape_game(self):
        for path in ['../secret','assets/worlds/../secret','assets/frogs/C:/other','assets/frogs/a\\b','scripts/frog.gd']:
            with self.assertRaises(ValueError):asset_path(ROOT,path)

    def test_ros_install_selects_active_pack_and_optional_frog(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)
            for name in ['data','assets/worlds/test/current','assets/worlds/test/old','assets/frogs','scripts']:(root/name).mkdir(parents=True)
            catalog={'places':[{'provider':'local_mesh','scene':'res://assets/worlds/test/city.glb','tile_manifest':'res://assets/worlds/test/current/manifest.json'}]}
            (root/'data/travel_places.json').write_text(json.dumps(catalog))
            (root/'assets/worlds/test/current/manifest.json').write_text(json.dumps({'files':{'mesh.res':'hash'}}))
            for name in ['assets/worlds/test/current/mesh.res','assets/worlds/test/current/source.bin','assets/worlds/test/old/mesh.res','assets/worlds/test/city.glb','assets/frogs/red_eye.glb','assets/frogs/unused.png','scripts/frog.gd']:(root/name).write_bytes(b'data')
            selected={p.relative_to(root).as_posix() for p in game_files(root)}
            self.assertIn('assets/worlds/test/current/mesh.res',selected);self.assertIn('assets/frogs/red_eye.glb',selected)
            for excluded in ['assets/worlds/test/current/source.bin','assets/worlds/test/old/mesh.res','assets/worlds/test/city.glb','assets/frogs/unused.png']:self.assertNotIn(excluded,selected)
