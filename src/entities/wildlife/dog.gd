class_name Dog
extends Node3D

## One dog: a model, a palette colour and a take library. **No behaviour.**
##
## ---------------------------------------------------------------------------
## WHAT THIS IS FOR AND WHERE IT STOPS
## ---------------------------------------------------------------------------
## The companion -- following, protecting, being named, surviving a save -- is a
## later task and none of it is here. What is here is the three things that have
## to be true before any of that can be written, and that a behaviour must not
## have to get right for itself:
##
##   WHICH MODEL, per breed, and the library of takes hung on it
##   WHICH COLOUR, resolved from `data/palette/color_bible.tres`
##   WHICH WAY ROUND, which is the bug this asset class ships with
##
## `Bird` is the same three things plus eight hundred lines of timeline. This is
## deliberately only the three, so that when the companion is written it can be
## written against a rig that is already correct instead of against a rig plus a
## list of things to remember.
##
## ---------------------------------------------------------------------------
## THE FACING, AND WHY THERE IS NO `MODEL_YAW` CONSTANT HERE
## ---------------------------------------------------------------------------
## The crow shipped a whole wave flying tail-first because Unity is left-handed
## with +Z forward and Godot's `look_at()` aims -Z. These dogs came out of the
## same package with the same handedness, and `tools/blender/build_dog.py`
## measured it on all three rigs before applying a degree.
##
## It is fixed at the RIG -- the `.glb` is written already turned -- and not by a
## constant every consumer applies. `Bird` carries `species.model_yaw` because
## its models are third-party FBXs this project cannot rewrite; the dogs go
## through a Blender build this project owns, so the correction belongs in the
## asset and there is nothing left for a call site to forget.
##
## `tests/art/test_dog_models.gd` therefore measures the SHIPPED `.glb`, bones
## and geometry, with no constant in the loop. A gate that reads a constant can
## only tell you the constant is what it was.
##
## ---------------------------------------------------------------------------
## THE COLOUR, AND WHAT REPAINTING COST
## ---------------------------------------------------------------------------
## The pack ships one 1024 colour map shared by all three dogs: 326 unique
## colours, 40.2% `#2B2B2D`, then `#B19D8A` and `#D09D79` -- a photoreal-ish
## brown-and-tan skin. `Docs/asset-inventory-low-poly-animals.md` section 2
## priced the repaint as "moderate -- 326 colours".
##
## **The palette cannot hold it.** The twelve are five snow blues, four structure
## navies and three warm tones, and Art Bible rule 12 reserves warm for windows,
## fire, beacons, the truck and the scarf. So every colour on that map that is
## not already near-black quantises to a navy, and a golden retriever repainted
## into this palette is not a golden retriever with different values -- it is a
## dark blue dog. Keeping the map to preserve the eyes and the muzzle would have
## bought two darker pixels at this game's framing and cost a texture no gate
## judges, on a material `CelPainter` cannot make: `material_for()` takes one
## flat colour, and giving it a map means a shader change, which this wave may
## not make.
##
## So the map is DROPPED at build time -- `export_materials="NONE"` in
## `build_dog.py` -- and the animal is painted one flat palette tone, exactly as
## the crow and the pigeon are. What that cost, stated so nobody has to rediscover
## it: **the eyes, the nose, the muzzle and the paws are gone.** A dog at 0.3 m to
## 1.3 m is a silhouette with a value, and the three breeds are told apart by size
## and outline, not by markings.
##
## `structure_tones[2]`, between the pigeon's [1] and the crow's near-black [3].
## Not [0], which is the farmhouse's own siding. All three breeds share it,
## which is not laziness: the scene picks one at random and they are never on
## screen together, so a per-breed tone would be a distinction nobody can ever
## make -- and there are only four structure tones to spend.
##
## Snow is refused through `CelPainter.material_for(tone, true)` rather than by
## writing `snow_receptivity` afterwards. The `bare` flag is part of the
## painter's CACHE KEY, so the dog and anything else painted `#1C2A45` become two
## materials; writing the parameter on would turn the snow off for every one of
## them. A living animal carries no settled snow, and by day six a dog that did
## would be white.

