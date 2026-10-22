extends Node
## The quality switch: one input action (Q, or the left shoulder button) steps through the levels of
## quality_levels.tres, Low, Medium, High and round again. A level turns the expensive parts of the look on or off:
## the indirect light, the fog, the lamps' shadows, the glow. It never touches the level, the chain or a plan, so a
## run is the same run on every level.

const QualityLevels := preload("quality_levels.gd")
const LEVELS: QualityLevels = preload("quality_levels.tres") ## What each level turns on. Data: tune quality_levels.tres.

@export var world: WorldEnvironment
@export var label: Label ## Says the new level for a moment.
@export var timer: Timer ## How long the label stays.

var current := 0 ## The level in use, an index into the lists of LEVELS.
var _shadow_atlas := 0 ## The viewport's shadow atlas size before this node changed it.

func _ready() -> void:
	# The Environment is a resource of main.tscn: every copy of the scene shares it. Change a copy of our own.
	world.environment = world.environment.duplicate() as Environment
	_shadow_atlas = get_viewport().positional_shadow_atlas_size
	timer.timeout.connect(label.hide)
	label.hide()
	apply(LEVELS.start_level)

func _exit_tree() -> void:
	get_viewport().positional_shadow_atlas_size = _shadow_atlas # the viewport outlives the scene

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cycle_quality"):
		apply((current + 1) % LEVELS.names.size())
		label.text = "Quality: " + LEVELS.names[current]
		label.show()
		timer.start()

## Switches to a level: the Environment's GI, fog and glow, and the shadows of every lamp at once (a shadow atlas
## of size 0 draws no lamp shadow at all, also in the rooms that are built afterwards).
func apply(index: int) -> void:
	current = index
	var environment := world.environment
	environment.sdfgi_enabled = LEVELS.gi[index]
	environment.volumetric_fog_enabled = LEVELS.fog[index]
	environment.glow_enabled = LEVELS.glow[index]
	get_viewport().positional_shadow_atlas_size = _shadow_atlas if LEVELS.shadows[index] else 0
