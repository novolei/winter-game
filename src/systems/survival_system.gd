extends Node

## Autoload "SurvivalSystem". GDD section 5 -- the five interlocking survival
## stats, and the model every other system reads the player's body through.
##
## It owns no rules of its own. Every stat, every rate, and every interlock
## lives in res://data/stats/*.tres; this file is the machine that ticks them.
## Adding a sixth stat, or a new interlock between two existing ones, is a new
## .tres and nothing else (briefing constraint 4). If you ever find yourself
## about to write `if hunger < 0.3: temperature_decay *= 1.5` here, that line
## belongs in a ThresholdEffect instead.
##
## ---------------------------------------------------------------------------
## POLARITY -- read this before touching anything that consumes a value
## ---------------------------------------------------------------------------
## EVERY stat is a RESERVE. max_value is healthy, min_value is the worst it
## gets, and it falls. That holds for the two whose names read the other way
## round:
##
##   core_temperature 1 = warm      0 = dead
##   hunger           1 = fed       0 = starving
##   thirst           1 = watered   0 = parched
##   fatigue          1 = rested    0 = exhausted, cannot run
##   frostbite_hands  1 = healthy   0 = the limb is lost
##
## GDD section 5's own table is written this way -- "疲劳 ... 归零后果: 无法奔跑",
## fatigue at zero means cannot run -- and one direction for all of them is what
## lets a readout say "low is bad" without knowing which stat it is holding.
##
## Consumers that want the opposite sense invert it themselves. BreathFog's
## set_chill() is 0 warm .. 1 freezing, so its caller passes
## 1.0 - fraction_of(&"core_temperature").
##
## ---------------------------------------------------------------------------
## CHANNELS -- what a modifier is allowed to point at
## ---------------------------------------------------------------------------
## A target is "<name>:<channel>", and a bare "<name>" means "<name>:drain".
## Every distinct target owns one ModifierStack. Three kinds exist:
##
##   core_temperature:drain     how fast the reserve falls. The default.
##   fatigue:recovery           how fast something puts it back. Zero until a
##                              fire, a meal or sleep pushes onto it.
##   locomotion:speed           a BEHAVIOUR channel -- not a stat at all. Read
##                              by whoever owns the behaviour, via
##                              channel_value(), and modified from data here.
##
## Drain and recovery are separate stacks on purpose, and it is the least
## obvious decision in this file. ModifierStack evaluates
## (base + sum ADD) * product MULTIPLY. With ONE stack per stat a fire would be
## an ADD of a negative number, and "you tire faster when dehydrated" -- a
## MULTIPLY above 1 -- would then scale a NEGATIVE total and recover you FASTER.
## The wrong sign, silently, in the direction that helps the player. Two stacks
## make that shape unrepresentable: GDD section 5's "口渴低 → 疲劳恢复变慢" is a
## MULTIPLY of 0.5 on fatigue:recovery and cannot touch the drain.
##
## Behaviour channels are what keep the localised half of GDD section 5 out of
## GDScript: "frostbitten hands make lighting a fire slower and aim worse" is
## two rows in frostbite_hands.tres pointing at ignition:speed and
## aim:steadiness, not two branches in whatever code owns fire and aiming.
##
## ---------------------------------------------------------------------------
## ORDER OF A TICK
## ---------------------------------------------------------------------------
## advance() sub-steps at MAX_STEP so that one long frame, or a test calling
## advance(600.0), integrates the same curve a stream of small frames would.
## Each sub-step, in order:
##
##   1. every stack ticks, expiring timed modifiers
##   2. threshold groups are re-evaluated; ones that changed state add or
##      remove their modifiers BY SOURCE and announce the crossing
##   3. every stat integrates: value += (recovery - drain) * dt, clamped
##   4. floors reached and floors left are announced; a lethal floor ends it
##
## Step 2 adds and removes by source rather than accumulating, which is the
## whole reason ModifierStack.remove_by_source() exists. An implementation that
## re-added while the condition held would compound 1.5x per frame and look
## fine on screen for about four seconds.

const EVENT_THRESHOLD_CROSSED := &"survival.threshold_crossed"
const EVENT_STAT_DEPLETED := &"survival.stat_depleted"
const EVENT_STAT_RECOVERED := &"survival.stat_recovered"
const EVENT_DIED := &"survival.died"

const DEFAULT_STATS_DIRECTORY := "res://data/stats"

const CHANNEL_SEPARATOR := ":"
const CHANNEL_DRAIN := "drain"
const CHANNEL_RECOVERY := "recovery"

