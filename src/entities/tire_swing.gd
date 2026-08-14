extends Node3D

## The visible swing is still driven by WindPendulum. This small relay only
## turns a physical player contact into an impulse for that same integrator, so
## a nudge and a gust share one believable ring-down rather than competing
## animation systems.

@export var pendulum_driver_group: StringName = &"wind_swing_driver"
@export var impact_gain := 0.85
@export var minimum_impact_speed := 0.05
@export var impact_cooldown_seconds := 0.16

var _next_impact_at := 0.0
var _impact_sensor: Area3D = null


func _ready() -> void:
	_build_impact_sensor()


## Jolt's slide report remains the first route, but the physical sphere also
## lends its exact shape to a non-blocking Area. A slow body entering that Area
## is still an impact even when deep snow leaves no useful slide velocity.
func _build_impact_sensor() -> void:
	if _impact_sensor != null:
		return
	var source := _first_collision_shape(self)
	if source == null or source.shape == null:
		return
	var source_body := source.get_parent() as CollisionObject3D
	var sensor := Area3D.new()
	sensor.name = "ImpactSensor"
	sensor.collision_layer = 0
	sensor.collision_mask = source_body.collision_layer if source_body != null else 1
	sensor.monitorable = false
	add_child(sensor)
	var shape := CollisionShape3D.new()
	shape.name = "TireContact"
	shape.shape = source.shape.duplicate()
	if shape.shape is SphereShape3D:
		# Enter just before the solid tire resolves a head-on CharacterBody
		# velocity. The physical sphere is unchanged; only this harmless sensor
		# receives twelve centimetres or so of anticipation around it.
		(shape.shape as SphereShape3D).radius *= 1.20
	shape.transform = global_transform.affine_inverse() * source.global_transform
	sensor.add_child(shape)
	sensor.body_entered.connect(_on_impact_body_entered)
	_impact_sensor = sensor


func _first_collision_shape(root: Node) -> CollisionShape3D:
	for child in root.get_children():
		if child is CollisionShape3D:
			return child as CollisionShape3D
		var found := _first_collision_shape(child)
		if found != null:
			return found
	return null


func _on_impact_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D:
		receive_player_impact((body as CharacterBody3D).velocity)
	elif body is RigidBody3D:
		receive_player_impact((body as RigidBody3D).linear_velocity)


func impact_sensor() -> Area3D:
	return _impact_sensor


## Called by any moving body that meets this prop's compact tire collider.
## The caller is intentionally generic: other hanging props can opt in by
## exposing the same seam without PlayerController knowing their game noun.
func receive_player_impact(world_velocity: Vector3) -> void:
	var horizontal := Vector3(world_velocity.x, 0.0, world_velocity.z)
	if horizontal.length() < minimum_impact_speed:
		return
	var now := Time.get_ticks_msec() * 0.001
	if now < _next_impact_at:
		return
	_next_impact_at = now + impact_cooldown_seconds
	for driver in get_tree().get_nodes_in_group(pendulum_driver_group):
		if driver.has_method(&"apply_impulse"):
			driver.call(&"apply_impulse", self, horizontal * impact_gain)
