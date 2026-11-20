# FrogExplorer

A Godot frog exploration game with an optional ROS 2 Lyrical bridge. Walk around a woodland pond, jump, catch flies, croak, climb trees, swim, grow or shrink, fly under a helium balloon, and drive a convertible.

The ROS package is named `frog_explorer`. This repository contains its source, the Godot project, reviewed runtime assets, asset-building tools and installation scripts. ROS itself, downloaded tools, generated workspaces and original asset downloads live outside Git.

## Table of Contents

- [Install](#install)
- [Usage](#usage)
- [Controls](#controls)
- [World travel](#world-travel)
- [ROS interface](#ros-interface)
- [Development](#development)
- [Maintainers](#maintainers)
- [Contributing](#contributing)
- [License](#license)

## Install

### Prerequisites

- Windows x64, Linux x64, or Linux ARM64 with an OpenGL-capable graphics driver.
- [Python 3.10 or newer](https://www.python.org/downloads/) on `PATH` and [Git](https://git-scm.com/downloads).
- Internet access for the initial Godot download, or an existing Godot 4.7+ executable.
- Optional: a separately installed [ROS 2 Lyrical underlay](https://docs.ros.org/en/lyrical/Get-Started/Installation.html). The installer does not install ROS or modify system packages.

Windows is the tested platform. Linux/ARM64 scripts are provided; Linux and Raspberry Pi graphics/performance have not been qualified.

### Windows: first install

```powershell
git clone https://github.com/votecoffee/FrogExplorer.git
cd FrogExplorer
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/install_windows.ps1 -Test
.\Start-FrogExplorer.cmd
```

The installer downloads **Godot 4.7.2** from its official GitHub release, verifies the pinned SHA-256, unpacks it under ignored `tools/`, imports the project, and optionally runs a headless gameplay check. Settings go in ignored `.local/settings.json`; logs and test reports go in ignored `state/`. No administrator rights, global Python packages or global execution-policy changes are required.

A fresh clone includes six animated frogs, all 16 city/landmark tile packs, synthesized audio, the authored vehicles and the woodland pond. The red-eyed tree frog has original authored geometry, textures, rig and 28 motion clips. Procedural starter frogs supply all 28 animation names if a model is absent.

To use an existing engine or install offline:

```powershell
.\scripts\install_windows.ps1 -GodotPath "C:\path\to\godot.exe" -SkipDownload -Test
```

### Included scenery and optional local assets

The repository includes **six animated frogs and all 16 city/landmark tile packs**. The installer verifies their checksums and imports the Godot resources. No separate asset download is needed for those files. The original red-eyed tree frog is MIT-licensed and includes a reproducible Blender builder. Other models and scenery retain their individual licenses, including noncommercial restrictions for some assets; see [asset credits](ASSET_CREDITS.md).

Optional municipal packs add **4 x 4 km of Helsinki**, plus photographed **Lyon
and Strasbourg** samples about one kilometre square each. Prepare them using
the [city pack installation guide](docs/CITY_PACKS.md). They use multiple source
detail levels and precise nearby collision. Large downloads and generated
meshes remain outside the base Git bundle.

To retain the earlier reference models and full-scene files for authoring, the importer accepts an existing project directory, its `game/` directory, or its `game/assets/` directory:

```powershell
.\scripts\install_windows.ps1 -AssetSource "D:\path\to\existing\FrogExplorer" -Test
```

It verifies every file against `config/assets.lock.json` before copying anything and preserves differing destination files. Existing third-party bundled files already match that reference set; additional original scenes, texture sources and the historical restricted model remain ignored. The red-eyed species selects the new `red_eye_original.glb`; importing the historical `red_eye.glb` does not replace it. Your originals remain intact. See [asset import and rebuild procedures](docs/ASSETS.md) and [asset credits](ASSET_CREDITS.md).

### Enable ROS 2 Lyrical on Windows

Install ROS separately using the [official Windows instructions](https://docs.ros.org/en/lyrical/Get-Started/Installation/Windows-Install-Binary.html), including the underlay's Python and colcon dependencies. Then configure that existing installation and build only this project's package:

```powershell
.\scripts\install_windows.ps1 -WithRos -RosPrefix "C:\path\to\lyrical" -BuildRos -Test
.\Start-FrogExplorer.cmd
```

The prefix must contain `local_setup.ps1`. The launcher recognizes the usual `.pixi/envs/default/python.exe` layout; pass `-RosPython "C:\path\to\ros-python.exe"` for another layout. ROS uses its own compatible Python, rather than assuming the installer's Python has `rclpy`.

This builds `ros2_ws/src/frog_explorer` into ignored `ros2_ws/build`, `install` and `log` directories. After ROS is configured, the normal launcher starts its bridge automatically. Use `-WithoutRos` for standalone play.

To put the build, install and log directories on another drive, add `-RosWorkspace` to the installer.

```powershell
.\scripts\install_windows.ps1 -WithRos -RosPrefix "C:\path\to\lyrical" -RosWorkspace "D:\workspaces\FrogExplorer" -BuildRos -Test
.\scripts\build_windows.ps1 -Test
.\Start-FrogExplorer.cmd
```

The installer saves the workspace path in `.local/settings.json`. Subsequent builds read the package and game source from this checkout and write to that workspace. The launcher opens the installed game and, when ROS is enabled, starts the bridge from the same installation. Use `-Editor` to edit the checkout's game.

For Windows builds that cross drive letters, FrogExplorer stages the package source on the workspace drive. Colcon reads the game assets through a temporary directory junction and installs regular copies. When the workspace filesystem cannot create a junction, the build stages the selected runtime assets as copies.

### Linux and Raspberry Pi

```bash
git clone https://github.com/votecoffee/FrogExplorer.git
cd FrogExplorer
bash scripts/install_linux.sh --test
bash scripts/run_linux.sh
```

The installer selects the pinned Linux x64 or ARM64 engine for the current machine. To import your assets, add `--asset-source /path/to/existing/FrogExplorer`. To use an existing engine, add `--godot /path/to/godot --skip-download`.

For ROS, first install a Lyrical underlay for your OS using the [official instructions](https://docs.ros.org/en/lyrical/Get-Started/Installation.html), then:

```bash
bash scripts/install_linux.sh --with-ros --ros-prefix /opt/ros/lyrical --build-ros --test
bash scripts/run_linux.sh --with-ros
# Explicit standalone play:
bash scripts/run_linux.sh --without-ros
```

Add `--ros-workspace /path/to/workspace` to the installer to build and run from a separate ROS workspace.

The pond is available on every supported platform. Real-world packs currently remain filtered out on Linux/Pi until qualified. The larger scans need performance work before claiming Pi suitability.

## Usage

```powershell
.\Start-FrogExplorer.cmd
.\scripts\run_windows.ps1 -WithoutRos
.\scripts\run_windows.ps1 -WithRos
.\scripts\run_windows.ps1 -Editor
# Start in an included world pack:
.\scripts\run_windows.ps1 -Place helsinki_senate_square
```

Use Logitech **F710 or F310 controllers in X mode**. Keep the controller's MODE light off for the normal stick/D-pad arrangement. Keyboard controls work alongside the gamepad; a keyboard legend appears at the bottom right when no controller is detected. **F2** shows detected devices and axes.

Press **Start on each additional controller** to join up to four local frogs. Two players use left/right split screen; three or four use a grid. Each player owns their frog, size, camera and vehicle. Keyboard input belongs to Player 1.

**F4** opens LAN host/join controls for up to eight frogs across computers. Install the same source revision, Godot version and optional asset set on every computer. The host's Player 1 chooses travel for the group. ENet uses UDP **24970** by default; allow that port on the host's local firewall when connecting from another computer. Asset files are not streamed to clients. LAN clients suspend their local ROS bridge ownership.

```powershell
.\scripts\run_windows.ps1 -HostLan
.\scripts\run_windows.ps1 -JoinLan 192.168.1.20:24970
```

Linux equivalents are `--host 24970` and `--join 192.168.1.20:24970`.

## Controls

| Gamepad | Keyboard | Action |
|---|---|---|
| Left stick / D-pad | WASD / arrows | Move; steer in behind/first-person views |
| Right stick left/right | J/L or Z/E | Strafe; move around a tree trunk |
| Right stick up/down | I/K or Page Up/Down | Swim depth; balloon altitude |
| X | Space / X | Jump; detach from tree; jump out of vehicle |
| Y | F / Y | Catch a fly and swallow |
| A | V | Croak |
| B | G / B | Random silly motion |
| LB | Tab / Q | Switch frog |
| RB | C | Overhead → behind → first person |
| LT / RT | + / - | Grow / shrink in size mode |
| L3 | F3 | Toggle size controls / ride controls |
| LT / RT in ride mode | 1 / 2 | Balloon / convertible |
| — | 3 | Controlled vehicle landing / dismount |
| — | 0 | Attempt default 1× size |
| Back / Select | T | Random travel; cancel an in-progress trip |
| R3 | N | Places list |
| Select Woodland pond | H | Return home |
| — | R | Recover at current arrival point |
| Start | Escape / F1 | Pause/help; extra-controller Start joins |
| — | F2 | Controller diagnostics |
| — | F4 | LAN menu |
| — | M | Mute |

In menus, use the left stick/D-pad or arrows to select, **A / Enter** to activate and **B / Escape** to close.

Walk into a trunk and keep pressing forward to climb. Either stick's horizontal input moves around the trunk; X/Space jumps away. Enter the pond to swim. Hold right-stick down or K to dive; releasing depth input floats toward the surface.

Pond entry and shore exit play short transition animations. Movement and depth controls remain active; jump, fly-catching, croak and silly-motion buttons can interrupt a transition. Reversing across the shoreline switches to the matching transition.

Size ranges from **0.25× to 16×**, subject to physical clearance. Movement speed and camera distance scale with size. In ride mode the frog hangs from a helium-balloon tether or drives a green convertible. Right-stick input raises/lowers and strafes the balloon. Jumping from a balloon deploys a parachute; a new balloon is allowed before landing, while a car requires touchdown. Jumping from a car removes it and decelerates the frog to a stop.

Hold movement keys or the D-pad to ramp up balloon speed over about four seconds. At normal frog size, full joystick or digital input reaches **36 m/s** (about 130 km/h); small stick movements give finer control, and releasing the controls brakes to a hover. Balloon altitude controls reach **12 m/s**. The parachute accelerates to a **12 m/s** descent, so returning from a high flight is quicker. Ride speeds continue to scale with frog size, with upper limits.

## World travel

The catalog includes **12 city areas and four historic destinations**: Helsinki, five US cities, Tokyo, Shanghai, Berlin, Moscow, Montréal, Mexico City, Machu Picchu, a Great Wall section, Giza and the Colosseum. A fresh clone includes their runtime tiles and the pond; only present, device-qualified packs appear in the places list.

Three additional optional entries provide the larger Helsinki city centre,
Lyon Bellecour and Strasbourg cathedral district. See [coverage, preparation
commands and limitations](docs/CITY_PACKS.md). The small Helsinki pack remains
available alongside the expanded one.

The Places list marks large maps (at least 1 km² of mapped bounds) with an
expanding-map icon, and detailed municipal photomesh packs with an **HD** badge.
The selected location shows its mapped dimensions. HD describes aerial mesh
detail; close-up reconstruction artifacts can remain.

Worlds have bounded coverage and varying detail. Montréal is a short sidewalk scan; Shanghai is simplified architecture. Water and trees in imported scenes do not gain swimming or climbing volumes automatically. Travel restores every frog to default size and clears vehicles; failed or cancelled travel preserves the old world. City/history category preferences and recent visits influence random selection.

All 16 city/landmark packs use **streamed tiles**: full detail and collision near each frog, a coarse distant overview for balloon exploration, and unloading outside the group's active regions. Tile size follows the area's scale, from 16 m for short scans to 256 m for wide city cuts. Small scans can fit entirely in the nearby region. Original scene imports remain compatible. See [the tiling guide](docs/TILING.md); **F2** shows tile residency diagnostics.

## ROS interface

After configuring ROS:

```powershell
. .\scripts\environment.ps1
. (Join-Path (Resolve-FrogRosWorkspace) 'install\local_setup.ps1')
ros2 launch frog_explorer explorer.launch.py
ros2 topic echo /frog_explorer/state
```

| Topic | Type | Meaning |
|---|---|---|
| `/frog_explorer/pose` | `geometry_msgs/PoseStamped` | Host Player 1 pose |
| `/tf` | `tf2_msgs/TFMessage` | Local `woodland` → `frog_base` transform |
| `/frog_explorer/state` | `std_msgs/String` | JSON state, world/epoch, vehicles and player roster |
| `/frog_explorer/events` | `std_msgs/String` | Actions and transitions |
| `/frog_explorer/input/joy` | `sensor_msgs/Joy` | Native controller state |
| `/frog_explorer/cmd_vel` | `geometry_msgs/Twist` | Forward/left/up m/s; yaw rad/s |
| `/frog_explorer/action` | `std_msgs/String` | Action such as `jump`, `croak`, `next_frog` |
| `/frog_explorer/size` | `std_msgs/Float32` | Absolute size multiplier |
| `/frog_explorer/travel` | `std_msgs/String` | Installed place ID, `random`, `home` or `cancel` |
| `/frog_explorer/cmd/joy` | `sensor_msgs/Joy` | Standardized external controller input |
| `/clock` | `rosgraph_msgs/Clock` | Game time |

```powershell
ros2 topic pub --once /frog_explorer/action std_msgs/msg/String "{data: jump}"
ros2 topic pub --rate 10 /frog_explorer/cmd_vel geometry_msgs/msg/Twist "{linear: {x: 0.4}}"
```

Velocity commands expire after 0.3 seconds without renewal. ROS domain defaults to **79**, with localhost discovery. Game/bridge UDP ports are **17776/17777**; run one bridge/game pair per port pair. The game remains usable without ROS.

The `woodland` frame is local to the current place. Travel changes `map_epoch`; reset accumulated trajectories when it changes. Axis conversion is ROS X = −Godot Z, ROS Y = −Godot X, ROS Z = Godot Y. No continuous Earth-fixed transform is published.

## Development

```powershell
python -m unittest discover -s tests -v
python scripts/repo_check.py
.\scripts\run_windows.ps1 -WithoutRos -Smoke
.\scripts\build_windows.ps1 -Test
```

The first three commands support the public installation. Building ROS requires its configured underlay. The bundled packs support the city/travel/tiling regressions; source-GLB comparisons and rebuilding scenery require the optional original reference files. Native scripts and world/vehicle exporters are in `scripts/`; world-data Python dependencies are pinned in `scripts/worlds/requirements.txt`. See [asset tooling](docs/ASSETS.md).

The public source has Windows headless and ROS checks. Physical controllers, rendered frame rate, Linux/Pi operation and separate physical LAN computers require native acceptance. Generated validation reports stay local; no automated GitHub Actions jobs consume build minutes.

| Path | Contents |
|---|---|
| `game/` | Godot gameplay, starter geometry, six animated frogs and 16 runtime tile packs |
| `ros2_ws/src/frog_explorer/` | Custom ROS bridge, launch and package source |
| `scripts/` | Installers, launchers, exporters and validation tools |
| `config/` | Engine checksums, optional-asset identities and world recipes |
| `.local/`, `state/`, `tools/` | Ignored machine settings, reports and downloads |

## Maintainers

[@votecoffee](https://github.com/votecoffee).

## Contributing

Open an [issue](https://github.com/votecoffee/FrogExplorer/issues) or pull request with the problem, expected behavior and relevant local checks. Keep personal paths, credentials, raw captures, original downloads and generated workspaces outside Git. Runtime assets must match the reviewed inventory and retain their source credits. Keep native hardware validation separate from injected/headless results.

## License

[MIT](LICENSE) for FrogExplorer's authored code, procedural starter geometry, synthesized audio and original vehicle assets. Copyright © 2026 FrogExplorer contributors. Imported frogs/worlds and downloaded Godot retain their own terms; see [ASSET_CREDITS.md](ASSET_CREDITS.md).
