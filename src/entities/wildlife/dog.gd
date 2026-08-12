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
## THE COLOUR: THE DOG WEARS ITS OWN COAT, ON THE CHARACTER EXEMPTION
## ---------------------------------------------------------------------------
## `1a4aaac` put the companion dog on Art Bible rules 8 and 9's character
## exemption, beside the protagonist, the scavenger and the bear: **free of the
## 12-colour table and the banned-feature list, using its own PBR maps.** The
## exemption's own justification is that a character needs its own materiality to
## separate from the world, and the bear was already on the list.
##
## The direct cause was a visible failure, and it is worth keeping: the dog
## textures had never been brought into the project at all, so an earlier reading
## of "the golden keeps its coat" could only be built as a flat warm shape. The
## owner looked at it and said the gold was fake. **It was.** A golden retriever
## is golden because of light and shade through fur -- here, because of a gold
## body against a cream chest with dark paws, a black nose and a red tongue --
## and not because of a hex value. A solid fill cannot stand in for a coat, and
## the two frames that proved it are still in the wave folder.
##
## So this class no longer resolves anything from `data/palette/color_bible.tres`
## and no longer goes through `CelPainter`. It mounts the pack's own 1024 colour
## map on a `StandardMaterial3D` and overrides it onto every surface, which is
## exactly what `player_controller.gd` does with the wanderer's Meshy maps and
## for the same stated reason: a material assembled from separate files does not
## belong inside the model file.
##
## Snow no longer has to be refused, either. `CelPainter`'s `snow_receptivity` is
## a parameter of the world's cel shader; a character on a StandardMaterial3D is
## outside that system entirely, so a living animal carries no settled snow by
## construction rather than by a flag.
##
## ---------------------------------------------------------------------------
## THE PART OF THE RULE 12 AMENDMENT THAT STILL BINDS
## ---------------------------------------------------------------------------
## The Director amended Art Bible rule 12 in `a0f7d8c` to put the companion dog
## on the warm list, as a sixth entry beside the window, the fire, the beacon,
## the truck and the scarf. The reasoning is that the list was incomplete rather
## than broken: three of the five are warm because they are HEAT and two because
## they are TRACES OF A PERSON, and an animal that sleeps against you and keeps
## the night off is both. A gold dog is not a breach of 暖色即生存; it is that
## sentence.
##
## **Scoped to the dog alone.** Every other animal in this game -- deer, fox,
## rabbit, chicken, the two birds, the bear, the wolf -- stays repainted to the
## palette, because at a 45-degree camera under aerial perspective breed is
## carried by silhouette and mass rather than by coat colour. The lying-dog
## capture is the evidence for that and it stands; it just does not apply to the
## one animal the player names.
##
## ---------------------------------------------------------------------------
## WHICH THREE COLOURS, MEASURED RATHER THAN PICKED
## ---------------------------------------------------------------------------
## `tools/blender/measure_dog_coats.py` samples each breed's own texture through
## its own UVs and weights every colour by the SQUARE METRES of dog it covers --
## which is a different answer from the texture's histogram, and the one a viewer
## sees. The pack ships five maps, one per breed variant, not the single shared
## one `Docs/asset-inventory-low-poly-animals.md` section 4 reports:
##
##   golden retriever            #D2BA94  67.2% of the animal, mean #D1BDA0
##   great dane   (Black)        #535355  81.5%,               mean #696766
##   great dane   (Brown)        #A37D47  81.3%,               mean #9F7E50
##   chihuahua    (Black)        #727275  76.6%,               mean #8A8786
##   chihuahua    (plain, fawn)  #C4A687  72.3%,               mean #C6AD93
##
## **Only the golden retriever has one coat.** The other two ship a warm variant
## and a cool one, and the Director's ruling says which to take in as many words:
## the warm one must be the best outcome of a random draw, so the other two are
## the Black variants. That is a choice, it is reversible in one constant here,
## and the numbers above are what it should be argued with.
##
## ---------------------------------------------------------------------------
## THE TWO FLAT WARMS THAT WERE TRIED AND ARE NOW SUPERSEDED
## ---------------------------------------------------------------------------
## Kept because the pair of frames is the evidence for the amendment above, and
## because somebody will otherwise propose the same thing again.
##
## Both of the palette's existing warms were tried on the real model at the real
## camera, and nothing was added to the twelve. Measured, they could not be
## separated on the quota:
## 0.2480% of frame against 0.2487%, eleven pixels in 1.6 million, because the
## warm count is the animal's SILHOUETTE and both candidates are warm.
##
## `#A05A35` read as a terracotta dog -- a fox, which is another animal on the
## roster. `#FFB257` read as gold and was chosen. **Both were wrong**, and the
## owner said so in one look: neither is a coat. A flat fill has no chest, no
## paws, no nose and no shading, and at 74 px of dog those are most of what says
## "golden retriever" rather than "orange animal".
##
## The lesson is the one this task keeps re-learning from the other direction:
## the colour distance, the luminance arithmetic and the quota all said the
## question was between two hex values, and the question was not about a hex
## value at all.

