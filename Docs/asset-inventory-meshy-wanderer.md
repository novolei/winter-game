# Asset inventory — Meshy AI *Winter Wanderer* animation deliveries

The owner is exporting takes for the wanderer out of his Meshy AI library, one file at a
time, and roughly eighteen more can follow. This file is the register: what has arrived,
what each one **measures** as, and the procedure that turns the next arrival into a
mechanical five minutes.

**Nothing here is read off a filename.** This project has been wrong about an animation
three times by trusting one — most recently `Limping_Walk_inplace`, whose foot-lift ratio
of 0.871 and left-against-mirrored-right correlation of 0.933 make it statistically
identical to an ordinary walk. It does not limp. Every number below came out of
`tools/measure_wanderer_takes.gd` playing the take and reading the skeleton.

The originals stay in `Refs/game ref/`, which is untracked reference material. What the
repository holds is a copy under `assets/source/characters/animations/`, byte-identical,
named for the motion.

---

## 1. What has arrived

| In the repo as | Delivered as | Bytes | Takes | Status |
|---|---|---:|:-:|---|
| `assets/source/characters/animations/fall_backward_hard.fbx` | `Meshy_AI_Winter_Wanderer_biped (9)/…_Animation_Shot_and_Fall_Backward_withSkin.fbx` | 16,326,476 | 1 | **held, not wired.** Measured; see §2 |

`md5 9a538b9b2466d38d64d5067b9ea0d4cd` — the owner's file, the file that was measured, and
the file in the repository are the same bytes.

Three earlier deliveries sit beside it and are already merged into the shipping character:
`idle_neutral.fbx`, `idle_cold_shiver.fbx`, `knockdown_and_recover.fbx`. They are measured
in §6 as controls, because what they did on the way through is what the next twenty will do.

---

## 2. `fall_backward_hard` — what it actually is

### 2.1 As delivered

Measured with `bash tools/probe_take.sh assets/source/characters/animations/fall_backward_hard.fbx`:

```
24 bones, skeleton world scale (1, 1, 1), hip bone Hips, head bone Head
rig height at rest, world: 1.6585 m
RIG: identical to the wanderer's -- 24 bones, name for name
worst height delta across shared bones: 0.0192

"Armature|Armature|Shot_and_Fall_Backward|baselayer"
   MOVES   3.5000 s   25 tracks  worst LeftArm  rot 1.7877 rad
   ROOT MOTION  hip travel max 1.377 m, net 1.349 m
   hip  y 0.979 -> 0.159 m  (drop 0.827 m)
   head y 1.397 -> 0.063 m  (drop 1.334 m)
   lean 8.7 to 103.8 deg
   peak drop 2.740 m/s, peak ground speed 1.953 m/s
   hip height every 0.233 s: 0.98 0.98 0.98 1.01 1.02 1.01 1.00 0.97 0.85 0.42 0.18 0.20 0.18 0.17 0.15 0.16
```

**It moves.** Every one of the 24 bones is driven; the worst is the left arm at 1.79 rad.
This was checked before anything else, because a take that arrives with no armature
binding leaves the mesh in its bind pose, imports with zero errors, and is worse than a
missing clip — the crow's pack shipped exactly that, 121 nulls and no skeleton.

**What the body does**, off the hip timeline rather than off the name: he stands for about
1.6 s, straightens slightly (0.98 → 1.02 m, a flinch), starts down at 1.87 s, is on the
ground by 2.33 s, and lies there for the remaining 1.17 s — a third of the take. The torso
passes 90° and finishes at 103.8°, i.e. flat on his back and slightly past. He travels
**1.349 m** doing it.

**It is not in place.** Every take the movement code plays today is in place — root travel
under half a centimetre per cycle — and this one is not. Anything that uses it has to
consume the travel or the man will slide 1.35 m out of himself.

**The name is clean and the trimming is a non-issue**, both checked because briefing trap
15 says to. No trailing space. And `animation/trimming` — which is per-pack, has no
project-wide correct value, and has cost this project a take arriving at 8.958 s against a
true 3.958 s — makes **no difference at all here**: 3.5000 s with it on and 3.5000 s with
it off. Worth knowing that Godot's default is `true` for `.fbx` and `false` for `.glb`, so
the two halves of this pipeline do not agree by default; `tools/probe_take.sh` pins it off
to match the character model.

### 2.2 Same rig as the wanderer's — yes, and this is the cheap case

