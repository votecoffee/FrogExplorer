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

The Windows build defaults to the checkout's `ros2_ws` directory. A checkout on C: keeps `build`, `install` and `log` on C:. After ROS is configured, the launcher starts its bridge automatically. Use `-WithoutRos` for standalone play.

Pass `-RosWorkspace` to build into a separate workspace for one run. For example:

```powershell
.\scripts\build_windows.ps1 -RosWorkspace "G:\workspaces\FrogExplorer" -Test
```

To configure the launcher and future installer runs to use an external workspace, pass the same option to the installer:

```powershell
.\scripts\install_windows.ps1 -WithRos -RosPrefix "C:\path\to\lyrical" -RosWorkspace "G:\workspaces\FrogExplorer" -BuildRos -Test
.\Start-FrogExplorer.cmd
```

The installer saves the path in `.local/settings.json`. The launcher opens the installed game and starts ROS from the same installation when enabled. Direct calls to `build_windows.ps1` use the checkout's workspace unless you pass `-RosWorkspace`. Use `-Editor` to edit the checkout's game.

For Windows builds that cross drive letters, FrogExplorer stages the package source on the workspace drive. Colcon reads the game assets through a temporary directory junction and installs regular copies. When the workspace filesystem cannot create a junction, the build stages the selected runtime assets as copies.

ROS installs preserve and compare source asset timestamps at full precision, so edits within the same second can trigger an update. When a previous install rounded an asset timestamp, the build restores its precision after verifying that the file bytes match.

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
| A at an activity | F5 | Start or restart a race, or open the garden editor |
| Select Woodland pond | H | Return home |
| — | R | Recover at current arrival point |
| Start | Escape / F1 | Pause/help; extra-controller Start joins |
| — | F2 | Controller diagnostics |
| — | F4 | LAN menu |
| — | M | Mute |

In menus, use the left stick/D-pad or arrows to select, **A / Enter** to activate and **B / Escape** to close.

On land, hold a movement key or the D-pad to reach full crawl speed in about 0.8 seconds. A partial stick deflection ramps toward a slower speed. Releasing movement brakes the frog to rest, and the walking cadence follows its speed.

Walk into a trunk and keep pressing forward to climb. Either stick's horizontal input moves around the trunk; X/Space jumps away. Enter the pond to swim. Hold right-stick down or K to dive; releasing depth input floats toward the surface.

Pond entry and shore exit play short transition animations. Movement and depth controls remain active; jump, fly-catching, croak and silly-motion buttons can interrupt a transition. Reversing across the shoreline switches to the matching transition.

Size ranges from **0.25× to 16×**, subject to physical clearance. Movement speed and camera distance scale with size. In ride mode the frog hangs from a helium-balloon tether or drives a green convertible. Right-stick input raises/lowers and strafes the balloon. Jumping from a balloon deploys a parachute; a new balloon is allowed before landing, while a car requires touchdown. Jumping from a car removes it and decelerates the frog to a stop.

Hold movement keys or the D-pad to ramp up balloon speed over about four seconds. At normal frog size, full joystick or digital input reaches **36 m/s** (about 130 km/h); small stick movements give finer control, and releasing the controls brakes to a hover. Balloon altitude controls reach **12 m/s**. The parachute accelerates to a **12 m/s** descent, so returning from a high flight is quicker. Ride speeds continue to scale with frog size, with upper limits.

## World travel

### Manual activities

Open Places with **N / R3** to select these single-player destinations. Random travel skips them. Press **F5** or the gamepad's **A** button after arrival.

| Destination | Activity |
| --- | --- |
| Kingfisher Circuit | Board the convertible and drive two timed laps. The first start-line crossing starts the clock. Drive through each gate in order. |
| Cloudring Course | Launch a helium balloon and fly through eight rings in order. The next ring glows gold. Use the right stick or I/K and J/L for altitude and strafe. |
| Lily Code Garden | Type Python in a popup editor and program Pondbot to water and gather lilies across fifteen grid puzzles and four renewable nurseries. |

