extends Node3D
## Draws what the generator knows into the world: the box of every room it has planned, and the markers inside it
## (the entrance and the exit, the spots for a key and for props, with the choice the plan made). F3 shows and hides it.
## When a room is planned, the room types the chain tried first and turned down flash red where they would have stood.
## It only reads. It looks at the level's plans and draws lines; it never changes the level, the chain or a plan,
## so a run with the gizmos on is the run it is with them off.

const Chain := preload("room_chain.gd")
const Level := preload("level.gd")
const Lines := preload("lines.gd")

const CURRENT_COLOR := Color(1.0, 0.8, 0.25) ## The room the player is in: the map's colour for it.
const LIVE_COLOR := Color(0.45, 0.75, 1.0) ## A room that exists right now.
const REMOVED_COLOR := Color(0.6, 0.6, 0.6, 0.6) ## A room the chain remembers but the level has removed. It still blocks new rooms.
const ENTRANCE_COLOR := Color(0.35, 1.0, 0.45) ## Green: in.
const EXIT_COLOR := Color(1.0, 0.35, 0.95) ## Magenta: out. Orange is the door, and an orange arrow on an orange door cannot be seen.
const KEY_COLOR := Color(1.0, 0.82, 0.2) ## Gold, like the key.
const PROP_COLOR := Color(0.92, 0.92, 1.0)
const UNUSED_ALPHA := 0.35 ## A spot the plan did not use is drawn faint.
const KEY_SIZE := 0.5 ## Half the length of the arms of the cross on the key spot the plan chose.
const SPOT_SIZE := 0.25 ## The same for a spot the plan did not use and for a prop spot.
const KEY_CROSS_HEIGHT := 0.5 ## Metres above the floor: the cross on the key spot the plan chose.
const KEY_POST_HEIGHT := 1.5 ## Metres: the post on that spot, so the key is easy to find in a big room.
const SPOT_HEIGHT := 0.2 ## Metres: the crosses on the key spots the plan did not use and on the prop spots.
const FACING_LENGTH := 0.6 ## Metres: the stick that shows the way a prop spot faces.
const REJECTED_COLOR := Color(1.0, 0.1, 0.1) ## Red: not here.
const FLASH_SECONDS := 1.5 ## How long a rejected room stays on the screen while it fades.
const ARROW_HEIGHT := 1.0 ## Metres above the floor: the markers sit on the floor, an arrow there would lie in the doorway sill.

## A rejected room on its way out. The chain made the Rejection; the view only remembers how long ago it saw it.
class Flash:
	var rejection: Chain.Rejection
	var age := 0.0

	func _init(rejected: Chain.Rejection) -> void:
		rejection = rejected

@export var level: Level

var _flashes: Array[Flash] = []
var _chain: Chain ## The chain this view is following. A new run has a new chain.
var _seen := 0 ## How many plans of that chain the view has looked at.

@onready var lines: Lines = $Lines

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_gizmos") and not level.typing: # while the seed box is up, its keys are not ours
		visible = not visible # a hidden node hides its lines, too

func _process(delta: float) -> void:
	_collect_flashes()
	for i in range(_flashes.size() - 1, -1, -1): # backwards, so that removing one does not skip the next
		_flashes[i].age += delta
		if _flashes[i].age >= FLASH_SECONDS:
			_flashes.remove_at(i)
	if not visible:
		return
	lines.begin()
	for plan in level.chain.plans:
		draw_bounds(lines, plan, color_of(plan))
		draw_markers(lines, level.chain, plan)
	for flash in _flashes:
		draw_rejection(lines, level.chain, flash.rejection, 1.0 - flash.age / FLASH_SECONDS)
	lines.end()

## Looks at the plans that are new since the last frame and starts a flash for each room type they turned down.
func _collect_flashes() -> void:
	if level.chain != _chain:
		_chain = level.chain
		_seen = 0
	while _seen < _chain.plans.size():
		for rejection in _chain.plans[_seen].rejected:
			_flashes.append(Flash.new(rejection))
		_seen += 1

## The colour of a room's box: where the player is, what exists, what is gone.
func color_of(plan: Chain.Plan) -> Color:
	if plan.index == level.current:
		return CURRENT_COLOR
	return LIVE_COLOR if level.rooms.has(plan.index) else REMOVED_COLOR

## A room as the generator sees it: its bounds, the box that the overlap test uses. Static: it needs
## the plan and a place to draw, nothing else, so any view can use it.
static func draw_bounds(pen: Lines, plan: Chain.Plan, color: Color) -> void:
	pen.box(plan.bounds, color)

## The markers of a room, from the module of its type (they sit in the room's own space) and the plan (where the room
## stands, which key spot holds the key, which prop spots hold a prop). A spot the plan did not use is faint.
static func draw_markers(pen: Lines, chain: Chain, plan: Chain.Plan) -> void:
	var module := chain.module_of(plan.type)
	pen.arrow(_raised(plan.transform * module.entrance), ENTRANCE_COLOR)
	if plan.type != Chain.Type.GOAL: # the goal room has no exit
		pen.arrow(_raised(plan.transform * module.exit), EXIT_COLOR)
	for i in module.key_spots.size():
		var spot := plan.transform * module.key_spots[i]
		if i == plan.key_spot:
			pen.cross(spot + Vector3.UP * KEY_CROSS_HEIGHT, KEY_SIZE, KEY_COLOR)
			pen.line(spot, spot + Vector3.UP * KEY_POST_HEIGHT, KEY_COLOR) # a post, so the key is easy to find in a big room
		else:
			pen.cross(spot + Vector3.UP * SPOT_HEIGHT, SPOT_SIZE, _faint(KEY_COLOR))
	for i in module.prop_spots.size():
		var spot := plan.transform * module.prop_spots[i]
		var color := PROP_COLOR if plan.props[i] != Chain.NO_PROP else _faint(PROP_COLOR)
		var base := spot.origin + Vector3.UP * SPOT_HEIGHT
		pen.cross(base, SPOT_SIZE, color)
		pen.line(base, base - spot.basis.z * FACING_LENGTH, color) # the way the prop faces

static func _raised(placed: Transform3D) -> Transform3D:
	return Transform3D(placed.basis, placed.origin + Vector3.UP * ARROW_HEIGHT)

static func _faint(color: Color) -> Color:
	return Color(color.r, color.g, color.b, UNUSED_ALPHA)

## A room type the chain turned down: its box in red where it would have stood. A room that turns back
## also shows its exit, the arrow that points the wrong way. alpha fades the red out.
static func draw_rejection(pen: Lines, chain: Chain, rejection: Chain.Rejection, alpha: float) -> void:
	var color := Color(REJECTED_COLOR.r, REJECTED_COLOR.g, REJECTED_COLOR.b, alpha)
	pen.box(rejection.bounds, color)
	if rejection.reason == Chain.Reason.HEADING:
		pen.arrow(_raised(rejection.transform * chain.module_of(rejection.type).exit), color)
