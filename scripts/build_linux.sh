#!/usr/bin/env bash
set -euo pipefail
FROG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FROG_WORKSPACE="$(python3 "$FROG_ROOT/scripts/settings.py" ros_workspace)"
FROG_WORKSPACE="${FROG_WORKSPACE:-$FROG_ROOT/ros2_ws}"
FROG_ROS_SOURCE="$FROG_ROOT/ros2_ws/src"
ROS_PREFIX="${ROS_PREFIX:-$(python3 "$FROG_ROOT/scripts/settings.py" ros_prefix)}"
ROS_PREFIX="${ROS_PREFIX:-/opt/ros/lyrical}"
set +u
source "$ROS_PREFIX/setup.bash"
set -u
mkdir -p -- "$FROG_WORKSPACE"
cd -- "$FROG_WORKSPACE"
colcon build --base-paths "$FROG_ROS_SOURCE" --merge-install
colcon test --base-paths "$FROG_ROS_SOURCE" --merge-install --event-handlers console_direct+
colcon test-result --verbose
