"""Select game runtime inputs, leaving original/obsolete local caches behind."""
import json
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
    for path in game.rglob('*'):
        if not path.is_file() or '.godot' in path.parts or path.suffix in ['.tmp','.import']:continue
        relative=path.relative_to(game).as_posix()
        if relative.startswith(('assets/worlds/','assets/frogs/')) and path.name!='README.md':continue
        selected.add(path)
    return sorted(selected)
