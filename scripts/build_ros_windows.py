"""Build a Windows ROS overlay, including when sources and outputs use different drives."""

import argparse
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
from tempfile import TemporaryDirectory


ROOT = Path(__file__).resolve().parents[1]


def link_game(source, stage):
    source = source.resolve(strict=True)
    link = stage / "game"
    environment = os.environ | {"FROGEXPLORER_GAME_SOURCE": str(source)}
    try:
        result = subprocess.run(
            ["powershell.exe", "-NoProfile", "-NonInteractive", "-Command",
             "$ErrorActionPreference='Stop'; New-Item -Path . -Name game "
             "-ItemType Junction -Target "
             "([System.Management.Automation.WildcardPattern]::Escape($env:FROGEXPLORER_GAME_SOURCE)) | Out-Null"],
            cwd=stage, env=environment, capture_output=True,
        )
    except FileNotFoundError:
        return False

    if result.returncode and not os.path.lexists(link):
        return False
    if (link.lstat().st_reparse_tag != stat.IO_REPARSE_TAG_MOUNT_POINT
            or link.resolve(strict=True) != source):
        raise RuntimeError(f"Unexpected game directory created in ROS build staging: {link}")
    return True


def stage_game(root, stage):
    if link_game(root / "game", stage):
        # TemporaryDirectory removes the junction entry on Windows without
        # traversing the source game. Colcon installs regular asset copies.
        print("Reading game assets through a temporary Windows junction.", flush=True)
        return

    print("Windows junction unavailable. Staging selected game assets.", flush=True)
    # Use the same asset selection as setup.py so the temporary source tree
    # includes the runtime tiles and excludes old authoring caches.
    sys.path.insert(0, str(root / "ros2_ws/src/frog_explorer"))
    try:
        from frog_explorer.asset_files import game_files
    finally:
        sys.path.pop(0)

    assets = game_files(root / "game")
    for parent in {asset.parent for asset in assets}:
        (stage / parent.relative_to(root)).mkdir(parents=True, exist_ok=True)
    for asset in assets:
        shutil.copy2(asset, stage / asset.relative_to(root))


def stage_inputs(root, stage):
    source = root / "ros2_ws/src"
    staged_source = stage / "ros2_ws/src"
    shutil.copytree(source, staged_source, ignore=shutil.ignore_patterns("__pycache__", "*.pyc", ".pytest_cache"))
    for name in ("README.md", "LICENSE", "ASSET_CREDITS.md"):
        shutil.copy2(root / name, stage / name)
    stage_game(root, stage)
    return staged_source


def colcon(workspace, source, test):
    command = [sys.executable, "-m", "colcon"]
    options = ["--base-paths", str(source), "--merge-install", "--event-handlers", "console_direct+"]
    subprocess.run([*command, "build", *options], cwd=workspace, check=True)
    if test:
        subprocess.run([*command, "test", *options], cwd=workspace, check=True)
        subprocess.run([*command, "test-result", "--verbose"], cwd=workspace, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("workspace", type=Path)
    parser.add_argument("--test", action="store_true")
    args = parser.parse_args()
    workspace = args.workspace.resolve()
    workspace.mkdir(parents=True, exist_ok=True)
    if workspace.drive.casefold() == ROOT.drive.casefold():
        colcon(workspace, ROOT / "ros2_ws/src", args.test)
    else:
        # The Windows ament_python build computes relative paths between
        # setup.py and the build directory. Use a source snapshot on its drive.
        with TemporaryDirectory(prefix=".frogexplorer-source-", dir=workspace) as directory:
            stage = Path(directory).resolve()
            if stage.parent != workspace:
                raise ValueError("Staging directory escaped the ROS workspace")
            print(f"Staging ROS build inputs on {workspace.drive}", flush=True)
            colcon(workspace, stage_inputs(ROOT, stage), args.test)


if __name__ == "__main__":
    main()
