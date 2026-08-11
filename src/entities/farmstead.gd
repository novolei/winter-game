class_name Farmstead
extends Node3D

## The composition. Everything in the frame except the house, the ground and
## the player.
##
## Art Bible rule 1's first clause is that the camera never rotates, and the
## consequence nobody states is that the *world* is therefore the only thing
## that can be composed. A shot you cannot re-frame is a shot you have to build.
## So this is not a prop scatter -- the positions in scenes/main.tscn were
## measured off Refs/game ref/level.jpg and pushed through the camera basis, and
## every one of them is somewhere for a reason.
##
## HOW THE POSITIONS WERE DERIVED, so the next person can move something without
## guessing. The rig is pitched 45 degrees and yawed -35, which fixes two ground
## directions on the screen:
##
##     screen right = ( 0.8192, 0.5736)   in world (x, z)
##     screen up    = ( 0.5736,-0.8192)   in world (x, z), before the
##                                        sin(45) vertical squash
##
## so world +X reads as up-and-right at 26 degrees and world -Z as up-and-left at
## 45. Reading a feature's position off level.jpg as a fraction (u, v) of the
## image and running it back through those two vectors gives the world XZ that
## puts it in the same place in the frame. The reference works out at roughly
## 70 m across, which is why the farmstead is as spread out as it is: that is
## the establishing shot's scale, not gameplay's 17 m.
##
## THREE THINGS THIS OWNS THAT THE SCENE FILE CANNOT:
##
## 1. Y. The terrain is procedural noise, so no height can be saved in a .tscn.
##    Everything settles onto the snow at _ready() -- see _settle().
## 2. The wires. They are a 1 m element the scene stretches between two points
##    (see the props report), and both endpoints are other nodes' business.
## 3. The lines in the snow. Rule 11 says the ploughed furrows and the tyre
##    tracks are the only texture the frame has, and section 3 says they are
##    baked into the track mask rather than modelled. They have no node to live
##    on, so they live here, beside the props they belong to.

## The model's ground band. A vertex below this in the prop's own space is a
## vertex that touches snow, and the XZ hull of those vertices is what the prop
## rests on.
##
## This is why there is no per-prop footprint table. A tree's bounding box is
## seven metres across and none of it is on the ground except the trunk, so
## resting a tree on the lowest point under its *crown* drops it into a hole; a
## shed's box is its walls and it really does rest on all four of them. Asking
## the geometry which part is near the ground answers both without a lookup
## table that can go stale the next time a build script changes a model.
@export var ground_band_m := 1.0

## Grid spacing for the footprint sample, in metres. Finer than the 20 m swells
## the noise makes, which is all it has to resolve.
@export var footprint_step := 0.7

## Pushed a little further into the snow than the lowest point strictly needs,
## so things read as bedded in rather than as resting on the surface.
@export var bed_depth := 0.06

## Held rather than settled: the wires are positioned by _string_wires() and
## have no ground contact at all.
@export var wire_root := NodePath("Wires")

## ---------------------------------------------------------------------------
## The fence
## ---------------------------------------------------------------------------
## A fence is the fourth thing this node owns that scenes/main.tscn cannot
## express, and it is the clearest case of the four: a run of fence is a
## *direction and a count*, not a list of places. Written out as transforms it
## would be twenty-two nodes whose only content is an arithmetic series, and
## moving the corner by a metre would mean editing all of them.
##
## The segment is one post at the origin with rails running along its own -Z --
## the axis `look_at()` aims, the same convention the wire uses. It is never
## scaled: scaling would stretch the post along with the rails.
const FENCE_SEGMENT := preload("res://assets/models/props/fence_segment.glb")
const FENCE_SPAN := 2.6

@export var fence_root := NodePath("Fence")

## Where the two runs meet. West and south of the yard, so the fence reads as
## the boundary of the ground the farmstead sits on rather than as a line drawn
## across open country.
const FENCE_CORNER := Vector3(-16.0, 0.0, -8.0)

