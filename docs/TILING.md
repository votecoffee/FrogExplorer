# Streamed world tiles

Tokyo uses a 128 m grid (202 occupied cells); the Colosseum uses a 64 m grid (72 occupied cells). This first implementation covers those two large static exports. Other places retain their existing loaders, spawns and coverage.

Full-resolution triangles are clipped at cell boundaries, including interpolated UVs and normals. Each tile has its own baked collision shape. Tiles share their texture and material; they do not reference or retain the original GLB. A simplified, non-colliding overview supplies distant scenery. Its shape and texture mapping are approximate; close scenery uses the original surface attributes.

The loader prefetches around every frog, including authoritative remote players and client replicas. It also requests geometry ahead of movement. Detail normally extends 1.25 tile widths from an actor. Arrival and recovery areas remain pinned. Unwanted detail unloads after two seconds; a soft target of 96 resident cells trims distant visual demand. Collision needed by players takes priority and may exceed that target. This is a cell budget, not a fixed RAM limit.

Movement, growth and boarding queries require nearby collision to be ready. On slow storage the frog or vehicle waits at the frontier. A failed tile load leaves already loaded ground available and displays a notice. **H** returns to the pond. Incoming travel remains isolated on a staging collision layer until the arrival is checked. Invalid packs, failed integrity checks and cancelled travel preserve the old world.

## Build the optional packs

First install the original realistic world assets and Godot as described in [the asset guide](ASSETS.md). Use the pinned world-building Python environment; Blender is not needed for this splitting step.

```powershell
python -m venv tools/world_data_env
.\tools\world_data_env\Scripts\python.exe -m pip install -r scripts/worlds/requirements.txt
.\tools\world_data_env\Scripts\python.exe scripts/worlds/tile_world.py tokyo_imperial_palace --tile-size 128 --register
.\tools\world_data_env\Scripts\python.exe scripts/worlds/tile_world.py rome_colosseum --tile-size 64 --register
```

Linux uses the environment's `bin/python`. Engine resolution uses `GODOT_BIN`, the installer settings, then PATH. The splitter supports baked, static, single-mesh/surface triangle GLBs with ordinary position/normal/tangent/UV/color attributes. Unsupported transforms, skins, morphs, sparse/normalized accessors and additional surfaces fail explicitly. Other source formats need a separate baking/generalization step.

Outputs go beside each source, under an ignored `tiles_<size>_<digest>` folder. The digest includes source identity, build-script identity and tile size. The scripts preserve originals and previous derived packs. They import geometry through Godot, save render meshes and collision resources, then write a SHA-256 manifest. `--register` updates only that place's optional `tile_manifest` field in the catalog. Coordinates and the original `scene` path are preserved. Logs stay in `.local/tiling/`.

No generated assets are published with the code. A fresh clone or an original-only asset import uses the original whole scene when its optional manifest is absent. A present but invalid pack is refused. The startup availability check verifies required files; travel verifies their hashes before staging. As with the original assets, do not modify a pack during play.

For LAN, copy the **same completed tile folder** to the matching relative path on every computer, retain the matching catalog, and run Godot import there. Rebuilding separately can produce different serialized resource identities. The LAN fingerprint includes the manifest and its files, preventing mixed whole-scene/tiled builds from joining. Original asset licenses still apply to derived geometry and textures.

## Check the implementation

The source-only streaming harness creates a flat tiled fixture under Godot's user directory. It checks isolated arrival collision, seam crossing, capsule sizing, slow-loading movement/boarding guards, remote demand, unloading and revisiting. It does not require third-party assets.

```powershell
python -m unittest discover -s tests -v
python scripts/wait_engine.py --log state/stream.log -- tools/godot/Godot_v4.7.2-stable_win64.exe --headless --path game --script res://scripts/stream_smoke.gd -- --test-session --no-ros --starter-models
# Requires both completed real tile packs:
python scripts/wait_engine.py --log state/tile_travel.log -- tools/godot/Godot_v4.7.2-stable_win64.exe --headless --path game --script res://scripts/tile_travel_smoke.gd -- --test-session --no-ros --starter-models
```

The real-pack harness checks integrity failure, cancellation/retry, atomic travel, original-mesh absence from the resource cache and return to the pond. The existing city, landmark and LAN suites also exercise tiled destinations when installed.

For reproducible comparisons, `stream_probe.gd` records Godot's static allocation counter, resources, arrival time and resident triangles. Launch separate processes with identical arguments; add `--whole-scenes` to the legacy run. Use `--destination=rome_colosseum` for that pack and `--report=res://../state/name.json` for a report. `--whole-scenes` is a development flag; it is included in the LAN fingerprint.

Headless loading is serialized because Godot's dummy renderer has [an upstream thread-safety issue](https://github.com/godotengine/godot/issues/121949). Interactive loading uses background resource requests and integrates at most one ready tile per frame on the main thread. Headless checks therefore validate physics, residency and travel, rather than interactive loading frame times.

Windows Godot 4.7.2 headless comparisons, using one starter frog at the checked arrival and a three-second settling period:

| Place | Whole-scene static allocations | Tiled static allocations | Resident detail cells |
|---|---:|---:|---:|
| Tokyo | 508 MB | 85 MB | 16 / 202 |
| Colosseum | 704 MB | 151 MB | 12 / 72 |

MB is decimal. These counters include the running game; they are not total process RAM, GPU memory or Raspberry Pi measurements. Eight separated frogs, large scales and different locations change residency. Rendered frame rate, visible overview transitions, physical controllers and Linux/Pi acceptance still require native testing; the existing platform qualifications have not been broadened.
