extends RefCounted
## The chain as data: one plan per room, made one at a time from a seed.
## It never touches the scene tree, so the same seed always gives the same chain.
## Every room draws its dice from streams of its own, started again for each room from the run's seed, the
## room's number and the stream's name (Seeds.child): the layout, the locks and the props of a room never
## depend on how many dice another room has drawn.
## The room at goal_index is the goal room, the end of the run.
## Some rooms are locked. A locked room holds the key to its own door, at one of the room's
## key spots, so a run can always be finished (see _decide_contents).
## Some prop spots of a room hold a prop (see _decide_props): the plan only says which. What a room type
## may hold, and how likely each prop is, is data: the Resources in props/.
## Every room also gets a lamp tint (see _decide_lamp): a feature of its own, rolled on a stream of its own.
## The chain is a generate-and-test loop, and it writes its tests down: every room type it tries and turns down is
## kept in the plan of the room that was built instead (Plan.rejected), with where it would have stood and why not.

enum Type { STRAIGHT, LONG, TURN_LEFT, TURN_RIGHT, WIDE, VAULT, GOAL }

const SCENES: Array[PackedScene] = [
	preload("room_straight.tscn"),
	preload("room_long.tscn"),
	preload("room_turn_left.tscn"),
	preload("room_turn_right.tscn"),
	preload("room_wide.tscn"),
	preload("room_vault.tscn"),
	preload("room_goal.tscn"),
]
const PropSet := preload("prop_set.gd")
const RoomWeights := preload("room_weights.gd")
const Seeds := preload("seeds.gd")

## How often each room type is tried first. Data: the designer tunes room_weights.tres.
const ROOM_WEIGHTS: RoomWeights = preload("room_weights.tres")

## What each room type may hold, in the order of Type (the goal room has no prop spots). A plan stores the
## index into the scenes of its own room type's set.
const PROP_SETS: Array[PropSet] = [
	preload("props/straight_set.tres"),
	preload("props/long_set.tres"),
	preload("props/turn_left_set.tres"),
	preload("props/turn_right_set.tres"),
	preload("props/wide_set.tres"),
	preload("props/vault_set.tres"),
]
const NO_PROP := -1 ## What a plan says for a prop spot that stays empty.
## The colours a room's lamp may have, by the plan's lamp number. The first one is the warm white the rooms always had.
const LAMP_TINTS: Array[Color] = [
	Color(1.0, 0.94, 0.82), ## warm white
	Color(1.0, 0.82, 0.62), ## amber
	Color(1.0, 1.0, 1.0), ## neutral white
	Color(0.80, 0.90, 1.0), ## cold white
	Color(0.86, 1.0, 0.90), ## pale green, like a tube light
]
## Why a room type was turned down.
enum Reason {
	OVERLAP, ## The room would run into an earlier one.
	HEADING, ## The room's exit would send the chain back.
}

const START_HEADING := Vector3.FORWARD
const BACK_LIMIT := 0.05 ## How far a heading may lean back (0 = side on, 1 = straight back).
const SHRINK := 0.05 ## Metres. Rooms that only touch are not overlapping.

## What a room type is: its connection points and its box, in the room's own space.
class Module:
	var entrance: Transform3D
	var exit: Transform3D
	var bounds: AABB
	var key_spots: Array[Vector3] ## Where this room type can hold a key, in the room's own space.
	var prop_spots: Array[Transform3D] ## Where it can hold props, in the room's own space. -Z is the way a prop faces.

## A room type that was tried at the end of the last room and turned down. A record, nothing more: the chain
## has already moved on, and nothing reads it to decide anything.
class Rejection:
	var type: int ## A Type.
	var reason: int ## A Reason.
	var transform: Transform3D ## Where the room would have stood.
	var bounds: AABB ## Its box there, in world space.
	var hit := -1 ## For OVERLAP: the index of the earlier room it would have run into. Otherwise -1.

	func _init(rejected_type: int, why: int, placed: Transform3D, box: AABB, hit_index := -1) -> void:
		type = rejected_type
		reason = why
		transform = placed
		bounds = box
		hit = hit_index

## One room of the chain.
class Plan:
	var index: int
	var type: int
	var transform: Transform3D
	var bounds: AABB ## In world space.
	var locked := false ## The exit door needs a key.
	var key_spot := -1 ## Which of the room's key spots holds the key. -1: no key in this room.
	var props: Array[int] = [] ## One entry per prop spot of the room: the index of a prop, or NO_PROP.
	var lamp := 0 ## Which of LAMP_TINTS the room's lamp has. The goal room keeps 0: its own light is the pad's.
	var rejected: Array[Rejection] = [] ## The room types tried before this one fit, in the order they were tried.

	func _init(plan_index: int, plan_type: int, plan_transform: Transform3D, plan_bounds: AABB) -> void:
		index = plan_index
		type = plan_type
		transform = plan_transform
		bounds = plan_bounds

