class_name DogConcern
extends Node3D

## The dog notices that something is wrong with you.
##
## The corner readout is gone and the world has to say what the body is doing.
## This is the loudest thing the world has to say it with, because it does not
## report a number -- it makes something be worried about you, and this game is
## about being alone.
##
## ---------------------------------------------------------------------------
## THE ICON IS THE LABEL. THE BEHAVIOUR IS THE SIGNAL.
## ---------------------------------------------------------------------------
## Three behaviours, and every one of them must read with the badge off screen,
## because the badge is 44 px and the dog is not always in frame:
##
##   IT COMES CLOSER      standoff_m() falls from `easy_standoff_m` to
##                        `close_standoff_m` as the worst stat falls, and it
##                        STAYS there. A dog that closes and then wanders off has
##                        said nothing.
##   IT WHINES            `dog.whine` on an interval that shortens with the same
##                        curve. Sustained 723-848 Hz, carrying 35 m.
##   IT WILL NOT SETTLE   may_lie_down() is false for the whole of it. Refusing
##                        to lie down is the quietest of the three and the one a
##                        player reads without being told anything.
##
## ---------------------------------------------------------------------------
## OUTWARD AND INWARD MUST NEVER BE CONFUSED, SO THEY DIFFER FOUR WAYS
## ---------------------------------------------------------------------------
## The growl already means "a threat is over there". This means "something is
## wrong with you". Same animal, opposite directions, and a player who mixes them
## up acts on the wrong one at the worst moment. They are separated on four
## independent axes, not on one:
##
##                    outward (threat)          inward (this)
##   voice            dog.growl 145-200 Hz      dog.whine 723-848 Hz
##   carry            14 m -- a place           35 m -- you, wherever you are
##   posture          growl take, head low      idle/walk, upright, will not lie
##   position         holds its ground, faces   closes on you and faces YOU
##                    away
##
## This class never plays `growl` and never says `dog.growl`; the growl is driven
## by whatever owns threats, through the take, and `AnimalVoice` picks it up.
## `test_the_concern_never_speaks_outward` holds that.
##
## ---------------------------------------------------------------------------
## WHERE THE ONSET COMES FROM, AND WHY IT IS NOT A NUMBER I CHOSE
## ---------------------------------------------------------------------------
## "How bad is bad enough for the dog to notice" is exactly the shape of constant
## the briefing warns about: a number that is only correct in relation to another
## number, written down on its own and then drifting.
##
## So it is not written down. `onset()` is the HIGHEST threshold anybody authored
## in data/stats/*.tres -- the point at which the body first does something the
## player can feel. Today that is 0.50, where core temperature starts changing
## the breath rate and frostbite starts costing dexterity. The dog begins to
## worry at the exact moment the first consequence lands, and if a designer moves
## that threshold the dog moves with it, with no code change and nothing to
## remember.
##
## ---------------------------------------------------------------------------
## IT SUBSCRIBES, AND IT ALSO ASKS
## ---------------------------------------------------------------------------
## Three separate nodes in this project have shipped listening only for
## transitions and therefore never learning the state they were born into. The
## split here is deliberate rather than defensive:
##
##   the BADGE is episodic and event-driven -- it appears because something
##   crossed, and it dies on its own
##   the BEHAVIOUR is continuous and polled -- the dog is worried whether or not
##   anything crossed while it was watching
##
## `_ready()` reads the current values before any event can arrive, so a dog
## rescued by a player who is already freezing arrives already worried.

const EVENT_THRESHOLD_CROSSED := &"survival.threshold_crossed"
const EVENT_STAT_DEPLETED := &"survival.stat_depleted"
const EVENT_STAT_RECOVERED := &"survival.stat_recovered"

const DEFAULT_STATS_DIRECTORY := "res://data/stats"
const DEFAULT_LAYOUT := "res://data/ui/vital_layout.tres"

@export var enabled := true

@export_dir var stats_directory := DEFAULT_STATS_DIRECTORY
@export_file("*.tres") var layout_path := DEFAULT_LAYOUT

## How far off it stands when nothing is wrong, and how close it comes when
## everything is. Both in metres, measured on the flat.
##
## The near figure is inside the tight framing stop's 10.5 m of world by a wide
## margin, so the closing happens ON SCREEN rather than off the edge of it --
## which is the whole reason to have a standoff at all.
@export var easy_standoff_m := 4.2
@export var close_standoff_m := 1.3

## Dead band around the standoff, so a dog holding position does not shuffle.
@export var standoff_slack_m := 0.25

@export var approach_speed := 1.35

## Seconds between whines at the two ends of the curve.
@export var whine_period_easy := 13.0
@export var whine_period_worst := 4.5

@export var whine_call: StringName = &"dog.whine"

