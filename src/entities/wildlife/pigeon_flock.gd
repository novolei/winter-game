class_name PigeonFlock
extends BirdFlock

## The pigeons in the valley: `BirdFlock` driven by `data/wildlife/pigeon.tres`.
##
## ---------------------------------------------------------------------------
## THE THREE OVERRIDES THIS CLASS USED TO NEED
## ---------------------------------------------------------------------------
## `PigeonFlock extends CrowFlock` had to override six methods -- `_init`,
## `ask_the_clock`, `_on_day_started`, `_on_night_started`, `available_perches`
## and `_build_crow` -- to say three things. All three are fields now:
##
##   1. NIGHT IS NOT A REASON TO EMPTY THE WIRE. `daylight_only = false`.
##      A rock dove roosts on the ledges it feeds from: it is on the eave at dusk
##      and still on it at dawn. The parent's `_night` flag means one thing in
##      its own logic -- the wires must be empty -- and `_dark` is the separate
##      fact that the sun is down. `BirdFlock` now keeps both for every species,
##      so nothing has to be held at false by hand.
##
##   2. IT WILL NOT LAND ON A BIRD THAT IS ALREADY THERE.
##      `avoids_occupied_perches = true`. **And it now works in both directions
##      if the crows ever want it**: the filter is on `BirdFlock` and asks the
##      tree for `Bird`, so it sees crows and pigeons alike. It is still one-way
##      today only because `crow.tres` leaves the flag false, which is a data
##      decision rather than a file nobody could touch.
##
##   3. A FLOCK OF PIGEONS IS BIGGER AND LESS EASILY MOVED. `fewest 2, most 6,
##      flush_radius_m 5.0`. Both are the bird rather than a preference: rock
##      doves feed and roost in groups where a crow perches in ones and twos, and
##      they are used to people. The flush radius being inside the crow's 8 m is
##      what makes the same walk past the pole put the crows up first and the
##      pigeons only if he keeps coming.
##
## What is left is the same one method `CrowFlock` keeps, and for the same
## reason: `test_pigeon_flock.gd` asserts the flock hatches pigeons rather than
## plain birds, which is the assertion that would have caught a lost override
## back when there were five of them.
const SPECIES := preload("res://data/wildlife/pigeon.tres")
const PRESENTATION: PigeonPresentation = preload("res://data/wildlife/pigeon_presentation.tres")
const PigeonFootprintsScript := preload("res://src/entities/wildlife/pigeon_footprints.gd")
const BreadcrumbScatterScript := preload("res://src/entities/wildlife/breadcrumb_scatter.gd")
const PigeonAffectionScript := preload("res://src/entities/wildlife/pigeon_affection.gd")
const EVENT_WAITING_FOR_FOOD := &"wildlife.pigeon_waiting_for_food"
const EVENT_FED := &"wildlife.pigeon_fed"
const EVENT_FOOTPRINT := &"wildlife.pigeon_footprint"
const EVENT_FEED_STARTED := &"wildlife.pigeon_feed_started"
const EVENT_INTERACTION_ACTIVATED := &"interaction.activated"
const EVENT_OFFER_ENTERED := &"interaction.offer_entered"
const EVENT_OFFER_CHANGED := &"interaction.offer_changed"
const EVENT_OFFER_EXITED := &"interaction.offer_exited"

@export_range(0.0, 1.0, 0.01) var friendly_visit_chance := 0.34
@export_range(4.0, 60.0, 0.5) var friendly_check_seconds := 12.0
@export_range(1, 4, 1) var max_ground_visitors := 2
@export var friendly_radius_min_m := 2.4
@export var friendly_radius_max_m := 4.2
@export var friendly_wait_min_seconds := 14.0
@export var friendly_wait_max_seconds := 28.0
@export var feeding_interaction_radius_m := 4.8
@export_range(0.3, 2.0, 0.05) var feeding_hold_seconds := 0.8
@export var feeding_prompt_front_m := 1.05
@export var food_throw_distance_m := 2.05
@export var feed_release_seconds := 0.58
@export var feed_duration_seconds := 1.0333

var _friendly_timer := 12.0
var _footprints: MultiMeshInstance3D = null
var _feeding_connected := false
var _ground_offers: Dictionary = {}
var _announced_waiting: Dictionary = {}
var _reserved_visitors: Dictionary = {}
var _pending_feeds: Array[Dictionary] = []
var _food_patches: Array = []
var _food_patch_by_offer: Dictionary = {}
var _feed_gesture_left := 0.0
var _affection_total := 0


func _init() -> void:
	species = SPECIES


func _ready() -> void:
	super._ready()
	_footprints = PigeonFootprintsScript.new()
	_footprints.name = "PigeonFootprints"
	add_child(_footprints)
	_connect_feeding()