var plans: Array[Plan] = [] ## Every room made so far, also the ones long removed.
var goal_index: int ## The plan that becomes the goal room. It moves on by one for every room the goal had to wait.

var lock_chance: float ## The chance for a room to be locked, 0 to 1.

var _rng := RandomNumberGenerator.new() ## Decides the rooms (stream "layout"). Only room choices ever draw from it. Started again for every room.
var _content_rng := RandomNumberGenerator.new() ## Decides the locks (stream "locks"). Contents never move a room. Started again for every room.
var _last_vault := -1 ## The index of the last vault made, or -1 if there was none yet.
var _prop_rng := RandomNumberGenerator.new() ## Decides the props (stream "props"). Started again for every room.
var _lamp_rng := RandomNumberGenerator.new() ## Decides the lamp tints (stream "lamp"). Started again for every room.
var _chain_seed: int
var _modules: Array[Module] = []

func _init(chain_seed: int, goal_room: int, chance := 0.0) -> void:
	_chain_seed = chain_seed
	goal_index = goal_room
	lock_chance = chance
	for scene in SCENES:
		_modules.append(_read_module(scene))

## Makes the next room. Call it in order: the plan list is the history.
func next_plan() -> Plan:
	if plans.is_empty():
		return _add(Type.STRAIGHT, Transform3D.IDENTITY, [])

	var last := plans[-1]
	var exit_point := last.transform * _modules[last.type].exit
	var rejected: Array[Rejection] = []

	# The goal room is a dead end, so it only has to fit: no heading to test.
	if plans.size() == goal_index:
		var goal := _modules[Type.GOAL]
		var goal_placed := exit_point * goal.entrance.affine_inverse()
		var goal_hit := _first_hit(goal_placed * goal.bounds)
		if goal_hit < 0:
			return _add(Type.GOAL, goal_placed, rejected)
		rejected.append(Rejection.new(Type.GOAL, Reason.OVERLAP, goal_placed, goal_placed * goal.bounds, goal_hit))
		goal_index += 1 # no room for it here: an ordinary room now, the goal after that

	for type: int in _weighted_types():
		var module := _modules[type]
		# Snap: the new room's entrance lands on the last room's exit.
		var placed := exit_point * module.entrance.affine_inverse()
		if _turns_back(placed, module.exit):
			rejected.append(Rejection.new(type, Reason.HEADING, placed, placed * module.bounds))
			continue # no U-turns
		var hit := _first_hit(placed * module.bounds)
		if hit >= 0:
			rejected.append(Rejection.new(type, Reason.OVERLAP, placed, placed * module.bounds, hit))
			continue # the room would run into an earlier one
		return _add(type, placed, rejected)

	push_error("room chain: no room type fits after room %d" % last.index)
	return _add(Type.STRAIGHT, exit_point * _modules[Type.STRAIGHT].entrance.affine_inverse(), rejected)

## What a room type is made of: its markers and its box, in the room's own space. Read only: a view draws it.
func module_of(type: int) -> Module:
	return _modules[type]

## How many key spots a room type has. A plan's key_spot has to be below this (see check_solvable.gd).
func key_spot_count(type: int) -> int:
	return _modules[type].key_spots.size()

## Takes the prop spots away from every room type: the chain then plans the same rooms and locks without a
## single prop. The contents check builds this twin to prove that props change nothing else.
func clear_prop_spots() -> void:
	for module in _modules:
		module.prop_spots.clear()

## The scene a prop index of a plan stands for: it counts in the set of the plan's room type.
func prop_scene(type: int, prop: int) -> PackedScene:
	return PROP_SETS[type].scenes[prop]

## A weighted choice in three steps: add the weights up (sum), roll a number up to that sum (roll), walk along
## the weights until the roll is used up (walk). roll is 0 up to 1. A bigger weight is a bigger slice of the roll.
static func weighted_pick(weights: Array[float], roll: float) -> int:
	var total := 0.0
	for weight in weights:
		total += weight
	var target := roll * total
	for i in weights.size():
		target -= weights[i]
		if target < 0.0:
			return i
	return weights.size() - 1 # only reached by rounding: the last slice

## True while the next room, plans.size(), would be closer to the last vault than the weights allow.
func _vault_too_soon() -> bool:
	return _last_vault >= 0 and plans.size() - _last_vault < ROOM_WEIGHTS.min_gap

## True if the room's exit would send the chain back: against the start heading, or towards the start room.
func _turns_back(placed: Transform3D, exit_local: Transform3D) -> bool:
	var heading := -(placed * exit_local).basis.z
	var to_start := (plans[0].transform.origin - placed.origin).normalized()
	return heading.dot(START_HEADING) < -BACK_LIMIT or heading.dot(to_start) > BACK_LIMIT