## How long before the badge is allowed to come back on its own while the player
## is still in trouble. Nothing is permanent: it blooms, it holds, it drifts, and
## then there is nothing above the dog's head again until either something else
## crosses or this timer runs out.
@export var badge_repeat_seconds := 14.0

## How high above the animal's own top the badge hangs.
@export var head_gap_m := 0.18

## Where the pictographs live. The readout is handed this too, so there is one
## answer to "which icon set" rather than two that can disagree.
@export_dir var icon_directory := "res://assets/ui/icons"

var _bus = null
var _survival = null
var _layout: VitalLayout = null
var _dog: Node3D = null
var _voice: AnimalVoice = null
var _target: Node3D = null
var _ground = null
var _readout: ConcernReadout = null

var _onset := -1.0
var _worst: StringName = &""
var _worst_fraction := 1.0
var _since_whine := 0.0
var _since_badge := 0.0
var _lying := false
var _moving := false
var _subscribed := false
var _shown := 0
var _was_concerned := false
var _shown_stat: StringName = &""


func _ready() -> void:
	if _bus == null:
		# Briefing trap 3: a project [autoload] is a node under /root and never
		# enters the engine's singleton registry.
		set_event_bus(get_node_or_null("/root/EventBus"))
	if _survival == null:
		set_survival_system(get_node_or_null("/root/SurvivalSystem"))
	if _layout == null and ResourceLoader.exists(layout_path):
		_layout = ResourceLoader.load(layout_path) as VitalLayout
	if _dog == null and get_parent() is Dog:
		set_dog(get_parent() as Dog)
	if _voice == null:
		_find_voice()
	if _readout == null:
		_readout = ConcernReadout.new()
		_readout.name = "Readout"
		_readout.icon_directory = icon_directory
		add_child(_readout)
	# ASKED, not waited for. See the header: a node that only hears transitions
	# never learns the state it was born into.
	_sample()
	_update_badge()


func set_event_bus(bus) -> void:
	_unsubscribe()
	_bus = bus
	_subscribe()


## Named after the THING, not the quantity. `set_wind()` was taken by a duck-typed
## tree sweep that then drove the node it was meant to inject (briefing trap 16),
## and any setter on a Node is in that shared namespace.
func set_survival_system(system) -> void:
	_survival = system


## Typed `Node3D` rather than `Dog`, and every call into it is guarded by
## `has_method`. Two reasons, and the second is the one that matters: a unit test
## must be able to hand this a bare `Node3D` instead of loading 1.5 MB of `.glb`
## to assert a distance, and the day a fox or the bear wants the same behaviour
## it should not need this file edited to get it.
func set_dog(dog: Node3D) -> void:
	_dog = dog


func set_voice(voice: AnimalVoice) -> void:
	_voice = voice


## Who the dog is worried about. Injected rather than searched for: a scene-wide
## hunt by name or by group is the shape that made `set_wind` a hazard.
func set_target(target: Node3D) -> void:
	_target = target


## Anything answering `surface_height_at`, so the dog walks on the snow rather
## than through it. Optional; without one the height it starts at is kept.
func set_ground(ground) -> void:
	_ground = ground


func set_layout(layout: VitalLayout) -> void:
	_layout = layout


func readout() -> ConcernReadout:
	return _readout


# --- what the body is doing -------------------------------------------------

## The highest threshold authored anywhere in data/stats/*.tres. See the header:
## this is a relationship, not a constant, and it is read rather than written.
func onset() -> float:
	if _onset >= 0.0:
		return _onset
	_onset = 0.0
	var dir := DirAccess.open(stats_directory)
	if dir == null:
		return _onset
	var names := dir.get_files()
	names.sort()
	for entry in names:
		var file_name := entry
		# An exported build serves data/*.tres as *.tres.remap.
		if file_name.ends_with(".remap"):
			file_name = file_name.trim_suffix(".remap")
		# Accepting only the suffixes wanted, rather than excluding the sidecars
		# known today: `.import` was the first and `.uid` the second, and an
		# exclusion list is wrong again every time a third arrives (trap 17).
		if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			continue
		var definition := ResourceLoader.load(stats_directory.path_join(file_name)) as StatDefinition
		if definition == null:
			continue
		for effect in definition.threshold_effects:
			if effect == null or effect.comparison != ThresholdEffect.Comparison.BELOW:
				continue
			_onset = maxf(_onset, effect.threshold)
	return _onset


## Which reading is furthest gone. ONE, never a list: a dog wearing a dashboard
## is the corner HUD again, in a worse place.
func worst_stat() -> StringName:
	return _worst


func worst_fraction() -> float:
	return _worst_fraction


