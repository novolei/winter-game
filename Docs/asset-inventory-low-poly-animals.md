# Asset inventory — *Low Poly Animated Animals* v4.1.1

**Source:** `D:/Low Poly Animated Animals v4.1.1.unitypackage` — 122 MB packed, **598 MB
unpacked**, 1,112 entries. Publisher: **polyperfect**.

**The package is not in this repository and should not be.** It is the owner's source
material, like `Refs/`. This file exists so the parts we did *not* take are a known,
searchable list rather than a forgotten folder — if a later wave wants a wolf, or a
second bird, or wants to be sure there is no owl, the answer is here and nobody has to
unpack 598 MB again.

Everything below was **measured**, not read off the store page: triangle counts and
animation takes come from parsing the FBX binaries directly, and every size in metres
was measured by importing the file through **Godot 4.7.1's own ufbx importer** in a
throwaway project. Every take was then **played and measured**: 217 takes loaded, a bone sampled at
five points across each, and the pose compared. The full method and the per-animal
verdicts are in `.superpowers/sdd/wave3/task-w3-animals-report.md`.

**Written as though the package has been lost.** §7 records every take of every
animal — adopted or not — with its name, its frame range inside its parent take, its
duration and its source file. Slicing a missed animation later should be a matter of
reading a row, not of re-deriving Unity's clip structure from 598 MB.

---

## 1. The five things that decide what an adoption costs

These are properties of *this pack*, found by measurement, and each one has a silent
failure mode. Read them before importing anything out of it.

### 1.1 The models arrive at three different scales, and the wrong one does not error

Godot divides every file by 100 (the FBX `UnitScaleFactor` path). The pack's animals
are authored in three different units, so **only some of them come out life-sized**:

| Authored in | Arrives as | Needs `nodes/root_scale` |
|---|---|---|
| centimetres | correct | **1.0** |
| decimetres | 10× too small | **10.0** |
| metres | 100× too small | **100.0** |

Measured, before and after the fix:

| Model | as imported | with `root_scale` | result |
|---|---|---|---|
| Deer | 0.99 × 2.44 × 2.18 m | 1.0 | 0.99 × 2.44 × 2.18 m |
| DoveRock | 0.73 × 0.27 × 0.26 m | 1.0 | 0.73 × 0.27 × 0.26 m |
| Rabbit | 0.21 × 0.38 × 0.46 m | 1.0 | 0.21 × 0.38 × 0.46 m |
| Squirrel | 0.07 × 0.16 × 0.32 m | 1.0 | 0.07 × 0.16 × 0.32 m |
| Boar | 0.04 × 0.08 × **0.125 m** | 10.0 | 0.37 × 0.78 × 1.25 m |
| Wolf | 0.004 × 0.010 × **0.015 m** | 100.0 | 0.36 × 1.01 × 1.53 m |
| Reindeer | 0.008 × 0.020 × **0.021 m** | 100.0 | 0.84 × 2.00 × 2.05 m |
| Vulture | 0.017 × 0.005 × **0.006 m** | 100.0 | 1.71 × 0.55 × 0.64 m |
| Eagle | 0.021 × 0.009 × **0.010 m** | 100.0 | 2.12 × 0.92 × 1.00 m |
| Fox | 0.002 × 0.006 × **0.011 m** | 100.0 | 0.21 × 0.62 × 1.12 m |

**A 15 mm wolf imports cleanly and passes every art gate.** Its triangle count is right,
its material is right, its animations are right. The only symptom is a creature nobody
can see, which at this game's framing reads as "the spawn logic isn't working" and sends
you looking in the wrong file. **Measure the imported AABB and assert it**, the way
`test_threat_models.gd` asserts the bear's triangle count.

### 1.2 Several FBXs name a texture the package does not ship, and that is a `WARNING:`

Captured from a clean `--import` of ten candidate models:

```
WARNING: FBX: Image index '0' couldn't be loaded from path: res://models/Deer_COL_1k.png
WARNING: FBX: Image index '0' couldn't be loaded from path: res://models/Dove-rock_COL_2k.png
WARNING: FBX: Image index '0' couldn't be loaded from path: res://models/Wolf-new_COL_2k.psd
WARNING: FBX: Image index '1' couldn't be loaded from path: res://models/Wolf-new_EMI_2k.png
WARNING: FBX: Image index '0' couldn't be loaded from path:
         res://../../../../../../../../Rigging/Low Poly Animals Rigs/Vulture/Vulture_COL_2k.png
WARNING: FBX: Image index '0' couldn't be loaded from path:
         res://../../../../../../../Rigging/Low Poly Animals Rigs/Reindeer/Reindeer_COL_2k.png
ERROR: Resource file not found: res:// (expected type: Texture2D)
```

Three distinct causes, and they do **not** cost the same to fix:

| Cause | Animals | Fix |
|---|---|---|
| The FBX spells the texture with a hyphen where the pack ships an underscore (`Dove-rock` vs `Dove_rock`) | DoveRock, Bear, Boar, Buffalo, Camel, Cow, Crab, Giraffe, Hen, Parrot, Rhino, Seahorse | **Copy the texture in beside the FBX under the name the FBX asks for.** Verified: doing this made Deer and DoveRock import silent. |
| The FBX names a file the pack never shipped | **Wolf** (`Wolf-new_COL_2k.psd` — a PSD Godot cannot read — and `Wolf-new_EMI_2k.png`, absent entirely), Horse, Lion, Elephant (`tusk.tif`) | **No placement fixes this.** Either re-export the FBX without the material, or accept a dirty import. |
| The FBX has the author's own machine path baked in (`res://../../../../..../Rigging/...`) | **Reindeer**, **Vulture** | **No placement fixes this.** Same two options. |

This matters more here than in most projects: `tools/run_tests.sh` fails any run whose
console holds `WARNING:`. The warnings above are **import-time only** — once the
`.import` cache is written, loading the scene is silent, and a test run stays clean.
But AGENT-BRIEFING §1 makes `--import` part of the workflow and §5 forbids calling an
unexpected warning harmless, so treat a dirty import as an adoption cost, not noise.

### 1.3 Two kinds of animation file, and only one needs a slicer

The crow's pack put fifteen clips end to end inside one long take, which is why
`CrowAnimations` exists. **Most of this pack does not do that.**

- **Pre-split (55 animals).** Each Unity clip is its own FBX `AnimationStack`. Godot's
  importer produces them as separate, correctly named, correctly trimmed `Animation`
  resources with no help. Verified against the Unity clip ranges: `deer_walk` is frames
  30–54 in the `.meta` and imports at **1.000 s** at 24 fps; `deer_idle 2` is 160–346 and
  imports at **7.750 s**. **No `CrowAnimations`-style slicer is needed.**
- **One long take (11 animals).** All clips share a single `Take 001` and only the
  `.meta` knows the boundaries. These need build-time slicing exactly as the crow did:
  **Cow, Crocodile, Ostrich, Parrot, Penguin, Rhino, Seagull, Shark, Spider, Tapir,
  Vulture.** Two individual files are also long-take: `SKM_Deer_Animations_Eat.fbx` and
  `SKM_Wolf_Animations_Howl.fbx`, both a single `Take 001`.

The pack is **24 fps** almost everywhere. Two exceptions: **Reindeer is 30 fps** and
**Pig is 60 fps**. Computing a clip length from the `.meta` frame range at the wrong
rate is off by 25% (Reindeer) or 150% (Pig) and nothing reports it — the Reindeer's idle
is 11.5 s at 24 fps and **9.2 s** as it actually imports.

### 1.4 Nine animals have no animation Godot can read

Their clips ship only as Unity `.anim` files — YAML `AnimationClip` assets, not FBX
takes. Godot cannot read them, and converting them means writing a Unity-curve →
`Animation` converter with bone-path remapping. **The model imports; it just never
moves.**

**Dog ×3, Gorilla, JellyFish, Orca, Rabbit, Snake, StarFish.**

This is the finding that kills the **Rabbit**, which is otherwise one of the best
candidates in the pack — 630 triangles, a 0.46 m silhouette with unmistakable ears at
exactly the crow's pixel budget, and seven clips including a `LookOut` that is
flee-and-return behaviour already authored. All seven are `.anim`. Its rig FBX carries
one unnamed 4.958 s `Take 001` and nothing else.

Nine further animals have *some* FBX clips **and** extra Unity-only ones — Bear, Cow,
Crocodile, Fish, Horse, Penguin, Seagull, Shark, Spider — so their clip counts in the
table below understate what Unity users get and overstate what we can have.

### 1.5 Do the takes actually play? — 217 loaded, 209 move, 8 still

An animation that imports without error, appears in the list and leaves the mesh in its
bind pose is worse than a missing one, because the inventory will claim we have it. The
crow's pack shipped animation FBXs carrying 121 nulls and **no armature at all** — they
imported cleanly and had no pose to give.

So every take was played, not merely counted. Method: instantiate the imported scene,
put it in the tree, `play()` each take, `seek()` to five fractions of its length
(0, ¼, ½, ¾, ~1), read **every bone's** pose rotation and position at each, and take the
largest delta against the first sample. A take "moves" if any bone's quaternion changes
by more than 0.001 or any bone's position by more than 0.5 mm.

```
TOTAL takes imported : 217
TOTAL takes that move: 209
STILL (imported but never leaves the bind pose): 8
   bear_pack_rig.fbx   :: Take 001 (43.708s,   4 tracks)
   dog_greatdane.fbx   :: Take 001 ( 4.958s,   3 tracks)
   vulture_rig.fbx     :: Take 001 ( 4.958s,   4 tracks)
   wolf_rig.fbx        :: Take 001 (56.667s,   4 tracks)
   bear_project.glb    :: Death_Lying_R01_DeathPose  (1.033s, 102 tracks)
   bear_project.glb    :: Death_Sitting_R01_poses    (1.033s, 102 tracks)
   bear_project.glb    :: Death_StandHind_F01_poses  (1.033s, 102 tracks)
   bear_project.glb    :: Death_Stand_R01_poses      (1.033s, 102 tracks)
```

**The eight fall into two groups and only one of them is a trap.**

- **Four are the junk `Take 001` that every `*_Rig.fbx` in this pack carries.** Three or
  four tracks, no skeleton motion, and a length that is meaningless (the wolf rig's is
  **56.667 s**). They exist because the exporter wrote a stack for a scene with nothing
  animated in it. **Every rig file must be imported with `animation/import=false`**, or
  each adopted animal gains a phantom take that a `AnimationPlayer.get_animation_list()`
  census will happily count. This is the one to guard.
- **Four are the existing project bear's `_poses` / `_DeathPose` clips**, and they are
  **correct**: a held death pose is *supposed* to be still. They are single-pose assets,
  not broken takes. Worth knowing so nobody "fixes" them.

**Every single take of every roster animal moves.** Deer 10/10 and its Eat 1/1, Fox 9/9,
Pigeon 13/13, Hen 18/18 (rig) and 12/12 (animations), Rooster 12/12, Wolf 5/5 and its
Howl 1/1, Boar 10/10, Eagle 15/15, Squirrel 10/10, pack Bear 7/7, project Bear 77/81
(the four above being poses by design).

The rig files carry no `AnimationPlayer` at all — `deer_rig`, `dove_rig`,
`dog_chihuahua`, `dog_golden` reported "no AnimationPlayer or no Skeleton3D" — which is
correct and expected: they are model files.


---

## 2. The textures are flat colour maps, not detailed diffuse

This is the single most important fact for the Art Bible question, and it is the
opposite of what "122 MB of animals" suggests.

**Most of these textures hold between 4 and 50 unique colours across a 2048×2048 map.**
They are not painted skins; they are UV islands parked on flat colour patches. The
Bear's whole 2k map is **8 colours**. The Sheep's is 8. The Horse's is 4. The Chick's
is 5.

Two consequences:

- **Repainting into the 12-colour palette is a colour-substitution, not a paint job.**
  For a 6-to-16-colour animal it is a lookup table, and it could be generated by a script
  in `tools/` the way every other content file in this project is.
- **For anything that reads as a silhouette, the texture can simply be dropped** —
  which is what the crow already does. `Crow.palette_tone()` takes `structure_tones[3]`
  and the bird is one flat value with no map at all. Any dark animal here can take the
  same treatment for the same cost: none.

The exceptions — animals whose maps carry real gradients and noise, and which would need
actual repainting — are **Gorilla** (1,662–3,591 colours), **JellyFish** (4,538–11,705),
**StarFish** (2,181), **Spider Green** (2,380), **Wolf** (1,510), **Shark** (1,072),
**Orca** (930), **Snake** (699), **Rabbit** (645), the three **Dogs** (326–507),
**Cat** (342–477), **Cow White** (257), **Crocodile** (255), **Deer Grey** (219).

**The Wolf's 1,510 is misleading and worth saying plainly:** 48.3% of its map is a
single value `#1D1D1D` and almost all the rest sits between `#333` and `#393939`. It is
a near-black wolf with dither on it. As a flat palette tone it loses nothing.

---

## 3. What is in the package