Press **F5 / A** again to restart a race. The course shows your current time and saved personal best. After your first timed finish, the HUD compares each gate or ring to your fastest run with recorded splits. Existing personal best times carry over. Use **H** or Places to return to the pond.

In the garden, use **Check** to preview your draft on a fresh board. It reports the expected harvest and action count or marks a command that would fail. Open **Review** and use the slider or the **Left/Right** arrow keys to inspect Pondbot's predicted position, water supply and lilies after each action. Choose **Back to board** to return to the live garden. Use **Run** or **Ctrl+Enter** to start, pause, or resume and record a completed run. Use **Step** or **F10** to execute one command and see its source line. Click beside a line number or press **F9** on a command to toggle a breakpoint. **Run** pauses before the marked command each time a loop reaches it. **Resume** runs that command and continues. Use **Stop** to edit your code while keeping the current board visible, or **Reset board** to start over. **Esc** closes the editor. The board shows Pondbot, its water supply, and how many lilies remain. Fill at a spring, hop onto a plot, water it, then allow another turn before gathering. Twin terraces has two matching beds for nested repeats. Reedbank loop needs two tankfuls and a route around the stones. Stone spillway has two beds with double lilies and a starter routine. Patchwork beds uses conditions to tend mixed plots. Forked banks uses a direct path and a detour to reach two lily beds. Lantern rows has beds of different lengths for practicing **while**. Spring relay uses combined conditions to stop a sweep when the tank runs dry. The keyboard editor opens in **Python**. Press **Tab** to indent or **Shift+Tab** to unindent. The first puzzle includes this complete example:

```python
fill()
hop(east)
water()
wait()
gather()
hop(east)
water()
wait()
gather()
```

In **Review** or **Best program**, choose **Play** or press **Space** with the timeline focused to watch the preview advance. Choose **Pause** or move the slider to stop at an action. Playing again at the end restarts the preview.

**Compare drafts** also has **Play** and **Pause**. Both drafts advance on the shared timeline. A shorter or blocked draft holds its last board while the other continues.

Place the cursor on a board command and press **Ctrl+F10** to run until just before that command. This works from a new or paused run in either language. If an earlier breakpoint pauses the run, use **Resume** to continue toward the cursor line. The temporary stop is used once. **Stop** and **Reset board** clear it.

To reproduce a specific preview step on the live board, run **Check**, open **Review**, and select an action. Choose **Run to action** or press **Ctrl+F10** with the timeline focused. The draft runs from its normal starting board and pauses after that action. Use **Resume** to continue past an earlier breakpoint. If the action ends the program, the run finishes normally.

In **Review**, use **Previous breakpoint** and **Next breakpoint** to jump between actions on marked lines. With the timeline focused, use **Shift+Page Up** and **Shift+Page Down**. Each visit to a marked line in a loop is a separate action. The preview shows the board after that action, while a live breakpoint pauses before its command.

Breakpoints save with each draft and return when you reopen it. A new copy starts with its own empty breakpoint list.

Choose **Breakpoints** or press **Ctrl+F9** to list all the marks in the current draft. Use **Up/Down** to select one, **Enter** to open its source line, or **Delete** to remove it. **Esc** closes the focused panel.

Choose **Mute all** in the panel to skip line breakpoints during live runs. You can still navigate the marks in Review and use temporary stops such as **Run to action**. Choose **Unmute** or close the editor to restore the pauses.

The first three lessons are available when you arrive. A completed puzzle adds its lilies to the garden total once. Later sets open at **2**, **8**, **18**, and **26** earned lilies. The lesson list shows the requirement beside each locked puzzle. After a clear, press **Ctrl+Page Down** or choose **Next lesson** to open the first available unfinished puzzle. Earlier drafts and completed boards stay accessible.

Lily Code Garden uses Python 3.10 or newer to parse the garden language. The supported subset includes Pondbot calls, `def`, `if` / `elif` / `else`, `while`, `for` with `range()`, `break`, and `continue`. The game interprets these through Pondbot's board simulator. The Python executable is found on `PATH`. Set `FROG_GARDEN_PYTHON` to its full path if needed.