func _exit_tree() -> void:
	_withdraw_all_ground_offers()
	_disconnect_feeding()
	super._exit_tree()


func set_event_bus(bus) -> void:
	_disconnect_feeding()
	super.set_event_bus(bus)
	_connect_feeding()


func _new_bird() -> Bird:
	var pigeon := Pigeon.new()
	pigeon.set_plumage_variant(_rng.randi_range(0, Pigeon.PLUMAGE_COUNT - 1))
	pigeon.footprint_stamped.connect(_on_footprint_stamped)
	pigeon.meal_completed.connect(_on_pigeon_meal_completed.bind(pigeon))
	return pigeon


func _on_footprint_stamped(at: Vector3, heading: Vector3, left_foot: bool) -> void:
	var lifetime := 6.0
	if _footprints != null and is_instance_valid(_footprints):
		lifetime = float(_footprints.call(&"lifetime_for", _wind_strength))
		_footprints.call(&"stamp", at, heading, _wind_strength)
	if _bus != null:
		_bus.emit_event(EVENT_FOOTPRINT, {
			"subject": &"pigeon",
			"position": at,
			"heading": heading,
			"left_foot": left_foot,
			"lifetime_seconds": lifetime,
		})


func footprint_renderer() -> MultiMeshInstance3D:
	return _footprints


func advance(delta: float) -> void:
	super.advance(delta)
	if not is_finite(delta) or delta <= 0.0:
		return
	_feed_gesture_left = maxf(_feed_gesture_left - delta, 0.0)
	_advance_feed_releases(delta)
	_publish_ground_offers()
	if not enabled:
		return
	_friendly_timer -= delta
	if _friendly_timer > 0.0:
		return
	_friendly_timer = _rng.randf_range(friendly_check_seconds * 0.8, friendly_check_seconds * 1.25)
	try_friendly_visit()


## One low-frequency probability draw, never per bird and never per frame.
## `force` exists for captures and tests; gameplay always takes the authored
## chance. At most two ground visitors are alive at once.
func try_friendly_visit(force := false) -> bool:
	if not enabled or _blowing or ground_visitor_count() >= max_ground_visitors:
		return false
	var watched := _watch()
	if watched == null:
		return false
	if not force and _rng.randf() > friendly_visit_chance:
		return false
	var centre := watched.global_position if watched.is_inside_tree() else watched.position
	var angle := _rng.randf_range(0.0, TAU)
	var radius := _rng.randf_range(
		minf(friendly_radius_min_m, friendly_radius_max_m),
		maxf(friendly_radius_min_m, friendly_radius_max_m)
	)
	var radial := Vector3(cos(angle), 0.0, sin(angle))
	var landing := centre + radial * radius
	var surface = _registry.get_service(&"snow_field") if _registry != null else null
	if surface != null and surface.has_method(&"surface_height_at"):
		landing.y = float(surface.call(&"surface_height_at", landing))
	var from := landing + radial * arrival_distance_m + Vector3.UP * arrival_height_m
	var pigeon := _build_bird() as Pigeon
	if pigeon == null:
		return false
	var wait := _rng.randf_range(
		minf(friendly_wait_min_seconds, friendly_wait_max_seconds),
		maxf(friendly_wait_min_seconds, friendly_wait_max_seconds)
	)
	var calls := _rng.randi_range(2, 4)
	if not pigeon.begin_ground_visit(landing, from, watched, wait, surface, calls):
		pigeon.queue_free()
		return false
	_birds.append(pigeon)
	return true


func ground_visitor_count() -> int:
	var count := 0
	for bird in _birds:
		if bird is Pigeon and (bird as Pigeon).is_ground_visitor():
			count += 1
	return count


## Inventory/interaction code offers one logical landing patch without a direct
## reference to an individual bird. The closest visitors WALK to it; the fed
## event is deliberately deferred until the full peck take finishes.
func offer_food(at: Vector3, radius_m := 2.5) -> int:
	var accepted := 0
	for bird in _birds:
		if not is_instance_valid(bird):
			continue
		var pigeon := bird as Pigeon
		if pigeon == null or not pigeon.is_waiting_for_food():
			continue
		var flat_gap := Vector2(pigeon.where().x - at.x, pigeon.where().z - at.z).length()
		if flat_gap > maxf(radius_m, 0.0):
			continue
		pigeon.receive_food(at)
		accepted += 1
	return accepted


func active_food_patch_count() -> int:
	var living := 0
	for raw in _food_patches:
		if raw != null and is_instance_valid(raw):
			living += 1
	return living


func affection_count() -> int:
	return _affection_total


