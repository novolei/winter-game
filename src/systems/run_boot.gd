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
## begin_run() is the whole of it, and it is idempotent PER HALF: it refuses a
## model that is already running rather than restarting it, and it decides that
## separately for the body and for the clock. So GameState takes over in either
## order, all at once or one half at a time, and none of it is a rework:
##
##   1. GameState calls SurvivalSystem.start() and/or WorldClock.start() from
##      its own "run begins" transition, and sets RunBoot.auto_start = false (or
##      simply lands first -- an autoload declared before this one is ready
##      first, and begin_run() will then decline whichever half it finds already
##      going).
##   2. The RunBoot line comes out of project.godot and this file is deleted.
##
## Nothing else in the project refers to RunBoot, deliberately, so step 2 is a
## deletion and not a refactor. If you find yourself adding a second job here,
## that is GameState arriving and it wants its own file.
##
## THE JOB IS STILL ONE JOB. "The run begins" is one event with two subjects: a
## body that starts losing heat and a calendar that starts counting days, and
## starting one without the other is a game where a man freezes on a day that
## never ends. What does NOT live here is anything that happens *during* the run
## -- GDD section 3's nightfall doubling is its own file, src/systems/
## night_exposure.gd, hanging off the clock's events rather than off this.
##
## WHY THE CLOCK WAS LEFT ALONE BEFORE, and what changed. Starting a clock with
## no schedules loaded finishes the run on the first frame and fires
## clock.run_finished, which MusicDirector plays as an ending. So it needed both
## a loader that reads res://data/schedule and a WorldClock.start() that refuses
## an empty clock outright. Both exist now, and the order below is the one that
## matters: load first, start second.

## Off, and this file does nothing at all. The switch GameState flips if it
## arrives before the autoload line comes out.
@export var auto_start := true

var _survival = null
var _clock = null

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

func set_world_clock(clock) -> void:
	_clock = clock

## Starts the run: the body losing heat, and the calendar counting days. Returns
## whether it actually started anything.
##
## The "already running" guard is not politeness, on either half.
## SurvivalSystem.start() resets every stat to its initial value, so calling it a
## second time is a full heal -- in a survival game, from a line nobody would
## look at twice. WorldClock.start() returns the run to day 1, so calling it a
## second time on day 6 throws the whole game away.
##
## The two halves are decided independently, so GameState can take over one of
## them without the other silently stopping.
func begin_run() -> bool:
	_resolve()
	var started := false
	if _survival != null and not _survival.is_running():
		_survival.start()
		started = true
	if _clock != null and not _clock.is_running() and not _clock.is_finished():
		# LOAD BEFORE START, and the order is the whole of why this call did not
		# exist until now -- see the header. start() refuses an empty clock, so
		# getting this backwards is now a run that does not begin rather than a
		# run that ends on frame one, but it is still wrong.
		if _clock.schedule_count() == 0:
			_clock.load_schedules_from_directory()
		started = _clock.start() or started
	return started

## get_node_or_null, NOT Engine.get_singleton: a project [autoload] entry is a
## node under /root and never enters the engine's singleton registry (briefing
## trap 3). Written the plausible-looking way this file would start nothing, for
## ever, with no diagnostic anywhere. Guarded on is_inside_tree() because an
## absolute path cannot be resolved from a node that is not in a tree.
func _resolve() -> void:
	if not is_inside_tree():
		return
	if _survival == null:
		_survival = get_node_or_null("/root/SurvivalSystem")
	if _clock == null:
		_clock = get_node_or_null("/root/WorldClock")