Use `hop(east)` to move one tile. The game provides `north`, `east`, `south`, and `west` as direction values. Use `has_water()` to check the tank. The tile tests `spring()`, `lily()`, `thirsty()`, `growing()`, and `ripe()` inspect the current tile by default. Pass a direction to inspect the neighboring tile, as in `lily(north)`. Use `clear(east)` before hopping into an unfamiliar tile. Combine tests with `not`, `and`, `or`, and parentheses.

In **Nursery beds**, sow a lily on a prepared brown bed with `plant()`. Test for a bed with `empty_bed()` or look ahead with `empty_bed(east)`. A new lily needs water before it can grow. The harvest target includes both seedbeds and lilies already planted.

**Switchback beds** opens at 26 earned lilies. Use the stop number in a `for` loop to choose which way to turn off the causeway. The Python starter tends the two west beds and remembers the spring column. Plan a refill and the mirrored east sweep to harvest all four lilies. The action target is 36.

**Open nursery** is a practice board that opens at 26 earned lilies. Harvested beds can be planted again. Its starter program uses `while True` to tend two rows until you pause or stop it. New runs start from the current position and crops. **Reset board** clears the board and returns Pondbot to the spring. **Check** previews up to 256 actions on a copy of the live board.

Each live harvest in a nursery adds one nursery lily to your saved balance. When Pondbot is stopped in Open nursery, spend **12 nursery lilies** to unlock **Willow nursery**. It has five renewable seedbeds and a gap in the south row. Extend the starter to tend both banks and keep earning lilies. Lesson unlocks use the lilies from first clears of scored puzzles.

After unlocking Willow nursery, spend **24 nursery lilies** on the reservoir upgrade. The next fill gives Pondbot six doses in every nursery. In Willow nursery, move `fill()` ahead of the two bank sweeps to tend all five beds on one fill. Scored lessons use a three-dose tank.

After fitting the reservoir, spend **32 nursery lilies** on the reach tool. It lets Pondbot plant or water an adjacent bed in the nurseries. A lily watered before a hop can ripen during the hop. Use `has_reach_tool()` to check availability in Python. Classic Pondbot uses commands such as `plant east` and `water east`.

```python
if has_reach_tool() and empty_bed(east) and has_water():
    plant(east)
    water(east)
    hop(east)
    gather()
```

Spend **40 nursery lilies** after buying the reach tool to unlock **Lotus marsh**. Its purple lotus beds need two water doses and ripen three actions after their final watering. A ripe lotus adds three nursery lilies to your balance. Tend the neighboring lily while the lotus ripens. The starter shows one pair, and a six-dose fill can cover both pairs for eight nursery lilies per circuit.

After opening Lotus marsh, spend **56 nursery lilies** on the harvest hook. Use `gather(direction)` from the neighboring tile when a crop is ripe. Check ownership with `has_harvest_hook()` in Python. Classic Pondbot uses commands such as `gather north`.

In Willow nursery, the center path gives Pondbot access to both banks. Tend each bed on the way out and gather on the way back. The same route also works in Lotus marsh.

```python
def tend(heading):
    if empty_bed(heading):
        plant(heading)
    while thirsty(heading):
        water(heading)

def collect(heading):
    if ripe(heading):
        gather(heading)

fill()
for _ in range(3):
    hop(east)
    tend(north)
    tend(south)

for _ in range(3):
    collect(north)
    collect(south)
    hop(west)
```

After buying the harvest hook, spend **72 nursery lilies** to unlock **Stone ring nursery**. Each bank has two lotus beds and two lily beds and needs a full six-dose tank. The starter tends one bank and stops at the opposite spring. Run it again to tend the next bank, or change its outer `if spring():` to `while spring():` in Python to keep circling. The first circuit plants and waters all eight beds. Each later circuit gathers **16 nursery lilies** and replants while staying on the path. If you stop mid-sweep, hop to either spring before starting the script again.

After unlocking Stone ring nursery, spend **96 nursery lilies** on **Speed control**. In any nursery, choose 1×, 2×, or 4× beside **Run**, or press **F8** to cycle through them. You can change speed during a run. Crops still ripen after the same number of actions, and **Step** and breakpoints work at every speed.

