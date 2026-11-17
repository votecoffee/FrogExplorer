"""Project-local installer for Windows x64, Linux x64 and Linux ARM64."""
import argparse
import json
import os
from pathlib import Path
import platform
import shutil
import stat
import subprocess
import tempfile
import urllib.request
import zipfile

from manage_assets import import_assets,sha256,safe_path
from runtime_assets import verify as verify_runtime

ROOT=Path(__file__).resolve().parents[1]


def platform_key():
    system=platform.system().lower();machine=platform.machine().lower()
    architecture="arm64" if machine in ("arm64","aarch64") else "x86_64" if machine in ("amd64","x86_64") else machine
    return system+"-"+architecture


def unpack(archive,destination):
    with zipfile.ZipFile(archive) as zipped:
        for item in zipped.infolist():
            safe_path(destination,item.filename.rstrip("/"))
            if stat.S_ISLNK(item.external_attr>>16):raise ValueError("Archive symlinks are not accepted")
        zipped.extractall(destination)


def install_engine(root,key,skip_download=False):
    manifest=json.loads((root/"config/godot.json").read_bytes())
    if key not in manifest["releases"]:raise ValueError("No pinned Godot archive for "+key+"; pass --godot with a suitable Godot 4.7+ executable")
    entry=manifest["releases"][key];destination=safe_path(root,"tools/godot");engine=destination/entry["executable"]
    if engine.is_file():return engine
    if skip_download:raise ValueError("Godot is missing. Supply --godot or allow the pinned official download")
    cache=safe_path(root,"tools/downloads");cache.mkdir(parents=True,exist_ok=True);archive=safe_path(cache,entry["file"])
    if not archive.is_file() or sha256(archive)!=entry["sha256"]:
        url="https://github.com/godotengine/godot-builds/releases/download/"+manifest["version"]+"/"+entry["file"]
        temporary=archive.with_suffix(".part")
        print("Downloading official Godot",manifest["version"],"for",key,flush=True)
        request=urllib.request.Request(url,headers={"User-Agent":"FrogExplorer-installer"})
        with urllib.request.urlopen(request,timeout=120) as response,temporary.open("wb") as output:shutil.copyfileobj(response,output)
        if sha256(temporary)!=entry["sha256"]:raise ValueError("Godot download checksum mismatch; archive was not installed")
        temporary.replace(archive)
    with tempfile.TemporaryDirectory(prefix="godot-",dir=cache) as staging:
        stage=Path(staging).resolve()
        if not stage.is_relative_to(cache.resolve()):raise ValueError("Engine staging directory escaped the project cache")
        unpack(archive,stage)
        if not (stage/entry["executable"]).is_file():raise ValueError("Official archive does not contain the expected executable")
        destination.mkdir(parents=True,exist_ok=True)
        entries=list(stage.iterdir())
        for file in entries:
            if (destination/file.name).exists():raise ValueError("Preserving an existing engine file: "+str(destination/file.name))
        for file in entries:shutil.move(str(file),destination/file.name)
    if os.name!="nt":engine.chmod(0o755)
    return engine


def validate_engine(engine):
    text=subprocess.check_output([str(engine),"--version"],text=True).strip()
    numbers=text.split(".")
    if len(numbers)<2 or not numbers[0].isdigit() or not numbers[1].isdigit() or (int(numbers[0]),int(numbers[1]))<(4,7):
        raise ValueError("Godot 4.7 or newer is required; executable reports "+text)
    return text


def logged(command,path,environment=None):
    path.parent.mkdir(parents=True,exist_ok=True)
    with path.open("wb") as log:result=subprocess.run([str(p) for p in command],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,env=environment)
    contents=path.read_bytes().decode("utf-8",errors="replace")
    if result.returncode or any(token in contents for token in ("SCRIPT ERROR:","ERROR:","Parse Error")):
        raise RuntimeError("Command failed; see "+str(path))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot",type=Path);parser.add_argument("--skip-download",action="store_true")
    parser.add_argument("--asset-source",type=Path);parser.add_argument("--ros-prefix",type=Path);parser.add_argument("--ros-python",type=Path)
    parser.add_argument("--with-ros",action="store_true");parser.add_argument("--build-ros",action="store_true");parser.add_argument("--test",action="store_true")
    args=parser.parse_args();local=ROOT/".local";local.mkdir(exist_ok=True);path=local/"settings.json"
    settings=json.loads(path.read_bytes()) if path.exists() else {}
    supplied=args.godot or os.environ.get("GODOT_BIN") or settings.get("godot")
    engine=Path(supplied).expanduser().resolve() if supplied else install_engine(ROOT,platform_key(),args.skip_download)
    version=validate_engine(engine);settings["godot"]=str(engine);settings.setdefault("use_ros",False)
    if args.ros_prefix:settings["ros_prefix"]=str(args.ros_prefix.resolve())
    if args.ros_python:settings["ros_python"]=str(args.ros_python.resolve())
    if args.with_ros or args.build_ros:
        prefix=settings.get("ros_prefix") or os.environ.get("ROS_PREFIX") or ("/opt/ros/lyrical" if os.name!="nt" else "")
        setup=Path(prefix)/("local_setup.ps1" if os.name=="nt" else "setup.bash")
        if not prefix or not setup.is_file():raise ValueError("Install ROS 2 Lyrical separately, then supply --ros-prefix with its existing underlay")
        settings["ros_prefix"]=str(Path(prefix).resolve());settings["use_ros"]=True
    if args.asset_source:print("Imported",import_assets(ROOT,args.asset_source),"verified optional asset files",flush=True)
    if (ROOT/'config/runtime_assets.lock.json').is_file():print('Verified bundled runtime assets:',verify_runtime(ROOT),flush=True)
    path.write_bytes((json.dumps(settings,indent=2)+"\n").encode("utf-8"))
    logged([engine,"--headless","--editor","--path",ROOT/"game","--import"],ROOT/"state/import.log")
    if args.build_ros:
        command=["powershell.exe","-NoProfile","-ExecutionPolicy","Bypass","-File",ROOT/"scripts/build_windows.ps1"] if os.name=="nt" else ["bash",ROOT/"scripts/build_linux.sh"]
        if args.test and os.name=="nt":command.append("-Test")
        env=os.environ.copy();env["ROS_PREFIX"]=settings["ros_prefix"];env["GODOT_BIN"]=str(engine)
        logged(command,ROOT/"state/build.log",env)
    if args.test:logged([engine,"--headless","--path",ROOT/"game","--","--smoke","--test-session","--no-ros"],ROOT/"state/install-smoke.log")
    print("Installed FrogExplorer with Godot",version)
    print("Run Start-FrogExplorer.cmd" if os.name=="nt" else "Run bash scripts/run_linux.sh")
    print("Settings: .local/settings.json; logs: state/. Realistic frogs/worlds are optional local imports.")


if __name__=="__main__":main()
