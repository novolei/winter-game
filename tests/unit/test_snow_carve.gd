extends TestCase

## Buildings displace snow.
##
## The height field covers the whole valley and did not know buildings existed,
## so the farmhouse's floorboards sat under as much as 0.59 m of field -- and
## because the player is grounded on that same field, he stood on the drift
## rather than on the boards. Raising the house would only have hidden him.
##
## THE MEASUREMENT THAT DECIDED THE SHAPE OF THIS. Sampled over the real
## farmhouse's main room before any of this existed:
##
##     MAIN  surface 0.280..1.200  bare ground 0.273..1.200  max depth 0.007
##
## The snow in that room is SEVEN MILLIMETRES DEEP. What buries the floor is the
## bare ground: the house stands on the flank of a crest that the wind has
## already scoured clean, and the terrain there runs 0.6 m over the boards.
##
## So "carve the snow away" is not enough on its own and would have changed
## nothing at all in the room that needed it. A building levels the ground it
## stands on AND keeps the snow off it, and this exercises both.
##
## Both are written into the two rasters the field already has -- there is no
## third texture, because assets/shaders/snow_ground.gdshader reads exactly
## these two and reproduces `ground + depth` from them line for line. Write the
## field correctly and the picture follows with no shader edit.

const SnowFieldScript := preload("res://src/systems/snow_field.gd")
const RevealScript := preload("res://src/entities/interior/interior_reveal.gd")

## 140 m of ground plane over 320 subdivisions. The mesh has a vertex every
## 43.75 cm and cannot draw a transition finer than that.
const MESH_VERTEX_M := 140.0 / 320.0

const HUT_AT := Vector2(0.0, 0.0)
const HUT_HALF := Vector2(3.0, 3.0)
const FLOOR_Y := 0.30

var _field: SnowField


func before_each() -> void:
	_field = SnowFieldScript.new()
	# build_at() rather than adding to the tree: _ready() would also register the
	# field in ServiceRegistry and subscribe it to EventBus, and a unit test that
	# leaves either behind poisons every test after it.
	_field.build_at(Vector3.ZERO)


func after_each() -> void:
	_field.free()
	_field = null


func _footprint(doorways: Array = [], floor_y: float = FLOOR_Y) -> Dictionary:
	return {
		"id": 1,
		"building": "Hut",
		"floor_y": floor_y,
		"areas": [{
			"centre": HUT_AT,
			"axis_x": Vector2(1.0, 0.0),
			"axis_z": Vector2(0.0, 1.0),
			"half": HUT_HALF,
		}],
		"doorways": doorways,
	}


func _doorway() -> Dictionary:
	# In the +Z wall, blowing along -Z.
	return {
		"centre": HUT_AT + Vector2(0.0, HUT_HALF.y),
		"inward": Vector2(0.0, -1.0),
		"width": 1.0,
	}


func _at(x: float, z: float) -> Vector3:
	return Vector3(HUT_AT.x + x, 0.0, HUT_AT.y + z)


# --- the levelled site ------------------------------------------------------

## The floor is one flat plane, so the ground under it has to be one too. A
## carve that only removed snow would have left the room's bare ground running
## its natural 0.9 m of relief straight through the floorboards.
func test_a_building_levels_the_ground_it_stands_on() -> void:
	_field.carve_building(_footprint())
	var first: float = _field.surface_height_at(_at(-1.5, -1.5))
	for spot in [Vector2(1.5, -1.5), Vector2(-1.5, 1.5), Vector2(1.5, 1.5), Vector2(0.0, 0.0)]:
		assert_almost_eq(_field.surface_height_at(_at(spot.x, spot.y)), first, 0.0005)


## Just under, never over. The raster is 8 bit, so the pad cannot land on an
## arbitrary height -- it is rounded DOWN, because a pad a millimetre proud of
## the boards is snow drawn on top of the floor and a pad a centimetre under
## them is hidden by the slab.
func test_the_levelled_ground_sits_just_under_the_floorboards() -> void:
	_field.carve_building(_footprint())
	var pad: float = _field.surface_height_at(_at(0.0, 0.0))
	assert_true(pad <= FLOOR_Y, "pad %.4f is above the floor at %.4f" % [pad, FLOOR_Y])
	assert_true(pad > FLOOR_Y - 0.05, "pad %.4f is %.3f m below the floor" % [pad, FLOOR_Y - pad])


