"""Read-only public-source hygiene and local documentation checks."""
import json
from pathlib import Path
import re
import subprocess
from runtime_assets import MANIFEST,read_manifest,verify

ROOT=Path(__file__).resolve().parents[1]
EXCLUDED={".git",".godot",".local","state","tools","outputs","backups","__pycache__",".pytest_cache","build","install","log"}


def main():
    files=subprocess.check_output(["git","ls-files","--cached","--others","--exclude-standard"],cwd=ROOT,text=True).splitlines()
    errors=[]
    bundled=set()
    if (ROOT/MANIFEST).is_file():
        try:
            bundled={'game/'+entry['path'] for entry in read_manifest(ROOT)['files']}
            verify(ROOT)
        except (ValueError,OSError,KeyError) as error:errors.append('Runtime inventory: '+str(error))
    for name in files:
        path=ROOT/name
        if not path.is_file():continue
        if EXCLUDED.intersection(Path(name).parts):errors.append("Generated/private path: "+name)
        if name.startswith(("game/assets/frogs/","game/assets/worlds/")) and path.name!="README.md" and name not in bundled:errors.append("Unreviewed asset in Git candidates: "+name)
        if path.stat().st_size>10*1024*1024 and name not in bundled:errors.append("Large file in source repository: "+name)
        if path.suffix in [".py",".gd",".gdshader",".ps1",".sh",".md",".json",".txt",".xml"] or path.name in ["LICENSE",".gitignore",".gitattributes",".editorconfig"]:
            raw=path.read_bytes()
            try:text=raw.decode("utf-8")
            except UnicodeDecodeError:errors.append("Not UTF-8: "+name);continue
            if raw.startswith(b"\xef\xbb\xbf") or b"\r" in raw or not raw.endswith(b"\n") or raw.endswith(b"\n\n"):errors.append("Text convention: "+name)
            if re.search(r"C:[/\\](?:Users[/\\]|~LocalWork[/\\]|dev[/\\]FrogExplorer)",text,re.I):errors.append("Machine path: "+name)
            if re.search(r"(?:ghp_|github_pat_)[A-Za-z0-9_]{25,}|-----BEGIN (?:RSA |OPENSSH )?PRIVATE KEY-----",text):errors.append("Possible secret: "+name)
    readme=(ROOT/"README.md").read_text(encoding="utf-8")
    headings=re.findall(r"^## (.+)$",readme,re.M);required=["Install","Usage","Maintainers","Contributing","License"]
    if [h for h in headings if h in required]!=required:errors.append("Standard Readme section order")
    for target in re.findall(r"\]\(([^)]+)\)",readme):
        if target.startswith(("https://","http://","#")):continue
        if not (ROOT/target.split("#")[0]).exists():errors.append("README broken local link: "+target)
    catalog=json.loads((ROOT/"game/data/travel_places.json").read_bytes())
    if len({p["id"] for p in catalog["places"]})!=len(catalog["places"]):errors.append("Duplicate catalog IDs")
    print(json.dumps({"ok":not errors,"candidate_files":len(files),"errors":errors},indent=2))
    if errors:raise SystemExit(1)


if __name__=="__main__":main()