After fitting speed control, spend **128 nursery lilies** to unlock **Alder Crossing**. The south bank needs four doses and yields five lilies. The north bank needs six doses and yields eight. The Python and Classic starters work from either spring. They harvest the nearby bank and cross to the other spring. In Python, replace the final `if spring():` with `while spring() and harvest_count() < harvest_target():` to repeat the route, checking the target at each spring.

Use `harvest_count()` for lilies earned by the current program and `action_count()` for completed board actions. A new run starts both at zero even when the nursery already has crops. Pausing, stepping, or resuming an active run keeps its counts. A lotus adds three to the harvest count. Check and Review use their own preview counts. In Classic Pondbot, use `harvest_count` and `action_count` in comparisons.

Set **Harvest target** in a nursery and read it with `harvest_target()` in Python or `harvest_target` in Classic Pondbot. Each nursery remembers its own target. In Stone ring nursery, replace the starter's final `if spring():` with `while spring() and harvest_count() < harvest_target():` and keep its indented body. Change the field to reuse the code for a new quota. Pondbot checks the target at each spring, so it finishes the current bank before stopping. Scored lessons report the board's required harvest.

Nursery summaries show how many lilies the program gathered, how many actions it completed, whether it met the target, and how many water doses and fills it used. Check reports the preview. Run and Stop report the live program. In Review, scrub through the preview to see its water use and fills at each step. Every successful `fill()` counts, including top-ups.

For a nursery personal best, use **Reset board**, then complete a live program that meets the harvest target. Records compare runs with the same starting board, target, and nursery tools. Fewer actions win, followed by fewer water doses and fewer fills. **Check** shows the differences from the saved best when the preview reaches the same target from a reset board. Personal bests save locally across restarts. Open **Best program** to read the saved code and replay it from a fresh board. The live nursery and current draft stay available when you return. Choose **Edit a copy** to make a saved, editable copy in the recorded language. In the editor, choose **Duplicate draft** to save the code you’re editing as a new copy and open it. You can duplicate the main draft or any copy. Use the draft menu above the editor to switch between the main draft and copies. Choose **Rename** to name the selected copy, then press **Enter** or **Save name**. An empty name restores its numbered label. Each board and language remembers its selected draft when you return or restart. Choose **Compare drafts** to preview the current draft alongside a saved draft or your **Personal best** in the same language. Nursery bests match the current board, tools, and harvest target. Selecting one starts both previews from **Fresh nursery**. In the Source view, choose **Edit a copy** to edit the best program as a new draft. Both forecasts start from the same board. In nurseries, choose **Live nursery** to use the current beds and tank or **Fresh nursery** to preview a reset with your current tools and harvest target. Lessons always start fresh. The comparison shows harvest, actions, water use, and errors without running either draft on the board. Drag the shared slider or focus it and use **Left/Right** to see both routes at the same action count. Each preview shows its command, location, tank, and a board with the same symbols as the live garden. Gold outlines mark tiles where Pondbot or the plants differ between drafts. Select **First difference** to jump to the earliest different command, direction, or stopping point in the preview. Use **Previous** and **Next** to move between differences, or press **Page Up/Page Down** while the slider has focus. A shorter route holds its ending state. Nursery comparisons begin with a 256-action limit. **Extend preview** doubles the limit for both drafts up to 4,096 actions without moving the slider. The comparison remembers the extended limit for the session. Use the view menu below the previews to switch between **Boards** and **Source** at the selected action. Source shows both drafts side by side and marks the action or error line. Select **Edit current draft** or **Edit other draft** to open that draft at the preview cursor. Switching drafts saves your current edits. During the session, reopening **Compare drafts** restores the drafts, starting board choice, view, and action and refreshes both previews. If you edit the other draft, it becomes the left pane. If the new previews end sooner, the slider stops at the last available action. **Results** shows the lilies harvested, actions, water doses, and fills for both previews. Its target row shows the first action where each draft reaches the harvest goal. Select that action to move the shared slider there. In the **Totals at** menu, use **Selected action** to follow the slider or **First target action** to see each draft’s costs when it first reaches the goal. A draft that has yet to reach the goal has no totals in that mode. The difference column subtracts the current draft from the other draft. In **Selected action** mode, use the difference buttons to jump to changes in the totals. In Python comparisons, the menu also offers **Variables** and **Print output**. In Source, the difference buttons jump between different board actions and stopping points. In Variables and Print output, they jump between Python differences. Variables align by name and highlight different values or missing assignments in gold. Print output highlights different messages emitted at the selected action. The preview scrolls to the first highlighted line. Scroll the right sidebar to see the command guide on taller boards. Older score-only records gain code when matched or improved. For runs longer than 4,096 actions the replay shows the first 4,096, and the entire source stays available.