## [direction, segments, laid backwards]. Both runs leave the frame rather than
## stopping in it, which is the honest way to end a fence: a run that stops in
## open snow needs a reason, and one that goes off the edge of the picture has
## the same reason as the road.
##
## THE `backwards` FLAG IS NOT A FLOURISH. Both runs share the corner, and the
## segment carries its post at its own origin, so laying both forwards would put
## two posts in exactly the same place -- coincident faces, which z-fight on some
## frames and not others. The west run is therefore laid *from the far end back*:
## its post sits one span out and its rails reach back to the corner, which is
## served by the south run's post. One post at the corner, no gap in the rails.
const FENCE_RUNS := [
	# West, along the top of the frame's lower-left quadrant.
	[Vector2(-0.6, -0.8), 9, true],
	# South, down past the well house and off the bottom edge.
	[Vector2(0.351, 0.936), 13, false],
]

## The house is a sibling, not a child -- it has its own placement script -- but
## the service drop has to start on its eave.
@export var farmhouse_path := NodePath("../Farmhouse")

## Where on the house the drop is fixed, in the house's own metres. The main
## block's right wall is at x = +3.89 and its eave at y = 5.00; this sits just
## inside both, on the front half of the wall.
@export var house_wire_anchor := Vector3(3.7, 4.85, 1.2)

## Tie points on the power pole, in pole-local metres, printed by
## tools/blender/build_power_pole.py. Blender Z-up (x, y, z) becomes Godot
## (x, z, -y), so the crossarm's (+-1.00, 0, 8.06) arrives here.
const POLE_CROSSARM_WEST := Vector3(-1.0, 8.06, 0.0)
const POLE_CROSSARM_EAST := Vector3(1.0, 8.06, 0.0)

## ---------------------------------------------------------------------------
## The lines in the snow
## ---------------------------------------------------------------------------
## All in world XZ. Y is ignored -- the mask is a plan view.

## Where the baked window sits. Centred on the furrows and the farmyard
## together rather than on either, because a stroke outside the window draws
## nothing at all and says nothing about it. tests/art/test_farmstead_placement.gd
## checks every line below fits inside it.
const BAKE_CENTRE := Vector3(6.0, 0.0, -22.0)

## The ploughed field, upper left of the reference and the only texture in an
## otherwise flat white field.
##
## The furrows run along world +X because that is what the reference shows: its
## hatching climbs to the right at roughly the angle world +X reads at, and its
## field boundary runs parallel to the hatching, which is what the long edge of
## a ploughed field does.
@export var furrow_origin := Vector3(-26.0, 0.0, -62.0)
@export var furrow_direction := Vector2(1.0, 0.0)
@export var furrow_length := 62.0
@export var furrow_spacing := 0.85
@export var furrow_count := 44
## 0.11 m half-width is 3.7 texels on the baked layer and about 3 px in a frame
## of this width -- the same weight the reference draws them at. Wider reads as
## ridges rather than as a worked field.
##
## The strength went from 0.6 to 0.85 when the terrain's band threshold came
## down (see src/rendering/terrain_renderer.gd). That is not a coincidence and
## it is worth writing down: the shader mixes a track two palette steps down
## from *lit* snow and only one down from *shaded* snow, so the field used to
## read strongest exactly where the ground happened to be dark. Now that the
## whole field is lit, the same 0.6 produced a barely-there grey. Raising the
## per-stroke strength is the local fix; raising `track_tint` would have been
## the global one and would have coarsened every footprint in the game with it.
@export var furrow_radius := 0.11
@export var furrow_strength := 0.85

