"""Geometric invariants, independent of Godot's importer and runtime."""
from pathlib import Path
import sys
import unittest

try:import numpy as np
except ImportError:raise unittest.SkipTest('Optional world-building tests require numpy')
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts/worlds'))
from tile_geometry import partition,simplify


def area(points,faces):
    tri=points[faces]
    return np.linalg.norm(np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]),axis=1).sum()/2


class TileGeometryTests(unittest.TestCase):
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
