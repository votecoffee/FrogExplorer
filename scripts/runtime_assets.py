"""Validate the explicit, redistributable runtime asset inventory."""
import hashlib
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
MANIFEST='config/runtime_assets.lock.json'
MAX_FILE=100*1024*1024


def asset_path(root,relative):
    if not isinstance(relative,str) or ':' in relative or '\\' in relative or '..' in relative.split('/') or not relative.startswith(('assets/worlds/','assets/frogs/')):
        raise ValueError('Unsafe runtime asset path: '+str(relative))
    path=(Path(root)/'game'/relative).resolve()
    if not path.is_relative_to((Path(root)/'game').resolve()):raise ValueError('Runtime asset escapes game root')
    return path


def read_manifest(root=ROOT):
    data=json.loads((Path(root)/MANIFEST).read_bytes())
    if data.get('version')!=1 or not isinstance(data.get('files'),list):raise ValueError('Invalid runtime inventory')
    seen=set()
    for entry in data['files']:
        asset_path(root,entry['path'])
        if entry['path'] in seen:raise ValueError('Duplicate runtime asset: '+entry['path'])
        seen.add(entry['path'])
        if not isinstance(entry.get('size'),int) or not 0<entry['size']<MAX_FILE:raise ValueError('Runtime file exceeds ordinary Git size limit')
        if not isinstance(entry.get('sha256'),str) or len(entry['sha256'])!=64:raise ValueError('Missing runtime checksum')
    return data


def verify(root=ROOT):
    data=read_manifest(root)
    for entry in data['files']:
        path=asset_path(root,entry['path'])
        if not path.is_file() or path.stat().st_size!=entry['size']:raise ValueError('Missing or different runtime asset: '+entry['path'])
        digest=hashlib.sha256()
        with path.open('rb') as file:
            for block in iter(lambda:file.read(1024*1024),b''):digest.update(block)
        if digest.hexdigest()!=entry['sha256']:raise ValueError('Runtime checksum mismatch: '+entry['path'])
    return {'files':len(data['files']),'bytes':sum(e['size'] for e in data['files']),'worlds':len(data['worlds']),'frogs':len(data['frogs'])}


if __name__=='__main__':print(json.dumps(verify(),indent=2))