## ---------------------------------------------------------------------------
## THE STUBBLE, AND WHY IT IS NOT GEOMETRY
## ---------------------------------------------------------------------------
## The brief asked for a snow-covered wheat field -- "stubble poking through
## snow, short broken stalks in rows" -- and said to look at `level.jpg` first
## and say so if the field there reads as lines in snow with no standing stalks.
##
## **It does, and there is therefore no stubble model in this project.** Magnified
## three times, the reference's field is several hundred short dark dashes lying
## in the plane of the snow, running along the furrow direction, in rows. Not one
## of them stands proud: none has a cast shadow, none breaks the horizon of the
## rise it sits on, and none has a lit side and a dark side. They are marks, and
## a mark in the snow is what the track mask is for. It would also be the wrong
## call at any framing -- a 25 cm stalk under this camera is a third of a pixel
## at the establishing shot and under two at gameplay.
##
## What was missing was not geometry but *granularity*: `bake_furrows` draws 44
## continuous passes, and the reference's field is broken. So the field gets a
## second baked pass of short dashes scattered along the same lines, which is
## the same thing the painting does and costs no triangles and no draw call.
##
## Deterministic, from a seeded RNG, because the static layer is baked once and
## a field that reshuffled itself on every load would be a field nobody could
## compose against.
## Measured off the reference at three times magnification: a dash there is
## about 8 px long and 2 wide in a 1000 px frame covering 70 m, which is 0.55 m
## by 0.14. The radius below is half-width, so 0.08 draws them 0.16 m across --
## within a texel of the painting's, and 2.7 texels on the baked layer, which is
## the least that can carry a shape at all.
@export var stubble_rows := 34
@export var stubble_per_row := 34
@export var stubble_length := 0.75
@export var stubble_radius := 0.08
@export var stubble_strength := 0.9
@export var stubble_seed := 41077

## The farm road, running along the near edge of the field and off both sides of
## the frame. The bend near the middle is the junction the spur leaves from.
const ROAD := [
	Vector3(30.0, 0.0, -46.0),
	Vector3(20.0, 0.0, -37.0),
	Vector3(11.0, 0.0, -29.5),
	Vector3(2.7, 0.0, -25.6),
	Vector3(-9.0, 0.0, -28.5),
	Vector3(-24.0, 0.0, -34.0),
]

## Where the spur leaves the road, and the one bend it makes on the way in. Its
## far end is not a constant -- it is wherever the truck actually is, so the
## ruts arrive under the wheels however the truck is moved.
const SPUR_JUNCTION := Vector3(2.7, 0.0, -25.6)
const SPUR_BEND := Vector3(4.6, 0.0, -22.2)

## Half the track width of the truck, so the two ruts land where its wheels are.
@export var rut_gauge := 0.78
@export var rut_radius := 0.13
@export var rut_strength := 0.62
## The swept band between and around the ruts: packed snow, much fainter, and
## what stops a road reading as two isolated pencil lines.
@export var road_bed_radius := 1.25
@export var road_bed_strength := 0.26

## The cleared patch the truck is parked on -- the reference has one, and it is
## the thing that says somebody drives in and out of here rather than that a
## truck was placed in a field. Runs from the end of the spur past the front of
## the house, which is where the traffic goes.
const YARD := [
	Vector3(4.2, 0.0, -20.6),
	Vector3(6.4, 0.0, -16.4),
	Vector3(10.6, 0.0, -12.4),
	Vector3(14.4, 0.0, -9.6),
]
@export var yard_radius := 3.4
@export var yard_strength := 0.26

## Footprint chains that were here before the player was, running away from the
## house to the right of frame and down toward the bottom -- both in the
## reference, both narrative. These go in the *dynamic* layer, not the baked
## one: they are somebody's recent walk, and when the wind arrives they are
## exactly the kind of mark it should take away. The furrows are not.
const TRAIL_TO_THE_EAST := [
	Vector3(16.5, 0.0, -8.5),
	Vector3(24.0, 0.0, 3.0),
	Vector3(30.0, 0.0, 13.0),
	Vector3(37.2, 0.0, 24.9),
]
const TRAIL_TO_THE_WELL := [
	Vector3(13.5, 0.0, -8.0),
	Vector3(8.6, 0.0, -0.4),
	Vector3(4.4, 0.0, 3.2),
	Vector3(-1.0, 0.0, 10.5),
	Vector3(-4.6, 0.0, 17.5),
]