Use Python `print("Tank ready", has_water())` to show messages and sensor readings with their source line numbers. **Program output** shows the live run. **Check output** shows readings from the simulated board, and **Review** reveals those messages as you move through the actions. Printing costs no actions, and each view retains the latest 32 messages.

`water_level()` returns the remaining doses and `tank_capacity()` returns the tank's limit. `column()` counts from the left edge and `row()` counts from the top, both starting at zero. Print the readings with `print(column(), row(), water_level())` or compare them in a route. For example, use `while column() < 2 and clear(east):` with an indented `hop(east)` to move toward column 2. Use `spring() and water_level() < tank_capacity()` in an `if` before filling. Classic Pondbot uses comparisons such as `if water_level < tank_capacity`.

Save a numeric reading or a Boolean in a Python variable, such as `start = column()` or `had_water = has_water()`. Assign values with `=` and update counters with `+=` or `-=`. Assignments and named loop counters inside a function belong to that call. If a function assigns a name anywhere in its body, initialize that local value before reading it. Functions can read other variables from the main program. Run and Check each start with fresh variables, and Resume keeps the current values.

Press **F7** or choose **Variables** to inspect the current Python values. The panel labels local variables with their function name. **Check** shows the final simulated values. In **Review** and **Best program**, move the action slider to see which values the program had at each point. The initial position includes assignments made before Pondbot's first action.

Press **Shift+F7** or choose **Call stack** in the inspector to see the active Python functions, with the innermost call first. Each entry gives the line where that function was called, including functions with no local variables. In **Review** and **Best program**, the call stack follows the action slider. Press **F7** to return to variable values.

Double-click a call stack entry to open the call site in the source. From the open stack, press **Shift+F7** again to focus the list, then use **Up/Down** and **Enter**. **Esc** returns focus to the source. Opening a call site keeps the execution marker and replay position in place.

Select a call to see its local variables beside the stack. The selection follows that call as you step or scrub while it stays active. Press **F7** to see all active local values and top-level variables together.

Press **Ctrl+F7** or choose **Changes** in the inspector to see assignments, value changes, and locals that went out of scope after the last board action. **Check** shows the last previewed action. In **Review** and **Best program**, each slider position compares with the preceding action, so rewinding shows the same changes as stepping forward. Choose **Previous change** or **Next change** to skip unchanged actions. With the slider focused, use **Page Up/Page Down** to jump between changes or **Left/Right** to move one action at a time.

In a replay, choose a variable from **All variables** to filter the Changes list and jump only to changes for that name. Local names include their function, so you can follow a local independently of a top-level variable. The filter keeps your current action selected and returns to **All variables** if the next replay has no matching name.

Choose **History** beside a followed variable to see its starting value and every change. Double-click an entry to jump to that action, or press **Ctrl+Shift+F7** to focus History and use **Up/Down** and **Enter**. **Esc** returns focus to the timeline, and **Ctrl+F7** switches back to the changes for the current action.

Select a History entry and choose **Source line** or press **F12** with the list focused to open the Python line responsible for the change. Parameter assignments and scope exits point to the call site. This keeps the replay position and execution marker in place.

