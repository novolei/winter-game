extends Node

## Autoload "RunBoot". TEMPORARY, and it should be deleted rather than grown.
##
## SurvivalSystem does not tick until something calls start() -- deliberately, so
## that a menu or a cutscene is not a man freezing to death -- and in the running
## game nothing did. The model shipped complete, tested, registered as an
## autoload, and inert: every stat read as full for ever, because the clock had
## never been started. That is invisible in the suite (every test starts its own
## model) and invisible on screen (there is no HUD), which is the only reason it
## survived a whole wave.
##
## Owning the run belongs to src/systems/game_state.gd -- the System Map has it
## in a later batch, alongside the day loop, the endings and the restart. This
## file is the smallest honest thing that can stand in until then. It starts the
## run where the game actually begins: at boot, because scenes/main.tscn IS the
## game today and there is no menu in front of it.
##
## ---------------------------------------------------------------------------
## THE SEAM, for whoever writes GameState
## ---------------------------------------------------------------------------
## begin_run() is the whole of it, and it is idempotent: it refuses a model that
## is already running rather than restarting it. So GameState takes over in
## either order and neither is a rework:
##
##   1. GameState calls SurvivalSystem.start() from its own "run begins"
##      transition, and sets RunBoot.auto_start = false (or simply lands first --
##      an autoload declared before this one is ready first, and begin_run()
##      will then decline).
##   2. The RunBoot line comes out of project.godot and this file is deleted.
##
## Nothing else in the project refers to RunBoot, deliberately, so step 2 is a
## deletion and not a refactor. If you find yourself adding a second job here,
## that is GameState arriving and it wants its own file.
##
## WHAT THIS DELIBERATELY DOES NOT START. WorldClock is in exactly the same
## position -- nothing calls its start() either -- but it also has no schedules
## loaded, and starting a clock with an empty schedule finishes the run on the
## first frame and fires clock.run_finished, which the music director hears as an
## ending. Starting it properly means load_schedules(res://data/schedule) and a
## decision about the GDD section 3 nightfall doubling that core temperature is
## tuned around. Both belong to whoever owns the day loop, which is GameState.

## Off, and this file does nothing at all. The switch GameState flips if it
## arrives before the autoload line comes out.
@export var auto_start := true

var _survival = null

## Armed here, fired on the first frame -- NOT done here.
##
## Autoloads are added to /root in the order project.godot lists them, and each
## one's _ready() runs as it is added, so an autoload declared BELOW this line
## does not exist yet when this line runs. Starting from _ready() would therefore
## make this file care where its own entry sits in a list nobody thinks about,
## and getting it wrong would leave the survival model inert with no diagnostic:
## the exact failure this file exists to fix, reintroduced by its own fix. By the
## first frame every autoload is present and every _ready() has run.
func _ready() -> void:
	set_process(auto_start)

func _process(_delta: float) -> void:
	# Disarmed first: this has one job and must not go on polling for the rest of
	# the run, nor try again after GameState or a death has stopped the model.
	set_process(false)
	begin_run()

func set_survival_system(system) -> void:
	_survival = system

## Starts the survival model, unless there is nothing to start or it is already
## running. Returns whether it actually started anything.
##
## The "already running" guard is not politeness. SurvivalSystem.start() resets
## every stat to its initial value, so calling it a second time is a full heal --
## in a survival game, from a line nobody would look at twice.
func begin_run() -> bool:
	_resolve()
	if _survival == null or _survival.is_running():
		return false
	_survival.start()
	return true

## get_node_or_null, NOT Engine.get_singleton: a project [autoload] entry is a
## node under /root and never enters the engine's singleton registry (briefing
## trap 3). Written the plausible-looking way this file would start nothing, for
## ever, with no diagnostic anywhere. Guarded on is_inside_tree() because an
## absolute path cannot be resolved from a node that is not in a tree.
func _resolve() -> void:
	if _survival == null and is_inside_tree():
		_survival = get_node_or_null("/root/SurvivalSystem")