| Folder | Entries | Unpacked |
|---|---:|---:|
| `Meshes/` (66 animals + nature, props, terrain) | 316 | **598.75 MB** |
| `Sounds/` (49 `.ogg`) | 49 | 16.26 MB |
| `Textures/` | 142 | 14.74 MB |
| `README_LowPolyAnimatedAnimals.pdf` | 1 | 9.15 MB |
| `Prefabs/` (Unity-only) | 169 | 6.88 MB |
| `DEMO_Scenes/`, demo scenes (Unity-only) | 24 | 7.20 MB |
| `Terrains/` | 10 | 4.96 MB |
| `UI/` (Unity-only) | 28 | 3.09 MB |
| `URP_LowPolyAnimatedAnimals.unitypackage` (nested) | 1 | 2.32 MB |
| `Animator Controllers/`, `Scripts/`, `Stats/`, `Wander Script/`, `Navmesh/` (Unity-only C# and assets) | 164 | 1.53 MB |

**Prefabs, Animator Controllers, Scripts, Stats, the Wander Script and the UI are Unity
C# and Unity asset formats. None of them can be used here.** The pack's own wander AI is
`Common/Wander Script/` — it is not portable, and this project would not want it anyway:
`CrowFlock` already establishes the shape (a system that owns its creatures and drives
them, publishing to `EventBus`).

### Sounds worth knowing about

49 `.ogg` files, 16.26 MB. Most are wrong-biome (elephant, gorilla, jungle). Four are
directly useful to this game and one is remarkable:

| File | KB | Why |
|---|---:|---|
| **`SFX_Wolf_Howl.ogg`** | 22.8 | See the wolf's verdict. A howl is a threat tell that needs no model on screen. |
| `SFX_Environment_Artic.ogg` | 1,067.9 | Ambient bed, polar |
| `SFX_Ice_Squeels.ogg` | 84.2 | Ice under load |
| `SFX_Deer.ogg` / `SFX_Deer_Walk.ogg` | 125.9 / 35.0 | With the deer |
| `SFX_Piano_Sad.ogg` | 430.5 | Not ours — GDD §9 specifies a four-layer adaptive bed, not a cue |

---

## 4. The complete animal inventory

66 animals. `tris` is the whole-asset triangle count (every mesh in the file, added up),
which is the number `test_topology.gd` and `test_threat_models.gd` care about — the Art
Bible's creature budget is **8,000** and **nothing in this pack is over 5,682**.

`takes` says whether Godot gets the clips ready-split or as one long take needing a
slicer (§1.3). `Unity-only` counts `.anim` files Godot cannot read (§1.4). `colours` is
the number of unique RGB values in the animal's colour map, and `dominant` its three
largest patches by area — `#000000` is unused UV space and is excluded.

| Animal | tris | bones | fps | takes | FBX files | clips | Unity-only | texture | colours | dominant colours | pack MB |
|---|---:|---:|---:|---|---:|---:|---:|---|---:|---|---:|
| Anteater | 1852 | 102 | 24 | pre-split | 1 | 10 | 0 | 2048px | 10 | `#67492D` 21.9% `#4D3B2B` 20.6% `#C4AD93` 7.1% | 13.98 |
| Bear | 3898 | 40 | 24 | pre-split | 3 | 8 | 6 | 2048px | 8 | `#67492D` 54.3% `#4D3B2B` 5.8% `#3F3C3C` 2.7% | 22.78 |
| Beaver | 1566 | 93 | 24 | pre-split | 1 | 9 | 0 | 2048px | 7 | `#79604B` 42.4% `#3F3C3C` 22.3% `#2F2F2F` 1.1% | 10.94 |
| Bees | 1342 | 57 | 24 | pre-split | 2 | 5 | 0 | 2048px | 7 | `#2F2F2F` 12.7% `#312F2F` 9.6% `#4D3B2B` 7.3% | 5.87 |
| Boar | 1636 | 56 | 24 | pre-split | 2 | 10 | 0 | 2048px | 16 | `#67492D` 35.1% `#4D3B2B` 20.8% `#852929` 2.6% | 16.45 |
| Buffalo | 1378 | 60 | 24 | pre-split | 2 | 11 | 0 | 2048px | 20 | `#4D3B2B` 48.6% `#3F3C3C` 11.7% `#2F2F2F` 2.0% | 18.82 |
| Camel | 1866 | 84 | 24 | pre-split | 4 | 10 | 0 | 2048px | 6 | `#CC9B60` 36.3% `#A7783E` 11.6% `#9E5C55` 0.8% | 22.53 |
| Capybara | 1450 | 82 | 24 | pre-split | 1 | 5 | 0 | 2048px | 9 | `#885B39` 56.4% `#3F3C3C` 9.3% `#BC7A5A` 1.2% | 4.13 |
| Cat | 734 | 51 | 24 | pre-split | 3 | 11 | 0 | 2048px | 342 | `#CC5C27` 49.1% `#E0DFDF` 2.7% `#D09D79` 0.9% | 10.70 |
| Chick | 618 | 47 | 24 | pre-split | 1 | 9 | 0 | 2048px | 5 | `#FDC524` 55.5% `#FAA62D` 6.7% `#CA3038` 1.6% | 4.19 |
| Chimpanzee | 1542 | 100 | 24 | pre-split | 2 | 11 | 0 | 2048px | 34 | `#2F2F2F` 50.6% `#BD7A5A` 17.2% `#852929` 1.1% | 14.96 |
| Cockroach | 378 | 41 | 24 | pre-split | 2 | 5 | 0 | 2048px | 4 | `#4D3B2B` 42.4% `#67492D` 12.6% `#885B39` 3.7% | 2.20 |
| Cow | 5682 | 58 | 24 | pre-split | 4 | 12 | 5 | 2048px | 7 | `#67492D` 56.9% `#2F2F2F` 4.0% `#BC7A5A` 2.0% | 16.43 |
| Crab | 1470 | 53 | 24 | pre-split | 2 | 5 | 0 | 2048px | 5 | `#67492D` 16.7% `#4D3B2B` 14.9% `#A7783E` 14.3% | 3.96 |
| Crocodile | 1490 | 71 | 24 | long take | 1 | 6 | 6 | 1024px | 255 | `#A6893C` 12.9% `#161310` 3.2% `#E76138` 2.9% | 5.55 |
| Deer | 1030 | 51 | 24 | pre-split | 3 | 11 | 0 | 1024px | 51 | `#5D3414` 39.4% `#8F7966` 15.0% `#291C14` 7.4% | 9.30 |
| Dog Chihauhau | 872 | 56 | — | — | 1 | 0 | 5 | 1024px | 326 | `#2B2B2D` 40.2% `#B19D8A` 6.7% `#D09D79` 2.3% | 1.48 |
| Dog GoldenRetriever | 928 | 56 | — | — | 1 | 0 | 6 | 1024px | 326 | `#2B2B2D` 40.2% `#B19D8A` 6.7% `#D09D79` 2.3% | 2.10 |
| Dog GreatDane | 988 | 55 | — | — | 1 | 0 | 6 | 1024px | 326 | `#2B2B2D` 40.2% `#B19D8A` 6.7% `#D09D79` 2.3% | 2.12 |
| Dolphin | 902 | 34 | 24 | pre-split | 1 | 9 | 0 | 2048px | 6 | `#5E5A5A` 33.9% `#A7A19E` 14.4% `#CA3038` 5.7% | 5.04 |
| DoveRock | 832 | 45 | 24 | pre-split | 2 | 13 | 0 | 2048px | 46 | `#A7A19E` 25.1% `#2F2F2F` 17.0% `#5E5A5A` 13.0% | 8.41 |
| Eagle | 1012 | 113 | 24 | pre-split | 1 | 15 | 0 | 2048px | 46 | `#4D3B2B` 48.8% `#F2E0CF` 11.3% `#DCBF9A` 2.7% | 23.25 |
| Elephant | 1822 | 92 | 24 | pre-split | 4 | 15 | 0 | 2048px | 26 | `#4D3B2B` 57.7% `#885B39` 1.6% `#DBBE9A` 0.5% | 13.06 |
| Fish | 148 | 14 | 24 | pre-split | 1 | 1 | 1 | 1024px | 3 | `#FF7900` 53.6% `#171717` 0.5% | 0.14 |
| Flamingo | 1482 | 105 | 24 | pre-split | 2 | 5 | 0 | 2048px | 5 | `#FBC9C9` 24.2% `#F9ACB3` 18.4% `#CB6194` 8.5% | 4.92 |
| Fox | 1870 | 55 | 24 | pre-split | 1 | 9 | 0 | 2048px | 54 | `#FC7D20` 42.2% `#DCBF9A` 8.0% `#2F2F2F` 6.7% | 5.51 |
| Giraffe | 4630 | 70 | 24 | pre-split | 3 | 17 | 0 | 2048px | 9 | `#DBBE9A` 26.3% `#A7783E` 13.4% `#F1DFCE` 7.3% | 16.93 |
| Goat | 1458 | 53 | 24 | pre-split | 1 | 9 | 0 | 2048px | 14 | `#F2E0CF` 53.7% `#615347` 4.3% `#BD7A5A` 3.4% | 4.43 |
| Goose | 1158 | 86 | 24 | pre-split | 2 | 12 | 0 | 2048px | 13 | `#F2E0CF` 35.3% `#FC7D20` 18.8% `#4D3B2B` 2.5% | 11.17 |
| Gorilla | 1282 | 97 | — | — | 1 | 0 | 6 | 1024px | 1662 | `#0D0C0C` 78.0% `#3B3B3B` 7.5% `#1D1C1C` 1.5% | 6.00 |
| Hen | 894 | 92 | 24 | pre-split | 2 | 18 | 0 | 2048px | 6 | `#885B39` 34.2% `#CD9B60` 19.7% `#67492D` 11.0% | 32.88 |
| Hippo | 1666 | 54 | 24 | pre-split | 2 | 10 | 0 | 2048px | 25 | `#3F3C3C` 46.8% `#9F5C55` 10.5% `#7A444B` 5.4% | 7.62 |
| Horse | 1928 | 51 | 24 | pre-split | 3 | 8 | 5 | 2048px | 4 | `#2C2D2F` 57.8% `#DBBE9A` 2.1% `#852929` 1.2% | 10.75 |
| JellyFish | 954 | 126 | — | — | 1 | 0 | 1 | 1024px | 8544 | `#090909` 31.3% `#EEB1E3` 7.5% `#52168D` 7.4% | 1.91 |
| Lion | 1982 | 79 | 24 | pre-split | 5 | 25 | 0 | 2048px | 10 | `#A7783E` 39.8% `#DBBE9A` 11.1% `#4D3B2B` 1.0% | 28.36 |
| Meerkat | 1818 | 126 | 24 | pre-split | 2 | 8 | 0 | 2048px | 9 | `#A7783E` 41.9% `#DBBE9A` 11.1% `#67492D` 3.9% | 9.64 |
| Octopus | 2172 | 60 | 24 | pre-split | 1 | 6 | 0 | 2048px | 7 | `#F2E0CF` 23.0% `#DCBF9A` 14.2% `#C4AD93` 2.4% | 5.81 |
| Orca | 944 | 29 | — | — | 1 | 0 | 5 | 1024px | 930 | `#2B2B2D` 35.2% `#E0DFDF` 15.1% `#D42532` 4.7% | 0.50 |
| Ostrich | 988 | 70 | 24 | long take | 2 | 5 | 0 | 2048px | 6 | `#2F2F2F` 39.8% `#9F5C55` 11.9% `#F2E0CF` 10.9% | 4.31 |
| Panda | 1710 | 89 | 24 | pre-split | 2 | 10 | 0 | 2048px | 5 | `#2F2F2F` 32.1% `#E0DFDF` 23.3% `#3F3C3C` 1.9% | 12.77 |
| Parrot | 976 | 84 | 24 | long take | 2 | 6 | 0 | 2048px | 31 | `#FAA62D` 22.1% `#384878` 18.5% `#5E5A5A` 6.1% | 3.52 |
| Penguin | 602 | 37 | 24 | long take | 1 | 3 | 5 | 1024px | 35 | `#171717` 40.9% `#E7E7E7` 28.9% `#C13E0E` 3.7% | 3.64 |
| Pig | 1524 | 55 | 60 | pre-split | 1 | 12 | 0 | 2048px | 85 | `#BD7A5A` 63.6% `#9F5C55` 9.3% `#F2E0CF` 1.5% | 10.15 |
| Rabbit | 630 | 53 | — | — | 1 | 0 | 7 | 1024px | 645 | `#4D4134` 43.6% `#E0DFDF` 8.5% `#D09D79` 1.9% | 10.94 |
| Rat | 1118 | 86 | 24 | pre-split | 2 | 6 | 0 | 2048px | 24 | `#4D3B2B` 53.3% `#BC7A5A` 14.0% `#9E5C55` 1.9% | 6.74 |
| Reindeer | 2458 | 55 | 30 | pre-split | 2 | 8 | 0 | 2048px | 87 | `#4D3B2B` 21.9% `#DCBF9A` 17.9% `#67492D` 17.6% | 7.28 |
| Rhino | 1420 | 61 | 24 | long take | 2 | 5 | 0 | 2048px | 42 | `#A7A19E` 53.3% `#878282` 8.2% `#5E5A5A` 2.6% | 3.35 |
| Rooster | 1106 | 97 | 24 | pre-split | 1 | 12 | 0 | 2048px | 114 | `#22293E` 29.9% `#384878` 14.1% `#67492D` 7.6% | 12.00 |
| Seagull | 160 | 17 | 24 | long take | 1 | 2 | 2 | 1024px | 5 | `#E7E7E7` 36.5% `#9096A7` 8.8% `#171717` 3.1% | 0.58 |
| Seahorse | 702 | 29 | 24 | pre-split | 2 | 5 | 0 | 2048px | 4 | `#C93038` 21.6% `#E34935` 2.3% `#2F2F2F` 1.3% | 2.02 |
| Seal | 932 | 40 | 24 | pre-split | 1 | 10 | 0 | 2048px | 47 | `#3F3C3C` 63.2% `#C4AD93` 2.4% `#BD7A5A` 0.8% | 5.88 |
| Shark | 796 | 29 | 24 | long take | 1 | 2 | 3 | 1024px | 1072 | `#293034` 39.1% `#BBC4C5` 13.6% `#181D20` 9.4% | 0.39 |
| Sheep | 1408 | 51 | 24 | pre-split | 2 | 26 | 0 | 2048px | 8 | `#F2E0CF` 43.7% `#3F3C3C` 13.3% `#615347` 4.8% | 18.11 |
| Snake | 390 | 31 | — | — | 1 | 0 | 4 | 512px | 699 | `#2B1E0D` 15.1% `#D4A84B` 14.1% `#0C0B0A` 1.1% | 24.65 |
| Spider | 948 | 45 | 24 | long take | 1 | 3 | 7 | 1024px | 28 | `#080701` 57.0% `#F76D07` 17.9% `#171717` 1.2% | 4.39 |
| Squid | 2098 | 59 | 24 | pre-split | 1 | 5 | 0 | 2048px | 17 | `#EEA770` 21.8% `#C4AD93` 7.0% `#DCBF9A` 5.9% | 4.20 |
| Squirrel | 1500 | 102 | 24 | pre-split | 1 | 10 | 0 | 2048px | 18 | `#6A4A2E` 46.6% `#67492D` 8.8% `#4D3B2B` 4.5% | 13.85 |
| StarFish | 106 | 107 | — | — | 1 | 0 | 1 | 512px | 2181 | `#FF7A18` 2.4% `#FF6400` 0.9% `#FF6600` 0.7% | 0.67 |
| Tapir | 1468 | 56 | 24 | long take | 2 | 5 | 0 | 2048px | 22 | `#3F3C3C` 39.8% `#DBDBDA` 17.5% `#878282` 5.0% | 2.95 |
| Tiger | 2204 | 79 | 24 | pre-split | 2 | 11 | 0 | 2048px | 36 | `#FC7D20` 29.4% `#E0DFDF` 10.8% `#852929` 0.5% | 12.57 |
| Tucan | 1056 | 50 | 24 | pre-split | 2 | 13 | 0 | 2048px | 68 | `#5E5A5A` 5.6% `#FAA62D` 3.5% `#CA3038` 3.2% | 9.25 |
| Vulture | 934 | 106 | 24 | long take | 2 | 5 | 0 | 2048px | 21 | `#2F2F2F` 40.1% `#878282` 13.6% `#F2E0CF` 4.4% | 7.55 |
| Walrus | 964 | 31 | 24 | pre-split | 1 | 10 | 0 | 2048px | 7 | `#79604B` 54.5% `#4D3B2B` 14.1% `#F2E0CF` 2.1% | 4.67 |
| Whale | 1564 | 44 | 24 | pre-split | 2 | 4 | 0 | 2048px | 6 | `#3F3C3C` 26.5% `#A6A09E` 10.7% `#F9ACB3` 9.0% | 4.40 |
| Wolf | 2008 | 56 | 24 | pre-split | 7 | 24 | 0 | 2048px | 1510 | `#1D1D1D` 48.3% `#353535` 6.9% `#333333` 5.6% | 17.78 |
| Zebra | 2574 | 70 | 24 | pre-split | 2 | 6 | 0 | 2048px | 6 | `#DADAD9` 16.1% `#2F2F2F` 12.1% `#3F3C3C` 1.0% | 4.25 |


---

## 5. The dogs — the deliverable, and the blocker

> **UNBLOCKED, and the rest of this section is now history rather than status.**
> The owner did what §5.2 recommended: he opened the package in Unity and
> re-exported the seventeen dog clips as `Model@Clip.fbx`. All three dogs are in
> the project as of commit `9b028dd` —
> `assets/models/characters/dogs/{chihuahua,golden_retriever,great_dane}.glb`,
> built by `tools/blender/build_dog.py`, **23 takes, all 23 measured to move**
> (`tools/measure_dog_takes.gd`). The two takes §5.3 said could never be filled —
> lying down and growling — are **authored on all three rigs** by that same
> script. `src/entities/wildlife/dog_animations.gd` is the shared vocabulary, and
> the chihuahua's missing `stand` resolves to its `idle` by an explicit rule.
>
> Three findings below are corrected by the re-export and are left in place
> because they are true of the *package*: the `.anim` hash problem (§5.2) is what
> made the Unity round trip necessary; the two scale families (§5.1) collapsed
> into one on the way through, which `data/scale/dog_*.tres` now asserts; and the
> Great Dane's 55-bone rig is still a different rig, which costs nothing because
> each breed's takes are played on the skeleton they were authored on. See
> `.superpowers/sdd/wave3/task-w3-dogs-report.md`.

The scripted find (an injured dog in the snow, healed, named, becomes a companion) is the
priority. Three things were asked; here are the three answers, and the first is bad news.

### 5.1 The three take tables, side by side

| Take | Chihuahua | Golden Retriever | Great Dane | Duration (chi / gold / dane) |
|---|:-:|:-:|:-:|---|
| `Bark` | `.anim` | `.anim` | `.anim` | 0.667 / 1.042 / 0.833 s |
| `Idle` | `.anim` | `.anim` | `.anim` | 10.667 / 7.500 / 6.458 s |
| `Run` | `.anim` | `.anim` | `.anim` | 0.625 / 0.708 / 0.542 s |
| `Sit` | `.anim` | `.anim` | `.anim` | 1.375 / 1.042 / 1.458 s |
| `Walk` | `.anim` | `.anim` | `.anim` | 1.417 / 1.208 / 0.833 s |
| `Stand` | **absent** | `.anim` | `.anim` | — / 0.833 / 1.667 s |
| **`Lie down`** | **absent** | **absent** | **absent** | — |
| **`Hurt` / `Injured`** | **absent** | **absent** | **absent** | — |
| **`Sleep`** | **absent** | **absent** | **absent** | — |
| **`Death`** | **absent** | **absent** | **absent** | — |
| `Eat` / `Drink` | absent | absent | absent | — |
| `Growl` | absent | absent | absent | — |
| Jump, Attack, transitions | absent | absent | absent | — |
| **FBX takes Godot can read** | **0** | **0** | **1**, and it is junk — 4.958 s, 3 tracks, **measured STILL** | |

Two findings the design needs before the scene is written:

**1. No dog in this pack can lie down.** There is no lying, no hurt, no sleep, no death
take on any of the three. The scene as described — a hurt dog in the snow — has no
authored pose to open on. The vocabulary is exactly six verbs: bark, idle, run, sit,
stand, walk. `Sit` is the closest thing to "down" and a sitting dog does not read as
injured.

**2. The three are not fully interchangeable.** Chihuahua and Golden Retriever share an
**identical 56-bone skeleton, name for name**. The **Great Dane is a different rig**: 55
bones, 49 shared, and it both drops and adds bones —

```
in Chihuahua/Golden only : Chest_M, Neck2_M, RootPart1_M, RootPart2_M,
                           Spine1Part1_M, Spine1Part2_M, Tail1_M
in Great Dane only       : Spine11_M, Tail5_M, Tail6_M, joint4_M,
                           tempRename_M, tempRename1_M
```

`tempRename_M` and `tempRename1_M` are the author's own leftover rename artefacts. A
companion behaviour that drives "one of the three at random" therefore needs either a
bone-name mapping layer for the Great Dane or a retarget — it is not free.

**And they are not even at the same import scale.** Chihuahua needs `root_scale` **1.0**
(it arrives at 0.28 m, correct); Golden and Great Dane need **100.0** (they arrive at
12 mm and 13 mm). Three dogs, two scale families, and the wrong one does not error.

### 5.2 Why the `.anim` files cannot simply be converted

All seventeen dog clips are Unity `AnimationClip` YAML. Inside, curves are **not keyed by
bone name** — they are keyed by an opaque 32-bit path hash:

```
m_ClipBindingConstant:
  genericBindings:
  - path: 421436397     attribute: 1  typeID: 4
  - path: 4233262604    attribute: 1  typeID: 4
```

A converter must therefore reverse that hash against the skeleton's own transform paths.
**Standard CRC32 does not reproduce it** — tested against all 56 bone paths of the Golden
Retriever, with six plausible root prefixes: **0 of 69 hashes matched.** Unity uses its
own hash function, so step one of any converter is replicating it, before you get to
decoding Hermite quaternion curves and re-timing them.

**The cheap route is not a converter, it is Unity.** Open the package in Unity once and
export each dog as FBX (or glTF) with its clips baked as takes. That turns a
research-and-build task into running one program, and it is the recommendation.

### 5.3 What the dogs would cost, and what they would buy

Even converted, the companion needs takes that do not exist: lie down, get up, hurt,
sleep, growl. The owner cannot author quadruped animation, which is exactly why this
matters — **these are not gaps that can be filled later by hand.**

Two ways out, both worth the Director's attention:

- **Borrow from the pack's other quadrupeds.** They will not transfer to a dog: the
  dogs' rig shares only **14 of 56 bones** with the fox/wolf family. Measured.
- **Buy or source a dog with a full companion vocabulary**, the way the bear and the
  wanderer were sourced. The project bear demonstrates what "enough" looks like: it has
  `Lying_Idle_01`, `Lying_Breathing_01`, `Trans_Stand_to_Lying`, `Trans_Lying_to_Stand`,
  `Hit_Lying_R01` and `Death_Lying_R01` — a complete down-and-up vocabulary, on an animal
  that already lives in this repository.

---

## 6. Verdicts

### 6.1 The named roster

| Animal | Class | Verdict | Triangles | `root_scale` | Takes (move/total) | Import | Repaint cost |
|---|---|---|---:|---:|---|---|---|
| **Deer** | indifferent | **ADOPT** | 1,030 | 1.0 | 10/10 + Eat 1/1 | clean once `Deer_COL_1k.png` is placed | **trivial** — 3 flat browns, or drop the map and take one palette tone |
| **Pigeon** (`DoveRock`) | indifferent | **ADOPT** | 832 | 1.0 | 13/13 | clean once `Dove-rock_COL_2k.png` is placed | **trivial** — already grey/near-black |
| **Fox** | watchful | **ADOPT** | 1,870 | **100.0** | 9/9 | clean | **moderate, and it must be done** — 42.2% of its map is `#FC7D20`, and orange is the reserved warm quota |
| **Chicken** (`Hen`) | indifferent | **ADOPT** | 894 | **100.0** | 18/18 (rig) + 12/12 (anims) | clean once `Hen-brown_COL_2k.png` is placed | **trivial** — 6 colours |
| **Wolf** | hostile · W5 | **ADOPT, blocker first** | 2,008 | **100.0** | 5/5 + Howl 1/1 | **DIRTY — unfixable by placement** | **trivial** — 48.3% is already `#1D1D1D` |
| **Rabbit** | indifferent | **ADOPT model, animation blocked** | 630 | 1.0 | **0 usable** — all 7 are Unity `.anim` | clean | moderate — 645 colours, but it is a small silhouette |
| **Dog ×3** | bonded | **ADOPTED — in, via a Unity re-export** | 872 / 928 / 988 | n/a — rebuilt as `.glb` | **23/23 move**, including a `lie` and a `growl` authored here | clean | done — map dropped, one flat `structure_tones[2]` |
| **Bear** | hostile · W5 | **REJECT — keep the one we have** | 3,898 | 100.0 | 7/7 | dirty (2 missing textures) | trivial |

### 6.2 The bear: measured against the one already in the repository

Both were loaded and every take played.

| | **Project bear** `assets/models/characters/bear/bear.glb` | **Pack bear** `SKM_Bear_*.fbx` |
|---|---|---|
| Triangles | **3,000** (gate-locked at 2,996 ± 300 by `test_threat_models.gd`) | 3,898 |
| Bones | 35 | 130 |
| Takes that play | **77 of 81** | 7 of 7 |
| Imported size | 0.88 × 1.68 × 2.60 m, correct as-is | needs `root_scale` 100 |
| Import console | clean, already gated | 2 missing-texture warnings |
| The GDD's bear — "先警告后冲锋，撞倒玩家" | `Trans_Stand_to_StandHind` (the rear-up warning), `Attack_StandAngry_01_High` (the blow), `Attack_Run_01_AttackF` (the charge that connects) | **none of these exist** |
| Locomotion | Sneak / WalkSlow / Walk / Trot / Run / Sprint, each with L and R variants, plus **25 `Trans_*` transitions** | Walk, Run |
| Reaction & death | 5 `Hit_*`, 8 `Death_*` | 1 `Dead` |
| Postures | Stand, StandAngry, StandHind, Sitting, Lying, with transitions between all five | none |

**Keep the project bear.** The pack's is 30% more triangles for 7 takes against 81, has
no rear-up and no transitions, would break a green gate, and imports dirty. Its one
genuinely nice take is `Bear_Rub` (4.167 s, a bear rubbing itself) which the project bear
does not have; that is not worth the trade.

**The polar bear is not a separate model.** It is the same 3,898-triangle grizzly mesh
with `Bear_Polar_COL_2k.png` swapped in — a texture variant. Refusing it costs nothing
that refusing the grizzly did not already cost.

### 6.3 Refused by the Director, recorded here as available-but-refused

Both are present in the package, both are good models, and both are **refused on world
coherence, not on quality**. The valley has a pickup truck, power lines, a ploughed field
and an American farmhouse. An animal that does not belong to that place breaks the third
pillar, 沉默即叙事 — the world speaks only by everything in it belonging to it.

| Animal | What is there | Why refused | If overruled |
|---|---|---|---|
| **Tiger** | 2,204 tris, 79 bones, 11 pre-split takes, 24 fps, `Tiger_COL_2k.png` 36 colours (`#FC7D20` 29.4%) | Reads as a game spawning a monster, not as a place that has a tiger | `Tiger/SKM_Tiger_Rig.fbx` + `SKM_Tiger_Animations.fbx`, 12.57 MB, `root_scale` 1.0 |
| **Polar bear** | not a separate model — the grizzly mesh with `Bear_Polar_COL_2k.png` (8 colours, `#E3FDFE` 46.8%) | Polar bears live on sea ice and there is no coast; and a white animal on `#8FB0D8` snow has no silhouette at all | swap the texture on the pack bear, which is itself rejected in §6.2 |

### 6.4 Everything else in the package

None of the following is adopted. Grouped by the reason, so a later wave can find the
exception it wants. Full take lists for all of them are in §7 — nothing here is lost.

| Reason | Animals |
|---|---|
| **Wrong biome** — savanna, jungle, desert, wetland | Anteater, Buffalo, Camel (×2), Capybara, Chimpanzee, Crocodile, Elephant (×2), Flamingo, Giraffe, Gorilla, Hippo, Lion (×3), Meerkat, Ostrich, Panda, Parrot, Rhino, Tapir, Tucan, Vulture, Zebra |
| **Marine** — the valley has no open water | Dolphin, Fish, JellyFish, Octopus, Orca, Seahorse, Seal, Shark, Squid, StarFish, Walrus, Whale, Crab, Penguin, Seagull |
| **Farmyard, and a live one says the farm still works** — but see the note below | Cow, Goat, Horse, Pig, Sheep (×2), Chick, Goose, Rooster |
| **Absent in deep winter** | Bees, Cockroach, Snake, Spider |
| **Northern and plausible, simply not on the roster** | Beaver, Boar, Fox *(adopted)*, Reindeer, Squirrel, Rat, Wolf *(adopted)*, Cat, Eagle |

**Two of those deserve a second look and are flagged rather than buried:**

- **Reindeer** (2,458 tris, 8 takes, 30 fps) is the most thematically correct large animal
  in the package and has by far the best antler silhouette. It is not on the roster and
  it is *not* being smuggled on; but it also has the worst import defect in the pack — the
  author's own machine path baked into the FBX, unfixable by placement.
- **The `_Death` takes end lying down.** Sheep, Goat, Cow and Horse all have a death take
  whose last frame is the animal on the ground. A frozen carcass in a field is set
  dressing that belongs in this valley exactly as much as a live one does not, and it
  costs one held pose rather than a behaviour. Not proposed — noted, because it is the
  cheapest thing in the whole package.

### 6.5 The warning network — how much of the roster is nearly free

This is the question that decides the value of the roster, and the answer is: **most of
it, for the flee, and none of it for free beyond that.**

`CrowFlock.scatter(cause)` already carries a reason (`&"player"`, `&"nightfall"`) and
already publishes `wildlife.crows_scattered {position, count, cause}`. Nothing consumes
it yet. Every animal below can raise the same event with a different `cause`, and a
Wave 5 threat can subscribe once.

| Animal | Can share `scatter(cause)` | What it needs that the crow system does not already have |
|---|---|---|
| **Pigeon** | **yes, almost entirely** | Nothing structural. It perches, walks, takes off, flies and lands — 13 takes covering every state `Crow` has. `PerchPoints` already offers 24 perches. This is genuinely a data change plus a second `CrowAnimations`-shaped take map. |
| **Chicken** | **yes, with one addition** | It has `Fly` (0.833 s) but a hen flaps rather than departs; it needs a *ground* flee that ends nearby instead of at `vanish_distance_m`. Its `Idle_Roost` and `Sleep` takes are a night state the crow does not have. |
| **Deer** | yes, but the mover is new | Perch logic does not apply. Needs ground navigation over the snow field and a home range. Its `idle→run` / `run→idle` transitions **are** the flee-and-return grammar, already authored. |
| **Rabbit** | yes, once animated | Same as the deer, at a quarter the size. |
| **Fox** | **no — different behaviour by design** | "Watchful" is the opposite of flee-and-return: hold distance, keep facing, retreat only when closed on. Same event, inverted rule. |
| **Dog** | no | Bonded. It moves *toward* the disturbance. It is the one that raises the cause rather than reacting to it. |
| **Wolf / Bear** | no — they are the cause | They should publish something the others subscribe to. |

**The single cheapest item in the entire roster is the pigeon**, and the single cheapest
*idea* is the wolf's howl: `SFX_Wolf_Howl.ogg` (22.8 KB) plus the 3.708 s `Wolf_Howl`
take is a night presence and a threat tell that needs **no wolf on screen at all**.

**One free transfer was found by measurement.** The **fox and the wolf share 55 of 56
bones** — the wolf adds only `Tail7_M`. The fox has `Idle→Walk`, `Walk→Idle`,
`Idle→Run`, `Run→Idle`; **the wolf has none of these**. The fox's four transitions can
drive the wolf directly. That is four takes the wolf does not otherwise have, for nothing.

The dogs share only **14 of 56** bones with the fox/wolf family, so nothing transfers to
them.

---

## 7. Every take of every animal

Recorded so that a take missed today can be recovered tomorrow by reading a row.

- **Frames** are the Unity clip range inside the **parent take** named in the third
  column. Where the parent take is the clip's own `AnimationStack` (a *pre-split* file),
  Godot already produces that clip correctly and the range is informational.
- Where the parent take is `Take 001` and several clips share it (a *long take* file,
  marked in the heading), **the frame range is the slicing instruction** — the same job
  `src/entities/wildlife/crow_animations.gd` does for the crow.
- **Duration** is computed at the file's own frame rate, which is stated in each heading.
  The pack is 24 fps except **Reindeer (30)** and **Pig (60)**.
- Rows marked *Unity `.anim`* cannot be read by Godot at all — see §1.4 and §5.2.
- One inconsistency to know about: a few Unity clip ranges are shorter than the FBX take
  they name, so Godot imports slightly more than Unity plays. `Eagle_Flying attack` is
  frames 511–548 (1.542 s) in the `.meta` and imports as a **2.000 s** stack.

### Anteater — 24 fps, 1852 tris, 102 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Anteater_Idle` | SKM_Anteater_Animation.fbx | `Anteater_Idle` | 0–50 | 2.083 s | loop |
| `Anteater_Idle_2` | SKM_Anteater_Animation.fbx | `Anteater_Idle2` | 100–250 | 6.250 s | loop |
| `Anteater_Idle_To_Walk` | SKM_Anteater_Animation.fbx | `Anteater_Idle to Walk` | 300–320 | 0.833 s | once |
| `Anteater_Walk` | SKM_Anteater_Animation.fbx | `Anteater_Walk` | 350–390 | 1.667 s | loop |
| `Anteater_Walk_To_Idle` | SKM_Anteater_Animation.fbx | `Anteater_Walk to Idle` | 420–440 | 0.833 s | once |
| `Anteater_Idle_To_ Run` | SKM_Anteater_Animation.fbx | `Anteater_Idle to Run` | 470–478 | 0.333 s | once |
| `Anteater_Run` | SKM_Anteater_Animation.fbx | `Anteater_Run` | 500–515 | 0.625 s | loop |
| `Anteater_Run_To_Idle` | SKM_Anteater_Animation.fbx | `Anteater_Run to Idle` | 530–539 | 0.375 s | once |
| `Anteater_Attack` | SKM_Anteater_Animation.fbx | `Anteater_Attack` | 560–603 | 1.792 s | loop |
| `Anteater_Death` | SKM_Anteater_Animation.fbx | `Anteater_Death` | 630–658 | 1.167 s | once |

### Bear — 24 fps, 3898 tris, 40 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Walk` | SKM_Bear_Rig.fbx | `Take 001` | 301–301 | 0.000 s | loop |
| `Bear_Walk` | SKM_Bear_Animations.fbx | `Bear_Walk` | 1–33 | 1.333 s | loop |
| `Bear_Run` | SKM_Bear_Animations.fbx | `Bear_Run` | 50–65 | 0.625 s | loop |
| `Bear_Idle` | SKM_Bear_Animations.fbx | `Bear_Idle` | 100–350 | 10.417 s | loop |
| `Bear_Rub` | SKM_Bear_Animations.fbx | `Bear_Rub` | 400–500 | 4.167 s | loop |
| `Bear_Attack_Bite` | SKM_Bear_Animations.fbx | `Bear_Attack_Bite` | 550–579 | 1.208 s | loop |
| `Bear_Attack_Swipe` | SKM_Bear_Animations.fbx | `Bear_Attack_Swipe` | 600–650 | 2.083 s | loop |
| `Bear_Dead` | SKM_Bear_Animations.fbx | `Bear_Dead` | 700–732 | 1.333 s | once |
| `Take 001` | SKM_Bear_Rig.fbx | `Take 001` | — | 43.708 s | — |
| `Bear_Legacy_Death` | **Bear_Legacy_Death.anim** (Unity `.anim`, unreadable by Godot) | — | — | 2.083 s | — |
| `Bear_Legacy_Idle` | **Bear_Legacy_Idle.anim** (Unity `.anim`, unreadable by Godot) | — | — | 15.792 s | — |
| `Bear_Legacy_Run` | **Bear_Legacy_Run.anim** (Unity `.anim`, unreadable by Godot) | — | — | 1.083 s | — |
| `Bear_Legacy_StandUp` | **Bear_Legacy_StandUp.anim** (Unity `.anim`, unreadable by Godot) | — | — | 6.833 s | — |
| `Bear_Legacy_StandUp_Attack` | **Bear_Legacy_StandUp_Attack.anim** (Unity `.anim`, unreadable by Godot) | — | — | 6.625 s | — |
| `Bear_Legacy_Walk` | **Bear_Legacy_Walk.anim** (Unity `.anim`, unreadable by Godot) | — | — | 1.417 s | — |

### Beaver — 24 fps, 1566 tris, 93 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Beaver_Idle` | SKM_Beaver_Animations.fbx | `Beaver_Idle` | 0–40 | 1.667 s | loop |
| `Beaver_Idle_To_Walk` | SKM_Beaver_Animations.fbx | `Beaver_Idle to Walk` | 80–95 | 0.625 s | once |
| `Beaver_Walk` | SKM_Beaver_Animations.fbx | `Beaver_Walk` | 120–150 | 1.250 s | loop |
| `Beaver_Walk_To_Idle` | SKM_Beaver_Animations.fbx | `Beaver_Walk to Idle` | 170–185 | 0.625 s | once |
| `Beaver_Idle_To_Run` | SKM_Beaver_Animations.fbx | `Beaver_Idle to Run` | 210–217 | 0.292 s | once |
| `Beaver_Run` | SKM_Beaver_Animations.fbx | `Beaver_Run` | 230–245 | 0.625 s | loop |
| `Beaver_Run_To_Idle` | SKM_Beaver_Animations.fbx | `Beaver_Run to Idle` | 260–268 | 0.333 s | once |
| `Beaver_Attack` | SKM_Beaver_Animations.fbx | `Beaver_Attack` | 290–329 | 1.625 s | loop |
| `Beaver_Death` | SKM_Beaver_Animations.fbx | `Beaver_Death` | 350–373 | 0.958 s | once |

### Bees — 24 fps, 1342 tris, 57 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Bee_Idle_A` | SKM_Bee_Animation.fbx | `Bee_IdleA` | 0–60 | 2.500 s | loop |
| `Bee_Idle_B` | SKM_Bee_Animation.fbx | `Bee_IdleB` | 80–140 | 2.500 s | loop |
| `Bee_Fly` | SKM_Bee_Animation.fbx | `Bee_Fly` | 150–170 | 0.833 s | loop |
| `Bee_Attack` | SKM_Bee_Animation.fbx | `Bee_Attack` | 200–285 | 3.542 s | loop |
| `Bee_Death` | SKM_Bee_Animation.fbx | `Bee_Death` | 310–340 | 1.250 s | once |
| `Take 001` | SKM_Bees_Rig.fbx | `Take 001` | — | 6.250 s | — |

### Boar — 24 fps, 1636 tris, 56 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Boar_Idle_Breathing` | SKM_Boar_Animations.fbx | `Boar_Idle Breathing` | 0–80 | 3.333 s | loop |
| `Boar_Idle_Left_Right` | SKM_Boar_Animations.fbx | `Boar_Idle Left Right` | 120–280 | 6.667 s | once |
| `Boar_Idle_To_Walk` | SKM_Boar_Animations.fbx | `Boar_Idle to Walk` | 310–322 | 0.500 s | once |
| `Boar_Walk` | SKM_Boar_Animations.fbx | `Boar_Walk` | 340–372 | 1.333 s | loop |
| `Boar_Walk_To_Idle` | SKM_Boar_Animations.fbx | `Boar_Walk to Idle` | 400–412 | 0.500 s | once |
| `Boar_Idle_To_Run` | SKM_Boar_Animations.fbx | `Boar_Idle to Run` | 440–448 | 0.333 s | once |
| `Boar_Run` | SKM_Boar_Animations.fbx | `Boar_Run` | 458–471 | 0.542 s | loop |
| `Boar_Run_To_Idle` | SKM_Boar_Animations.fbx | `Boar_Run to Idle` | 492–500 | 0.333 s | loop |
| `Boar_Attack` | SKM_Boar_Animations.fbx | `Boar_Attack` | 520–546 | 1.083 s | loop |
| `Boar_Death` | SKM_Boar_Animations.fbx | `Boar_Death` | 580–606 | 1.083 s | once |
| `Boar_Idle Breathing` | SKM_Boar_Rig.fbx | `Boar_Idle Breathing` | — | 3.333 s | — |
| `Boar_Idle Left Right` | SKM_Boar_Rig.fbx | `Boar_Idle Left Right` | — | 6.667 s | — |
| `Boar_Idle to Walk` | SKM_Boar_Rig.fbx | `Boar_Idle to Walk` | — | 0.500 s | — |
| `Boar_Walk` | SKM_Boar_Rig.fbx | `Boar_Walk` | — | 1.333 s | — |
| `Boar_Walk to Idle` | SKM_Boar_Rig.fbx | `Boar_Walk to Idle` | — | 0.500 s | — |
| `Boar_Idle to Run` | SKM_Boar_Rig.fbx | `Boar_Idle to Run` | — | 0.333 s | — |
| `Boar_Run` | SKM_Boar_Rig.fbx | `Boar_Run` | — | 0.542 s | — |
| `Boar_Run to Idle` | SKM_Boar_Rig.fbx | `Boar_Run to Idle` | — | 0.333 s | — |
| `Boar_Attack` | SKM_Boar_Rig.fbx | `Boar_Attack` | — | 1.083 s | — |
| `Boar_Death` | SKM_Boar_Rig.fbx | `Boar_Death` | — | 1.083 s | — |

### Buffalo — 24 fps, 1378 tris, 60 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Buffalo_Idle_Breathing` | SKM_Buffalo_Animations.fbx | `Buffalo_Idle Breathing` | 0–48 | 2.000 s | loop |
| `Buffalo_Idle_Right` | SKM_Buffalo_Animations.fbx | `Buffalo_Idle Right` | 80–176 | 4.000 s | loop |
| `Buffalo_Idle_Left` | SKM_Buffalo_Animations.fbx | `Buffalo_Idle Left` | 220–316 | 4.000 s | loop |
| `Buffalo_Idle_To_Walk` | SKM_Buffalo_Animations.fbx | `Buffalo_Idle to Walk` | 340–356 | 0.667 s | once |
| `Buffalo_Walk` | SKM_Buffalo_Animations.fbx | `Buffalo_Walk` | 380–420 | 1.667 s | loop |
| `Buffalo_Walk_To_Idle` | SKM_Buffalo_Animations.fbx | `Buffalo_Walk to Idle` | 450–470 | 0.833 s | once |
| `Buffalo_Idle_To_Run` | SKM_Buffalo_Animations.fbx | `Buffalo_Idle to Run` | 500–512 | 0.500 s | once |
| `Buffalo_Run` | SKM_Buffalo_Animations.fbx | `Buffalo_Run` | 550–566 | 0.667 s | loop |
| `Buffalo_Run_To_Idle` | SKM_Buffalo_Animations.fbx | `Buffalo_Run to Idle` | 592–604 | 0.500 s | once |
| `Buffalo_Attack` | SKM_Buffalo_Animations.fbx | `Buffalo_Attack` | 630–667 | 1.542 s | loop |
| `Buffalo_Death` | SKM_Buffalo_Animations.fbx | `Buffalo_Death` | 700–730 | 1.250 s | once |
| `Buffalo_Idle Breathing` | SKM_Buffalo_Rig.fbx | `Buffalo_Idle Breathing` | — | 2.000 s | — |
| `Buffalo_Idle Right` | SKM_Buffalo_Rig.fbx | `Buffalo_Idle Right` | — | 4.000 s | — |
| `Buffalo_Idle Left` | SKM_Buffalo_Rig.fbx | `Buffalo_Idle Left` | — | 4.000 s | — |
| `Buffalo_Idle to Walk` | SKM_Buffalo_Rig.fbx | `Buffalo_Idle to Walk` | — | 0.667 s | — |
| `Buffalo_Walk` | SKM_Buffalo_Rig.fbx | `Buffalo_Walk` | — | 1.667 s | — |
| `Buffalo_Walk to Idle` | SKM_Buffalo_Rig.fbx | `Buffalo_Walk to Idle` | — | 0.833 s | — |
| `Buffalo_Idle to Run` | SKM_Buffalo_Rig.fbx | `Buffalo_Idle to Run` | — | 0.500 s | — |
| `Buffalo_Run` | SKM_Buffalo_Rig.fbx | `Buffalo_Run` | — | 0.667 s | — |
| `Buffalo_Run to Idle` | SKM_Buffalo_Rig.fbx | `Buffalo_Run to Idle` | — | 0.500 s | — |
| `Buffalo_Attack` | SKM_Buffalo_Rig.fbx | `Buffalo_Attack` | — | 1.542 s | — |
| `Buffalo_Death` | SKM_Buffalo_Rig.fbx | `Buffalo_Death` | — | 1.250 s | — |

### Camel — 24 fps, 1866 tris, 84 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Camel_Bactrian_Walk` | SKM_Camel_Bactrian_Animations.fbx | `Bactrian_Walk` | 1–30 | 1.208 s | loop |
| `Camel_Bactrian_Run` | SKM_Camel_Bactrian_Animations.fbx | `Bactrian_Run` | 60–73 | 0.542 s | loop |
| `Camel_Bactrian_Idle` | SKM_Camel_Bactrian_Animations.fbx | `Bactrian_Idle` | 100–250 | 6.250 s | loop |
| `Camel_Bactrian_Attack` | SKM_Camel_Bactrian_Animations.fbx | `Bactrian_Attack` | 300–350 | 2.083 s | loop |
| `Camel_Bactrian_Death` | SKM_Camel_Bactrian_Animations.fbx | `Bactrian_Death` | 400–450 | 2.083 s | once |
| `Take 001` | SKM_Camel_Bactrian_Rig.fbx | `Take 001` | — | 46.500 s | — |
| `Camel_Dromedary_Walk` | SKM_Camel_Dromedary_Animations.fbx | `Dromedary_Walk` | 1–29 | 1.167 s | loop |
| `Camel_Dromedary_Run` | SKM_Camel_Dromedary_Animations.fbx | `Dromedary_Run` | 60–73 | 0.542 s | loop |
| `Camel_Dromedary_Idle` | SKM_Camel_Dromedary_Animations.fbx | `Dromedary_Idle` | 100–250 | 6.250 s | loop |
| `Camel_Dromedary_Attack` | SKM_Camel_Dromedary_Animations.fbx | `Dromedary_Attack` | 300–350 | 2.083 s | loop |
| `Camel_Dromedary_Death` | SKM_Camel_Dromedary_Animations.fbx | `Dromedary_Death` | 400–450 | 2.083 s | once |
| `Take 001` | SKM_Camel_Dromedary_Rig.fbx | `Take 001` | — | 46.500 s | — |

### Capybara — 24 fps, 1450 tris, 82 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Capybara_Idle` | SKM_Capybara_Animations.fbx | `SKM_Capybara_Idle` | 0–40 | 1.667 s | loop |
| `Capybara_Walk` | SKM_Capybara_Animations.fbx | `SKM_Capybara_Walk` | 120–150 | 1.250 s | loop |
| `Capybara_Run` | SKM_Capybara_Animations.fbx | `SKM_Capybara_Run` | 230–245 | 0.625 s | loop |
| `Capybara_Attack` | SKM_Capybara_Animations.fbx | `SKM_Capybara_Attack` | 290–329 | 1.625 s | loop |
| `Capybara_Death` | SKM_Capybara_Animations.fbx | `SKM_Capybara_Death` | 350–373 | 0.958 s | once |

### Cat — 24 fps, 734 tris, 51 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Cat_Idle` | SKM_Cat_Animations.fbx | `Cat_Idle` | 0–80 | 3.333 s | loop |
| `Cat_Attack` | SKM_Cat_Animations.fbx | `Cat_Attack` | 120–158 | 1.583 s | once |
| `Cat_Idle_To_Walk` | SKM_Cat_Animations.fbx | `Cat_Idle_To_Walk` | 200–216 | 0.667 s | once |
| `Cat_Walk` | SKM_Cat_Animations.fbx | `Cat_Walk` | 230–266 | 1.500 s | loop |
| `Cat_Walk_To_Run` | SKM_Cat_Animations.fbx | `Cat_Walk_To_Run` | 280–296 | 0.667 s | once |
| `Cat_Idle_To_Run` | SKM_Cat_Animations.fbx | `Cat_Idle_To_Run` | 320–329 | 0.375 s | once |
| `Cat_Run` | SKM_Cat_Animations.fbx | `Cat_Run` | 345–359 | 0.583 s | loop |
| `Cat_Run_To_Idle` | SKM_Cat_Animations.fbx | `Cat_Run_To_Idle` | 370–381 | 0.458 s | once |
| `Cat_Death` | SKM_Cat_Animations.fbx | `Cat_Death` | 430–500 | 2.917 s | once |
| `Cat_Sleep` | SKM_Cat_Animations_Extra.fbx | `Cat_Sleep` | 600–650 | 2.083 s | loop |
| `Cat_Stand_To_Sleep` | SKM_Cat_Animations_Extra.fbx | `Cat_Stand_To_Sleep` | 550–600 | 2.083 s | once |
| `Take 001` | SKM_Cat_Rig.fbx | `Take 001` | — | 3.333 s | — |

### Chick — 24 fps, 618 tris, 47 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Chick_Idle1` | SKM_Chick_Animations.fbx | `Chick_Idle1` | 0–100 | 4.167 s | loop |
| `Chick_Idle2` | SKM_Chick_Animations.fbx | `Chick_Idle2` | 140–227 | 3.625 s | loop |
| `Chick_Walk` | SKM_Chick_Animations.fbx | `Chick_Walk` | 290–314 | 1.000 s | loop |
| `Chick_Run` | SKM_Chick_Animations.fbx | `Chick_Run` | 410–426 | 0.667 s | loop |
| `Chick_Attack` | SKM_Chick_Animations.fbx | `Chick_Attack` | 490–528 | 1.583 s | loop |
| `Chick_Death` | SKM_Chick_Animations.fbx | `Chick_Death` | 550–566 | 0.667 s | once |
| `Chick_Sleep` | SKM_Chick_Animations.fbx | `Chick_Sleep` | 600–650 | 2.083 s | loop |
| `Chick_Sleep_Stand` | SKM_Chick_Animations.fbx | `Chick_Sleep_Stand` | 650–690 | 1.667 s | once |
| `Chick_Eat` | SKM_Chick_Animations.fbx | `Chick_Eat` | 720–800 | 3.333 s | loop |

### Chimpanzee — 24 fps, 1542 tris, 100 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Chimpanzee_Idle_To_Walk` | SKM_Chimpanzee_Animations.fbx | `Chimpanzee_idle to walk` | 0–16 | 0.667 s | once |
| `Chimpanzee_Walk` | SKM_Chimpanzee_Animations.fbx | `Chimpanzee_walk` | 40–70 | 1.250 s | loop |
| `Chimpanzee_Walk_To_Idle` | SKM_Chimpanzee_Animations.fbx | `Chimpanzee_walk to idle` | 90–105 | 0.625 s | once |
| `Chimpanzee_Idle_To_Run` | SKM_Chimpanzee_Animations.fbx | `Chimpanzee_idle to run` | 140–146 | 0.250 s | once |
| `Chimpanzee_Run` | SKM_Chimpanzee_Animations.fbx | `Chimpanzee_run` | 170–184 | 0.583 s | loop |
| `Chimpanzee_Run_To_Idle` | SKM_Chimpanzee_Animations.fbx | `Chimpanzee_run to idle` | 200–210 | 0.417 s | once |
| `Chimpanzee_Idle_Breathing` | SKM_Chimpanzee_Animations.fbx | `'Chimpanzee_idle breathing '` | 240–280 | 1.667 s | loop |
| `Chimpanzee_Idle_Screaming` | SKM_Chimpanzee_Animations.fbx | `Chimpanzee_idle screaming` | 300–340 | 1.667 s | loop |
| `Chimpanzee_Idle_Banging_Chest` | SKM_Chimpanzee_Animations.fbx | `Chimpanzee_idle banging chest` | 360–443 | 3.458 s | loop |
| `Chimpanzee_Attack` | SKM_Chimpanzee_Animations.fbx | `Chimpanzee_attack` | 470–506 | 1.500 s | loop |
| `Chimpanzee_Death` | SKM_Chimpanzee_Animations.fbx | `Chimpanzee_death` | 520–556 | 1.500 s | once |

### Cockroach — 24 fps, 378 tris, 41 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Cockroach_Walk` | SKM_Cockroach_Animations.fbx | `Cockroach_Walk` | 1–15 | 0.583 s | loop |
| `Cockroach_Run` | SKM_Cockroach_Animations.fbx | `Cockroach_Run` | 21–28 | 0.292 s | loop |
| `Cockroach_Idle` | SKM_Cockroach_Animations.fbx | `Cockroach_Idle` | 50–120 | 2.917 s | loop |
| `Cockroach_Attack` | SKM_Cockroach_Animations.fbx | `Cockroach_Attack` | 130–150 | 0.833 s | loop |
| `Cockroach_Death` | SKM_Cockroach_Animations.fbx | `Cockroach_Death` | 160–180 | 0.833 s | once |
| `Take 001` | SKM_Cockroach_Rig.fbx | `Take 001` | — | 4.958 s | — |

### Cow — 24 fps, 5682 tris, 58 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Cow_Walk` | SKM_Cow_Horns_Legacy_Rig.fbx | `Take 001` | 1–35 | 1.417 s | loop |
| `Cow_Idle` | SKM_Cow_Horns_Legacy_Rig.fbx | `Take 001` | 42–105 | 2.625 s | loop |
| `Cow_Eating` | SKM_Cow_Horns_Legacy_Rig.fbx | `Take 001` | 107–200 | 3.875 s | loop |
| `Take 001` | SKM_Cow_Legacy_Rig.fbx | `Take 001` | — | 12.125 s | — |
| `Cow_Walk` | SKM_Cow_Animations.fbx | `Walk` | 1–37 | 1.500 s | loop |
| `Cow_Run` | SKM_Cow_Animations.fbx | `Run` | 45–59 | 0.583 s | loop |
| `Cow_Idle1` | SKM_Cow_Animations.fbx | `Idle1` | 65–141 | 3.167 s | loop |
| `Cow_Idle_2` | SKM_Cow_Animations.fbx | `Idle2` | 150–227 | 3.208 s | loop |
| `Cow_Attack` | SKM_Cow_Animations.fbx | `Attack` | 240–299 | 2.458 s | loop |
| `Cow_Death` | SKM_Cow_Animations.fbx | `Death` | 350–400 | 2.083 s | once |
| `Cow_Eat` | SKM_Cow_Animations.fbx | `Eat` | 410–499 | 3.708 s | loop |
| `Cow_Sleep` | SKM_Cow_Animations.fbx | `Sleep` | 520–550 | 1.250 s | loop |
| `Cow_Sleep_Stand` | SKM_Cow_Animations.fbx | `Sleep-Stand` | 550–616 | 2.750 s | once |
| `Cow_Death` | **Cow_Death.anim** (Unity `.anim`, unreadable by Godot) | — | — | 2.500 s | — |
| `Cow_Eating` | **Cow_Eating.anim** (Unity `.anim`, unreadable by Godot) | — | — | 3.875 s | — |
| `Cow_Idle` | **Cow_Idle.anim** (Unity `.anim`, unreadable by Godot) | — | — | 2.625 s | — |
| `Cow_Run` | **Cow_Run.anim** (Unity `.anim`, unreadable by Godot) | — | — | 1.167 s | — |
| `Cow_Walk` | **Cow_Walk.anim** (Unity `.anim`, unreadable by Godot) | — | — | 1.417 s | — |

### Crab — 24 fps, 1470 tris, 53 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Crab_Walk` | SKM_Crab_Animations.fbx | `Crab_Walk` | 1–34 | 1.375 s | loop |
| `Crab_Run` | SKM_Crab_Animations.fbx | `Crab_Run` | 35–44 | 0.375 s | loop |
| `Crab_Idle` | SKM_Crab_Animations.fbx | `Crab_Idle` | 50–150 | 4.167 s | loop |
| `Crab_Attack` | SKM_Crab_Animations.fbx | `Crab_Attack` | 170–210 | 1.667 s | loop |
| `Crab_Death` | SKM_Crab_Animations.fbx | `Crab_Death` | 250–276 | 1.083 s | once |
| `Take 001` | SKM_Crab_Rig.fbx | `Take 001` | — | 4.958 s | — |

### Crocodile — 24 fps, 1490 tris, 71 bones  ·  **one long take, needs slicing**

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Crocodile_Walk` | SKM_Crocodile_Rig.fbx | `Take 001` | 1–33 | 1.333 s | loop |
| `Crocodile_Idle` | SKM_Crocodile_Rig.fbx | `Take 001` | 40–195 | 6.458 s | loop |
| `Crocodile_Swim` | SKM_Crocodile_Rig.fbx | `Take 001` | 200–240 | 1.667 s | loop |
| `Crocodile_Attack_1` | SKM_Crocodile_Rig.fbx | `Take 001` | 245–290 | 1.875 s | loop |
| `Crocodile_Attack_2` | SKM_Crocodile_Rig.fbx | `Take 001` | 290–345 | 2.292 s | loop |
| `Crocodile_Death` | SKM_Crocodile_Rig.fbx | `Take 001` | 350–380 | 1.250 s | once |
| `Crocodile_Attack_1` | **Crocodile_Attack_1.anim** (Unity `.anim`, unreadable by Godot) | — | — | 1.875 s | — |
| `Crocodile_Attack_2` | **Crocodile_Attack_2.anim** (Unity `.anim`, unreadable by Godot) | — | — | 2.292 s | — |
| `Crocodile_Death` | **Crocodile_Death.anim** (Unity `.anim`, unreadable by Godot) | — | — | 1.250 s | — |
| `Crocodile_Idle` | **Crocodile_Idle.anim** (Unity `.anim`, unreadable by Godot) | — | — | 6.458 s | — |
| `Crocodile_Swim` | **Crocodile_Swim.anim** (Unity `.anim`, unreadable by Godot) | — | — | 1.667 s | — |
| `Crocodile_Walk` | **Crocodile_Walk.anim** (Unity `.anim`, unreadable by Godot) | — | — | 1.333 s | — |

### Deer — 24 fps, 1030 tris, 51 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Deer_Idle_To_Walk` | SKM_Deer_Animations.fbx | `deer_idle to walk` | 0–11 | 0.458 s | once |
| `Deer_Walk` | SKM_Deer_Animations.fbx | `deer_walk` | 30–54 | 1.000 s | loop |
| `Deer_Walk_To_Idle` | SKM_Deer_Animations.fbx | `deer_walk to idle` | 70–82 | 0.500 s | once |
| `Deer_Idle_Breath` | SKM_Deer_Animations.fbx | `deer_idle breath` | 110–140 | 1.250 s | loop |
| `Deer_Idle` | SKM_Deer_Animations.fbx | `deer_idle 2` | 160–346 | 7.750 s | loop |
| `Deer_Idle_To_Run` | SKM_Deer_Animations.fbx | `deer_idle to run` | 360–371 | 0.458 s | once |
| `Deer_Run` | SKM_Deer_Animations.fbx | `deer_run` | 390–404 | 0.583 s | loop |
| `Deer_Run_To_Idle` | SKM_Deer_Animations.fbx | `deer_run to idle` | 420–432 | 0.500 s | once |
| `Deer_Attack` | SKM_Deer_Animations.fbx | `deer_attack` | 450–504 | 2.250 s | loop |
| `Deer_Death` | SKM_Deer_Animations.fbx | `deer_death` | 530–554 | 1.000 s | once |
| `Deer_Eat` | SKM_Deer_Animations_Eat.fbx | `Take 001` | 1–280 | 11.625 s | loop |

### Dog Chihauhau — ? fps, 872 tris, 56 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Dog_Chihuahua_Bark` | **Dog_Chihuahua_Bark.anim** (Unity `.anim`, unreadable by Godot) | — | — | 0.667 s | — |
| `Dog_Chihuahua_Idle` | **Dog_Chihuahua_Idle.anim** (Unity `.anim`, unreadable by Godot) | — | — | 10.667 s | — |
| `Dog_Chihuahua_Run` | **Dog_Chihuahua_Run.anim** (Unity `.anim`, unreadable by Godot) | — | — | 0.625 s | — |
| `Dog_Chihuahua_Sit` | **Dog_Chihuahua_Sit.anim** (Unity `.anim`, unreadable by Godot) | — | — | 1.375 s | — |
| `Dog_Chihuahua_Walk` | **Dog_Chihuahua_Walk.anim** (Unity `.anim`, unreadable by Godot) | — | — | 1.417 s | — |

### Dog GoldenRetriever — ? fps, 928 tris, 56 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Dog_GoldenRetriever_Bark` | **Dog_GoldenRetriever_Bark.anim** (Unity `.anim`, unreadable by Godot) | — | — | 1.042 s | — |
| `Dog_GoldenRetriever_Idle` | **Dog_GoldenRetriever_Idle.anim** (Unity `.anim`, unreadable by Godot) | — | — | 7.500 s | — |
| `Dog_GoldenRetriever_Run` | **Dog_GoldenRetriever_Run.anim** (Unity `.anim`, unreadable by Godot) | — | — | 0.708 s | — |
| `Dog_GoldenRetriever_Sit` | **Dog_GoldenRetriever_Sit.anim** (Unity `.anim`, unreadable by Godot) | — | — | 1.042 s | — |
| `Dog_GoldenRetriever_Stand` | **Dog_GoldenRetriever_Stand.anim** (Unity `.anim`, unreadable by Godot) | — | — | 0.833 s | — |
| `Dog_GoldenRetriever_Walk` | **Dog_GoldenRetriever_Walk.anim** (Unity `.anim`, unreadable by Godot) | — | — | 1.208 s | — |

### Dog GreatDane — ? fps, 988 tris, 55 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Take 001` | SKM_Dog_GreatDane_Rig.fbx | `Take 001` | — | 4.958 s | — |
| `Dog_GreatDane_Bark` | **Dog_GreatDane_Bark.anim** (Unity `.anim`, unreadable by Godot) | — | — | 0.833 s | — |
| `Dog_GreatDane_Idle` | **Dog_GreatDane_Idle.anim** (Unity `.anim`, unreadable by Godot) | — | — | 6.458 s | — |
| `Dog_GreatDane_Run` | **Dog_GreatDane_Run.anim** (Unity `.anim`, unreadable by Godot) | — | — | 0.542 s | — |
| `Dog_GreatDane_Sit` | **Dog_GreatDane_Sit.anim** (Unity `.anim`, unreadable by Godot) | — | — | 1.458 s | — |
| `Dog_GreatDane_Stand` | **Dog_GreatDane_Stand.anim** (Unity `.anim`, unreadable by Godot) | — | — | 1.667 s | — |
| `Dog_GreatDane_Walk` | **Dog_GreatDane_Walk.anim** (Unity `.anim`, unreadable by Godot) | — | — | 0.833 s | — |

### Dolphin — 24 fps, 902 tris, 34 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Dolphine_Idle` | SKM_Dolphin_Animations.fbx | `Dolphine_Idle` | 0–40 | 1.667 s | loop |
| `Dolphine_Idle_2` | SKM_Dolphin_Animations.fbx | `Dolphine_Idle2` | 70–150 | 3.333 s | once |
| `Dolphine_Idle_To_Swim` | SKM_Dolphin_Animations.fbx | `Dolphine_Idle to Swim` | 180–195 | 0.625 s | once |
| `Dolphine_Swimming` | SKM_Dolphin_Animations.fbx | `Dolphine_Swimming` | 220–250 | 1.250 s | loop |
| `Dolphine_Swim_Jump` | SKM_Dolphin_Animations.fbx | `Dolphine_Swim jump` | 280–347 | 2.792 s | loop |
| `Dolphine_Attack` | SKM_Dolphin_Animations.fbx | `Dolphine_Attack` | 370–430 | 2.500 s | loop |
| `Dolphine_Swim_To_Idle` | SKM_Dolphin_Animations.fbx | `Dolphine_Swim to Idle` | 460–490 | 1.250 s | once |
| `Dolphine_Death_Progressive` | SKM_Dolphin_Animations.fbx | `Dolphine_Death progpressive` | 416–582 | 6.917 s | once |
| `Dolphine_Death_Inplace` | SKM_Dolphin_Animations.fbx | `Dolphine_Death Inplace` | 650–720 | 2.917 s | once |

### DoveRock — 24 fps, 832 tris, 45 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `DoveRock_Idle_Left` | SKM_DoveRock_Animations.fbx | `Dove_Idle Left` | 0–95 | 3.958 s | loop |
| `DoveRock_Idle_Right` | SKM_DoveRock_Animations.fbx | `Dove_Idle Right` | 120–215 | 3.958 s | loop |
| `DoveRock_Idle_To_Walk` | SKM_DoveRock_Animations.fbx | `Dove_Idle to Walk` | 230–240 | 0.417 s | once |
| `DoveRock_Walk` | SKM_DoveRock_Animations.fbx | `Dove_Walk` | 250–278 | 1.167 s | loop |
| `DoveRock_Walk_To_Idle` | SKM_DoveRock_Animations.fbx | `Dove_Walk to Idle` | 290–300 | 0.417 s | once |
| `DoveRock_Idle_To_Run` | SKM_DoveRock_Animations.fbx | `Dove_Idle to Run` | 310–317 | 0.292 s | once |
| `DoveRock_Run` | SKM_DoveRock_Animations.fbx | `Dove_Run` | 330–344 | 0.583 s | loop |
| `DoveRock_Run_To_Idle` | SKM_DoveRock_Animations.fbx | `'Dove_Run to Idle '` | 363–370 | 0.292 s | once |
| `DoveRock_Idle_To_Fly` | SKM_DoveRock_Animations.fbx | `Dove_Idle to Fly` | 400–409 | 0.375 s | once |
| `DoveRock_Fly` | SKM_DoveRock_Animations.fbx | `Dove_Fly` | 420–434 | 0.583 s | loop |
| `DoveRock_Fly_To_Idle` | SKM_DoveRock_Animations.fbx | `Dove_Fly to Idle` | 452–462 | 0.417 s | once |
| `DoveRock_Atttack` | SKM_DoveRock_Animations.fbx | `Dove_Atttack` | 480–520 | 1.667 s | loop |
| `DoveRock_Death` | SKM_DoveRock_Animations.fbx | `Dove_Death` | 550–571 | 0.875 s | once |

### Eagle — 24 fps, 1012 tris, 113 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Eagle_Idle` | SKM_Eagle_Animations.fbx | `Eagle_Idle` | 0–76 | 3.167 s | loop |
| `Eagle_Fly_Start` | SKM_Eagle_Animations.fbx | `Eagle_Fly Start` | 100–141 | 1.708 s | once |
| `Eagle_Flying` | SKM_Eagle_Animations.fbx | `Eagle_Flying` | 180–264 | 3.500 s | loop |
| `Eagle_Flying_To_Fly_Idle` | SKM_Eagle_Animations.fbx | `Eagle_Flying to fly idle` | 300–310 | 0.417 s | once |
| `Eagle_Fly_Idle` | SKM_Eagle_Animations.fbx | `Eagle_Fly idle` | 330–410 | 3.333 s | once |
| `Eagle_Fly_Idle_To_Flying` | SKM_Eagle_Animations.fbx | `Eagle_Fly idle to flying` | 450–461 | 0.458 s | once |
| `Eagle_Flying_Attack` | SKM_Eagle_Animations.fbx | `Eagle_Flying attack` | 511–548 | 1.542 s | loop |
| `Eagle_Flying_To_Idle` | SKM_Eagle_Animations.fbx | `Eagle_Flying to idle` | 570–620 | 2.083 s | once |
| `Eagle_Idle_To_Walk` | SKM_Eagle_Animations.fbx | `Eagle_Idle to walk` | 640–654 | 0.583 s | once |
| `Eagle_Walk` | SKM_Eagle_Animations.fbx | `Eagle_Walk` | 665–693 | 1.167 s | loop |
| `Eagle_Walk_To_Idle` | SKM_Eagle_Animations.fbx | `Eagle_Walk to idle` | 720–733 | 0.542 s | once |
| `Eagle_Idle_To_Run` | SKM_Eagle_Animations.fbx | `Eagle_Idle to Run` | 750–757 | 0.292 s | once |
| `Eagle_Run` | SKM_Eagle_Animations.fbx | `Eagle_Run` | 780–794 | 0.583 s | loop |
| `Eagle_Run_To_Idle` | SKM_Eagle_Animations.fbx | `Eagle_Run to idle` | 805–814 | 0.375 s | once |
| `Eagle_Death` | SKM_Eagle_Animations.fbx | `Eagle_Death` | 830–854 | 1.000 s | once |

### Elephant — 24 fps, 1822 tris, 92 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Elephant_idle` | SKM_Elephant_Animations.fbx | `Elephant_Elephant_idle` | 0–60 | 2.500 s | loop |
| `Elephant_idle_2` | SKM_Elephant_Animations.fbx | `Elephant_Elephant_idle2` | 60–120 | 2.500 s | loop |
| `Elephant_Idle_To_Walk` | SKM_Elephant_Animations.fbx | `Elephant_Elephant_idle_to_walk` | 120–140 | 0.833 s | once |
| `Elephant_Walk` | SKM_Elephant_Animations.fbx | `Elephant_Elephant_walk` | 140–192 | 2.167 s | loop |
| `Elephant_Walk_To_Idle` | SKM_Elephant_Animations.fbx | `Elephant_Elephant_walk_to_idle` | 192–212 | 0.833 s | once |
| `Elephant_Idle_To_Run` | SKM_Elephant_Animations.fbx | `Elephant_Elephant_idle_to_run` | 212–221 | 0.375 s | once |
| `Elephant_Run` | SKM_Elephant_Animations.fbx | `Elephant_Elephant_run` | 221–239 | 0.750 s | loop |
| `Elephant_Run_To_Idle` | SKM_Elephant_Animations.fbx | `Elephant_Elephant_run_to_idle` | 239–248 | 0.375 s | once |
| `Elephant_Attack` | SKM_Elephant_Animations.fbx | `Elephant_Elephant_attack` | 248–292 | 1.833 s | loop |
| `Elephant_Death` | SKM_Elephant_Animations.fbx | `Elephant_Elephant_death` | 292–323 | 1.292 s | once |
| `Elephant_Female_Walk` | SKM_Elephant_Female_Animations.fbx | `Elephant_Walk` | 1–52 | 2.125 s | loop |
| `Elephant_Female_Run` | SKM_Elephant_Female_Animations.fbx | `Elephant_Run` | 60–79 | 0.792 s | loop |
| `Elephant_Female_Idle` | SKM_Elephant_Female_Animations.fbx | `Elephant_Idle` | 100–250 | 6.250 s | loop |
| `Elephant_Female_Attack` | SKM_Elephant_Female_Animations.fbx | `Elephant_Attack` | 300–350 | 2.083 s | loop |
| `Elephant_Female_Death` | SKM_Elephant_Female_Animations.fbx | `Elephant_Death` | 400–431 | 1.292 s | once |

### Fish — 24 fps, 148 tris, 14 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Fish_Swim` | SKM_Fish.fbx | `Take 001` | 1–35 | 1.417 s | loop |
| `Fish_Swim` | **Fish_Swim.anim** (Unity `.anim`, unreadable by Godot) | — | — | 1.417 s | — |

### Flamingo — 24 fps, 1482 tris, 105 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Flamingo_Walk` | SKM_Flamingo_Animations.fbx | `Walk` | 1–40 | 1.625 s | loop |
| `Flamingo_Run` | SKM_Flamingo_Animations.fbx | `Run` | 50–65 | 0.625 s | loop |
| `Flamingo_Idle` | SKM_Flamingo_Animations.fbx | `Idle` | 70–225 | 6.458 s | loop |
| `Flamingo_Attack` | SKM_Flamingo_Animations.fbx | `Attack` | 240–303 | 2.625 s | loop |
| `Flamingo_Death` | SKM_Flamingo_Animations.fbx | `Death` | 310–340 | 1.250 s | once |
| `Take 001` | SKM_Flamingo_Rig.fbx | `Take 001` | — | 4.167 s | — |

### Fox — 24 fps, 1870 tris, 55 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Fox_Idle` | SKM_Fox.fbx | `Fox_Idle` | 0–170 | 7.083 s | loop |
| `Fox_Idle_To_Walk` | SKM_Fox.fbx | `Fox_Idle to Walk` | 190–202 | 0.500 s | once |
| `Fox_Walk` | SKM_Fox.fbx | `Fox_Walk` | 230–264 | 1.417 s | loop |
| `Fox_Walk_To_Idle` | SKM_Fox.fbx | `Fox_Walk to Idle` | 290–307 | 0.708 s | once |
| `Fox_Idle_To_Run` | SKM_Fox.fbx | `Fox_Idle to Run` | 315–323 | 0.333 s | once |
| `Fox_Run` | SKM_Fox.fbx | `Fox_Run` | 330–342 | 0.500 s | loop |
| `Fox_Run_To_Idle` | SKM_Fox.fbx | `Fox_Run to Idle` | 360–372 | 0.500 s | once |
| `Fox_Attack` | SKM_Fox.fbx | `Fox_Attack` | 390–470 | 3.333 s | loop |
| `Fox_Death` | SKM_Fox.fbx | `Fox_Death` | 500–535 | 1.458 s | once |

### Giraffe — 24 fps, 4630 tris, 70 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Giraffe_Legacy_Idle` | SKM_Giraffe_Animations_Legacy.fbx | `Giraffe_idle` | 0–45 | 1.875 s | loop |
| `Giraffe_Legacy_Idle_To_Walk` | SKM_Giraffe_Animations_Legacy.fbx | `Giraffe_idle to walk` | 60–71 | 0.458 s | once |
| `Giraffe_Legacy_Walk` | SKM_Giraffe_Animations_Legacy.fbx | `Giraffe_walk` | 90–120 | 1.250 s | loop |
| `Giraffe_Legacy_Walk_To_Idle` | SKM_Giraffe_Animations_Legacy.fbx | `Giraffe_walk to idle` | 130–142 | 0.500 s | once |
| `Giraffe_Legacy__idle_2` | SKM_Giraffe_Animations_Legacy.fbx | `Giraffe_idle2` | 180–233 | 2.208 s | loop |
| `Giraffe_Legacy_Idle_To_Run` | SKM_Giraffe_Animations_Legacy.fbx | `Giraffe_idle to run` | 270–281 | 0.458 s | once |
| `Giraffe_Legacy_Run` | SKM_Giraffe_Animations_Legacy.fbx | `Giraffe_run` | 300–319 | 0.792 s | loop |
| `Giraffe_Legacy_Run_To_Idle` | SKM_Giraffe_Animations_Legacy.fbx | `Giraffe_run to idle` | 330–345 | 0.625 s | once |
| `Giraffe_Legacy_Attack` | SKM_Giraffe_Animations_Legacy.fbx | `Giraffe_attack` | 360–414 | 2.250 s | loop |
| `Giraffe_Legacy_Death` | SKM_Giraffe_Animations_Legacy.fbx | `Giraffe_death` | 440–488 | 2.000 s | once |
| `Giraffe_Walk` | SKM_Giraffe_Animations.fbx | `Giraffe_Walk` | 1–24 | 0.958 s | loop |
| `Giraffe_Run` | SKM_Giraffe_Animations.fbx | `Giraffe_Run` | 32–46 | 0.583 s | loop |
| `Giraffe_Eating` | SKM_Giraffe_Animations.fbx | `Giraffe_Eating` | 60–120 | 2.500 s | loop |
| `Giraffe_Drink_To` | SKM_Giraffe_Animations.fbx | `Giraffe_Drink_To` | 120–180 | 2.500 s | once |
| `Giraffe_Drink` | SKM_Giraffe_Animations.fbx | `Giraffe_Drink` | 180–224 | 1.833 s | loop |
| `Giraffe_Attack` | SKM_Giraffe_Animations.fbx | `Giraffe_Attack` | 240–320 | 3.333 s | loop |
| `Giraffe_Death` | SKM_Giraffe_Animations.fbx | `Giraffe_Death` | 320–340 | 0.833 s | once |
| `Take 001` | SKM_Giraffe_Rig.fbx | `Take 001` | — | 46.500 s | — |

### Goat — 24 fps, 1458 tris, 53 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Goat_Idle` | SKM_Goat_Animation.fbx | `Idle` | 0–30 | 1.250 s | loop |
| `Goat_Walk` | SKM_Goat_Animation.fbx | `Walk` | 90–113 | 0.958 s | loop |
| `Goat_Scream` | SKM_Goat_Animation.fbx | `Scream` | 180–233 | 2.208 s | loop |
| `Goat_Run` | SKM_Goat_Animation.fbx | `Run` | 300–314 | 0.583 s | loop |
| `Goat_Attack` | SKM_Goat_Animation.fbx | `Attack` | 360–414 | 2.250 s | loop |
| `Goat_Death` | SKM_Goat_Animation.fbx | `Death` | 440–469 | 1.208 s | once |
| `Goat_Sleep` | SKM_Goat_Animation.fbx | `Sleep` | 500–550 | 2.083 s | loop |
| `Goat_Sleep_Stand` | SKM_Goat_Animation.fbx | `Sleep-Stand` | 550–620 | 2.917 s | once |
| `Goat_Eating` | SKM_Goat_Animation.fbx | `Eating` | 630–700 | 2.917 s | loop |

### Goose — 24 fps, 1158 tris, 86 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Goose_Idle` | SKM_Goose_Animations.fbx | `Goose_Idle` | 0–60 | 2.500 s | loop |
| `Goose_Idle_2` | SKM_Goose_Animations.fbx | `Goose_Idle 2` | 100–160 | 2.500 s | loop |
| `Goose_Idle_3` | SKM_Goose_Animations.fbx | `Goose_Idle 3` | 180–272 | 3.833 s | loop |
| `Goose_Idle_4` | SKM_Goose_Animations.fbx | `Goose_Idle 4` | 330–360 | 1.250 s | loop |
| `Goose_Walk` | SKM_Goose_Animations.fbx | `Goose_Walk` | 420–450 | 1.250 s | loop |
| `Goose_Run` | SKM_Goose_Animations.fbx | `Goose_Run` | 540–556 | 0.667 s | loop |
| `Goose_Fly` | SKM_Goose_Animations.fbx | `Goose_Fly` | 640–660 | 0.833 s | loop |
| `Goose_Attack` | SKM_Goose_Animations.fbx | `Goose_Attack` | 740–776 | 1.500 s | loop |
| `Goose_Death` | SKM_Goose_Animations.fbx | `Goose_Death` | 810–836 | 1.083 s | once |
| `Goose_Sleep` | SKM_Goose_Animations.fbx | `Goose_Sleep` | 900–950 | 2.083 s | loop |
| `Goose_Sleep_Stand` | SKM_Goose_Animations.fbx | `Goose_Sleep_Stand` | 950–1000 | 2.083 s | once |
| `Goose_Eat` | SKM_Goose_Animations.fbx | `Goose_Eat` | 1100–1250 | 6.250 s | loop |

### Gorilla — ? fps, 1282 tris, 97 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Gorilla_Attack` | **Gorilla_Attack.anim** (Unity `.anim`, unreadable by Godot) | — | — | 1.625 s | — |
| `Gorilla_ChestHit` | **Gorilla_ChestHit.anim** (Unity `.anim`, unreadable by Godot) | — | — | 3.833 s | — |
| `Gorilla_Death` | **Gorilla_Death.anim** (Unity `.anim`, unreadable by Godot) | — | — | 1.667 s | — |
| `Gorilla_Idle` | **Gorilla_Idle.anim** (Unity `.anim`, unreadable by Godot) | — | — | 7.500 s | — |
| `Gorilla_Run` | **Gorilla_Run.anim** (Unity `.anim`, unreadable by Godot) | — | — | 0.875 s | — |
| `Gorilla_Walk` | **Gorilla_Walk.anim** (Unity `.anim`, unreadable by Godot) | — | — | 1.000 s | — |

### Hen — 24 fps, 894 tris, 92 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Hen_Idle Breathing` | SKM_Hen_Animations.fbx | `Hen_Idle Breathing` | — | 2.500 s | — |
| `Hen_Idle_Roost` | SKM_Hen_Animations.fbx | `Hen_Idle_Roost` | — | 2.500 s | — |
| `Hen_Idle_2` | SKM_Hen_Animations.fbx | `Hen_Idle_2` | — | 4.500 s | — |
| `Hen_Walk` | SKM_Hen_Animations.fbx | `Hen_Walk` | — | 1.250 s | — |
| `Hen_Run` | SKM_Hen_Animations.fbx | `Hen_Run` | — | 0.667 s | — |
| `Hen_Fly` | SKM_Hen_Animations.fbx | `Hen_Fly` | — | 0.833 s | — |
| `Hen_Attack` | SKM_Hen_Animations.fbx | `Hen_Attack` | — | 1.500 s | — |
| `Hen_Death` | SKM_Hen_Animations.fbx | `Hen_Death` | — | 1.083 s | — |
| `Hen_Idle_3` | SKM_Hen_Animations.fbx | `Hen_Idle_3` | — | 1.250 s | — |
| `Hen_Sleep` | SKM_Hen_Animations.fbx | `Hen_Sleep` | — | 2.083 s | — |
| `Hen_Sleep_Stand` | SKM_Hen_Animations.fbx | `Hen_Sleep_Stand` | — | 1.042 s | — |
| `Hen_Eat` | SKM_Hen_Animations.fbx | `Hen_Eat` | — | 4.167 s | — |
| `Hen_Idle breath` | SKM_Hen_Rig.fbx | `Hen_Idle breath` | 0–60 | 2.500 s | loop |
| `Hen_Idle roast` | SKM_Hen_Rig.fbx | `Hen_Idle roast` | 100–160 | 2.500 s | loop |
| `Hen_Idle2` | SKM_Hen_Rig.fbx | `Hen_Idle2` | 180–288 | 4.500 s | loop |
| `Hen_Idle3` | SKM_Hen_Rig.fbx | `Hen_Idle3` | 330–360 | 1.250 s | loop |
| `Hen_Idle to slow walk` | SKM_Hen_Rig.fbx | `Hen_Idle to slow walk` | 380–395 | 0.625 s | once |
| `Hen_Slow walk` | SKM_Hen_Rig.fbx | `Hen_Slow walk` | 420–468 | 2.000 s | loop |
| `Hen_Slow walk to idle` | SKM_Hen_Rig.fbx | `Hen_Slow walk to idle` | 490–505 | 0.625 s | once |
| `Hen_Idle to run` | SKM_Hen_Rig.fbx | `Hen_Idle to run` | 530–538 | 0.333 s | once |
| `Hen_Run` | SKM_Hen_Rig.fbx | `Hen_Run` | 570–586 | 0.667 s | loop |
| `Hen_Run to idle` | SKM_Hen_Rig.fbx | `Hen_Run to idle` | 600–611 | 0.458 s | once |
| `Hen_Idle to fly` | SKM_Hen_Rig.fbx | `Hen_Idle to fly` | 640–650 | 0.417 s | once |
| `Hen_Flying` | SKM_Hen_Rig.fbx | `Hen_Flying` | 670–690 | 0.833 s | loop |
| `Hen_Fly to idle` | SKM_Hen_Rig.fbx | `Hen_Fly to idle` | 715–725 | 0.417 s | once |
| `Hen_Idle to walk` | SKM_Hen_Rig.fbx | `Hen_Idle to walk` | 750–765 | 0.625 s | once |
| `Hen_Walk` | SKM_Hen_Rig.fbx | `Hen_Walk` | 790–820 | 1.250 s | loop |
| `Hen_Walk to idle` | SKM_Hen_Rig.fbx | `Hen_Walk to idle` | 840–855 | 0.625 s | once |
| `Hen_Attack` | SKM_Hen_Rig.fbx | `Hen_Attack` | 900–936 | 1.500 s | loop |
| `Hen_Death` | SKM_Hen_Rig.fbx | `Hen_Death` | 970–996 | 1.083 s | once |

### Hippo — 24 fps, 1666 tris, 54 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Hippo_Idle` | SKM_Hippo_Animations.fbx | `Hippo_Idle` | 0–40 | 1.667 s | loop |
| `Hippo_Idle_2` | SKM_Hippo_Animations.fbx | `Hippo_Idle2` | 80–200 | 5.000 s | once |
| `Hippo_Idle_To_Walk` | SKM_Hippo_Animations.fbx | `Hippo_Idle to Walk` | 230–245 | 0.625 s | once |
| `Hippo_Walk` | SKM_Hippo_Animations.fbx | `Hippo_Walk` | 270–300 | 1.250 s | loop |
| `Hippo_Walk_To_Idle` | SKM_Hippo_Animations.fbx | `Hippo_Walk to Idle` | 320–340 | 0.833 s | once |
| `Hippo_Idle_To_Run` | SKM_Hippo_Animations.fbx | `Hippo_Idle to Run` | 360–368 | 0.333 s | once |
| `Hippo_Run` | SKM_Hippo_Animations.fbx | `Hippo_Run` | 385–401 | 0.667 s | loop |
| `Hippo_Run_To_Idle` | SKM_Hippo_Animations.fbx | `Hippo_Run to Idle` | 415–423 | 0.333 s | once |
| `Hippo_Attack` | SKM_Hippo_Animations.fbx | `Hippo_Attack` | 440–474 | 1.417 s | loop |
| `Hippo_Death` | SKM_Hippo_Animations.fbx | `Hippo_Death` | 500–540 | 1.667 s | once |

### Horse — 24 fps, 1928 tris, 51 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Take 001` | SKM_Horse_Legacy_Rig.fbx | `Take 001` | — | 4.958 s | — |
| `Horse_Walk` | SKM_Horse_Animations.fbx | `Walk` | 1–43 | 1.750 s | loop |
| `Horse_Run` | SKM_Horse_Animations.fbx | `Run` | 53–68 | 0.625 s | loop |
| `Horse_Idle` | SKM_Horse_Animations.fbx | `Idle` | 78–149 | 2.958 s | loop |
| `Horse_Attack` | SKM_Horse_Animations.fbx | `Attack` | 159–205 | 1.917 s | loop |
| `Horse_Death` | SKM_Horse_Animations.fbx | `Death` | 215–293 | 3.250 s | once |
| `Horse_Eating` | SKM_Horse_Animations.fbx | `Eating` | 430–600 | 7.083 s | loop |
| `Horse_Sleeping` | SKM_Horse_Animations.fbx | `Sleeping` | 300–350 | 2.083 s | loop |
| `Horse_Sleep_Stand` | SKM_Horse_Animations.fbx | `Sleep_Stand` | 350–425 | 3.125 s | once |
| `Horse_Legacy_Death` | **Horse_Legacy_Death.anim** (Unity `.anim`, unreadable by Godot) | — | — | 2.083 s | — |
| `Horse_Legacy_Eating` | **Horse_Legacy_Eating.anim** (Unity `.anim`, unreadable by Godot) | — | — | 8.708 s | — |
| `Horse_Legacy_Idle` | **Horse_Legacy_Idle.anim** (Unity `.anim`, unreadable by Godot) | — | — | 9.792 s | — |
| `Horse_Legacy_Run` | **Horse_Legacy_Run.anim** (Unity `.anim`, unreadable by Godot) | — | — | 0.458 s | — |
| `Horse_Legacy_Walk` | **Horse_Legacy_Walk.anim** (Unity `.anim`, unreadable by Godot) | — | — | 1.917 s | — |

### JellyFish — ? fps, 954 tris, 126 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Jellyfish_Idle` | **JellyFish_Idle.anim** (Unity `.anim`, unreadable by Godot) | — | — | 2.875 s | — |

### Lion — 24 fps, 1982 tris, 79 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Lion_Legacy_Idle_Breathing` | SKM_Lion_Legacy_Animations.fbx | `Lion_idle breathing` | 0–80 | 3.333 s | loop |
| `Lion_Idle_To_Walk_Legacy` | SKM_Lion_Legacy_Animations.fbx | `Lion_idle to walk` | 100–116 | 0.667 s | once |
| `Lion_Legacy_Walk` | SKM_Lion_Legacy_Animations.fbx | `Lion_walk` | 130–166 | 1.500 s | loop |
| `Lion_Legacy_Walk_To_Idle` | SKM_Lion_Legacy_Animations.fbx | `Lion_walk to idle` | 180–196 | 0.667 s | once |
| `Lion_Legacy_Idle_Roar` | SKM_Lion_Legacy_Animations.fbx | `Lion_idle roar` | 220–286 | 2.750 s | once |
| `Lion_Legacy_Idle_To_Run` | SKM_Lion_Legacy_Animations.fbx | `Lion_idle to run` | 310–319 | 0.375 s | once |
| `Lion_Legacy_Run` | SKM_Lion_Legacy_Animations.fbx | `Lion_run` | 335–349 | 0.583 s | loop |
| `Lion_Legacy_Run_To_Idle` | SKM_Lion_Legacy_Animations.fbx | `Lion_run to idle` | 360–371 | 0.458 s | once |
| `Lion_Legacy_Attack` | SKM_Lion_Legacy_Animations.fbx | `Lion_attack` | 390–448 | 2.417 s | loop |
| `Lion_Legacy_Death` | SKM_Lion_Legacy_Animations.fbx | `Lion_death` | 470–534 | 2.667 s | once |
| `Lion_Female_Walk` | SKM_Lion_Female_Animations.fbx | `Lion_Female_Walk` | 1–34 | 1.375 s | loop |
| `Lion_Female_Run` | SKM_Lion_Female_Animations.fbx | `Lion_Female_Run` | 50–62 | 0.500 s | loop |
| `Lion_Female_Idle` | SKM_Lion_Female_Animations.fbx | `Lion_Female_Idle` | 80–220 | 5.833 s | loop |
| `Lion_Female_Attack` | SKM_Lion_Female_Animations.fbx | `Lion_Female_Attack` | 250–285 | 1.458 s | loop |
| `Lion_Female_Death` | SKM_Lion_Female_Animations.fbx | `Lion_Female_Death` | 300–335 | 1.458 s | once |
| `Lion_Male_Idle_Breathing` | SKM_Lion_Male_Animations.fbx | `SKM_Lion_Animations_Lion_idle_breathing` | 1–81 | 3.333 s | loop |
| `Lion_Male_Idle_To_Walk` | SKM_Lion_Male_Animations.fbx | `SKM_Lion_Animations_Lion_idle_to_walk` | 81–97 | 0.667 s | once |
| `Lion_Male_Walk` | SKM_Lion_Male_Animations.fbx | `SKM_Lion_Animations_Lion_walk` | 97–133 | 1.500 s | loop |
| `Lion_Male_Walk_To_Idle` | SKM_Lion_Male_Animations.fbx | `SKM_Lion_Animations_Lion_walk_to_idle` | 133–149 | 0.667 s | once |
| `Lion_Male_Idle_Roar` | SKM_Lion_Male_Animations.fbx | `SKM_Lion_Animations_Lion_idle_roar` | 149–215 | 2.750 s | once |
| `Lion_Male_Idle_To_Run` | SKM_Lion_Male_Animations.fbx | `SKM_Lion_Animations_Lion_idle_to_run` | 215–224 | 0.375 s | once |
| `Lion_Male_Run` | SKM_Lion_Male_Animations.fbx | `SKM_Lion_Animations_Lion_run` | 224–238 | 0.583 s | loop |
| `Lion_Male_Run_To_Idle` | SKM_Lion_Male_Animations.fbx | `SKM_Lion_Animations_Lion_run_to_idle` | 238–249 | 0.458 s | once |
| `Lion_Male_Attack` | SKM_Lion_Male_Animations.fbx | `SKM_Lion_Animations_Lion_attack` | 249–307 | 2.417 s | loop |
| `Lion_Male_Death` | SKM_Lion_Male_Animations.fbx | `SKM_Lion_Animations_Lion_death` | 307–371 | 2.667 s | once |

### Meerkat — 24 fps, 1818 tris, 126 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Meerkat_Walk` | SKM_Meerkat_Animations.fbx | `Walk` | 1–17 | 0.667 s | loop |
| `Meerkat_Run` | SKM_Meerkat_Animations.fbx | `Run` | 20–30 | 0.417 s | loop |
| `Meerkat_Idle_Standing_In` | SKM_Meerkat_Animations.fbx | `Idle` | 43–57 | 0.583 s | loop |
| `Meerkat_Attack` | SKM_Meerkat_Animations.fbx | `Attack` | 110–140 | 1.250 s | loop |
| `Meerkat_Death` | SKM_Meerkat_Animations.fbx | `Death` | 145–170 | 1.042 s | once |
| `Meerkat_Idle_Floor` | SKM_Meerkat_Animations.fbx | `Idle_V2` | 180–450 | 11.250 s | once |
| `Meerkat_Idle_Standing` | SKM_Meerkat_Animations.fbx | `Idle` | 62–76 | 0.583 s | loop |
| `Meerkat_Idle_Standing_Out` | SKM_Meerkat_Animations.fbx | `Idle` | 85–104 | 0.792 s | once |
| `Take 001` | SKM_Meerkat_Rig.fbx | `Take 001` | — | 4.958 s | — |

### Octopus — 24 fps, 2172 tris, 60 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Octopus_Idle` | SKM_Octopus_Animations.fbx | `Octopus_Idle` | 0–80 | 3.333 s | loop |
| `Octopus_Idle_To_Swim` | SKM_Octopus_Animations.fbx | `Octopus_Idle to Swim` | 120–150 | 1.250 s | once |
| `Octopus_Swim` | SKM_Octopus_Animations.fbx | `Octopus_Swim` | 190–270 | 3.333 s | loop |
| `Octopus_Swim_To_Idle` | SKM_Octopus_Animations.fbx | `Octopus_Swim to Idle` | 310–345 | 1.458 s | once |
| `Octopus_Attack` | SKM_Octopus_Animations.fbx | `Octopus_Attack` | 400–450 | 2.083 s | loop |
| `Octopus_Death` | SKM_Octopus_Animations.fbx | `Octopus_Death` | 500–548 | 2.000 s | once |

### Orca — ? fps, 944 tris, 29 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Orca_Attack` | **Orca_Attack.anim** (Unity `.anim`, unreadable by Godot) | — | — | 1.375 s | — |
| `Orca_Death` | **Orca_Death.anim** (Unity `.anim`, unreadable by Godot) | — | — | 2.292 s | — |
| `Orca_Eat` | **Orca_Eat.anim** (Unity `.anim`, unreadable by Godot) | — | — | 1.375 s | — |
| `Orca_Idle` | **Orca_Idle.anim** (Unity `.anim`, unreadable by Godot) | — | — | 1.375 s | — |
| `Orca_Swim` | **Orca_Swim.anim** (Unity `.anim`, unreadable by Godot) | — | — | 1.375 s | — |

### Ostrich — 24 fps, 988 tris, 70 bones  ·  **one long take, needs slicing**

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Ostrich_Walk` | SKM_Ostrich_Animations.fbx | `Take 001` | 1–40 | 1.625 s | loop |
| `Ostrich_Run` | SKM_Ostrich_Animations.fbx | `Take 001` | 60–80 | 0.833 s | loop |
| `Ostrich_Idle` | SKM_Ostrich_Animations.fbx | `Take 001` | 100–300 | 8.333 s | loop |
| `Ostrich_Attack` | SKM_Ostrich_Animations.fbx | `Take 001` | 500–550 | 2.083 s | loop |
| `Ostrich_Death` | SKM_Ostrich_Animations.fbx | `Take 001` | 400–452 | 2.167 s | once |
| `Take 001` | SKM_Ostrich_Rig.fbx | `Take 001` | — | 4.958 s | — |

### Panda — 24 fps, 1710 tris, 89 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Panda_Idle` | SKM_Panda_Animations.fbx | `Panda_Idle` | 0–45 | 1.875 s | once |
| `Panda_Idle_To_Walk` | SKM_Panda_Animations.fbx | `Panda_Idle to Walk` | 80–94 | 0.583 s | once |
| `Panda_Walk` | SKM_Panda_Animations.fbx | `Panda_Walk` | 110–150 | 1.667 s | loop |
| `Panda_Walk_To_Idle` | SKM_Panda_Animations.fbx | `Panda_Walk to Idle` | 170–184 | 0.583 s | once |
| `Panda_Idle_To_Run` | SKM_Panda_Animations.fbx | `Panda_Idle to Run` | 200–208 | 0.333 s | once |
| `Panda_Run` | SKM_Panda_Animations.fbx | `Panda_Run` | 230–246 | 0.667 s | loop |
| `Panda_Run_To_Idle` | SKM_Panda_Animations.fbx | `Panda_Run to Idle` | 270–280 | 0.417 s | once |
| `Panda_Attack` | SKM_Panda_Animations.fbx | `Panda_Attack` | 300–332 | 1.333 s | loop |
| `Panda_Death` | SKM_Panda_Animations.fbx | `Panda_Death` | 360–404 | 1.833 s | once |
| `Panda_Idle_2` | SKM_Panda_Animations.fbx | `Panda_Idle2` | 430–578 | 6.167 s | loop |

### Parrot — 24 fps, 976 tris, 84 bones  ·  **one long take, needs slicing**

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Parrot_Walk` | SKM_Parrot_Animations.fbx | `Take 001` | 1–20 | 0.792 s | loop |
| `Parrot_Run` | SKM_Parrot_Animations.fbx | `Take 001` | 30–42 | 0.500 s | loop |
| `Parrot_Idle` | SKM_Parrot_Animations.fbx | `Take 001` | 60–245 | 7.708 s | loop |
| `Parrot_Fly` | SKM_Parrot_Animations.fbx | `Take 001` | 260–280 | 0.833 s | loop |
| `Parrot_Attack` | SKM_Parrot_Animations.fbx | `Take 001` | 300–330 | 1.250 s | loop |
| `Parrot_Death` | SKM_Parrot_Animations.fbx | `Take 001` | 350–380 | 1.250 s | once |

### Penguin — 24 fps, 602 tris, 37 bones  ·  **one long take, needs slicing**

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Penguin_Walk` | SKM_Penguin_Rig.fbx | `Take 001` | 1–29 | 1.167 s | loop |
| `Penguin_Idle` | SKM_Penguin_Rig.fbx | `Take 001` | 38–112 | 3.083 s | loop |
| `Penguin_Shake` | SKM_Penguin_Rig.fbx | `Take 001` | 129–203 | 3.083 s | loop |
| `Penguin_Death` | **Penguin_Death.anim** (Unity `.anim`, unreadable by Godot) | — | — | 1.333 s | — |
| `Penguin_Idle` | **Penguin_Idle.anim** (Unity `.anim`, unreadable by Godot) | — | — | 3.083 s | — |
| `Penguin_Run` | **Penguin_Run.anim** (Unity `.anim`, unreadable by Godot) | — | — | 0.583 s | — |
| `Penguin_Shake` | **Penguin_Shake.anim** (Unity `.anim`, unreadable by Godot) | — | — | 3.083 s | — |
| `Penguin_Walk` | **Penguin_Walk.anim** (Unity `.anim`, unreadable by Godot) | — | — | 1.167 s | — |

### Pig — 60 fps, 1524 tris, 55 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Pig_Idle_Breathing` | SKM_Pig_Animations.fbx | `Pig_idle breathing` | 0–80 | 1.333 s | loop |
| `Pig_idle_2` | SKM_Pig_Animations.fbx | `Pig_idle2` | 300–700 | 6.667 s | loop |
| `Pig_Idle_To_Walk` | SKM_Pig_Animations.fbx | `Pig_idle to walk` | 775–805 | 0.500 s | once |
| `Pig_Walk` | SKM_Pig_Animations.fbx | `Pig_walk` | 850–930 | 1.333 s | loop |
| `Pig_Walk_To_Idle` | SKM_Pig_Animations.fbx | `Pig_walk to idle` | 1000–1030 | 0.500 s | once |
| `Pig_Run` | SKM_Pig_Animations.fbx | `Pig_run` | 1145–1177 | 0.533 s | loop |
| `Pig_Run_To_Idle` | SKM_Pig_Animations.fbx | `Pig_run to idle` | 1230–1250 | 0.333 s | once |
| `Pig_Attack` | SKM_Pig_Animations.fbx | `Pig_attack` | 1300–1370 | 1.167 s | loop |
| `Pig_Death` | SKM_Pig_Animations.fbx | `Pig_death` | 1450–1515 | 1.083 s | once |
| `Pig_Sleep` | SKM_Pig_Animations.fbx | `Pig_Sleep` | 1625–1750 | 2.083 s | loop |
| `Pig_Sleep_Stand` | SKM_Pig_Animations.fbx | `Pig_Sleep_To_Stand` | 1800–1950 | 2.500 s | once |
| `Pig_Eat` | SKM_Pig_Animations.fbx | `Pig_Eat` | 1975–2342 | 6.117 s | loop |

### Rabbit — ? fps, 630 tris, 53 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Take 001` | SKM_Rabbit_Rig.fbx | `Take 001` | — | 4.958 s | — |
| `Rabbit_Death_1` | **Rabbit_Death_1.anim** (Unity `.anim`, unreadable by Godot) | — | — | 1.625 s | — |
| `Rabbit_Death_2` | **Rabbit_Death_2.anim** (Unity `.anim`, unreadable by Godot) | — | — | 1.208 s | — |
| `Rabbit_Idle` | **Rabbit_Idle.anim** (Unity `.anim`, unreadable by Godot) | — | — | 1.542 s | — |
| `Rabbit_Jump_Up` | **Rabbit_Jump_Up.anim** (Unity `.anim`, unreadable by Godot) | — | — | 2.458 s | — |
| `Rabbit_Jump_Walk` | **Rabbit_Jump_Walk.anim** (Unity `.anim`, unreadable by Godot) | — | — | 1.875 s | — |
| `Rabbit_LookOut` | **Rabbit_LookOut.anim** (Unity `.anim`, unreadable by Godot) | — | — | 2.458 s | — |
| `Rabbit_Run` | **Rabbit_Run.anim** (Unity `.anim`, unreadable by Godot) | — | — | 0.667 s | — |

### Rat — 24 fps, 1118 tris, 86 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Rat_Run` | SKM_Rat_Animations.fbx | `Rat_Run` | 1–9 | 0.333 s | loop |
| `Rat_Walk` | SKM_Rat_Animations.fbx | `Rat_Walk` | 20–32 | 0.500 s | loop |
| `Rat_Idle` | SKM_Rat_Animations.fbx | `Rat_Idle` | 40–180 | 5.833 s | loop |
| `Rat_Idle_2` | SKM_Rat_Animations.fbx | `Rat_Idle_1` | 180–250 | 2.917 s | loop |
| `Rat_Death` | SKM_Rat_Animations.fbx | `Rat_Death` | 300–329 | 1.208 s | once |
| `Rat_Attack` | SKM_Rat_Animations.fbx | `Rat_Attack` | 380–403 | 0.958 s | loop |
| `Take 001` | SKM_Rat_Rig.fbx | `Take 001` | — | 4.958 s | — |

### Reindeer — 30 fps, 2458 tris, 55 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Reindeer_Attack` | SKM_Reindeer_Animations.fbx | `Reindeer_Rig_Reindeer_Attack` | 0–70 | 2.333 s | once |
| `Reindeer_Death` | SKM_Reindeer_Animations.fbx | `Reindeer_Rig_Reindeer_Death` | 70–151 | 2.700 s | once |
| `Reindeer_Idle` | SKM_Reindeer_Animations.fbx | `Reindeer_Rig_Reindeer_Idle` | 151–427 | 9.200 s | loop |
| `Reindeer_Run` | SKM_Reindeer_Animations.fbx | `Reindeer_Rig_Reindeer_Run` | 427–445 | 0.600 s | once |
| `Reindeer_Walk` | SKM_Reindeer_Animations.fbx | `Reindeer_Rig_Reindeer_Walk` | 445–470 | 0.833 s | loop |
| `Reindeer_Eat` | SKM_Reindeer_Animations.fbx | `Reindeer__Eating_Loop` | 475–547 | 2.400 s | loop |
| `Reindeer_Eat_In` | SKM_Reindeer_Animations.fbx | `Reindeer__Eating_In` | 547–563 | 0.533 s | once |
| `Reindeer_Eat_Out` | SKM_Reindeer_Animations.fbx | `Reindeer__Eating_Out` | 563–580 | 0.567 s | once |

### Rhino — 24 fps, 1420 tris, 61 bones  ·  **one long take, needs slicing**

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Rhino_Idle` | SKM_Rhino_Animations.fbx | `Take 001` | 1–200 | 8.292 s | loop |
| `Rhino_Walk` | SKM_Rhino_Animations.fbx | `Take 001` | 300–333 | 1.375 s | loop |
| `Rhino_Run` | SKM_Rhino_Animations.fbx | `Take 001` | 400–412 | 0.500 s | loop |
| `Rhino_Attack` | SKM_Rhino_Animations.fbx | `Take 001` | 450–479 | 1.208 s | loop |
| `Rhino_Death` | SKM_Rhino_Animations.fbx | `Take 001` | 500–540 | 1.667 s | once |

### Rooster — 24 fps, 1106 tris, 97 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Rooster_Idle_Breathing` | SKM_Rooster_Animations.fbx | `Rooster_Idle Breathing` | 0–60 | 2.500 s | loop |
| `Rooster_Idle_Roast` | SKM_Rooster_Animations.fbx | `Rooster_Idle_Roost` | 100–160 | 2.500 s | loop |
| `Rooster_Idle_2` | SKM_Rooster_Animations.fbx | `Rooster_Idle_2` | 180–288 | 4.500 s | loop |
| `Rooster_Idle_3` | SKM_Rooster_Animations.fbx | `Rooster_Idle_3` | 330–360 | 1.250 s | loop |
| `Rooster_Walk` | SKM_Rooster_Animations.fbx | `Rooster_Walk` | 430–460 | 1.250 s | loop |
| `Rooster_Run` | SKM_Rooster_Animations.fbx | `Rooster_Run` | 570–586 | 0.667 s | loop |
| `Rooster_Fly` | SKM_Rooster_Animations.fbx | `Rooster_Fly` | 670–690 | 0.833 s | loop |
| `Rooster_Attack` | SKM_Rooster_Animations.fbx | `Rooster_Attack` | 770–806 | 1.500 s | loop |
| `Rooster_Death` | SKM_Rooster_Animations.fbx | `Rooster_Death` | 840–866 | 1.083 s | once |
| `Rooster_Sleep` | SKM_Rooster_Animations.fbx | `Rooster_Sleep` | 900–950 | 2.083 s | loop |
| `Rooster_Sleep_Stand` | SKM_Rooster_Animations.fbx | `Rooster_Sleep_Stand` | 950–975 | 1.042 s | once |
| `Rooster_Eat` | SKM_Rooster_Animations.fbx | `Rooster_Eat` | 1000–1100 | 4.167 s | loop |

### Seagull — 24 fps, 160 tris, 17 bones  ·  **one long take, needs slicing**

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Seagul_Fly` | SKM_Seagull_Rig.fbx | `Take 001` | 1–24 | 0.958 s | loop |
| `Seagul_Sitting` | SKM_Seagull_Rig.fbx | `Take 001` | 30–149 | 4.958 s | loop |
| `Seagul_Fly` | **Seagul_Fly.anim** (Unity `.anim`, unreadable by Godot) | — | — | 0.958 s | — |
| `Seagul_Sitting` | **Seagul_Sitting.anim** (Unity `.anim`, unreadable by Godot) | — | — | 4.958 s | — |

### Seahorse — 24 fps, 702 tris, 29 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Seahorse_Swim` | SKM_Seahorse_Animations.fbx | `Seahorse_Swim` | 1–36 | 1.458 s | loop |
| `Seahorse_FastSwim` | SKM_Seahorse_Animations.fbx | `Seahorse_FastSwim` | 40–60 | 0.833 s | loop |
| `Seahorse_Idle` | SKM_Seahorse_Animations.fbx | `Seahorse_Idle` | 80–255 | 7.292 s | loop |
| `Seahorse_Attack` | SKM_Seahorse_Animations.fbx | `Seahorse_Attack` | 275–315 | 1.667 s | loop |
| `Seahorse_Death` | SKM_Seahorse_Animations.fbx | `Seahorse_Death` | 350–400 | 2.083 s | once |
| `Take 001` | SKM_Seahorse_Rig.fbx | `Take 001` | — | 4.958 s | — |

### Seal — 24 fps, 932 tris, 40 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Seal_Idle` | SKM_Seal_Animations.fbx | `Seal_Idle` | 0–60 | 2.500 s | loop |
| `Seal_Idle 2` | SKM_Seal_Animations.fbx | `Seal_Idle 2` | 100–290 | 7.917 s | loop |
| `Seal_Idle_To_Walk` | SKM_Seal_Animations.fbx | `Seal_Idle to Walk` | 330–342 | 0.500 s | once |
| `Seal_Walk` | SKM_Seal_Animations.fbx | `Seal_Walk` | 360–390 | 1.250 s | loop |
| `Seal_Walk_To_Idle` | SKM_Seal_Animations.fbx | `Seal_Walk to Idle` | 410–422 | 0.500 s | once |
| `Seal_Idle_To_Run` | SKM_Seal_Animations.fbx | `Seal_Idle to Run` | 450–458 | 0.333 s | once |
| `Seal_Run` | SKM_Seal_Animations.fbx | `Seal_Run` | 490–506 | 0.667 s | loop |
| `Seal_Run_To_Idle` | SKM_Seal_Animations.fbx | `Seal_Run to Idle` | 520–529 | 0.375 s | once |
| `Seal_Attack` | SKM_Seal_Animations.fbx | `Seal_Attack` | 560–595 | 1.458 s | loop |
| `Seal_Death` | SKM_Seal_Animations.fbx | `Seal_Death` | 630–650 | 0.833 s | once |

### Shark — 24 fps, 796 tris, 29 bones  ·  **one long take, needs slicing**

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Shark_Swim` | SKM_Shark_Rig.fbx | `Take 001` | 0–87 | 3.625 s | loop |
| `Shark_Attack` | SKM_Shark_Rig.fbx | `Take 001` | 90–120 | 1.250 s | loop |
| `Shark_Attack` | **Shark_Attack.anim** (Unity `.anim`, unreadable by Godot) | — | — | 1.250 s | — |
| `Shark_Death` | **Shark_Death.anim** (Unity `.anim`, unreadable by Godot) | — | — | 1.458 s | — |
| `Shark_Swim` | **Shark_Swim.anim** (Unity `.anim`, unreadable by Godot) | — | — | 3.625 s | — |

### Sheep — 24 fps, 1408 tris, 51 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Sheep_Idle` | SKM_Sheep_Animations.fbx | `Sheep_Idle` | 0–30 | 1.250 s | loop |
| `Sheep_Idle_To_Walk` | SKM_Sheep_Animations.fbx | `Sheep_Idle to Walk` | 70–81 | 0.458 s | once |
| `Sheep_Walk` | SKM_Sheep_Animations.fbx | `Sheep_Walk` | 100–124 | 1.000 s | loop |
| `Sheep_Walk_To_Idle` | SKM_Sheep_Animations.fbx | `Sheep_Walk to Idle` | 140–152 | 0.500 s | once |
| `Sheep_Idle_2` | SKM_Sheep_Animations.fbx | `Sheep_Idle 2` | 160–346 | 7.750 s | loop |
| `Sheep_Idle_To_Run` | SKM_Sheep_Animations.fbx | `Sheep_Idle to Run` | 360–371 | 0.458 s | once |
| `Sheep_Run` | SKM_Sheep_Animations.fbx | `Sheep_Run` | 390–404 | 0.583 s | loop |
| `Sheep_Run_To_Idle` | SKM_Sheep_Animations.fbx | `Sheep_Run to Idle` | 420–432 | 0.500 s | once |
| `Sheep_Attack` | SKM_Sheep_Animations.fbx | `Sheep_Attack` | 450–505 | 2.292 s | loop |
| `Sheep_Death` | SKM_Sheep_Animations.fbx | `Sheep_Death` | 530–555 | 1.042 s | once |
| `Sheep_Sleep` | SKM_Sheep_Animations.fbx | `Sheep_Sleep` | 580–700 | 5.000 s | loop |
| `Sheep_Sleep_Stand` | SKM_Sheep_Animations.fbx | `Sheep_Sleep_To_Stand` | 715–760 | 1.875 s | once |
| `Sheep_Eat` | SKM_Sheep_Animations.fbx | `Sheep_Eat` | 770–900 | 5.417 s | loop |
| `Sheep_Wool_Idle` | SKM_Sheep_Wool_Animations.fbx | `Sheep_Sheep_Idle` | 0–30 | 1.250 s | loop |
| `Sheep_Wool_Idle_to_Walk` | SKM_Sheep_Wool_Animations.fbx | `Sheep_Sheep_Idle_to_Walk` | 30–41 | 0.458 s | once |
| `Sheep_Wool_Walk` | SKM_Sheep_Wool_Animations.fbx | `Sheep_Sheep_Walk` | 41–65 | 1.000 s | loop |
| `Sheep_Wool_Walk_To_Idle` | SKM_Sheep_Wool_Animations.fbx | `Sheep_Sheep_Walk_to_Idle` | 65–77 | 0.500 s | once |
| `Sheep_Wool_Idle_2` | SKM_Sheep_Wool_Animations.fbx | `Sheep_Sheep_Idle_2` | 77–263 | 7.750 s | loop |
| `Sheep_Wool_Idle_To_Run` | SKM_Sheep_Wool_Animations.fbx | `Sheep_Sheep_Idle_to_Run` | 263–274 | 0.458 s | once |
| `Sheep_Wool_Run` | SKM_Sheep_Wool_Animations.fbx | `Sheep_Sheep_Run` | 274–288 | 0.583 s | loop |
| `Sheep_Wool_Run_To_Idle` | SKM_Sheep_Wool_Animations.fbx | `Sheep_Sheep_Run_to_Idle` | 288–300 | 0.500 s | once |
| `Sheep_Wool_Attack` | SKM_Sheep_Wool_Animations.fbx | `Sheep_Sheep_Attack` | 300–355 | 2.292 s | loop |
| `Sheep_Wool_Death` | SKM_Sheep_Wool_Animations.fbx | `Sheep_Sheep_Death` | 355–380 | 1.042 s | once |
| `Sheep_Wool_Sleep` | SKM_Sheep_Wool_Animations.fbx | `Sheep_Sheep_Sleep` | 380–500 | 5.000 s | loop |
| `Sheep_Wool_Sleep_Stand` | SKM_Sheep_Wool_Animations.fbx | `Sheep_Sheep_Sleep_To_Stand` | 500–545 | 1.875 s | once |
| `Sheep_Wool_Eat` | SKM_Sheep_Wool_Animations.fbx | `Sheep_Sheep_Eat` | 545–675 | 5.417 s | loop |

### Snake — ? fps, 390 tris, 31 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Snake_Attack` | **Snake_Attack.anim** (Unity `.anim`, unreadable by Godot) | — | — | 1.458 s | — |
| `Snake_Death` | **Snake_Death.anim** (Unity `.anim`, unreadable by Godot) | — | — | 2.083 s | — |
| `Snake_Idle` | **Snake_Idle.anim** (Unity `.anim`, unreadable by Godot) | — | — | 11.417 s | — |
| `Snake_Slither` | **Snake_Slither.anim** (Unity `.anim`, unreadable by Godot) | — | — | 0.958 s | — |

### Spider — 24 fps, 948 tris, 45 bones  ·  **one long take, needs slicing**

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Spider_Walk` | SKM_Spider_Rig.fbx | `Take 001` | 1–19 | 0.750 s | loop |
| `Spider_Idle` | SKM_Spider_Rig.fbx | `Take 001` | 30–104 | 3.083 s | loop |
| `Spider_Scared` | SKM_Spider_Rig.fbx | `Take 001` | 110–199 | 3.708 s | loop |
| `Spider_Attack` | **Spider_Attack.anim** (Unity `.anim`, unreadable by Godot) | — | — | 1.667 s | — |
| `Spider_Death` | **Spider_Death.anim** (Unity `.anim`, unreadable by Godot) | — | — | 1.333 s | — |
| `Spider_Death_2` | **Spider_Death_2.anim** (Unity `.anim`, unreadable by Godot) | — | — | 2.208 s | — |
| `Spider_Death_3` | **Spider_Death_3.anim** (Unity `.anim`, unreadable by Godot) | — | — | 3.250 s | — |
| `Spider_Idle` | **Spider_Idle.anim** (Unity `.anim`, unreadable by Godot) | — | — | 3.083 s | — |
| `Spider_Scared` | **Spider_Scared.anim** (Unity `.anim`, unreadable by Godot) | — | — | 3.708 s | — |
| `Spider_Walk` | **Spider_Walk.anim** (Unity `.anim`, unreadable by Godot) | — | — | 0.750 s | — |

### Squid — 24 fps, 2098 tris, 59 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Squid_Idle` | SKM_Squid_Animations.fbx | `Squid_Idle` | 0–50 | 2.083 s | loop |
| `Squid_Idle_To_Swim` | SKM_Squid_Animations.fbx | `Squid_Idle to Swim` | 100–120 | 0.833 s | once |
| `Squid_Swim` | SKM_Squid_Animations.fbx | `Squid_Swim` | 160–202 | 1.750 s | loop |
| `Squid_Swim_To_Idle` | SKM_Squid_Animations.fbx | `Squid_Swim to Idle` | 230–256 | 1.083 s | once |
| `Squid_Death` | SKM_Squid_Animations.fbx | `Squid_Death` | 280–323 | 1.792 s | once |

### Squirrel — 24 fps, 1500 tris, 102 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Squirrel_Idle` | SKM_Squirrel_Animations.fbx | `Squirrel_Idle` | 0–34 | 1.417 s | loop |
| `Squirrel_Idle_2` | SKM_Squirrel_Animations.fbx | `Squirrel_Idle 2` | 80–259 | 7.458 s | loop |
| `Squirrel_Idle_To_Walk` | SKM_Squirrel_Animations.fbx | `Squirrel_Idle to Walk` | 280–290 | 0.417 s | once |
| `Squirrel_Walk` | SKM_Squirrel_Animations.fbx | `Squirrel_Walk` | 310–334 | 1.000 s | loop |
| `Squirrel_Walk_To_Idle` | SKM_Squirrel_Animations.fbx | `Squirrel_Walk to Idle` | 360–370 | 0.417 s | once |
| `Squirrel_Idle_To_Run` | SKM_Squirrel_Animations.fbx | `Squirrel_Idle to Run` | 390–395 | 0.208 s | once |
| `Squirrel_Run` | SKM_Squirrel_Animations.fbx | `Squirrel_Run` | 420–432 | 0.500 s | loop |
| `Squirrel_Run_To_Idle` | SKM_Squirrel_Animations.fbx | `Squirrel_Run to Idle` | 450–457 | 0.292 s | once |
| `Squirrel_Attack` | SKM_Squirrel_Animations.fbx | `Squirrel_Attack` | 480–516 | 1.500 s | loop |
| `Squirrel_Death` | SKM_Squirrel_Animations.fbx | `Squirrel_Death` | 540–569 | 1.208 s | once |

### StarFish — ? fps, 106 tris, 107 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `StarFish_Walk` | **StarFish_Walk.anim** (Unity `.anim`, unreadable by Godot) | — | — | 1.833 s | — |

### Tapir — 24 fps, 1468 tris, 56 bones  ·  **one long take, needs slicing**

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Tapir_Idle` | SKM_Tapir_Animations.fbx | `Take 001` | 0–232 | 9.667 s | loop |
| `Tapir_Walk` | SKM_Tapir_Animations.fbx | `Take 001` | 294–332 | 1.583 s | loop |
| `Tapir_Run` | SKM_Tapir_Animations.fbx | `Take 001` | 391–407 | 0.667 s | loop |
| `Tapir_Attack` | SKM_Tapir_Animations.fbx | `Take 001` | 438–475 | 1.542 s | loop |
| `Tapir_Death` | SKM_Tapir_Animations.fbx | `Take 001` | 484–515 | 1.292 s | once |

### Tiger — 24 fps, 2204 tris, 79 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Tiger_Idle_Breathing` | SKM_Tiger_Animations.fbx | `Tiger_idle breathing` | 0–80 | 3.333 s | loop |
| `Tiger_Attack` | SKM_Tiger_Animations.fbx | `Tiger_attack1` | 120–158 | 1.583 s | loop |
| `Tiger_Idle_To_Walk` | SKM_Tiger_Animations.fbx | `Tiger_idle to walk` | 200–216 | 0.667 s | once |
| `Tiger_Walk` | SKM_Tiger_Animations.fbx | `Tiger_walk` | 230–266 | 1.500 s | loop |
| `Tiger_Walk_To_Idle` | SKM_Tiger_Animations.fbx | `Tiger_walk to idle` | 280–296 | 0.667 s | once |
| `Tiger_Idle_Roar` | SKM_Tiger_Animations.fbx | `Tiger_idle roar` | 320–386 | 2.750 s | once |
| `Tiger_Idle_To_Run` | SKM_Tiger_Animations.fbx | `Tiger_idle to run` | 410–419 | 0.375 s | once |
| `Tiger_Run` | SKM_Tiger_Animations.fbx | `Tiger_run` | 435–449 | 0.583 s | loop |
| `Tiger_Run_To_Idle` | SKM_Tiger_Animations.fbx | `Tiger_run to idle` | 460–471 | 0.458 s | once |
| `Tiger_Attack_2` | SKM_Tiger_Animations.fbx | `Tiger_attack2` | 490–548 | 2.417 s | loop |
| `Tiger_Death` | SKM_Tiger_Animations.fbx | `Tiger_death` | 570–634 | 2.667 s | once |

### Tucan — 24 fps, 1056 tris, 50 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Tucan_Idle_Left` | SKM_Tucan_Animations.fbx | `Tucan_idle left` | 0–95 | 3.958 s | loop |
| `Tucan_Idle_Right` | SKM_Tucan_Animations.fbx | `Tucan_idle right` | 120–215 | 3.958 s | loop |
| `Tucan_Idle_To_Walk` | SKM_Tucan_Animations.fbx | `Tucan_idle to walk` | 230–240 | 0.417 s | once |
| `Tucan_Walk` | SKM_Tucan_Animations.fbx | `Tucan_walk` | 250–278 | 1.167 s | loop |
| `Tucan_Walk_To_Idle` | SKM_Tucan_Animations.fbx | `Tucan_walk to idle` | 290–300 | 0.417 s | once |
| `Tucan_Idle_To_Run` | SKM_Tucan_Animations.fbx | `Tucan_idle to run` | 310–317 | 0.292 s | once |
| `Tucan_Run` | SKM_Tucan_Animations.fbx | `Tucan_run` | 330–344 | 0.583 s | loop |
| `Tucan_Run_To_Iidle` | SKM_Tucan_Animations.fbx | `Tucan_run to idle` | 363–370 | 0.292 s | once |
| `Tucan_Idle_To_Fly` | SKM_Tucan_Animations.fbx | `Tucan_idle to fly` | 400–409 | 0.375 s | once |
| `Tucan_Flying` | SKM_Tucan_Animations.fbx | `Tucan_flying` | 420–434 | 0.583 s | loop |
| `Tucan_Fly_To_Idle` | SKM_Tucan_Animations.fbx | `Tucan_fly to idle` | 452–462 | 0.417 s | once |
| `Tucan_Attack` | SKM_Tucan_Animations.fbx | `Tucan_attack` | 480–520 | 1.667 s | loop |
| `Tucan_Death` | SKM_Tucan_Animations.fbx | `Tucan_death` | 550–571 | 0.875 s | once |

### Vulture — 24 fps, 934 tris, 106 bones  ·  **one long take, needs slicing**

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Vulture_Idle` | SKM_Vulture_Animations.fbx | `Take 001` | 1–240 | 9.958 s | loop |
| `Vulture_Fly` | SKM_Vulture_Animations.fbx | `Take 001` | 300–320 | 0.833 s | loop |
| `Vulture_Walk` | SKM_Vulture_Animations.fbx | `Take 001` | 346–382 | 1.500 s | loop |
| `Vulture_Attack` | SKM_Vulture_Animations.fbx | `Take 001` | 450–491 | 1.708 s | loop |
| `Vulture_Death` | SKM_Vulture_Animations.fbx | `Take 001` | 500–536 | 1.500 s | once |
| `Take 001` | SKM_Vulture_Rig.fbx | `Take 001` | — | 4.958 s | — |

### Walrus — 24 fps, 964 tris, 31 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Walrus_Idle` | SKM_Walrus_Animations.fbx | `Walrus_Idle` | 0–60 | 2.500 s | loop |
| `Walrus_Idle_2` | SKM_Walrus_Animations.fbx | `Walrus_Idle 2` | 100–290 | 7.917 s | loop |
| `Walrus_Idle_To_Walk` | SKM_Walrus_Animations.fbx | `Walrus_Idle to Walk` | 330–342 | 0.500 s | once |
| `Walrus_Walk` | SKM_Walrus_Animations.fbx | `Walrus_Walk` | 360–390 | 1.250 s | loop |
| `Walrus_Walk_To_Idle` | SKM_Walrus_Animations.fbx | `Walrus_Walk to Idle` | 410–422 | 0.500 s | once |
| `Walrus_Idle_To_Run` | SKM_Walrus_Animations.fbx | `Walrus_Idle to Run` | 450–458 | 0.333 s | once |
| `Walrus_Run` | SKM_Walrus_Animations.fbx | `Walrus_Run` | 490–506 | 0.667 s | loop |
| `Walrus_Run_To_Idle` | SKM_Walrus_Animations.fbx | `Walrus_Run to Idle` | 520–529 | 0.375 s | once |
| `Walrus_Attack` | SKM_Walrus_Animations.fbx | `Walrus_Attack` | 560–595 | 1.458 s | loop |
| `Walrus_Death` | SKM_Walrus_Animations.fbx | `Walrus_Death` | 630–650 | 0.833 s | once |

### Whale — 24 fps, 1564 tris, 44 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Whale_Fast` | SKM_Whale_Animations.fbx | `Whale_Fast` | 1–30 | 1.208 s | loop |
| `Whale_Slow` | SKM_Whale_Animations.fbx | `Whale_Slow` | 150–250 | 4.167 s | loop |
| `Whale_Eat` | SKM_Whale_Animations.fbx | `Whale_Eat` | 300–400 | 4.167 s | loop |
| `Whale_Dead` | SKM_Whale_Animations.fbx | `Whale_Dead` | 450–500 | 2.083 s | once |
| `Take 001` | SKM_Whale_Rig.fbx | `Take 001` | — | 6.250 s | — |

### Wolf — 24 fps, 2008 tris, 56 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Wolf_Idle` | SKM_Wolf_Animations.fbx | `Wolf_Idle` | 0–170 | 7.083 s | loop |
| `Wolf_Walk` | SKM_Wolf_Animations.fbx | `Wolf_Walk` | 230–264 | 1.417 s | loop |
| `Wolf_Run` | SKM_Wolf_Animations.fbx | `Wolf_Run` | 330–342 | 0.500 s | loop |
| `Wolf_Attack` | SKM_Wolf_Animations.fbx | `Wolf_Attack` | 390–470 | 3.333 s | loop |
| `Wolf_Death` | SKM_Wolf_Animations.fbx | `Wolf_Death` | 500–535 | 1.458 s | once |
| `Wolf_Howl` | SKM_Wolf_Animations_Howl.fbx | `Take 001` | 1–90 | 3.708 s | loop |
| `Take 001` | SKM_Wolf_Rig.fbx | `Take 001` | — | 56.667 s | — |
| `Wolf_Legacy_Idle` | SKM_Wolf_Legacy_Animations.fbx | `wolf_idle` | 0–170 | 7.083 s | loop |
| `Wolf_Legacy_Idle_To_Walk` | SKM_Wolf_Legacy_Animations.fbx | `wolf_idle to walk` | 190–202 | 0.500 s | once |
| `Wolf_Legacy_Walk` | SKM_Wolf_Legacy_Animations.fbx | `wolf_walk` | 230–264 | 1.417 s | loop |
| `Wolf_Legacy_Walk_To_Idle` | SKM_Wolf_Legacy_Animations.fbx | `wolf_walk to idle` | 290–307 | 0.708 s | once |
| `Wold_Legacy_Idle_To_Run` | SKM_Wolf_Legacy_Animations.fbx | `wolf_idle to run` | 315–323 | 0.333 s | once |
| `Wolf_Legacy_Run` | SKM_Wolf_Legacy_Animations.fbx | `wolf_run` | 330–342 | 0.500 s | loop |
| `Wolf_Legacy_Run_To_Idle` | SKM_Wolf_Legacy_Animations.fbx | `wolf_run to idle` | 360–372 | 0.500 s | once |
| `Wolf_Legacy_Attack` | SKM_Wolf_Legacy_Animations.fbx | `wolf_attack` | 390–470 | 3.333 s | loop |
| `Wolf_Legacy_Death` | SKM_Wolf_Legacy_Animations.fbx | `wolf_death` | 500–535 | 1.458 s | once |
| `Wolf_Legacy_Fixed_Idle_To_Walk` | SKM_Wolf_Legacy_Animations_Fixed.fbx | `Wolf_Animation_wolf_idle_to_walk` | 170–182 | 0.500 s | once |
| `Wolf_Legacy_Fixed_Walk` | SKM_Wolf_Legacy_Animations_Fixed.fbx | `Wolf_Animation_wolf_walk` | 182–216 | 1.417 s | loop |
| `Wolf_Legacy_Fixed_Walk_To_Idle` | SKM_Wolf_Legacy_Animations_Fixed.fbx | `Wolf_Animation_wolf_walk_to_idle` | 216–233 | 0.708 s | once |
| `Wolf_Legacy_Fixed_Idle_To_Run` | SKM_Wolf_Legacy_Animations_Fixed.fbx | `Wolf_Animation_wolf_idle_to_run` | 233–241 | 0.333 s | once |
| `Wolf_Legacy_Fixed_Run` | SKM_Wolf_Legacy_Animations_Fixed.fbx | `Wolf_Animation_wolf_run` | 241–253 | 0.500 s | loop |
| `Wolf_Legacy_Fixed_Run_To_Idle` | SKM_Wolf_Legacy_Animations_Fixed.fbx | `Wolf_Animation_wolf_run_to_idle` | 253–265 | 0.500 s | once |
| `Wolf_Legacy_Fixed_Attack` | SKM_Wolf_Legacy_Animations_Fixed.fbx | `Wolf_Animation_wolf_attack` | 265–345 | 3.333 s | loop |
| `Wolf_Legacy_Fixed_Death` | SKM_Wolf_Legacy_Animations_Fixed.fbx | `Wolf_Animation_wolf_death` | 345–380 | 1.458 s | once |
| `Wolf_Legacy_Howl` | SKM_Wolf_Legacy_Animations_Howl.fbx | `Take 001` | 0–90 | 3.750 s | loop |

### Zebra — 24 fps, 2574 tris, 70 bones

| Take | Source FBX | Parent take | Frames | Duration | Loop |
|---|---|---|---:|---:|:-:|
| `Zebra_Walk` | SKM_Zebra_Animations.fbx | `Walk` | 1–38 | 1.542 s | loop |
| `Zebra_Run` | SKM_Zebra_Animations.fbx | `Run` | 45–60 | 0.625 s | loop |
| `Zebra_Idle` | SKM_Zebra_Animations.fbx | `Idle1` | 65–142 | 3.208 s | loop |
| `Zebra_Idle_2` | SKM_Zebra_Animations.fbx | `Idle2` | 150–227 | 3.208 s | loop |
| `Zebra_Attack` | SKM_Zebra_Animations.fbx | `Attack` | 235–274 | 1.625 s | loop |
| `Zebra_Death` | SKM_Zebra_Animations.fbx | `Death` | 280–332 | 2.167 s | once |
| `Take 001` | SKM_Zebra_Rig.fbx | `Take 001` | — | 64.000 s | — |