const PALETTE_PATH := "res://data/palette/color_bible.tres"

## Which of the twelve. See the header for why one tone serves all three breeds.
const PALETTE_FAMILY := "structure"
const PALETTE_INDEX := 2

## Which dog this is. Set before the node enters the tree; `_ready()` builds the
## rig from it. One of `DogAnimations.BREEDS`.
@export var breed: StringName = DogAnimations.GOLDEN_RETRIEVER

var _painter: CelPainter = null
var _material: ShaderMaterial = null
var _player: AnimationPlayer = null
var _rig: Node3D = null


func _ready() -> void:
	build_rig()


## Instantiate the model, paint it, and hang the take library on its own
## AnimationPlayer.
##
## Public and idempotent so a gate can build one without a tree and so a later
## companion can swap breeds at spawn. Returns false when the model is missing,
## rather than half-building.
func build_rig() -> bool:
	if _rig != null:
		return true
	if not ResourceLoader.exists(DogAnimations.model_path(breed)):
		push_warning("dog: no model for breed %s" % breed)
		return false
	var packed := ResourceLoader.load(DogAnimations.model_path(breed))
	if not (packed is PackedScene):
		return false
	var rig := (packed as PackedScene).instantiate() as Node3D
	if rig == null:
		return false
	rig.name = "Rig"
	add_child(rig)
	_rig = rig
	_paint(rig)
	for node in rig.find_children("*", "AnimationPlayer", true, false):
		_player = node as AnimationPlayer
		break
	if _player == null:
		push_warning("dog: %s carries no AnimationPlayer" % DogAnimations.model_path(breed))
		return false
	if _player.has_animation_library(DogAnimations.LIBRARY):
		_player.remove_animation_library(DogAnimations.LIBRARY)
	_player.add_animation_library(DogAnimations.LIBRARY, DogAnimations.build(breed))
	return true


## Play the take this breed uses for `state`. Returns the state it actually
## played, or `&""` when the breed can answer the question at all -- which is a
## hole in the vocabulary and not something to swallow.
##
## THE RESOLUTION HAPPENS HERE AND ONLY HERE. A behaviour says `play(STAND)` and
## does not learn which dog it got; `DogAnimations.resolve()` decides, once, in a
## table anybody can read.
func play(state: StringName) -> StringName:
	var played := DogAnimations.resolve(breed, state)
	if played == &"" or _player == null:
		return &""
	_player.play("%s/%s" % [DogAnimations.LIBRARY, played])
	return played


func player() -> AnimationPlayer:
	return _player


## Hand the dog the world's painter, so it is lit by the same two bands as
## everything else. Anything already resolved came from the previous one.
func set_painter(painter: CelPainter) -> void:
	_painter = painter
	_material = null


## The material this dog wears: its palette tone on the world's two-band cel
## shader, keyed BARE so no snow ever settles on it.
func material() -> ShaderMaterial:
	if _material != null:
		return _material
	if _painter == null:
		_painter = CelPainter.new()
	_material = _painter.material_for(palette_tone(), true)
	return _material


## The dog's colour, read from the palette and never written here (briefing
## constraint 6). Public so a gate can assert what it resolved to rather than
## trusting a comment.
func palette_tone() -> Color:
	var bible: Resource = load(PALETTE_PATH)
	if bible == null:
		return Color(0.0, 0.0, 0.0)
	var tones: Array = bible.get(PALETTE_FAMILY + "_tones")
	if tones == null or tones.size() <= PALETTE_INDEX:
		return Color(0.0, 0.0, 0.0)
	return tones[PALETTE_INDEX]


func _paint(rig: Node3D) -> void:
	var worn := material()
	for node in rig.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		var mesh := instance.mesh
		if mesh == null:
			continue
		for surface in range(mesh.get_surface_count()):
			instance.set_surface_override_material(surface, worn)
