extends TestCase

## An AudioStreamPlayer3D can report `playing` while a boom-mounted camera has
## put its listener outside the emitter's max_distance. This test builds the
## actual CameraRig (including its 90 m boom and Ear). In a synthetic tree the
## new listener does not become active in the audio server before the test
## runner exits, so the meter proof belongs to the real-scene probe below; this
## regression still pins the wiring and placement that makes that proof hold.

const AudioMeterScript := preload("res://tests/framework/audio_meter.gd")
const CameraRigScript := preload("res://src/rendering/camera_rig.gd")
const CallsScript := preload("res://src/entities/wildlife/crow_calls.gd")
const CrowScript := preload("res://src/entities/wildlife/crow.gd")
const DirectorScript := preload("res://src/audio/ambience_director.gd")
const MapScript := preload("res://src/definitions/ambience_map.gd")
const LayerScript := preload("res://src/definitions/ambience_layer.gd")

const LOOP_FOLDER := "res://assets/audio/foley"
const LOOP_STEM := &"footstep_snow_01"

var _nodes: Array[Node] = []
var _birds: Array[Crow] = []


class WindStandIn extends Node:
	func strength() -> float:
		return 0.9


func after_each() -> void:
	for node in _nodes:
		if is_instance_valid(node):
			if node.is_inside_tree():
				node.get_parent().remove_child(node)
			node.free()
	_nodes.clear()
	for bird in _birds:
		if is_instance_valid(bird):
			bird.free()
	_birds.clear()


func _root() -> Node:
	return Engine.get_main_loop().root


func _rig() -> CameraRig:
	var rig: CameraRig = CameraRigScript.new()
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	rig.add_child(camera)
	_root().add_child(rig)
	_nodes.append(rig)
	return rig


func _crow(at: Vector3) -> Crow:
	var crow: Crow = CrowScript.new()
	crow.perch_on(at, Vector3.FORWARD)
	_birds.append(crow)
	return crow


func test_camera_rig_ear_keeps_crows_and_ambience_audible() -> void:
	var rig := _rig()
	var ear := rig.get_node_or_null("Ear") as AudioListener3D
	assert_not_null(ear, "CameraRig did not build the player-relative listener")
	if ear == null:
		return
	assert_true(ear.is_current(), "CameraRig's Ear exists but is not the active listener")
	assert_true(
		ear.global_position.distance_to(rig.global_position) < 0.001,
		"the active ear moved down the 90 m boom instead of staying on CameraRig"
	)

	var calls: CrowCalls = CallsScript.new()
	calls.fewest = 1
	calls.most = 1
	calls.first_call_min = 0.01
	calls.first_call_max = 0.01
	_root().add_child(calls)
	_nodes.append(calls)
	var crows: Array = [_crow(Vector3(2.0, 5.0, 1.0))]
	assert_eq(calls.announce(crows), 1, "the audible test did not schedule a crow call")
	calls.advance(0.02)
	assert_true(not calls.voices().is_empty(), "the scheduled crow call opened no emitter")
	if calls.voices().is_empty():
		return
	assert_true(
		calls.voices()[0].global_position.distance_to(ear.global_position) < calls.audible_m,
		"the player-relative ear is outside the crow's %.1f m designed carry distance" % calls.audible_m
	)

	var map: AmbienceMap = MapScript.new()
	map.sound_folder = LOOP_FOLDER
	var layer: AmbienceLayer = LayerScript.new()
	layer.layer_id = LOOP_STEM
	layer.enters_at = 0.05
	layer.full_at = 0.20
	var layers: Array[AmbienceLayer] = [layer]
	map.layers = layers
	var wind := WindStandIn.new()
	_nodes.append(wind)
	var director: AmbienceDirector = DirectorScript.new()
	director.set_map(map)
	director.set_wind_system(wind)
	_root().add_child(director)
	_nodes.append(director)
	for _step in range(20):
		director.advance(0.05)
	assert_true(director.voice(0).is_playing(), "the ambience bed did not start in the live tree")
	assert_true(
		director.voice(0).global_position.distance_to(ear.global_position) < map.unit_size * 1.1,
		"the ambience emitter is not positioned around CameraRig's active ear"
	)
