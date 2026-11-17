class_name FrogPlacement
extends RefCounted

static func within_bounds(world:WoodlandWorld,foot:Vector3,size:float)->bool:
 var bounds=world.travel_bounds.grow(-FrogBodyMetrics.BASE_RADIUS*size)
 return bounds.has_point(Vector2(foot.x,foot.z))

static func fits(space:PhysicsDirectSpaceState3D,foot:Vector3,size:float,mask:int,exclude:Array[RID]=[])->bool:
 var query=PhysicsShapeQueryParameters3D.new()
 query.shape=FrogBodyMetrics.capsule(size);query.collision_mask=mask;query.exclude=exclude
 # Lift the query 2 mm per size unit to avoid rejecting an existing floor
 # contact because of solver tolerance. Actual foot position stays anchored.
 query.transform=Transform3D(Basis.IDENTITY,foot+Vector3.UP*(.15*size+.002*size))
 query.margin=0.0
 return space.intersect_shape(query,1).is_empty()

static func arrival(world:WoodlandWorld,expected:Vector3,size:float,mask:int,exclude:Array[RID]=[])->Dictionary:
 if not within_bounds(world,expected,size):return {}
 var space=world.get_world_3d().direct_space_state
 var ray=PhysicsRayQueryParameters3D.create(expected+Vector3.UP*2,expected-Vector3.UP*3,mask)
 ray.exclude=exclude
 var hit=space.intersect_ray(ray)
 if hit.is_empty() or hit.normal.dot(Vector3.UP)<.72:return {}
 var foot=hit.position+Vector3.UP*(.035*size)
 if not fits(space,foot,size,mask,exclude):return {}
 return {"position":foot}