## The pack's own colour map, per breed, copied into the project beside the
## model. One `_COL_1k.png` each, 1024 square, 78-101 KB.
##
## **Two of the three ship more than one coat and this is a choice.** The pack
## has a fawn chihuahua and a brown great dane as well, and both were measured
## (see the block above). The Black variants are taken so that rule 12's
## amendment still means what it says -- the golden is the warm one and finding
## it is the best outcome of the draw. Either alternative is one line here:
##
##   chihuahua   fawn   `Dog_Chihauhau_COL_1k.png`      mean #C6AD93
##   great dane  brown  `Dog_GreatDane_Brown_COL_1k.png` mean #9F7E50
const ALBEDO := {
	DogAnimations.CHIHUAHUA: "res://assets/models/characters/dogs/chihuahua_albedo.png",
	DogAnimations.GOLDEN_RETRIEVER: "res://assets/models/characters/dogs/golden_retriever_albedo.png",
	DogAnimations.GREAT_DANE: "res://assets/models/characters/dogs/great_dane_albedo.png",
}

## What the map is multiplied by before it is lit.
##
## NOT a recolour, and the difference matters after the last round. MEASURED on
## the first textured capture, with the map mounted raw: the golden retriever's
## `#D2BA94` body arrived on screen as `#FFE0AB` -- the red channel CLIPPED at
## 1.0 and the rest 1.2x over -- and the black great dane's `#535355` arrived as
## `#918D90`, a mid grey. The coat was bound, correct, and blown out, which reads
## as a washed cream dog and is its own kind of fake.
##
## `player_controller.gd` has the same problem with the same cause and this
## project already has the answer: `CharacterScheme.albedo_tint`, whose own
## comment says a grey value darkens without shifting hue and that it exists to
## UNCLIP -- the wanderer's scarf saturates its red channel at full brightness
## and reads as fluorescent orange until it is pulled down. The shipped wanderer
## runs at (0.80, 0.80, 0.82) and this is the same number, arrived at from the
## same measurement: 1 / 1.20 is 0.83.
##
## A constant rather than a `CharacterScheme.tres` because there is one look and
## no behaviour to choose between looks yet. The day a second one is wanted --
## a wet dog, a snow-caked dog -- this becomes a resource exactly as the
## wanderer's did, and nothing else moves.
const ALBEDO_TINT := Color(0.80, 0.80, 0.82)

## Flat, rough, non-metal.
##
## The exemption frees a character from the banned-feature list, and the map is
## colour only -- the pack ships no normal, roughness or metallic for these -- so
## there is nothing to strip. What there IS to do is stop `StandardMaterial3D`'s
## defaults inventing a specular highlight on fur, which is `rigkit.make_matte()`
## on the Blender side and these three lines on this one.
const ROUGHNESS := 0.95
const METALLIC := 0.0
const SPECULAR := 0.0

## Which dog this is. Set before the node enters the tree; `_ready()` builds the
## rig from it. One of `DogAnimations.BREEDS`.
@export var breed: StringName = DogAnimations.GOLDEN_RETRIEVER

var _material: StandardMaterial3D = null
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


## The material this dog wears: its own coat map on a plain
## `StandardMaterial3D`, matte.
##
## Built here rather than baked into the `.glb`, and OVERRIDDEN rather than
## assigned into the mesh, for the reason `player_controller.gd` gives about the
## wanderer: the model file's own surface material is whatever Godot invented for
## a primitive that arrived without one, and a material assembled from separate
## files does not belong inside a model.
func material() -> StandardMaterial3D:
	if _material != null:
		return _material
	_material = StandardMaterial3D.new()
	var path: String = String(ALBEDO.get(breed, ""))
	if path == "" or not ResourceLoader.exists(path):
		# Never silently. A StandardMaterial3D with no map is white plastic, and
		# a white dog on a snowfield has no silhouette at all -- which is the
		# argument the inventory used to refuse the polar bear.
		push_warning("dog: no coat map for breed %s at %s" % [breed, path])
		return _material
	_material.albedo_texture = load(path)
	# Multiplies the map. See ALBEDO_TINT: raw, the coat clips.
	_material.albedo_color = ALBEDO_TINT
	_material.roughness = ROUGHNESS
	_material.metallic = METALLIC
	# `metallic_specular`, which is what Godot 4 calls the Specular slider.
	# `specular` is the Godot 3.x name; assigning it does not error, it emits
	# `WARNING: Godot 3.x SpatialMaterial remapped parameter not found` and
	# leaves the default 0.5 in place -- a highlight on fur, and a dirty console.
	_material.metallic_specular = SPECULAR
	return _material


## Where this breed's coat map lives. Static, so a gate can check the file
## without building a rig.
static func albedo_path(which: StringName) -> String:
	return String(ALBEDO.get(which, ""))


func _paint(rig: Node3D) -> void:
	var worn := material()
	for node in rig.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null:
			continue
		instance.material_override = worn