**24 bones, identical to the shipping character's name for name.** No retarget, no bone
map, no donor rig. `.superpowers/sdd/wave3/task-w3-hunger-hunch-report.md` is what the
other case costs: a cross-rig bake that carried every joint angle to a tenth of a degree
and delivered 10.5° where 26.8° was authored, because the two rigs put their spine bones
at different heights up the body.

So the names were not trusted on their own. Every shared bone's **rest height as a
fraction of the rig's own height** was compared, and the worst disagreement is **0.019** —
about 3 cm on a 1.6 m man, and in the same direction for every bone. That is the same
skeleton. For scale, `knockdown_and_recover.fbx`, which has already shipped through this
path, disagrees by **0.227**.

One number does differ and it matters in §6: this delivery's armature sits at **1.6585 m**
at rest where the shipping character's sits at **1.6020 m**.

### 2.3 Through the project's own pipeline — and this is the finding

The delivery is not what the game would play. What the game would play is the take after
`tools/decimate_character.py` merges it into the character `.glb`, and **that is
measurably a different animation.** The merge was run to a throwaway destination (the
shipping model was not touched) and measured there:

| | as delivered | through the pipeline |
|---|---:|---:|
| length | 3.5000 s | 3.5333 s |
| net root travel | 1.349 m | 1.466 m |
| hip at the end | **0.159 m** | **0.329 m** |
| head at the end | **0.063 m** | **0.263 m** |
| lean, maximum | 103.8° | 100.4° |
| peak hip descent | **2.740 m/s** | **2.280 m/s** |

**He finishes 17 cm higher at the hip and 20 cm higher at the head. He does not lie down —
he hovers.** Photographed, level orthographic side view, one ground line, the three
backward falls at their final frame:
`.superpowers/sdd/wave3/meshy-pack/three-backward-falls-final-frame.png`. The two takes
the library already has are resting on the line; this one is visibly clear of it.

The merge is faithful for the 21 takes that come out of the character file — every one of
their numbers reproduced to the digit in the rebuild — so this is not a broken rebuild. It
is what an **animation-only** delivery does on the way in. §6 has the controls.

And the reason to lead with it: **the raw file's headline advantage is mostly not real.**
As delivered, this take hits the ground 49% faster than `death_slow_back` (2.740 against
1.838 m/s). After the pipeline that edge is **12%** (2.280 against 1.838). Reading the
delivery and stopping there would have overstated the one property that makes this take
worth having.

### 2.4 Against the three going-down takes the library already has

All four measured in the same rebuilt file, on the same rig, the same way:

| library take | length | net travel | hip end | head end | lean max | peak descent | on the ground from |
|---|---:|---:|---:|---:|---:|---:|---|
| **`fall_backward_hard`** (new) | 3.5333 s | 1.466 m | 0.329 m | 0.263 m | 100.4° | **2.280 m/s** | 2.36 s — **1.18 s** of 3.53 |
| `death_slow_back` (`Shot_and_Slow_Fall_Backward`) | 4.4667 s | 1.115 m | 0.174 m | 0.070 m | 104.7° | 1.838 m/s | 2.98 s — 1.49 s of 4.47 |
| `death_collapse_back` (`dying_backwards`) | 2.2667 s | 0.859 m | 0.179 m | 0.102 m | 100.9° | 2.038 m/s | 1.36 s — 0.91 s of 2.27 |
| `knockdown_recover` (`knockdown_and_recover`) | 3.0333 s | 4.589 m | 1.175 m | 1.582 m | 122.4° | 2.645 m/s | never — lowest hip 0.500 m, then he stands |

Grounded-from times are read off each take's own hip-height timeline, which
`tools/measure_wanderer_takes.gd` prints for anything that drops more than 30 cm.

They are genuinely three different motions, not one clip at three speeds — the shapes
differ, not just the lengths:

- `death_collapse_back` starts down immediately and slides all the way. **A man giving
  out.** Nothing hits him.
- `death_slow_back` stands for 2.1 s, then topples softly. **A man who is hit and folds.**
- `fall_backward_hard` stands for 1.6 s, flinches upward, then goes down in **0.47 s**.
  **A man who is knocked off his feet.**

The retime hypothesis was checked and fails: 3.50/4.47 = 0.783, so a retimed
`death_slow_back` would peak at 2.35 m/s and travel 1.115 m. This one peaks at 2.74 and
travels 1.349.

