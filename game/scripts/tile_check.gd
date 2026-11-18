extends RefCounted

# File IO only: this worker never touches nodes, rendering or physics RIDs.
var thread=Thread.new()
var mutex=Mutex.new()
var pack:Dictionary
var cancelled=false
var completed=0

func start(data:Dictionary)->Error:
 pack=data.duplicate(true)
 return thread.start(_run)

func _run()->String:return WorldTiles.verify(pack,self)
func is_alive()->bool:return thread.is_alive()
func finish()->String:return str(thread.wait_to_finish()) if thread.is_started() else "cancelled"

func cancel():
 mutex.lock();cancelled=true;mutex.unlock()

func is_cancelled()->bool:
 mutex.lock();var value=cancelled;mutex.unlock();return value

func advance():
 mutex.lock();completed+=1;mutex.unlock()

func fraction()->float:
 mutex.lock();var value=completed;mutex.unlock()
 return float(value)/maxi(1,pack.files.size())
