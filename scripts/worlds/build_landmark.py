"""Blender landmark worker. Source scales are approximate, not surveyed."""
import hashlib,json,sys
from pathlib import Path
import bmesh,bpy
from mathutils import Matrix,Vector
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[2]
CONFIG={
 'machu_picchu':dict(name='Machu Picchu · Peru',scale=.01,target=[15000,-26000],budget=40000,calibration='Assumed centimetre-scale architectural source; 0.01 m/unit, approximate, not surveyed.',description='Terraced citadel reconstruction with modeled walls and ruins. Bounded architectural model; surrounding mountains are not included.',kind='Textured architectural reconstruction',credit='Ministerio de Cultura Perú / original SketchUp contributor'),
 'great_wall_china':dict(name='Great Wall · Huanghuacheng area, China',scale=1,target=[-22,-346],budget=220000,calibration='Native source units treated as metres; physical scale unverified.',description='Short drone-scanned wall section near Huanghuacheng, with watchtowers. Narrow paths and incomplete surrounding terrain; use the balloon to explore.',kind='Drone photogrammetry, 156 Mavic Pro photographs',credit='Lionel'),
 'giza_pyramids':dict(name='Pyramids of Giza · Egypt',scale=10,target=[10,78],budget=90000,calibration='Approximate 10 m/source unit estimated from the large pyramid bases. No survey control.',description='Partial aerial reconstruction of the Giza plateau and two large pyramids. Coarse at frog height, with holes at some scan edges; no pyramid interiors.',kind='Aerial photogrammetry, Meshroom reconstruction',credit='gabriele.l'),
 'rome_colosseum':dict(name='Colosseum · Rome, Italy',scale=19,target=[-6,-2],budget=1600000,calibration='Approximate 19 m/source unit from roughly 10-unit outer major axis versus roughly 189 m landmark. Not surveyed.',description='Aerial scan of the Colosseum and surrounding Rome block. Explore the plaza and fly around the arena; close-up scan detail and arch openings are limited. Dense Windows prototype.',kind='Textured aerial reconstruction',credit='CMBC'),
}
def write(path,data):path.write_bytes((json.dumps(data,indent=2,ensure_ascii=False)+'\n').encode('utf-8'))
def bounds(objects):
 points=[o.matrix_world@v.co for o in objects for v in o.data.vertices]
 return [Vector(tuple(min(v[i] for v in points) for i in range(3))),Vector(tuple(max(v[i] for v in points) for i in range(3)))]
