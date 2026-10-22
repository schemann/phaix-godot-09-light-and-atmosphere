extends Node3D

enum State {
	READY, ## In room 0, the first door is closed.
	RUNNING, ## From the moment the first door opens.
	FINISHED, ## The player stands on the goal pad.
}

signal room_entered(index: int) ## The player is in this room. Also sent for room 0 when a run starts.
signal state_changed(state: State)
signal keys_changed(count: int) ## The number of keys the player holds. Also sent with 0 when a run starts.
signal door_blocked ## A player without a key walked up to a locked door.
signal seed_changed(seed_text: String) ## A run starts with this seed. Also sent when the level starts.

const BestTimes := preload("best_times.gd")
const Chain := preload("room_chain.gd")
const Door := preload("door.gd")
const KeyPickup := preload("key.gd")
const KeyScene := preload("key.tscn")
const PlayerScene := preload("player.tscn")
const Room := preload("room.gd")
const Seeds := preload("seeds.gd")

const SPAWN_DEPTH := 1.5 ## Metres inside room 0, so the capsule starts clear of the wall.

@export var seed_text := "42" ## The seed as a person types it. Plain digits are that number, any other text is hashed (seeds.gd).
@export_range(1, 500) var goal_room := 20 ## The room the run ends in.
@export_range(0.0, 1.0) var lock_chance := 0.4 ## The chance for a room to be locked. Its key lies in the same room.
@export var save_path := "user://best_times.json" ## Tests and recordings point it at a temporary file.

var chain_seed: int ## The number of seed_text. Set by start(); what the chain, the best times and the map use.
var typing := false ## The seed box is up: the player stands and the clock waits.
var chain: Chain
var rooms: Dictionary[int, Room] = {} ## The rooms that exist right now, by plan index.
var current := 0 ## Index of the room the player is in.
var state := State.READY
var run_time := 0.0 ## Seconds of the run. Added up from the physics delta, never read from a clock.
var best_times: BestTimes
var new_best := false ## The run that just finished beat the best time of its seed.
var keys := 0 ## The keys the player holds right now.
var player: CharacterBody3D

func _ready() -> void:
	best_times = BestTimes.new(save_path)
	player = PlayerScene.instantiate() as CharacterBody3D
	add_child(player)
	start()

## R and N only pick the seed. Everything a run changes is reset in start(), nowhere else.
func _unhandled_input(event: InputEvent) -> void:
	if typing:
		return
	if event.is_action_pressed("regenerate"):
		start()
	elif event.is_action_pressed("next_seed"):
		seed_text = Seeds.next_text(seed_text)
		start()

func _physics_process(delta: float) -> void:
	if state == State.RUNNING and not typing:
		run_time += delta

## A run with a seed somebody typed. The seed box calls it (main.tscn connects them).
func use_seed(text: String) -> void:
	seed_text = text
	start()

## The seed box is up: the player must not walk while the keys are typed into it. The mouse is free for it.
func _on_seed_entry_opened() -> void:
	typing = true
	player.set_frozen(true)

func _on_seed_entry_closed() -> void:
	typing = false
	if state != State.FINISHED:
		player.set_frozen(false)

## A new run: the seed, the state, the clock, the counter, the keys, room 0 only with its door closed, the player just inside.
func start() -> void:
	for room: Room in rooms.values():
		room.queue_free()
	rooms.clear()

	seed_text = Seeds.normalize(seed_text)
	chain_seed = Seeds.parse(seed_text)
	chain = Chain.new(chain_seed, goal_room, lock_chance)
	current = 0
	run_time = 0.0
	new_best = false
	keys = 0
	_spawn_room(chain.next_plan())
	rooms[0].seal_entrance()
	player.global_transform = rooms[0].entrance.global_transform.translated_local(Vector3(0.0, 0.0, -SPAWN_DEPTH))
	player.velocity = Vector3.ZERO
	seed_changed.emit(seed_text)
	room_entered.emit(current)
	keys_changed.emit(keys)
	_set_state(State.READY)

func _spawn_room(plan: Chain.Plan) -> void:
	var room := Chain.SCENES[plan.type].instantiate() as Room
	room.transform = plan.transform
	add_child(room)
	rooms[plan.index] = room
	if room.door != null: # the goal room has no door
		room.door.opened.connect(_on_door_opened.bind(plan.index))
		room.door.unlock_requested.connect(_on_unlock_requested.bind(room.door))
	room.inside.body_entered.connect(_on_room_entered.bind(plan.index))
	if room.goal_pad != null:
		room.goal_pad.body_entered.connect(_on_goal_reached)
	# What the plan put in the room: a lock on the door, and the key at its spot.
	if plan.locked:
		room.door.lock()
	if plan.key_spot >= 0:
		_spawn_key(room, room.key_spots[plan.key_spot])
	_spawn_props(room, plan)
	room.light.light_color = Chain.LAMP_TINTS[plan.lamp] # the plan's lamp number is a colour of the table

## The key becomes a child of the room, so it goes away with the room.
func _spawn_key(room: Room, spot: Marker3D) -> void:
	var key := KeyScene.instantiate() as KeyPickup
	key.transform = spot.transform # the room is the parent: the spot's place in the room is the key's
	room.add_child(key)
	key.picked_up.connect(_on_key_picked_up)

## One prop per planned spot, placed as the spot is placed and facing the way it faces. Like the key,
## the props become children of the room and go away with it.
func _spawn_props(room: Room, plan: Chain.Plan) -> void:
	for i in plan.props.size():
		if plan.props[i] == Chain.NO_PROP:
			continue
		var prop := chain.prop_scene(plan.type, plan.props[i]).instantiate() as Node3D
		prop.transform = room.prop_spots[i].transform
		room.add_child(prop)

func _on_key_picked_up() -> void:
	keys += 1
	keys_changed.emit(keys)

## Somebody walked up to a locked door. The rule is here and nowhere else: a key unlocks a door and
## is used up. The door then opens by itself (it checks its lock again after asking).
## No key: the answer is shown at once, on the door and on the screen.
func _on_unlock_requested(door: Door) -> void:
	if keys > 0:
		keys -= 1
		keys_changed.emit(keys)
		door.unlock()
	else:
		door.rattle()
		door_blocked.emit()

## A door starts to open: build what is behind it. Only the newest room's door asks for
## a new room, so walking back builds nothing.
func _on_door_opened(index: int) -> void:
	if state == State.READY:
		_set_state(State.RUNNING)
	if index == chain.plans.size() - 1:
		_spawn_room(chain.next_plan())

## The player stepped into a room: close the door behind the player and forget the old rooms.
func _on_room_entered(_body: Node3D, index: int) -> void:
	if index <= current:
		return
	current = index
	room_entered.emit(current)
	rooms[current - 1].door.close()
	for old: int in rooms.keys():
		if old < current - 1:
			rooms[old].queue_free()
			rooms.erase(old)

func _on_goal_reached(_body: Node3D) -> void:
	if state == State.RUNNING:
		new_best = best_times.submit(chain_seed, run_time)
		_set_state(State.FINISHED)

## The only place the state changes. What a state means for the player happens here.
func _set_state(new_state: State) -> void:
	state = new_state
	match state:
		State.READY:
			player.set_frozen(false)
		State.FINISHED:
			player.set_frozen(true)
	state_changed.emit(state)
