"""Live DDS -> bridge -> Godot -> bridge -> DDS acceptance on this host."""
import json,os,subprocess,sys,time
from pathlib import Path
import rclpy
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from geometry_msgs.msg import PoseStamped,Twist
from sensor_msgs.msg import Joy
from std_msgs.msg import String,Float32
from engine import resolve_engine

ROOT=Path(__file__).resolve().parents[1]
def main():
    godot=resolve_engine(ROOT)
    rclpy.init();probe=Node('frog_explorer_acceptance');states=[];poses=[];checks=[];joy_samples=[]
    probe.create_subscription(String,'/frog_explorer/state',lambda m:states.append(json.loads(m.data)),10)
    probe.create_subscription(PoseStamped,'/frog_explorer/pose',lambda m:poses.append(m),10)
    actions=probe.create_publisher(String,'/frog_explorer/action',10);velocities=probe.create_publisher(Twist,'/frog_explorer/cmd_vel',10)
    travels=probe.create_publisher(String,'/frog_explorer/travel',10)
    sizes=probe.create_publisher(Float32,'/frog_explorer/size',10)
    joy_commands=probe.create_publisher(Joy,'/frog_explorer/cmd/joy',qos_profile_sensor_data)
    probe.create_subscription(Joy,'/frog_explorer/input/joy',lambda m:joy_samples.append(m),qos_profile_sensor_data)
    logs=[];processes=[]
    def wait_for(predicate,timeout=7):
        end=time.monotonic()+timeout
        while time.monotonic()<end:
            rclpy.spin_once(probe,timeout_sec=.025)
            if predicate():return True
        return False
    def check(condition,text):
        checks.append({'check':text,'passed':bool(condition)})
        if not condition:raise AssertionError(text)
    def action(name):actions.publish(String(data=name))
    try:
        for name,cmd in [('bridge',[sys.executable,'-m','frog_explorer.bridge']),('game',[godot,'--headless','--path',str(ROOT/'game'),'--max-fps','60','--','--test-session'])]:
            log=(ROOT/'state'/('live_'+name+'.log')).open('w');logs.append(log)
            processes.append(subprocess.Popen(cmd,stdout=log,stderr=subprocess.STDOUT,cwd=ROOT))
        check(wait_for(lambda:len(states)>=3 and bool(poses)),'Game state and pose arrive over ROS DDS')
        check(states[-1].get('player_count')==1 and states[-1].get('local_player_count')==1 and states[-1].get('primary_player_id')=='1:0' and len(states[-1].get('players',[]))==1,'ROS state adds the party roster while retaining the Player 1 interface')
        check(states[-1]['species']=='Montane brown frog','Game starts with first frog')
        initial=states[-1]['camera'];action('next_camera')
        check(wait_for(lambda:states[-1]['camera']!=initial),'ROS action changes the game camera')
        action('next_frog');check(wait_for(lambda:states[-1]['species']=='Japanese toad'),'ROS action switches the actual frog model')
        action('croak');check(wait_for(lambda:states[-1]['animation']=='Croak'),'ROS croak action reaches AnimationPlayer')
        action('reset');wait_for(lambda:states[-1]['animation']=='Living_Idle')
        before=poses[-1].pose.position
        started=time.monotonic()
        while time.monotonic()-started<.8:
            command=Twist();command.linear.x=.45;velocities.publish(command);rclpy.spin_once(probe,timeout_sec=.04)
        check(wait_for(lambda:abs(poses[-1].pose.position.x-before.x)+abs(poses[-1].pose.position.y-before.y)>.15),'ROS SI velocity moves the physical frog')
        time.sleep(.45);rclpy.spin_once(probe,timeout_sec=.05);last=poses[-1].pose.position
        time.sleep(.5);rclpy.spin_once(probe,timeout_sec=.05)
        # Drain queued DDS samples before measuring the watchdog's settled pose.
        for _ in range(20):rclpy.spin_once(probe,timeout_sec=.01)
        settled=poses[-1].pose.position;time.sleep(.3)
        for _ in range(20):rclpy.spin_once(probe,timeout_sec=.01)
        current=poses[-1].pose.position
        distance=((current.x-settled.x)**2+(current.y-settled.y)**2)**.5
        check(distance<.035,'Expired ROS velocity stops motion without renewal')
        check(all(p.pose.orientation.w**2+p.pose.orientation.x**2+p.pose.orientation.y**2+p.pose.orientation.z**2>.99 for p in poses),'Published orientations remain normalized')
        old_time=states[-1]['time'];epoch=states[-1]['map_epoch']
        travels.publish(String(data='helsinki_senate_square'))
        check(wait_for(lambda:states[-1].get('place_id')=='helsinki_senate_square',15),'Named ROS travel reaches Helsinki')
        check(states[-1]['map_epoch']==epoch+1 and states[-1]['time']>old_time,'DDS state exposes a new map epoch with a continuous clock')
        check(states[-1]['geographic_anchor']['horizontal_crs']=='EPSG:3879','DDS state includes the projected geographic anchor')
        sizes.publish(Float32(data=4.0))
        check(wait_for(lambda:abs(states[-1].get('scale',0)-4)<.001),'ROS size request grows the physical frog to 4x')
        check(abs(states[-1]['walk_speed_mps']-2.08)<.001 and abs(states[-1]['body_height_m']-1.2)<.001,'ROS state publishes scaled walking speed and collision height')
        for _ in range(10):rclpy.spin_once(probe,timeout_sec=.025)
        command=Twist();command.linear.x=.4;before=poses[-1].pose.position;started=time.monotonic()
        while time.monotonic()-started<.55:
            velocities.publish(command);rclpy.spin_once(probe,timeout_sec=.025)
        displacement=((poses[-1].pose.position.x-before.x)**2+(poses[-1].pose.position.y-before.y)**2)**.5
        check(.12<displacement<.36,'A 4x frog keeps external cmd_vel in SI units')
        velocities.publish(Twist())
        check(wait_for(lambda:bool(joy_samples) and len(joy_samples[-1].axes)==6),'DDS controller state includes independent LT/RT axes')
        trigger=Joy();trigger.axes=[0.,0.,0.,0.,0.,1.];trigger.buttons=[0]*15
        started=time.monotonic()
        while time.monotonic()-started<.3:
            joy_commands.publish(trigger);rclpy.spin_once(probe,timeout_sec=.025)
        check(wait_for(lambda:states[-1]['scale']<3.7),'External DDS RT axis shrinks the frog')
        trigger.axes=[0.,0.,0.,0.,0.,0.];joy_commands.publish(trigger)
        sizes.publish(Float32(data=4.0));check(wait_for(lambda:abs(states[-1]['scale']-4)<.001),'Size can be restored after external trigger input')
        travels.publish(String(data='not_installed'))
        check(wait_for(lambda:states[-1].get('travel_state')=='failed'),'Invalid named travel reports failure over DDS')
        check(states[-1]['place_id']=='helsinki_senate_square' and states[-1]['map_epoch']==epoch+1,'Failed ROS travel keeps the current place and epoch')
        travels.publish(String(data='home'))
        check(wait_for(lambda:states[-1].get('place_id')=='home_woodland_pond',15),'ROS return home restores the pond')
        check(abs(states[-1]['scale']-1)<.001,'ROS travel restores the default frog size')
        action('reset_size')
        check(wait_for(lambda:abs(states[-1].get('scale',0)-1)<.001),'ROS reset_size restores the baseline multiplier')
        travels.publish(String(data='helsinki_senate_square'))
        check(wait_for(lambda:states[-1]['place_id']=='helsinki_senate_square',15),'Return to Helsinki for ride acceptance')
        action('toggle_trigger_mode')
        check(wait_for(lambda:states[-1].get('trigger_mode')=='rides'),'ROS action selects the alternate ride trigger mode')
        trigger.axes=[0.,0.,0.,0.,0.,0.];joy_commands.publish(trigger)
        wait_for(lambda:False,.15)
        trigger.axes=[0.,0.,0.,0.,1.,0.]
        started=time.monotonic()
        while time.monotonic()-started<.25:
            joy_commands.publish(trigger);rclpy.spin_once(probe,timeout_sec=.025)
        check(wait_for(lambda:states[-1].get('ride')=='BALLOON'),'External LT summons the helium balloon')
        check(abs(states[-1]['scale']-1)<.001,'Ride triggers preserve the selected frog size')
        start_pose=poses[-1].pose;start_z=start_pose.position.z
        q=start_pose.orientation
        initial_q=(q.x,q.y,q.z,q.w)
        trigger.axes=[0.,0.,.7,-.7,0.,0.];started=time.monotonic()
        while time.monotonic()-started<.6:
            joy_commands.publish(trigger);rclpy.spin_once(probe,timeout_sec=.025)
        check(poses[-1].pose.position.z>start_z+.1 and ((poses[-1].pose.position.x-start_pose.position.x)**2+(poses[-1].pose.position.y-start_pose.position.y)**2)**.5>.15,'DDS right stick combines balloon altitude and strafe')
        q=poses[-1].pose.orientation
        check(abs(sum(a*b for a,b in zip(initial_q,(q.x,q.y,q.z,q.w))))>.999,'DDS right-stick strafing preserves balloon heading')
        trigger.axes=[0.,0.,0.,0.,0.,0.];joy_commands.publish(trigger)
        wait_for(lambda:False,.2)
        action('ride_car')
        check(wait_for(lambda:states[-1].get('ride')=='CAR',10),'ROS car request lands the balloon before boarding the convertible')
        started=time.monotonic()
        while time.monotonic()-started<.5:
            command=Twist();command.linear.x=1.;velocities.publish(command);rclpy.spin_once(probe,timeout_sec=.025)
        check(abs(states[-1]['ride_speed_mps']-1)<.05,'Car SI velocity command remains in metres per second')
        velocities.publish(Twist());action('ride_exit')
        check(wait_for(lambda:states[-1].get('ride')=='FOOT',5),'ROS dismount restores frog movement')
        action('ride_balloon');check(wait_for(lambda:states[-1].get('ride')=='BALLOON'),'Balloon is ready for jump-exit acceptance')
        trigger.axes=[0.,0.,0.,-1.,0.,0.];started=time.monotonic()
        while time.monotonic()-started<1.8:
            joy_commands.publish(trigger);rclpy.spin_once(probe,timeout_sec=.025)
        trigger.axes=[0.,0.,0.,0.,0.,0.];joy_commands.publish(trigger)
        action('jump')
        check(wait_for(lambda:states[-1].get('ride')=='PARACHUTE' and states[-1].get('parachute_active')),'ROS jump immediately changes balloon flight to parachuting')
        action('ride_car');wait_for(lambda:False,.15)
        check(states[-1]['ride']=='PARACHUTE' and states[-1]['ride_altitude_m']>.1,'ROS car request is rejected during airborne parachuting')
        action('ride_balloon')
        check(wait_for(lambda:states[-1].get('ride')=='BALLOON') and states[-1]['ride_altitude_m']>.1,'ROS can deploy another balloon before touchdown')
        action('jump');check(wait_for(lambda:states[-1].get('ride')=='PARACHUTE'),'The replacement balloon also supports jumping out')
        check(wait_for(lambda:states[-1].get('ride')=='FOOT',8),'Parachute touchdown returns ROS state to walking')
        action('ride_car');check(wait_for(lambda:states[-1].get('ride')=='CAR'),'Car deployment is available after parachute touchdown')
        started=time.monotonic()
        while time.monotonic()-started<.35:
            command=Twist();command.linear.x=1.5;velocities.publish(command);rclpy.spin_once(probe,timeout_sec=.025)
        action('jump')
        check(wait_for(lambda:states[-1].get('ride')=='COAST' and states[-1].get('coasting')),'ROS car jump removes the car and reports coasting')
        check(wait_for(lambda:states[-1].get('ride')=='FOOT',4),'ROS coasting comes to rest and returns to walking')
        for place_id,crs in [('rochester_high_falls','EPSG:32618'),('washington_national_mall','EPSG:32618'),('holland_downtown','EPSG:32616'),('norfolk_waterfront','EPSG:32618'),('lynchburg_riverfront','EPSG:32617')]:
            prior_epoch=states[-1]['map_epoch']
            travels.publish(String(data=place_id))
            check(wait_for(lambda:states[-1].get('place_id')==place_id,15),'Named ROS travel reaches '+place_id)
            check(states[-1]['map_epoch']==prior_epoch+1 and states[-1]['geographic_anchor']['horizontal_crs']==crs,place_id+': DDS publishes the new map epoch and UTM anchor')
            check(abs(states[-1]['scale']-1)<.001 and states[-1]['ride']=='FOOT',place_id+': DDS arrival reports default size on foot')
        for place_id in ['machu_picchu','great_wall_china','giza_pyramids','rome_colosseum']:
            prior_epoch=states[-1]['map_epoch']
            travels.publish(String(data=place_id))
            check(wait_for(lambda:states[-1].get('place_id')==place_id,20),'Named ROS travel reaches '+place_id)
            check(states[-1]['map_epoch']==prior_epoch+1 and states[-1]['geographic_anchor']['horizontal_crs']=='LOCAL_MODEL',place_id+': DDS publishes a local model frame without inventing georeferencing')
            check(abs(states[-1]['scale']-1)<.001 and states[-1]['ride']=='FOOT',place_id+': DDS landmark arrival reports default size on foot')
        for place_id in ['tokyo_imperial_palace','shanghai_lujiazui','berlin_teufelsberg','moscow_andronikov','montreal_sainte_elisabeth','mexico_city_cathedral']:
            prior_epoch=states[-1]['map_epoch']
            travels.publish(String(data=place_id))
            check(wait_for(lambda:states[-1].get('place_id')==place_id,25),'Named ROS travel reaches '+place_id)
            check(states[-1]['map_epoch']==prior_epoch+1 and states[-1]['geographic_anchor']['horizontal_crs']=='LOCAL_MODEL',place_id+': DDS publishes the new epoch and local model frame')
            check(abs(states[-1]['scale']-1)<.001 and states[-1]['ride']=='FOOT',place_id+': DDS city arrival reports default size on foot')
        travels.publish(String(data='home'))
        check(wait_for(lambda:states[-1].get('place_id')=='home_woodland_pond',15),'ROS returns home after all US cities, landmarks and six international cities')
    finally:
        for process in processes:
            if process.poll() is None:process.terminate()
        for process in processes:
            try:process.wait(timeout=5)
            except subprocess.TimeoutExpired:process.kill();process.wait()
        for log in logs:log.close()
        probe.destroy_node();rclpy.shutdown()
        report={'checks':checks,'state_messages':len(states),'pose_messages':len(poses),'scope':'Live Windows ROS 2 Lyrical DDS, local UDP bridge and headless Godot physics; physical controller and Linux host untested.'}
        (ROOT/'state/ros_game_acceptance.json').write_text(json.dumps(report,indent=2))
        print(json.dumps(report,indent=2))

if __name__=='__main__':main()