def triangles(objects):return sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in objects)
def render(objects,path):
 lo,hi=bounds(objects);center=(lo+hi)*.5;span=max(hi-lo);scene=bpy.context.scene
 scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=12;scene.cycles.use_denoising=True
 scene.world=bpy.data.worlds.new('Sky');scene.world.use_nodes=True
 scene.world.node_tree.nodes['Background'].inputs['Color'].default_value=(.48,.58,.7,1);scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.8
 bpy.ops.object.light_add(type='SUN');sun=bpy.context.object;sun.data.energy=2;sun.rotation_euler=(.5,-.5,-.5)
 bpy.ops.object.camera_add(location=center+Vector((.6,-.8,.65))*span);camera=bpy.context.object
 camera.rotation_euler=(center-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.type='ORTHO';camera.data.ortho_scale=span*1.4;camera.data.clip_start=max(.001,span*.00001);camera.data.clip_end=span*10;scene.camera=camera
 scene.render.resolution_x=1100;scene.render.resolution_y=850;scene.render.resolution_percentage=100;scene.render.filepath=str(path);bpy.ops.render.render(write_still=True)
def main():
 args=sys.argv[sys.argv.index('--')+1:];folder=Path(args[0]);place_id=folder.name
 external=next((a.split('=',1)[1] for a in args if a.startswith('--config=')),None)
 c=json.loads(Path(external).read_bytes().decode('utf-8')) if external else CONFIG[place_id]
 output=Path(c.get('output_dir',ROOT/'outputs/Landmarks_20261117'))
 if not output.is_absolute():output=ROOT/output
 output.mkdir(parents=True,exist_ok=True)
 scene_name=c.get('scene_name','landmark.glb')
 bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.preferences.filepaths.save_version=0;bpy.ops.import_scene.gltf(filepath=str(folder/'source.glb'))
 meshes=[o for o in bpy.context.scene.objects if o.type=='MESH'];source_bounds=bounds(meshes);source_triangles=triangles(meshes)
 excluded=c.get('exclude_meshes',[])
 for obj in list(meshes):
  if obj.name in excluded:meshes.remove(obj);bpy.data.objects.remove(obj,do_unlink=True)
 if excluded:source_bounds=bounds(meshes);source_triangles=triangles(meshes)
 if '--inspect' in args:
  write(folder/'inspection.json',{'id':place_id,'bounds':[list(v) for v in source_bounds],'mesh_parts':len(meshes),'triangles':source_triangles,'images':[{'name':im.name,'size':list(im.size)} for im in bpy.data.images]});render(meshes,output/(place_id+'_source.png'));return
 if external and not c.get('reviewed',False):raise RuntimeError('Inspect, calibrate and mark build_config reviewed before export')
 scale=c['scale'];origin=(source_bounds[0]+source_bounds[1])*.5;origin.z=0
 # Snapshot hierarchy matrices before unparenting so the original node order
 # cannot change child transforms. Welding retains per-loop texture seams.
 transforms={o.name:Matrix.Scale(scale,4)@Matrix.Translation(-origin)@o.matrix_world.copy() for o in meshes}
 for obj in meshes:
  obj.data=obj.data.copy();obj.parent=None;obj.matrix_world=Matrix.Identity(4);obj.data.transform(transforms[obj.name]);bm=bmesh.new();bm.from_mesh(obj.data);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.0001);bm.to_mesh(obj.data);bm.free();obj.data.update()
 bpy.ops.object.select_all(action='DESELECT')
 for obj in meshes:obj.select_set(True)
 bpy.context.view_layer.objects.active=meshes[0];bpy.ops.object.join();mesh=bpy.context.object;mesh.name=place_id
 before=triangles([mesh])
 if before>c['budget']:
  modifier=mesh.modifiers.new('Scan triangle budget','DECIMATE');modifier.ratio=c['budget']/before;bpy.ops.object.modifier_apply(modifier=modifier.name)
 # Material/UV boundaries constrain collapse. Measure the result instead of
 # assuming Decimate's ratio equals the requested output count.
 for attempt in range(3):
  mesh.data.validate(clean_customdata=False);mesh.data.update();actual=triangles([mesh])
  if actual<=c['budget']*1.03:break
  modifier=mesh.modifiers.new('Measured triangle budget','DECIMATE');modifier.ratio=c['budget']/actual*.85;bpy.ops.object.modifier_apply(modifier=modifier.name)
 mesh.data.calc_loop_triangles();vertices=[v.co.copy() for v in mesh.data.vertices];bvh=BVHTree.FromPolygons(vertices,[tuple(t.vertices) for t in mesh.data.loop_triangles],all_triangles=True);lo,hi=bounds([mesh])
 def floor(x,y):
  at,normal,_,_=bvh.ray_cast(Vector((x,y,hi.z+10)),Vector((0,0,-1)),hi.z-lo.z+20)
  return (at,normal) if at is not None else None
 target=(Vector((*c['target'],0))-origin)*scale;candidates=[];radius=c.get('arrival_radius',1.2)
 # Validate actual exported surfaces around the selected plaza/path. No pads
 # are added to hide missing scan geometry.
 for i in range(-24,25):
  for j in range(-24,25):
   x=target.x+i*.5;y=target.y+j*.5;sample=floor(x,y)
   if sample is None or abs(sample[1].z)<.985:continue
   at=sample[0];valid=True
   for dx,dy in [(0,0),(radius,0),(-radius,0),(0,radius),(0,-radius),(radius*.67,radius*.67),(-radius*.67,-radius*.67)]:
    around=floor(x+dx,y+dy)
    if around is None or abs(around[1].z)<.97 or abs(around[0].z-at.z)>.20:valid=False;break
   if valid:candidates.append(((x-target.x)**2+(y-target.y)**2,at.copy()))
 candidates.sort(key=lambda pair:pair[0])
 if not candidates:raise RuntimeError('No clear arrival near selected source path: '+place_id)
 arrival=candidates[0][1];z_origin=arrival.z
 for v in mesh.data.vertices:v.co.z-=z_origin
 mesh.data.update();recover=[]
 for _,at in candidates:
  p=Vector((at.x,at.y,at.z-z_origin))
  if all((Vector((old[0],-old[2],old[1]))-p).length>1.5 for old in recover):recover.append([p.x,p.z+.04,-p.y])
  if len(recover)>=16:break
 mesh.data.validate(clean_customdata=False)
 bm=bmesh.new();bm.from_mesh(mesh.data)
 bmesh.ops.delete(bm,geom=[v for v in bm.verts if not v.link_faces],context='VERTS')
 bm.to_mesh(mesh.data);bm.free();mesh.data.update();bpy.context.view_layer.update()
 lo,hi=bounds([mesh]);out=ROOT/'game/assets/worlds'/place_id;out.mkdir(parents=True,exist_ok=True)
 bpy.ops.object.select_all(action='DESELECT');mesh.select_set(True);bpy.context.view_layer.objects.active=mesh
 bpy.ops.export_scene.gltf(filepath=str(out/scene_name),export_format='GLB',use_selection=True,export_animations=False,export_cameras=False,export_lights=False)
 for image in bpy.data.images:
  if image.source=='FILE' and not image.packed_file:image.pack()
 bpy.ops.wm.save_as_mainfile(filepath=str(folder/(Path(scene_name).stem+'.blend')));r=json.loads((folder/'source_receipt.json').read_bytes().decode('utf-8'))
 entry={'id':place_id,'name':c['name'],'category':'history','provider':'local_mesh','status':'ready','profiles':['windows'],'random_eligible':True,'scene':f'res://assets/worlds/{place_id}/landmark.glb','spawn':[arrival.x,.04,-arrival.y],'spawn_candidates':recover[1:],'heading_degrees':0,'bounds':[lo.x+.25,-hi.y+.25,hi.x-.25,-lo.y-.25],'vertical_bounds':[lo.z,hi.z],'size_range':[.25,16.0],'camera_far':max(650,2*max(hi-lo)),'fog_density':.00020,'attribution':c['credit']+' · CC BY 4.0 · archived via Objaverse / Zenodo','source_url':r['original_url'],'source_urls':[r['original_url'],r['archive_url']],'description':c['description'],'capabilities':['walking','jumping','balloon','driving'],'anchor':{'horizontal_crs':'LOCAL_MODEL','source_units_to_meters':scale,'source_blender_origin':[origin.x,origin.y,z_origin/scale],'local_axes':'X model-right, Y up, Z model-back; north orientation unknown','scale_accuracy':c['calibration'],'georeferenced':False},'quality':c['kind']+'; finite source cut, holes and coarse close-up textures retained. No invented surrounding terrain, water or climbing volumes.','qualification':{'windows':'Windows prototype; see LANDMARKS.md and retained validation receipts for checked physics routes. Rendered game FPS and physical controller untested','linux':'untested','pi5':'untested'}}
 entry['category']=c.get('category','history');entry['scene']=f'res://assets/worlds/{place_id}/{scene_name}'
 if external:
  entry['country']=c['country']
  entry['license']=r.get('license',{})
  entry['attribution']=c['credit']+' · '+str(r.get('license',{}).get('id','unspecified'))+' · archived via Objaverse / Zenodo'
  entry['qualification']['windows']='Windows prototype; see WORLD_CITIES.md and validation receipts. Rendered game FPS and physical controller untested'
 write(folder/'catalog_entry.json',entry);write(folder/'build_receipt.json',{'id':place_id,'source_sha256':r['source_sha256'],'source_bounds':[list(v) for v in source_bounds],'source_triangles':source_triangles,'export_triangles':triangles([mesh]),'scale_calibration':c['calibration'],'entry':entry,'glb_bytes':(out/scene_name).stat().st_size,'glb_sha256':hashlib.sha256((out/scene_name).read_bytes()).hexdigest()})
 print('LANDMARK_BUILT',place_id,triangles([mesh]),entry['spawn'],entry['vertical_bounds'],flush=True);render([mesh],output/(place_id+'_ready.png'))
if __name__=='__main__':main()
