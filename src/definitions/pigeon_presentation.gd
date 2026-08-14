class_name PigeonPresentation
extends Resource

## The rock dove's presentation layer: three authored plumages and the two
## supplied one-shot sounds. It is separate from BirdSpecies because these are
## variations within one species rather than facts every bird species needs.

@export var plumage_tones: Array[Color] = []
## How much each variant shifts the source DoveRock map while preserving its
## painted value structure. Zero is the untouched pack texture; one is the full
## grey-brown / grey-black / milk-white grade.
@export_range(0.0, 1.0, 0.01) var plumage_texture_tint_strength := 0.34

@export var ground_call: AudioStream
@export var departure_wings: AudioStream

## The owner's explicit exception to the twelve-colour world palette: affection
## is a tiny UI-like animal readout, not a painted surface in the valley.
@export var heart_color: Color

## The feeding prompt is another deliberately local UI affordance rather than a
## world surface. The owner asked for the hold ring and its guide to use the
## interaction's vivid green; keeping it beside the heart exception makes that
## choice data-visible without weakening the twelve-colour UITokens contract.
@export var feed_prompt_color: Color
@export var feed_guide_color: Color

@export var call_volume_db := -4.0
@export var departure_volume_db := -2.0
@export var call_carry_m := 32.0
@export var departure_carry_m := 42.0
@export var unit_size_m := 6.0
@export var call_pitch_step := 0.035
@export var call_silence_seconds := 0.42
