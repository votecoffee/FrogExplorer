"""Read one non-secret local launcher setting without shell evaluation."""
import json
from pathlib import Path
import sys
path=Path(__file__).resolve().parents[1]/'.local/settings.json'
settings=json.loads(path.read_bytes()) if path.exists() else {}
value=settings.get(sys.argv[1], '')
print(str(value).lower() if isinstance(value,bool) else value)
