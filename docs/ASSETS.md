# Runtime assets and optional source files

The public game includes five realistic frog GLBs and all 16 runtime world tile packs, alongside starter frogs, vehicles, synthesized audio and the pond. `config/runtime_assets.lock.json` identifies the published files and their source notices. The installer verifies this inventory before importing Godot resources. Run `python scripts/runtime_assets.py` to check it manually.

The red-eyed tree frog remains a locally licensed optional model; its source terms prohibit distribution as an extractable GLB. The public game uses its authored starter model. Original world GLBs, texture authoring files and previous tile builds remain local development inputs.

## Import the existing reference set

```powershell
.\scripts\install_windows.ps1 -AssetSource "D:\path\to\existing\FrogExplorer" -Test
# Or, after installing Godot:
python scripts\manage_assets.py "D:\path\to\existing\FrogExplorer"
```

Linux uses `bash scripts/install_linux.sh --asset-source /path/to/project --test`. After importing manually, rerun the installer to import Godot resources. Source paths may identify a project, its `game` folder or its `game/assets` folder.

`config/assets.lock.json` identifies the previously prepared reference files by path, size and SHA-256. Every source file is checked before copying starts. Differing existing destination files cause a refusal rather than being overwritten. Original files stay intact. The importer records its source only in ignored `.local/assets.json`.

The reference lock does not grant redistribution rights. The separate runtime inventory and narrow ignore exceptions define the reviewed files committed to Git. Do not add original full scenes, raw downloads, intermediate glTF buffers or the restricted red-eyed model. Both inventories preserve their own purpose: the original reference set supports local authoring; the runtime inventory supports public installation.

## Rebuild world packs from sources

Blender and Python GIS/image dependencies are development tools, not runtime game dependencies:

```powershell
python -m venv tools/world_data_env
.\tools\world_data_env\Scripts\python.exe -m pip install -r scripts/worlds/requirements.txt
.\tools\world_data_env\Scripts\python.exe scripts/worlds/prepare_world_cities.py --blender "C:\path\to\blender.exe"
# Optional: --city tokyo_imperial_palace for one pack. The validator below checks all six.
```

The six international-city recipes in `config/worlds/` record approximate scale, reviewed arrival area, triangle budget, source credits and exclusions. Originals, packed Blender files and receipts are cached under ignored `data/world_sources/`. Downloads verify archive size/MD5 and retain SHA-256 identities. Optional country packs originate from their linked public Zenodo/Sketchfab archives; source licenses vary.

Other exporters are `prepare_landmarks.py`, `prepare_us_cities.py` and `prepare_helsinki.py`. Their generated GLBs go under ignored `game/assets/worlds/`. Review generated `catalog_entry.json` against the matching `game/data/travel_places.json` entry; bounds/spawns must match the actual export. Then run Godot import and the relevant physics harness. Rebuilding a source does not automatically qualify Linux/Pi or rendered performance.

```powershell
.\tools\world_data_env\Scripts\python.exe scripts/worlds/validate_world_cities.py
# Engine path shown as an example; GODOT_BIN can point to another installation.
& .\tools\godot\Godot_v4.7.2-stable_win64.exe --headless --editor --path game --import
& .\tools\godot\Godot_v4.7.2-stable_win64.exe --headless --path game --script res://scripts/world_city_smoke.gd -- --test-session --no-ros
```

World scenes have finite edges, missing geometry and varying close-up detail. Models without a verified geographic transform explicitly use `LOCAL_MODEL` and approximate scale. A photograph of a tree, river, bridge or doorway does not supply corresponding gameplay semantics.

All 16 exports can be split into streaming packs without modifying their original GLBs. See [tile building and validation](TILING.md). The original reference lock and asset importer continue to describe the original assets. `python scripts/prepare_runtime_assets.py` inventories completed tiles and updates the Git ignore exceptions after a reviewed rebuild; it does not stage files or delete prior local packs.

## Rebuild original small assets

`python scripts/make_audio.py` regenerates croak/woodland synthesis. The separate authored American-toad trill is included as a small audio asset. Run `scripts/rides/build_props.py` in Blender to rebuild the balloon, convertible and parachute. `game/scripts/starter_frog.gd` creates its own primitive geometry and simple animation keys at runtime; Blender is not required for starter play.

The earlier detailed frog retargeting/sculpting source archives are outside this code repository. Import their prepared GLBs to retain the established skins, rigs and 28-clip libraries. No realistic source model is silently replaced: the starter path runs only when a species GLB is absent, or when the explicit development flag `--starter-models` is supplied.