func _publish_ground_offers() -> void:
	var current: Dictionary = {}
	if _feed_gesture_left > 0.0:
		_withdraw_all_ground_offers()
		return
	var watched := _watch()
	var player_at := Vector3(INF, INF, INF)
	if watched != null:
		player_at = watched.global_position if watched.is_inside_tree() else watched.position
	for bird in _birds:
		if not is_instance_valid(bird):
			continue
		var pigeon := bird as Pigeon
		if pigeon == null or not pigeon.is_waiting_for_food():
			continue
		var id := _offer_id(pigeon)
		if _reserved_visitors.has(id):
			continue
		var pigeon_at := pigeon.where()
		if watched == null or _flat_gap(player_at, pigeon_at) > feeding_interaction_radius_m:
			continue
		var toward := Vector3(
			pigeon_at.x - player_at.x, 0.0, pigeon_at.z - player_at.z
		)
		var prompt_forward := toward.normalized() if toward.length_squared() > 0.0001 \
			else Vector3.FORWARD
		if watched.has_method(&"interaction_forward"):
			var reported: Variant = watched.call(&"interaction_forward")
			if reported is Vector3:
				var flat := Vector3(reported.x, 0.0, reported.z)
				if flat.is_finite() and flat.length_squared() > 0.0001:
					prompt_forward = flat.normalized()
		# The line belongs to the player's interaction space, not to the bird.
		# Distance to the bird decides whether it exists; the visible anchor stays
		# just ahead of the player's boots as requested.
		var at := player_at + prompt_forward * maxf(feeding_prompt_front_m, 0.0)
		at.y = _surface_height(at)
		var spatial := {"anchor": at, "target": pigeon_at}
		var offer := {
			"id": id,
			"kind": &"pigeon_feed",
			"verb": "投喂",
			"label": "",
			"world_position": at,
			"target_position": pigeon_at,
			"enabled": true,
			"reason": &"",
			"hold_seconds": feeding_hold_seconds,
			"facing_dot_min": -1.0,
			"guide_line": true,
			"accent_color": PRESENTATION.feed_prompt_color,
			"guide_color": PRESENTATION.feed_guide_color,
		}
		if not _ground_offers.has(id):
			current[id] = spatial
			_emit(EVENT_OFFER_ENTERED, offer)
			if not _announced_waiting.has(id):
				_announced_waiting[id] = true
				_emit(EVENT_WAITING_FOR_FOOD, {"id": id, "position": pigeon_at})
		else:
			var previous: Dictionary = _ground_offers[id]
			var anchor_moved := (previous.get("anchor", at) as Vector3).distance_squared_to(at) >= 0.0016
			var target_moved := (previous.get("target", pigeon_at) as Vector3) \
				.distance_squared_to(pigeon_at) >= 0.0016
			if anchor_moved or target_moved:
				current[id] = spatial
				_emit(EVENT_OFFER_CHANGED, offer)
			else:
				# Compare the next frame with the last PUBLISHED location, not the
				# last sampled one. A walking pigeon moves only millimetres per frame;
				# replacing the cache here would swallow that motion forever.
				current[id] = previous
	for raw_id in _ground_offers.keys():
		var id := StringName(raw_id)
		if not current.has(id):
			_emit(EVENT_OFFER_EXITED, {"id": id})
	_ground_offers = current


func _withdraw_ground_offer(id: StringName) -> void:
	if not _ground_offers.has(id):
		return
	_emit(EVENT_OFFER_EXITED, {"id": id})
	_ground_offers.erase(id)


func _withdraw_all_ground_offers() -> void:
	for raw_id in _ground_offers.keys():
		_emit(EVENT_OFFER_EXITED, {"id": StringName(raw_id)})
	_ground_offers.clear()


func _on_interaction_activated(payload) -> void:
	if not (payload is Dictionary) or StringName(payload.get("kind", &"")) != &"pigeon_feed":
		return
	if _feed_gesture_left > 0.0:
		return
	var id := StringName(payload.get("id", &""))
	var pigeon := _pigeon_for_offer(id)
	if pigeon == null or not pigeon.is_waiting_for_food():
		return
	var watched := _watch()
	if watched == null:
		return
	var player_at := watched.global_position if watched.is_inside_tree() else watched.position
	var pigeon_gap := _flat_gap(player_at, pigeon.where())
	if pigeon_gap > feeding_interaction_radius_m or pigeon_gap <= Pigeon.FLEE_RADIUS_M:
		return
	var toward := Vector3(pigeon.where().x - player_at.x, 0.0, pigeon.where().z - player_at.z)
	if toward.length_squared() <= 0.0001:
		return
	var aimed := toward.normalized()
	# The one-shot turns the body squarely toward the pigeon. Use that same
	# heading for the visual throw; using the pre-turn facing at the edge of the
	# cone could put crumbs more than a metre sideways from the reaching hand.
	var target := player_at + aimed * food_throw_distance_m
	target.y = _surface_height(target)
	var origin := player_at + Vector3.UP * 1.05 + aimed * 0.28
	_reserved_visitors[id] = true
	pigeon.reserve_food_arrival(feed_release_seconds + BreadcrumbScatterScript.MAX_FLIGHT_SECONDS)
	_feed_gesture_left = maxf(feed_duration_seconds, 0.0)
	_withdraw_all_ground_offers()
	_pending_feeds.append({
		"id": id,
		"elapsed": 0.0,
		"origin": origin,
		"target": target,
		"released": false,
	})
	_emit(EVENT_FEED_STARTED, {
		"id": id,
		"kind": &"pigeon_feed",
		"pigeon_position": pigeon.where(),
		"world_position": target,
		"duration_seconds": feed_duration_seconds,
		"release_seconds": feed_release_seconds,
	})