## Longest slice advance() will integrate in one go. Rates change when a
## threshold is crossed, so a single huge step would miss the crossing and
## under-drain by however long the run was. 0.25 s is four times finer than the
## coarsest thing that matters (a crossing) and cheap enough that fast-forwarding
## a whole seven-day run is a fraction of a second.
const MAX_STEP := 0.25

var _order: Array[StringName] = []
var _definitions: Dictionary = {}
var _values: Dictionary = {}
var _stacks: Dictionary = {}
var _depleted: Dictionary = {}

## One entry per (watched stat, comparison, threshold), each holding every
## effect authored at that point. Grouped so that four effects hanging off
## "hands below 0.5" are one crossing event rather than four.
var _groups: Array = []

var _running := false
var _dead := false
var _bus = null

# --- wiring ----------------------------------------------------------------

func _ready() -> void:
	# get_node_or_null, NOT Engine.get_singleton: a project [autoload] entry is
	# a node under /root and never enters the engine's singleton registry
	# (briefing trap 3). Getting this wrong leaves _bus null forever and every
	# event is swallowed by _emit()'s null guard with no diagnostic.
	if _bus == null:
		set_event_bus(get_node_or_null("/root/EventBus"))
	if _order.is_empty():
		load_from_directory()

func _process(delta: float) -> void:
	advance(delta)

func set_event_bus(bus) -> void:
	_bus = bus

# --- loading ---------------------------------------------------------------

## Loads every StatDefinition in a directory, in filename order so a run is
## reproducible. Returns how many were accepted.
func load_from_directory(directory_path := DEFAULT_STATS_DIRECTORY) -> int:
	var definitions: Array = []
	var dir := DirAccess.open(directory_path)
	if dir == null:
		return 0
	var file_names := dir.get_files()
	file_names.sort()
	for entry in file_names:
		var file_name := entry
		# An exported build serves data/*.tres as *.tres.remap.
		if file_name.ends_with(".remap"):
			file_name = file_name.trim_suffix(".remap")
		if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			continue
		var resource := ResourceLoader.load(directory_path.path_join(file_name))
		if resource is StatDefinition:
			definitions.append(resource)
	load_definitions(definitions)
	return _order.size()

## Replaces the whole model. Definitions without an id, and duplicates of an id
## already taken, are skipped rather than half-loaded.
func load_definitions(definitions: Array) -> void:
	_definitions.clear()
	_order.clear()
	for definition in definitions:
		if not (definition is StatDefinition):
			continue
		var id: StringName = definition.id
		if id == &"" or _definitions.has(id):
			continue
		_definitions[id] = definition
		_order.append(id)
	_rebuild_groups()
	_reset()

# --- the run ---------------------------------------------------------------

## Begins, or begins again -- permadeath restarts from day 1, so this has to
## return the model to its initial state rather than assume a fresh instance.
func start() -> void:
	_reset()
	_running = true
	_evaluate_thresholds()

func stop() -> void:
	_running = false

func is_running() -> bool:
	return _running

func is_dead() -> bool:
	return _dead

func advance(delta: float) -> void:
	if not _running or _dead:
		return
	if not is_finite(delta) or delta <= 0.0:
		return
	var remaining := delta
	while remaining > 0.0 and _running and not _dead:
		var step := minf(remaining, MAX_STEP)
		remaining -= step
		_step(step)

func _step(delta: float) -> void:
	for target in _stacks:
		(_stacks[target] as ModifierStack).tick(delta)
	_evaluate_thresholds()
	for stat_id in _order:
		var definition: StatDefinition = _definitions[stat_id]
		var rate := recovery_rate_of(stat_id) - drain_rate_of(stat_id)
		_values[stat_id] = clampf(
			float(_values[stat_id]) + rate * delta,
			definition.min_value,
			definition.max_value
		)
	_announce_floors()

func _announce_floors() -> void:
	var lethal_stat: StringName = &""
	for stat_id in _order:
		var definition: StatDefinition = _definitions[stat_id]
		var value := float(_values[stat_id])
		var on_floor := value <= definition.min_value
		var was_on_floor := bool(_depleted.get(stat_id, false))
		if on_floor == was_on_floor:
			continue
		_depleted[stat_id] = on_floor
		if on_floor:
			_emit(EVENT_STAT_DEPLETED, {"stat": stat_id, "value": value})
			# GDD section 5: frostbite bottoming out costs a limb, never a life.
			# Only a stat that says lethal_at_min ends the run.
			if definition.lethal_at_min and lethal_stat == &"":
				lethal_stat = stat_id
		else:
			_emit(EVENT_STAT_RECOVERED, {"stat": stat_id, "value": value})
	if lethal_stat == &"":
		return
	_dead = true
	_running = false
	_emit(EVENT_DIED, {"stat": lethal_stat})

