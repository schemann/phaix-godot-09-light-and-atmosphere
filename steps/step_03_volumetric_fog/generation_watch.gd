extends Node3D
## Watch the generator think (F4). The watch makes a chain of its own with the level's seed and settings, and plans it one
## room per press of Enter, seen from high above. Before a room appears, the room types the chain tried first and turned
## down show up one after the other in red, and a few lines say why. The level's own chain is never touched: the same seed
## gives the same chain, so this is the run you play, planned slowly.
## The planning is a coroutine: it plans a room, waits for the next press, plans the next one. Nothing else in the watch
## has to remember where the planning is.

const Chain := preload("room_chain.gd")
const Gizmos := preload("gizmos.gd")
const Level := preload("level.gd")
const Lines := preload("lines.gd")

signal step_requested ## Enter was pressed while watching.
signal room_planned(plan: Chain.Plan) ## A room has been shown, with the room types that were turned down for it.

const PLAN_COLOR := Color(0.45, 0.75, 1.0)
const SKY_HEIGHT := 60.0 ## Metres above the floor. An orthographic camera sees the same at any height; this one clears the ceilings.
const FRAME_MARGIN := 1.25 ## The rooms fill 80 percent of the picture.
const MIN_VIEW := 24.0 ## Metres of floor the camera shows at least: room 0 alone fills a bit more than half of it.

@export var level: Level
@export var candidate_seconds := 0.7 ## How long each room type that was turned down stays on the screen.

var watching := false
var chain: Chain ## The chain of this watch, not the level's.

var _ticket := 0 ## Counts the watches. A coroutine cannot be stopped from outside, so it keeps the ticket it started with and quits when it is no longer the latest.
var _shown := 0 ## How many plans of the chain are on the screen. The chain plans a room before the watch shows it.
var _rejection: Chain.Rejection ## The turned-down room that is on the screen right now, or null.

@onready var lines: Lines = $Lines
@onready var camera: Camera3D = $Camera
@onready var screen: CanvasLayer = $Screen
@onready var report: Label = $Screen/Report

func _ready() -> void:
	level.seed_changed.connect(_on_seed_changed)
	_set_shown(false)

func _unhandled_input(event: InputEvent) -> void:
	if level.typing:
		return # the seed box is up: its keys are not ours
	if event.is_action_pressed("toggle_watch"):
		if watching:
			_leave()
		else:
			_enter()
	elif event.is_action_pressed("step_generation") and watching:
		step_requested.emit()

func _process(_delta: float) -> void:
	if not watching:
		return
	lines.begin()
	for i in _shown:
		Gizmos.draw_bounds(lines, chain.plans[i], PLAN_COLOR)
		Gizmos.draw_markers(lines, chain, chain.plans[i])
	if _rejection != null:
		Gizmos.draw_rejection(lines, chain, _rejection, 1.0)
	lines.end()
	_frame_camera()

## One sentence for a room type that was turned down: "WIDE runs into room 3".
static func rejection_text(rejection: Chain.Rejection) -> String:
	var why := "runs into room %d" % rejection.hit if rejection.reason == Chain.Reason.OVERLAP else "turns back"
	return "%s %s" % [Chain.Type.find_key(rejection.type), why]

func _enter() -> void:
	watching = true
	_set_shown(true)
	camera.make_current()
	_begin()

func _leave() -> void:
	watching = false
	_ticket += 1 # the running coroutine quits at its next await
	_set_shown(false)
	camera.clear_current() # the player's camera takes over again

## A fresh chain for the level's seed, and a fresh coroutine to plan it.
func _begin() -> void:
	_ticket += 1
	chain = Chain.new(level.chain_seed, level.goal_room, level.lock_chance)
	_shown = 0
	_rejection = null
	report.text = "Seed %s\nEnter plans room 0" % level.seed_text
	_think(_ticket)

## Plans the chain one room per step, for as long as this is the latest watch. Every await is followed by the ticket
## check: the watch may have been left or restarted (R, N, a typed seed) while the coroutine was waiting.
func _think(ticket: int) -> void:
	while ticket == _ticket:
		await step_requested
		if ticket != _ticket:
			return
		var plan := chain.next_plan()
		report.text = "Room %d" % plan.index
		for rejection in plan.rejected:
			_rejection = rejection
			report.text += "\n" + rejection_text(rejection)
			await get_tree().create_timer(candidate_seconds).timeout
			if ticket != _ticket:
				return
		_rejection = null
		_shown = plan.index + 1
		report.text += "\n%s fits" % Chain.Type.find_key(plan.type)
		room_planned.emit(plan)
		if plan.type == Chain.Type.GOAL:
			report.text += "\nThe chain is complete: %d rooms. F4 leaves, R or N starts another seed." % chain.plans.size()
			return

func _on_seed_changed(_seed_text: String) -> void:
	if watching:
		_begin()

func _set_shown(on: bool) -> void:
	lines.visible = on
	screen.visible = on
	if not on:
		lines.begin()
		lines.end() # nothing left on the mesh

## High above the middle of what is on the screen, looking down, far enough out to see all of it.
func _frame_camera() -> void:
	var area := AABB(Vector3.ZERO, Vector3.ZERO)
	for i in _shown:
		area = chain.plans[i].bounds if i == 0 else area.merge(chain.plans[i].bounds)
	if _rejection != null:
		area = _rejection.bounds if _shown == 0 else area.merge(_rejection.bounds)
	var aspect := get_viewport().get_visible_rect().size.aspect()
	camera.position = area.get_center() * Vector3(1.0, 0.0, 1.0) + Vector3.UP * SKY_HEIGHT
	camera.size = maxf(MIN_VIEW, maxf(area.size.z, area.size.x / aspect) * FRAME_MARGIN)