## Matched to PlayerController's own numbers so an old trail and a fresh one are
## the same walk. Weaker, because these have had a night on them.
@export var trail_stride := 0.72
@export var trail_width := 0.19
@export var trail_radius := 0.28
@export var trail_aspect := 1.5
@export var trail_strength := 0.5

var _painter: CelPainter


func _ready() -> void:
	# Before the painter, so the fence is repainted with everything else rather
	# than arriving in the world on the glTF importer's materials.
	_build_fences()
	_painter = CelPainter.new()
	_painter.paint(self)
	_settle_all()
	_string_wires()
	_draw_the_lines()


## ---------------------------------------------------------------------------
## Standing things on the ground
## ---------------------------------------------------------------------------


func _settle_all() -> void:
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry == null:
		return
	var snow := registry.get_service(&"snow_field") as Node
	if snow == null:
		return
	for prop in _settleable():
		_settle(prop, snow)


## Everything that stands on the ground.
##
## Direct children, less the wires (they hang) and less the fence root (it is a
## container, not a prop, and its origin is nowhere in particular) -- plus each
## fence segment individually. A post 30 m along a run has to find its own snow;
## settling the container would drop the whole fence to the lowest ground under
## any part of it and leave most of it in the air.
func _settleable() -> Array[Node3D]:
	var props: Array[Node3D] = []
	var wires := get_node_or_null(wire_root)
	var fence := get_node_or_null(fence_root)
	for child in get_children():
		if child == wires or child == fence or not (child is Node3D):
			continue
		props.append(child as Node3D)
	if fence != null:
		for segment in fence.get_children():
			if segment is Node3D:
				props.append(segment as Node3D)
	return props


## Sit on the lowest snow surface anywhere under the prop's ground band.
##
## The lowest rather than the average, for the reason src/entities/farmhouse.gd
## gives at length: sitting on the average leaves the downhill corner in the
## air, and daylight under one corner of a shed is unmistakable at any distance,
## where a shed with snow banked up one wall is just a shed in a drift.
##
## Sampled through the snow surface rather than the bare ground, because the
## snow is what is drawn and a hollow holds most of a metre of it.
func _settle(node: Node3D, snow: Node) -> void:
	var footprint := _ground_footprint(node)
	if footprint.size == Vector2.ZERO and footprint.position == Vector2.ZERO:
		return
	var lowest := INF
	var here := node.global_position
	var basis := node.global_transform.basis
	var x := footprint.position.x
	while x <= footprint.end.x + 0.0001:
		var z := footprint.position.y
		while z <= footprint.end.y + 0.0001:
			var spot: Vector3 = here + basis * Vector3(x, 0.0, z)
			lowest = minf(lowest, snow.terrain_height_at(spot) + snow.depth_at(spot))
			z += footprint_step
		x += footprint_step
	if lowest == INF:
		return
	node.global_position.y = lowest - bed_depth