## 0 while nothing is wrong, 1 when the worst reading is on the floor. Every
## behaviour below is this one number put through a different lever, so they
## cannot disagree with each other or with the badge.
func concern() -> float:
	var floor_at := onset()
	if floor_at <= 0.0:
		return 0.0
	return clampf(1.0 - _worst_fraction / floor_at, 0.0, 1.0)


func is_concerned() -> bool:
	return concern() > 0.0


## How far off the dog holds station, in metres.
func standoff_m() -> float:
	return lerpf(easy_standoff_m, close_standoff_m, concern())


## Whether the dog is willing to lie down. False for the whole time the player is
## in trouble -- a dog that will not settle is the quietest of the three tells
## and it costs nothing to read.
func may_lie_down() -> bool:
	return not is_concerned()


func whine_period() -> float:
	return lerpf(whine_period_easy, whine_period_worst, concern())


## How many badges this dog has raised. For tests and for a capture; a readout
## nobody can count is a readout nobody can gate.
func badges_shown() -> int:
	return _shown


func _process(delta: float) -> void:
	advance(delta)


## Public and carrying everything, so a test or a capture drives it without a
## tree tick -- the same shape as `AnimalVoice.advance()`.
func advance(delta: float) -> void:
	if not enabled or not is_finite(delta) or delta <= 0.0:
		return
	_sample()
	_since_whine += delta
	_since_badge += delta
	_walk(delta)
	_speak()
	_hold_posture()
	_update_badge()
	if _readout != null:
		_readout.anchor_at(_badge_anchor())
		_readout.advance(delta)


func _sample() -> void:
	_worst = &""
	_worst_fraction = 1.0
	if _survival == null or not _survival.has_method("stat_ids"):
		return
	for stat_id in _survival.stat_ids():
		var fraction := float(_survival.fraction_of(stat_id))
		if _worst == &"" or fraction < _worst_fraction:
			_worst = stat_id
			_worst_fraction = fraction


# --- the three behaviours ---------------------------------------------------

func _walk(delta: float) -> void:
	_moving = false
	if _dog == null or _target == null:
		return
	var here := _dog.global_position
	var there := _target.global_position
	var flat := Vector3(there.x - here.x, 0.0, there.z - here.z)
	var distance := flat.length()
	if distance <= 0.0001:
		return
	var want := standoff_m()
	var step := 0.0
	if distance > want + standoff_slack_m:
		step = minf(approach_speed * delta, distance - want)
	elif distance < want - standoff_slack_m:
		step = -minf(approach_speed * delta, want - distance)
	if absf(step) > 0.0:
		_moving = true
		var to := here + flat.normalized() * step
		if _ground != null and _ground.has_method("surface_height_at"):
			to.y = float(_ground.surface_height_at(Vector3(to.x, 0.0, to.z)))
		_dog.global_position = to
	# Facing the person, which is the half of "comes closer" a distance cannot
	# carry: an animal that closes on you while looking elsewhere is an animal
	# that happens to be near you.
	var look := Vector3(there.x, _dog.global_position.y, there.z)
	if look.distance_squared_to(_dog.global_position) > 0.0001:
		_dog.look_at(look, Vector3.UP)


func _speak() -> void:
	if not is_concerned() or _voice == null:
		return
	if _since_whine < whine_period():
		return
	# Stamped whatever the voice does with it. `say()` refuses on its own
	# cooldown too, and a request refused there must not turn into a request
	# every frame for the rest of the run.
	_since_whine = 0.0
	_voice.say(whine_call)


func _hold_posture() -> void:
	if _dog == null or not _dog.has_method("play"):
		return
	if _lying and may_lie_down():
		return
	var state := DogAnimations.WALK if _moving else DogAnimations.IDLE
	if _lying:
		# THE TELL. It was lying down and the player got into trouble, so it gets
		# up -- and stays up. Nothing announces this and nothing needs to.
		_lying = false
		_dog.play(state)
		return
	var animation_player = _dog.player() if _dog.has_method("player") else null
	if animation_player != null and not animation_player.is_playing():
		_dog.play(state)


## Ask the dog to lie down. Refused, and it says so, for the whole time the
## player is in trouble.
func lie_down() -> bool:
	if not may_lie_down() or _dog == null:
		return false
	_lying = true
	if _dog.has_method("play"):
		_dog.play(DogAnimations.LIE)
	return true


func is_lying() -> bool:
	return _lying


# --- the badge --------------------------------------------------------------

## Three ways a badge is allowed to appear, and only three.
##
##   the dog NOTICES        concern crosses from nothing to something. Polled,
##                          not waited for: a stat with no threshold authored
##                          against it emits no crossing at all, and the dog
##                          would watch it fall to zero without a word.
##   something OVERTAKES    a different reading becomes the worst one
##   the WARNING RECURS     it died a while ago and the body is still failing
##
## Nothing else, and in particular not "every frame the player is in trouble".
func _update_badge() -> void:
	var now := is_concerned()
	if now:
		if not _was_concerned:
			_raise_badge()
		elif _worst != _shown_stat:
			_raise_badge()
		elif not _readout.is_live() and _since_badge >= badge_repeat_seconds:
			_raise_badge()
	_was_concerned = now


