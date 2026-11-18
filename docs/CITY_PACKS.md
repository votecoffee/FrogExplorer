# Larger municipal city packs

Three optional packs use municipal photogrammetry. The original 16 bundled
maps remain available. New downloads and generated meshes stay outside Git.

| Place ID | Extent | Source | Near / middle / outer / overview source levels |
|---|---|---|---|
| `helsinki_city_center` | 4 x 4 km, 16 km2 | Helsinki 2017 | L21 / L19 / L17 / L15 |
| `lyon_bellecour` | 1.024 x 1.024 km | Lyon 2023 | Error thresholds 0.7 / 1.4 / 5.5 / 12 m |
| `strasbourg_cathedral` | 1.024 x 1.024 km | Strasbourg 2022 | Error thresholds 1.4 / 2.8 / 5.5 / 12 m |

These are bounded samples of larger datasets. Helsinki extends west and north
of the Senate Square arrival. French samples center on Bellecour and the
cathedral district. Coverage can include holes and photographed water. Error
thresholds select source hierarchy levels; they do not promise positional
accuracy or street-level detail. Lyon's source imagery is 5.5 cm per ground
pixel; Strasbourg's is 5 cm. Aerial photographs cannot resolve every doorway,
underside, tree or narrow street. Cars and vegetation are baked into the mesh;
close-up inspection still shows reconstruction artifacts. These packs are
particularly useful for balloon exploration.

## Prepare and install

Install the base game and Godot using the root README. Use Python 3.11 or newer
for the optional preparation environment:

```powershell
python -m venv tools/world_data_env
.\tools\world_data_env\Scripts\python.exe -m pip install -r scripts/worlds/requirements.txt
.\tools\world_data_env\Scripts\python.exe scripts/worlds/prepare_city_mesh.py lyon_bellecour --register
.\tools\world_data_env\Scripts\python.exe scripts/worlds/prepare_city_mesh.py strasbourg_cathedral --register
.\tools\world_data_env\Scripts\python.exe scripts/worlds/prepare_city_mesh.py helsinki_city_center --register
.\scripts\run_windows.ps1 -Place helsinki_city_center
```

Prepare one pack at a time: Godot imports share the project cache. Engine
resolution uses `GODOT_BIN`, the base installer's settings, then PATH. Blender
is optional for offscreen review with `scripts/worlds/preview_city_mesh.py`.

Allow substantial preparation time and at least **80 GB free disk space** for
all three packs, source archives, intermediates and Godot imports. Helsinki's
four archives alone total about 8 GB. French downloads have an 8 GB default
network budget per command; `--max-download-gb` changes it. Helsinki's archive
list is explicitly bounded and SHA-256 pinned. This is offline preparation;
internet streaming is not required during play.

An installed ROS game copy requires additional space for the active native
packs. Source caches and intermediate geometry are retained for rebuilding.

`--plan-only` inspects source selection without downloading mesh payloads.
`--prepare-only` writes geometry without launching Godot. To finish a retained
prepared pack, pass `--prepared-folder game/assets/worlds/PLACE/tiles_city_DIGEST`.
Cached downloads are checked against receipts. Originals and earlier packs
are preserved. Registration follows native rendering/collision baking and hash
manifest creation. Repeating `--register` replaces only that optional place's
catalog object; the importer preserves bundled places.

Sources go in ignored `data/world_sources/PLACE/`; outputs go in ignored
`game/assets/worlds/PLACE/tiles_city_DIGEST/`. A fresh clone lists the optional
catalog entries but offers them in Places only when installed. The public
runtime inventory continues to cover the 16 bundled maps, excluding these packs.
Rebuild the ROS package after adding a pack if launching its installed game.

Linux preparation uses `tools/world_data_env/bin/python`. Runtime entries remain
Windows-qualified only. Linux and the 8 GB Raspberry Pi 5 need separate native
graphics and memory qualification. Prepare these large packs on a desktop.

## Streaming and gameplay

Three independent source levels stream over a non-colliding far overview.
There is no map-wide triangle decimation. Helsinki uses 250 m cells with
220 / 600 / 1000 m detail thresholds; French samples use 128 m cells with
128 / 256 / 512 m thresholds. Exact clipping retains source UVs, material slots
and boundary positions. Photographs are shared by content hash.

Only the finest level has baked collision. The previous visual remains until
its replacement is ready. Movement and boarding require finest collision at
the destination. Every player's position and velocity feed prefetch. The
existing cell budget and two-second unload grace apply. F2 shows residency;
streaming diagnostics also report LOD counts. A cell budget is not a RAM limit.

Walking, jumping, cars, balloons and parachutes use checked mesh collision.
Photographed rivers and scanned trees remain static surfaces. Swimming volumes,
climbable trunks, bridge clearance and road navigation need separate authoring.
The woodland pond retains authored swimming and climbing.

For LAN, copy the same completed native pack and matching catalog entry to each
computer, then rebuild/import there. Hashes participate in compatibility checks;
asset transfer is not part of LAN play.

## Sources and credits

- [Helsinki 3D](https://www.hel.fi/en/decision-making/information-on-helsinki/maps-and-geospatial-data/helsinki-3d):
  City of Helsinki, CC BY 4.0. Four OBJ archives, L21/L19/L17/L15.
- [Lyon photomesh](https://www.data.gouv.fr/datasets/photomaillage-3d-de-la-metropole-de-lyon):
  Metropole de Lyon, Licence Ouverte 2.0; static legacy glTF 1 in 3D Tiles.
- [Strasbourg photomesh](https://data.strasbourg.eu/explore/dataset/pm3d_2022/information/):
  Licence Ouverte 2.0. Retain **Ville et Eurométropole de Strasbourg - Données
  produites avec le soutien du FEDER et de DataGrandEst**, plus the Eurometropole,
  European Union and DataGrandEst logos on distribution supports. Preparation
  downloads pinned original logos; the attribution panel displays them during
  a visit. Retain the credits when sharing packs or screenshots. Logo identity
  terms remain separate from the MIT code license.

Manifests retain URLs, coordinate transforms, exact downloaded hashes and
notices. French ECEF geometry is rebased in float64 before float32 export.
Unsupported required compression and non-static geometry are refused.

## Validation

```powershell
python -m unittest discover -s tests -v
python scripts/wait_engine.py --log state/lod.log -- tools/godot/Godot_v4.7.2-stable_win64.exe --headless --path game --script res://scripts/lod_smoke.gd -- --test-session --no-ros --starter-models
python scripts/wait_engine.py --log state/city_pack.log -- tools/godot/Godot_v4.7.2-stable_win64.exe --headless --path game --script res://scripts/city_pack_smoke.gd -- --test-session --no-ros --starter-models
```

The LOD fixture checks upgrades, downgrades, remote demand, collision readiness
and boarding. The optional real-pack suite checks hashes, arrivals, walking,
balloon traversal, parachute landing, vehicles, residency, cancellation and
return to the pond. Pass `--destination=PLACE` for one pack. Reports stay in
ignored `state/`. Headless physics and offscreen appearance checks do not
measure interactive FPS, physical gamepads, Linux or Pi performance.