## The XZ hull of every vertex within `ground_band_m` of the prop's own origin
## plane, in the prop's own space.
##
## Empty when the prop was not modelled standing on that plane at all. Every
## world model in the wave has its lowest vertex within a few centimetres of its
## own origin -- the pole's buried butt reaches -0.45 and the trees' -0.26 -- so
## a model whose geometry runs a long way *below* its origin is one whose origin
## means something else. The tire swing's does: it is the hang point, and the
## tire is 2.09 m under it (props report, section 5). An empty footprint is what
## tells _settle() to leave such a thing exactly where it was hung.
##
## Today the swing is a child of the tree and _settle_all() only settles its own
## direct children, so this never fires in the shipped scene. It fires the day
## somebody reparents it, which is precisely when nothing else would say a word.
func _ground_footprint(node: Node3D) -> Rect2:
	var bounds := Rect2()
	var found := false
	var deepest := 0.0
	var into_prop := node.global_transform.affine_inverse()
	for instance: MeshInstance3D in _ground_meshes(node, into_prop):
		var mesh: Mesh = instance.mesh
		if mesh == null:
			continue
		var to_prop: Transform3D = into_prop * instance.global_transform
		for vertex in mesh.get_faces():
			var local: Vector3 = to_prop * vertex
			deepest = minf(deepest, local.y)
			if local.y > ground_band_m:
				continue
			var point := Vector2(local.x, local.z)
			if found:
				bounds = bounds.expand(point)
			else:
				bounds = Rect2(point, Vector2.ZERO)
				found = true
	if deepest < -ground_band_m:
		return Rect2()
	return bounds


## Meshes that are part of what the prop stands on.
##
## A child mounted well above the ground -- the tire swing on its branch -- is
## attached to the prop rather than standing beside it, so its geometry must not
## widen the footprint. Without this the swing's tire, which hangs to 0.71 m in
## the tree's own space, drags the tree's footprint two metres sideways and the
## tree settles on the lowest snow under the *swing* instead of under its trunk.
func _ground_meshes(node: Node, into_prop: Transform3D) -> Array:
	var found: Array = []
	if node is MeshInstance3D:
		found.append(node)
	for child in node.get_children():
		if child is Node3D and (into_prop * (child as Node3D).global_position).y > ground_band_m:
			continue
		found.append_array(_ground_meshes(child, into_prop))
	return found


## ---------------------------------------------------------------------------
## The fence
## ---------------------------------------------------------------------------


## Where every fence segment goes, as `{name, at, toward}` in world space.
##
## Pure arithmetic, separated from the node-building below so a test can check
## the layout without instancing twenty-two models -- the same reason
## `SnowField.sample_bilinear` is static. It is the only part of the fence that
## can be wrong in a way a screenshot would not show, because two posts in one
## place look like one post until the day they z-fight.
func fence_layout() -> Array:
	var places: Array = []
	for entry in FENCE_RUNS:
		var direction: Vector2 = (entry[0] as Vector2).normalized()
		var count: int = entry[1]
		var backwards: bool = entry[2]
		var along := Vector3(direction.x, 0.0, direction.y)
		for index in range(count):
			# Backwards: post one span further out, rails reaching back toward
			# the corner. See FENCE_RUNS -- this is what stops the two runs
			# putting a post in the same place.
			var step := float(index + 1) if backwards else float(index)
			var at := FENCE_CORNER + along * (FENCE_SPAN * step)
			places.append({
				"name": "Segment%s%d" % ["W" if backwards else "S", index],
				"at": at,
				"toward": at - along if backwards else at + along,
			})
	return places


## Lays both runs out from the corner. Called before the painter and before
## _settle_all(), so the segments are repainted and dropped onto the snow with
## everything else and nothing here has to know about either.
func _build_fences() -> void:
	var fence := get_node_or_null(fence_root)
	if fence == null:
		return
	for place in fence_layout():
		var segment := FENCE_SEGMENT.instantiate() as Node3D
		if segment == null:
			return
		segment.name = place["name"]
		fence.add_child(segment)
		# Global rather than local, for the same reason _span() is: the
		# constants here are world XZ read off the reference, and look_at()
		# aims in world space whatever the parent's transform happens to be.
		segment.global_position = place["at"]
		segment.look_at(place["toward"], Vector3.UP)


## ---------------------------------------------------------------------------
## The wires
## ---------------------------------------------------------------------------


