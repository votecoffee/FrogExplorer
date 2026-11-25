"""Reuse Godot's existing base game imports when starting FrogExplorer."""
import argparse
import json
from pathlib import Path
import re

from runtime_assets import MANIFEST, ROOT
from wait_engine import run_engine


IMPORTABLE = {".glb", ".gltf", ".jpg", ".jpeg", ".png", ".svg", ".wav", ".ogg"}
IMPORT_PREFIX = "res://.godot/imported/"


def base_assets(project):
    inventory = json.loads((ROOT / MANIFEST).read_bytes())
    bundled = [project / entry["path"] for entry in inventory["files"]]
    for folder in ("audio", "rides"):
        bundled.extend((project / "assets" / folder).glob("*"))
    # Godot extracts these textures when it imports the bundled frog GLBs.
    bundled.extend((project / "assets/frogs").glob("*.png"))
    return sorted({path for path in bundled if path.suffix.lower() in IMPORTABLE})


def current_import(project, source, scanned_at):
    sidecar = source.with_name(source.name + ".import")
    if max(source.stat().st_mtime_ns, sidecar.stat().st_mtime_ns) > scanned_at:
        return False
    match = re.search(r"^dest_files=(.+)$", sidecar.read_text(encoding="utf-8"), re.MULTILINE)
    if not match:
        return False
    outputs = json.loads(match[1])
    if not isinstance(outputs, list) or not outputs:
        return False
    for output in outputs:
        if not isinstance(output, str) or not output.startswith(IMPORT_PREFIX):
            return False
        name = output.removeprefix(IMPORT_PREFIX)
        if not name or name in {".", ".."} or any(character in name for character in "/\\:"):
            return False
        imported = project / ".godot" / "imported" / name
        if not imported.is_file() or imported.stat().st_size == 0:
            return False
    return True


def current_classes(project, cache_file):
    # Body edits can run without an editor scan. A new, renamed or moved
    # global class needs Godot to refresh its generated class index.
    expected = set()
    for script in (project / "scripts").rglob("*.gd"):
        match = re.search(r"^class_name\s+(\w+)", script.read_text(encoding="utf-8"), re.MULTILINE)
        if match:
            expected.add((match[1], "res://" + script.relative_to(project).as_posix()))
    cache = cache_file.read_text(encoding="utf-8")
    entries = set(re.findall(r'"class":\s*&?"([^"]+)"[^}]*"path":\s*"([^"]+)"', cache))
    return entries == expected


def cache_is_current(engine, project, assets):
    cache = project / ".godot"
    try:
        scans = (cache / "editor").glob("filesystem_cache*")
        scanned_at = max(
            (scan.stat().st_mtime_ns for scan in scans if scan.name.removeprefix("filesystem_cache").isdigit()),
            default=0,
        )
        if scanned_at < max(engine.stat().st_mtime_ns, (project / "project.godot").stat().st_mtime_ns):
            return False
        return (
            (cache / "uid_cache.bin").stat().st_size > 0
            and current_classes(project, cache / "global_script_class_cache.cfg")
            and all(current_import(project, asset, scanned_at) for asset in assets)
        )
    except (OSError, ValueError):
        return False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("engine", type=Path)
    parser.add_argument("project", type=Path)
    parser.add_argument("log", type=Path)
    parser.add_argument("--import-assets", action="store_true")
    args = parser.parse_args()
    if not args.import_assets and cache_is_current(args.engine, args.project, base_assets(args.project)):
        return 0
    print(f"Importing Godot assets. Progress is logged in {args.log}", flush=True)
    return run_engine(
        [str(args.engine), "--headless", "--editor", "--path", str(args.project), "--import"], args.log,
    )


if __name__ == "__main__":
    raise SystemExit(main())
