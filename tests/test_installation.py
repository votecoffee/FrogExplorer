"""Installer boundary checks use synthetic tiny assets, never private models."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

SCRIPTS=Path(__file__).resolve().parents[1]/"scripts"
sys.path.insert(0,str(SCRIPTS))
from manage_assets import import_assets,safe_path
import bootstrap
from bootstrap import unpack,platform_key
from build_ros_windows import link_game, stage_game
from prepare_windows_game import cache_is_current


class AssetImportTests(unittest.TestCase):
    def setUp(self):
        self.temporary=tempfile.TemporaryDirectory();self.root=Path(self.temporary.name)
        self.source=self.root/"source/game";self.target=self.root/"checkout";self.target.mkdir()
        self.asset=self.source/"assets/frogs/example.glb";self.asset.parent.mkdir(parents=True);self.asset.write_bytes(b"synthetic-asset")
        self.manifest={"files":[{"path":"assets/frogs/example.glb","size":15,"sha256":hashlib.sha256(b"synthetic-asset").hexdigest()}]}

    def tearDown(self):self.temporary.cleanup()

    def test_import_accepts_project_root_and_is_repeatable(self):
        self.assertEqual(import_assets(self.target,self.source.parent,self.manifest),1)
        self.assertEqual(import_assets(self.target,self.source,self.manifest),1)
        self.assertEqual((self.target/"game/assets/frogs/example.glb").read_bytes(),b"synthetic-asset")
        self.assertEqual(json.loads((self.target/".local/assets.json").read_bytes())["files"],1)

    def test_preflight_failure_copies_no_files(self):
        self.manifest["files"].append({"path":"assets/worlds/missing.glb","size":1,"sha256":"bad"})
        with self.assertRaisesRegex(ValueError,"No assets were copied"):import_assets(self.target,self.source,self.manifest)
        self.assertFalse((self.target/"game").exists())

    def test_same_length_corruption_is_rejected(self):
        self.asset.write_bytes(b"corrupted-asset")
        with self.assertRaises(ValueError):import_assets(self.target,self.source,self.manifest)
        self.assertFalse((self.target/"game").exists())

    def test_existing_different_destination_is_preserved(self):
        destination=self.target/"game/assets/frogs/example.glb";destination.parent.mkdir(parents=True);destination.write_bytes(b"mine")
        with self.assertRaisesRegex(ValueError,"preserve"):import_assets(self.target,self.source,self.manifest)
        self.assertEqual(destination.read_bytes(),b"mine")

    def test_unsafe_manifest_paths_are_rejected(self):
        for relative in ["../outside","/outside","assets/frogs/../../../outside","assets\\frogs\\outside","C:/outside"]:
            with self.subTest(relative=relative),self.assertRaises(ValueError):safe_path(self.target,relative)

    def test_unexpected_asset_category_is_rejected(self):
        self.manifest["files"][0]["path"]="scripts/injected.py"
        with self.assertRaisesRegex(ValueError,"category"):import_assets(self.target,self.source,self.manifest)


class ArchiveTests(unittest.TestCase):
    def test_safe_archive_extracts(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);archive=root/"engine.zip"
            with zipfile.ZipFile(archive,"w") as output:output.writestr("engine",b"test")
            unpack(archive,root/"unpack")
            self.assertEqual((root/"unpack/engine").read_bytes(),b"test")

    def test_archive_escape_is_rejected_before_extraction(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);archive=root/"engine.zip"
            with zipfile.ZipFile(archive,"w") as output:
                output.writestr("valid",b"safe");output.writestr("../escape",b"bad")
            with self.assertRaises(ValueError):unpack(archive,root/"unpack")
            self.assertFalse((root/"unpack/valid").exists());self.assertFalse((root/"escape").exists())


class WorkspaceSettingsTests(unittest.TestCase):
    def test_configured_ros_workspace_survives_a_later_install(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "checkout"
            root.mkdir()
            workspace = Path(directory) / "external workspace"
            engine = root / "godot"
            command = ["bootstrap.py", "--godot", str(engine)]
            prefix = root / "lyrical"
            prefix.mkdir()
            windows = sys.platform == "win32"
            (prefix / ("local_setup.ps1" if windows else "setup.bash")).touch()
            with (
                patch.object(bootstrap, "ROOT", root),
                patch.object(bootstrap, "logged") as logged,
                patch.object(bootstrap, "validate_engine", return_value="4.7"),
                patch("builtins.print"),
            ):
                with patch.object(
                    sys, "argv", [*command, "--ros-prefix", str(prefix), "--ros-workspace", str(workspace)]
                ):
                    bootstrap.main()
                with patch.object(sys, "argv", [*command, "--build-ros", "--test"]):
                    bootstrap.main()
            build_command = next(
                call.args[0] for call in logged.call_args_list if call.args[1].name == "build.log"
            )
            if windows:
                self.assertEqual(build_command[-3:], ["-RosWorkspace", str(workspace.resolve()), "-Test"])
            settings = json.loads((root / ".local/settings.json").read_bytes())
            self.assertEqual(settings["ros_workspace"], str(workspace.resolve()))

    @unittest.skipUnless(sys.platform == "win32", "requires Windows PowerShell")
    def test_direct_build_defaults_to_checkout_and_accepts_workspace_override(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve() / "checkout"
            scripts = root / "scripts"
            scripts.mkdir(parents=True)
            for name in ("build_windows.ps1", "project_paths.ps1"):
                (scripts / name).write_bytes((SCRIPTS / name).read_bytes())

            # Keep the real PowerShell path resolution and record the Python
            # entrypoint arguments without requiring a ROS underlay.
            executable = sys.executable.replace("'", "''")
            (scripts / "environment.ps1").write_bytes(
                ("param([int]$DomainId,[string]$RosPrefix)\n"
                 '. "$PSScriptRoot\\project_paths.ps1"\n'
                 f"$RosPython='{executable}'\n").encode("utf-8")
            )
            (scripts / "build_ros_windows.py").write_bytes(
                b"import json, sys\nprint(json.dumps(sys.argv[1:]))\n"
            )

            settings = root / ".local/settings.json"
            settings.parent.mkdir()
            original = json.dumps({"ros_workspace": str(root / "saved workspace")}).encode("utf-8")
            settings.write_bytes(original)
            command = [
                "powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
                "-File", str(scripts / "build_windows.ps1"), "-Test",
            ]
            external = root.parent / "external workspace"
            for options, expected in (
                ([], root / "ros2_ws"),
                (["-RosWorkspace", str(external)], external),
                (["-RosWorkspace", "local output"], root / "local output"),
            ):
                with self.subTest(options=options):
                    output = subprocess.run(
                        [*command, *options], cwd=directory, capture_output=True, text=True, check=True,
                    )
                    self.assertEqual(json.loads(output.stdout.splitlines()[-1]), [str(expected), "--test"])

            self.assertEqual(settings.read_bytes(), original)


class WindowsLaunchImportTests(unittest.TestCase):
    def test_warm_base_imports_are_reused_until_an_input_or_output_changes(self):
        with tempfile.TemporaryDirectory() as directory:
            game = Path(directory)
            engine = game / "godot.exe"
            project = game / "project.godot"
            asset = game / "frog.glb"
            sidecar = game / "frog.glb.import"
            output = game / ".godot/imported/frog.scn"
            uid = game / ".godot/uid_cache.bin"
            classes = game / ".godot/global_script_class_cache.cfg"
            scan = game / ".godot/editor/filesystem_cache10"
            files = {
                engine: "engine", project: "project", asset: "model", output: "scene",
                sidecar: 'dest_files=["res://.godot/imported/frog.scn"]\n',
                uid: "uids", classes: "list=Array[Dictionary]([])", scan: "filesystem scan",
            }
            timestamp = 1_790_000_000
            for path, value in files.items():
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(value, encoding="utf-8")
                os.utime(path, (timestamp, timestamp))
            self.assertTrue(cache_is_current(engine, game, [asset]))
            for changed in (engine, project, asset, sidecar):
                with self.subTest(changed=changed.name):
                    os.utime(changed, (timestamp + 10, timestamp + 10))
                    self.assertFalse(cache_is_current(engine, game, [asset]))
                    os.utime(changed, (timestamp, timestamp))
            script = game / "scripts/player.gd"
            script.parent.mkdir()
            script.write_text("class_name FrogPlayer\nextends Node\n", encoding="utf-8")
            self.assertFalse(cache_is_current(engine, game, [asset]))
            classes.write_text(
                'list=Array[Dictionary]([{"class": &"FrogPlayer", "path": "res://scripts/player.gd"}])',
                encoding="utf-8",
            )
            self.assertTrue(cache_is_current(engine, game, [asset]))
            output.unlink()
            self.assertFalse(cache_is_current(engine, game, [asset]))


class WindowsStageTests(unittest.TestCase):
    @unittest.skipUnless(sys.platform == "win32", "requires Windows junctions")
    def test_stage_cleanup_leaves_the_game_source_intact(self):
        with tempfile.TemporaryDirectory() as directory:
            workspace = Path(directory)
            game = workspace / "source [with spaces]" / "game"
            game.mkdir(parents=True)
            asset = game / "source.glb"
            asset.write_bytes(b"original game asset")

            with tempfile.TemporaryDirectory(dir=workspace, prefix="staging area ") as stage_directory:
                stage = Path(stage_directory)
                if not link_game(game, stage):
                    self.skipTest("test volume does not support directory junctions")
                self.assertTrue((stage / "game/source.glb").samefile(asset))

            self.assertFalse(stage.exists())
            self.assertEqual(asset.read_bytes(), b"original game asset")

    def test_stage_copies_runtime_assets_when_a_junction_is_unavailable(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "checkout"
            stage = Path(directory) / "stage"
            module = Path("ros2_ws/src/frog_explorer/frog_explorer/asset_files.py")
            files = {
                module: (SCRIPTS.parent / module).read_bytes(),
                Path("game/data/travel_places.json"): b'{"places":[]}',
                Path("game/assets/frogs/kept.glb"): b"runtime asset",
                Path("game/assets/worlds/unused.glb"): b"old cache",
            }
            for relative, contents in files.items():
                (root / relative).parent.mkdir(parents=True, exist_ok=True)
                (root / relative).write_bytes(contents)

            with patch("build_ros_windows.link_game", return_value=False), patch("builtins.print"):
                stage_game(root, stage)

            self.assertEqual((stage / "game/assets/frogs/kept.glb").read_bytes(), b"runtime asset")
            self.assertFalse((stage / "game/assets/worlds").exists())


if __name__=="__main__":unittest.main()
