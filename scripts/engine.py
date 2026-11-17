"""Resolve the installed engine without assuming an operating system or checkout."""
import json
import os
from pathlib import Path
import shutil


def resolve_engine(root):
    settings=Path(root)/".local/settings.json"
    config=json.loads(settings.read_bytes()) if settings.exists() else {}
    executable=os.environ.get("GODOT_BIN") or config.get("godot") or shutil.which("godot4") or shutil.which("godot")
    if not executable:raise RuntimeError("Run the installer or set GODOT_BIN before running game checks")
    return str(executable)