## Rule 11 calls the line across the frame the detail, so the wires are three
## spans that between them cut a single continuous line from the top right of
## the frame, through the house, down to the pole and off the bottom left.
##
## The asset is one metre of wire running along its own -Z with its origin at
## one end, which is the axis look_at() aims. Stringing one is therefore three
## lines and no trigonometry (props report, section 5), and the endpoints can be
## read off whatever the nodes actually settled at rather than written down.
func _string_wires() -> void:
	var wires := get_node_or_null(wire_root)
	var pole := get_node_or_null("PowerPole") as Node3D
	var house := get_node_or_null(farmhouse_path) as Node3D
	if wires == null or pole == null:
		return

	var west: Vector3 = pole.global_transform * POLE_CROSSARM_WEST
	var east: Vector3 = pole.global_transform * POLE_CROSSARM_EAST
	var eave := west + Vector3(0.0, 1.0, 0.0)
	if house != null:
		eave = house.global_transform * house_wire_anchor

	# Down the screen and to the left, past the bottom edge: the next pole is
	# out of frame and the line simply leaves. Slightly lower at the far end,
	# which is the only sag a straight element can honestly carry.
	var away := west + Vector3(-33.0, -1.2, 11.8)
	# Up the screen and to the right from the house, off the top edge -- the
	# span that arrives at the farm in the first place. The -Z is larger than
	# the reference's line would suggest and that is deliberate: at the shallower
	# angle the span ran straight through TreeA's crown, which at this camera
	# reads as a wire snagged in the branches. Poles get sited to avoid trees.
	var arriving := eave + Vector3(30.0, 2.6, -32.0)

	_span(wires.get_node_or_null("WireArriving"), arriving, eave)
	_span(wires.get_node_or_null("WireDrop"), eave, west)
	_span(wires.get_node_or_null("WireLeaving"), east, away)


func _span(wire: Node3D, from: Vector3, to: Vector3) -> void:
	if wire == null:
		return
	var length := from.distance_to(to)
	if length < 0.01:
		return
	wire.global_position = from
	# look_at() rebuilds the basis orthonormal, so the scale has to go on after
	# it or it is thrown away. Only Z is scaled: the section stays 7 cm however
	# long the span is.
	wire.look_at(to, Vector3.UP)
	wire.scale = Vector3(1.0, 1.0, length)


## ---------------------------------------------------------------------------
## The lines in the snow
## ---------------------------------------------------------------------------


func _draw_the_lines() -> void:
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry == null:
		return
	var tracks := registry.get_service(&"track_mask") as Node
	if tracks == null:
		return

	# The baked window is fixed in the world and is placed once, here, because
	# this node is the only thing that knows where the farmstead is.
	tracks.bake_at(BAKE_CENTRE)

	tracks.bake_furrows(
		furrow_origin, furrow_direction, furrow_length, furrow_spacing, furrow_count,
		furrow_radius, furrow_strength, 0.22
	)
	_bake_stubble(tracks)
	# The yard goes down first so the ruts and the prints composite over it. With
	# max() the order does not change the result, but it is the order the world
	# happened in.
	tracks.bake_path(YARD, yard_radius, yard_strength, 0.15, 0.3, 71.0)
	_bake_wheeled(tracks, ROAD)
	_bake_wheeled(tracks, _spur())

	_stamp_trail(tracks, TRAIL_TO_THE_EAST, 0.0)
	_stamp_trail(tracks, TRAIL_TO_THE_WELL, 17.0)


