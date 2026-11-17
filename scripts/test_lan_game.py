"""Exercise real ENet sockets between independent headless Godot processes."""
import json
import math
import os
from pathlib import Path
import subprocess
import time

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'outputs/Multiplayer_20261117'
GODOT=ROOT/'tools/godot/Godot_v4.7.2-stable_win64.exe'


def main():
    run=OUT/('lan_run_'+time.strftime('%Y%m%d_%H%M%S'))
    run.mkdir(parents=True)
    processes={};logs={};checks=[];sequences={};latest={}
    port=24971
    def start(role,pads=2):
        logs[role]=(run/(role+'.log')).open('wb')
        processes[role]=subprocess.Popen([str(GODOT),'--headless','--path',str(ROOT/'game'),'--max-fps','60','--script','res://scripts/lan_probe.gd','--','--test-session','--no-ros',f'--probe-dir={run}',f'--probe-role={role}',f'--probe-port={port}',f'--probe-pads={pads}'],stdout=logs[role],stderr=subprocess.STDOUT)
    def read(role):
        try:
            latest[role]=json.loads((run/(role+'_state.json')).read_bytes().decode('utf-8'))
        except (FileNotFoundError,json.JSONDecodeError,PermissionError):pass
        return latest.get(role,{})
    def wait(predicate,timeout=10):
        end=time.monotonic()+timeout
        while time.monotonic()<end:
            for role in processes:read(role)
            if predicate():return True
            if any(p.poll() is not None for p in processes.values()):return False
            time.sleep(.05)
        return False
    def check(ok,text):
        checks.append({'test':text,'passed':bool(ok)});print(('PASS ' if ok else 'FAIL ')+text,flush=True)
        if not ok:raise AssertionError(text)
    def send(role,cmd,**values):
        seq=sequences.get(role,0)+1;sequences[role]=seq
        temp=run/(role+f'_command_{seq:06d}.tmp');temp.write_bytes(json.dumps({'seq':seq,'cmd':cmd,**values}).encode('utf-8'))
        os.replace(temp,run/(role+f'_command_{seq:06d}.json'))
        if not wait(lambda:read(role).get('processed',-1)>=seq,4):raise AssertionError('Command did not complete: '+role+' '+cmd)
    def state(role):return read(role)
    def player(role,key):return next((p for p in state(role).get('players',[]) if p['key']==key),{})
    def local(role,index=0):return next((p for p in state(role).get('players',[]) if p['local'] and p['index']==index),{})
    def distance(a,b):return math.dist(a,b)
    try:
        start('host');check(wait(lambda:state('host').get('role')=='host'),'Host opens a real loopback ENet server')
        start('client');check(wait(lambda:state('client').get('role')=='client' and state('client').get('snapshots')==4 and len(state('host').get('players',[]))==4,20),'Two computers with two local controllers each share four frogs')
        client_key=local('client')['key'];second_key=local('client',1)['key'];host_key=local('host')['key']
        check(state('host')['views']==2 and state('client')['views']==2,'Each computer renders only its two local split-screen views')
        check(not state('host')['ros_client_mode'] and state('client')['ros_client_mode'],'LAN clients suspend local ROS ownership while the host retains Player 1 ROS')
        check(all(p['physics'] for p in state('host')['players']) and not any(p['physics'] for p in state('client')['players']),'Only the host simulates player physics')
        before=player('host',client_key)['position'];host_before=player('host',host_key)['position']
        send('client','axes',move=[1,0],duration=.8)
        check(wait(lambda:player('host',client_key)['position'][0]>before[0]+.2),'Client stick input moves its authoritative frog on the host')
        check(distance(player('host',host_key)['position'],host_before)<.05,'Remote input cannot move the host player')
        check(wait(lambda:distance(player('host',client_key)['position'],player('client',client_key)['position'])<.1),'Client rendering converges to the host position')
        send('client','axes',move=[1,0],duration=3);time.sleep(.25);send('client','silence_input',enabled=True);time.sleep(.8)
        stopped=player('host',client_key)['position'];time.sleep(.4)
        check(distance(stopped,player('host',client_key)['position'])<.03,'Host input watchdog stops movement when client input packets stop')
        send('client','axes',duration=.05);send('client','silence_input',enabled=False)
        before=player('host',second_key)['species'];send('client','action',player=1,action='next_frog')
        check(wait(lambda:player('host',second_key)['species']==(before+1)%6 and player('client',second_key)['species']==(before+1)%6),'Client Player 2 species changes replicate to both computers')
        before=player('host',client_key)['scale'];send('client','axes',triggers=[1,0],resize=1,duration=.55)
        check(wait(lambda:player('host',client_key)['scale']>before*1.2),'Client LT grows its host-controlled frog')
        check(player('host',second_key)['scale']==1 and player('host',host_key)['scale']==1,'Remote resizing leaves other frogs unchanged')
        send('client','axes',triggers=[0,0],resize=0,duration=.05);time.sleep(.25)
        send('client','action',action='reset_size');check(wait(lambda:abs(player('host',client_key)['scale']-1)<.001),'Remote reset size returns to baseline')
        # Place an owned frog at a known catch location on the authoritative host.
        send('host','setup_catch',key=client_key);time.sleep(.2);send('client','action',action='catch_fly')
        check(wait(lambda:player('host',client_key)['score']==1 and player('client',client_key)['score']==1),'Fly catch and score are decided by the host and replicated')
        check(any(v>0 for v in state('client')['flies']),'Clients share the host fly respawn state')
        send('client','action',action='ride_balloon')
        check(wait(lambda:player('host',client_key)['ride']=='BALLOON' and player('client',client_key)['ride']=='BALLOON'),'Remote balloon boarding replicates its vehicle visual')
        check(player('client',client_key)['ride_prop'] and player('client',client_key)['ride_collision']==0,'Client vehicle replicas are visible and non-authoritative')
        before=player('host',client_key)['position'];send('client','axes',aux=[1,-1],duration=1.5)
        check(wait(lambda:player('host',client_key)['position'][1]>before[1]+.25 and abs(player('host',client_key)['position'][0]-before[0])>.2),'Remote right stick raises and strafes the balloon')
        check(wait(lambda:player('host',client_key)['position'][1]>before[1]+2),'Remote balloon reaches a clear test altitude before jumping')
        send('client','axes',aux=[0,0],duration=.05);time.sleep(.2)
        send('client','action',action='jump')
        check(wait(lambda:player('host',client_key)['ride']=='PARACHUTE' and player('client',client_key)['ride']=='PARACHUTE'),'Remote jump changes balloon to parachute on both computers')
        check(player('client',client_key)['parachute_lines']==8,'Parachute suspension lines replicate')
        send('client','action',action='ride_car');time.sleep(.15)
        check(player('host',client_key)['ride']!='CAR','Remote car boarding is rejected before parachute touchdown')
        send('client','action',action='ride_balloon');check(wait(lambda:player('host',client_key)['ride']=='BALLOON'),'A remote frog can redeploy a balloon in midair')
        before=state('host')['epoch'];send('host','travel',place='holland_downtown')
        check(wait(lambda:state('host').get('place')=='holland_downtown' and state('client').get('place')=='holland_downtown' and state('client').get('snapshots')==4,20),'Host travel loads the same installed city on the client')
        check(state('host')['epoch']==before+1 and state('client')['epoch']==state('host')['epoch'],'Host and client share the map epoch after travel')
        check(all(p['scale']==1 and p['ride']=='FOOT' for p in state('host')['players']),'Group travel resets every local and remote frog size and ride')
        check(wait(lambda:all(p['scale']==1 and p['ride']=='FOOT' for p in state('client')['players'])),'All four client replicas adopt the clean arrival state')
        send('client','travel',place='home_woodland_pond');time.sleep(.25)
        check(state('host')['place']=='holland_downtown' and state('client')['place']=='holland_downtown','A client cannot change the group destination')
        before=player('host',client_key)['position'];send('client','old_epoch');time.sleep(.5)
        check(distance(before,player('host',client_key)['position'])<.08,'Input from an old world epoch is ignored')
        send('client','action',action='ride_car')
        check(wait(lambda:player('host',client_key)['ride']=='CAR' and player('client',client_key)['ride']=='CAR'),'Remote convertible is visible on both computers')
        send('client','axes',move=[0,-1],duration=.6);time.sleep(.4);send('client','action',action='jump')
        check(wait(lambda:player('host',client_key)['ride']=='COAST' and player('client',client_key)['ride']=='COAST'),'Remote car ejection and coasting replicate')
        check(wait(lambda:player('host',client_key)['ride']=='FOOT',5),'Host brings the remote coasting frog to rest')
        for index in (2,3):send('host','add_local',index=index);send('client','add_local',index=index)
        check(wait(lambda:len(state('host')['players'])==8 and len(state('client')['players'])==8 and state('client')['snapshots']==8),'Four local controllers on each computer share eight frogs')
        check(state('host')['views']==4 and state('client')['views']==4,'Both computers use four-way split screen at eight-player capacity')
        start('extra',1)
        check(wait(lambda:state('extra').get('role')=='local' and 'full' in state('extra').get('status',''),15),'A full party rejects another computer without spawning extra frogs')
        check(len(state('host')['players'])==8,'Rejected joins preserve the eight-player party')
        send('extra','quit');processes['extra'].wait(timeout=5);del processes['extra']
        before=state('host')['epoch'];send('host','travel',place='giza_pyramids')
        check(wait(lambda:state('host')['place']=='giza_pyramids' and state('client')['place']=='giza_pyramids' and state('client')['epoch']==state('host')['epoch'],25),'Eight local and remote frogs travel together to Giza')
        check(state('host')['epoch']==before+1 and all(p['scale']==1 and p['ride']=='FOOT' for p in state('host')['players']),'Landmark group travel resets all eight sizes and rides in one epoch')
        check(wait(lambda:len(state('client')['players'])==8 and all(p['scale']==1 and p['ride']=='FOOT' for p in state('client')['players'])),'All eight landmark replicas converge after scene loading')
        before=state('host')['epoch'];send('host','travel',place='tokyo_imperial_palace')
        check(wait(lambda:state('host')['place']=='tokyo_imperial_palace' and state('client')['place']=='tokyo_imperial_palace' and state('client')['epoch']==state('host')['epoch'],30),'Eight local and remote frogs travel together to Tokyo')
        check(state('host')['epoch']==before+1 and len(state('host')['players'])==8 and all(p['scale']==1 and p['ride']=='FOOT' for p in state('host')['players']),'International city travel retains all eight frogs and clears their sizes and rides')
        check(wait(lambda:len(state('client')['players'])==8 and all(p['scale']==1 and p['ride']=='FOOT' for p in state('client')['players'])),'All eight Tokyo replicas converge after loading the large city scan')
        send('client','disconnect')
        check(wait(lambda:len(state('host')['players'])==4 and state('client')['role']=='local' and len(state('client')['players'])==4),'Disconnect removes only remote frogs and restores local play on both computers')
        check(not state('client')['ros_client_mode'],'Returning to local play restores normal ROS ownership')
        send('client','fingerprint',value='mismatched_build');send('client','join',address=f'127.0.0.1:{port}')
        check(wait(lambda:state('client')['role']=='local' and 'differ' in state('client')['status'],15),'Different game/scene builds are rejected before joining')
        check(len(state('host')['players'])==4,'A mismatched build cannot alter the host roster')
        send('client','fingerprint',value='');send('client','join',address=f'127.0.0.1:{port}')
        check(wait(lambda:state('client')['role']=='client' and state('client')['snapshots']==8 and len(state('host')['players'])==8,20),'A disconnected computer can reconnect with its four local controllers')
        send('host','disconnect')
        check(wait(lambda:state('client')['role']=='local' and len(state('client')['players'])==4 and all(p['physics'] for p in state('client')['players'])),'Losing the host restores local physics and removes remote frogs')
        send('host','travel',place='home_woodland_pond');check(wait(lambda:state('host')['place']=='home_woodland_pond'),'Host returns its four local frogs to the pond')
    finally:
        for p in processes.values():
            if p.poll() is None:p.terminate()
        for p in processes.values():
            try:p.wait(timeout=5)
            except subprocess.TimeoutExpired:p.kill();p.wait()
        for log in logs.values():log.close()
        errors={p.name: [line for line in p.read_bytes().decode('utf-8',errors='replace').splitlines() if 'ERROR:' in line or 'WARNING: Sending' in line] for p in run.glob('*.log')}
        checks.append({'test':'Independent game processes have no runtime errors or oversized unreliable packets','passed':not any(errors.values())})
        report={'checks':checks,'failures':[c['test'] for c in checks if not c['passed']],'run':str(run),'scope':'Real ENet sockets between independent Godot processes on Windows loopback, with injected controls and actual meshes. Separate physical computers, multiple physical F710 controllers, rendered FPS, Linux and Pi remain untested.'}
        (OUT/'lan_acceptance.json').write_bytes((json.dumps(report,indent=2)+'\n').encode('utf-8'))
        print(json.dumps({'checks':len(checks),'failures':report['failures'],'run':str(run)},indent=2))
    if report['failures']:raise AssertionError(report['failures'])


if __name__=='__main__':main()