# --- reading ---------------------------------------------------------------

## A copy. Callers cannot add a stat by writing to what they are handed.
func stat_ids() -> Array[StringName]:
	return _order.duplicate()

func has_stat(stat_id: StringName) -> bool:
	return _definitions.has(stat_id)

## Zero for a stat that does not exist, deliberately: a readout asking for
## something misspelt should look alarming, not healthy.
func value_of(stat_id: StringName) -> float:
	return float(_values.get(stat_id, 0.0))

## Where the stat sits in its own range, 0 .. 1. What a readout wants when it
## does not care that a stat might not be scaled 0 .. 1.
func fraction_of(stat_id: StringName) -> float:
	if not _definitions.has(stat_id):
		return 0.0
	var definition: StatDefinition = _definitions[stat_id]
	var span: float = definition.max_value - definition.min_value
	if span <= 0.0:
		return 0.0
	return clampf((float(_values[stat_id]) - definition.min_value) / span, 0.0, 1.0)

func is_depleted(stat_id: StringName) -> bool:
	return bool(_depleted.get(stat_id, false))

## How fast the reserve is falling, after every modifier on its drain channel.
func drain_rate_of(stat_id: StringName) -> float:
	if not _definitions.has(stat_id):
		return 0.0
	var definition: StatDefinition = _definitions[stat_id]
	return _apply_stack(_channel(stat_id, CHANNEL_DRAIN), definition.base_decay_per_second)

## How fast something is putting it back. Zero unless a fire, a meal or sleep
## has pushed onto the recovery channel.
func recovery_rate_of(stat_id: StringName) -> float:
	if not _definitions.has(stat_id):
		return 0.0
	return _apply_stack(_channel(stat_id, CHANNEL_RECOVERY), 0.0)

## Signed: negative while the stat is losing ground.
func net_rate_of(stat_id: StringName) -> float:
	return recovery_rate_of(stat_id) - drain_rate_of(stat_id)

## The one call a behaviour makes: "here is my base value, tell me what the
## body does to it". Unknown channels return the base untouched, so a system
## can ask for something no stat file has an opinion about yet.
func channel_value(channel: StringName, base_value: float) -> float:
	return _apply_stack(_canonical(channel), base_value)

## Introspection for tests and, later, for a readout that wants to say WHY a
## stat is moving.
func modifier_count(target: StringName) -> int:
	var stack: ModifierStack = _stacks.get(_canonical(target), null)
	return 0 if stack == null else stack.size()

func active_threshold_count() -> int:
	var count := 0
	for group in _groups:
		if group["active"]:
			count += 1
	return count

# --- writing ---------------------------------------------------------------
#
# There is no setter for a stat's value. Values move by the model -- drain,
# recovery and restore() -- so that "why did my temperature jump" always has an
# answer somewhere in data.

## Puts `amount` back into a stat: a drink, a meal, a limb treated at a fire.
## Refuses negative amounts; taking a value down is what a drain modifier is
## for, and a back door here would be a value change with no source to blame.
## Returns the resulting value.
func restore(stat_id: StringName, amount: float) -> float:
	if not _definitions.has(stat_id) or not is_finite(amount) or amount <= 0.0:
		return value_of(stat_id)
	var definition: StatDefinition = _definitions[stat_id]
	_values[stat_id] = clampf(
		float(_values[stat_id]) + amount,
		definition.min_value,
		definition.max_value
	)
	return float(_values[stat_id])

## The content path: a StatModifier off an ItemDefinition or a
## WeatherEventDefinition, applied as authored. False only when there is
## nothing to apply.
func apply_stat_modifier(modifier) -> bool:
	if modifier == null or modifier.target_stat == &"":
		return false
	return push_modifier(
		modifier.target_stat,
		modifier.source_id,
		modifier.operation,
		modifier.value,
		modifier.duration
	)

## The code path, for a system computing a value rather than authoring one --
## the nightfall doubling of GDD section 3, say, which is the clock's to push
## and not this file's to know about:
##
##     push_modifier(&"core_temperature", &"night", Modifier.Operation.MULTIPLY, 2.0)
##     remove_source(&"night")
func push_modifier(
	target: StringName,
	source_id: StringName,
	operation: int,
	value: float,
	duration := -1.0
) -> bool:
	if target == &"":
		return false
	var modifier := Modifier.new()
	modifier.source_id = source_id
	modifier.operation = operation
	modifier.value = value
	modifier.duration = duration
	_stack_for(_canonical(target)).add(modifier)
	return true