func _add(type: int, placed: Transform3D, rejected: Array[Rejection]) -> Plan:
	var plan := Plan.new(plans.size(), type, placed, placed * _modules[type].bounds)
	plan.rejected = rejected
	if type == Type.VAULT:
		_last_vault = plan.index
	_decide_contents(plan)
	_decide_props(plan)
	_decide_lamp(plan)
	plans.append(plan)
	return plan

## Locks and keys. The dice come from _content_rng, never from _rng, so the rooms of a seed are the
## same with or without locks. The stream is started again for every room from the seed and the room's
## number, so nothing that happens in another room moves this room's roll. Both dice are rolled for every
## room with key spots, locked or not, so a room gets the same roll whatever the lock chance is.
func _decide_contents(plan: Plan) -> void:
	var spot_count := _modules[plan.type].key_spots.size()
	if spot_count == 0:
		return # the goal room has no door and nothing to lock
	_content_rng.seed = Seeds.child(_chain_seed, "locks", plan.index)
	var roll := _content_rng.randf()
	var spot := _content_rng.randi_range(0, spot_count - 1)
	# Never locked: room 0, because the run starts with a door that simply opens, and the room before
	# the goal, so the last stretch is a clean sprint to the pad. (The goal room has no door.)
	var always_open := plan.index == 0 or plan.index == goal_index - 1
	if roll < lock_chance and not always_open:
		plan.locked = true
		plan.key_spot = spot # the key lies in the same room as its lock

## Props. Their own dice, like the locks': one stream per room, so a room's props depend on nothing else: no
## lock, no goal room, no other room moves them, and they move none of those. One roll for every spot: the
## room type's set says what it may be.
func _decide_props(plan: Plan) -> void:
	var spot_count := _modules[plan.type].prop_spots.size()
	if spot_count == 0:
		return # the goal room has no prop spots
	var prop_set := PROP_SETS[plan.type]
	var weights: Array[float] = prop_set.weights.duplicate()
	weights.append(prop_set.empty_weight) # the last slice of the roll is "nothing"
	_prop_rng.seed = Seeds.child(_chain_seed, "props", plan.index)
	for i in spot_count:
		var pick := weighted_pick(weights, _prop_rng.randf())
		plan.props.append(pick if pick < prop_set.scenes.size() else NO_PROP)

## The lamp tint, a new feature on a new stream. It draws its dice from a stream nobody else uses, so
## adding it moved no room, no lock and no prop of any seed: the plans are the plans of the step before.
func _decide_lamp(plan: Plan) -> void:
	if plan.type == Type.GOAL:
		return # the goal room keeps its light
	_lamp_rng.seed = Seeds.child(_chain_seed, "lamp", plan.index)
	plan.lamp = _lamp_rng.randi_range(0, LAMP_TINTS.size() - 1)

## The index of the first earlier room the box runs into, or -1 if it fits.
func _first_hit(box: AABB) -> int:
	var inner := box.grow(-SHRINK)
	for plan in plans:
		if inner.intersects(plan.bounds):
			return plan.index
	return -1

## The room types in the order the chain tries them: drawn one at a time by weight, and a type that is
## drawn is not drawn again (a weighted order without replacement). Our own generator, as always:
## Array.shuffle() would use the global one. The goal room is never drawn: it is only placed at goal_index.
## A rare room is not even a candidate while the gap to the last one is too small.
## The draws come from the layout stream of the room that is being placed, so the order of a room never
## depends on how many dice an earlier room used.
func _weighted_types() -> Array[int]:
	_rng.seed = Seeds.child(_chain_seed, "layout", plans.size())
	var left: Array[int] = []
	for type in range(Type.GOAL):
		if type == Type.VAULT and _vault_too_soon():
			continue
		left.append(type)
	var order: Array[int] = []
	while not left.is_empty():
		var weights: Array[float] = []
		for type in left:
			weights.append(ROOM_WEIGHTS.weight_of(type))
		order.append(left.pop_at(weighted_pick(weights, _rng.randf())))
	return order

## Instancing a scene outside the tree is enough to read its markers and its box.
func _read_module(scene: PackedScene) -> Module:
	var room := scene.instantiate()
	var module := Module.new()
	module.entrance = (room.get_node("Entrance") as Marker3D).transform
	var exit_marker := room.get_node_or_null("Exit") as Marker3D # the goal room has none
	if exit_marker != null:
		module.exit = exit_marker.transform
	var spots := room.get_node_or_null("KeySpots") # the goal room has none
	if spots != null:
		for spot in spots.get_children():
			module.key_spots.append((spot as Marker3D).position)
	var decor := room.get_node_or_null("PropSpots") # nor has it prop spots
	if decor != null:
		for spot in decor.get_children():
			module.prop_spots.append((spot as Marker3D).transform)
	var shape := room.get_node("Inside/CollisionShape3D") as CollisionShape3D
	var box_size := (shape.shape as BoxShape3D).size
	module.bounds = shape.transform * AABB(-box_size / 2.0, box_size)
	room.free()
	return module
