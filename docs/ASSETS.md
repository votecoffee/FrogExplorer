# Runtime assets and optional source files

The public game includes six animated frog GLBs and all 16 runtime world tile packs, alongside starter frogs, vehicles, synthesized audio and the pond. `config/runtime_assets.lock.json` identifies the published files and their source notices. The installer verifies this inventory before importing Godot resources. Run `python scripts/runtime_assets.py` to check it manually.

The red-eyed species uses the original MIT `red_eye_original.glb`. The earlier
third-party `red_eye.glb` and its derived shape passes remain local authoring
archives under their original terms. Original world GLBs, texture authoring
files and previous tile builds remain local development inputs.

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

The earlier third-party frog retargeting/sculpting source archives are outside this code repository. Import their prepared GLBs to retain the established skins, rigs and 28-clip libraries. The starter path runs only when a species GLB is absent, or when the explicit development flag `--starter-models` is supplied.

## Rebuild the original red-eyed tree frog

The original model has a continuous lofted head/trunk, slender articulated
limbs, four fingers per hand, five toes per foot, eighteen adhesive discs,
scalloped partial webbing, a jaw, oral surfaces, tongue, gular sac and moving
eyelids. The builder authors its own painted color/normal/roughness maps,
red iris with a vertical pupil, 61-joint rig, skin weights and 28 action clips.
Blender 5.0.1 was used for this build. Blender and NumPy are authoring tools;
they are not required to play the published asset.

```powershell
& "C:\path\to\blender.exe" --background --python scripts/frogs/build_original_red_eye.py -- --output .local/red_eye_original/candidate
python scripts/frogs/validate_original_red_eye.py .local/red_eye_original/candidate/red_eye_original.glb
& "C:\path\to\blender.exe" --background --python scripts/frogs/preview_original_red_eye.py -- --input .local/red_eye_original/candidate/Original_Red_Eyed_Tree_Frog.blend --output outputs/red_eye_review.png
```

The builder starts with an empty Blender scene and opens no source asset.
It writes a packed editable Blender file, self-contained GLB and a receipt
with source-script and output hashes. Review clay, skin and animated poses
before copying a candidate to `game/assets/frogs/red_eye_original.glb`; then
update the public inventory with `python scripts/prepare_runtime_assets.py`
and rerun the installer with `-Test`. Earlier models stay untouched.
The historical reference lock continues to describe its own older file set.

After the installer imports the published GLB, run its native rig/animation
check with Godot (use `scripts/wait_engine.py` when launching the Windows exe):

```powershell
python scripts/wait_engine.py --log state/original_frog.log -- tools/godot/Godot_v4.7.2-stable_win64.exe --headless --path game --script res://scripts/original_frog_probe.gd -- --test-session --no-ros
```

The native check samples all 28 clips and checks joint transforms, skin bindings
and all eighteen terminal digit joints. Headless checks and offscreen renders
do not measure interactive FPS or qualify Linux/Pi rendering.

## Larger municipal scenery

The [city pack guide](CITY_PACKS.md) prepares an optional 4 x 4 km Helsinki area
and photographed Lyon/Strasbourg samples from municipal data. Native resources,
source caches and intermediates remain ignored. These entries are excluded
from the public runtime inventory. Rebuild ROS after installing them locally.

## Archived local red-eyed shape work

The following older passes refine the historical third-party model. They are
separate from the original builder and do not modify the new default model.

`scripts/frogs/refine_red_eye_shape.py` applies a conservative rest-mesh pass to
the previously prepared skin/eyes v2 Blender model (111 joints, 28 actions).
It narrows the trunk, tapers arm/leg cross-sections around their existing bones,
softens the muzzle/brow contour with a protected eye-socket band, and refines
terminal toe-pad profiles. It preserves topology, UVs, skin weights, packed
images, eye/lid/tongue geometry, joint rest transforms and animation curves.

```powershell
& "C:\path\to\blender.exe" --background --python scripts/frogs/refine_red_eye_shape.py -- --input "D:\local\Red_Eyed_Tree_Frog_Animated.blend" --output .local/red_eye_shape_v3/candidate
```

Keep a verified backup and review the exported GLB in neutral clay, with its
skin, and in motion before installing it as `game/assets/frogs/red_eye.glb`.
The script saves a new packed Blender file, self-contained GLB and preservation
report. `--strength` ranges from 0 to 1. The original reference lock remains a
baseline; it does not describe this later local override. The reference importer
will preserve/refuse an existing differing model rather than overwrite it.

Shape changes remain derived from the source model and do not remove its
redistribution restrictions. Only the sculpting code is published; the revised
red-eyed GLB stays local. Reference photographs guide proportions and are not
sampled into the skin: [Smithsonian active/sleeping frogs](https://nationalzoo.si.edu/animals/news/new-zoo-red-eyed-tree-frogs)
and [STRI's species description](https://panamabiota.org/portal/taxa/index.php?clid=0&taxauthid=1&tid=10678).

To continue from the saved **v3** Blender model, use the separate contour pass:

```powershell
& "C:\path\to\blender.exe" --background --python scripts/frogs/refine_red_eye_contours.py -- --input .local/red_eye_shape_v3/candidate/Red_Eyed_Tree_Frog_Shape_v3.blend --output .local/red_eye_shape_v4/candidate
```

This v4 pass refines the muzzle roof and ventral chin, narrows digit stems,
rounds all 18 terminal pad outlines, and retracts the shared web slightly.
Localized smoothing polishes the pad contours without smoothing the whole
animal. It preserves the v3 body proportions, skin, eye/lid geometry and motion
library. Review open/closed eyes, mouth actions and planted feet before local
installation. [Additional reference photographs](https://exo-terra.com/explore/care-guides/frogs-toads/agalychnis-callidryas/)
guide shape only; no photo pixels are included in the skin.

The next pass continues **v4**, concentrating on anatomical transitions:

```powershell
& "C:\path\to\blender.exe" --background --python scripts/frogs/refine_red_eye_anatomy.py -- --input .local/red_eye_shape_v4/candidate/Red_Eyed_Tree_Frog_Shape_v4.blend --output .local/red_eye_shape_v5/candidate
```

Shape v5 tapers the limb ends around retained muscle bellies, reduces projecting
elbow/knee/ankle caps, and blends the rear cheek into the shoulder. A shared
upper/lower-lip mask softens the exaggerated upturn at the mouth corners. It
keeps v4's trunk and toe-pad work, separate eyes/lids/tongue, skin textures,
topology, UVs, weights, skeleton and all 28 actions. Masked surface fairing and
an orientation guard protect local transitions; review the exported model in
climbing, swimming, jumping and mouth poses before installing it. These shape
choices use the photographs linked above and [Smithsonian's active frog](https://nationalzoo.si.edu/animals/news/new-zoo-red-eyed-tree-frogs),
without embedding the photographs in the asset.
