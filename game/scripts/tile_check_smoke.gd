extends SceneTree

const TileCheck=preload("res://scripts/tile_check.gd")
class PausedCheck extends "res://scripts/tile_check.gd":
 var paused=Semaphore.new()
 var release=Semaphore.new()
 var held=false
 func advance():
  super.advance()
  if not held:held=true;paused.post();release.wait()

var failures=[]
var checks=[]
func _initialize():run.call_deferred()
func check(ok,text):
 checks.append({"test":text,"passed":bool(ok)})
 if not ok:failures.append(text)
 print(("PASS " if ok else "FAIL ")+text)
func paused(job):
 var end=Time.get_ticks_msec()+5000
 while Time.get_ticks_msec()<end:
  if job.paused.try_wait():return true
  await process_frame
 return false
func finished(job):
 while job.is_alive():await process_frame
 return job.finish()
func fixture():
 var folder="user://tile_check_"+str(Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(folder)
 var files={}
 for name in ["a.bin","b.bin"]:
  var file=FileAccess.open(folder+"/"+name,FileAccess.WRITE);file.store_buffer(name.repeat(4096).to_utf8_buffer());file.close()
  files[name]=FileAccess.get_sha256(folder+"/"+name)
 return {"folder":folder,"files":files}
func run():
 var data=fixture();var job=PausedCheck.new()
 check(job.start(data)==OK,"Integrity worker starts")
 check(await paused(job),"Worker can pause between real file hashes")
 var frame=Engine.get_process_frames()
 for i in range(4):await process_frame
 check(Engine.get_process_frames()>=frame+3 and job.is_alive(),"The main loop continues while integrity IO is pending")
 job.cancel();job.release.post()
 check(await finished(job)=="cancelled" and not job.thread.is_started(),"Cancellation joins the worker cleanly")
 check(not WorldTiles.is_verified(data),"A cancelled check is never cached as successful")
 var normal=TileCheck.new();normal.start(data)
 check(await finished(normal)=="" and WorldTiles.is_verified(data),"Successful verification is cached for the exact file table")
 var cached=PausedCheck.new();cached.start(data)
 check(await finished(cached)=="" and cached.fraction()==0,"A repeat visit skips file hashing")
 var changed=data.duplicate(true);changed.files["b.bin"]="0".repeat(64)
 var damaged=TileCheck.new();damaged.start(changed)
 check((await finished(damaged)).contains("integrity") and not WorldTiles.is_verified(changed),"A changed expected digest cannot reuse the cached result")
 var missing=data.duplicate(true);missing.files["missing.bin"]="0".repeat(64)
 var absent=TileCheck.new();absent.start(missing)
 check((await finished(absent)).contains("missing.bin"),"A missing dependency is rejected before travel")
 var original=fixture();var snapshot=PausedCheck.new();snapshot.start(original)
 check(await paused(snapshot),"A second worker takes its own snapshot")
 original.files["b.bin"]="0".repeat(64);snapshot.release.post()
 check(await finished(snapshot)=="" and not WorldTiles.is_verified(original),"Caller mutations cannot alter an in-flight file table")
 print("TILE_CHECK_SMOKE "+JSON.stringify({"checks":checks.size(),"failures":failures}))
 quit(0 if failures.is_empty() else 1)