In **Review**, follow a variable and choose **Run to change** to start the draft on the live board. Pondbot pauses after the first completed action that changes the value, assigns it, or takes it out of scope. A change on the final action still lets the program finish normally. Earlier breakpoints pause before their commands, and **Resume** keeps watching. After a variable stop, **Resume** runs normally. **Step** cancels a pending stop. **Stop** and **Reset board** clear the followed variable from the live run.

Once a live run has a followed variable, choose **Next change** while paused to watch the same variable again from the current board. **Ctrl+Shift+Enter** works for both **Run to change** and **Next change**. You can step between stops and continue watching later in the same run.

During any paused Python run, open the inspector with **F7** and use **Watch** to choose a variable for **Next change**. **Ctrl+Shift+F7** focuses the Watch menu. Choosing a variable keeps the board paused and replaces the previous selection. Choose **Off** to clear it. A watched local stays available when it goes out of scope, so you can watch for its next assignment.

Use **Stop when** to choose **Equals**, **At least**, or **At most**, enter a value, then choose **Next match** or press **Ctrl+Shift+Enter**. **Equals** accepts a signed 32-bit integer or Python's `True` and `False`. **At least** and **At most** compare integers. Pondbot pauses when the condition becomes true after a board action. If it's already true when you resume, it must become false before it can trigger again.

To preview a condition, follow a variable in **Review** or **Best program** and set **Stop when** there. **Previous match**, **Next match**, and **Page Up/Page Down** jump to the actions that make the condition true. In **History**, turn on **Matches only** to list those actions. Press **Enter** on a match to jump to it, or **F12** to open its Python source line. Choose **Run to match** in Review to use the same condition on the live board.

After a live variable stop, choose **Source line** in the inspector or press **F12** from the editor to open the assignment or call site that triggered it. Pondbot stays paused at the next board command.

While paused inside a Python function, press **Shift+F11** in the editor to **Step out**. Pondbot finishes that call and pauses before the next board command so you can see the caller's variables and any returned value. If a breakpoint pauses the run before the function returns, choose **Resume** to continue stepping out. **Step**, **Stop**, and **Reset board** clear the request.

```python
start = column()
hops = 0
while hops < 2 and clear(east):
    hop(east)
    hops += 1
print("Started at", start, "and hopped", hops, "times")
```

Use `for bed in range(2):` to count from zero or `for bed in range(2, 0, -1):` to count down. A range takes up to 16 iterations, excludes its stop value, and reads its bounds once on entry. Bounds can come from variables or garden readings. Use `for _ in range(...):` when you just need repetition.

Define reusable functions above their first call. Functions can accept direction parameters, as in `def seek(heading):` with `hop(heading)` inside. `seek(north)` then uses north for that call. Use a bare `return` to end a function early and resume just after its call. The Python starter in **Low water row** uses it to end a sweep when the tank runs dry.

Use `int` for whole-number parameters and `bool` for parameters that accept `True` or `False`. Leave direction parameters unannotated. A call evaluates its inputs before running the function, so the same route can take a different direction, count, or sensor result each time.

```python
def walk(heading, count: int):
    for _ in range(count):
        if not clear(heading):
            return
        hop(heading)

walk(east, 2)
walk(west, 1)
```

To use a function's result, return a whole number or a Boolean and assign the call to a variable. A call used in an assignment must return a value on the path it takes. Here, `ready` stores the reading from `clear(east)`.

```python
def can_hop(heading):
    return clear(heading)

ready = can_hop(east)
if ready:
    hop(east)
```

`break` exits the innermost loop and `continue` advances it. A `while` loop stops with a line error if it repeats without an action or a change to a variable. Scored puzzles allow up to 16 iterations of each `while` loop and 256 board actions. Programs that keep computing without an action also have an instruction limit.

Each board has an action target and saves your fewest actions for a completed run. Open **Best program** to read and replay the source that earned the score. Use **Back to draft** or **Esc** to return to the editor. Select **Classic Pondbot** in the language menu to open an earlier draft written with commands such as `hop east` and `repeat 2`. The two formats have separate drafts and share each puzzle's score. Drafts, completed puzzles, and best programs save locally across restarts.

### Real-world maps

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
