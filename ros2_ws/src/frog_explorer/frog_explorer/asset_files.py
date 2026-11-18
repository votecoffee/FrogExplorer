"""Select game runtime inputs, leaving original/obsolete local caches behind."""
import json
import os
from pathlib import Path


def game_files(game):
    game=Path(game);selected=set()
    catalog=json.loads((game/'data/travel_places.json').read_bytes())
    for place in catalog['places']:
        if place.get('provider')!='local_mesh':continue
        manifest=place.get('tile_manifest','').removeprefix('res://');pack=game/manifest
        if manifest and pack.is_file():
            selected.add(pack)
            for relative in json.loads(pack.read_bytes())['files']:
                if Path(relative).is_absolute() or ':' in relative or '\\' in relative or '..' in relative.split('/'):raise ValueError('Unsafe tile dependency')
                path=pack.parent/relative
                if not path.is_file():raise ValueError('Missing tile dependency: '+str(path))
                selected.add(path)
        else:
            path=game/place['scene'].removeprefix('res://')
            if path.is_file():selected.add(path)
    selected.update((game/'assets/frogs').glob('*.glb'))
    # Authoring caches can contain tens of thousands of municipal source parts.
    # Prune them before walking, rather than statting every excluded file.
    for directory,children,files in os.walk(game):
        folder=Path(directory)
        children[:]=[name for name in children if name!='.godot' and (folder/name).relative_to(game).as_posix() not in ['assets/worlds','assets/frogs']]
        for name in files:
            path=folder/name
            if path.suffix not in ['.tmp','.import'] and path.is_file():selected.add(path)
    for folder in ['assets/worlds','assets/frogs']:
        readme=game/folder/'README.md'
        if readme.is_file():selected.add(readme)
    return sorted(selected)