### 2.5 The verdict

**For `W2-K 倒地冲击` (a body-shaped impression in the snow plus momentum-thrown snow):
yes, and it is the right take — with one condition and one caveat.**

- It is the hardest impact available: 2.280 m/s at the hip through the pipeline, against
  2.038 and 1.838. Momentum-thrown snow needs an impact speed and this is the only take
  that gives it a real one.
- It holds the ground for 1.18 s, a third of its length — long enough to stamp an
  impression and let the thrown snow settle. `knockdown_recover`, the other violent take,
  never gets below a 0.500 m hip before it stands up again.
- **The condition: it carries 1.466 m of root motion.** The impression must be stamped
  where the body *finishes*, not at the character's transform when the fall starts. A
  naive implementation puts the mark a metre and a half from the man, and nothing will
  error.
- **The caveat: he lands 15 cm too high** (§2.3). An impression is stamped under a body
  that is not touching the snow. That is fixable in the fall's own handling — clamp or
  offset the model for the grounded third — but it is work, and it is not zero.

**For a death ending: usable, and not the best thing we have today.**

GDD §10 gives 死亡 two causes — a survival bar reaching zero, or being killed by the bear
or a scavenger — and the library already answers both better:

- `death_collapse_back` is a man giving out with nothing hitting him. That is the
  exposure/starvation death, and it lies flat.
- `death_slow_back` lies flat too.
- `fall_backward_hard` is the best *violent* fall by shape — it is the only take where a
  standing man is knocked off his feet and stays down — but the final pose is the one a
  player looks at for as long as the ending holds, and **a corpse floating 15 cm above the
  snow is exactly the kind of thing an ending cannot survive.**

So: hold it for W2-K, where the moment matters more than the final pose, and prefer the
existing two for an ending unless the landing height is fixed.

---

## 3. Where these live, and why the naming is not `Model@Clip`

**`assets/source/characters/animations/<motion>.fbx`.** Tracked. `snake_case`, English,
named for what the take was **measured** to do — not for what the exporter called it, and
not for the game meaning, which is a later wave's decision.

Four reasons, in the order they would otherwise bite:

1. **It is already the convention.** Three wanderer animation deliveries live there and
   are already merged into the shipping character. A fourth home would split the register.
2. **`assets/source/` carries a `.gdignore`, and that is the point.** Godot never imports
   anything under it. Importing this file produces a **12,557,045-byte PNG** beside it —
   the FBX's embedded albedo, extracted by ufbx — plus a duplicate skinned mesh in the
   import cache. Times twenty deliveries that is a quarter of a gigabyte of duplicate
   albedo. Measured, not assumed: the extracted file is byte-identical
   (`df6f6c0200357c50616e6f8e05995c5b`) to the one Godot has already written into the
   owner's `Refs/` folder.
3. **`assets/models/` is the art gates' root** and everything under it is walked by
   `test_topology.gd`, `test_asset_scale.gd` and `test_world_collision.gd`. An unmerged
   source FBX is not a thing that appears in the world, and declaring a collision policy
   for it would be a lie told to a gate. (Same reasoning that put the retarget donor in
   `assets/rigs/`.)
4. **The game must not read it directly anyway.** Godot's FBX importer lands this rig in a
   different space from the shipping `.glb` — measured here again: skeleton world scale
   1.0 against 0.01, and read raw out of the skeleton the FBX's rest is Z-up. The same Hips
   rest measures 85.07 on one path and 0.84 on the other. A track copied across that gap
   scales the skeleton by a hundred and the visible result is not an error, it is a
   character who has vanished because his bones are tens of metres apart.

### `Model@Clip` is Godot's convention, and it is not this project's

`Model@Clip.fbx` is what Godot's importer understands for a *directly imported* animation
library, and it is how the **dogs** arrived — the owner re-exported them out of Unity that
way. It is not how the wanderer's library was assembled and it should not be.

The wanderer's twenty-one takes all come out of **one file**,
`assets/models/characters/winter_wanderer.glb`, built by `tools/decimate_character.py`.
There is no `@` anywhere in `assets/`. `Model@Clip` would mean importing each delivery
directly, which is exactly the space mismatch in point 4 above. **The take name is carried
by the filename instead**: `decimate_character.py::merge_animation` names the merged action
after the file it came from, and requires exactly one take per file.

