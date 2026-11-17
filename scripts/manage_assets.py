"""Import an existing reference asset set locally, verifying before any copy."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil

ROOT=Path(__file__).resolve().parents[1]


def sha256(path):
    digest=hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda:stream.read(1024*1024),b""):digest.update(chunk)
    return digest.hexdigest()


def safe_path(root,relative):
    if not relative or "\\" in relative or ":" in relative or Path(relative).is_absolute() or ".." in Path(relative).parts:
        raise ValueError("Unsafe asset path: "+relative)
    path=(root/relative).resolve()
    if not path.is_relative_to(root.resolve()):raise ValueError("Asset escapes root: "+relative)
    return path


def import_assets(project,source,manifest=None):
    project=Path(project).resolve();source=Path(source).resolve()
    if not (project/"game").resolve().is_relative_to(project):raise ValueError("Destination game directory escapes the project")
    manifest=manifest or json.loads((project/"config/assets.lock.json").read_bytes())
    roots=[source/"game",source,source.parent]
    origin=next((p for p in roots if (p/"assets/frogs").is_dir()),None)
    if origin is None:raise ValueError("AssetSource must be an existing project, its game folder, or its game/assets folder")
    pairs=[]
    for entry in manifest["files"]:
        relative=entry["path"]
        if not relative.startswith(("assets/frogs/","assets/worlds/")):raise ValueError("Unexpected asset category: "+relative)
        src=safe_path(origin,relative);dst=safe_path(project/"game",relative)
        if not src.is_file() or src.stat().st_size!=entry["size"] or sha256(src)!=entry["sha256"]:
            raise ValueError("Missing or different reference asset: "+relative+". No assets were copied.")
        if dst.exists() and sha256(dst)!=entry["sha256"]:
            raise ValueError("Existing destination differs; preserve it before importing: "+str(dst))
        pairs.append((src,dst))
    # Preflight every file before creating anything in the asset directories.
    for src,dst in pairs:
        if src==dst or dst.exists():continue
        dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dst)
        if sha256(dst)!=sha256(src):raise OSError("Copy verification failed: "+str(dst))
    local=project/".local";local.mkdir(parents=True,exist_ok=True)
    (local/"assets.json").write_bytes((json.dumps({"source":str(origin),"files":len(pairs),"manifest_sha256":hashlib.sha256(json.dumps(manifest,sort_keys=True).encode()).hexdigest()},indent=2)+"\n").encode("utf-8"))
    return len(pairs)


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("source",type=Path);args=parser.parse_args()
    print("Verified and imported",import_assets(ROOT,args.source),"optional asset files into ignored folders.")


if __name__=="__main__":main()
