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
& "C:\path\to\blender.exe" --background --python-exit-code 1 --python scripts/frogs/check_original_gait.py -- --input .local/red_eye_original/candidate/Original_Red_Eyed_Tree_Frog.blend --report state/original_gait.json
& "C:\path\to\blender.exe" --background --python-exit-code 1 --python scripts/frogs/check_original_attachments.py -- --input .local/red_eye_original/candidate/Original_Red_Eyed_Tree_Frog.blend --report state/original_attachments.json
& "C:\path\to\blender.exe" --background --python-exit-code 1 --python scripts/frogs/check_original_locomotion.py -- --input .local/red_eye_original/candidate/Original_Red_Eyed_Tree_Frog.blend --report state/original_locomotion.json
& "C:\path\to\blender.exe" --background --python-exit-code 1 --python scripts/frogs/check_original_transitions.py -- --input .local/red_eye_original/candidate/Original_Red_Eyed_Tree_Frog.blend --report state/original_transitions.json
& "C:\path\to\blender.exe" --background --python-exit-code 1 --python scripts/frogs/check_original_face.py -- --input .local/red_eye_original/candidate/Original_Red_Eyed_Tree_Frog.blend --report state/original_face.json
& "C:\path\to\blender.exe" --background --python scripts/frogs/preview_original_red_eye.py -- --input .local/red_eye_original/candidate/Original_Red_Eyed_Tree_Frog.blend --output outputs/red_eye_review.png
```

The builder starts with an empty Blender scene and opens no source asset.
It writes a packed editable Blender file, self-contained GLB and a receipt
with source-script and output hashes. Review clay, skin and animated poses
before copying a candidate to `game/assets/frogs/red_eye_original.glb`; then
update the public inventory with `python scripts/prepare_runtime_assets.py`
and rerun the installer with `-Test`. Earlier models stay untouched.
The historical reference lock continues to describe its own older file set.

The current authored revision is **original-red-eye-v16**. The mouth
corner turns up into the cheek fold. The lower jaw is rounder under the
front of the muzzle and shallower near the hinge. The throat surface is
wider and sits farther forward under the chin. The head and lower jaw use
the same mouth corner contour so the lip follows the cheek when it closes.

The v15 eye socket has
a thinner upper rim and a fuller lower rim that joins the cheek. A rounded
tympanic membrane sits in the cheek behind each eye and follows the surface
at its edges. The fold behind it curves toward the mouth corner. The face
check tests the socket as well as the eyelid and cranial skin for obstruction
of the open iris.

The v14 head mesh introduced a
defined ridge from the brow toward each naris, a steeper cheek below the ridge,
and a rounded lower eye socket. The nares sit in depressions in the muzzle, with
five additional mesh rings in that area. The export has 97,808 triangles. The
shapes follow the supplied photographs and the credited Sartore profile.

The v13 pass used the supplied frog photographs to guide a shorter muzzle with
a tapered tip, a fuller forehead between the eyes, and lower brow contours.
The lower lip follows the muzzle's
underside and the throat blends into the chin. The throat skin sits below the
oral floor during feeding. The 28 clip durations, 61-joint hierarchy and the
v12 limb surfaces are retained.

The v12 pass revised the resting
pose follows the crouch in the supplied frog photographs, with the front feet
closer under the shoulders, the knees folded forward and the ankles tucked
closer to the flanks. The forearms have a fuller muscle belly. Walking, climbing,
turning and Swamp Shuffle give the forward-reaching knees room behind the elbows.
The original 28 clip names and durations are retained, along with all twelve
texture images.
The export has 75 mesh objects, 61 joints and 96,848 triangles.

The v11 pass used real photographs as the primary shape reference:
the supplied front, side and overhead views, plus the credited photographer/zoo
photographs. They guide a shallower cheek below the eye, a more tapered snout,
repositioned nares, a rising mouth line, a rounder rump and a rounded ankle fold.
The slim thighs are retained; the calf has a modest muscle belly and the ankle
skin has a lateral soft-tissue roll with denser longitudinal samples.

The jaw, tongue and throat pivots are refitted to the higher mouth floor.
The palate follows the closing jaw width rather than a fixed ellipse, and
the rear oral surface is enclosed at rest.
The existing rig hierarchy, clip timing and eleven painted images are retained;
the trunk naris marks follow the revised snout and body UV range. These are
authored interpretations across different photographic poses and perspectives,
rather than a calibrated reconstruction from the photographs.

The v10 pass used a visual review of the earlier local frog to guide
a broader proportion pass: a narrower skull and waist, smaller forward-facing
eyes in cranial recesses, fitted brows, a leaner belly/rump, a more compact
forelimb stance, shorter digits and smaller palms and pads. The body uses one
continuous loft profile rather than blending revised facial sections back into
the older bulky head profile. Subtle dorsal relief gives the back more shape.
The v10 export had 75 mesh objects, 61 joints, 92,176 triangles, twelve
embedded images and 28 clips.

The 61 joint names/hierarchy, 75 mesh part names, 28 clip durations and 7,140
animation-channel key times remain compatible. Most joint landmarks and the
IK curve values are regenerated for the new proportions; the paired kick and
swimming hand targets are adjusted with the stance. Eleven painted images are
identical to v9; the trunk albedo's naris marks follow the new head width.
The builder still opens no reference model. The earlier frog is retained only
as a local visual reference, with its original terms and files kept separate.

The v9 pass slimmed and flattened the hind thighs, reduced the
knee/calf bulk and tapered the ankle while retaining the terminal foot surfaces.
At the middle of each rest-mesh thigh, the major cross-section diameter is
38 percent smaller and the minor diameter 45 percent smaller than v8. These
measure the model change, rather than dimensions calibrated from photographs.
The face has a shallower lower cheek and a higher, flatter resting throat.
A flush cheek membrane uses the surrounding skin map and a tapered upper
fold, with skin weights following the torso instead of a rigid circular rim.
All 61 joint rests, all 7,140 animation curves, 46 unchanged forelimb/foot
contact meshes, the posterior trunk and all twelve painted images are retained.
Only the two continuous hind-limb skins change among the 48 contact meshes.

The v8 pass narrowed the anterior muzzle into a tapered
wedge, brought the snout forward, and gave the forehead a flatter roof with
beveled transitions into angled cheeks. A finer canthus ridge runs toward
each nostril. The closing jaw and mouth seam follow the tapered upper lip;
interpolated jaw widths stay inside it at the rear mouth corners.
All 61 joint rests, all 7,140 v7 animation curves, all 48 limb/contact meshes,
the posterior trunk and eleven painted images are retained. Only the trunk
albedo's naris marks move to follow the changed muzzle proportions.

The v7 facial pass shortened and flattened the muzzle,
reduced the jaw depth, lowered and recessed the eyes, and added fitted nostrils
and subtle cheek surfaces. Irregular iris fibers and crypts surround a wider
vertical pupil; finer head pigment and less uniform gloss break up the skin.
Open eyelids sit behind the cornea, then close over it with slight eye
retraction. `Croak` uses a closed jaw and throat inflation. The v7 export had
75 mesh objects, 61 joints, 92,082 triangles, 12 embedded images and 28 clips.

The face work preserves all 48 limb/contact meshes, the posterior trunk,
seven limb/digital/orbital images and 57 joint rest transforms. Only the four
eye/lid rests move. Lid curves, added eye-retraction curves and the `Croak`
jaw rotation change; all other 6,744 existing curves are retained, including
the v5/v6 locomotion. Photographs guide proportions rather than supplying
geometry, texture pixels or measured motion. These remain authored likenesses.

The v6 pass replaced `Hop`, `Water_Entry` and `Shore_Exit`
with coordinated foot paths and gradual changes between the resting and active
limb bend planes. Hop returns to idle; water entry connects idle to the first
swim pose; shore exit connects that swim pose to idle. All v5 meshes, painted
pixels, joint rests and curves in the other 25 clips are retained, including
the v5 walking, jumping and swimming work.

Pond crossings now select the existing entry/exit clip for every frog, played
over 0.60 seconds. Movement and diving continue during transitions. Action
buttons interrupt them; an already-running action is preserved, and a rapid
shoreline reversal replaces the previous transition. These animations do not
change the physical water/shore detection or create water in imported maps.

The v5 pass replaced `Slow_Walk`, `Big_Jump` and `Swim` with
authored foot paths and parent-aware limb IK. Walking uses a shorter 40-frame
cycle, rearward hind-foot placement and constant stance travel: 0.072 m/s at
authored scale, approximately 0.20 m/s at the game's 2.8 model scale. Jumping
extends the hind feet behind the torso before recovery; swimming has a paired
power stroke, glide and slower recovery. These are artistic interpretations
of general frog locomotion research, not captured red-eyed frog measurements.
All v4 meshes, painted pixels and joint rests are retained, as are the curves
in the other 25 clips. Godot still supplies world travel and jump height.
The receipt records source hashes and the largest IK target residual.

The v4 pass refined the shoulder and hip attachments with
buried root rims and a gradual blend from torso skin weights into the upper
limbs. Tapered calves, narrower ankles and softer joint folds distinguish the
folded leg segments. The v3 face, feet, webbing and painted pixels are preserved,
as are all 61 joint rest transforms and all 28 motion clips. The triangle count
is unchanged. The receipt and public inventory identify the exact exported file.

The v3 pass added individually sized adhesive pads aligned
with each toe, flatter pad soles, finer digital skin, and partial webbing that
deforms with the adjacent digits. Flatter wrists/ankles and softer joint folds
refine the folded limbs while preserving the v2 head, trunk, mouth and eyes.

The v2 pass established the continuous brow/muzzle, oval corneal surfaces and
fitted orbital skin, slimmer torso, tapered limb muscles, closing jaw rim,
recessed palate and throat. The v7 face revises its eye/lid pivots and lid curves
while retaining the throat pivot and locomotion joints.

After the installer imports the published GLB, run its native rig/animation
check with Godot (use `scripts/wait_engine.py` when launching the Windows exe):

```powershell
python scripts/wait_engine.py --log state/original_frog.log -- tools/godot/Godot_v4.7.2-stable_win64.exe --headless --path game --script res://scripts/original_frog_probe.gd -- --test-session --no-ros
```

The native check samples all 28 clips and checks joint transforms, skin bindings
and all eighteen terminal digit joints. The Blender gait check measures the
evaluated pad, digit, palm, web and limb surfaces between keys during walking
and climbing. It also checks planted-pad clearance, using a 0.45 mm penetration
tolerance and a 0.9 mm maximum stance gap at the authored metre scale; joint
positions alone would miss skin crossing the support plane. These are sampled
geometry checks against a flat plane, separate from world collision testing.
The check also rejects intersections between the forelimb and hind limb skin
on either side in the sampled walk and climb poses.
For walking, it also checks the evaluated pad stance speed against the travel
calibration, with a 0.007 m/s error tolerance. The locomotion check samples 48
poses in each revised clip for distal skin/trunk intrusion, fore/hind pad
clearance and hind feet crossing forward into the head region. It does not
prove absence of all mesh self-intersections or continuous-time collisions.
The attachment check samples the four proximal limb rims against the evaluated
torso in nine poses per clip. It detects exposed root caps with a 0.45 mm
tolerance; this is separate from checking mesh union or all self-intersections.
The transition check compares all evaluated meshes at six endpoints against
the neighboring idle/swim poses, with a 0.25 mm displacement tolerance. It
checks all eighteen pads in 44 planted-phase poses using the same contact
tolerances as the gait check. The locomotion check includes both the v5 and
v6 clips by default; `--clips` selects a smaller explicit set for diagnosis.
The face check ray-tests the central 92 percent corneal radius in an open and
closed blink: at most two percent lid or cranial-skin occlusion when open,
at least 98 percent lid coverage when closed. This detects head skin cutting
through the iris as eye size or placement changes. Seventeen `Croak` poses check a closed jaw and throat
inflation. This measures sampled geometry and animation behavior, not realism.
Closed-palate vertices are also checked against the nearest oriented head/jaw
surfaces, with a 0.20 mm exposure tolerance, to detect oral surfaces spilling
through a narrowed or raised cheek while the mouth is closed.
At the sampled open feeding pose, the face check also casts rays toward the
oral floor to detect throat skin showing through it by more than 0.20 mm.
Use `--face` on the preview tool for matched face close-ups, and `--clay` to
separate silhouette changes from skin and eye shading.
`--hindlegs` frames the right folded thigh, calf and ankle with a fixed camera
for skin/clay comparisons. Full-body animated previews still fit the sampled
motion so extended legs and toes stay visible.
Use the preview tool's `--lift 0.08` option to suspend the frog and camera for
inspection of swimming or jumping poses away from the studio floor.
`--span 0.44` provides a wider minimum frame; animated full-body previews fit
the sampled motion with a steady camera so extended toes remain visible.
Headless checks and offscreen renders
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