## A house is a thing that keeps snow out. Neither mobility snow nor the mature
## imprint veneer may survive the same authored carve.
func test_there_is_no_snow_inside_a_building() -> void:
	_field.carve_building(_footprint())
	assert_almost_eq(_field.depth_at(_at(0.0, 0.0)), 0.0, 0.0001)
	assert_almost_eq(_field.visible_depth_at(_at(0.0, 0.0)), 0.0, 0.0001)
	assert_almost_eq(_field.wade_factor(_at(-2.0, 1.0)), 0.0, 0.0001)


## The player reads this field and nothing else -- no gravity, no floor
## collider (player_controller.gd). Standing him on the pad is the whole
## grounding fix, and it comes for free.
func test_the_player_would_stand_on_the_boards() -> void:
	_field.carve_building(_footprint())
	var ground: float = _field.terrain_height_at(_at(0.5, -0.5))
	var depth: float = _field.depth_at(_at(0.5, -0.5))
	# player_controller.gd: global_position.y = ground + depth * (1 - sink).
	var feet := ground + depth * 0.25
	assert_true(absf(feet - FLOOR_Y) < 0.05, "feet at %.4f, boards at %.4f" % [feet, FLOOR_Y])


# --- the wall line ----------------------------------------------------------

func test_the_ground_outside_the_falloff_is_untouched() -> void:
	var far := _at(HUT_HALF.x + _field.carve_falloff_m + 4.0, 0.0)
	var before: float = _field.surface_height_at(far)
	_field.carve_building(_footprint())
	assert_almost_eq(_field.surface_height_at(far), before, 0.0001)


## A rectangular cliff-edge of snow at the wall reads as a graphics bug, and it
## is the same defect the footprint round already paid for. The falloff has to
## be measured against what the GROUND MESH can draw, not against a wall: 16 cm
## of softening is a hard step between two vertices 43.75 cm apart, however
## smooth the curve looks written down.
func test_the_wall_line_is_a_slope_the_ground_mesh_can_actually_draw() -> void:
	var worst := 0.0
	var at := -1.0
	while at <= _field.carve_falloff_m + 1.0:
		var here := SnowField.edge_weight(at, _field.carve_falloff_m)
		var next := SnowField.edge_weight(at + MESH_VERTEX_M, _field.carve_falloff_m)
		worst = maxf(worst, absf(here - next))
		at += 0.02
	assert_true(worst < 0.6, "one mesh quad carries %.2f of the whole carve" % worst)


func test_the_carve_is_whole_inside_the_wall_and_gone_at_the_falloff() -> void:
	assert_almost_eq(SnowField.edge_weight(-2.0, 1.2), 1.0)
	assert_almost_eq(SnowField.edge_weight(0.0, 1.2), 1.0)
	assert_almost_eq(SnowField.edge_weight(1.2, 1.2), 0.0)
	assert_almost_eq(SnowField.edge_weight(9.0, 1.2), 0.0)


## Negative inside, zero on the wall line, positive outside -- and correct for a
## building that is not square to the world, which every building after the
## farmhouse will be.
func test_the_footprint_measures_distance_in_the_building_s_own_axes() -> void:
	var turned := {
		"centre": Vector2(4.0, 0.0),
		"axis_x": Vector2(0.0, 1.0),
		"axis_z": Vector2(-1.0, 0.0),
		"half": Vector2(2.0, 1.0),
	}
	# half.x runs along world +Z now, so the long side is north-south.
	assert_almost_eq(SnowField.area_distance(Vector2(4.0, 0.0), turned), -1.0)
	assert_almost_eq(SnowField.area_distance(Vector2(4.0, 2.0), turned), 0.0)
	assert_almost_eq(SnowField.area_distance(Vector2(4.0, 3.0), turned), 1.0)
	assert_almost_eq(SnowField.area_distance(Vector2(6.0, 0.0), turned), 1.0)


# --- the doorway ------------------------------------------------------------

## The cheapest possible proof that the carve respects openings instead of
## stamping a rectangle: a tongue of snow over the threshold, thinning inward.
func test_snow_blows_in_through_the_doorway() -> void:
	_field.carve_building(_footprint([_doorway()]))
	var pad: float = _field.surface_height_at(_at(0.0, 0.0))
	var sill: float = _field.surface_height_at(_at(0.0, HUT_HALF.y - 0.3))
	assert_true(sill > pad + 0.02, "the threshold is only %.3f m above the pad" % (sill - pad))


func test_the_drift_thins_as_it_reaches_in() -> void:
	_field.carve_building(_footprint([_doorway()]))
	var near: float = _field.surface_height_at(_at(0.0, HUT_HALF.y - 0.3))
	var far: float = _field.surface_height_at(_at(0.0, HUT_HALF.y - 1.1))
	var pad: float = _field.surface_height_at(_at(0.0, 0.0))
	assert_true(near > far, "the drift does not thin: %.4f then %.4f" % [near, far])
	assert_true(far > pad, "the drift stops before it has thinned")