That has a consequence worth stating: **the filename is not decoration, it is the take's
name in the shipping library.** Which is why it has to be measured before it is chosen.

### The `.import` sidecar

The repository's rule is that every imported asset and its `.import` file are both
committed. **A `.gdignore`d file is not an imported asset and has no sidecar** — Godot
never generates one. The three existing deliveries are tracked with no `.import` beside
them, and this one is the same. The sidecar rule attaches to the merged
`winter_wanderer.glb`, which has `winter_wanderer.glb.import` committed beside it.

---

## 4. The four PBR textures: nothing to do, and not for the reason you would guess

The pack ships four maps beside the FBX. **All four are byte-identical to files already in
the repository:**

| Delivered | Already in the repo as | md5 |
|---|---|---|
| `…_texture_0.png` | `assets/models/characters/winter_wanderer_albedo.png` | `2dba0b9e…` |
| `…_texture_0_normal.png` | `…_normal.png` | `79f4c0ae…` |
| `…_texture_0_roughness.png` | `…_roughness.png` | `1da7da6e…` |
| `…_texture_0_metallic.png` | `…_metallic.png` | `cf9afea4…` |

**Decision: none of them is imported, because they are duplicates.** Not because a
metallic/roughness/normal set is unwanted — and that distinction matters, because the
obvious reasoning is wrong here.

Art Bible rules 8 and 9 (no normal/roughness/metallic/specular, flat palette colour) are
about the **world**. `assets/models/characters` is exempt by the owner's own ruling
(*人物的颜色不受 GDD 的影响*), and the exemption is on the record in
`AssetScanner.SURFACE_RULE_EXEMPT_ROOTS` rather than left as a silence. The shipping
character **uses all four maps**: `PlayerController._build_body()` mounts them and
`CharacterScheme.normal_map_enabled` / `roughness_map_enabled` / `metallic_map_enabled` all
default to `true`, both shipped looks keeping them, because the quilting on the coat is
most of what says "person in a winter coat" at this framing.

So the rule for the next twenty is simply: **a `withSkin` delivery re-ships the same four
maps every time. Hash them against the repository and drop them.** They will be identical
until the owner regenerates the character itself, at which point everything changes at once
and the model is what gets rebuilt.

### One artifact to know about

`Meshy_AI_Winter_Wanderer_biped_Animation_Shot_and_Fall_Backward_withSkin_0.png` in the
owner's `Refs/` folder is **not part of the delivery** — Godot wrote it, extracting the
FBX's embedded image, because `Refs/` has no `.gdignore` and Godot imports everything in
it. It will reappear next to every future delivery left there. Dropping a `.gdignore` into
`Refs/` would stop it (and stop Godot importing several dozen reference screenshots), but
`Refs/` is the owner's untracked folder and that is his call, not an agent's.

---

## 5. The procedure for the next arrival

Five steps. Nothing here needs re-deriving.

**1 — Measure it where it landed, before naming it or moving it.**

```bash
bash tools/probe_take.sh "Refs/game ref/<pack>/<whatever Meshy called it>.fbx"
```

The script copies the file somewhere Godot does look, pins `animation/trimming=false` to
match the character model, imports, runs `tools/measure_wanderer_takes.gd`, and deletes
every trace including the extracted PNG. **Exit 0 only if every take in the file moves.**

Read four things off the report and write them into §1 of this file:

| Read | Reject or flag when |
|---|---|
| `MOVES` / `STILL` | STILL. The file has no pose to give; ask for a re-export. |
| the take name, in quotes | it needs trimming — a trailing space silently drops a take (trap 15.1). Get the asset fixed rather than trimming in code. |
| `RIG: identical to the wanderer's` | it is not. Everything downstream becomes a retarget; say so loudly before anyone plans around it. |
| `rig height at rest` against **1.6020 m** | it differs. §6 — this predicts how far the merged take will drift. |

**2 — Name it for what it does.** English `snake_case`, describing the measured motion, and
distinguishing it from what the library already holds — `fall_backward_hard`, not
`shot_and_fall_backward`. The filename becomes the take's name in the shipping library
(§3), and there is no gun in this game.

**3 — Put it in.** `assets/source/characters/animations/<name>.fbx`, tracked, no sidecar.
Verify the copy with `md5sum` against the original: the chain from the owner's file to the
measured file to the committed file should be one hash.

**4 — Stop here if the wave that wants it has not started.** Steps 1–4 are 预留保存. The
model is not rebuilt and nothing in `src/` changes.