## Broken stalks in the snow, along the furrows. See the note on the stubble
## constants above for why this is a bake and not a model.
##
## Every stroke lands inside the furrow band by construction -- the rows are
## spread across the same span `bake_furrows` uses -- so nothing here can fall
## outside the baked window that the furrows themselves fit in.
func _bake_stubble(tracks: Node) -> void:
	if stubble_rows <= 0 or stubble_per_row <= 0:
		return
	var along := furrow_direction.normalized()
	var across := Vector2(-along.y, along.x)
	var band := furrow_spacing * float(maxi(furrow_count - 1, 1))
	var rng := RandomNumberGenerator.new()
	rng.seed = stubble_seed
	for row in range(stubble_rows):
		# Offset half a furrow spacing so a dash sits *between* two passes as
		# often as on one. Stubble left standing is what the plough missed.
		var lane := across * (band * (float(row) + 0.5) / float(stubble_rows))
		for index in range(stubble_per_row):
			var travel := furrow_length * (float(index) + rng.randf()) / float(stubble_per_row)
			var wander := across * rng.randf_range(-furrow_spacing * 0.55, furrow_spacing * 0.55)
			var at := furrow_origin \
				+ Vector3(lane.x, 0.0, lane.y) \
				+ Vector3(wander.x, 0.0, wander.y) \
				+ Vector3(along.x, 0.0, along.y) * travel
			var run := stubble_length * rng.randf_range(0.45, 1.0)
			tracks.bake_stroke(
				at, at + Vector3(along.x, 0.0, along.y) * run,
				stubble_radius, stubble_strength * rng.randf_range(0.6, 1.0),
				0.5, 0.5, rng.randf() * 97.0
			)


## The tyre tracks that curve in from the road, ending under the truck wherever
## the truck happens to be parked.
func _spur() -> Array:
	var truck := get_node_or_null("Truck") as Node3D
	if truck == null:
		return []
	var at := truck.global_position
	var arrival := Vector3(at.x, 0.0, at.z)
	# Past the truck by half its length, so the ruts run under it and stop
	# rather than stopping at its middle.
	var last_leg := (arrival - SPUR_BEND).normalized()
	return [SPUR_JUNCTION, SPUR_BEND, arrival + last_leg * 1.4]


## A vehicle track: a broad shallow bed with two ruts in it. The bed is what
## makes it read as a road rather than as two pencil lines, and the ruts are
## what make it read as a *vehicle*.
func _bake_wheeled(tracks: Node, path: Array) -> void:
	if path.size() < 2:
		return
	tracks.bake_path(path, road_bed_radius, road_bed_strength, 0.25, 0.35, 5.0)
	for side in [-1.0, 1.0]:
		var rut: Array = []
		for index in range(path.size()):
			# Offset perpendicular to the local direction of travel, so the pair
			# stays a fixed gauge apart around the bends instead of crossing on
			# the inside of one.
			var ahead: Vector3 = path[mini(index + 1, path.size() - 1)]
			var behind: Vector3 = path[maxi(index - 1, 0)]
			var run := Vector2(ahead.x - behind.x, ahead.z - behind.z)
			if run.length_squared() < 0.0001:
				continue
			var across: Vector2 = run.normalized().orthogonal() * (rut_gauge * side)
			rut.append(path[index] + Vector3(across.x, 0.0, across.y))
		tracks.bake_path(rut, rut_radius, rut_strength, 0.4, 0.3, 40.0 * side)


## A chain of prints along a route, left and right alternating about the centre
## line, at the same stride and the same lateral offset PlayerController walks
## at -- so an old trail and one the player makes are the same walk.
func _stamp_trail(tracks: Node, route: Array, seed_offset: float) -> void:
	if route.size() < 2:
		return
	var side := 1.0
	var step := 0
	for index in range(route.size() - 1):
		var from: Vector3 = route[index]
		var to: Vector3 = route[index + 1]
		var run := to - from
		var length := run.length()
		if length < 0.001:
			continue
		var forward := run / length
		var lateral := Vector3(-forward.z, 0.0, forward.x)
		var travelled := 0.0
		while travelled < length:
			var at := from + forward * travelled + lateral * (side * trail_width)
			tracks.stamp(
				at,
				trail_radius,
				trail_strength,
				Vector2(forward.x, forward.z),
				trail_aspect,
				0.55,
				0.3,
				seed_offset + float(step) * 2.11
			)
			side = -side
			step += 1
			travelled += trail_stride
