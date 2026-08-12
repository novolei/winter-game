class_name ThresholdCopy
extends Resource

## One row of UI design document section 5.2's copy table: the words that
## surface when a survival stat crosses one authored threshold.
##
## ---------------------------------------------------------------------------
## THE ROW SAYS THE CONSEQUENCE. IT HAS NO FIELD FOR A NUMBER, ON PURPOSE
## ---------------------------------------------------------------------------
## Section 5.2: 「冻伤 34%」要求玩家在脑子里维护一张表。「手指不听使唤了」不要求任何
## 东西. A percentage asks the player to keep a lookup table in his head; a
## consequence asks nothing of him -- he knows at once not to go and light the
## fire yet, and to warm his hands first.
##
## That is the third pillar (沉默即叙事) landing in the interface rather than
## being suspended for it, which is why there is deliberately no `value` here for
## a well-meaning author to start rendering.
##
## ---------------------------------------------------------------------------
## WHY THE MECHANIC IS COPIED ONTO THE ROW
## ---------------------------------------------------------------------------
## `effect` is what the data actually does at this point, in the designer's own
## words from section 5.2's table. It is never drawn. It is here so that whoever
## reviews a line of copy can check it against the mechanic without opening
## data/stats/*.tres and decoding a ThresholdEffect -- the failure this guards
## against is a row whose words are fine English and describe the wrong thing.

@export var stat: StringName = &""

## The threshold authored in data/stats/*.tres that this row answers. Compared
## with a tolerance rather than for equality -- see ThresholdCopyMap.
@export var threshold: float = 0.0

## What the data does at this point. Documentation, never rendered.
@export var effect: String = ""

## What the player is told. Section 5.2's 浮现文案 column.
@export var text: String = ""