## Takes every modifier carrying this source off every channel. Returns how
## many were removed.
func remove_source(source_id: StringName) -> int:
	var removed := 0
	for target in _stacks:
		removed += (_stacks[target] as ModifierStack).remove_by_source(source_id)
	return removed

# --- interlocks -------------------------------------------------------------

func _rebuild_groups() -> void:
	_groups.clear()
	var by_key := {}
	for stat_id in _order:
		var definition: StatDefinition = _definitions[stat_id]
		var effects: Array = definition.threshold_effects
		for index in effects.size():
			var effect = effects[index]
			if effect == null:
				continue
			if effect.watch_stat == &"" or effect.target_stat == &"":
				continue
			var key := "%s|%d|%.6f" % [effect.watch_stat, effect.comparison, effect.threshold]
			var group: Dictionary
			if by_key.has(key):
				group = by_key[key]
			else:
				group = {
					"watch": effect.watch_stat,
					"comparison": effect.comparison,
					"threshold": effect.threshold,
					"active": false,
					"entries": [],
				}
				by_key[key] = group
				_groups.append(group)
			# The source id has to be unique per authored effect or
			# remove_by_source() would take a sibling off with it. Owning stat
			# plus index in that stat's list is unique by construction, and
			# readable in a debugger.
			(group["entries"] as Array).append({
				"source": StringName("threshold:%s:%d" % [stat_id, index]),
				"target": _canonical(effect.target_stat),
				"operation": effect.operation,
				"value": effect.value,
			})

func _evaluate_thresholds() -> void:
	for group in _groups:
		var watch: StringName = group["watch"]
		var holds := false
		var value := 0.0
		# An effect watching a stat that does not exist never fires. A typo in
		# a .tres is a silent no-op at runtime and a failing test in
		# tests/unit/test_survival_stats_data.gd, which is where it belongs.
		if _values.has(watch):
			value = float(_values[watch])
			var threshold: float = group["threshold"]
			if int(group["comparison"]) == ThresholdEffect.Comparison.BELOW:
				holds = value < threshold
			else:
				holds = value > threshold
		if holds == bool(group["active"]):
			continue
		group["active"] = holds
		var targets: Array[StringName] = []
		for entry in group["entries"]:
			var target: StringName = entry["target"]
			var source: StringName = entry["source"]
			targets.append(target)
			var stack := _stack_for(target)
			# Remove first even when adding: if anything else took this source
			# off, or put it on, re-adding blind would stack two copies of one
			# interlock and there would be no way to tell from the outside.
			stack.remove_by_source(source)
			if holds:
				var modifier := Modifier.new()
				modifier.source_id = source
				modifier.operation = int(entry["operation"])
				modifier.value = float(entry["value"])
				modifier.duration = -1.0
				stack.add(modifier)
		_emit(EVENT_THRESHOLD_CROSSED, {
			"stat": watch,
			"threshold": float(group["threshold"]),
			"comparison": (
				"below" if int(group["comparison"]) == ThresholdEffect.Comparison.BELOW else "above"
			),
			"active": holds,
			"value": value,
			"targets": targets,
		})

# --- internals --------------------------------------------------------------

func _reset() -> void:
	_values.clear()
	_stacks.clear()
	_depleted.clear()
	_dead = false
	for stat_id in _order:
		var definition: StatDefinition = _definitions[stat_id]
		_values[stat_id] = clampf(
			definition.initial_value,
			definition.min_value,
			definition.max_value
		)
	for group in _groups:
		group["active"] = false

func _canonical(target: StringName) -> StringName:
	var text := String(target)
	if text.contains(CHANNEL_SEPARATOR):
		return target
	return StringName(text + CHANNEL_SEPARATOR + CHANNEL_DRAIN)

func _channel(stat_id: StringName, channel: String) -> StringName:
	return StringName(String(stat_id) + CHANNEL_SEPARATOR + channel)

func _stack_for(target: StringName) -> ModifierStack:
	var stack: ModifierStack = _stacks.get(target, null)
	if stack == null:
		stack = ModifierStack.new()
		_stacks[target] = stack
	return stack

## Reads a stack without creating one, so that asking about a channel nobody
## has touched does not grow the table.
func _apply_stack(target: StringName, base_value: float) -> float:
	var stack: ModifierStack = _stacks.get(target, null)
	if stack == null:
		return base_value
	return stack.apply(base_value)

func _emit(event: StringName, payload) -> void:
	if _bus != null:
		_bus.emit_event(event, payload)