func _advance_feed_releases(delta: float) -> void:
	var waiting: Array[Dictionary] = []
	for entry in _pending_feeds:
		entry["elapsed"] = float(entry.get("elapsed", 0.0)) + delta
		var elapsed := float(entry["elapsed"])
		if elapsed + 0.000001 < feed_release_seconds:
			waiting.append(entry)
			continue
		var origin: Vector3 = entry.get("origin", Vector3.ZERO)
		var target: Vector3 = entry.get("target", Vector3.ZERO)
		var id := StringName(entry.get("id", &""))
		if not bool(entry.get("released", false)):
			var scatter := _spawn_breadcrumbs(origin, target)
			_food_patch_by_offer[id] = scatter
			entry["released"] = true
		# The bird may notice the throw, but it does not commit to a ground peck
		# until the slowest piece has physically reached the patch.
		if elapsed + 0.000001 < feed_release_seconds \
				+ BreadcrumbScatterScript.MAX_FLIGHT_SECONDS:
			waiting.append(entry)
			continue
		var pigeon := _pigeon_for_offer(id)
		if pigeon != null and pigeon.is_waiting_for_food():
			pigeon.receive_food(target)
	_pending_feeds = waiting


func _spawn_breadcrumbs(origin: Vector3, target: Vector3) -> BreadcrumbScatter:
	var scatter = BreadcrumbScatterScript.new()
	scatter.name = "BreadcrumbScatter"
	add_child(scatter)
	scatter.scatter(origin, target, _rng.randi())
	_food_patches.append(scatter)
	return scatter as BreadcrumbScatter


func _on_pigeon_meal_completed(at: Vector3, pigeon: Pigeon) -> void:
	if pigeon == null or not is_instance_valid(pigeon):
		return
	var id := _offer_id(pigeon)
	_retire_food_patch(id)
	_affection_total += 1
	var heart = PigeonAffectionScript.new()
	heart.name = "AffectionHeart"
	heart.position = Vector3.UP * 0.42
	heart.configure(_rng.randi())
	pigeon.add_child(heart)
	_emit(EVENT_FED, {
		"id": id,
		"count": 1,
		"position": at,
	})


func _retire_food_patch(id: StringName) -> void:
	var raw: Variant = _food_patch_by_offer.get(id, null)
	_food_patch_by_offer.erase(id)
	if raw == null or not is_instance_valid(raw):
		return
	var scatter := raw as BreadcrumbScatter
	if scatter == null:
		return
	if scatter.is_inside_tree():
		scatter.queue_free()
	else:
		scatter.free()


func _pigeon_for_offer(id: StringName) -> Pigeon:
	if id == &"":
		return null
	for bird in _birds:
		# Guard BEFORE the typed cast: a flock list may contain a freed Variant for
		# the remainder of a frame (AGENT-BRIEFING trap 10).
		if not is_instance_valid(bird):
			continue
		var pigeon := bird as Pigeon
		if pigeon != null and _offer_id(pigeon) == id:
			return pigeon
	return null


func _offer_id(pigeon: Pigeon) -> StringName:
	return StringName("pigeon_feed:%d" % pigeon.get_instance_id())


func _surface_height(at: Vector3) -> float:
	if _registry != null:
		var surface = _registry.get_service(&"snow_field")
		if surface != null and is_instance_valid(surface) and surface.has_method(&"surface_height_at"):
			return float(surface.call(&"surface_height_at", at))
	return at.y


func _connect_feeding() -> void:
	if _feeding_connected or _bus == null or not is_instance_valid(_bus):
		return
	_bus.subscribe(EVENT_INTERACTION_ACTIVATED, _on_interaction_activated)
	_feeding_connected = true


func _disconnect_feeding() -> void:
	if _feeding_connected and _bus != null and is_instance_valid(_bus):
		_bus.unsubscribe(EVENT_INTERACTION_ACTIVATED, _on_interaction_activated)
	_feeding_connected = false
