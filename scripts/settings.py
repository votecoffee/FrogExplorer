"""Read one non-secret local launcher setting without shell evaluation."""
import json
from pathlib import Path
import sys
path=Path(__file__).resolve().parents[1]/'.local/settings.json'
settings=json.loads(path.read_bytes()) if path.exists() else {}
key=sys.argv[1]
value=settings.get(key, '')
if key == 'ros_workspace' and value:
    value = str((path.parents[1] / Path(value).expanduser()).resolve())
print(str(value).lower() if isinstance(value,bool) else value)
