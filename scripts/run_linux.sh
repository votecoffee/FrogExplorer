#!/usr/bin/env bash
set -euo pipefail
FROG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-$(python3 "$FROG_ROOT/scripts/settings.py" godot)}"
GODOT_BIN="${GODOT_BIN:-$(command -v godot4 || command -v godot || true)}"
[[ -n "$GODOT_BIN" ]] || { echo 'Install Godot 4 and set GODOT_BIN.'; exit 1; }
[[ "$("$GODOT_BIN" --version)" == 4.* ]] || { echo 'Godot 4 is required.'; exit 1; }
mkdir -p "$FROG_ROOT/state"
WITHOUT_ROS=true
[[ "$(python3 "$FROG_ROOT/scripts/settings.py" use_ros)" == true ]] && WITHOUT_ROS=false
HOSTING_LAN=false
JOINING_LAN=false
GAME_ARGS=()
USER_ARGS=()
while (($#)); do
 case "$1" in
  --without-ros) WITHOUT_ROS=true; shift ;;
  --with-ros) WITHOUT_ROS=false; shift ;;
  --smoke|--travel-smoke|--size-smoke|--ride-smoke) GAME_ARGS+=(--headless); USER_ARGS+=("$1"); shift ;;
  --place)
   [[ "$#" -ge 2 && "$2" =~ ^[a-z][a-z0-9_]{0,79}$ ]] || { echo 'Use --place with an installed place ID.'; exit 1; }
   USER_ARGS+=("--place=$2"); shift 2 ;;
  --host)
   [[ "$#" -ge 2 && "$2" =~ ^[0-9]{4,5}$ && "$2" -ge 1024 && "$2" -le 65535 ]] || { echo 'Use --host with a UDP port (1024-65535).'; exit 1; }
   HOSTING_LAN=true; USER_ARGS+=("--host=$2"); shift 2 ;;
  --join)
   [[ "$#" -ge 2 && -n "$2" ]] || { echo 'Use --join with the host IP or hostname, optionally :port.'; exit 1; }
   WITHOUT_ROS=true; JOINING_LAN=true; USER_ARGS+=("--join=$2" '--no-ros'); shift 2 ;;
  *) echo "Unknown option: $1"; exit 1 ;;
 esac
done
[[ "$HOSTING_LAN" != true || "$JOINING_LAN" != true ]] || { echo 'Choose --host or --join.'; exit 1; }
FROG_WORKSPACE="$(python3 "$FROG_ROOT/scripts/settings.py" ros_workspace)"
GAME_PATH="$FROG_ROOT/game"
if [[ -n "$FROG_WORKSPACE" ]]; then
 GAME_SHARE="$FROG_WORKSPACE/install/share/frog_explorer"
 GAME_PATH="$GAME_SHARE/game"
 [[ -f "$GAME_PATH/project.godot" ]] || { echo "Build the configured ROS workspace before launching its installed game: $FROG_WORKSPACE"; exit 1; }
 mkdir -p -- "$GAME_SHARE/state"
fi
BRIDGE_PID=""
cleanup() { if [[ -n "$BRIDGE_PID" ]]; then kill "$BRIDGE_PID" 2>/dev/null || true; wait "$BRIDGE_PID" 2>/dev/null || true; fi; }
trap cleanup EXIT INT TERM
if [[ "$WITHOUT_ROS" != true ]]; then
 set +u
 ROS_PREFIX="${ROS_PREFIX:-$(python3 "$FROG_ROOT/scripts/settings.py" ros_prefix)}"
 source "${ROS_PREFIX:-/opt/ros/lyrical}/setup.bash"
 if [[ -n "$FROG_WORKSPACE" ]]; then
  source "$FROG_WORKSPACE/install/local_setup.bash"
 else
  export PYTHONPATH="$FROG_ROOT/ros2_ws/src/frog_explorer:${PYTHONPATH:-}"
 fi
 set -u
 export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-79}"
 export ROS_AUTOMATIC_DISCOVERY_RANGE=LOCALHOST
 export ROS_HOME="$FROG_ROOT/state/ros"
 export ROS_LOG_DIR="$ROS_HOME/log"
 python3 -m frog_explorer.bridge >"$FROG_ROOT/state/bridge.log" 2>&1 &
 BRIDGE_PID=$!
else
 USER_ARGS+=(--no-ros)
fi
"$GODOT_BIN" --headless --editor --path "$GAME_PATH" --import >"$FROG_ROOT/state/import.log" 2>&1
"$GODOT_BIN" --path "$GAME_PATH" "${GAME_ARGS[@]}" -- "${USER_ARGS[@]}" >"$FROG_ROOT/state/game.log" 2>&1
