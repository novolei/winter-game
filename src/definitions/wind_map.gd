class_name WindMap
extends Resource

## Which wind blows under which sky. One `.tres` under `data/weather/`, generated
## by `tools/generate_wind_profiles.gd`.
##
## ---------------------------------------------------------------------------
## A WHITEOUT IS NOT A PALE DAY WITH MORE SNOW
## ---------------------------------------------------------------------------
## This file exists because for a while it was. The wind system shipped with one
## profile and drove it under every sky, so `pale_day` and `whiteout` produced the
## same 0.11 .. 0.90 -- and that was nobody's decision, it fell out of the wind
## and the accumulation being built in parallel.
##
## It had a consequence neither of us would have designed: because the snow load's
## accumulation constant scales with SNOWFALL and the scour scales with WIND, an
## unchanging wind meant **the wind bit hardest in light snow.** The load plateaued
## at 0.47 on day one and 0.86 in a whiteout, which is backwards.
##
## GDD section 7's weather kinds differ from each other in exactly this axis:
## 暴雪 is wind AND snow, 寒流's whole tell is 空气变得极静, 雪雾 is snow with
## almost no wind at all. A weather model that cannot say "still and heavy" or
## "dry and blowing" cannot express four of the six.
##
## ---------------------------------------------------------------------------
## AND THE STILL NIGHT IS THE DANGEROUS ONE
## ---------------------------------------------------------------------------
## `deep_night` gets the calmest wind in the game, and that is a design decision
## rather than an omission. GDD section 8: 风大 → 足迹速消 → 你安全；风停 →
## 足迹留存 → 你被跟上. `TrackMask`'s own header says the same thing -- still air
## is a weather condition, not an absence of one, and in this game it is the
## frightening one. The wind dropping at nightfall is what leaves a trail for
## something to follow.
##
## The mapping is by LIGHTING PRESET because the six presets already carry the
## weather's identity -- `Snowfall.storm_by_preset` reads them for the same
## reason. A profile lists the looks it serves, the way a `MusicCue` lists the
## situations it plays in.

@export var profiles: Array[WindProfile] = []

## Used when the sky names a look nothing claims, and when there is no lighting
## to ask at all.
@export var default_id: StringName = &"wind_valley"


func profile_for(preset_id: StringName) -> WindProfile:
	for profile in profiles:
		if profile != null and profile.presets.has(preset_id):
			return profile
	return default_profile()


func by_id(id: StringName) -> WindProfile:
	for profile in profiles:
		if profile != null and profile.id == id:
			return profile
	return null


func default_profile() -> WindProfile:
	var named := by_id(default_id)
	if named != null:
		return named
	return null if profiles.is_empty() else profiles[0]


## Every lighting preset this map claims, for a test that wants to check none
## has been left behind.
func claimed_presets() -> Array[StringName]:
	var seen: Array[StringName] = []
	for profile in profiles:
		if profile == null:
			continue
		for preset in profile.presets:
			if not seen.has(preset):
				seen.append(preset)
	return seen
