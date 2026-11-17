"""Geometric invariants, independent of Godot's importer and runtime."""
from pathlib import Path
import json
import struct
import sys
import tempfile
import unittest

try:import numpy as np
except ImportError:raise unittest.SkipTest('Optional world-building tests require numpy')
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts/worlds'))
from tile_geometry import merge_surfaces,partition,read_glb,simplify,write_gltf


def area(points,faces):
    tri=points[faces]
    return np.linalg.norm(np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]),axis=1).sum()/2


class TileGeometryTests(unittest.TestCase):
    def test_multiple_materials_and_active_scene_instances_survive(self):
        attrs={'POSITION':np.array([[0,0,0],[0,0,1],[1,0,0]],np.float32),'COLOR_0':np.array([[1,0,0,1]]*3,np.float32)}
        surfaces=[{'attrs':attrs,'faces':np.array([[0,1,2]]),'material':i} for i in [0,1]]
        materials=[{'name':f'FrogExplorerMaterial_{i:04d}','pbrMetallicRoughness':{'baseColorFactor':color}} for i,color in enumerate([[1,0,0,1],[0,0,1,1],[0,1,0,1]])]
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)/'fixture.gltf';write_gltf(path,surfaces,materials,[],[],[])
            doc=json.loads(path.read_bytes());self.assertEqual(len(doc['materials']),2,'unused material is not imported by every tile')
            # One mesh is instanced twice in the active scene; an unused node
            # must not introduce geometry into the tiled world.
            doc['nodes']=[{'mesh':0},{'mesh':0},{'mesh':0}];doc['scenes']=[{'nodes':[0,1]}]
            binary=path.with_suffix('.bin').read_bytes();doc['buffers'][0].pop('uri')
            data=json.dumps(doc).encode();data+=b' '*((-len(data))%4);binary+=b'\0'*((-len(binary))%4)
            glb=struct.pack('<III',0x46546c67,2,28+len(data)+len(binary))+struct.pack('<II',len(data),0x4e4f534a)+data+struct.pack('<II',len(binary),0x004e4942)+binary
            source=Path(temp)/'fixture.glb';source.write_bytes(glb)
            parsed,kept,*_=read_glb(source);merged=merge_surfaces(parsed)
            self.assertEqual(len(parsed),4);self.assertEqual(len(merged),2)
            self.assertEqual([len(s['faces']) for s in merged],[2,2])
            self.assertNotEqual(kept[0]['pbrMetallicRoughness'],kept[1]['pbrMetallicRoughness'])
            np.testing.assert_array_equal(merged[0]['attrs']['COLOR_0'],np.tile([1,0,0,1],(6,1)))

    def test_texture_indices_are_remapped_without_copying_unused_images(self):
        attrs={'POSITION':np.array([[0,0,0],[0,0,1],[1,0,0]],np.float32)}
        materials=[{'pbrMetallicRoughness':{'baseColorTexture':{'index':i}}} for i in range(3)]
        textures=[{'source':i,'sampler':0} for i in range(3)]
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)/'fixture.gltf';write_gltf(path,[{'attrs':attrs,'faces':np.array([[0,1,2]]),'material':2}],materials,['a.png','b.png','c.png'],textures,[{}])
            doc=json.loads(path.read_bytes())
            self.assertEqual(doc['images'],[{'uri':'../shared/c.png'}])
            self.assertEqual(doc['materials'][0]['pbrMetallicRoughness']['baseColorTexture']['index'],0)
            self.assertEqual(doc['textures'][0]['source'],0)
            self.assertEqual(materials[2]['pbrMetallicRoughness']['baseColorTexture']['index'],2,'source metadata remains unchanged')

    def test_seams_preserve_area_uv_and_winding(self):
        points=np.array([[-30,0,-20],[180,21,-20],[180,30,160],[-30,9,160]],np.float32)
        attrs={'POSITION':points,'TEXCOORD_0':points[:,[0,2]]/256}
        faces=np.array([[0,2,1],[0,3,2]])
        pieces=list(partition(attrs,faces,64));total=0;edges={}
        for cell,values,tri in pieces:
            world=values['POSITION']+np.array([cell[0]*64,0,cell[1]*64])
            total+=area(world,tri)
            np.testing.assert_allclose(values['TEXCOORD_0'],world[:,[0,2]]/256,atol=1e-7)
            normals=np.cross(world[tri[:,1]]-world[tri[:,0]],world[tri[:,2]]-world[tri[:,0]])
            self.assertTrue(np.all(normals[:,1]>0),'clipping must preserve floor winding')
            self.assertTrue(np.all(world[:,0]>=cell[0]*64-1e-5))
            self.assertTrue(np.all(world[:,0]<=(cell[0]+1)*64+1e-5))
            for point in world:
                if point[0]%64==0 or point[2]%64==0:edges.setdefault(tuple(point.round(4)),set()).add(cell)
        self.assertAlmostEqual(total,area(points,faces),delta=.02)
        self.assertTrue(any(len(cells)>1 for cells in edges.values()),'adjacent tiles share actual boundary vertices')

    def test_vertical_boundary_is_owned_once(self):
        points=np.array([[64,0,1],[64,10,1],[64,0,40]],np.float32)
        pieces=list(partition({'POSITION':points},np.array([[0,1,2]]),64))
        self.assertEqual(len(pieces),1);self.assertEqual(pieces[0][0],(1,0))
        self.assertAlmostEqual(area(pieces[0][1]['POSITION'],pieces[0][2]),195)

    def test_overview_is_smaller_and_has_no_degenerate_indices(self):
        x,z=np.meshgrid(np.arange(30),np.arange(30));points=np.column_stack((x.ravel(),np.zeros(x.size),z.ravel())).astype(np.float32)
        faces=[]
        for row in range(29):
            for col in range(29):
                i=row*30+col;faces.extend([[i,i+30,i+1],[i+1,i+30,i+31]])
        coarse,indices=simplify({'POSITION':points},np.array(faces),4)
        self.assertLess(len(indices),len(faces)/4)
        self.assertLess(len(coarse['POSITION']),len(points)/4)
        self.assertTrue(np.all(np.diff(np.sort(indices,axis=1),axis=1)!=0))


if __name__=='__main__':unittest.main()
