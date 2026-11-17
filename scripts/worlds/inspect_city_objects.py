"""Inspect source object bounds without altering the archived model."""
import bpy,sys,json
from pathlib import Path
from mathutils import Vector
root=Path(__file__).resolve().parents[2]
place=sys.argv[sys.argv.index("--")+1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(root/"data/world_sources"/place/"source.glb"))
rows=[]
for o in bpy.context.scene.objects:
 if o.type!="MESH":continue
 points=[o.matrix_world@Vector(v) for v in o.bound_box]
 lo=[min(v[i] for v in points) for i in range(3)];hi=[max(v[i] for v in points) for i in range(3)]
 rows.append({"name":o.name,"bounds":[lo,hi],"triangles":sum(len(p.vertices)-2 for p in o.data.polygons),"users":o.data.users})
(root/"data/world_sources"/place/"objects.json").write_bytes((json.dumps(rows,indent=2)+"\n").encode("utf-8"))
for r in rows:print("SOURCE_OBJECT",json.dumps(r))
