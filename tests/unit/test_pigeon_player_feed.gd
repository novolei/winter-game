extends TestCase

## Feeding temporarily owns the wanderer's upper-body picture without becoming
## another locomotion state.  A one-shot sits after the normal motion graph,
## while the controller keeps the last facing when it stops moving and locks the
## body only for the gesture's authored second.

const PlayerScript := preload("res://src/entities/player/player_controller.gd")

var _player: PlayerController = null


func before_each() -> void:
	_player = PlayerScript.new()


func after_each() -> void:
	if _player != null:
		_player.free()
		_player = null


func test_the_feed_clip_is_a_non_looping_one_shot_after_locomotion() -> void:
	var graph := PlayerScript.build_blend_tree()
	assert_true(graph.has_node("feed_clip"), "the baked feeding gesture is not in the player graph")
	assert_true(graph.has_node("feed_action"), "feeding has no one-shot gate and would replace locomotion permanently")
	if not graph.has_node("feed_clip") or not graph.has_node("feed_action"):
		return
	var clip := graph.get_node("feed_clip") as AnimationNodeAnimation
	var action := graph.get_node("feed_action") as AnimationNodeOneShot
	assert_not_null(clip, "feed_clip is not an animation node")
	assert_not_null(action, "feed_action is not an AnimationNodeOneShot")
	if clip != null:
		assert_eq(clip.animation, WandererAnimations.FEED, "the one-shot plays a different gesture")
	if action != null:
		assert_true(action.fadein_time >= 0.10 and action.fadein_time <= 0.20, "feeding cuts into the body instead of blending briefly")
		assert_true(action.fadeout_time >= 0.10 and action.fadeout_time <= 0.20, "feeding cuts back to locomotion")


func test_feeding_turns_toward_the_pigeon_and_locks_only_for_the_gesture() -> void:
	var required: Array[StringName] = [
		&"interaction_forward", &"begin_feed_interaction", &"advance_feed_interaction", &"is_feeding",
	]
	for method in required:
		assert_true(_player.has_method(method), "PlayerController exposes no %s contract" % method)
	for method in required:
		if not _player.has_method(method):
			return
	_player.position = Vector3(2.0, 0.0, -1.0)
	_player.velocity = Vector3(4.6, 0.0, -1.2)
	var pigeon := Vector3(4.0, 0.0, 2.0)
	_player.call(&"begin_feed_interaction", pigeon, 1.0)
	assert_true(bool(_player.call(&"is_feeding")), "the completed hold did not start the player gesture")
	assert_almost_eq(
		Vector2(_player.velocity.x, _player.velocity.z).length(), 0.0, 0.0001,
		"run momentum slides the player away from the fixed breadcrumb throw"
	)
	var facing: Vector3 = _player.call(&"interaction_forward")
	var expected := Vector3(pigeon.x - _player.position.x, 0.0, pigeon.z - _player.position.z).normalized()
	assert_true(facing.dot(expected) > 0.999, "the player scatters crumbs away from the pigeon")
	assert_true(bool(_player.call(&"advance_feed_interaction", 0.99)), "the movement lock ended before the gesture")
	assert_false(bool(_player.call(&"advance_feed_interaction", 0.02)), "feeding permanently owns movement after the one-shot")