## A drift at the threshold, not a path to the middle of the room.
func test_the_drift_does_not_reach_the_middle_of_the_room() -> void:
	_field.carve_building(_footprint([_doorway()]))
	var middle: float = _field.surface_height_at(_at(0.0, 0.0))
	var back: float = _field.surface_height_at(_at(0.0, -2.0))
	assert_almost_eq(middle, back, 0.0005)


## It comes through the door, not through the wall.
func test_the_drift_is_no_wider_than_the_doorway() -> void:
	_field.carve_building(_footprint([_doorway()]))
	var pad: float = _field.surface_height_at(_at(0.0, 0.0))
	var aside: float = _field.surface_height_at(_at(2.4, HUT_HALF.y - 0.3))
	assert_almost_eq(aside, pad, 0.0005)


func test_a_building_with_no_doorway_gets_no_drift() -> void:
	_field.carve_building(_footprint())
	var pad: float = _field.surface_height_at(_at(0.0, 0.0))
	assert_almost_eq(_field.surface_height_at(_at(0.0, HUT_HALF.y - 0.3)), pad, 0.0005)


# --- keeping it there -------------------------------------------------------

## The window is regenerated from noise whenever the player strays 8 m from the
## middle of it. A carve stamped once would be wiped by the first walk to the
## barn and nobody would see it go, because it comes back the moment you look.
func test_a_recentred_window_is_still_carved() -> void:
	_field.carve_building(_footprint())
	var pad: float = _field.surface_height_at(_at(0.0, 0.0))
	assert_true(_field.follow(Vector3(11.0, 0.0, 11.0)), "the window did not move")
	assert_almost_eq(_field.surface_height_at(_at(0.0, 0.0)), pad, 0.0005)
	assert_almost_eq(_field.depth_at(_at(0.0, 0.0)), 0.0, 0.0001)


## The pad is a level, not a subtraction: stamping it twice must not dig a
## second time.
func test_carving_the_same_building_twice_changes_nothing() -> void:
	_field.carve_building(_footprint())
	var once: float = _field.surface_height_at(_at(1.0, 1.0))
	var edge: float = _field.surface_height_at(_at(HUT_HALF.x + 0.4, 0.0))
	_field.carve_building(_footprint())
	assert_almost_eq(_field.surface_height_at(_at(1.0, 1.0)), once, 0.0001)
	assert_almost_eq(_field.surface_height_at(_at(HUT_HALF.x + 0.4, 0.0)), edge, 0.0001)


## Buildings are not permanent fixtures of the *field*; they are entries in it.
func test_forgetting_a_building_gives_its_ground_back() -> void:
	var before: float = _field.surface_height_at(_at(0.0, 0.0))
	_field.carve_building(_footprint())
	_field.forget_building(1)
	assert_eq(_field.carved_count(), 0)
	assert_almost_eq(_field.surface_height_at(_at(0.0, 0.0)), before, 0.0001)


# --- the seam ---------------------------------------------------------------

## Zero direct references between systems: the building publishes, the field
## subscribes, and neither names the other. The one thing that can silently
## break that is the two ends spelling the event differently.
func test_the_building_and_the_field_name_the_same_event() -> void:
	assert_eq(String(SnowField.BUILDING_FOOTPRINT_EVENT), String(RevealScript.EVENT_FOOTPRINT))


func test_the_field_carves_what_the_bus_hands_it() -> void:
	_field.on_building_footprint(_footprint())
	assert_eq(_field.carved_count(), 1)
	assert_almost_eq(_field.depth_at(_at(0.0, 0.0)), 0.0, 0.0001)


func test_a_payload_that_is_not_a_footprint_is_ignored() -> void:
	_field.on_building_footprint("nonsense")
	_field.on_building_footprint({})
	assert_eq(_field.carved_count(), 0)


## A building whose floor could not be measured still keeps the snow out -- it
## just does not get to say where the ground is. Levelling to a height nobody
## knows would be worse than leaving it alone.
func test_a_building_with_no_floor_still_keeps_the_snow_out() -> void:
	var ground: float = _field.terrain_height_at(_at(0.0, 0.0))
	_field.carve_building(_footprint([], NAN))
	assert_almost_eq(_field.depth_at(_at(0.0, 0.0)), 0.0, 0.0001)
	assert_almost_eq(_field.terrain_height_at(_at(0.0, 0.0)), ground, 0.0001)
