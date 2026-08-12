extends SceneTree

## Generator for res://data/montage/*.tres -- UI design document section 4.5.
##
## Run: godot --headless --path <project> --script res://tools/generate_montages.gd
##
## ---------------------------------------------------------------------------
## THE OPENING
## ---------------------------------------------------------------------------
## Three shots pushing in on the farmhouse, which stands at (13, 0, -12) in
## scenes/main.tscn. Each carries one line, standing in the world ahead of the
## camera so that the approach foreshortens it -- see Inscription.
##
## The lines are three sentences and no more. GDD section 2's third pillar is
## 沉默即叙事 and its non-goals rule out an exposition dump; what an opening owes
## the player is the SHAPE of the week, which is: it is snowing, someone is
## coming, and they have to be able to see you. The last of those is also the
## setup for the ending the whole game lands on -- 直升机从头顶飞过，没有看见你.
##
## ---------------------------------------------------------------------------
## THESE CAMERAS ARE A FIRST PASS
## ---------------------------------------------------------------------------
## The positions below are composed against the farmhouse's known transform and
## are meant to be tuned by eye, which is what a generator is for: change a
## number, re-run, look. What is NOT free to drift is the fit -- every line has
## to finish before its shot cuts, and tests/unit/test_montage_data.gd asserts it.

const OUT_DIR := "res://data/montage"
const FARMHOUSE := Vector3(13.0, 0.0, -12.0)

func _initialize() -> void:
	var ShotScript := load("res://src/definitions/montage_shot.gd")
	var MontageScript := load("res://src/definitions/montage.gd")

	var shots: Array[MontageShot] = []

	# 1. The valley, from high and far. A slow drift in; nothing is happening yet.
	shots.append(_shot(ShotScript,
		7.5,
		FARMHOUSE + Vector3(34.0, 22.0, 40.0), FARMHOUSE + Vector3(28.0, 18.0, 33.0),
		46.0, 44.0,
		"雪已经下了七天。",
		FARMHOUSE + Vector3(12.0, 9.0, 18.0), -38.0))

	# 2. Closer, lower. The farmstead resolves out of the snow.
	shots.append(_shot(ShotScript,
		7.5,
		FARMHOUSE + Vector3(16.0, 8.0, 20.0), FARMHOUSE + Vector3(10.0, 5.0, 13.0),
		42.0, 40.0,
		"他们说会有直升机。",
		FARMHOUSE + Vector3(5.0, 3.4, 8.0), -34.0))

	# 3. In on the one warm window. The line that sets up the ending.
	shots.append(_shot(ShotScript,
		8.0,
		FARMHOUSE + Vector3(6.5, 3.0, 9.0), FARMHOUSE + Vector3(3.2, 2.1, 4.6),
		38.0, 34.0,
		"他们要看得见你。",
		FARMHOUSE + Vector3(1.6, 2.0, 3.4), -30.0))

	var opening = MontageScript.new()
	opening.id = &"opening"
	opening.shots = shots

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := OUT_DIR.path_join("opening.tres")
	var error := ResourceSaver.save(opening, path)
	print("generate_montages: save returned %d, %d shots, %.1f s"
		% [error, opening.shot_count(), opening.total_seconds()])
	quit(0 if error == OK else 1)


## One shot. The camera looks at the farmhouse from wherever it is, and the line
## stands facing back down the camera's approach.
func _shot(ShotScript, duration: float, from: Vector3, to: Vector3,
		fov_from: float, fov_to: float, text: String,
		text_at: Vector3, text_yaw_degrees: float) -> MontageShot:
	var shot = ShotScript.new()
	shot.duration = duration
	# looking_at keeps the origin and turns -Z toward the target, which is the
	# direction a Camera3D actually looks.
	shot.camera_from = Transform3D(Basis.IDENTITY, from).looking_at(FARMHOUSE + Vector3(0.0, 2.0, 0.0), Vector3.UP)
	shot.camera_to = Transform3D(Basis.IDENTITY, to).looking_at(FARMHOUSE + Vector3(0.0, 2.0, 0.0), Vector3.UP)
	shot.fov_from = fov_from
	shot.fov_to = fov_to
	shot.camera_ease = 0.35
	shot.text = text
	# Yawed rather than aimed at the camera: a line square to the lens has no
	# perspective to lose as the camera comes on, and the whole effect is that it
	# has some. Standing at an angle, the far end of the line foreshortens first.
	shot.text_transform = Transform3D(
		Basis(Vector3.UP, deg_to_rad(text_yaw_degrees)), text_at)
	shot.text_start = 0.6
	shot.wind = Vector2(1.0, -0.25)
	shot.scatter_metres = 1.4
	shot.scatter_spin = 0.9
	shot.lighting_preset = &"nightfall"
	return shot
