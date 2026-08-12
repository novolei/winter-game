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

## How much of the frame's width a line should cover.
##
## Dropped from 0.44 with the weight increase, and the two go together: a heavy
## face at 0.44 is a title card with a photograph behind it, while a light face
## at 0.32 disappears into the snow. Small and heavy is the pairing that reads as
## something standing in the valley rather than something laid over it.
const LINE_FRACTION := 0.32

## The frame the sizes are solved against. 16:9; a wider window reveals more
## valley either side rather than enlarging the line (System Map section 8).
const ASPECT := 16.0 / 9.0

## Font pixels per glyph before world scaling. Only the RATIO to pixel_size
## matters for size on screen, so this stays fixed and the scale is solved --
## large enough that the glyph texture is not the limit at the closest shot.
const FONT_SIZE := 96

var _grade: MontageGrade = null

func _initialize() -> void:
	var ShotScript := load("res://src/definitions/montage_shot.gd")
	var MontageScript := load("res://src/definitions/montage.gd")
	_grade = _build_grade()
	if _grade == null:
		printerr("generate_montages: no palette, so no grade")
		quit(1)
		return

	var shots: Array[MontageShot] = []

	# 1. The valley, from high and far. A slow drift in; nothing has happened yet.
	shots.append(_shot(ShotScript,
		7.5,
		FARMHOUSE + Vector3(34.0, 22.0, 40.0), FARMHOUSE + Vector3(28.0, 18.0, 33.0),
		46.0, 44.0,
		"雪已经下了七天。", 15.0, 0.4, -26.0))

	# 2. Closer, lower. The farmstead resolves out of the snow.
	shots.append(_shot(ShotScript,
		7.5,
		FARMHOUSE + Vector3(19.0, 9.0, 23.0), FARMHOUSE + Vector3(14.0, 6.5, 17.0),
		42.0, 40.0,
		"他们说会有直升机。", 10.0, 0.1, -22.0))

	# 3. In on the one warm window -- and STOPPING SHORT OF THE PORCH. The first
	# pass ran the camera to 5.6 m and put the line at 3.4 m, which is inside the
	# porch: the glyphs intersected the posts and the roof, and depth testing did
	# exactly what section 5.9 asks of it, hiding everything embedded in the
	# geometry. What reached the frame was the few millimetres of each letter
	# still sticking out, which reads as dark glyphs with a warm rim.
	shots.append(_shot(ShotScript,
		8.0,
		FARMHOUSE + Vector3(11.0, 5.0, 15.0), FARMHOUSE + Vector3(8.0, 3.8, 11.0),
		38.0, 34.0,
		"他们要看得见你。", 7.0, 0.0, -18.0))

	var opening = MontageScript.new()
	opening.id = &"opening"
	opening.shots = shots

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := OUT_DIR.path_join("opening.tres")
	var error := ResourceSaver.save(opening, path)
	print("generate_montages: save returned %d, %d shots, %.1f s"
		% [error, opening.shot_count(), opening.total_seconds()])
	quit(0 if error == OK else 1)


## One shot.
##
## THE LINE IS PLACED FROM THE CAMERA, NOT FROM THE FARMHOUSE, and the first pass
## did it the other way round. Positioning narration against the SUBJECT means
## its distance from the lens -- which decides both whether it is legible and
## whether it is buried in scenery -- is a thing you get by accident. Two of the
## three shots came out wrong that way: one line 34 m from the lens and seven
## pixels tall, one embedded in the porch.
##
## Given `metres_ahead` along the camera's own view axis, all three follow:
## the line stands in open air between the lens and the subject, it faces back
## down the approach, and its size can be SOLVED rather than guessed.
func _shot(ShotScript, duration: float, from: Vector3, to: Vector3,
		fov_from: float, fov_to: float, text: String,
		metres_ahead: float, rise: float, text_yaw_degrees: float) -> MontageShot:
	# `rise` is metres above the camera's own view axis, and it is deliberately
	# small. The wind carries a line up and to the right as it takes it, so a line
	# composed high in the frame finishes leaving it before it has finished coming
	# apart -- the dissolve is the point, and it has to be watchable.
	var subject := FARMHOUSE + Vector3(0.0, 2.0, 0.0)
	var shot = ShotScript.new()
	shot.duration = duration
	# looking_at keeps the origin and turns -Z toward the target, which is the
	# direction a Camera3D actually looks.
	shot.camera_from = Transform3D(Basis.IDENTITY, from).looking_at(subject, Vector3.UP)
	shot.camera_to = Transform3D(Basis.IDENTITY, to).looking_at(subject, Vector3.UP)
	shot.fov_from = fov_from
	shot.fov_to = fov_to
	shot.camera_ease = 0.35
	shot.text = text

	var view := (subject - from).normalized()
	var at := from + view * metres_ahead + Vector3.UP * rise

	# Facing back down the approach, then YAWED off it. A line square to the lens
	# has no perspective left to lose as the camera comes on, and having some is
	# the whole of section 5.9 -- obliqued, the far end foreshortens first.
	var away := at - Vector3(from.x - at.x, 0.0, from.z - at.z)
	var facing := Transform3D(Basis.IDENTITY, at).looking_at(away, Vector3.UP)
	shot.text_transform = Transform3D(
		facing.basis.rotated(Vector3.UP, deg_to_rad(text_yaw_degrees)), at)

	shot.text_font_size = FONT_SIZE
	shot.text_pixel_size = _pixel_size_for(text, metres_ahead, fov_from)
	shot.text_start = 0.6
	shot.wind = Vector2(1.0, -0.25)
	shot.scatter_metres = maxf(metres_ahead * 0.16, 0.9)
	shot.scatter_spin = 0.9
	shot.lighting_preset = &"nightfall"
	shot.grade = _grade
	shot.text_weight_latin = 500
	shot.text_weight_cjk = 600
	return shot


## The look, with both of its colours READ OUT OF THE PALETTE rather than
## written here (briefing constraint 6). A vignette to black and a fog tinted by
## eye would each put a thirteenth colour in the frame -- at the edges of every
## montage, and across its whole distance.
func _build_grade() -> MontageGrade:
	var bible = load("res://data/palette/color_bible.tres")
	if bible == null or bible.snow_tones.size() < 5 or bible.structure_tones.size() < 4:
		return null
	var grade := MontageGrade.new()
	# Fog in the second snow tone: the air is made of the same stuff the ground
	# is, one step down so the distance recedes rather than glows.
	grade.fog_colour = bible.snow_tones[1]
	# Vignette toward the darkest structure tone -- the same value section 2.1
	# gives scrim/veil, so the montage darkens toward what the interface darkens
	# toward.
	grade.vignette_colour = bible.structure_tones[3]
	return grade


## Solves the world scale so the line covers `LINE_FRACTION` of the frame width
## at the distance it actually stands, rather than carrying a constant that is
## only right for whichever shot it was tuned against.
func _pixel_size_for(text: String, distance: float, fov_degrees: float) -> float:
	var frame_height := 2.0 * distance * tan(deg_to_rad(fov_degrees) * 0.5)
	var frame_width := frame_height * ASPECT
	# Full-width CJK advances one em per character, so the line is about
	# `length * font_size` pixels wide before scaling. Latin would measure
	# narrower and simply read a little smaller, which is the safe direction.
	var ems := maxf(float(text.length()), 1.0)
	return (frame_width * LINE_FRACTION) / (ems * float(FONT_SIZE))