**5 — When a wave wants it**, rebuild the character with *every* delivery on the command
line, and re-measure through the merge — the delivery's numbers are not the game's (§2.3):

```bash
"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
  --python tools/decimate_character.py -- \
  assets/source/characters/winter_wanderer_meshy.fbx \
  assets/models/characters/winter_wanderer.glb \
  assets/source/characters/animations/idle_neutral.fbx \
  assets/source/characters/animations/idle_cold_shiver.fbx \
  assets/source/characters/animations/knockdown_and_recover.fbx \
  assets/source/characters/animations/fall_backward_hard.fbx
  # ...and every later delivery, or it is silently dropped from the library
```

then add a row to `WandererAnimations.TAKES` — `[MODEL_PATH, "<filename>", "<library
name>", loops]` — and re-measure the merged model:

```bash
"D:/Godot_v4.7.1/Godot_v4.7.1-stable_win64_console.exe" --headless \
  --path "D:/Godot resource/winter-time" \
  --script res://tools/measure_wanderer_takes.gd
```

`tests/unit/test_wanderer_animations.gd` is the gate on the result: it asserts the library
census, the units, and the track paths.

**Verified end to end on this delivery.** The merge ran with no change to any tool, printed
`merged fall_backward_hard.fbx as 'fall_backward_hard' (106 frames)` and
`exporting 22 takes`, and the rebuilt model reproduced all 21 existing takes' measurements
to the digit. The pipeline does not need touching for a fourth delivery, or a twentieth.

---

## 6. What this delivery taught us about the next twenty

**An animation-only delivery does not arrive intact, and how far it drifts is predicted by
one number the probe already prints.**

Every one of the four deliveries measured as its own file and again inside the merged
model:

| delivery | its rest height | hip at the start: source → merged | hip at the bottom: source → merged |
|---|---:|---|---|
| `idle_neutral.fbx` | 1.5976 m | 0.842 → 0.851 (**+0.009**) | — |
| `idle_cold_shiver.fbx` | 1.6606 m | 0.885 → 0.821 (**−0.064**) | — |
| `knockdown_and_recover.fbx` | 1.3766 m | 0.709 → 0.851 (**+0.142**) | 0.301 → 0.500 (**+0.199**) |
| `fall_backward_hard.fbx` | 1.6585 m | 0.979 → 0.916 (**−0.063**) | 0.152 → 0.322 (**+0.170**) |
| *the character itself* | **1.6020 m** | | |

The measurement is unambiguous. `idle_neutral`, whose armature rest is within 4 mm of the
character's, comes through to **9 mm**. The two whose rests are 3.5% taller both drift by
**63–64 mm** in the same direction and by nearly the same amount. The one whose rest is 14%
shorter drifts the other way.

**The explanation — that the drift is the difference between the delivery's armature rest
and the character's — fits three of the four and should be treated as a hypothesis, not a
rule.** It does not predict the bottom-out drift, which is larger than the start drift and
of the opposite sign on `fall_backward_hard`. Nobody has taken it apart, and the briefing's
own warning applies: a record's measurement and its explanation do not have the same
reliability, and any fix derived from the explanation inherits the explanation's.

What is safe to act on is measurement-shaped and is the whole point of this section:

- **Measure the merged take, never the delivery.** They are different animations.
- **Deliveries that keep the body upright and near its rest are cheap** — an idle drifts by
  millimetres. The next twenty are mostly this kind, and for them this section is noise.
- **Anything that puts the character on the ground, or travels far, is not cheap.** It will
  arrive off the ground, by an amount nobody can predict from the file, and it will not
  error. `knockdown_and_recover` already shipped with this defect and nobody had looked:
  its lowest hip is **0.500 m** in the library against **0.301 m** in its own file.
- **`rig height at rest` is the early warning**, and `tools/probe_take.sh` prints it. A
  delivery at 1.60 m will come through clean. One at 1.38 m or 1.66 m will not.

---

## 7. Where this file should eventually live

Here, beside `Docs/asset-inventory-low-poly-animals.md`, which is the same kind of
document about a different source: what a pack holds, measured, so that the parts we did
not take are a searchable list rather than a forgotten folder. The two are the register of
externally sourced art in this project and they belong together.

The one thing that would move it is the wanderer's animation library growing its own
folder of build notes — but that library is thirty lines of `TAKES` in one script and does
not want a folder.