func _raise_badge() -> bool:
	if _readout == null or _worst == &"":
		return false
	var glyph := _glyph_for(_worst)
	if glyph == &"":
		return false
	# Already up, and already about this reading. Refresh the level and leave its
	# LIFE alone: restarting the envelope on every crossing is exactly how a
	# warning becomes permanent, and a permanent warning is the corner HUD in a
	# worse place. This is the guard that keeps rule 4 true under a body that is
	# crossing a threshold every few seconds.
	if _readout.is_live() and _shown_stat == _worst:
		_readout.set_fill(_worst_fraction)
		return false
	if not _readout.show_reading(_worst, glyph, _worst_fraction):
		return false
	_shown_stat = _worst
	_since_badge = 0.0
	_shown += 1
	return true


## Which pictograph a reading wears.
##
## `data/ui/vital_layout.tres` already answers this for the interface, so a sixth
## stat is a row in that file and nothing here learns another noun (constraint 4).
##
## With one refinement, and it is not cosmetic. Frostbite is ONE row with TWO
## sites -- `stat` is the hands and `second_stat` is the feet -- so the row's
## glyph is the hand for both, and a dog warning about the player's feet would
## draw a hand. `assets/ui/icons/frostbite_feet.png` exists. So a pictograph
## named exactly for the reading wins when there is one, and the row's glyph is
## what answers when there is not.
func _glyph_for(stat_id: StringName) -> StringName:
	if ResourceLoader.exists("%s/%s.png" % [icon_directory, stat_id]):
		return stat_id
	if _layout == null:
		return &""
	var row := _layout.row_for(stat_id)
	return &"" if row == null else row.glyph


## Directly over the animal, close enough that it never reads as floating free.
func _badge_anchor() -> Vector3:
	if _dog == null:
		return global_position
	return _dog.global_position + Vector3.UP * (_animal_top() + head_gap_m)


## The animal's own height, from the POSED skeleton.
##
## `Mesh.get_aabb()` on a skinned mesh never moves and on these exports is a
## hundredth of life size (briefing trap 15), so it would hang the badge inside
## the dog's back. The bones are where the animal actually is, and they are also
## what makes the badge drop when the dog lies down.
func _animal_top() -> float:
	var top := 0.0
	var found := false
	for node in _dog.find_children("*", "Skeleton3D", true, false):
		var skeleton := node as Skeleton3D
		for bone in range(skeleton.get_bone_count()):
			var at: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
			var height := at.y - _dog.global_position.y
			if not found or height > top:
				top = height
				found = true
	return top if found else 0.5


# --- events -----------------------------------------------------------------

func _subscribe() -> void:
	if _bus == null or _subscribed:
		return
	_bus.subscribe(EVENT_THRESHOLD_CROSSED, _on_threshold_crossed)
	_bus.subscribe(EVENT_STAT_DEPLETED, _on_stat_depleted)
	_bus.subscribe(EVENT_STAT_RECOVERED, _on_stat_recovered)
	_subscribed = true


func _unsubscribe() -> void:
	if _bus == null or not _subscribed:
		return
	_bus.unsubscribe(EVENT_THRESHOLD_CROSSED, _on_threshold_crossed)
	_bus.unsubscribe(EVENT_STAT_DEPLETED, _on_stat_depleted)
	_bus.unsubscribe(EVENT_STAT_RECOVERED, _on_stat_recovered)
	_subscribed = false


## Exactly one parameter, always. EventBus calls back with one argument even when
## the payload is null, and a handler taking zero or two is a runtime error at
## dispatch rather than a parse error.
func _on_threshold_crossed(payload) -> void:
	if not enabled or payload == null:
		return
	# `active` false is a threshold being LEFT -- the body getting better. The dog
	# has nothing to warn about on the way up, and a badge that fires on recovery
	# would teach the player that it means nothing.
	if not bool(payload.get("active", false)):
		return
	_sample()
	_raise_badge()


func _on_stat_depleted(_payload) -> void:
	if not enabled:
		return
	_sample()
	_raise_badge()


func _on_stat_recovered(_payload) -> void:
	if not enabled:
		return
	_sample()


func _find_voice() -> void:
	var parent := get_parent()
	if parent == null:
		return
	for node in parent.find_children("*", "AnimalVoice", true, false):
		_voice = node as AnimalVoice
		return


func _exit_tree() -> void:
	_unsubscribe()
