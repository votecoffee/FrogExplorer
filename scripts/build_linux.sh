#!/usr/bin/env bash
set -euo pipefail
FROG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROS_PREFIX="${ROS_PREFIX:-$(python3 "$FROG_ROOT/scripts/settings.py" ros_prefix)}"
ROS_PREFIX="${ROS_PREFIX:-/opt/ros/lyrical}"
set +u
source "$ROS_PREFIX/setup.bash"
set -u
cd "$FROG_ROOT/ros2_ws"
colcon build --merge-install
colcon test --merge-install --event-handlers console_direct+
colcon test-result --verbose
