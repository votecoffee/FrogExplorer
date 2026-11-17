import os
import shutil
import sys
from pathlib import Path
from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, ExecuteProcess, RegisterEventHandler, EmitEvent, OpaqueFunction, TimerAction
from launch.event_handlers import OnProcessExit
from launch.events import Shutdown
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node


def start(context):
    game = LaunchConfiguration("game_path").perform(context)
    executable = LaunchConfiguration("godot").perform(context)
    # Run the ROS interpreter directly: terminating a Windows setuptools .exe
    # wrapper can otherwise leave its Python child alive.
    bridge = ExecuteProcess(cmd=[sys.executable, "-m", "frog_explorer.bridge"], output="screen")
    prepare = ExecuteProcess(cmd=[executable, "--headless", "--editor", "--path", game, "--import"], output="screen")
    arguments = [executable, "--path", game]
    if LaunchConfiguration("headless").perform(context).lower() == "true":
        arguments.append("--headless")
    frames = int(LaunchConfiguration("auto_quit_frames").perform(context))
    if frames > 0:
        arguments.extend(["--max-fps", "60", "--", "--quit-frames="+str(frames)])
    play = ExecuteProcess(cmd=arguments, output="screen")
    def imported(event, context):
        return [play] if event.returncode == 0 else [EmitEvent(event=Shutdown(reason="Godot import failed"))]
    return [bridge, RegisterEventHandler(OnProcessExit(target_action=prepare, on_exit=imported)),
            RegisterEventHandler(OnProcessExit(target_action=play, on_exit=[TimerAction(period=.4, actions=[EmitEvent(event=Shutdown(reason="Game closed"))])])), prepare]


def generate_launch_description():
    share = Path(get_package_share_directory("frog_explorer"))
    executable = os.environ.get("GODOT_BIN") or shutil.which("godot4") or shutil.which("godot")
    if not executable:
        import json
        for parent in share.parents:
            settings = parent / ".local/settings.json"
            if settings.is_file() and (parent / "config/godot.json").is_file():
                executable = json.loads(settings.read_bytes()).get("godot")
                if executable:
                    break
    executable = executable or "godot4"
    return LaunchDescription([
        DeclareLaunchArgument("game_path", default_value=str(share / "game")),
        DeclareLaunchArgument("godot", default_value=executable),
        DeclareLaunchArgument("headless", default_value="false"),
        DeclareLaunchArgument("auto_quit_frames", default_value="0"),
        OpaqueFunction(function=start)])
