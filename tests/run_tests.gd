extends SceneTree
## Headless tests for tutorial 09. From the repository root:
##   godot --headless --path godot/09-light-and-atmosphere -s res://tests/run_tests.gd
## Prints PASS or FAIL per test and exits with 0 only if every test passed.
## `-- --only=text` runs the tests whose name contains the text (for example `-- --only=kit`).
##
## Saves: every level the tests load gets its own temporary save file (OS temp dir, wiped
## first), so a test run never reads or writes the real best_times.json. A few tests damage a file or write to a missing folder on
## purpose: the game logs a WARNING line for each of those, that is expected.

const Chain00 := preload("res://steps/step_00_start/room_chain.gd") ## The chain the tutorial starts from (tutorial 08's final one).
const Chain := preload("res://steps/step_05_quality_switch/room_chain.gd") ## The finished chain: the same code, light changes no plan.
const Solvable := preload("res://steps/step_05_quality_switch/check_solvable.gd")
const Contents := preload("res://steps/step_05_quality_switch/check_contents.gd")
const Autopilot := preload("res://tools/autopilot.gd")
const BestTimes := preload("res://steps/step_05_quality_switch/best_times.gd")
const Echo := preload("res://steps/step_05_quality_switch/check_echo.gd") ## Measures the deep echo of any step's chain.
const Pinned := preload("res://steps/step_05_quality_switch/check_pinned.gd") ## The pinned seeds of tutorial 07.
const CheckKit := preload("res://steps/step_05_quality_switch/check_kit.gd") ## Tutorial 08's import gate of the kit: the pieces and their colliders.
const Grid := preload("res://steps/step_05_quality_switch/check_grid.gd") ## Tutorial 08's grid check.
const GiOptions := preload("res://steps/step_05_quality_switch/gi_options.gd") ## The GI check of step 4.

const STEPS: Array[String] = [
	"step_00_start",
	"step_01_room_lights",
	"step_02_world_environment",
	"step_03_volumetric_fog",
	"step_04_runtime_gi",
	"step_05_quality_switch",
]
const FINAL_STEP := "step_05_quality_switch"
const ROOM_TYPES: Array[String] = ["straight", "long", "turn_left", "turn_right", "wide", "vault"] ## Every room type of every step.
const PROP_NAMES: Array[String] = ["crate", "stack", "table", "shelf", "pillar"]

## What each step changes against the one before (file names under the step folder, props/ and kit/ included; .uid and
## .import files do not count: test_kit_import_settings checks the import settings of every step).
const KIT_FILES: Array[String] = ["kit/kit_floor_2x2.glb", "kit/kit_ceiling_2x2.glb", "kit/kit_wall_2m.glb", "kit/kit_wall_1m.glb", "kit/kit_doorway_2m.glb", "kit/kit_corner.glb", "kit/kit_door_leaf.glb", "kit/kit_pillar.glb", "kit/kit_plinth_3x3.glb", "kit/kit_goal_pad.glb"]
const CHANGES: Dictionary[String, Dictionary] = {
	"step_01_room_lights": {changed = ["door.tscn", "key.tscn", "level.gd", "room.gd"], added = ["room_lighting.gd", "room_lighting.tres"]},
	"step_02_world_environment": {changed = ["main.tscn"], added = []},
	"step_03_volumetric_fog": {changed = ["main.tscn", "room.gd", "room_lighting.gd", "room_lighting.tres"], added = []},
	"step_04_runtime_gi": {changed = ["door.tscn", "key.tscn", "main.tscn"], added = ["gi_options.gd"]},
	"step_05_quality_switch": {changed = ["main.tscn"], added = ["quality.gd", "quality_levels.gd", "quality_levels.tres"]},
}
## Every room type, each built from the kit in every step (tutorial 08's final state).
const KIT_FROM := {
	"straight": "step_00_start",
	"long": "step_00_start",
	"turn_left": "step_00_start",
	"turn_right": "step_00_start",
	"wide": "step_00_start",
	"vault": "step_00_start",
	"goal": "step_00_start",
}

const STATE_READY := 0 ## Level.State, checked by test_state_enum.
const STATE_RUNNING := 1
const STATE_FINISHED := 2

const RAY_HEIGHT := 1.2 ## Metres above the floor: through the middle of a doorway.
const CEILING_LAYER := 2 ## VisualInstance3D.layers of the ceilings and lamp blocks: layer 2 only.
const ALL_LAYERS := 1048575 ## Camera3D.cull_mask default: all 20 layers.
const WALL_THICKNESS := 0.2 ## Studio graybox standard: interior wall 0.1-0.25 x 3.0 m.
const WALL_HEIGHT := 3.0
const SLAB_THICKNESS := 0.2 ## Floor and ceiling.
const DOORWAY_WIDTH := 1.6
const DOORWAY_HEIGHT := 2.4
const MATERIAL_DIR := "res://materials/"
const SEED_COUNT := 1000
const ROOMS_PER_SEED := 300
const GOAL_SEEDS := 500 ## Seeds 1..500 for the goal room placement.
const MAX_EXTRA_ROOMS := 3 ## The goal may wait at most this many rooms for a free place.
const STREAM_ROOMS := 10 ## How many rooms the streaming test walks through.
const SPEED_UP := 4 ## The walking tests run this many times faster than real time.
const SWEEP_SEEDS := 200 ## Seeds 1..200 of the finished game for the autopilot sweep.
const SWEEP_WORKERS := 5 ## Processes the sweep is split over (tools/sweep_seeds.gd, 8 times real time each).
const SHORT_GOAL := 3 ## Goal room of the quick runs.
const LOCK_CHANCE := 0.4 ## The level's default.
const CONTENT_SEEDS := 200 ## Seeds 1..200 for the comparisons that build two chains per seed.
const PROP_SEEDS := 500 ## Seeds 1..500 for the prop rules.
const VAULT_PLATFORM_HEIGHT := 0.12 ## The raised middle of the vault: a step the capsule climbs, like the goal pad.
const ECHO_SEEDS := 200 ## Neighbour seeds 1..201 for the deep echo.
const EXPERIMENT_SEEDS := 100 ## Seeds 1..100 for the extra-dice experiment.
const EXPERIMENT_ROOMS: Array[int] = [1, 5, 9, 14] ## The rooms that get the extra dice.
## The experiment of tutorial 06: a feature that rolls three more dice in one room, written into the chain's source where
## a viewer types it, just before the lock roll. It is also one of the accidents the pinned seeds have to catch.
const EXPERIMENT_ANCHOR := "\tvar roll := _content_rng.randf()\n"
const EXPERIMENT_LINES := "\tif plan.index == %d:\n\t\tfor i in %d:\n\t\t\t_content_rng.randf()\n"
## Rooms that the default settings lock in seed 42 (goal room 20, lock chance 0.4), and the vaults it has, by step.
## Every step plans the run of tutorial 08's final step: light changes how a room looks, never a plan.
const SEED_42_LOCKS := {
	"step_00_start": [3, 6, 7, 10, 11, 13, 16, 17],
	"step_01_room_lights": [3, 6, 7, 10, 11, 13, 16, 17],
	"step_02_world_environment": [3, 6, 7, 10, 11, 13, 16, 17],
	"step_03_volumetric_fog": [3, 6, 7, 10, 11, 13, 16, 17],
	"step_04_runtime_gi": [3, 6, 7, 10, 11, 13, 16, 17],
	"step_05_quality_switch": [3, 6, 7, 10, 11, 13, 16, 17],
}
const SEED_42_VAULTS := {
	"step_00_start": [],
	"step_01_room_lights": [],
	"step_02_world_environment": [],
	"step_03_volumetric_fog": [],
	"step_04_runtime_gi": [],
	"step_05_quality_switch": [],
}
const FAULT_SEED := 43 ## A seed with a vault, a lock in room 1 and plenty of rooms to break: the check tests sabotage its plans.

# Tutorial 07
const PLAN_SEEDS := 200 ## Seeds 1..200 for the comparisons between steps.
const REJECT_SEEDS := 300 ## Seeds 1..300 for the record of rejected rooms.
const WATCH_SEEDS := 40 ## Seeds 1..40 planned room by room by the watch.
const VIEW_SEEDS: Array[int] = [42, 7, 1000] ## The seeds that are run with all debug views on and off.
const VIEW_TICKS := 900 ## Physics ticks (15 s of game time) the two runs of a seed are compared over.
const ENTER_EVERY_TICKS := 12 ## The views-on runs press Enter this often (every 0.2 s of game time) to let the watch plan next to the run.

# Tutorial 08
const KIT_STEPS: Array[String] = STEPS ## Every step has tutorial 08's kit, with its colliders.
const WALK_PROBE := 1.0 ## Metres between two pushes against a wall in test_walls_hold.
const PLAYER_RADIUS := 0.4

## Counts the script errors the engine logs. A test that hits one stops at that line and the engine hands back an
## empty array, which reads as a pass: `_report` charges the count to the test that ran.
class ScriptErrorCounter extends Logger:
	var count := 0
	var _lock := Mutex.new() ## The engine calls a logger from any thread.

	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_SCRIPT:
			return
		_lock.lock()
		count += 1
		_lock.unlock()

var _passed := 0
var _failed := 0
var _skipped := 0
var _script_errors := ScriptErrorCounter.new() ## Registered with the engine's logger for the whole run.
var _script_errors_reported := 0 ## How many script errors the tests reported so far have been charged with.
var _save_dir := ""
var _save_counter := 0

func _initialize() -> void:
	OS.add_logger(_script_errors)
	await process_frame
	var started := Time.get_ticks_msec()
	_save_dir = OS.get_temp_dir().path_join("phaix-godot-09-tests-%d" % OS.get_process_id()) # one folder per run: two runs at the same time (two sessions, a CI job and a person) must not wipe each other's save files
	_wipe_save_dir()

	await _run("code rules: no class_name, no global random, no wall clock, input only through named actions", test_code_rules)
	await _run("code rules: the HUD only reads the level", test_hud_reads_only)
	await _run("code rules: the debug views only read and draw: no write to the level, the chain or a plan, no dice, the game code does not know them", test_views_read_only)
	await _run("code rules: the door never knows what a key is, the key never knows the level, every stream of dice has one place and, from step 3, one seed per room", test_key_rules)
	await _run("code rules: props and room weights are data (Resource scripts with exports, .tres files), the code only rolls and walks", test_data_rules)
	await _run("steps: each step changes only what its concept needs, everything else is copied forward", test_copy_forward)
	await _run("step_00_start: tutorial 08's final state, file for file (only the folder names differ)", test_step_zero_is_tutorial_08)

	# Tutorial 09: room lights from data, the interior environment, volumetric fog, runtime GI, a quality switch.
	await _run("room lighting (step 1): one data file, an entry per room type; a bigger room a brighter lamp; shadows only in the vault", test_room_lighting_data)
	for step in STEPS:
		await _run("%s: every room's lamp is lit from its plan and its room type's data (tint, energy, range to the far corner, shadows, fog); a warm light on the exit" % step, test_room_lights_in_level.bind(step))
	await _run("shadows: at most one shadowed lamp among the rooms that exist at once (seeds 1-%d); the key, which spins, throws no shadow" % PLAN_SEEDS, test_shadow_budget)
	for step in STEPS:
		await _run("%s: the environment: the sky and sun of tutorial 08 (steps 0, 1), an interior from step 2 (ambient fill, no sky reflections, AgX, glow on what emits)" % step, test_environment.bind(step))
	await _run("fog (step 3): volumetric fog thin enough to read the door across the largest room (75 to 85 percent of its light gets across), as long as the rooms that can be seen, the lamps light it", test_volumetric_fog)
	await _run("gi (step 4): SDFGI for rooms built at runtime, read for an interior; what moves (door leaf, lock, key) adds nothing to it", test_runtime_gi)
	await _run("gi (step 4): gi_options.gd: LightmapGI has no bake() in a running game, VoxelGI has; GI OK for step 4, GI FAILED without GI and with a LightmapGI", test_gi_options)
	await _run("gi (step 4): gi_options.gd from the command line: exit 0 and GI OK, exit 1 and GI FAILED for step 3", test_gi_options_command)
	await _run("quality (step 5): one data file, Low to High each a superset of the one before, High is the look of step 4, the game starts on High", test_quality_data)
	await _run("quality (step 5): Q (and the left shoulder button) steps Low, Medium, High and round; each level sets GI, fog, glow and the lamp shadows; the label says it for 1.5 s", test_quality_switch)
	await _run("quality (step 5): the scene's Environment is not changed (every instance its own copy), the shadow atlas comes back when the scene goes", test_quality_owns_its_copy)
	await _run("quality (step 5): a run that switches the quality all the time is the run that never switches (seeds 42 and 1000)", test_quality_changes_no_run)
	await _run("code rules: the light, the environment and the quality switch never touch the chain, a plan or the run", test_light_reads_only)

	# Carried over from tutorial 08: the kit, its colliders, the rooms built from it, the grid check.
	await _run("kit: the import settings of every piece in every step: the project's graybox materials, no LODs, the name hints on", test_kit_import_settings)
	for step in KIT_STEPS:
		await _run("%s check_kit: every piece as the table says (size, pivot, facing, normals, material, 1 UV unit per metre, colliders)" % step, test_kit_table.bind(step))
	await _run("check_kit: the -colonly boxes came in as StaticBody3D boxes on the world layer, in every step", test_kit_colliders)
	await _run("check_kit: finds each kind of broken piece (size, pivot, material, an inward face, texel density, a missing, moved or overlapping collider, a face in the opening)", test_kit_check_finds_faults)
	await _run("check_kit: runs from the command line and exits 0 for the kit", test_kit_command)
	for step in KIT_STEPS:
		await _run("%s kit zoo: every piece once, in the order of the table, with its measured size and its pivot dot, a figure of the player's size" % step, test_kit_zoo.bind(step))
		await _run("%s kit zoo: every piece stops the player at its face, the floor tile carries it" % step, test_kit_zoo_collision.bind(step))
	for step in STEPS:
		await _run("%s rooms: every room type built from the kit, no CSG left" % step, test_kit_rooms.bind(step))
	await _run("door: the leaf is the kit's door leaf on the hinge, its collider on the hinge body is the leaf's box", test_kit_door_leaf)
	await _run("ceiling tile: an inherited scene of the kit's ceiling tile, on layer 2 only, with its collider", test_ceiling_tile)
	for step: String in [STEPS[0], FINAL_STEP]: # the room scenes are the same files in every step (test_copy_forward)
		await _run("%s: the player cannot walk through a wall: pushed into every metre of every edge of every room, it stops at the wall's face" % step, test_walls_hold.bind(step))
		await _run("%s: the player can walk every room: across the whole floor and every seam, along every wall" % step, test_walk_every_room.bind(step))
	await _run("contents: the fixtures of the finished step are tutorial 08's (pillars, plinths, pad)", test_kit_fixtures)
	await _run("grid: every room of every step passes check_grid; the tile schedule counts every piece", test_grid_rooms)
	await _run("grid: the check finds each kind of broken room (off the grid, a gap, an overlap, a wall facing out, a doorway moved, CSG in the shell)", test_grid_finds_faults)
	await _run("grid: check_grid.gd from the command line: exit 0 and GRID OK", test_grid_command)

	# Carried over from tutorial 07: debug views that read and draw, the record of the rooms the chain turned down, the watch, pinned seeds.
	await _run("lines: begin, line, box, cross, arrow, end: a box is 12 edges, the mesh gets the points and colours (as strips of 3 pixels, or as plain lines), an empty frame is no surface", test_lines)
	await _run("plans: all six steps plan the run of tutorial 08 (type, place, lock, key, props and lamp of seeds 1-%d): light moves nothing" % PLAN_SEEDS, test_steps_plan_the_same)
	for step in STEPS:
		await _run("%s gizmos: F3 shows and hides them, hidden they draw nothing, the hint says F3" % step, test_gizmos_toggle.bind(step))
		await _run("%s gizmos: the plan's bounds of every room, in the colour of where the player is (current, live, removed)" % step, test_gizmo_bounds.bind(step))
		await _run("%s gizmos: entrance, exit, key spots and prop spots are where the room's scene has them; the plan's key spot and props are the bright ones" % step, test_gizmo_markers.bind(step))
	await _run("rejected: every room type the chain turned down is recorded with where it would have stood, why and whom it hit; the tried types are the head of the drawn order (seeds 1-%d)" % REJECT_SEEDS, test_rejections_recorded)
	await _run("rejected: a goal room that does not fit is the first record of the next plan, and the chain waits", test_rejections_goal)
	for step: String in [STEPS[0], FINAL_STEP]:
		await _run("%s gizmos: the rejected rooms flash red where they would have stood, once per plan, and fade out within 1.5 s" % step, test_rejection_flash.bind(step))
		await _run("%s watch: F4 looks from above and back, Enter plans one room, the watch's chain is the seed's chain and the level's is not touched" % step, test_watch_steps.bind(step))
		await _run("%s watch: after a restart only the latest coroutine plans; leaving stops it, even in the middle of a room" % step, test_watch_restart.bind(step))
		await _run("%s watch: stepping through reaches the plans of the normal run for seeds 1-%d, and the plans of walked levels" % [step, WATCH_SEEDS], test_watch_same_plans.bind(step))
		await _run("%s: a run with every debug view on is the run it is with them off (seeds 42 and 1000, 600 ticks)" % step, test_views_change_nothing.bind(step))
	await _run("views: the finished game, seeds 42 and 1000 from the first door to the goal pad with every view on: the same time, keys and plans", test_views_full_run)
	await _run("pinned: the pins hold in every step and are the chain's letters, locks and end points (worked out a second time)", test_pinned_holds)
	await _run("pinned: five accidents, each a small change that looks harmless, fail the pinned seeds and name the room that moved", test_pinned_fails)
	await _run("pinned: check_pinned.gd from the command line: exit 0 and PINNED OK, exit 1 and PINNED FAILED for the accident, --print prints the pins of the file", test_pinned_command)

	# Carried over from tutorial 06: the seed text, the seed box, the streams of dice.
	await _run("seeds (step 1): normalize and parse: digits are the number, other text is hashed, case and spaces do not matter", test_seed_text)
	await _run("seeds (step 1): text_hash is FNV-1a (the published test vectors and the seeds of this tutorial), next_text counts up", test_seed_hash_and_next)
	for step: String in [STEPS[0], FINAL_STEP]:
		await _run("%s: the HUD shows \"Seed 42\", T opens the seed box, Enter starts a run with the typed seed, Esc changes nothing" % step, test_seed_entry.bind(step))
		await _run("%s: the keys typed into the seed box (W A S D R N) do not move, restart or change anything; the clock waits" % step, test_typing_is_safe.bind(step))
		await _run("%s: C copies the seed and says so for 1.5 s; the box takes at most %d characters and no empty seed" % [step, 24], test_copy_and_limits.bind(step))
	await _run("seeds: the same seed text gives the same run in a level, wherever it comes from (typed, N, R, the property)", test_seed_text_in_levels)
	for step in STEPS:
		await _run("%s: a restart (R, N, a typed seed) with the player standing at the first door does not open the new room's door" % step, test_restart_at_the_door.bind(step))
	await _run("streams: from step 3 every room draws from its own streams: a room's dice depend on the seed, the stream and the room's number only", test_room_streams)
	await _run("experiment: three more dice in one room move nothing else in steps 0 and 5: rooms before and after are identical (seeds 1-%d, rooms %s)" % [EXPERIMENT_SEEDS, EXPERIMENT_ROOMS], test_extra_dice_independent)
	await _run("echo: with mixed seeds (steps 0 and 5) the measurement finds no echo, the agreement is chance", test_echo_after)
	await _run("echo: check_echo.gd from the command line exits 0", test_echo_command)
	await _run("echo: the engine's generator makes neighbour seeds unrelated numbers: the echo is two identical seeds, never two similar ones", test_engine_neighbour_seeds)
	await _run("mixing: mix() has the published values, flips about half the bits for any single changed bit, streams of one room are strangers", test_seed_mixing)
	await _run("lamps: the tints are stable, evenly used, the goal room keeps its light (seeds 1-%d)" % SEED_COUNT, test_lamp_tints)
	await _run("lamps: the level lights every room with the tint of its plan", test_lamps_in_level)

	for step in STEPS:
		await _run("%s chain: same seed gives the same plans 0-99, another seed another ones" % step, test_determinism.bind(_chain_script(step)))
	await _run("chain: seeds 1-%d x %d rooms, no overlap, no fallback, never backwards (finished chain, vault and weights)" % [SEED_COUNT, ROOMS_PER_SEED], test_no_overlap.bind(Chain, SEED_COUNT))
	await _run("chain (the starting one, no record of rejected rooms): seeds 1-300 x %d rooms, no overlap, no fallback, never backwards" % ROOMS_PER_SEED, test_no_overlap.bind(Chain00, 300))
	for chain_script: GDScript in [Chain00, Chain]:
		var which := "starting chain" if chain_script == Chain00 else "finished chain"
		await _run("goal (%s): plan %d is the goal room, once, last, no overlap, no U-turn, seeds 1-%d" % [which, 20, GOAL_SEEDS], test_goal_placement.bind(chain_script))
		await _run("goal (%s): other goal rooms (1, 2, 7, 50, 120), 100 seeds each" % which, test_goal_other_indices.bind(chain_script))
		await _run("goal (%s): a goal that does not fit waits for the next room, and the plans stay valid" % which, test_goal_waits.bind(chain_script))
	await _run("contents: locks never move a room, in every step (seeds 1-%d)" % CONTENT_SEEDS, test_locks_keep_rooms)
	await _run("contents: more lock chance only adds locks, the key spots stay; the goal room moves no roll (seeds 1-%d)" % CONTENT_SEEDS, test_contents_second_stream)
	await _run("contents: room 0, the room before the goal and the goal room are never locked, a lock has a key in the same room (the starting chain and the finished one)", test_contents_rules)
	await _run("contents: seed 42 locks the rooms the table says in every step, the lock rate is the chance", test_contents_statistics)
	await _run("solvable: seeds 1-%d, every lock has its key in its own room, the player never gets stuck (finished chain)" % SEED_COUNT, test_solvable_seeds)
	await _run("solvable: the check finds each kind of broken generator", test_solvable_finds_faults)
	await _run("solvable: check_solvable.gd runs from the command line and exits 0", test_solvable_command)
	await _run("materials: shared graybox materials, 1 m grid, orange door, gold goal and key, red-orange lock, darker gray props, emissive fixture, no private materials", test_materials)
	for step in STEPS:
		for room_type in ROOM_TYPES:
			await _run("%s room_%s: entrance, exit, doorway size, bounds" % [step, room_type], test_room_module.bind(room_type, step))
	await _run("room_vault: 14 x 14 hall, entrance and exit opposite, four pillars, a raised platform of 0.12 m in the middle, three key spots, six prop spots", test_vault_room)
	for step in STEPS:
		await _run("%s room_goal: entrance only, 10 x 14, raised pad 3 x 3 in gold, its own light and fixture, trigger on the player layer" % step, test_goal_room.bind(step))
	for step in STEPS:
		await _run("%s: every room is closed (0.2 m floor, walls and ceiling), lamp and fixture, shared materials" % step, test_graybox_rooms.bind(step))
		await _run("%s: every Entrance is on the previous Exit" % step, test_snapping.bind(step))
	for step in STEPS:
		await _run("%s: walks on the floor, relative to its facing" % step, test_walk.bind(step))
		await _run("%s: jumps about 1 m, stays below the ceiling and lands" % step, test_jump.bind(step))
		await _run("%s: the player's camera sees the ceiling" % step, test_player_camera.bind(step))
		await _run("%s: the sealed entrance of room 0 holds" % step, test_sealed_entrance.bind(step))
		await _run("%s: right stick turns the body and tilts the head, clamped at 89 deg" % step, test_stick_look.bind(step))
		await _run("%s: mouse look maths (0.002 rad per pixel, clamped)" % step, test_mouse_math.bind(step))
	if DisplayServer.get_name() == "headless":
		_skip("mouse capture: Esc releases, a click recaptures; the mouse is released at the finish and while the seed box is up and captured again by a restart", "the headless display server never reports a captured mouse; tools/capture.gd checks it in a window")
	for step in STEPS:
		await _run("%s: a door in the accent material opens on approach, lets a ray pass when open and blocks when closed" % step, test_door.bind(step))
		await _run("%s: a door never closes on the player" % step, test_door_waits_for_the_swing.bind(step))
		await _run("%s: a player sliding past the free end of an open door leaf keeps moving" % step, test_open_leaf_end.bind(step))
	for step in STEPS:
		await _run("%s key.tscn: a graybox key in the key material, a reach on the player layer, spins and bobs without moving its reach" % step, test_key_scene.bind(step))
		await _run("%s: key spots: on the floor, in view from the entrance, off the walking line, clear of the door" % step, test_key_spots.bind(step))
		await _run("%s: walking into a key counts it once and frees it; the HUD shows \"Keys N\"" % step, test_pickup.bind(step))
		await _run("%s: the keys label sits in the stats box with the other labels" % step, test_keys_label.bind(step))
		await _run("%s: a locked door shows its lock, stays shut without a key, opens with one and uses it up" % step, test_locked_door.bind(step))
	await _run("every step: every locked room has its key in the same room, and the player can finish with them", test_locks_in_level)
	for step: String in ["step_00_start", FINAL_STEP]:
		await _run("%s: a locked door without a key rattles within one physics frame, the lock flashes, \"Locked: find the key\" shows for 1.5 s" % step, test_feedback.bind(step))
		await _run("%s: with a key the lock drops and fades and the door opens normally" % step, test_unlock_animation.bind(step))

	# Tutorial 05, carried over: props, weighted rooms, the vault, the contents check.
	for step in STEPS:
		await _run("%s props/*.tscn: five graybox props in prop.tres, a StaticBody3D on the world layer, origin at the back middle, facing -Z" % step, test_prop_scenes.bind(step))
		await _run("%s: every module has 4 to 6 prop spots on the floor against a wall, facing into the room; the goal room has none" % step, test_prop_spots.bind(step))
		await _run("%s: same seed, same props; they depend on the seed and the room only (not on locks, goal room or lock chance)" % step, test_prop_determinism.bind(step))
		await _run("%s: the level builds the props the plans say, on the spots, as children of their room, and they go with it" % step, test_props_in_level.bind(step))
	await _run("props: the spot rules hold for every prop at every spot (and every pair of props), not just for the seeds we try", test_prop_spot_rules)
	await _run("props: a prop is solid: the player walking into one stops at its face", test_props_are_solid)
	for step in STEPS:
		await _run("%s: the prop sets are Resources: one .tres per room type, scenes and weights match, the long hall favours pillars, the wide room tables and shelves" % step, test_prop_sets.bind(step))
	await _run("weighted pick: sum, roll, walk: boundaries, zero weights, and 100000 rolls land in proportion", test_weighted_pick)
	await _run("props: the weights decide: what a set holds shows in the plans in proportion (seeds 1-%d), and changing the data changes the plans" % PROP_SEEDS, test_prop_distribution)
	for step in STEPS:
		await _run("%s: the room weights are a Resource: the data decides the order, the same seed gives the same order" % step, test_room_weights.bind(step))
	await _run("weighted rooms: the weights show in the mix of 1000 seeds, and the first try of every order follows the weights", test_weighted_rooms)
	await _run("vault: at most once every min_gap rooms (seeds 1-%d), never room 0 or the goal, exactly min_gap apart sometimes, the filter's boundary" % SEED_COUNT, test_vault_spacing)
	await _run("vault: a seed shows a vault before the goal room; a locked vault holds its key at one of its spots", test_vault_seeds)
	await _run("contents: the check (check_contents.gd) holds for seeds 1-%d at lock chance 0.4 and 1.0" % SEED_COUNT, test_contents_check_seeds)
	await _run("contents: the check finds each kind of broken content", test_contents_finds_faults)
	await _run("contents: the chain's clear_prop_spots() gives the twin without props: the same rooms and locks, no prop anywhere", test_clear_prop_spots)
	await _run("contents: check_contents.gd runs from the command line and exits 0", test_contents_command)

	for step in STEPS:
		await _run("%s: rooms stream in and out through %d rooms, keys fetched on the way" % [step, STREAM_ROOMS], test_streaming.bind(step))
	for step: String in ["step_00_start", FINAL_STEP]:
		await _run("%s: the plans do not depend on when the player walks" % step, test_timing_independence.bind(step))
	for step in STEPS:
		await _run("%s: the map starts visible, Tab toggles it" % step, test_toggle_map.bind(step))
		await _run("%s: the map reads data only" % step, test_map_reads_data_only.bind(step))
	for step in STEPS:
		await _run("%s: the HUD counter reads \"Room N / goal\", follows the player and fits the screen" % step, test_counter.bind(step))
		await _run("%s: the run ends in the goal room (no door, a pad to walk onto)" % step, test_goal_in_level.bind(step))
	await _run("state: the enum is READY, RUNNING, FINISHED in every step", test_state_enum)
	for step in STEPS:
		await _run("%s: READY in room 0, RUNNING when the first door opens, FINISHED on the goal pad, input ignored after" % step, test_states.bind(step))
		await _run("%s: the finish panel is centred and hidden until the finish" % step, test_finish_panel.bind(step))
	await _run("timer: format_time cuts to tenths (0:00.0, 0:42.3, 1:00.0 ...)", test_format_time)
	for step in STEPS:
		await _run("%s: the timer adds physics deltas only, never the wall clock, and stops at the finish" % step, test_timer.bind(step))
		await _run("%s: R restarts the same seed, N starts the next seed, both through start(), keys back to 0" % step, test_restart.bind(step))
	await _run("restart: the reset lives in start() and nowhere else", test_reset_in_one_place)
	await _run("best times: a saved time loads again (round trip), the file has the documented shape", test_best_round_trip)
	await _run("best times: only a faster time replaces the best", test_best_only_faster)
	await _run("best times: no file is an empty list and loading writes nothing", test_best_missing_file)
	await _run("best times: a damaged file is kept as .bad, the list starts empty, no crash", test_best_damaged_file)
	await _run("best times: unknown keys and odd entries survive a rewrite", test_best_unknown_keys)
	await _run("best times: the save goes through a temp file, a stale temp file does no harm", test_best_atomic_write)
	await _run("best times: a save that cannot be written does not crash and keeps the time in memory", test_best_write_failure)
	await _run("best time: the HUD shows \"Best 0:39.8\" for the current seed and follows N", test_best_label)
	await _run("best time: a faster run says \"New best!\" and is saved, a slower one is not", test_best_in_level)
	await _run("full run: seed 42, goal room 20, props, locks and tints on the way: the autopilot fetches every key, opens every lock and finishes; the best time is saved", test_full_run)
	await _run("full runs: other seeds, text seeds, locked vaults, and every lockable room locked, still finish", test_more_full_runs)
	await _run("worst case: every prop spot filled with the biggest prop it can hold, the autopilot still finishes (seeds 42, 3, 7)", test_full_runs_all_spots_filled)
	await _run("autopilot: seeds 1-%d of the finished game all reach the goal, none is held in place (%d processes)" % [SWEEP_SEEDS, SWEEP_WORKERS], test_autopilot_seed_sweep)
	for step in STEPS:
		await _run("%s: main scene runs 30 frames" % step, test_scene_runs.bind(step))

	_wipe_save_dir()
	OS.remove_logger(_script_errors)
	print("\n%d passed, %d failed, %d skipped in %.1f s" % [_passed, _failed, _skipped, (Time.get_ticks_msec() - started) / 1000.0])
	quit(1 if _failed > 0 else 0)

## Runs one test unless a `-- --only=text` argument asks for other tests only.
func _run(test_name: String, test: Callable) -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--only=") and not test_name.contains(argument.trim_prefix("--only=")):
			return
	await process_frame # the engine empties its message queue between tests: the chain tests build thousands of room scenes
	var failures: Array[String] = await test.call()
	_report(test_name, failures)

#region Source rules

func test_code_rules() -> Array[String]:
	var failures: Array[String] = []
	var global_random := RegEx.create_from_string("(^|[^.\\w])(randi|randf|randi_range|randf_range|randomize|pick_random)\\(")
	var wall_clock := RegEx.create_from_string("(Time\\.get_|OS\\.get_ticks|OS\\.get_unix|OS\\.delay)")
	var scripts := _scripts_in("res://steps")
	_expect(failures, scripts.size() >= 50, "found only %d scripts under steps" % scripts.size())
	for path in scripts:
		var source := FileAccess.get_file_as_string(path)
		var lines := source.split("\n")
		for i in lines.size():
			var line := lines[i].strip_edges()
			if line.begins_with("##") or line.begins_with("#"):
				continue
			var where := "%s:%d" % [path.trim_prefix("res://"), i + 1]
			_expect(failures, not line.begins_with("class_name"), "%s: class_name" % where)
			_expect(failures, global_random.search(line) == null, "%s: global random call" % where)
			_expect(failures, wall_clock.search(line) == null, "%s: reads the wall clock (the run time comes from the physics delta)" % where)
			_expect(failures, not line.contains(".shuffle("), "%s: Array.shuffle() uses the global generator" % where)
			_expect(failures, not line.contains("Input.is_key_pressed") and not line.contains("Input.is_physical_key_pressed"), "%s: reads a key directly" % where)
			_expect(failures, not line.contains("Input.is_mouse_button_pressed") and not line.contains("get_joy_axis") and not line.contains("is_joy_button_pressed"), "%s: reads a device directly" % where)
			_expect(failures, not line.contains("event is InputEventKey") and not line.contains("event is InputEventJoypad"), "%s: reads a key or button event directly" % where)
	# Gameplay state is never written in _process.
	for step in STEPS:
		var level_source := FileAccess.get_file_as_string("res://steps/%s/level.gd" % step)
		_expect(failures, not level_source.contains("func _process("), "%s/level.gd has a _process: the clock belongs in _physics_process" % step)
		_expect(failures, level_source.contains("func _physics_process(delta: float)") and level_source.contains("run_time += delta"), "%s/level.gd does not add the physics delta" % step)
	return failures

func _scripts_in(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(dir_path)
	for sub in dir.get_directories():
		found.append_array(_scripts_in(dir_path.path_join(sub)))
	for file in dir.get_files():
		if file.ends_with(".gd"):
			found.append(dir_path.path_join(file))
	return found

func test_hud_reads_only() -> Array[String]:
	var failures: Array[String] = []
	var assignment := RegEx.create_from_string("\\blevel\\.[\\w.]+\\s*(=|\\+=|-=)[^=]")
	var call_that_changes := RegEx.create_from_string("\\blevel\\.(start|_set_state|_spawn_room|_spawn_key|_on_unlock_requested)\\(")
	for step in STEPS:
		var lines := FileAccess.get_file_as_string("res://steps/%s/hud.gd" % step).split("\n")
		for i in lines.size():
			var line := lines[i].strip_edges()
			if line.begins_with("#"):
				continue
			_expect(failures, assignment.search(line) == null and call_that_changes.search(line) == null, "%s/hud.gd:%d changes the level: %s" % [step, i + 1, line])
	return failures

## The steps are copies of each other: a file only differs where the step's concept needs it.
func test_copy_forward() -> Array[String]:
	var failures: Array[String] = []
	for i in range(1, STEPS.size()):
		var before := STEPS[i - 1]
		var after := STEPS[i]
		var before_files := _step_files(before)
		var after_files := _step_files(after)
		var changed: Array[String] = []
		var added: Array[String] = []
		for file in before_files:
			if not after_files.has(file):
				failures.append("%s lost %s" % [after, file])
			elif _step_text(before, file) != _step_text(after, file):
				changed.append(file)
		for file in after_files:
			if not before_files.has(file):
				added.append(file)
		changed.sort()
		added.sort()
		var expected: Dictionary = CHANGES[after]
		_expect(failures, changed == expected.changed, "%s changes %s, expected %s" % [after, changed, expected.changed])
		_expect(failures, added == expected.added, "%s adds %s, expected %s" % [after, added, expected.added])
	return failures

func _step_files(step: String) -> Array[String]:
	var files: Array[String] = []
	for file in DirAccess.get_files_at("res://steps/" + step):
		if not file.ends_with(".uid"):
			files.append(file)
	for folder: String in ["props", "kit"]: # the props of tutorial 05 and the kit of this tutorial live in folders of their own
		if DirAccess.dir_exists_absolute("res://steps/%s/%s" % [step, folder]):
			for file in DirAccess.get_files_at("res://steps/%s/%s" % [step, folder]):
				if not file.ends_with(".uid") and not file.ends_with(".import"):
					files.append(folder + "/" + file)
	return files

## The file's text with the step folder name blanked out, so copies compare equal. A .glb is compared byte for byte.
func _step_text(step: String, file: String) -> String:
	var path := "res://steps/%s/%s" % [step, file]
	if file.ends_with(".glb"):
		return FileAccess.get_file_as_bytes(path).hex_encode()
	return FileAccess.get_file_as_string(path).replace(step, "STEP")

func test_step_zero_is_tutorial_08() -> Array[String]:
	var failures: Array[String] = []
	var original := ProjectSettings.globalize_path("res://").path_join("../08-modular-kit-from-blender/steps/step_05_grid_check").simplify_path()
	if not DirAccess.dir_exists_absolute(original):
		_skip("step_00_start equals tutorial 08's step 5", "tutorial 08 is not next to this project")
		return failures
	var count := 0
	var original_files: Array[String] = []
	for file in DirAccess.get_files_at(original):
		if not file.ends_with(".uid"):
			original_files.append(file)
	for folder: String in ["props", "kit"]:
		for file in DirAccess.get_files_at(original.path_join(folder)):
			if not file.ends_with(".uid") and not file.ends_with(".import"):
				original_files.append(folder + "/" + file)
	for file in original_files:
		count += 1
		if file.ends_with(".glb"):
			_expect(failures, FileAccess.get_file_as_bytes(original.path_join(file)) == FileAccess.get_file_as_bytes("res://steps/step_00_start/" + file), "%s differs from tutorial 08's step 5" % file)
			continue
		# The folder names are the only difference: the step's own, and the project's in the usage comments.
		var theirs := FileAccess.get_file_as_string(original.path_join(file)).replace("step_05_grid_check", "STEP").replace("godot/08-modular-kit-from-blender", "godot/PROJECT")
		var ours := FileAccess.get_file_as_string("res://steps/step_00_start/" + file).replace("step_00_start", "STEP").replace("godot/09-light-and-atmosphere", "godot/PROJECT")
		_expect(failures, theirs == ours, "%s differs from tutorial 08's step 5" % file)
	_expect(failures, count == _step_files("step_00_start").size(), "step_00_start has %d files, tutorial 08's step 5 has %d" % [_step_files("step_00_start").size(), count])
	return failures

#endregion

#region Chain (pure data, no scene)

func test_determinism(chain_script: GDScript) -> Array[String]:
	var failures: Array[String] = []
	var first := _plans(chain_script, 42, 100)
	var second := _plans(chain_script, 42, 100)
	var other := _plans(chain_script, 43, 100)
	_expect(failures, first.size() == 100, "made %d plans, expected 100" % first.size())
	_expect(failures, _same_plans(first, second), "seed 42 twice: the plans differ")
	_expect(failures, not _same_plans(first, other), "seed 43 gives the same plans as seed 42")
	for i in first.size():
		_expect(failures, first[i].index == i, "plan %d has index %d" % [i, first[i].index])
	return failures

func test_no_overlap(chain_script: GDScript, seed_count: int) -> Array[String]:
	var failures: Array[String] = []
	var types_seen := {}
	for chain_seed in range(1, seed_count + 1):
		if chain_seed % 50 == 0:
			await process_frame
		# Goal far away: this checks the ordinary rooms.
		var plans := _plans(chain_script, chain_seed, ROOMS_PER_SEED)
		for plan: Object in plans:
			types_seen[plan.type] = true
		failures.append_array(_chain_problems(plans, "seed %d" % chain_seed))
		if failures.size() > 8:
			break
	_expect(failures, types_seen.size() == chain_script.SCENES.size() - 1, "only %d of %d room types were ever chosen (the goal room is never drawn)" % [types_seen.size(), chain_script.SCENES.size() - 1])
	return failures

## Overlaps with any earlier plan, headings that turn back, and snaps that do not meet.
## `plans` is the history of one chain; the last plan may be a goal room (it has no exit).
func _chain_problems(plans: Array, label: String) -> Array[String]:
	var problems: Array[String] = []
	# Sweep over x: a room can only overlap rooms whose x range reaches it.
	var by_x := plans.duplicate()
	by_x.sort_custom(func(a: Object, b: Object) -> bool: return a.bounds.position.x < b.bounds.position.x)
	for i in by_x.size():
		var a: Object = by_x[i]
		var inner: AABB = (a.bounds as AABB).grow(-Chain.SHRINK)
		for j in range(i + 1, by_x.size()):
			var b: Object = by_x[j]
			if b.bounds.position.x > a.bounds.end.x:
				break
			if inner.intersects(b.bounds) or (b.bounds as AABB).grow(-Chain.SHRINK).intersects(a.bounds):
				problems.append("%s: rooms %d and %d overlap" % [label, a.index, b.index])
	var start: Vector3 = plans[0].transform.origin
	for k in range(1, plans.size() - 1):
		# The next room's entrance has no rotation, so its basis is the heading of this exit.
		var heading: Vector3 = -(plans[k + 1].transform as Transform3D).basis.z
		var to_start := (start - (plans[k].transform as Transform3D).origin).normalized()
		if heading.dot(Chain.START_HEADING) < -Chain.BACK_LIMIT or heading.dot(to_start) > Chain.BACK_LIMIT + 0.001:
			problems.append("%s: room %d heads back (heading %s)" % [label, k, heading.snapped(Vector3.ONE * 0.01)])
	return problems

## A chain of any step's script.
func _new_chain(chain_script: GDScript, chain_seed: int, goal_room: int, chance := 0.0) -> RefCounted:
	return chain_script.new(chain_seed, goal_room, chance)

## The room_chain.gd of a step.
func _chain_script(step: String) -> GDScript:
	return load("res://steps/%s/room_chain.gd" % step) as GDScript

## What the chain's Type enum calls the goal room: 5 up to step 3, 6 from the vault on.
func _goal_type(chain_script: GDScript) -> int:
	return (chain_script.get_script_constant_map()["Type"] as Dictionary)["GOAL"]

## The first `count` plans, the goal room far behind them.
func _plans(chain_script: GDScript, chain_seed: int, count: int, chance := LOCK_CHANCE) -> Array:
	var chain := _new_chain(chain_script, chain_seed, 100000, chance)
	for i in count:
		chain.next_plan()
	return chain.plans

func _same_plans(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if not _same_plan(a[i], b[i], true):
			return false
	return true

## One plan against another: the room, its locks, its props and (with_lamp) its tint. Steps before 4 have no lamp: both sides read null.
func _same_plan(a: Object, b: Object, with_lamp: bool) -> bool:
	if a.index != b.index or a.type != b.type or a.transform != b.transform or a.bounds != b.bounds:
		return false
	if a.get("locked") != b.get("locked") or a.get("key_spot") != b.get("key_spot") or a.get("props") != b.get("props"):
		return false
	return not with_lamp or a.get("lamp") == b.get("lamp")

#endregion

#region The goal room in the chain

## All plans of a chain up to and including its goal room (at most `limit` plans).
func _plans_to_goal(chain_script: GDScript, chain_seed: int, goal_room: int, chance := LOCK_CHANCE, limit := 400) -> RefCounted:
	var chain := _new_chain(chain_script, chain_seed, goal_room, chance)
	while chain.plans.size() < limit:
		var plan: Object = chain.next_plan()
		if plan.type == _goal_type(chain_script):
			break
	return chain

func test_goal_placement(chain_script: GDScript) -> Array[String]:
	var failures: Array[String] = []
	var waited := 0
	var max_extra := 0
	for chain_seed in range(1, GOAL_SEEDS + 1):
		if chain_seed % 50 == 0:
			await process_frame
		var chain := _plans_to_goal(chain_script, chain_seed, 20)
		var plans: Array = chain.plans
		var goals: Array[int] = []
		for plan: Object in plans:
			if plan.type == _goal_type(chain_script):
				goals.append(plan.index)
		if goals.size() != 1 or goals[0] != plans.size() - 1:
			failures.append("seed %d: goal rooms at %s of %d plans" % [chain_seed, goals, plans.size()])
			continue
		var extra: int = goals[0] - 20
		max_extra = maxi(max_extra, extra)
		waited += 1 if extra > 0 else 0
		if extra < 0 or extra > MAX_EXTRA_ROOMS:
			failures.append("seed %d: the goal room is plan %d, expected 20 to %d" % [chain_seed, goals[0], 20 + MAX_EXTRA_ROOMS])
		_expect(failures, chain.goal_index == goals[0], "seed %d: goal_index %d but the goal is plan %d" % [chain_seed, chain.goal_index, goals[0]])
		failures.append_array(_chain_problems(plans, "seed %d" % chain_seed))
		if failures.size() > 8:
			break
	print("        goal room: seeds 1-%d, %d needed to wait, the longest wait was %d rooms" % [GOAL_SEEDS, waited, max_extra])
	return failures

func test_goal_other_indices(chain_script: GDScript) -> Array[String]:
	var failures: Array[String] = []
	for goal_room: int in [1, 2, 7, 50, 120]:
		for chain_seed in range(1, 101):
			if chain_seed % 50 == 0:
				await process_frame
			var chain := _plans_to_goal(chain_script, chain_seed, goal_room)
			var plans: Array = chain.plans
			var last: Object = plans[-1]
			_expect(failures, last.type == _goal_type(chain_script), "goal %d seed %d: the chain does not end in a goal room" % [goal_room, chain_seed])
			_expect(failures, last.index >= goal_room and last.index <= goal_room + MAX_EXTRA_ROOMS, "goal %d seed %d: goal room is plan %d" % [goal_room, chain_seed, last.index])
			failures.append_array(_chain_problems(plans, "goal %d seed %d" % [goal_room, chain_seed]))
			if failures.size() > 8:
				return failures
	return failures

## The wait itself. A goal that never fits is faked: the goal's box is blown up to 2 km, so it hits
## the history wherever it is placed. (The test reaches into the chain's private module list; the
## shipped rooms always find a free place, see test_goal_placement.)
func test_goal_waits(chain_script: GDScript) -> Array[String]:
	var failures: Array[String] = []
	for chain_seed: int in [42, 7, 313]:
		var chain := _new_chain(chain_script, chain_seed, 6, 1.0)
		var real_bounds: AABB = chain._modules[_goal_type(chain_script)].bounds
		for i in 6:
			chain.next_plan()
		chain._modules[_goal_type(chain_script)].bounds = AABB(Vector3(-1000.0, -10.0, -1000.0), Vector3(2000.0, 20.0, 2000.0))
		for waited in 3:
			var plan: Object = chain.next_plan()
			_expect(failures, plan.type != _goal_type(chain_script), "seed %d: an unfit goal room was placed as plan %d" % [chain_seed, plan.index])
			_expect(failures, plan.index == 6 + waited and chain.goal_index == 7 + waited, "seed %d: plan %d, goal_index %d after %d waits" % [chain_seed, plan.index, chain.goal_index, waited + 1])
		chain._modules[_goal_type(chain_script)].bounds = real_bounds # free again
		var goal: Object = chain.next_plan()
		_expect(failures, goal.type == _goal_type(chain_script) and goal.index == 9 and chain.goal_index == 9, "seed %d: after the wait the goal is plan %d (goal_index %d), expected 9" % [chain_seed, goal.index, chain.goal_index])
		failures.append_array(_chain_problems(chain.plans, "seed %d after the wait" % chain_seed))
		# The same story twice gives the same plans.
		var again := _new_chain(chain_script, chain_seed, 6, 1.0)
		for i in 6:
			again.next_plan()
		again._modules[_goal_type(chain_script)].bounds = AABB(Vector3(-1000.0, -10.0, -1000.0), Vector3(2000.0, 20.0, 2000.0))
		for i in 3:
			again.next_plan()
		again._modules[_goal_type(chain_script)].bounds = real_bounds
		again.next_plan()
		_expect(failures, _same_plans(chain.plans, again.plans), "seed %d: the waiting chain is not reproducible" % chain_seed)
		if chain_script == Chain: # the rule "the room before the goal is never locked" holds when the goal waits, too
			for plan: Object in chain.plans:
				_expect(failures, not (plan.locked and (plan.index == 0 or plan.index >= 5)), "seed %d: room %d is locked, but room 0 and every room from 5 on (before the waiting goal) stay open" % [chain_seed, plan.index])
	return failures

#endregion

#region Rooms of either kind: tutorial 07's CSG shell or kit pieces

## A room built from the kit: its shell is a group of kit pieces, not a CSG combiner.
func _is_kit_room(room: Node3D) -> bool:
	return not room.get_node("Shell") is CSGShape3D

## The room's footprint (x, z): its Inside box, which covers the floor including the walls.
func _footprint(room: Node3D) -> Vector2:
	var shape := (room.get_node("Inside/CollisionShape3D") as CollisionShape3D).shape as BoxShape3D
	return Vector2(shape.size.x, shape.size.z)

## The floor as a box in the room's space: the CSG floor box, or the bounds of the kit's floor tiles.
func _floor_box(room: Node3D) -> AABB:
	if not _is_kit_room(room):
		var floor_box := room.get_node("Shell/Floor") as CSGBox3D
		return AABB(floor_box.position - floor_box.size / 2.0, floor_box.size)
	var tiles := room.get_node("Shell/Floor").get_children()
	var box: AABB = _part(room, tiles[0] as Node3D).box
	for tile in tiles:
		box = box.merge(_part(room, tile as Node3D).box)
	return box

## A part of a room as a box in the room's space and the path of its material: a CSGBox3D or CSGCylinder3D, or a kit piece
## (the bounds of its mesh and the material of its first surface).
func _part(room: Node3D, part: Node3D) -> Dictionary:
	if part is CSGBox3D:
		var csg_box := part as CSGBox3D
		return {box = AABB(csg_box.position - csg_box.size / 2.0, csg_box.size), material = csg_box.material.resource_path if csg_box.material != null else ""}
	if part is CSGCylinder3D:
		var cylinder := part as CSGCylinder3D
		var size := Vector3(cylinder.radius * 2.0, cylinder.height, cylinder.radius * 2.0)
		return {box = AABB(cylinder.position - size / 2.0, size), material = cylinder.material.resource_path if cylinder.material != null else ""}
	var mesh_node := part.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var to_room := Grid.placed(room, part) * mesh_node.transform
	var material := mesh_node.mesh.surface_get_material(0)
	return {box = to_room * mesh_node.mesh.get_aabb(), material = material.resource_path if material != null else ""}

## The parts of the shell whose name starts with this text: the CSG cylinders, or the kit pieces under Shell/Fixtures.
func _parts_named(room: Node3D, prefix: String) -> Array[Node3D]:
	var found: Array[Node3D] = []
	var parent := room.get_node_or_null("Shell/Fixtures" if _is_kit_room(room) else "Shell") # a kit room without fixtures has no group for them
	if parent == null:
		return found
	for child in parent.get_children():
		if child.name.begins_with(prefix):
			found.append(child as Node3D)
	return found

## Equal to the millimetre: a mesh Godot imported keeps its corners to about 0.02 mm.
func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.001

#endregion

#region Rooms and snapping (scene + physics)

func test_room_module(room_type: String, step: String) -> Array[String]:
	var failures: Array[String] = []
	var room: Node3D = (load("res://steps/%s/room_%s.tscn" % [step, room_type]) as PackedScene).instantiate()
	root.add_child(room)
	# The room puts a closed door in its exit; this test is about the doorway itself.
	(room.get("door") as Node).free()
	await _wait_physics(5)
	var entrance: Marker3D = room.get_node("Entrance")
	var exit_point: Marker3D = room.get_node("Exit")
	var inside_shape: CollisionShape3D = room.get_node("Inside/CollisionShape3D")
	var bounds: AABB = inside_shape.transform * AABB(-(inside_shape.shape as BoxShape3D).size / 2.0, (inside_shape.shape as BoxShape3D).size)
	var centre := bounds.get_center()
	centre.y = 0.0

	_expect(failures, is_zero_approx(entrance.position.y) and is_zero_approx(exit_point.position.y), "markers are not at floor level")
	_expect(failures, (centre - entrance.position).dot(-entrance.global_basis.z) > 1.0, "Entrance -Z does not point into the room")
	_expect(failures, (exit_point.position - centre).dot(-exit_point.global_basis.z) > 1.0, "Exit -Z does not point out of the room")
	_expect(failures, entrance.transform.basis.is_equal_approx(Basis.IDENTITY), "Entrance is rotated")
	# The Inside box covers the footprint including the walls: the CSG floor, or the kit's floor tiles.
	var floor_aabb := _floor_box(room)
	_expect(failures, _near(bounds.size.x, floor_aabb.size.x) and _near(bounds.size.z, floor_aabb.size.z), "Inside box %s does not match the floor %s" % [bounds.size, floor_aabb.size])
	_expect(failures, is_equal_approx(bounds.size.y, WALL_HEIGHT), "Inside box is %.2f m high, walls are 3 m" % bounds.size.y)
	if _is_kit_room(room):
		var problems := Grid.problems_of(room, "room_" + room_type)
		_expect(failures, problems.is_empty(), "the kit pieces: %s" % "; ".join(problems))
	else:
		for wall_name: String in ["WallEntrance", "WallFar", "WallLeft", "WallRight"]:
			var wall: CSGBox3D = room.get_node("Shell/" + wall_name)
			_expect(failures, is_equal_approx(wall.size.y, WALL_HEIGHT), "%s is %.2f m high" % [wall_name, wall.size.y])
			_expect(failures, is_equal_approx(minf(wall.size.x, wall.size.z), WALL_THICKNESS), "%s is %.2f m thick" % [wall_name, minf(wall.size.x, wall.size.z)])

	# Doorway: 1.6 m wide, 2.4 m high, in the wall at each marker.
	for point: Marker3D in [entrance, exit_point]:
		var label := point.name
		for sideways: float in [0.0, 0.7, -0.7]:
			_expect(failures, not _ray_hits(room, point, Vector3(sideways, RAY_HEIGHT, 1.0), Vector3(sideways, RAY_HEIGHT, -1.0)), "%s: a ray %.1f m off the middle hits the wall" % [label, sideways])
		for sideways: float in [0.9, -0.9]:
			_expect(failures, _ray_hits(room, point, Vector3(sideways, RAY_HEIGHT, 1.0), Vector3(sideways, RAY_HEIGHT, -1.0)), "%s: a ray %.1f m off the middle passes the wall" % [label, sideways])
		_expect(failures, not _ray_hits(room, point, Vector3(0.0, 2.3, 1.0), Vector3(0.0, 2.3, -1.0)), "%s: the doorway is lower than 2.3 m" % label)
		_expect(failures, _ray_hits(room, point, Vector3(0.0, 2.5, 1.0), Vector3(0.0, 2.5, -1.0)), "%s: the doorway is higher than 2.5 m" % label)
	root.remove_child(room)
	room.free()
	return failures

## Casts a ray in a marker's own space (x sideways, y up, -z the way through the wall).
func _ray_hits(room: Node3D, point: Marker3D, from_local: Vector3, to_local: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(point.global_transform * from_local, point.global_transform * to_local)
	return not room.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func test_snapping(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step)
	var rooms := _rooms_of(main.get_node("Level"))
	_expect(failures, rooms.size() >= 1, "%d rooms" % rooms.size())
	for i in range(rooms.size() - 1):
		var exit_point: Transform3D = (rooms[i].get("exit") as Marker3D).global_transform
		var entrance: Transform3D = (rooms[i + 1].get("entrance") as Marker3D).global_transform
		_expect(failures, exit_point.origin.distance_to(entrance.origin) < 1e-4, "room %d Entrance is %.5f m from room %d Exit" % [i + 1, exit_point.origin.distance_to(entrance.origin), i])
		_expect(failures, exit_point.basis.is_equal_approx(entrance.basis), "room %d Entrance faces another way than room %d Exit" % [i + 1, i])
	await _unload(main)
	return failures

## All rooms of a level in order: its children that have an Entrance.
func _rooms_of(level: Node3D) -> Array[Node3D]:
	var rooms: Array[Node3D] = []
	for child in level.get_children():
		if child is Node3D and child.get("entrance") != null and not child.is_queued_for_deletion():
			rooms.append(child)
	return rooms

#endregion

#region The goal room module

func test_goal_room(step: String) -> Array[String]:
	var failures: Array[String] = []
	var room := (load("res://steps/%s/room_goal.tscn" % step) as PackedScene).instantiate() as Node3D
	var player := (load("res://steps/%s/player.tscn" % step) as PackedScene).instantiate()
	var capsule := (player.get_node("CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D
	player.free()
	root.add_child(room)
	await _wait_physics(5)

	# Entrance only: no Exit marker, no doorway in the far wall.
	_expect(failures, room.get_node_or_null("Exit") == null, "the goal room has an Exit")
	if _is_kit_room(room):
		var problems := Grid.problems_of(room, "room_goal")
		_expect(failures, int(Grid.schedule(room).get(Grid.DOORWAY, 0)) == 1 and problems.is_empty(), "the goal room has %d doorways, expected 1 (the entrance): %s" % [int(Grid.schedule(room).get(Grid.DOORWAY, 0)), "; ".join(problems)])
	else:
		_expect(failures, (room.get_node("Shell/WallFar") as Node).get_child_count() == 0, "the far wall of the goal room has a doorway")
	var entrance: Marker3D = room.get_node("Entrance")
	_expect(failures, entrance.transform.origin.is_equal_approx(Vector3(0.0, 0.0, 7.0)) and entrance.transform.basis.is_equal_approx(Basis.IDENTITY), "Entrance is at %s, expected (0, 0, 7) unrotated" % entrance.transform)
	var floor_box := _floor_box(room)
	_expect(failures, _near(floor_box.size.x, 10.0) and _near(floor_box.size.z, 14.0), "the floor is %.1f x %.1f m, expected 10 x 14" % [floor_box.size.x, floor_box.size.z])
	var inside_shape := room.get_node("Inside/CollisionShape3D") as CollisionShape3D
	_expect(failures, (inside_shape.shape as BoxShape3D).size.is_equal_approx(Vector3(10.0, 3.0, 14.0)), "the Inside box is %s" % (inside_shape.shape as BoxShape3D).size)
	_expect(failures, room.get_node_or_null("Ceiling") != null and room.get_node_or_null("RoomLight") != null and room.get_node_or_null("Fixture") != null, "ceiling, room light or fixture missing")
	# Open at the entrance: a ray through the doorway passes; the far wall is solid everywhere.
	_expect(failures, not _ray_hits(room, entrance, Vector3(0.0, RAY_HEIGHT, 1.0), Vector3(0.0, RAY_HEIGHT, -1.0)), "the entrance doorway is closed")
	var space := room.get_world_3d().direct_space_state
	for sideways: float in [0.0, 1.0, -2.5, 3.0]:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(sideways, RAY_HEIGHT, -5.0), Vector3(sideways, RAY_HEIGHT, -8.0)))
		_expect(failures, not hit.is_empty(), "a ray through the far wall at x = %.1f passes: there is a doorway" % sideways)

	# The pad: 3 x 3, raised a little (a step the capsule climbs), the gold accent, from the shared materials.
	var pad_part := _part(room, room.get_node("Shell/Fixtures/Pad" if _is_kit_room(room) else "Shell/Pad") as Node3D)
	var pad_box: AABB = pad_part.box
	var pad_centre := pad_box.get_center()
	var pad_global := room.global_transform * pad_centre
	_expect(failures, _near(pad_box.size.x, 3.0) and _near(pad_box.size.z, 3.0), "the pad is %.1f x %.1f m, expected 3 x 3" % [pad_box.size.x, pad_box.size.z])
	var pad_top := pad_box.end.y
	_expect(failures, pad_box.size.y >= 0.05 and pad_box.size.y <= 0.15 and _near(pad_top, pad_box.size.y), "the pad is %.2f m high (top at %.2f), expected a low step standing on the floor" % [pad_box.size.y, pad_top])
	_expect(failures, pad_part.material == MATERIAL_DIR + "goal.tres", "the pad does not use goal.tres")
	_expect(failures, AABB(Vector3(-5.0, 0.0, -7.0), Vector3(10.0, 0.2, 14.0)).encloses(pad_box), "the pad does not lie inside the room")
	_expect(failures, pad_box.position.z + pad_box.size.z < -1.0, "the pad is not at the far end, away from the entrance")
	var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(pad_global + Vector3(0.0, 1.0, 0.0), pad_global + Vector3(0.0, -1.0, 0.0)))
	_expect(failures, not down.is_empty() and absf((down["position"] as Vector3).y - pad_top) < 0.01, "a ray down onto the pad does not hit its top")
	var up := space.intersect_ray(PhysicsRayQueryParameters3D.create(pad_global + Vector3(0.0, 1.0, 0.0), pad_global + Vector3(0.0, 3.5, 0.0)))
	_expect(failures, not up.is_empty() and absf((up["position"] as Vector3).y - WALL_HEIGHT) < 0.01, "a ray up from the pad does not hit the ceiling")

	# The trigger: the player layer only, over the pad, small enough that the whole capsule is on the pad when it fires.
	var goal_pad := room.get_node("GoalPad") as Area3D
	_expect(failures, goal_pad.collision_layer == 0 and goal_pad.collision_mask == 2, "GoalPad: layer %d mask %d, expected 0 and 2 (the player layer)" % [goal_pad.collision_layer, goal_pad.collision_mask])
	_expect(failures, goal_pad.global_position.is_equal_approx(Vector3(pad_centre.x, 0.0, pad_centre.z)), "GoalPad is at %s, not at the middle of the pad" % goal_pad.global_position)
	var trigger := goal_pad.get_node("CollisionShape3D") as CollisionShape3D
	var trigger_box := trigger.shape as BoxShape3D
	_expect(failures, trigger_box != null and trigger.position.y - trigger_box.size.y / 2.0 < capsule.height and trigger.position.y + trigger_box.size.y / 2.0 > pad_top, "the trigger does not reach the player's body")
	if trigger_box != null:
		_expect(failures, trigger_box.size.x / 2.0 + capsule.radius <= pad_box.size.x / 2.0 + 0.001 and trigger_box.size.z / 2.0 + capsule.radius <= pad_box.size.z / 2.0 + 0.001, "the trigger fires before the capsule is on the pad (half %.2f + radius %.2f > pad half %.2f)" % [trigger_box.size.x / 2.0, capsule.radius, pad_box.size.x / 2.0])

	# Its own small warm light and a visible fixture over the pad, on the ceiling layer like the room's lamp.
	var light := room.get_node("PadLight") as OmniLight3D
	var fixture := room.get_node("PadFixture") as MeshInstance3D
	var block := fixture.mesh as BoxMesh
	_expect(failures, not light.shadow_enabled, "PadLight casts shadows")
	_expect(failures, light.light_color.r >= light.light_color.g and light.light_color.g >= light.light_color.b and light.light_color.b < 0.95, "PadLight is not warm")
	_expect(failures, light.omni_range < (room.get_node("RoomLight") as OmniLight3D).omni_range and light.omni_range >= Vector3(1.5, 0.0, 1.5).length() and light.omni_range <= 6.0, "PadLight range %.1f is not a small light that covers the pad" % light.omni_range)
	_expect(failures, Vector2(light.position.x - pad_centre.x, light.position.z - pad_centre.z).length() < 0.01 and light.position.y > 2.2 and light.position.y < WALL_HEIGHT, "PadLight is not over the pad near the ceiling (%s)" % light.position)
	_expect(failures, fixture.layers == CEILING_LAYER, "PadFixture is on layers %d, expected only layer 2" % fixture.layers)
	_expect(failures, block.material != null and block.material.resource_path == MATERIAL_DIR + "fixture.tres", "PadFixture does not use fixture.tres")
	_expect(failures, is_equal_approx(fixture.position.y + block.size.y / 2.0, WALL_HEIGHT) and Vector2(fixture.position.x - light.position.x, fixture.position.z - light.position.z).length() < 0.01, "PadFixture does not hang under the ceiling above the PadLight")
	_expect(failures, block.size.x <= 0.5 and block.size.z <= 0.5, "PadFixture is %.1f x %.1f m: a small light gets a small block" % [block.size.x, block.size.z])
	root.remove_child(room)
	room.free()
	return failures

#endregion

#region Player

func test_walk(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step)
	var player: CharacterBody3D = main.get_node("Level").player
	var start := player.global_position
	_expect(failures, player.is_on_floor(), "player is not on the floor at the start")
	_expect(failures, start.distance_to(Vector3(0.0, 0.0, 3.5)) < 0.05, "player starts at %s, expected 1.5 m inside room 0 at (0, 0, 3.5)" % start)
	_expect(failures, (-player.global_basis.z).is_equal_approx(Vector3.FORWARD), "player does not face the way the chain starts")

	# 45 frames at 5 m/s: 3.75 m, still short of the first door's trigger.
	Input.action_press("move_forward")
	await _wait_physics(45)
	Input.action_release("move_forward")
	var moved := player.global_position - start
	_expect(failures, moved.dot(-player.global_basis.z) > 3.5, "moved only %.2f m forward" % moved.dot(-player.global_basis.z))
	_expect(failures, absf(moved.x) < 0.1, "drifted %.2f m sideways" % moved.x)
	_expect(failures, absf(player.global_position.y) < 0.05, "left the floor (y = %.3f)" % player.global_position.y)

	# Relative to the facing: turned right by a quarter, forward now goes along +x.
	player.rotation.y = -PI / 2.0
	var before := player.global_position
	Input.action_press("move_forward")
	await _wait_physics(30)
	Input.action_release("move_forward")
	var turned := player.global_position - before
	_expect(failures, turned.x > 2.0 and absf(turned.z) < 0.1, "facing right, forward moved %s" % turned)
	await _unload(main)
	return failures

func test_jump(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step)
	var player: CharacterBody3D = main.get_node("Level").player
	var camera: Camera3D = player.get_node("Head/Camera3D")
	var capsule := (player.get_node("CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D
	var ceiling_bottom := _ceiling_bottom(_rooms_of(main.get_node("Level"))[0])
	Input.action_press("jump")
	await _wait_physics(2)
	Input.action_release("jump")
	var highest := 0.0
	var highest_eye := 0.0
	for i in 30:
		await physics_frame
		highest = maxf(highest, player.global_position.y)
		highest_eye = maxf(highest_eye, camera.global_position.y)
	_expect(failures, highest > 0.8 and highest < 1.2, "highest point %.2f m, expected about 1.03" % highest)
	_expect(failures, highest + capsule.height < ceiling_bottom, "the head reaches %.2f m at the top of the jump, the ceiling is at %.2f m" % [highest + capsule.height, ceiling_bottom])
	_expect(failures, highest_eye < ceiling_bottom - 0.2, "the eye reaches %.2f m at the top of the jump, the ceiling is at %.2f m (0.2 m for the near plane)" % [highest_eye, ceiling_bottom])
	await _wait_physics(60)
	_expect(failures, player.is_on_floor(), "player did not land")
	_expect(failures, absf(player.global_position.y) < 0.05, "landed at y = %.3f" % player.global_position.y)
	await _unload(main)
	return failures

func test_sealed_entrance(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step)
	var player: CharacterBody3D = main.get_node("Level").player
	player.rotation.y = PI # look at the entrance wall
	Input.action_press("move_forward")
	await _wait_physics(90)
	Input.action_release("move_forward")
	# The wall's inner face is at z = 4.8 (0.2 m thick, flush with the footprint) and the capsule radius is 0.4 m.
	_expect(failures, player.global_position.z > 4.2 and player.global_position.z < 4.55, "stopped at z = %.2f, expected about 4.4" % player.global_position.z)
	_expect(failures, absf(player.global_position.y) < 0.05, "left the floor (y = %.3f)" % player.global_position.y)
	await _unload(main)
	return failures

func test_stick_look(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step)
	var player: CharacterBody3D = main.get_node("Level").player
	var head: Node3D = player.get_node("Head")

	# 3 rad/s for one second turns the body by about 3 rad (right is negative yaw).
	Input.action_press("look_right")
	await _wait_physics(60)
	Input.action_release("look_right")
	var turned := wrapf(-player.rotation.y, -PI, PI)
	_expect(failures, absf(turned - 3.0) < 0.15, "the stick turned the body by %.2f rad in 1 s" % turned)
	_expect(failures, is_zero_approx(head.rotation.x), "yaw moved the head pitch")

	Input.action_press("look_down")
	await _wait_physics(60)
	Input.action_release("look_down")
	_expect(failures, is_equal_approx(head.rotation.x, -deg_to_rad(89.0)), "looking down: pitch %.1f deg" % rad_to_deg(head.rotation.x))
	Input.action_press("look_up")
	await _wait_physics(120)
	Input.action_release("look_up")
	_expect(failures, is_equal_approx(head.rotation.x, deg_to_rad(89.0)), "looking up: pitch %.1f deg" % rad_to_deg(head.rotation.x))
	_expect(failures, is_zero_approx(player.rotation.x) and is_zero_approx(player.rotation.z), "pitch tilted the body")
	await _unload(main)
	return failures

func test_mouse_math(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step)
	var player: CharacterBody3D = main.get_node("Level").player
	var head: Node3D = player.get_node("Head")
	var sensitivity: float = player.get("mouse_sensitivity")
	_expect(failures, is_equal_approx(sensitivity, 0.002), "sensitivity is %f rad per pixel" % sensitivity)
	var yaw := player.rotation.y
	player.call("rotate_view", Vector2(100.0, 0.0) * sensitivity)
	_expect(failures, is_equal_approx(player.rotation.y - yaw, -0.2), "100 px right turned the body by %.3f rad, expected -0.2" % (player.rotation.y - yaw))
	_expect(failures, is_zero_approx(head.rotation.x), "yaw moved the head pitch")
	player.call("rotate_view", Vector2(0.0, 100000.0) * sensitivity)
	_expect(failures, is_equal_approx(head.rotation.x, -deg_to_rad(89.0)), "mouse down: pitch %.1f deg" % rad_to_deg(head.rotation.x))
	player.call("rotate_view", Vector2(0.0, -200000.0) * sensitivity)
	_expect(failures, is_equal_approx(head.rotation.x, deg_to_rad(89.0)), "mouse up: pitch %.1f deg" % rad_to_deg(head.rotation.x))
	_expect(failures, is_zero_approx(player.rotation.x), "pitch tilted the body")
	await _unload(main)
	return failures

#endregion

#region Doors

func test_door(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step)
	var level: Node3D = main.get_node("Level")
	var player: CharacterBody3D = level.player
	var room: Node3D = level.rooms[0]
	var door: Node3D = room.get("door")
	_unlock_by_hand(door) # step 2 locks room 0 for the key tests; this test is about the swing
	var door_point := (room.get("exit") as Marker3D).global_transform
	var opened_at: Array[float] = []
	door.connect("opened", func() -> void: opened_at.append(_depth(player, door_point)))

	var leaf := door.get_node_or_null("Hinge/Leaf") # from step 3 the kit's door leaf, before it a box mesh
	var slab := (leaf.find_children("*", "MeshInstance3D", true, false)[0] if leaf != null else door.get_node("Hinge/MeshInstance3D")) as MeshInstance3D
	var slab_material := slab.mesh.surface_get_material(0) if leaf != null else (slab.mesh as BoxMesh).material
	_expect(failures, slab_material != null and slab_material.resource_path == MATERIAL_DIR + "door.tres", "the door panel is not the accent material res://materials/door.tres")
	_expect(failures, not door.get("is_open"), "the door starts open")
	_expect(failures, _door_blocks(level, door_point), "the closed door lets a ray pass")
	await _wait_physics(10)
	_expect(failures, not door.get("is_open"), "the door opened by itself")

	# Walk up to it: it opens while the player is still a few metres away.
	Input.action_press("move_forward")
	for i in 150:
		await physics_frame
		if door.get("is_open"):
			break
	Input.action_release("move_forward")
	_expect(failures, door.get("is_open"), "the door did not open on approach")
	_expect(failures, opened_at.size() == 1, "`opened` was emitted %d times" % opened_at.size())
	if opened_at.size() == 1:
		_expect(failures, opened_at[0] < -2.5 and opened_at[0] > -4.2, "the door opened when the player was %.2f m away" % -opened_at[0])

	# Open: the hinge is turned 90 degrees and a ray passes through the doorway.
	await _wait_physics(40)
	var hinge: Node3D = door.get("hinge")
	_expect(failures, absf(hinge.rotation.y - (-PI / 2.0)) < 0.02, "the open door is at %.1f deg" % rad_to_deg(hinge.rotation.y))
	_expect(failures, not _door_blocks(level, door_point), "the open doorway blocks a ray")
	_expect(failures, not _door_blocks(level, door_point, 0.5), "the open doorway blocks a ray 0.5 m off the middle")

	# Closed again: it blocks the ray and the player.
	door.call("close")
	await _wait_physics(40)
	_expect(failures, not door.get("is_open"), "the door is still open after close()")
	_expect(failures, absf(hinge.rotation.y) < 0.02, "the closed door is at %.1f deg" % rad_to_deg(hinge.rotation.y))
	_expect(failures, _door_blocks(level, door_point), "the closed door lets a ray pass")
	Input.action_press("move_forward")
	await _wait_physics(90)
	Input.action_release("move_forward")
	var depth := _depth(player, door_point)
	_expect(failures, depth < -0.3 and depth > -0.65, "walking into the closed door stopped %.2f m before it" % -depth)
	await _unload(main)
	return failures

## True if a ray through the doorway at the exit is stopped by the door. sideways moves it off the middle.
func _door_blocks(level: Node3D, door_point: Transform3D, sideways := -0.3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(door_point * Vector3(sideways, RAY_HEIGHT, 1.0), door_point * Vector3(sideways, RAY_HEIGHT, -2.0))
	query.exclude = [(level.player as CollisionObject3D).get_rid()]
	return not level.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

## How far the player is in front of the exit plane; negative before it.
func _depth(player: Node3D, door_point: Transform3D) -> float:
	return (player.global_position - door_point.origin).dot(-door_point.basis.z)

func test_door_waits_for_the_swing(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step)
	var level: Node3D = main.get_node("Level")
	var player: CharacterBody3D = level.player
	var room: Node3D = level.rooms[0]
	var door: Node3D = room.get("door")
	_unlock_by_hand(door)
	var door_point := (room.get("exit") as Marker3D).global_transform
	var hinge: Node3D = door.get("hinge")

	# Walk into the doorway, the door opening on the way.
	Input.action_press("move_forward")
	for i in 240:
		await physics_frame
		if _depth(player, door_point) > 0.5:
			break
	Input.action_release("move_forward")
	_expect(failures, _depth(player, door_point) > 0.5, "the player did not get through the doorway")
	await _wait_physics(20)

	# Asked to close while the player is in the swing: nothing happens.
	door.call("close")
	await _wait_physics(45)
	_expect(failures, door.get("is_open") and absf(hinge.rotation.y + PI / 2.0) < 0.02, "the door closed on the player (hinge at %.1f deg)" % rad_to_deg(hinge.rotation.y))

	# Out of the swing: it closes, and the player was not touched.
	Input.action_press("move_forward")
	await _wait_physics(60)
	Input.action_release("move_forward")
	var before := player.global_position
	await _wait_physics(60)
	_expect(failures, not door.get("is_open") and absf(hinge.rotation.y) < 0.02, "the door did not close after the player left (hinge at %.1f deg)" % rad_to_deg(hinge.rotation.y))
	_expect(failures, player.global_position.distance_to(before) < 0.01, "the closing door moved the player by %.3f m" % player.global_position.distance_to(before))
	await _unload(main)
	return failures

## The open leaf stands in the next room, 1.6 m long, right where the way leads on. A player pressed against its face who slides
## past its free end must keep moving. On GodotPhysics3D a capsule whose axis stood a tenth of a millimetre past the end of the
## leaf's box was held in place for good (the box has a blind spot at its end edge, the one contact that is still reported is
## the floor's, and every move has zero travel). The projects run Jolt, which has no such blind spot; this guards the setting.
func test_open_leaf_end(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step)
	var level: Node3D = main.get_node("Level")
	var player: CharacterBody3D = level.player
	var door: Node3D = level.rooms[0].get("door")
	door.call("open")
	await _wait_physics(45) # the swing takes half a second
	door.set_physics_process(false) # the leaf stays open, whatever the probes do
	var hinge: Node3D = door.get("hinge")
	_expect(failures, absf(hinge.rotation.y + PI / 2.0) < 0.02, "the leaf is not open (%.1f deg)" % rad_to_deg(hinge.rotation.y))
	var radius := ((player.get_node("CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D).radius
	var face_x := 0.8 - 0.05 # the door's frame: the hinge sits at x = 0.8, the leaf is 0.1 thick and runs 1.6 m into the room (-z)
	var end_z := -1.6
	var yaw := atan2(-0.8, 0.6) # facing +x and on into the room, as the autopilot does when the exit is on the right
	var held: Array[String] = []
	var probes := 0
	for beyond_mm: float in [0.0, 0.05, 0.1]: # how far the capsule's axis stands past the end of the leaf
		for apart_mm: float in [0.0, 0.1, 0.2]: # how far its side is from the face
			var spot := Vector3(face_x - radius - apart_mm / 1000.0, 0.0, end_z - beyond_mm / 1000.0)
			player.global_transform = door.global_transform * Transform3D(Basis(Vector3.UP, yaw), spot)
			player.velocity = Vector3.ZERO
			await _wait_physics(2)
			var before := player.global_position
			Input.action_press("move_forward")
			await _wait_physics(10)
			Input.action_release("move_forward")
			probes += 1
			var moved := Vector2(player.global_position.x - before.x, player.global_position.z - before.z).length()
			if moved < 0.3:
				held.append("%.2f mm past the end, %.1f mm from the face: moved %.4f m" % [beyond_mm, apart_mm, moved])
	_expect(failures, held.is_empty(), "the player was held in place in %d of %d probes: %s" % [held.size(), probes, held.slice(0, 3)])
	await _unload(main)
	return failures

## The autopilot walks the finished game from the first door to the goal for seeds 1-200. It has no eyes and never steers around
## anything, so a place where the player can be held for good shows up as a run that stops moving (this is how the end of the open
## door leaf was found: on GodotPhysics3D seeds 83, 90, 189 and 197 stopped there, 17 and 60 with other drivers). A run is about
## 3600 physics ticks, so the seeds are split over SWEEP_WORKERS processes (tools/sweep_seeds.gd), each at 8 times real time (the
## engine's limit of 8 physics steps per frame; faster, Jolt warns about running out of jobs). A seed walks the same way in any of them.
func test_autopilot_seed_sweep() -> Array[String]:
	var failures: Array[String] = []
	DirAccess.make_dir_recursive_absolute(_save_dir)
	var per_worker := ceili(float(SWEEP_SEEDS) / SWEEP_WORKERS)
	var workers: Array[Dictionary] = []
	for index in SWEEP_WORKERS:
		var first := index * per_worker + 1
		var last := mini(first + per_worker - 1, SWEEP_SEEDS)
		if first > last:
			continue
		var out := _save_dir.path_join("sweep_%d.txt" % index)
		DirAccess.remove_absolute(out)
		var arguments := ["--headless", "--quiet", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://tools/sweep_seeds.gd", "--", "--from=%d" % first, "--to=%d" % last, "--out=%s" % out]
		var pid := OS.create_process(OS.get_executable_path(), arguments)
		_expect(failures, pid > 0, "could not start the sweep for seeds %d-%d" % [first, last])
		workers.append({"pid": pid, "out": out, "first": first, "last": last})
	while workers.any(func(worker: Dictionary) -> bool: return worker["pid"] > 0 and OS.is_process_running(worker["pid"])):
		await create_timer(1.0).timeout
	var held: Array[String] = []
	var walked := 0
	var longest := 0
	for worker in workers:
		var text := FileAccess.get_file_as_string(worker["out"])
		var lines := text.strip_edges().split("\n", false)
		_expect(failures, lines.size() > 0 and lines[-1] == "done", "the sweep for seeds %d-%d did not finish (%d lines in %s)" % [worker["first"], worker["last"], lines.size(), worker["out"]])
		for line in lines:
			var parts := line.split(" ")
			if parts[0] == "ok":
				walked += 1
				longest = maxi(longest, int(parts[2]))
			elif parts[0] == "held":
				walked += 1
				held.append("seed %s: held in room %s at %s after %s ticks" % [parts[1], parts[2], " ".join(parts.slice(3, parts.size() - 1)), parts[-1]])
		DirAccess.remove_absolute(worker["out"])
	_expect(failures, walked == SWEEP_SEEDS, "%d of %d seeds were walked" % [walked, SWEEP_SEEDS])
	_expect(failures, held.is_empty(), "%d of %d seeds did not reach the goal: %s" % [held.size(), SWEEP_SEEDS, held.slice(0, 4)])
	print("        seeds 1-%d: the longest run took %d ticks (%.1f s of game time)" % [SWEEP_SEEDS, longest, longest / 60.0])
	return failures

#endregion

#region Streaming with the real player

## Per-frame checks while the autopilot walks through the chain.
class Watcher extends RefCounted:
	var level: Node3D
	var pilot: RefCounted
	var failures: Array[String] = []
	var frame := 0
	var max_live := 0
	var max_step := 0.0
	var passed := {} ## Door index -> true once the player crossed its plane.
	var clear_since := {} ## Door index -> frame when the player was clear of the swing.
	var verified_closed := {} ## Door index -> true once checked closed and blocking.
	var checked_current := 0
	var current_since := 0 ## Frame when the player entered the room the player is in.
	var _last_position := Vector3.ZERO

	func _init(watched_level: Node3D, watched_pilot: RefCounted) -> void:
		level = watched_level
		pilot = watched_pilot
		_last_position = (watched_level.player as Node3D).global_position

	func fail(message: String) -> void:
		if failures.size() < 12:
			failures.append("frame %d: %s" % [frame, message])

	func check() -> void:
		frame += 1
		var player: CharacterBody3D = level.player
		var rooms: Dictionary = level.rooms
		var plans: Array = level.chain.plans ## Plans of the step under test, a class of its own.
		max_live = maxi(max_live, rooms.size())
		if rooms.size() > 3:
			fail("%d live rooms" % rooms.size())
		if plans.size() > int(level.current) + 2:
			fail("%d plans made while the player is in room %d" % [plans.size(), level.current])

		# Never pushed through a wall: always inside a live room, on the floor, no jumps in position.
		var inside := false
		for index: int in rooms.keys():
			if plans[index].bounds.grow(0.2).has_point(player.global_position):
				inside = true
		if not inside:
			fail("player at %s is outside every live room" % player.global_position)
		if player.global_position.y < -0.1 or player.global_position.y > 0.3:
			fail("player at height %.2f" % player.global_position.y)
		var step := player.global_position.distance_to(_last_position)
		max_step = maxf(max_step, step)
		if step > 0.2:
			fail("the player moved %.2f m in one physics frame, from %s to %s" % [step, _last_position, player.global_position])
		_last_position = player.global_position

		# The next room exists, and the door is open, before the player passes the door.
		var target: int = pilot.door_index
		if pilot.depth_at(target) >= 0.0 and not passed.has(target):
			passed[target] = true
			if not rooms.has(target + 1):
				fail("room %d did not exist when the player passed door %d" % [target + 1, target])
			elif not rooms[target].door.is_open:
				fail("door %d was closed when the player passed it" % target)

		# The door behind closes once the player is clear of the swing, and then it blocks.
		for index: int in rooms.keys():
			if index >= level.current or verified_closed.has(index):
				continue
			var depth: float = pilot.depth_at(index)
			if depth > 2.6 and not clear_since.has(index):
				clear_since[index] = frame
			if clear_since.has(index) and frame - int(clear_since[index]) > 45:
				verified_closed[index] = true
				var door: Node3D = rooms[index].door
				var door_point := (rooms[index].exit as Marker3D).global_transform
				if door.is_open or absf(door.hinge.rotation.y) > 0.02:
					fail("door %d is still open %d frames after the player cleared it" % [index, frame - int(clear_since[index])])
				var query := PhysicsRayQueryParameters3D.create(door_point * Vector3(-0.3, 1.2, -1.0), door_point * Vector3(-0.3, 1.2, 1.0))
				query.exclude = [player.get_rid()]
				if level.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
					fail("door %d is closed but a ray passes it" % index)

		# Rooms behind the previous one are gone: from the dictionary, and, three frames on, from the tree.
		if level.current != checked_current:
			checked_current = level.current
			current_since = frame
		for index: int in rooms.keys():
			if index < level.current - 1:
				fail("room %d still exists while the player is in room %d" % [index, level.current])
		if frame - current_since == 3:
			var in_tree := 0
			for child in level.get_children():
				if child.get("entrance") != null:
					in_tree += 1
			if in_tree != rooms.size():
				fail("%d room nodes in the tree for %d live rooms" % [in_tree, rooms.size()])

func test_streaming(step: String) -> Array[String]:
	var main := await _load_step(step)
	var level: Node3D = main.get_node("Level")
	var pilot := Autopilot.new(level)
	var watcher := Watcher.new(level, pilot)
	_fast_forward(true)

	_expect(watcher.failures, level.rooms.size() == 1, "%d rooms before the player moved" % level.rooms.size())
	var arrived := await _walk(level, pilot, STREAM_ROOMS, 0, watcher.check)
	_expect(watcher.failures, arrived, "the player did not reach room %d (stuck in room %d after %d frames)" % [STREAM_ROOMS, level.current, watcher.frame])
	# Keep walking so the last door can close behind the player.
	var frames_left := [150]
	await _drive(func() -> bool:
		pilot.physics_step()
		watcher.check()
		frames_left[0] -= 1
		return frames_left[0] <= 0)
	pilot.release()
	_fast_forward(false)

	_expect(watcher.failures, watcher.max_live == 3, "at most %d rooms were live at once, expected 3" % watcher.max_live)
	_expect(watcher.failures, watcher.max_step < 0.2, "the player moved %.2f m in one physics frame" % watcher.max_step)
	_expect(watcher.failures, watcher.passed.size() >= STREAM_ROOMS - 1, "the player passed only %d doors" % watcher.passed.size())
	_expect(watcher.failures, watcher.verified_closed.size() >= STREAM_ROOMS - 2, "only %d doors were seen closing behind the player" % watcher.verified_closed.size())
	var live: Array[Node3D] = _rooms_of(level)
	_expect(watcher.failures, live.size() == level.rooms.size() and live.size() <= 3, "%d room nodes in the tree for %d live rooms" % [live.size(), level.rooms.size()])
	for i in range(live.size() - 1):
		var exit_point: Transform3D = (live[i].get("exit") as Marker3D).global_transform
		var entrance: Transform3D = (live[i + 1].get("entrance") as Marker3D).global_transform
		_expect(watcher.failures, exit_point.origin.distance_to(entrance.origin) < 1e-4 and exit_point.basis.is_equal_approx(entrance.basis), "live rooms %d and %d are not snapped" % [i, i + 1])
	# Walking back builds nothing: the door behind is shut and the plans stay as they are.
	var plan_count: int = level.chain.plans.size()
	var seed_plans := _level_plans(step, level.chain_seed, plan_count, level)
	_expect(watcher.failures, _same_plans(level.chain.plans, seed_plans), "the streamed plans differ from the pure-data chain")
	Input.action_press("move_back")
	await _wait_physics(120)
	Input.action_release("move_back")
	_expect(watcher.failures, level.chain.plans.size() == plan_count, "walking back made %d new plans" % (level.chain.plans.size() - plan_count))
	await _unload(main)
	return watcher.failures

## The pure-data chain of a step, with the level's goal room and lock chance.
func _level_plans(step: String, chain_seed: int, count: int, level: Node3D) -> Array:
	var chain: RefCounted = _chain_script(step).new(chain_seed, level.get("goal_room"), level.get("lock_chance"))
	for i in count:
		chain.next_plan()
	return chain.plans

## Calls its callback once per physics tick, before the player's own tick.
class Driver extends Node:
	signal finished
	var tick: Callable

	func _physics_process(_delta: float) -> void:
		if tick.is_valid() and tick.call():
			tick = Callable()
			finished.emit()

## Runs tick once per physics tick until it returns true. (With Engine.time_scale above 1
## several ticks happen per frame, and `await physics_frame` would only see one of them.)
func _drive(tick: Callable) -> void:
	var driver := Driver.new()
	driver.process_priority = -100
	driver.tick = tick
	root.add_child(driver)
	await driver.finished
	root.remove_child(driver)
	driver.queue_free()

## Walks until the player is in room `goal`. dawdle: ticks of standing still at the start and at every new door.
func _walk(level: Node3D, pilot: RefCounted, goal: int, dawdle: int, on_tick: Callable) -> bool:
	var state := {"budget": 1500 * goal, "wait": dawdle, "target": pilot.door_index}
	await _drive(func() -> bool:
		if state["wait"] > 0:
			state["wait"] -= 1
		else:
			pilot.physics_step()
			if pilot.door_index != state["target"]:
				state["target"] = pilot.door_index
				state["wait"] = dawdle
				pilot.release()
		if on_tick.is_valid():
			on_tick.call()
		state["budget"] -= 1
		return level.current >= goal or state["budget"] <= 0)
	pilot.release()
	return level.current >= goal

## Walks until the run is FINISHED (the player stands on the goal pad). dawdle: ticks of standing
## still at every new door after the first, which makes the run slower. Returns true if it finished.
func _walk_to_finish(level: Node3D, pilot: RefCounted, dawdle := 0, budget := 40000, on_tick := Callable()) -> bool:
	var state := {"budget": budget, "wait": 0, "target": pilot.door_index}
	await _drive(func() -> bool:
		if state["wait"] > 0:
			state["wait"] -= 1
		else:
			pilot.physics_step()
			if pilot.door_index != state["target"]:
				state["target"] = pilot.door_index
				state["wait"] = dawdle
				pilot.release()
		if on_tick.is_valid():
			on_tick.call()
		state["budget"] -= 1
		return level.state == STATE_FINISHED or state["budget"] <= 0)
	pilot.release()
	return level.state == STATE_FINISHED

func test_timing_independence(step: String) -> Array[String]:
	var failures: Array[String] = []
	_fast_forward(true)
	for dawdle: int in [0, 30, 200]:
		var main := await _load_step(step)
		var level: Node3D = main.get_node("Level")
		var pilot := Autopilot.new(level)
		var arrived := await _walk(level, pilot, 7, dawdle, Callable())
		_expect(failures, arrived, "dawdle %d: did not reach room 7" % dawdle)
		var made: Array = level.chain.plans
		_expect(failures, made.size() >= 8, "dawdle %d: only %d plans" % [dawdle, made.size()])
		_expect(failures, _same_plans(made, _level_plans(step, level.chain_seed, made.size(), level)), "dawdle %d: the streamed plans differ from the pure-data chain" % dawdle)
		await _unload(main)
	_fast_forward(false)
	return failures

#endregion

#region Debug map

func test_toggle_map(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step)
	var map: Control = main.get_node("HUD/DebugMap")
	_expect(failures, map.get_parent() is CanvasLayer, "the map is not under a CanvasLayer")
	_expect(failures, map.visible, "the map does not start visible")
	_expect(failures, map.mouse_filter == Control.MOUSE_FILTER_IGNORE, "the map takes mouse input")
	_expect(failures, map.position.is_equal_approx(Vector2(16.0, 16.0)) and map.size.is_equal_approx(Vector2(300.0, 300.0)), "the map is %s at %s, expected 300x300 at the top left" % [map.size, map.position])
	await _action("toggle_debug")
	_expect(failures, not map.visible, "Tab did not hide the map")
	await _action("toggle_debug")
	_expect(failures, map.visible, "Tab did not show the map again")
	await _unload(main)
	return failures

func test_map_reads_data_only(step: String) -> Array[String]:
	var failures: Array[String] = []
	var source := FileAccess.get_file_as_string("res://steps/%s/debug_map.gd" % step)
	for forbidden: String in ["get_node", "get_tree", "find_child", "get_children", "$", "Physics"]:
		_expect(failures, not source.contains(forbidden), "debug_map.gd uses `%s`" % forbidden)
	_expect(failures, source.contains("level.chain.plans") and source.contains("level.rooms"), "debug_map.gd does not draw the plan history")
	return failures

#endregion

#region Step 1: the room counter

func test_counter(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step)
	var level: Node3D = main.get_node("Level")
	var label: Label = main.get_node("HUD/Stats/RoomLabel")
	_expect(failures, label.text == "Room 0 / 20", "the counter reads \"%s\" at the start, expected \"Room 0 / 20\"" % label.text)
	_expect(failures, level.get("goal_room") == 20, "goal_room is %s, expected 20" % level.get("goal_room"))

	# Every room the player enters: the signal comes with the index, and the label has the new text at once.
	var entered: Array[int] = []
	var texts: Array[String] = []
	level.connect("room_entered", func(index: int) -> void:
		entered.append(index)
		texts.append(label.text))
	_fast_forward(true)
	var pilot := Autopilot.new(level)
	var arrived := await _walk(level, pilot, 4, 0, Callable())
	_fast_forward(false)
	_expect(failures, arrived, "the player did not reach room 4")
	_expect(failures, entered == [1, 2, 3, 4], "room_entered was sent for %s, expected [1, 2, 3, 4]" % [entered])
	_expect(failures, texts == ["Room 1 / 20", "Room 2 / 20", "Room 3 / 20", "Room 4 / 20"], "the counter read %s" % [texts])
	_expect(failures, label.text == "Room 4 / 20", "the counter reads \"%s\" in room 4" % label.text)

	await _unload(main)

	# Readable at 1080p and at the project's 720p, inside the screen, clear of the map, on the right.
	main = await _load_step(step)
	for screen_size: Vector2i in [Vector2i(1920, 1080), Vector2i(1280, 720)]:
		await _set_screen(screen_size)
		var stats: Control = main.get_node("HUD/Stats")
		var map: Control = main.get_node("HUD/DebugMap")
		label = main.get_node("HUD/Stats/RoomLabel")
		label.text = "Room 20 / 20" # the widest text the counter shows
		await process_frame
		var screen := Rect2(Vector2.ZERO, Vector2(screen_size))
		var where := "at %dx%d" % [screen_size.x, screen_size.y]
		_expect(failures, label.get_theme_font_size("font_size") >= 32, "the counter font is %d px, too small for 1080p" % label.get_theme_font_size("font_size"))
		_expect(failures, label.get_theme_constant("outline_size") >= 4, "the counter has no outline: it can vanish on a bright wall")
		_expect(failures, screen.encloses(stats.get_global_rect()), "%s: the counter %s is not inside the screen" % [where, stats.get_global_rect()])
		_expect(failures, stats.get_global_rect().end.x <= screen.end.x - 8.0 and stats.get_global_rect().position.y >= 8.0, "%s: the counter is closer than 8 px to the screen corner" % where)
		_expect(failures, stats.get_global_rect().position.x > screen.size.x / 2.0, "%s: the counter is not on the right" % where)
		_expect(failures, not stats.get_global_rect().intersects(map.get_global_rect()), "%s: the counter overlaps the map" % where)
		_expect(failures, label.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT, "the counter is not right aligned")
		_expect(failures, label.get_minimum_size().x <= stats.size.x, "\"Room 20 / 20\" needs %.0f px, the box is %.0f px wide" % [label.get_minimum_size().x, stats.size.x])
	await _unload(main)
	return failures

#endregion

#region Step 2: the goal room in the level

## Goal room 3: the autopilot walks into it and onto the pad.
func test_goal_in_level(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step, true, {"goal_room": SHORT_GOAL})
	var level: Node3D = main.get_node("Level")
	var pilot := Autopilot.new(level)
	_fast_forward(true)
	var arrived := await _walk(level, pilot, SHORT_GOAL, 0, Callable())
	_expect(failures, arrived, "the player did not reach the goal room %d" % SHORT_GOAL)
	var plans: Array = level.chain.plans
	_expect(failures, plans.size() == SHORT_GOAL + 1 and plans[SHORT_GOAL].type == _goal_type(_chain_script(step)), "%d plans, the last is type %d" % [plans.size(), plans[-1].type])
	var room: Node3D = level.rooms[SHORT_GOAL]
	_expect(failures, room.scene_file_path.ends_with("room_goal.tscn"), "room %d is %s" % [SHORT_GOAL, room.scene_file_path])
	_expect(failures, room.get("door") == null and room.get("exit") == null, "the goal room has a door or an exit")
	_expect(failures, level.rooms.size() == 2 and level.rooms.has(SHORT_GOAL - 1), "%d rooms live in the goal room" % level.rooms.size())
	_expect(failures, level.get("goal_room") == SHORT_GOAL and level.chain.goal_index == SHORT_GOAL, "goal_room %s, goal_index %d" % [level.get("goal_room"), level.chain.goal_index])
	_expect(failures, room.get("goal_pad") != null and room.get("goal_pad") == room.get_node("GoalPad"), "the room does not point at its goal pad")

	# On: walk onto the pad. The player steps up onto it and stands inside its edges.
	var pad := room.get_node("GoalPad") as Node3D
	var player: CharacterBody3D = level.player
	var budget := [1200]
	await _drive(func() -> bool:
		pilot.physics_step()
		budget[0] -= 1
		var to_pad := Vector2(player.global_position.x - pad.global_position.x, player.global_position.z - pad.global_position.z)
		return to_pad.length() < 0.4 or level.get("state") == STATE_FINISHED or budget[0] <= 0)
	pilot.release()
	await _wait_physics(10)
	_fast_forward(false)
	var on_pad := Vector2(player.global_position.x - pad.global_position.x, player.global_position.z - pad.global_position.z).abs()
	_expect(failures, on_pad.x < 1.5 and on_pad.y < 1.5, "the player is %s from the middle of the pad" % on_pad)
	_expect(failures, absf(player.global_position.y - 0.12) < 0.02, "the player stands at y = %.3f, the pad top is 0.12" % player.global_position.y)
	await _unload(main)
	return failures

#endregion

#region Step 3: game states

func test_state_enum() -> Array[String]:
	var failures: Array[String] = []
	for step in STEPS:
		var constants := (load("res://steps/%s/level.gd" % step) as GDScript).get_script_constant_map()
		var states: Dictionary = constants.get("State", {})
		_expect(failures, states.get("READY") == STATE_READY and states.get("RUNNING") == STATE_RUNNING and states.get("FINISHED") == STATE_FINISHED and states.size() == 3, "%s: State is %s" % [step, states])
	return failures

func test_states(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step, true, {"goal_room": SHORT_GOAL})
	var level: Node3D = main.get_node("Level")
	var player: CharacterBody3D = level.player
	var changes: Array[int] = []
	level.connect("state_changed", func(new_state: int) -> void: changes.append(new_state))
	var door: Node3D = level.rooms[0].get("door")
	_unlock_by_hand(door) # step 2 locks room 0 for the key tests; the first door is meant to open here
	var state_when_opened: Array[int] = []
	door.connect("opened", func() -> void: state_when_opened.append(level.state))

	# READY in room 0, also while the player walks towards the door.
	_expect(failures, level.state == STATE_READY, "state %d at the start, expected READY" % level.state)
	Input.action_press("move_forward")
	await _wait_physics(30)
	Input.action_release("move_forward")
	_expect(failures, level.state == STATE_READY and changes.is_empty(), "walking in room 0 changed the state to %d" % level.state)

	# RUNNING the moment the first door opens.
	Input.action_press("move_forward")
	for i in 150:
		await physics_frame
		if door.get("is_open"):
			break
	Input.action_release("move_forward")
	_expect(failures, door.get("is_open") and level.state == STATE_RUNNING, "the first door is open, the state is %d" % level.state)
	_expect(failures, state_when_opened == [STATE_RUNNING], "the state was %s when `opened` reached the listeners" % [state_when_opened])
	_expect(failures, changes == [STATE_RUNNING], "state changes %s, expected [RUNNING]" % [changes])
	_expect(failures, not player.get("frozen"), "the player is frozen while running")

	# Standing on the pad before the run is on is nothing: only RUNNING can finish. (Called by hand, state READY.)
	level.set("state", STATE_READY)
	level.call("_on_goal_reached", player)
	_expect(failures, level.state == STATE_READY, "the goal pad finished a run that was not RUNNING")
	level.set("state", STATE_RUNNING)

	# FINISHED when the player steps onto the pad. The other doors on the way do not start anything again.
	_fast_forward(true)
	var pilot := Autopilot.new(level)
	var finished := await _walk_to_finish(level, pilot)
	_fast_forward(false)
	_expect(failures, finished, "the run did not finish (state %d, room %d)" % [level.state, level.current])
	_expect(failures, changes == [STATE_RUNNING, STATE_FINISHED], "state changes %s, expected [RUNNING, FINISHED]" % [changes])
	_expect(failures, level.current == SHORT_GOAL, "finished in room %d, expected %d" % [level.current, SHORT_GOAL])

	# The player stops: frozen, no velocity, and nothing a person can press moves it or turns it.
	await _wait_physics(20)
	_expect(failures, player.get("frozen") == true, "the player is not frozen after the finish")
	_expect(failures, player.velocity == Vector3.ZERO, "the player moves with %s after the finish" % player.velocity)
	var position := player.global_position
	var yaw := player.rotation.y
	var pitch := (player.get_node("Head") as Node3D).rotation.x
	for action: String in ["move_forward", "move_left", "jump", "look_right", "look_down"]:
		Input.action_press(action)
	await _wait_physics(60)
	for action: String in ["move_forward", "move_left", "jump", "look_right", "look_down"]:
		Input.action_release(action)
	_expect(failures, player.global_position.distance_to(position) < 0.001, "the player moved %.3f m after the finish" % player.global_position.distance_to(position))
	_expect(failures, player.rotation.y == yaw and (player.get_node("Head") as Node3D).rotation.x == pitch, "the view turned after the finish")
	_expect(failures, player.velocity == Vector3.ZERO, "the player has velocity %s" % player.velocity)
	_expect(failures, changes.size() == 2, "state changes %s after the finish" % [changes])

	# A player who is in the air at the finish comes down instead of hanging there.
	player.global_position.y += 1.0
	await _wait_physics(60)
	_expect(failures, player.is_on_floor() and player.global_position.y < 0.2, "the frozen player stays in the air (y = %.2f)" % player.global_position.y)

	# The panel: visible at the finish, saying "Finished!".
	var panel: Control = main.get_node("HUD/FinishPanel")
	_expect(failures, panel.visible, "the finish panel is not visible")
	_expect(failures, (main.get_node("HUD/FinishPanel/Rows/FinishTitle") as Label).text == "Finished!", "the panel says \"%s\"" % (main.get_node("HUD/FinishPanel/Rows/FinishTitle") as Label).text)
	await _unload(main)
	return failures

func test_finish_panel(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step, true, {"goal_room": SHORT_GOAL})
	var level: Node3D = main.get_node("Level")
	var panel: Control = main.get_node("HUD/FinishPanel")
	_expect(failures, not panel.visible, "the finish panel is visible before the finish")
	_expect(failures, panel.get_parent() == main.get_node("HUD") and main.get_node("HUD") is CanvasLayer, "the panel is not on the HUD layer")
	_expect(failures, panel.mouse_filter == Control.MOUSE_FILTER_IGNORE, "the panel takes mouse input")

	_fast_forward(true)
	var finished := await _walk_to_finish(level, Autopilot.new(level))
	_fast_forward(false)
	_expect(failures, finished, "the run did not finish")
	_expect(failures, panel.visible, "the panel is hidden after the finish")
	var title: Label = main.get_node("HUD/FinishPanel/Rows/FinishTitle")
	_expect(failures, title.get_theme_font_size("font_size") >= 48, "the title is %d px" % title.get_theme_font_size("font_size"))
	for screen_size: Vector2i in [Vector2i(1920, 1080), Vector2i(1280, 720)]:
		await _set_screen(screen_size)
		var screen := Vector2(screen_size)
		var centre := panel.get_global_rect().get_center()
		_expect(failures, centre.distance_to(screen / 2.0) < 2.0, "%dx%d: the panel is centred at %s, the screen centre is %s" % [screen_size.x, screen_size.y, centre, screen / 2.0])
		_expect(failures, Rect2(Vector2.ZERO, screen).encloses(panel.get_global_rect()), "%dx%d: the panel %s does not fit the screen" % [screen_size.x, screen_size.y, panel.get_global_rect()])
	await _unload(main)
	return failures

#endregion

#region Step 4: the run timer

func test_format_time() -> Array[String]:
	var failures: Array[String] = []
	var cases: Dictionary[float, String] = {
		0.0: "0:00.0",
		0.04: "0:00.0",
		0.1: "0:00.1",
		5.0: "0:05.0",
		42.37: "0:42.3",
		59.96: "0:59.9",
		60.0: "1:00.0",
		125.04: "2:05.0",
		599.99: "9:59.9",
		3600.0: "60:00.0",
	}
	for step in STEPS:
		var hud := load("res://steps/%s/hud.gd" % step) as GDScript
		for seconds in cases:
			var text: String = hud.call("format_time", seconds)
			_expect(failures, text == cases[seconds], "%s: format_time(%s) is \"%s\", expected \"%s\"" % [step, seconds, text, cases[seconds]])
	return failures

func test_timer(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step, true, {"goal_room": SHORT_GOAL})
	var level: Node3D = main.get_node("Level")
	var time_label: Label = main.get_node("HUD/Stats/TimeLabel")
	_expect(failures, level.run_time == 0.0 and time_label.text == "0:00.0", "run_time %s, label \"%s\" at the start" % [level.run_time, time_label.text])
	_expect(failures, time_label.get_theme_font_size("font_size") >= 32, "the timer font is too small for 1080p")

	# READY: the clock does not move, however long the player stands there.
	await _wait_physics(60)
	_expect(failures, level.run_time == 0.0, "the clock moved to %s in READY" % level.run_time)

	# RUNNING: exactly the sum of the physics deltas, whatever the wall clock does. The driver runs before
	# the level on every tick and also stalls the real clock by 25 ms on every fifth tick.
	var door: Node3D = level.rooms[0].get("door")
	door.call("open")
	_expect(failures, level.state == STATE_RUNNING, "opening the door did not start the run")
	var ticks := {"count": 0, "sum": 0.0, "mismatch": 0, "start": 0.0, "wall_start": Time.get_ticks_msec()}
	await _drive(func() -> bool:
		# Before its own tick the level has added every delta that came before this one. (The level
		# had one tick of its own between open() and the driver's first tick: that is the start value.)
		if ticks["count"] == 0:
			ticks["start"] = level.run_time
		if absf(level.run_time - ticks["start"] - ticks["sum"]) > 1e-9:
			ticks["mismatch"] += 1
		ticks["sum"] += _tick_delta()
		ticks["count"] += 1
		if ticks["count"] % 5 == 0:
			OS.delay_msec(25)
		return ticks["count"] >= 121)
	var wall_ms := Time.get_ticks_msec() - int(ticks["wall_start"])
	_expect(failures, ticks["mismatch"] == 0, "the clock differed from the sum of the physics deltas on %d ticks" % ticks["mismatch"])
	_expect(failures, ticks["start"] <= _tick_delta() * 1.5, "the clock was already at %s when the driver started" % ticks["start"])
	_expect(failures, absf(level.run_time - ticks["start"] - 120.0 / 60.0) < 1e-6, "120 physics ticks gave %.6f s, expected 2.0" % (level.run_time - ticks["start"]))
	_expect(failures, wall_ms >= 500, "the test did not stall the wall clock (%d ms)" % wall_ms)

	# The label shows the clock.
	await _wait_physics(2)
	_expect(failures, time_label.text == str(load("res://steps/%s/hud.gd" % step).call("format_time", level.run_time)), "the label says \"%s\" for %.3f s" % [time_label.text, level.run_time])

	# The clock stops at the finish; the panel shows the final time.
	_fast_forward(true)
	var finished := await _walk_to_finish(level, Autopilot.new(level))
	_fast_forward(false)
	_expect(failures, finished, "the run did not finish")
	var at_finish: float = level.run_time
	await _wait_physics(90)
	_expect(failures, level.run_time == at_finish, "the clock kept running after the finish (%.3f to %.3f)" % [at_finish, level.run_time])
	var expected: String = load("res://steps/%s/hud.gd" % step).call("format_time", at_finish)
	_expect(failures, (main.get_node("HUD/FinishPanel/Rows/FinishTime") as Label).text == expected, "the panel shows \"%s\", expected \"%s\"" % [(main.get_node("HUD/FinishPanel/Rows/FinishTime") as Label).text, expected])
	_expect(failures, time_label.text == expected, "the corner shows \"%s\", expected \"%s\"" % [time_label.text, expected])
	await _unload(main)
	return failures

## The delta every node gets in a physics tick: the engine's tick length times the time scale.
func _tick_delta() -> float:
	return Engine.time_scale / float(Engine.physics_ticks_per_second)

#endregion

#region Restart

## R is the same seed again, N is seed + 1 (tutorial 03's steps 5 and 6, here every step). Both reset everything through start().
func test_restart(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step, true, {"goal_room": SHORT_GOAL})
	var level: Node3D = main.get_node("Level")
	var player: CharacterBody3D = level.player
	var room_label: Label = main.get_node("HUD/Stats/RoomLabel")
	var time_label: Label = main.get_node("HUD/Stats/TimeLabel")
	var panel: Control = main.get_node("HUD/FinishPanel")
	_expect(failures, InputMap.has_action("next_seed"), "no next_seed action in the input map")
	var keys: Array[String] = []
	var buttons: Array[int] = []
	for event in InputMap.action_get_events("next_seed"):
		if event is InputEventKey:
			keys.append(OS.get_keycode_string((event as InputEventKey).physical_keycode))
		elif event is InputEventJoypadButton:
			buttons.append((event as InputEventJoypadButton).button_index)
	_expect(failures, keys == ["N"] and buttons == [JOY_BUTTON_RIGHT_SHOULDER], "next_seed is %s and %s, expected N and the right shoulder" % [keys, buttons])

	# A run in progress: two rooms in, the clock running.
	_fast_forward(true)
	var pilot := Autopilot.new(level)
	var arrived := await _walk(level, pilot, 2, 0, Callable())
	_fast_forward(false)
	await _wait_physics(10)
	_expect(failures, arrived and level.state == STATE_RUNNING and level.run_time > 1.5, "the run did not get going (state %d, %.1f s)" % [level.state, level.run_time])
	var first_run: Array = level.chain.plans.duplicate()

	# R: the same seed, a fresh run.
	await _action("regenerate")
	await _wait_physics(10)
	_expect(failures, level.chain_seed == 42, "seed is %d after R, expected 42" % level.chain_seed)
	failures.append_array(_fresh_run_problems(step, main, 42))
	_expect(failures, _same_plans(level.chain.plans, first_run.slice(0, 1)), "the first plan after R is not the same room 0")

	# The same seed, the same run: walk it again, the plans are the ones of the first run.
	_fast_forward(true)
	pilot = Autopilot.new(level)
	arrived = await _walk(level, pilot, 2, 0, Callable())
	_fast_forward(false)
	_expect(failures, arrived, "the second run did not reach room 2")
	var second_run: Array = level.chain.plans
	var shared := mini(first_run.size(), second_run.size())
	_expect(failures, shared >= 3 and _same_plans(first_run.slice(0, shared), second_run.slice(0, shared)), "R did not give the same rooms")

	# N: seed + 1.
	await _action("next_seed")
	await _wait_physics(10)
	_expect(failures, level.chain_seed == 43, "seed is %d after N, expected 43" % level.chain_seed)
	failures.append_array(_fresh_run_problems(step, main, 43))
	await _action("next_seed")
	await _wait_physics(10)
	_expect(failures, level.chain_seed == 44, "second N: seed is %d, expected 44" % level.chain_seed)
	failures.append_array(_fresh_run_problems(step, main, 44))
	await _action("regenerate")
	await _wait_physics(10)
	_expect(failures, level.chain_seed == 44, "R after N: seed is %d, expected 44" % level.chain_seed)

	# After a finish: R and N both give the player back.
	_fast_forward(true)
	pilot = Autopilot.new(level)
	var finished := await _walk_to_finish(level, pilot)
	_fast_forward(false)
	_expect(failures, finished and panel.visible and player.get("frozen") == true, "the run did not finish before the restart")
	await _action("regenerate")
	await _wait_physics(10)
	failures.append_array(_fresh_run_problems(step, main, 44))
	_fast_forward(true)
	finished = await _walk_to_finish(level, Autopilot.new(level))
	_fast_forward(false)
	_expect(failures, finished, "the second run did not finish")
	await _action("next_seed")
	await _wait_physics(10)
	failures.append_array(_fresh_run_problems(step, main, 45))
	# And the new run plays: input works again.
	var before := player.global_position
	Input.action_press("move_forward")
	await _wait_physics(20)
	Input.action_release("move_forward")
	_expect(failures, player.global_position.distance_to(before) > 1.0, "the player does not move after the restart")
	_expect(failures, room_label.text == "Room 0 / %d" % SHORT_GOAL and time_label.text == "0:00.0", "the HUD reads \"%s\" and \"%s\" after the restart" % [room_label.text, time_label.text])
	await _unload(main)
	return failures

## What a fresh run looks like, from any earlier state: seed, plans, rooms, counter, clock, state, player, panel.
func _fresh_run_problems(step: String, main: Node, expected_seed: int) -> Array[String]:
	var problems: Array[String] = []
	var level: Node3D = main.get_node("Level")
	var player: CharacterBody3D = level.player
	var label := "%s seed %d" % [step, expected_seed]
	_expect(problems, level.chain_seed == expected_seed, "%s: seed is %d" % [label, level.chain_seed])
	_expect(problems, _same_plans(level.chain.plans, _level_plans(step, expected_seed, 1, level)), "%s: room 0 is not the pure-data chain's" % label)
	_expect(problems, level.rooms.size() == 1 and level.rooms.has(0) and level.current == 0, "%s: %d live rooms, current %d" % [label, level.rooms.size(), level.current])
	_expect(problems, _rooms_of(level).size() == 1, "%s: %d room nodes in the tree" % [label, _rooms_of(level).size()])
	_expect(problems, level.state == STATE_READY and level.run_time == 0.0, "%s: state %d, clock %s" % [label, level.state, level.run_time])
	_expect(problems, not level.rooms[0].door.is_open, "%s: door 0 is open" % label)
	_expect(problems, player.global_position.distance_to(Vector3(0.0, 0.0, 3.5)) < 0.05 and player.is_on_floor(), "%s: the player is at %s" % [label, player.global_position])
	_expect(problems, player.get("frozen") == false and player.velocity == Vector3.ZERO, "%s: the player is frozen or moving" % label)
	_expect(problems, (main.get_node("HUD/Stats/RoomLabel") as Label).text == "Room 0 / %d" % level.goal_room, "%s: the counter reads \"%s\"" % [label, (main.get_node("HUD/Stats/RoomLabel") as Label).text])
	_expect(problems, (main.get_node("HUD/Stats/TimeLabel") as Label).text == "0:00.0", "%s: the clock reads \"%s\"" % [label, (main.get_node("HUD/Stats/TimeLabel") as Label).text])
	_expect(problems, not (main.get_node("HUD/FinishPanel") as Control).visible, "%s: the finish panel is still up" % label)
	if level.get("new_best") != null:
		_expect(problems, level.get("new_best") == false, "%s: new_best is still set" % label)
	if level.get("keys") != null:
		_expect(problems, level.keys == 0 and (main.get_node("HUD/Stats/KeysLabel") as Label).text == "Keys 0", "%s: keys %d, label \"%s\"" % [label, level.keys, (main.get_node("HUD/Stats/KeysLabel") as Label).text])
		_expect(problems, _keys_in(level.rooms[0]).is_empty(), "%s: %d keys in room 0" % [label, _keys_in(level.rooms[0]).size()])
	return problems

## The reset has one home. Every statement that undoes a run is in start(), and only there.
func test_reset_in_one_place() -> Array[String]:
	var failures: Array[String] = []
	for step in STEPS:
		var source := FileAccess.get_file_as_string("res://steps/%s/level.gd" % step)
		var start_at := source.find("func start() -> void:")
		var start_end := source.find("\nfunc ", start_at + 1)
		var start_body := source.substr(start_at, start_end - start_at)
		var statements: Array[String] = ["rooms.clear()", "current = 0", "run_time = 0.0", "chain = Chain.new(", "_set_state(State.READY)"]
		statements.append("new_best = false")
		statements.append("keys = 0")
		for statement in statements:
			_expect(failures, start_body.contains(statement), "%s: start() does not contain `%s`" % [step, statement])
			_expect(failures, source.count(statement) == 1, "%s: `%s` appears %d times in level.gd, expected once (in start())" % [step, statement, source.count(statement)])
		_expect(failures, start_body.contains("room_entered.emit(current)"), "%s: start() does not announce room 0" % step)
		_expect(failures, start_body.contains("keys_changed.emit(keys)"), "%s: start() does not announce the keys" % step)
		# The input only picks the seed and calls start().
		var input_at := source.find("func _unhandled_input(")
		var input_end := source.find("\nfunc ", input_at + 1)
		var input_body := source.substr(input_at, input_end - input_at)
		_expect(failures, input_body.count("start()") == 2 and input_body.count("seed_text = Seeds.next_text(seed_text)") == 1 and input_body.contains("if typing:"), "%s: _unhandled_input does more than pick a seed and call start(), or listens while the seed box is up" % step)
		_expect(failures, start_body.contains("seed_text = Seeds.normalize(seed_text)") and start_body.contains("chain_seed = Seeds.parse(seed_text)") and start_body.contains("seed_changed.emit(seed_text)"), "%s: start() does not make the seed canonical, turn it into its number and announce it" % step)
		_expect(failures, source.count("chain_seed = ") == 1 and source.count("seed_text = ") == 3, "%s: the seed is set in more places than start(), use_seed() and N (chain_seed %d, seed_text %d)" % [step, source.count("chain_seed = "), source.count("seed_text = ")])
		for statement: String in ["rooms.clear()", "run_time", "player.", "current = ", "_set_state"]:
			_expect(failures, not input_body.contains(statement), "%s: _unhandled_input touches `%s`" % [step, statement])
	return failures

#endregion

#region Step 6: best times

func test_best_round_trip() -> Array[String]:
	var failures: Array[String] = []
	var path := _fresh_save_path()
	var times := BestTimes.new(path)
	_expect(failures, times.best(42) == BestTimes.NO_TIME, "a new list has a time for seed 42")
	_expect(failures, times.submit(42, 39.8167), "the first time of a seed is a best")
	_expect(failures, FileAccess.file_exists(path), "no file after the first submit")
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	_expect(failures, data is Dictionary, "the file is not a JSON object")
	if data is Dictionary:
		_expect(failures, (data as Dictionary).get("formatVersion") == 1.0, "formatVersion is %s" % (data as Dictionary).get("formatVersion"))
		var best_times: Dictionary = (data as Dictionary).get("bestTimes", {})
		_expect(failures, best_times == {"42": 39.817}, "bestTimes is %s, expected {\"42\": 39.817}" % [best_times])
	var again := BestTimes.new(path)
	_expect(failures, again.best(42) == 39.817, "reloaded: %s" % again.best(42))
	_expect(failures, again.best(43) == BestTimes.NO_TIME, "seed 43 has a time")
	_expect(failures, times.submit(-5, 12.0) and BestTimes.new(path).best(-5) == 12.0, "a negative seed does not round trip")
	_expect(failures, BestTimes.new(path).best(42) == 39.817, "seed 42 was lost when seed -5 was saved")
	return failures

func test_best_only_faster() -> Array[String]:
	var failures: Array[String] = []
	var path := _fresh_save_path()
	var times := BestTimes.new(path)
	times.submit(42, 50.0)
	_expect(failures, not times.submit(42, 60.0), "a slower time counted as a best")
	_expect(failures, not times.submit(42, 50.0), "an equal time counted as a best")
	_expect(failures, not times.submit(42, 50.0004), "a time that rounds to the same millisecond counted as a best")
	_expect(failures, times.best(42) == 50.0, "the best changed to %s" % times.best(42))
	_expect(failures, BestTimes.new(path).best(42) == 50.0, "the file changed with a slower time")
	_expect(failures, times.submit(42, 49.999), "a faster time did not count")
	_expect(failures, times.best(42) == 49.999 and BestTimes.new(path).best(42) == 49.999, "the faster time was not kept")
	_expect(failures, times.submit(43, 90.0) and times.best(43) == 90.0 and times.best(42) == 49.999, "seeds are not independent")
	_expect(failures, BestTimes.new(path).best(43) == 90.0 and BestTimes.new(path).best(42) == 49.999, "the file lost a seed")
	return failures

func test_best_missing_file() -> Array[String]:
	var failures: Array[String] = []
	var path := _fresh_save_path()
	var times := BestTimes.new(path)
	_expect(failures, times.best(1) == BestTimes.NO_TIME and times.best(42) == BestTimes.NO_TIME, "an empty list has times")
	_expect(failures, not FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".bad") and not FileAccess.file_exists(path + ".tmp"), "loading a missing file wrote something")
	return failures

func test_best_damaged_file() -> Array[String]:
	var failures: Array[String] = []
	var damaged: Array[String] = [
		"{\"formatVersion\": 1, \"bestTimes\": {\"42\": 39.", # cut off in the middle of a write
		"", # empty
		"[1, 2, 3]", # valid JSON, not an object
		"\"just text\"",
		"42",
		"not json at all <<<",
		"{\"formatVersion\": 1, \"bestTimes\": [1, 2]}", # an object, but the list is not one
		"{\"formatVersion\": 1, \"bestTimes\": \"x\"}",
	]
	for text in damaged:
		var path := _fresh_save_path()
		_write_file(path, text)
		var times := BestTimes.new(path) # must not crash
		_expect(failures, times.best(42) == BestTimes.NO_TIME, "damaged %s: a time was invented" % [text])
		_expect(failures, FileAccess.file_exists(path + ".bad") and FileAccess.get_file_as_string(path + ".bad") == text, "damaged %s: not kept as .bad, unchanged" % [text])
		_expect(failures, not FileAccess.file_exists(path), "damaged %s: the damaged file is still in place" % [text])
		# The list works again, and the damaged copy stays as it was.
		_expect(failures, times.submit(42, 41.5) and BestTimes.new(path).best(42) == 41.5, "damaged %s: a new time was not saved" % [text])
		_expect(failures, FileAccess.get_file_as_string(path + ".bad") == text, "damaged %s: .bad changed when the new list was saved" % [text])
	return failures

func test_best_unknown_keys() -> Array[String]:
	var failures: Array[String] = []
	var path := _fresh_save_path()
	_write_file(path, JSON.stringify({
		"formatVersion": 3,
		"writtenBy": "9.9.9",
		"settings": {"volume": 0.5, "names": ["a", "b"]},
		"bestTimes": {"7": 12.5, "42": 50, "legacy": "n/a", "8": null, "9": "fast", "10": [1], "11": true},
	}))
	var times := BestTimes.new(path)
	_expect(failures, times.best(7) == 12.5 and times.best(42) == 50.0, "known times: %s and %s" % [times.best(7), times.best(42)])
	_expect(failures, times.best(8) == BestTimes.NO_TIME and times.best(9) == BestTimes.NO_TIME and times.best(10) == BestTimes.NO_TIME and times.best(11) == BestTimes.NO_TIME, "an odd entry counted as a time")
	_expect(failures, not times.submit(42, 51.0), "a slower time replaced an int time")
	_expect(failures, times.submit(42, 40.0), "a faster time did not replace an int time")
	_expect(failures, times.submit(9, 30.0), "a time for a seed with an odd entry was not stored")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	_expect(failures, data.get("writtenBy") == "9.9.9", "writtenBy is gone")
	_expect(failures, data.get("settings") == {"volume": 0.5, "names": ["a", "b"]}, "settings is %s" % [data.get("settings")])
	_expect(failures, data.get("formatVersion") == 3.0, "the format version went from 3 to %s" % data.get("formatVersion"))
	var best: Dictionary = data.get("bestTimes", {})
	_expect(failures, best.get("7") == 12.5 and best.get("42") == 40.0 and best.get("9") == 30.0, "bestTimes is %s" % [best])
	_expect(failures, best.get("legacy") == "n/a" and best.has("8") and best.get("8") == null and best.get("10") == [1.0] and best.get("11") == true, "odd entries did not survive: %s" % [best])
	_expect(failures, best.size() == 7, "bestTimes has %d entries, expected 7" % best.size())
	# A file without a version gets the version of this writer.
	var plain := _fresh_save_path()
	_write_file(plain, "{\"bestTimes\": {\"1\": 5.0}}")
	var plain_times := BestTimes.new(plain)
	plain_times.submit(2, 6.0)
	var plain_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(plain))
	_expect(failures, plain_data.get("formatVersion") == 1.0 and (plain_data.get("bestTimes") as Dictionary).size() == 2, "a file without a version: %s" % [plain_data])
	return failures

func test_best_atomic_write() -> Array[String]:
	var failures: Array[String] = []
	var path := _fresh_save_path()
	# A temp file left behind by a crash does no harm.
	_write_file(path + ".tmp", "{\"half written")
	var times := BestTimes.new(path)
	_expect(failures, times.best(42) == BestTimes.NO_TIME, "a stale temp file was read")
	_expect(failures, times.submit(42, 33.0), "the save failed with a stale temp file")
	_expect(failures, not FileAccess.file_exists(path + ".tmp"), "the temp file is still there after the save")
	_expect(failures, BestTimes.new(path).best(42) == 33.0, "the saved file does not load")
	# The old file is replaced whole: a second save still leaves a loadable file and no temp file.
	times.submit(42, 32.0)
	_expect(failures, not FileAccess.file_exists(path + ".tmp") and BestTimes.new(path).best(42) == 32.0, "the second save left a broken state")
	# The source goes temp file first, then rename (not delete then move, not a write in place).
	var source := FileAccess.get_file_as_string("res://steps/step_05_quality_switch/best_times.gd")
	_expect(failures, source.contains("\".tmp\"") and source.contains("rename_absolute") and source.contains("flush()"), "best_times.gd does not write a temp file, flush it and rename it")
	_expect(failures, not source.contains("remove_absolute") and not source.contains("DirAccess.remove"), "best_times.gd deletes a file")
	return failures

func test_best_write_failure() -> Array[String]:
	var failures: Array[String] = []
	var path := _save_dir.path_join("no-such-folder").path_join("best_times.json")
	var times := BestTimes.new(path)
	_expect(failures, times.submit(42, 40.0), "a failed save lost the time")
	_expect(failures, times.best(42) == 40.0, "the time is not kept in memory after a failed save")
	_expect(failures, not FileAccess.file_exists(path), "a file appeared in a folder that does not exist")
	return failures

## The label in the corner for the current seed, and how N changes it.
func test_best_label() -> Array[String]:
	var failures: Array[String] = []
	var path := _fresh_save_path()
	_write_file(path, JSON.stringify({"formatVersion": 1, "bestTimes": {"42": 39.8, "43": 70.25}}))
	var main := await _load_step(FINAL_STEP, true, {"save_path": path})
	var level: Node3D = main.get_node("Level")
	var label: Label = main.get_node("HUD/Stats/BestLabel")
	_expect(failures, label.text == "Best 0:39.8", "the label reads \"%s\" for seed 42" % label.text)
	_expect(failures, label.get_theme_font_size("font_size") >= 32 and label.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT, "the best label is not like the other labels")
	await _action("next_seed")
	await _wait_physics(5)
	_expect(failures, level.chain_seed == 43 and label.text == "Best 1:10.2", "seed %d: the label reads \"%s\", expected \"Best 1:10.2\"" % [level.chain_seed, label.text])
	await _action("next_seed")
	await _wait_physics(5)
	_expect(failures, level.chain_seed == 44 and label.text == "Best -:--.-", "seed %d: the label reads \"%s\", expected \"Best -:--.-\"" % [level.chain_seed, label.text])
	await _action("regenerate")
	await _wait_physics(5)
	_expect(failures, level.chain_seed == 44 and label.text == "Best -:--.-", "R changed the label to \"%s\"" % label.text)
	# All three labels fit the right side of the screen without touching the map.
	for screen_size: Vector2i in [Vector2i(1920, 1080), Vector2i(1280, 720)]:
		await _set_screen(screen_size)
		var stats: Control = main.get_node("HUD/Stats")
		var screen := Rect2(Vector2.ZERO, Vector2(screen_size))
		_expect(failures, screen.encloses(stats.get_global_rect()) and not stats.get_global_rect().intersects((main.get_node("HUD/DebugMap") as Control).get_global_rect()), "%dx%d: the stats box %s does not fit" % [screen_size.x, screen_size.y, stats.get_global_rect()])
	await _unload(main)
	return failures

func test_best_in_level() -> Array[String]:
	var failures: Array[String] = []

	# 1. Slower than the saved time: no "New best!", the file is untouched.
	var path := _fresh_save_path()
	var before := JSON.stringify({"formatVersion": 1, "settings": {"x": 1}, "bestTimes": {"42": 0.5}}, "\t")
	_write_file(path, before)
	var main := await _load_step(FINAL_STEP, true, {"save_path": path, "goal_room": SHORT_GOAL})
	var level: Node3D = main.get_node("Level")
	var new_best: Label = main.get_node("HUD/FinishPanel/Rows/NewBest")
	_expect(failures, not new_best.visible, "\"New best!\" is visible before the finish")
	_fast_forward(true)
	var finished := await _walk_to_finish(level, Autopilot.new(level))
	_fast_forward(false)
	_expect(failures, finished, "run 1 did not finish")
	_expect(failures, level.new_best == false and not new_best.visible, "a slower run says \"New best!\"")
	_expect(failures, FileAccess.get_file_as_string(path) == before, "a slower run changed the file")
	_expect(failures, (main.get_node("HUD/Stats/BestLabel") as Label).text == "Best 0:00.5", "the label reads \"%s\"" % (main.get_node("HUD/Stats/BestLabel") as Label).text)
	await _unload(main)

	# 2. Faster than the saved time: "New best!", saved, unknown keys kept.
	path = _fresh_save_path()
	_write_file(path, JSON.stringify({"formatVersion": 1, "settings": {"x": 1}, "bestTimes": {"42": 999.0, "7": 5.5}}))
	main = await _load_step(FINAL_STEP, true, {"save_path": path, "goal_room": SHORT_GOAL})
	level = main.get_node("Level")
	new_best = main.get_node("HUD/FinishPanel/Rows/NewBest")
	_fast_forward(true)
	finished = await _walk_to_finish(level, Autopilot.new(level))
	_fast_forward(false)
	_expect(failures, finished, "run 2 did not finish")
	var run_time: float = level.run_time
	_expect(failures, level.new_best == true and new_best.visible and new_best.text == "New best!", "a faster run does not say \"New best!\"")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	_expect(failures, absf((saved.bestTimes as Dictionary).get("42", 0.0) - run_time) < 0.0006, "saved %s, the run took %.4f s" % [(saved.bestTimes as Dictionary).get("42"), run_time])
	_expect(failures, (saved.bestTimes as Dictionary).get("7") == 5.5 and saved.get("settings") == {"x": 1.0}, "other entries did not survive: %s" % [saved])
	var best_text := "Best " + str(load("res://steps/step_05_quality_switch/hud.gd").call("format_time", BestTimes.new(path).best(42)))
	_expect(failures, (main.get_node("HUD/Stats/BestLabel") as Label).text == best_text, "the label reads \"%s\", expected \"%s\"" % [(main.get_node("HUD/Stats/BestLabel") as Label).text, best_text])
	var first_best := BestTimes.new(path).best(42)

	# 3. Restart, the same seed again but slower (the player waits at every door): not a best, the file stays.
	await _action("regenerate")
	await _wait_physics(10)
	_expect(failures, not new_best.visible and level.new_best == false, "\"New best!\" is still up after R")
	_fast_forward(true)
	finished = await _walk_to_finish(level, Autopilot.new(level), 90)
	_fast_forward(false)
	_expect(failures, finished, "run 3 did not finish")
	_expect(failures, level.run_time > run_time + 2.0, "the slow run took %.1f s, the first %.1f s" % [level.run_time, run_time])
	_expect(failures, level.new_best == false and not new_best.visible, "a slower second run says \"New best!\"")
	_expect(failures, BestTimes.new(path).best(42) == first_best, "the slower run replaced the best")

	# 4. Another seed has its own list: its first run is a best, and seed 42 is not touched.
	await _action("next_seed")
	await _wait_physics(10)
	_expect(failures, level.chain_seed == 43 and (main.get_node("HUD/Stats/BestLabel") as Label).text == "Best -:--.-", "seed 43 starts with a best time")
	_fast_forward(true)
	finished = await _walk_to_finish(level, Autopilot.new(level))
	_fast_forward(false)
	_expect(failures, finished and level.new_best == true and new_best.visible, "the first run of seed 43 is not a new best")
	_expect(failures, BestTimes.new(path).best(43) > 0.0 and BestTimes.new(path).best(42) == first_best, "seed 43 or seed 42 is wrong in the file")
	await _unload(main)
	return failures

#endregion

#region Full run

func test_full_run() -> Array[String]:
	var failures: Array[String] = []
	var path := _fresh_save_path()
	var main := await _load_step(FINAL_STEP, true, {"save_path": path})
	var level: Node3D = main.get_node("Level")
	var pilot := Autopilot.new(level)
	var changes: Array[int] = []
	level.connect("state_changed", func(new_state: int) -> void: changes.append(new_state))
	var key_counts: Array[int] = []
	level.connect("keys_changed", func(count: int) -> void: key_counts.append(count))
	var blocked := [0]
	level.connect("door_blocked", func() -> void: blocked[0] += 1)
	var built := [_props_in(level.rooms[0]).size()] # the props the rooms were built with, room 0 first
	level.connect("room_entered", func(index: int) -> void: built[0] += _props_in(level.rooms[index]).size())
	var vault_height := [0.0] # the highest the player stood in a vault: over the platform
	var on_tick := func() -> void:
		if level.chain.plans[level.current].type == Chain.Type.VAULT:
			vault_height[0] = maxf(vault_height[0], level.player.global_position.y)
	_expect(failures, level.chain_seed == 42 and level.goal_room == 20, "seed %d, goal room %d, expected 42 and 20" % [level.chain_seed, level.goal_room])
	_fast_forward(true)
	var started := Time.get_ticks_msec()
	var finished := await _walk_to_finish(level, pilot, 0, 60 * 60 * 5, on_tick)
	_fast_forward(false)
	var wall := (Time.get_ticks_msec() - started) / 1000.0
	_expect(failures, finished, "the run did not finish (state %d, room %d, %.1f s)" % [level.state, level.current, level.run_time])
	_expect(failures, changes == [STATE_RUNNING, STATE_FINISHED], "state changes %s" % [changes])
	_expect(failures, level.current == 20 and level.chain.goal_index == 20 and level.chain.plans.size() == 21, "finished in room %d with %d plans (goal_index %d)" % [level.current, level.chain.plans.size(), level.chain.goal_index])
	var run_time: float = level.run_time
	# 20 rooms of 10 to 18 m at 5 m/s, a detour for every key: well under two and a half minutes for the autopilot, a person takes longer.
	_expect(failures, run_time > 30.0 and run_time < 150.0, "the run took %.1f s" % run_time)
	var locked: Array[int] = []
	var vaults: Array[int] = []
	for plan: Object in level.chain.plans:
		if plan.locked:
			locked.append(plan.index)
		if plan.type == Chain.Type.VAULT:
			vaults.append(plan.index)
	_expect(failures, locked == SEED_42_LOCKS[FINAL_STEP], "seed 42 locks rooms %s, expected %s" % [locked, SEED_42_LOCKS[FINAL_STEP]])
	_expect(failures, vaults == SEED_42_VAULTS[FINAL_STEP], "seed 42 has vaults %s, expected %s" % [vaults, SEED_42_VAULTS[FINAL_STEP]])
	var expected_keys: Array[int] = []
	for room in locked:
		expected_keys.append_array([1, 0])
	_expect(failures, key_counts == expected_keys and level.keys == 0, "the keys went %s: every locked room needs its key picked up (1) and used up (0)" % [key_counts])
	_expect(failures, blocked[0] == 0, "the autopilot was refused at %d doors: it should fetch the key first" % blocked[0])
	_expect(failures, built[0] >= 40, "only %d props were built on the way: the rooms are bare" % built[0])
	_expect(failures, vaults.is_empty() or vault_height[0] > 0.1, "the player never climbed the vault's platform (highest %.3f m)" % vault_height[0])
	print("        full run, seed 42: %.2f s of game time (%d physics ticks), %.1f s of wall time at %dx, %d props in the rooms on the way, vaults %s, locks %s" % [run_time, roundi(run_time * 60.0), wall, SPEED_UP, built[0], vaults, locked])

	var panel: Control = main.get_node("HUD/FinishPanel")
	var format_time: GDScript = load("res://steps/step_05_quality_switch/hud.gd")
	_expect(failures, panel.visible and (main.get_node("HUD/FinishPanel/Rows/FinishTitle") as Label).text == "Finished!", "the finish panel is not up")
	_expect(failures, (main.get_node("HUD/FinishPanel/Rows/FinishTime") as Label).text == str(format_time.call("format_time", run_time)), "the panel time is \"%s\"" % (main.get_node("HUD/FinishPanel/Rows/FinishTime") as Label).text)
	_expect(failures, (main.get_node("HUD/FinishPanel/Rows/NewBest") as Label).visible and level.new_best == true, "no \"New best!\" for the first run")
	_expect(failures, (main.get_node("HUD/Stats/RoomLabel") as Label).text == "Room 20 / 20", "the counter reads \"%s\"" % (main.get_node("HUD/Stats/RoomLabel") as Label).text)
	_expect(failures, (main.get_node("HUD/Stats/BestLabel") as Label).text == "Best " + str(format_time.call("format_time", run_time)), "the best label reads \"%s\"" % (main.get_node("HUD/Stats/BestLabel") as Label).text)
	_expect(failures, level.player.get("frozen") == true and level.player.velocity == Vector3.ZERO, "the player is not stopped")
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	_expect(failures, saved is Dictionary and ((saved as Dictionary).get("bestTimes", {}) as Dictionary).has("42"), "no time saved for seed 42: %s" % [saved])
	if saved is Dictionary:
		_expect(failures, absf(((saved as Dictionary).bestTimes as Dictionary).get("42", 0.0) - run_time) < 0.0006, "saved %s, the run took %.4f s" % [((saved as Dictionary).bestTimes as Dictionary).get("42"), run_time])
	_expect(failures, not level.rooms.is_empty() and level.rooms.size() <= 2, "%d rooms live at the finish" % level.rooms.size())

	# R: the same seed, same rooms again; the saved time is still there.
	await _action("regenerate")
	await _wait_physics(10)
	_expect(failures, level.chain_seed == 42 and level.state == STATE_READY and level.run_time == 0.0 and not panel.visible, "R after the finish did not start a clean run")
	_expect(failures, (main.get_node("HUD/Stats/BestLabel") as Label).text == "Best " + str(format_time.call("format_time", run_time)), "the best time is gone after R: \"%s\"" % (main.get_node("HUD/Stats/BestLabel") as Label).text)
	await _unload(main)
	return failures

#endregion

#region Graybox standard: closed rooms, materials, lighting

func test_materials() -> Array[String]:
	var failures: Array[String] = []
	var grid := load(MATERIAL_DIR + "grid_1m.png") as Texture2D
	_expect(failures, grid != null and grid.get_size() == Vector2(256.0, 256.0), "grid_1m.png is not a 256x256 texture")
	if grid == null:
		return failures

	# One tile is 1 m: a dark line on the tile border, a fainter one at 0.5 m, the same on both axes.
	var image := grid.get_image()
	var fill := image.get_pixel(100, 100)
	var half_line := image.get_pixel(127, 100)
	var tile_line := image.get_pixel(0, 100)
	_expect(failures, tile_line.r < half_line.r and half_line.r < fill.r, "grid lines: tile %.2f, half %.2f, fill %.2f" % [tile_line.r, half_line.r, fill.r])
	_expect(failures, image.get_pixel(255, 100) == tile_line and image.get_pixel(100, 0) == tile_line and image.get_pixel(100, 255) == tile_line, "the tile border line is not centred on the border")
	_expect(failures, image.get_pixel(100, 127) == half_line and image.get_pixel(100, 128) == half_line and image.get_pixel(128, 100) == half_line, "the 0.5 m line is not the same on both axes")
	_expect(failures, image.has_mipmaps(), "the grid is imported without mipmaps: it would shimmer at a distance")

	# Neutral gray floor, walls and ceiling in the midtone range (50-100 percent), floor lighter than walls.
	var targets: Dictionary[String, float] = {"floor": 0.70, "wall": 0.55, "ceiling": 0.60}
	var fills: Dictionary[String, Color] = {}
	for material_name: String in targets:
		var material := load(MATERIAL_DIR + material_name + ".tres") as StandardMaterial3D
		_expect(failures, material != null, "%s.tres is not a StandardMaterial3D" % material_name)
		if material == null:
			continue
		var shown := (material.albedo_color.srgb_to_linear() * fill.srgb_to_linear()).linear_to_srgb()
		fills[material_name] = shown
		_expect(failures, material.albedo_texture != null and material.albedo_texture.resource_path == grid.resource_path, "%s.tres does not use the shared grid" % material_name)
		_expect(failures, material.uv1_triplanar and material.uv1_world_triplanar, "%s.tres is not world triplanar" % material_name)
		_expect(failures, material.uv1_scale.is_equal_approx(Vector3.ONE), "%s.tres: uv1_scale %s, one tile must be 1 m (scale 1)" % [material_name, material.uv1_scale])
		_expect(failures, material.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL, "%s.tres is unlit" % material_name)
		_expect(failures, material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC, "%s.tres: texture_filter %d" % [material_name, material.texture_filter])
		_expect(failures, shown.r >= 0.5 and shown.r <= 1.0, "%s.tres: albedo %.2f is outside 50-100 percent" % [material_name, shown.r])
		_expect(failures, absf(shown.r - targets[material_name]) < 0.02, "%s.tres: albedo %.3f, expected about %.2f" % [material_name, shown.r, targets[material_name]])
		_expect(failures, absf(shown.r - shown.g) < 0.01 and absf(shown.r - shown.b) < 0.01, "%s.tres is not neutral gray" % material_name)
	if fills.size() == 3:
		_expect(failures, fills["floor"].r > fills["wall"].r + 0.1, "the floor must be clearly lighter than the walls (%.2f vs %.2f)" % [fills["floor"].r, fills["wall"].r])

	# The door and the goal are the warm accents, and brighter than the gray room around them (squint test).
	var wall_light := 0.0
	if fills.has("wall"):
		wall_light = (load(MATERIAL_DIR + "wall.tres") as StandardMaterial3D).albedo_color.srgb_to_linear().get_luminance() * fill.srgb_to_linear().r
	for accent: String in ["door", "goal", "key"]:
		var material := load(MATERIAL_DIR + accent + ".tres") as StandardMaterial3D
		_expect(failures, material != null, "%s.tres is not a StandardMaterial3D" % accent)
		if material == null:
			continue
		_expect(failures, material.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL, "%s.tres is unlit" % accent)
		_expect(failures, material.albedo_texture == null, "%s.tres has a texture: the accent is a flat colour" % accent)
		_expect(failures, material.albedo_color.h > 0.04 and material.albedo_color.h < 0.16 and material.albedo_color.s > 0.7 and material.albedo_color.v > 0.9, "%s.tres %s is not a saturated warm colour" % [accent, material.albedo_color])
		var light := material.albedo_color.srgb_to_linear().get_luminance()
		_expect(failures, light > 1.5 * wall_light, "%s luminance %.3f is only %.2fx the wall's %.3f" % [accent, light, light / wall_light, wall_light])
	var door := load(MATERIAL_DIR + "door.tres") as StandardMaterial3D
	var goal := load(MATERIAL_DIR + "goal.tres") as StandardMaterial3D
	if door != null and goal != null:
		_expect(failures, goal.albedo_color.h > door.albedo_color.h and goal.albedo_color.srgb_to_linear().get_luminance() > door.albedo_color.srgb_to_linear().get_luminance(), "the goal gold is not the brighter, yellower step from the door's orange")
		_expect(failures, goal.emission_enabled and goal.emission_energy_multiplier <= 1.0, "the goal does not glow softly")

	# The key is a glowing gold-orange accent, yellower than the door (a pickup, not a passage).
	var key_material := load(MATERIAL_DIR + "key.tres") as StandardMaterial3D
	if door != null and key_material != null:
		_expect(failures, key_material.emission_enabled and key_material.emission_energy_multiplier >= 0.5, "the key does not glow")
		_expect(failures, key_material.albedo_color.h > door.albedo_color.h, "the key (hue %.3f) is not yellower than the door (%.3f)" % [key_material.albedo_color.h, door.albedo_color.h])

	# The lock: dark warm iron on the door's orange. It sits ON the door, so it has to read by value against the
	# door (squint test), not against the wall; it glows only while it flashes after a refused try.
	var lock_material := load(MATERIAL_DIR + "lock.tres") as StandardMaterial3D
	_expect(failures, lock_material != null, "lock.tres is not a StandardMaterial3D")
	if lock_material != null and door != null and key_material != null:
		var lock_color := lock_material.albedo_color
		_expect(failures, lock_material.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL and lock_material.albedo_texture == null, "lock.tres is unlit or textured: the accent is a flat colour")
		_expect(failures, lock_color.r >= lock_color.g and lock_color.g >= lock_color.b and lock_color.s < 0.6, "lock.tres %s is not a dark warm iron (no hazard red)" % lock_color)
		var lock_seen := lock_color.srgb_to_linear().get_luminance() + lock_material.emission.srgb_to_linear().get_luminance() * lock_material.emission_energy_multiplier
		var door_seen := door.albedo_color.srgb_to_linear().get_luminance()
		_expect(failures, lock_seen < 0.25 * door_seen, "the lock (%.3f) does not stand out darkly against the door (%.3f)" % [lock_seen, door_seen])
		_expect(failures, lock_material.emission_enabled and lock_material.emission_energy_multiplier == 0.0, "the lock glows at rest or cannot flash")

	# The props are not interactive: neutral gray, the room's grid, but darker than the walls (about 42 percent),
	# so a crate against a wall reads in the squint test, and no accent colour: nothing that is not a door,
	# a key or the goal looks like something to use.
	var prop_material := load(MATERIAL_DIR + "prop.tres") as StandardMaterial3D
	_expect(failures, prop_material != null, "prop.tres is not a StandardMaterial3D")
	if prop_material != null and fills.has("wall"):
		var shown_prop := (prop_material.albedo_color.srgb_to_linear() * fill.srgb_to_linear()).linear_to_srgb()
		_expect(failures, prop_material.albedo_texture != null and prop_material.albedo_texture.resource_path == grid.resource_path, "prop.tres does not use the shared grid")
		_expect(failures, prop_material.uv1_triplanar and prop_material.uv1_world_triplanar and prop_material.uv1_scale.is_equal_approx(Vector3.ONE), "prop.tres is not world triplanar at one tile per metre")
		_expect(failures, prop_material.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL and prop_material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC, "prop.tres is unlit or filtered differently from the room")
		_expect(failures, shown_prop.r >= 0.40 and shown_prop.r <= 0.45, "prop.tres shows %.3f, expected 40 to 45 percent" % shown_prop.r)
		_expect(failures, absf(shown_prop.r - shown_prop.g) < 0.01 and absf(shown_prop.r - shown_prop.b) < 0.01, "prop.tres is not neutral gray")
		_expect(failures, fills["wall"].r - shown_prop.r >= 0.08 and fills["floor"].r - shown_prop.r >= 0.2, "the prop (%.2f) is not clearly darker than the wall (%.2f) and the floor (%.2f)" % [shown_prop.r, fills["wall"].r, fills["floor"].r])
		_expect(failures, not prop_material.emission_enabled, "prop.tres glows: only the key, the goal and the fixtures do")

	# The lamp block glows but is still a lit material.
	var fixture := load(MATERIAL_DIR + "fixture.tres") as StandardMaterial3D
	_expect(failures, fixture != null and fixture.emission_enabled and fixture.emission_energy_multiplier >= 1.0, "fixture.tres is not emissive")
	_expect(failures, fixture != null and fixture.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL, "fixture.tres is unlit")

	# No scene brings its own material: floors, walls, ceilings, lamps, doors and the pad all come from res://materials.
	var scenes := 0
	for step in STEPS:
		for file in _step_files(step):
			if file.ends_with(".tscn"):
				scenes += 1
				var text := FileAccess.get_file_as_string("res://steps/%s/%s" % [step, file])
				_expect(failures, not text.contains('[sub_resource type="StandardMaterial3D"') and not text.contains("albedo_color"), "%s/%s defines a material of its own" % [step, file])
	_expect(failures, scenes >= 80, "found only %d scenes" % scenes)
	return failures

func test_graybox_rooms(step: String) -> Array[String]:
	var failures: Array[String] = []
	var files: Array[String] = []
	for file in DirAccess.get_files_at("res://steps/" + step):
		if file.begins_with("room_") and file.ends_with(".tscn"):
			files.append(file)
	files.sort()
	var expected := ROOM_TYPES.size() + 1 # the rooms and the goal room
	_expect(failures, files.size() == expected, "%d room scenes, expected %d" % [files.size(), expected])

	# Far apart, so that a ray only ever sees the room it starts in.
	var holder := Node3D.new()
	root.add_child(holder)
	for i in files.size():
		var room := (load("res://steps/%s/%s" % [step, files[i]]) as PackedScene).instantiate() as Node3D
		room.position = Vector3(i * 40.0, 0.0, 0.0)
		holder.add_child(room)
	await _wait_physics(5) # the CSG shapes build their collision
	for room in holder.get_children():
		failures.append_array(_graybox_problems(room as Node3D, step))
	root.remove_child(holder)
	holder.free()
	return failures

## Everything the graybox standard asks of one room module, as problems (empty = fine).
func _graybox_problems(room: Node3D, step: String) -> Array[String]:
	var problems: Array[String] = []
	var label := room.scene_file_path.trim_prefix("res://steps/")
	var player := (load("res://steps/%s/player.tscn" % step) as PackedScene).instantiate()
	var capsule := (player.get_node("CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D
	player.free()

	var footprint := _footprint(room)
	var ceiling: Node3D = room.get_node("Ceiling")
	if _is_kit_room(room):
		problems.append_array(_kit_graybox_problems(room, label, capsule))
	else:
		problems.append_array(_csg_graybox_problems(room, label, capsule, footprint))

	# The lamp: one warm omni light near the ceiling centre without shadows, range over the whole room, paired with a visible block on layer 2.
	var light := room.get_node("RoomLight") as OmniLight3D
	var farthest := Vector3(footprint.x / 2.0, light.position.y, footprint.y / 2.0).length()
	_expect(problems, not light.shadow_enabled, "%s: RoomLight casts shadows" % label)
	_expect(problems, light.light_color.r >= light.light_color.g and light.light_color.g >= light.light_color.b and light.light_color.b < 0.95, "%s: RoomLight is not warm white" % label)
	_expect(problems, light.omni_range >= farthest, "%s: RoomLight range %.1f does not reach the far corner (%.1f m)" % [label, light.omni_range, farthest])
	_expect(problems, light.position.y > 2.2 and light.position.y < WALL_HEIGHT and absf(light.position.x) < 0.01 and absf(light.position.z) < 0.01, "%s: RoomLight is not near the ceiling centre (%s)" % [label, light.position])
	var fixture := room.get_node("Fixture") as MeshInstance3D
	var block := (fixture.mesh as BoxMesh)
	_expect(problems, fixture.layers == CEILING_LAYER, "%s: the Fixture is on layers %d, expected only layer 2" % [label, fixture.layers])
	_expect(problems, block.material != null and block.material.resource_path == MATERIAL_DIR + "fixture.tres", "%s: the Fixture does not use fixture.tres" % label)
	_expect(problems, is_equal_approx(fixture.position.y + block.size.y / 2.0, WALL_HEIGHT) and Vector2(fixture.position.x - light.position.x, fixture.position.z - light.position.z).length() < 0.01, "%s: the Fixture does not hang under the ceiling above the light" % label)

	# Closed: straight up from anywhere in the room hits the ceiling at 3.0 m, straight down the floor.
	var space := room.get_world_3d().direct_space_state
	var spots: Array[Vector2] = [Vector2.ZERO, footprint / 4.0, footprint * Vector2(-0.25, 0.25), footprint * Vector2(0.25, -0.25), -footprint / 4.0]
	for spot in spots:
		var from := room.global_position + Vector3(spot.x, 1.0, spot.y)
		var up := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3(0.0, 2.5, 0.0)))
		if up.is_empty():
			problems.append("%s: a ray straight up from (%.1f, 1, %.1f) does not hit the ceiling" % [label, spot.x, spot.y])
		else:
			var hit_y: float = up["position"].y
			_expect(problems, absf(hit_y - WALL_HEIGHT) < 0.01, "%s: the ray up from (%.1f, 1, %.1f) hits at y = %.2f, expected 3.0" % [label, spot.x, spot.y, hit_y])
			_expect(problems, up["collider"] == ceiling or ceiling.is_ancestor_of(up["collider"] as Node), "%s: the ray up hit %s, not the Ceiling" % [label, up["collider"]])
		var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3(0.0, -2.0, 0.0)))
		var floor_y := VAULT_PLATFORM_HEIGHT if label.ends_with("room_vault.tscn") and spot.length() < 0.01 else 0.0 # the vault's middle is the platform
		_expect(problems, not down.is_empty() and absf((down["position"] as Vector3).y - floor_y) < 0.01, "%s: a ray straight down from (%.1f, 1, %.1f) misses the floor" % [label, spot.x, spot.y])
	return problems

## Tutorial 07's CSG shell: one floor box, four wall boxes with their cutters, one ceiling box.
func _csg_graybox_problems(room: Node3D, label: String, capsule: CapsuleShape3D, footprint: Vector2) -> Array[String]:
	var problems: Array[String] = []
	# Floor: 0.2 m thick, its top at y = 0.
	var floor_box := room.get_node("Shell/Floor") as CSGBox3D
	_expect(problems, is_equal_approx(floor_box.size.y, SLAB_THICKNESS) and is_zero_approx(floor_box.position.y + floor_box.size.y / 2.0), "%s: the floor is %.2f m thick with its top at y = %.2f" % [label, floor_box.size.y, floor_box.position.y + floor_box.size.y / 2.0])
	_expect(problems, floor_box.material != null and floor_box.material.resource_path == MATERIAL_DIR + "floor.tres", "%s: the floor does not use floor.tres" % label)

	# Walls: 0.2 x 3.0 m, standing on the floor, flush with the footprint edge; cutters 1.6 x 2.4 m and deeper than the wall.
	for wall_name: String in ["WallEntrance", "WallFar", "WallLeft", "WallRight"]:
		var wall := room.get_node("Shell/" + wall_name) as CSGBox3D
		var along_z := wall_name.begins_with("WallE") or wall_name == "WallFar"
		var thickness := wall.size.z if along_z else wall.size.x
		var centre := absf(wall.position.z) if along_z else absf(wall.position.x)
		var half := footprint.y / 2.0 if along_z else footprint.x / 2.0
		_expect(problems, is_equal_approx(thickness, WALL_THICKNESS) and is_equal_approx(wall.size.y, WALL_HEIGHT), "%s: %s is %.2f m thick and %.2f m high" % [label, wall_name, thickness, wall.size.y])
		_expect(problems, is_zero_approx(wall.position.y - wall.size.y / 2.0), "%s: %s does not stand on the floor" % [label, wall_name])
		_expect(problems, is_equal_approx(centre + thickness / 2.0, half), "%s: %s is not flush with the footprint edge" % [label, wall_name])
		_expect(problems, wall.material != null and wall.material.resource_path == MATERIAL_DIR + "wall.tres", "%s: %s does not use wall.tres" % [label, wall_name])
		for cutter in wall.get_children():
			var hole := cutter as CSGBox3D
			var width := maxf(hole.size.x, hole.size.z)
			var depth := minf(hole.size.x, hole.size.z)
			_expect(problems, hole.operation == CSGShape3D.OPERATION_SUBTRACTION, "%s: %s/%s does not subtract" % [label, wall_name, hole.name])
			_expect(problems, is_equal_approx(width, DOORWAY_WIDTH) and is_equal_approx(hole.size.y, DOORWAY_HEIGHT), "%s: %s is %.2f x %.2f m, expected 1.6 x 2.4" % [label, hole.name, width, hole.size.y])
			_expect(problems, depth >= thickness + 0.1, "%s: %s is only %.2f m deep for a %.2f m wall" % [label, hole.name, depth, thickness])
			_expect(problems, is_zero_approx(wall.position.y + hole.position.y - hole.size.y / 2.0), "%s: %s does not start at the floor" % [label, hole.name])
			_expect(problems, hole.material != null and hole.material.resource_path == MATERIAL_DIR + "wall.tres", "%s: %s does not use wall.tres" % [label, hole.name])
			_expect(problems, width >= 2.0 * capsule.radius * 2.0 and hole.size.y >= capsule.height + 0.6, "%s: %s is too small for the player (2x width, 0.6 m head room)" % [label, hole.name])

	# Ceiling: its own CSG shape beside the Shell, 0.2 m thick on top of the walls, collision, layer 2 only.
	var ceiling := room.get_node("Ceiling") as CSGBox3D
	_expect(problems, ceiling.get_parent() == room and not ceiling.is_class("CSGCombiner3D"), "%s: the Ceiling is not a direct child of the room" % label)
	_expect(problems, ceiling.use_collision, "%s: the Ceiling has no collision" % label)
	_expect(problems, ceiling.layers == CEILING_LAYER, "%s: the Ceiling is on layers %d, expected only layer 2" % [label, ceiling.layers])
	_expect(problems, is_equal_approx(ceiling.size.y, SLAB_THICKNESS) and is_equal_approx(ceiling.position.y - ceiling.size.y / 2.0, WALL_HEIGHT), "%s: the Ceiling is %.2f m thick with its bottom at y = %.2f, expected 0.2 m at 3.0" % [label, ceiling.size.y, ceiling.position.y - ceiling.size.y / 2.0])
	_expect(problems, is_equal_approx(ceiling.size.x, footprint.x) and is_equal_approx(ceiling.size.z, footprint.y), "%s: the Ceiling does not cover the footprint" % label)
	_expect(problems, ceiling.material != null and ceiling.material.resource_path == MATERIAL_DIR + "ceiling.tres", "%s: the Ceiling does not use ceiling.tres" % label)

	return problems

## A shell of kit pieces: every piece the kit's (check_grid says where they stand), each floor tile 0.2 m thick with its top at 0,
## every wall, doorway and corner 3 m high and 0.2 m thick, every ceiling tile 0.2 m thick from 3.0 m up on layer 2 with a
## collider, each in its material; the doorways large enough for the player.
func _kit_graybox_problems(room: Node3D, label: String, capsule: CapsuleShape3D) -> Array[String]:
	var problems: Array[String] = []
	for problem in Grid.problems_of(room, label):
		problems.append(problem)
	for piece in Grid.pieces_of(room):
		var kind := Grid.kind_of(piece)
		var part := _part(room, piece)
		var box: AABB = part.box
		var where := "%s: %s" % [label, room.get_path_to(piece)]
		match kind:
			Grid.FLOOR:
				_expect(problems, _near(box.size.y, SLAB_THICKNESS) and _near(box.end.y, 0.0), "%s is %.2f m thick with its top at y = %.2f" % [where, box.size.y, box.end.y])
				_expect(problems, part.material == MATERIAL_DIR + "floor.tres", "%s does not use floor.tres" % where)
			Grid.CEILING:
				_expect(problems, _near(box.size.y, SLAB_THICKNESS) and _near(box.position.y, WALL_HEIGHT), "%s is %.2f m thick with its bottom at y = %.2f, expected 0.2 m at 3.0" % [where, box.size.y, box.position.y])
				_expect(problems, part.material == MATERIAL_DIR + "ceiling.tres", "%s does not use ceiling.tres" % where)
				for mesh in piece.find_children("*", "MeshInstance3D", true, false):
					_expect(problems, (mesh as MeshInstance3D).layers == CEILING_LAYER, "%s is on layers %d, expected only layer 2" % [where, (mesh as MeshInstance3D).layers])
				_expect(problems, not piece.find_children("*", "StaticBody3D", true, false).is_empty(), "%s has no collider" % where)
			Grid.WALL_2M, Grid.WALL_1M, Grid.DOORWAY, Grid.CORNER:
				_expect(problems, _near(box.size.y, WALL_HEIGHT) and _near(box.position.y, 0.0), "%s is %.2f m high, standing at y = %.2f" % [where, box.size.y, box.position.y])
				_expect(problems, _near(minf(box.size.x, box.size.z), WALL_THICKNESS) or kind == Grid.CORNER, "%s is %.2f m thick" % [where, minf(box.size.x, box.size.z)])
				_expect(problems, part.material == MATERIAL_DIR + "wall.tres", "%s does not use wall.tres" % where)
	_expect(problems, CheckKit.DOOR_WIDTH >= 2.0 * capsule.radius * 2.0 - 0.001 and CheckKit.DOOR_HEIGHT >= capsule.height + 0.6 - 0.001, "%s: the kit's doorway is too small for the player (2x width, 0.6 m head room)" % label)
	return problems

func test_player_camera(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step, false)
	var player: CharacterBody3D = main.get_node("Level").player
	var camera: Camera3D = player.get_node("Head/Camera3D")
	_expect(failures, camera.cull_mask == ALL_LAYERS, "the player's cull_mask is %d, expected all %d layers" % [camera.cull_mask, ALL_LAYERS])
	_expect(failures, (camera.cull_mask & CEILING_LAYER) != 0, "the player's camera does not draw layer 2: no ceiling, no lamp")
	_expect(failures, main.find_child("OverviewCamera", true, false) == null, "a cutaway camera is left in a player step")
	await _unload(main)
	return failures

## The underside of a room's ceiling, in world space.
func _ceiling_bottom(room: Node3D) -> float:
	if _is_kit_room(room): # a ceiling tile's pivot is its underside
		return (room.get_node("Ceiling").get_child(0) as Node3D).global_position.y
	var ceiling := room.get_node("Ceiling") as CSGBox3D
	return ceiling.global_position.y - ceiling.size.y / 2.0

#endregion

func test_scene_runs(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step, false)
	for i in 30:
		await process_frame
	_expect(failures, is_instance_valid(main) and main.is_inside_tree(), "scene left the tree")
	await _unload(main)
	return failures

#region Tutorial 04 (checked again): source rules

## Who knows what: the door never knows what a key is, the key never knows the level, the level never rolls dice.
func test_key_rules() -> Array[String]:
	var failures: Array[String] = []
	var keys_word := RegEx.create_from_string("\\bkeys?\\b")
	for step in STEPS:
		for line in _code_lines("res://steps/%s/door.gd" % step):
			_expect(failures, keys_word.search(line) == null, "%s/door.gd talks about keys: %s" % [step, line])
			_expect(failures, not line.contains("Level") and not line.contains("get_parent") and not line.contains("owner"), "%s/door.gd reaches for the level: %s" % [step, line])
	for step in STEPS:
		for line in _code_lines("res://steps/%s/key.gd" % step):
			_expect(failures, not line.contains("keys") and not line.contains("Level") and not line.contains("get_parent") and not line.contains("level"), "%s/key.gd reaches for the level: %s" % [step, line])
		var key_source := FileAccess.get_file_as_string("res://steps/%s/key.gd" % step)
		var process_at := key_source.find("func _process(")
		var process_end := key_source.find("\nfunc ", process_at + 1)
		var process_body := key_source.substr(process_at, process_end - process_at)
		_expect(failures, not process_body.contains("picked_up") and not process_body.contains("queue_free") and not process_body.contains("collision") and not process_body.contains("monitoring"), "%s/key.gd: _process does more than move the model" % step)
		_expect(failures, key_source.contains("model.rotation.y") and key_source.contains("model.position.y"), "%s/key.gd: the model does not spin and bob" % step)
		for forbidden: String in ["RandomNumberGenerator", "Time."]:
			_expect(failures, not key_source.contains(forbidden), "%s/key.gd uses %s" % [step, forbidden])
	# The level, the door and the room never roll dice: only the chain does.
	for step in STEPS:
		for file: String in ["level.gd", "door.gd", "room.gd", "hud.gd"]:
			_expect(failures, not FileAccess.get_file_as_string("res://steps/%s/%s" % [step, file]).contains("RandomNumberGenerator"), "%s/%s has a random generator" % [step, file])
	# The chain has four streams of dice, each in one place: _rng picks the rooms, _content_rng the locks, _prop_rng the props,
	# _lamp_rng the lamp tints. Every room starts them again from Seeds.child(seed, stream name, room number), in the function
	# that draws from them. What the chain writes down about the room types it turns down draws no dice at all.
	var own_draws := RegEx.create_from_string("(?<![_a-z])_rng\\.rand")
	for step in STEPS:
		var source := FileAccess.get_file_as_string("res://steps/%s/room_chain.gd" % step)
		var contents := _function_body(source, "func _decide_contents(")
		var rooms := _function_body(source, "func _weighted_types(")
		var props := _function_body(source, "func _decide_props(")
		var lamp := _function_body(source, "func _decide_lamp(")
		_expect(failures, source.count("_content_rng.rand") == 2 and contents.count("_content_rng.rand") == 2, "%s: _content_rng is used outside _decide_contents (%d uses)" % [step, source.count("_content_rng.rand")])
		_expect(failures, own_draws.search_all(source).size() == 1 and own_draws.search_all(rooms).size() == 1, "%s: _rng is used outside the room order" % step)
		_expect(failures, not rooms.contains("_content_rng") and not rooms.contains("_prop_rng"), "%s: the generators are mixed up" % step)
		_expect(failures, source.count("_prop_rng.") == props.count("_prop_rng.") and props.count("_prop_rng.rand") >= 1, "%s: _prop_rng is used outside _decide_props" % step)
		_expect(failures, not props.contains("_rng.rand") or props.count("_rng.rand") == props.count("_prop_rng.rand"), "%s: _decide_props draws from another generator" % step)
		_expect(failures, source.contains("const Seeds := preload(\"seeds.gd\")"), "%s: the chain does not load seeds.gd" % step)
		var init_body := _function_body(source, "func _init(")
		_expect(failures, not init_body.contains(".seed"), "%s: _init seeds a generator: every room starts its own" % step)
		_expect(failures, rooms.contains("_rng.seed = Seeds.child(_chain_seed, \"layout\", plans.size())") and source.count("_rng.seed = ") == 4, "%s: the layout stream is not started again from the seed and the room's number" % step)
		_expect(failures, contents.contains("_content_rng.seed = Seeds.child(_chain_seed, \"locks\", plan.index)"), "%s: the lock stream is not started again from the seed and the room's number" % step)
		_expect(failures, props.contains("_prop_rng.seed = Seeds.child(_chain_seed, \"props\", plan.index)"), "%s: the prop stream is not started again from the seed and the room's number" % step)
		_expect(failures, lamp.contains("_lamp_rng.seed = Seeds.child(_chain_seed, \"lamp\", plan.index)") and source.count("_lamp_rng.") == lamp.count("_lamp_rng."), "%s: the lamp stream is not started again from the seed and the room's number, or is used elsewhere" % step)
		_expect(failures, not source.contains("hash(["), "%s: the chain still calls the engine's hash()" % step)
	return failures

## The lines of a script without comments, trailing ## comments cut off.
func _code_lines(path: String) -> Array[String]:
	var lines: Array[String] = []
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var code := line.split("##")[0].strip_edges()
		if not code.is_empty() and not code.begins_with("#"):
			lines.append(code)
	return lines

## The text of one function: from its signature to the next top-level func.
func _function_body(source: String, signature: String) -> String:
	var start := source.find(signature)
	if start < 0:
		return ""
	var end := source.find("\nfunc ", start + 1)
	return source.substr(start, (end if end >= 0 else source.length()) - start)

#endregion

#region Locks and keys, step by step (tutorial 04's generator, checked in every step)

## Locks never move a room: with any lock chance the rooms of a seed are the rooms without locks. In every step.
func test_locks_keep_rooms() -> Array[String]:
	var failures: Array[String] = []
	for step: String in [STEPS[0], FINAL_STEP]:
		var chain_script := _chain_script(step)
		for chain_seed in range(1, CONTENT_SEEDS + 1):
			if chain_seed % 25 == 0:
				await process_frame
			var plain: Array = _plans_to_goal(chain_script, chain_seed, 20, 0.0).plans
			for chance: float in [LOCK_CHANCE, 1.0]:
				var first: Array = _plans_to_goal(chain_script, chain_seed, 20, chance).plans
				var second: Array = _plans_to_goal(chain_script, chain_seed, 20, chance).plans
				_expect(failures, _same_plans(first, second), "%s seed %d, chance %.1f: the same seed gives other locks, key spots or props" % [step, chain_seed, chance])
				var same_rooms := first.size() == plain.size()
				for i in mini(first.size(), plain.size()):
					if first[i].type != plain[i].type or first[i].transform != plain[i].transform or first[i].bounds != plain[i].bounds:
						same_rooms = false
				_expect(failures, same_rooms, "%s seed %d, chance %.1f: the locks moved a room" % [step, chain_seed, chance])
			if failures.size() > 8:
				return failures
	return failures

## Raising the chance only adds locks: the dice are rolled for every room, so a room that stays locked keeps its key spot.
## And a room keeps its roll whatever the goal room does further on.
func test_contents_second_stream() -> Array[String]:
	var failures: Array[String] = []
	for chain_script: GDScript in [Chain00, Chain]:
		for chain_seed in range(1, CONTENT_SEEDS + 1):
			if chain_seed % 25 == 0:
				await process_frame
			var previous: Array = []
			for chance: float in [0.1, 0.3, 0.5, 0.8, 1.0]:
				var plans: Array = _plans_to_goal(chain_script, chain_seed, 20, chance).plans
				for i in previous.size():
					if previous[i].locked:
						_expect(failures, plans[i].locked and plans[i].key_spot == previous[i].key_spot, "seed %d room %d: locked at a lower chance, but not the same at %.1f" % [chain_seed, i, chance])
				previous = plans
			var near: Array = _plans_to_goal(chain_script, chain_seed, 12, 0.5).plans
			var far: Array = _plans_to_goal(chain_script, chain_seed, 20, 0.5).plans
			for i in 11: # room 11 is the one before the near goal: always open there
				_expect(failures, near[i].locked == far[i].locked and near[i].key_spot == far[i].key_spot, "seed %d room %d: the goal room changed the roll of another room" % [chain_seed, i])
			if failures.size() > 8:
				return failures
	return failures

func test_contents_rules() -> Array[String]:
	var failures: Array[String] = []
	for chain_script: GDScript in [Chain00, Chain]:
		for goal_room: int in [1, 2, 3, 7, 20]:
			for chain_seed in range(1, 301):
				if chain_seed % 50 == 0:
					await process_frame
				var chain := _plans_to_goal(chain_script, chain_seed, goal_room, 1.0)
				var plans: Array = chain.plans
				var label := "goal %d seed %d" % [goal_room, chain_seed]
				_expect(failures, plans[-1].type == _goal_type(chain_script) and chain.goal_index == plans.size() - 1, "%s: no goal room at the end" % label)
				for plan: Object in plans:
					var forced_open: bool = plan.index == 0 or plan.index == chain.goal_index - 1 or plan.type == _goal_type(chain_script)
					if forced_open:
						_expect(failures, not plan.locked and plan.key_spot == -1, "%s: room %d (room 0, before the goal or the goal) is locked or holds a key" % [label, plan.index])
					else:
						_expect(failures, plan.locked, "%s: room %d is not locked at chance 1" % [label, plan.index])
					_expect(failures, plan.locked == (plan.key_spot >= 0), "%s: room %d: locked %s, key spot %d" % [label, plan.index, plan.locked, plan.key_spot])
					_expect(failures, plan.key_spot < chain.key_spot_count(plan.type), "%s: room %d: key spot %d of %d" % [label, plan.index, plan.key_spot, chain.key_spot_count(plan.type)])
				for plan: Object in _plans_to_goal(chain_script, chain_seed, goal_room, 0.0).plans:
					_expect(failures, not plan.locked and plan.key_spot == -1, "%s: room %d is locked at chance 0" % [label, plan.index])
				if failures.size() > 8:
					return failures
	return failures

func test_contents_statistics() -> Array[String]:
	var failures: Array[String] = []
	for step in STEPS:
		var chain_script := _chain_script(step)
		var chain := _plans_to_goal(chain_script, 42, 20)
		var locked: Array[int] = []
		var detail := ""
		for plan: Object in chain.plans:
			if plan.locked:
				locked.append(plan.index)
				detail += " room %d (%s, spot %d)" % [plan.index, _room_name(chain_script, plan.type), plan.key_spot]
		_expect(failures, locked == SEED_42_LOCKS[step], "%s: seed 42 locks rooms %s, expected %s" % [step, locked, SEED_42_LOCKS[step]])
		if step == STEPS[0] or step == FINAL_STEP:
			print("        %s: seed 42, goal room 20, lock chance %.1f: %d locked rooms:%s" % [step, LOCK_CHANCE, locked.size(), detail])

	var locked_total := 0
	var eligible_total := 0
	var spot_use := [0, 0, 0]
	for chain_seed in range(1, SEED_COUNT + 1):
		if chain_seed % 50 == 0:
			await process_frame
		var plans: Array = _plans_to_goal(Chain, chain_seed, 20).plans
		for plan: Object in plans:
			var eligible: bool = plan.index >= 1 and plan.index <= 18 # room 0 and 19 are always open, so is the goal
			eligible_total += 1 if eligible else 0
			if plan.locked:
				locked_total += 1
				spot_use[plan.key_spot] += 1
	var rate := float(locked_total) / float(eligible_total)
	print("        seeds 1-%d (finished chain): %d of %d eligible rooms locked (%.3f), key spots used %s" % [SEED_COUNT, locked_total, eligible_total, rate, spot_use])
	_expect(failures, absf(rate - LOCK_CHANCE) < 0.02, "%.3f of the eligible rooms are locked, the chance is %.1f" % [rate, LOCK_CHANCE])
	for spot in 3:
		_expect(failures, spot_use[spot] > locked_total / 4.0, "key spot %d is used in only %d of %d locked rooms" % [spot, spot_use[spot], locked_total])
	return failures

## The name of a room type in a step's Type enum ("STRAIGHT", "VAULT", "GOAL").
func _room_name(chain_script: GDScript, type: int) -> String:
	return str((chain_script.get_script_constant_map()["Type"] as Dictionary).find_key(type)).to_lower()

#endregion

#region Tutorial 04 (checked again): solvable, check_solvable.gd of step 0 and step 5

func test_solvable_seeds() -> Array[String]:
	var failures: Array[String] = []
	var locked_total := 0
	for chance: float in [LOCK_CHANCE, 1.0]:
		for chain_seed in range(1, SEED_COUNT + 1):
			if chain_seed % 50 == 0:
				await process_frame
			var chain := Solvable.build(chain_seed, 20, chance)
			for plan in chain.plans:
				locked_total += 1 if plan.locked else 0
			for problem in Solvable.problems_of(chain, Solvable.build(chain_seed, 20, 0.0)):
				failures.append("seed %d, chance %.1f: %s" % [chain_seed, chance, problem])
			if failures.size() > 8:
				return failures
	# Other goal rooms, too: close ones, and the goal room right after room 0.
	for goal_room: int in [1, 2, 3, 5, 12]:
		for chance: float in [LOCK_CHANCE, 1.0]:
			for chain_seed in range(1, CONTENT_SEEDS + 1):
				if chain_seed % 50 == 0:
					await process_frame
				for problem in Solvable.problems_of(Solvable.build(chain_seed, goal_room, chance), Solvable.build(chain_seed, goal_room, 0.0)):
					failures.append("goal %d, seed %d, chance %.1f: %s" % [goal_room, chain_seed, chance, problem])
				if failures.size() > 8:
					return failures
	print("        seeds 1-%d at lock chance %.1f and 1.0: %d locked rooms, none stuck" % [SEED_COUNT, LOCK_CHANCE, locked_total])
	return failures

## A check that never fails is worth nothing: break the plans of a good chain in each way the generator could
## go wrong, and see that the check names it.
func test_solvable_finds_faults() -> Array[String]:
	var failures: Array[String] = []
	var all_locked := Solvable.build(42, 20, 1.0)
	var plain := Solvable.build(42, 20, 0.0)
	_expect(failures, Solvable.problems_of(all_locked, plain).is_empty(), "the check complains about a good chain: %s" % [Solvable.problems_of(all_locked, plain)])
	var default_chain := Solvable.build(42, 20, LOCK_CHANCE)
	_expect(failures, Solvable.problems_of(default_chain, plain).is_empty(), "the check complains about the default chain: %s" % [Solvable.problems_of(default_chain, plain)])

	var faults: Array[Dictionary] = [
		{kind = "no_key", name = "a locked room without a key", expect = "locked and has no key"},
		{kind = "stray_key", name = "a key in a room that is not locked", expect = "not locked but holds a key"},
		{kind = "bad_spot", name = "a key spot the room does not have", expect = "does not exist"},
		{kind = "locked_goal", name = "a locked goal room", expect = "never are"},
		{kind = "locked_before_goal", name = "a locked room before the goal", expect = "never are"},
		{kind = "locked_room_zero", name = "a locked room 0", expect = "never are"},
		{kind = "moved_room", name = "a lock that moves a room", expect = "not the room it is without locks"},
		{kind = "lost_room", name = "a lost room", expect = "rooms with locks"},
		{kind = "second_goal", name = "a second goal room", expect = "goal rooms"},
		{kind = "no_goal", name = "no goal room", expect = "goal rooms"},
		{kind = "late_key", name = "a key one room too late", expect = "stuck"},
	]
	for fault in faults:
		# Every lockable room locked, so that room 5 is one; the late key needs an open room after a locked one: the default chain.
		var chain := Solvable.build(42, 20, LOCK_CHANCE if fault.kind == "late_key" else 1.0)
		_sabotage(chain, fault.kind)
		var problems := Solvable.problems_of(chain, plain)
		var named := false
		for problem in problems:
			named = named or problem.contains(fault.expect)
		_expect(failures, named, "the check does not find %s (expected \"%s\", got %s)" % [fault.name, fault.expect, problems.slice(0, 3)])
	return failures

## Breaks the plans of a chain the way a buggy generator could.
func _sabotage(chain: Chain, kind: String) -> void:
	match kind:
		"no_key":
			chain.plans[5].key_spot = -1
		"stray_key":
			chain.plans[5].locked = false
		"bad_spot":
			chain.plans[5].key_spot = chain.key_spot_count(chain.plans[5].type)
		"locked_goal":
			chain.plans[-1].locked = true
		"locked_before_goal":
			chain.plans[chain.goal_index - 1].locked = true
			chain.plans[chain.goal_index - 1].key_spot = 0
		"locked_room_zero":
			chain.plans[0].locked = true
			chain.plans[0].key_spot = 0
		"moved_room":
			chain.plans[7].type = (chain.plans[7].type + 1) % 5
		"lost_room":
			chain.plans.remove_at(10)
		"second_goal":
			chain.plans[3].type = Chain.Type.GOAL
		"no_goal":
			chain.plans[-1].type = Chain.Type.STRAIGHT
		"late_key":
			# The first locked room whose next room is an open ordinary room: its key moves into that room.
			for plan in chain.plans:
				var next := chain.plans[plan.index + 1]
				if plan.locked and not next.locked and next.type != Chain.Type.GOAL:
					next.key_spot = plan.key_spot
					plan.key_spot = -1
					return

## The way a viewer runs it, and the way a build server would: a separate Godot process, exit code 0.
func test_solvable_command() -> Array[String]:
	var failures: Array[String] = []
	var executable := OS.get_executable_path()
	if executable.is_empty():
		_skip("check_solvable.gd from the command line", "no executable path")
		return failures
	for step: String in [STEPS[0], FINAL_STEP]:
		var output: Array = []
		var code := OS.execute(executable, ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://steps/%s/check_solvable.gd" % step, "--", "--seeds=40"], output, true)
		var text := ""
		for chunk: String in output:
			text += str(chunk)
		_expect(failures, code == 0 and text.contains("SOLVABLE OK") and text.contains("seeds 1-40, lock chance 0.4") and text.contains("seeds 1-40, lock chance 1.0"), "%s: exit code %d, output: %s" % [step, code, text.substr(0, 300)])
	return failures

#endregion

#region Tutorial 04 (checked again): key scene, key spots, pickup

func test_key_scene(step: String) -> Array[String]:
	var failures: Array[String] = []
	var key := (load("res://steps/%s/key.tscn" % step) as PackedScene).instantiate() as Area3D
	_expect(failures, key != null and key.has_signal("picked_up"), "key.tscn is not an Area3D with a picked_up signal")
	_expect(failures, key.collision_layer == 0 and key.collision_mask == 2, "Key: layer %d mask %d, expected 0 and 2 (it only looks at the player layer)" % [key.collision_layer, key.collision_mask])
	var shape := key.get_node("CollisionShape3D") as CollisionShape3D
	var sphere := shape.shape as SphereShape3D
	_expect(failures, sphere != null and sphere.radius >= 0.4 and sphere.radius <= 0.7, "the key's reach is not a sphere of about half a metre")
	_expect(failures, shape.position.y > 0.5 and shape.position.y < 1.3, "the reach is at y = %.2f: it has to meet a capsule of 1.8 m" % shape.position.y)

	# A graybox key: ring, shaft and two teeth, the key material, about half a metre long, hovering over the floor.
	var model := key.get_node("Model") as Node3D
	var box := AABB()
	var first := true
	for part_name: String in ["Ring", "Shaft", "ToothUpper", "ToothLower"]:
		var part := model.get_node(part_name) as MeshInstance3D
		_expect(failures, part != null and part.mesh is PrimitiveMesh, "Key/Model/%s is not a primitive mesh" % part_name)
		if part == null:
			continue
		var material := (part.mesh as PrimitiveMesh).material
		_expect(failures, material != null and material.resource_path == MATERIAL_DIR + "key.tres", "%s does not use key.tres" % part_name)
		var part_box := part.transform * part.mesh.get_aabb()
		box = part_box if first else box.merge(part_box)
		first = false
	_expect(failures, box.size.y >= 0.4 and box.size.y <= 0.9 and box.size.x <= 0.5, "the key model is %s: not about half a metre" % box.size)
	_expect(failures, model.position.y - 0.5 * box.size.y > 0.3, "the key hangs too low (model at %.2f)" % model.position.y)

	# Spinning and bobbing is for the eye: the model moves, the reach does not. The test calls _process by hand,
	# 0.1 s at a time, so it does not depend on how fast the headless loop runs.
	_expect(failures, not key.monitoring, "the key's reach is awake from the start: a player the level has just placed would be counted at the old place")
	root.add_child(key)
	await process_frame
	_expect(failures, key.is_processing(), "the key does not run _process")
	await _wait_physics(3)
	_expect(failures, key.monitoring, "the key's reach did not wake up after its first physics step")
	var reach_before := shape.global_transform
	var low := INF
	var high := -INF
	var yaw_first := model.rotation.y
	for i in 70: # 7 s: two bobs
		key.call("_process", 0.1)
		low = minf(low, model.position.y)
		high = maxf(high, model.position.y)
	_expect(failures, absf((high - low) - 0.16) < 0.01, "the key bobs by %.3f m, expected 0.16 (0.08 up and down)" % (high - low))
	_expect(failures, high - low < 0.2, "the key bobs by more than 0.2 m")
	key.call("_process", 0.5)
	_expect(failures, not is_equal_approx(model.rotation.y, yaw_first), "the key does not spin")
	_expect(failures, shape.global_transform == reach_before and key.global_transform == Transform3D.IDENTITY, "the reach moved with the model")
	root.remove_child(key)
	key.free()
	return failures

## Every room type's key spots, read from the scene: on the floor, off the walking line, clear of the door, in view.
func test_key_spots(step: String) -> Array[String]:
	var failures: Array[String] = []
	await _set_screen(Vector2i(1280, 720)) # the project's window: the view of a player at the entrance is wider than tall
	var camera := Camera3D.new()
	camera.current = false
	for room_type in ROOM_TYPES:
		var room := (load("res://steps/%s/room_%s.tscn" % [step, room_type]) as PackedScene).instantiate() as Node3D
		root.add_child(room)
		await _wait_physics(4) # the shells build their collision
		var spots: Array[Marker3D] = []
		var container := room.get_node_or_null("KeySpots")
		_expect(failures, container != null, "room_%s has no KeySpots" % room_type)
		if container != null:
			for child in container.get_children():
				_expect(failures, child is Marker3D and not child.name.is_empty(), "room_%s/KeySpots/%s is not a Marker3D" % [room_type, child.name])
				spots.append(child as Marker3D)
			_expect(failures, spots.size() >= 2 and spots.size() <= 3, "room_%s has %d key spots, expected 2 or 3" % [room_type, spots.size()])
		failures.append_array(_key_spot_problems(room, room_type, spots, camera))
		root.remove_child(room)
		room.free()
	# The goal room has no door and no key.
	var goal := (load("res://steps/%s/room_goal.tscn" % step) as PackedScene).instantiate() as Node3D
	_expect(failures, goal.get_node_or_null("KeySpots") == null and goal.get_node_or_null("KeySpot") == null and goal.get_node_or_null("PropSpots") == null, "the goal room has key or prop spots")
	goal.free()
	camera.free()
	return failures

func _key_spot_problems(room: Node3D, label: String, spots: Array[Marker3D], camera: Camera3D) -> Array[String]:
	var problems: Array[String] = []
	var entrance := room.get_node("Entrance") as Marker3D
	var exit_point := room.get_node("Exit") as Marker3D
	var door := room.get("door") as Node3D
	var floor_box := _floor_box(room)
	var floor_rect := Rect2(Vector2(floor_box.position.x, floor_box.position.z), Vector2(floor_box.size.x, floor_box.size.z))
	var trigger_rect := _area_rect(door, "Trigger")
	var swing_rect := _area_rect(door, "Swing")
	var line_from := Vector2(entrance.position.x, entrance.position.z)
	var line_to := Vector2(exit_point.position.x, exit_point.position.z)

	# A player at the entrance, eye 1.6 m up, looking straight into the room.
	room.add_child(camera)
	camera.transform = entrance.transform.translated_local(Vector3(0.0, 1.6, 0.0))
	camera.fov = 75.0
	for i in spots.size():
		var spot := spots[i]
		var name := "%s %s" % [label, spot.name]
		var at := Vector2(spot.position.x, spot.position.z)
		_expect(problems, is_zero_approx(spot.position.y), "%s is %.2f m above the floor" % [name, spot.position.y])
		_expect(problems, floor_rect.grow(-0.9).has_point(at), "%s (%s) is less than 0.9 m from a wall: the key's reach and the player's body need room" % [name, at])
		_expect(problems, _distance_to_rect(at, trigger_rect) >= 1.5, "%s is %.2f m from the door's trigger: picking the key up must not set the door off (key reach 0.5 + body 0.4 + margin)" % [name, _distance_to_rect(at, trigger_rect)])
		_expect(problems, _distance_to_rect(at, swing_rect) >= 1.5, "%s is %.2f m from the door's swing" % [name, _distance_to_rect(at, swing_rect)])
		var way_to_trigger := _segment_distance_to_rect(line_from, at, trigger_rect)
		var way_to_swing := _segment_distance_to_rect(line_from, at, swing_rect)
		_expect(problems, way_to_trigger >= 0.9 and way_to_swing >= 0.9, "%s: walking straight from the entrance to the key passes %.2f m from the door's trigger and %.2f m from its swing (body 0.4 + margin): the player would knock on the door on the way" % [name, way_to_trigger, way_to_swing])
		var line_distance := Geometry2D.get_closest_point_to_segment(at, line_from, line_to).distance_to(at)
		_expect(problems, line_distance >= 1.5, "%s is %.2f m from the walking line between entrance and exit: a player walking through would pick it up by accident" % [name, line_distance])
		var centre := room.global_transform * (spot.position + Vector3(0.0, 0.9, 0.0))
		_expect(problems, camera.is_position_in_frustum(centre), "%s is out of view for a player standing at the entrance" % name)
		var query := PhysicsRayQueryParameters3D.create(camera.global_position, centre)
		var hit := room.get_world_3d().direct_space_state.intersect_ray(query)
		_expect(problems, hit.is_empty(), "%s is hidden from the entrance: a ray hits %s" % [name, hit.get("collider")])
		for j in range(i + 1, spots.size()):
			_expect(problems, spot.position.distance_to(spots[j].position) >= 2.0, "%s and %s are less than 2 m apart" % [name, spots[j].name])
	room.remove_child(camera)
	return problems

## An area of a door as a rectangle on the floor plane of the room (the door sits in the room, turned by multiples of 90 degrees).
func _area_rect(door: Node3D, area_name: String) -> Rect2:
	var area := door.get_node(area_name) as Area3D
	var shape := area.get_node("CollisionShape3D") as CollisionShape3D
	var half := (shape.shape as BoxShape3D).size / 2.0
	var to_room := door.transform * area.transform * shape.transform
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for x: float in [-half.x, half.x]:
		for z: float in [-half.z, half.z]:
			var corner := to_room * Vector3(x, 0.0, z)
			low = low.min(Vector2(corner.x, corner.z))
			high = high.max(Vector2(corner.x, corner.z))
	return Rect2(low, high - low)

## How close a straight walk from a to b comes to a rectangle.
func _segment_distance_to_rect(from: Vector2, to: Vector2, rect: Rect2) -> float:
	var closest := INF
	for i in 101:
		closest = minf(closest, _distance_to_rect(from.lerp(to, i / 100.0), rect))
	return closest

func _distance_to_rect(point: Vector2, rect: Rect2) -> float:
	var outside := Vector2(maxf(maxf(rect.position.x - point.x, 0.0), point.x - rect.end.x), maxf(maxf(rect.position.y - point.y, 0.0), point.y - rect.end.y))
	return outside.length()

#endregion

#region Helpers for levels with a key and a lock

## Removes the lock of a door without opening it. Step 2 locks room 0 by hand; tests about the swing want a plain door.
func _unlock_by_hand(door: Node) -> void:
	if door.get("locked") == true:
		door.call("unlock")

## The keys lying in a room: children with a picked_up signal that are not on their way out.
func _keys_in(room: Node3D) -> Array[Node3D]:
	var found: Array[Node3D] = []
	for child in room.get_children():
		if child.has_signal("picked_up") and not child.is_queued_for_deletion():
			found.append(child)
	return found

const KEY_ROOM := 1 ## The room with the key and the locked door in a test level (lock chance 1 locks it; room 0 is never locked).

## A level with a key to fetch: lock_chance 1 locks every room but room 0 and the one before the goal, so room 1 is
## locked; the autopilot brings the player into it, the key still lies there.
func _load_with_key(step: String, extra := {}) -> Node:
	var settings := {"goal_room": 6, "lock_chance": 1.0}
	settings.merge(extra, true)
	var main := await _load_step(step, true, settings)
	var level: Node3D = main.get_node("Level")
	_fast_forward(true)
	var pilot := Autopilot.new(level)
	await _walk(level, pilot, KEY_ROOM, 0, Callable())
	_fast_forward(false)
	await _wait_physics(5)
	return main

## Puts the player `metres` in front of the room's exit, looking at the door.
func _stand_before_door(level: Node3D, room: Node3D, metres: float) -> void:
	var door_point := (room.get("exit") as Marker3D).global_transform
	var forward := -door_point.basis.z
	var player: CharacterBody3D = level.player
	player.global_position = door_point.origin - forward * metres
	player.rotation.y = atan2(-forward.x, -forward.z)
	(player.get_node("Head") as Node3D).rotation.x = 0.0
	player.velocity = Vector3.ZERO
	await _wait_physics(3)

## Walks the player at a key from 2.5 m away, from the side of the entrance (away from the door), until the key is gone.
func _walk_into(level: Node3D, room: Node3D, key: Node3D) -> bool:
	var player: CharacterBody3D = level.player
	var entrance := (room.get("entrance") as Marker3D).global_position
	var towards_entrance := Vector3(entrance.x - key.global_position.x, 0.0, entrance.z - key.global_position.z).normalized()
	player.global_position = key.global_position + towards_entrance * 2.5
	var direction := key.global_position - player.global_position
	player.rotation.y = atan2(-direction.x, -direction.z)
	player.velocity = Vector3.ZERO
	await _wait_physics(3)
	return await _walk_forward_until(func() -> bool: return not is_instance_valid(key) or key.is_queued_for_deletion(), 180)

## Holds move_forward until the condition is true (checked once per physics frame) or the ticks run out.
func _walk_forward_until(condition: Callable, max_ticks: int) -> bool:
	Input.action_press("move_forward")
	var reached := false
	for i in max_ticks:
		await physics_frame
		if condition.call():
			reached = true
			break
	Input.action_release("move_forward")
	return reached

func _label_text(main: Node, path: String) -> String:
	var label := main.get_node_or_null(path) as Label
	return label.text if label != null else ""

#endregion

#region Tutorial 04 (checked again): picking up, locking, unlocking

func test_pickup(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_with_key(step)
	var level: Node3D = main.get_node("Level")
	var room: Node3D = level.rooms[KEY_ROOM]
	var found := _keys_in(room)
	_expect(failures, found.size() == 1, "%d keys in the room, expected 1" % found.size())
	if found.size() != 1:
		await _unload(main)
		return failures
	var key := found[0]
	_expect(failures, level.keys == 0 and _label_text(main, "HUD/Stats/KeysLabel") == "Keys 0", "keys %s, label \"%s\" before the pickup" % [level.keys, _label_text(main, "HUD/Stats/KeysLabel")])
	var counts: Array[int] = []
	level.connect("keys_changed", func(count: int) -> void: counts.append(count))

	# Not touched: standing 2.5 m away, or walking past at the wall, picks nothing up.
	var player: CharacterBody3D = level.player
	await _wait_physics(30)
	_expect(failures, counts.is_empty() and is_instance_valid(key), "the key was picked up without being touched")

	var key_position := key.global_position
	var reached := await _walk_into(level, room, key)
	await _wait_physics(3)
	_expect(failures, reached, "walking into the key did not pick it up")
	_expect(failures, counts == [1], "keys_changed was sent with %s, expected [1] (counted exactly once)" % [counts])
	_expect(failures, level.keys == 1 and _label_text(main, "HUD/Stats/KeysLabel") == "Keys 1", "keys %s, label \"%s\" after the pickup" % [level.keys, _label_text(main, "HUD/Stats/KeysLabel")])
	_expect(failures, not is_instance_valid(key) and _keys_in(room).is_empty(), "the key is still in the room after the pickup")

	# Nothing left to pick up at the same place.
	player.global_position = key_position
	player.velocity = Vector3.ZERO
	await _wait_physics(30)
	_expect(failures, counts == [1] and level.keys == 1, "walking over the empty spot counted again: %s" % [counts])

	# R takes the key out of the player's hands.
	await _action("regenerate")
	await _wait_physics(10)
	_expect(failures, level.keys == 0 and _label_text(main, "HUD/Stats/KeysLabel") == "Keys 0" and counts.back() == 0, "R left keys %s, label \"%s\"" % [level.keys, _label_text(main, "HUD/Stats/KeysLabel")])
	await _unload(main)
	return failures

func test_keys_label(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step)
	var level: Node3D = main.get_node("Level")
	var label: Label = main.get_node("HUD/Stats/KeysLabel")
	var room_label: Label = main.get_node("HUD/Stats/RoomLabel")
	_expect(failures, label.text == "Keys 0", "the keys label reads \"%s\" at the start" % label.text)
	_expect(failures, label.get_parent() == room_label.get_parent() and label.get_index() == room_label.get_index() + 1, "the keys label is not right under the room counter")
	_expect(failures, label.get_theme_font_size("font_size") == room_label.get_theme_font_size("font_size") and label.get_theme_constant("outline_size") == room_label.get_theme_constant("outline_size") and label.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT, "the keys label does not look like the room counter")
	level.keys_changed.emit(7)
	_expect(failures, label.text == "Keys 7", "the label reads \"%s\" after keys_changed(7)" % label.text)
	level.keys_changed.emit(0)
	for screen_size: Vector2i in [Vector2i(1920, 1080), Vector2i(1280, 720)]:
		await _set_screen(screen_size)
		label.text = "Keys 20" # the widest it gets
		await process_frame
		var stats: Control = main.get_node("HUD/Stats")
		var screen := Rect2(Vector2.ZERO, Vector2(screen_size))
		var where := "at %dx%d" % [screen_size.x, screen_size.y]
		_expect(failures, screen.encloses(stats.get_global_rect()) and stats.get_global_rect().end.x <= screen.end.x - 8.0, "%s: the stats box %s does not fit the screen" % [where, stats.get_global_rect()])
		_expect(failures, not stats.get_global_rect().intersects((main.get_node("HUD/DebugMap") as Control).get_global_rect()), "%s: the stats box overlaps the map" % where)
		_expect(failures, label.get_minimum_size().x <= stats.size.x, "%s: \"Keys 20\" needs %.0f px, the box is %.0f px wide" % [where, label.get_minimum_size().x, stats.size.x])
		_expect(failures, label.get_global_rect().position.y > room_label.get_global_rect().position.y and label.get_global_rect().end.y <= stats.get_global_rect().end.y + 0.5, "%s: the keys label is not inside the box under the counter" % where)
	await _unload(main)
	return failures

func test_locked_door(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_with_key(step)
	var level: Node3D = main.get_node("Level")
	var player: CharacterBody3D = level.player
	var room: Node3D = level.rooms[KEY_ROOM]
	var door: Node3D = room.get("door")
	var hinge: Node3D = door.get("hinge")
	var lock_block: Node3D = door.get("lock_block")
	var label := "%s room %d" % [step, KEY_ROOM]

	# The lock is on the door: a red-orange bar and plate, from lock.tres, in front of the panel.
	_expect(failures, door.get("locked") == true and lock_block.visible and not door.get("is_open"), "%s: the door is not locked and shut with its lock showing" % label)
	for part_name: String in ["Bar", "Plate"]:
		var part := lock_block.get_node(part_name) as MeshInstance3D
		var material := (part.mesh as PrimitiveMesh).material
		_expect(failures, material != null and material.resource_path == MATERIAL_DIR + "lock.tres", "%s: the lock's %s does not use lock.tres" % [label, part_name])
		_expect(failures, part.position.z + (part.mesh as BoxMesh).size.z / 2.0 > 0.05 and lock_block.global_position.distance_to(door.global_position) < 3.0, "%s: the lock's %s does not stand out of the panel" % [label, part_name])
	var asked := [0]
	var opened := [0]
	var counts: Array[int] = []
	door.connect("unlock_requested", func() -> void: asked[0] += 1)
	door.connect("opened", func() -> void: opened[0] += 1)
	level.connect("keys_changed", func(count: int) -> void: counts.append(count))
	var key := _keys_in(room)[0]

	# 1. No key: the player walks up, the door asks the level, the answer is no. The door stays shut, however long the
	# player pushes. The refusal rattles the door (tutorial 04's feedback).
	var asked_at := [-1]
	var peak_angle := [0.0]
	door.connect("unlock_requested", func() -> void: asked_at[0] = Engine.get_physics_frames())
	await _stand_before_door(level, room, 5.0)
	Input.action_press("move_forward")
	var sampler := func() -> bool:
		peak_angle[0] = maxf(peak_angle[0], absf(hinge.rotation.y))
		return asked_at[0] >= 0 and Engine.get_physics_frames() > int(asked_at[0]) + 150
	await _drive(sampler)
	Input.action_release("move_forward")
	_expect(failures, asked[0] == 1, "%s: the locked door was asked %d times when the player walked up" % [label, asked[0]])
	_expect(failures, peak_angle[0] > deg_to_rad(3.0), "%s: the refused door did not rattle" % label)
	_expect(failures, not door.get("is_open") and opened[0] == 0 and absf(hinge.rotation.y) < 0.01, "%s: the locked door opened without a key (open %s, hinge %.3f rad)" % [label, door.get("is_open"), hinge.rotation.y])
	_expect(failures, level.keys == 0 and counts.is_empty() and door.get("locked") == true and lock_block.visible, "%s: keys %d, locked %s after the refusal" % [label, level.keys, door.get("locked")])
	var door_point := (room.get("exit") as Marker3D).global_transform
	_expect(failures, _depth(player, door_point) < -0.3, "%s: the player got through the locked door (depth %.2f)" % [label, _depth(player, door_point)])

	# 2. Fetch the key: one pickup, the HUD says so.
	var picked := await _walk_into(level, room, key)
	await _wait_physics(3)
	_expect(failures, picked and level.keys == 1 and counts == [1] and _label_text(main, "HUD/Stats/KeysLabel") == "Keys 1", "%s: keys %d, label \"%s\" after the pickup" % [label, level.keys, _label_text(main, "HUD/Stats/KeysLabel")])
	_expect(failures, not door.get("is_open") and door.get("locked") == true, "%s: picking up the key opened the door by itself" % label)

	# 3. With the key: the door asks again, the answer is yes, the key is used up, the door opens by itself.
	await _stand_before_door(level, room, 5.0)
	var asked_before: int = asked[0]
	var reached := await _walk_forward_until(func() -> bool: return door.get("is_open") == true, 240)
	await _wait_physics(5)
	_expect(failures, reached and door.get("is_open") == true, "%s: the door did not open for a player with a key" % label)
	_expect(failures, asked[0] == asked_before + 1 and opened[0] == 1, "%s: asked %d times, opened %d times with the key" % [label, asked[0] - asked_before, opened[0]])
	_expect(failures, level.keys == 0 and counts == [1, 0] and _label_text(main, "HUD/Stats/KeysLabel") == "Keys 0", "%s: keys %d, changes %s, label \"%s\": the key was not used up exactly once" % [label, level.keys, counts, _label_text(main, "HUD/Stats/KeysLabel")])
	_expect(failures, door.get("locked") == false, "%s: the door is still locked after the key" % label)
	await _wait_physics(60) # the swing (0.5 s) and the lock's fall
	_expect(failures, absf(hinge.rotation.y - (-PI / 2.0)) < 0.03 and not lock_block.visible, "%s: the door is at %.1f deg, lock visible %s" % [label, rad_to_deg(hinge.rotation.y), lock_block.visible])
	Input.action_press("move_forward")
	await _wait_physics(120)
	Input.action_release("move_forward")
	_expect(failures, _depth(player, door_point) > 0.5, "%s: the player cannot walk through the opened door (depth %.2f)" % [label, _depth(player, door_point)])
	# The door is a plain door now: nobody asks again.
	_expect(failures, asked[0] == asked_before + 1, "%s: the unlocked door asked again" % label)
	await _unload(main)
	return failures

#endregion

#region Tutorial 04 (checked again): what the level builds from the plans

## Every room the player passes holds what its plan says: a lock on the door, one key at the planned spot, in the same room.
## (Props are checked by test_props_in_level.)
func test_locks_in_level() -> Array[String]:
	var failures: Array[String] = []
	for step in STEPS:
		var main := await _load_step(step, true, {"goal_room": 20, "chain_seed": 3}) # seed 3 locks rooms early in every step
		var level: Node3D = main.get_node("Level")
		var checked := {}
		var seen_locked := [0]
		var pilot := Autopilot.new(level)
		var on_tick := func() -> void:
			for index: int in level.rooms.keys():
				if checked.has(index):
					continue
				checked[index] = true
				var room: Node3D = level.rooms[index]
				var plan: Object = level.chain.plans[index]
				var door: Node3D = room.get("door")
				var keys := _keys_in(room)
				var where := "%s room %d" % [step, index]
				if plan.locked:
					seen_locked[0] += 1
				_expect(failures, (door == null) or (door.get("locked") == plan.locked and door.get("lock_block").visible == plan.locked), "%s: the door's lock does not match the plan (locked %s)" % [where, plan.locked])
				_expect(failures, keys.size() == (1 if plan.key_spot >= 0 else 0), "%s: %d keys, the plan has key spot %d" % [where, keys.size(), plan.key_spot])
				if keys.size() == 1 and plan.key_spot >= 0:
					var spot: Marker3D = room.get("key_spots")[plan.key_spot]
					_expect(failures, keys[0].get_parent() == room and keys[0].global_position.distance_to(spot.global_position) < 1e-4, "%s: the key is not at key spot %d" % [where, plan.key_spot])
					_expect(failures, (plan.bounds as AABB).has_point(keys[0].global_position + Vector3(0.0, 0.5, 0.0)), "%s: the key is outside its room" % where)
		_fast_forward(true)
		var arrived := await _walk(level, pilot, 8, 0, on_tick)
		_fast_forward(false)
		_expect(failures, arrived, "%s: the player did not reach room 8" % step)
		_expect(failures, seen_locked[0] >= 2, "%s: only %d locked rooms among the first 9 of seed 3" % [step, seen_locked[0]])
		await _unload(main)
	return failures

#endregion

#region Tutorial 04 (checked again): feedback for a refused door

func test_feedback(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_with_key(step)
	var level: Node3D = main.get_node("Level")
	var room: Node3D = level.rooms[1]
	var door: Node3D = room.get("door")
	var hinge: Node3D = door.get("hinge")
	var message: Label = main.get_node("HUD/MessageLabel")
	var timer: Timer = main.get_node("HUD/MessageTimer")
	var meshes: Array[MeshInstance3D] = [door.get_node("Hinge/Lock/Bar"), door.get_node("Hinge/Lock/Plate")]
	var shared := load(MATERIAL_DIR + "lock.tres") as StandardMaterial3D
	var rest_energy := shared.emission_energy_multiplier

	# The message label: its words, its place, its time. Hidden until a door says no.
	_expect(failures, message.text == "Locked: find the key" and not message.visible, "the message reads \"%s\", visible %s at the start" % [message.text, message.visible])
	_expect(failures, is_equal_approx(timer.wait_time, 1.5) and timer.one_shot, "the message timer is %.2f s, one shot %s" % [timer.wait_time, timer.one_shot])
	_expect(failures, message.get_theme_font_size("font_size") >= 40 and message.get_theme_constant("outline_size") >= 6 and message.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER, "the message is too small or has no outline")
	message.show()
	for screen_size: Vector2i in [Vector2i(1920, 1080), Vector2i(1280, 720)]:
		await _set_screen(screen_size)
		var screen := Rect2(Vector2.ZERO, Vector2(screen_size))
		var rect := message.get_global_rect()
		var where := "at %dx%d" % [screen_size.x, screen_size.y]
		_expect(failures, screen.encloses(rect), "%s: the message %s is not inside the screen" % [where, rect])
		_expect(failures, absf(rect.get_center().x - screen.size.x / 2.0) < 2.0, "%s: the message is not centred (%s)" % [where, rect.get_center()])
		_expect(failures, rect.get_center().y > screen.size.y * 0.6 and rect.get_center().y < screen.size.y * 0.85, "%s: the message is at %.0f percent of the height, expected the lower third" % [where, rect.get_center().y / screen.size.y * 100.0])
		_expect(failures, not rect.intersects((main.get_node("HUD/Stats") as Control).get_global_rect()) and not rect.intersects((main.get_node("HUD/DebugMap") as Control).get_global_rect()), "%s: the message overlaps the stats or the map" % where)
		_expect(failures, message.get_minimum_size().x <= message.size.x, "%s: the text needs %.0f px, the label is %.0f px wide" % [where, message.get_minimum_size().x, message.size.x])
	message.hide()

	# The knock: a player without a key walks up. Sample every physics frame from the moment of the question.
	var knock := {"asked": -1, "blocked": -1, "message_at_signal": false, "override_at_signal": false, "energy_at_signal": 0.0}
	door.connect("unlock_requested", func() -> void: knock["asked"] = Engine.get_physics_frames())
	level.connect("door_blocked", func() -> void:
		knock["blocked"] = Engine.get_physics_frames()
		knock["message_at_signal"] = message.visible
		knock["override_at_signal"] = meshes[0].material_override != null and meshes[1].material_override != null
		knock["energy_at_signal"] = (meshes[0].material_override as StandardMaterial3D).emission_energy_multiplier if meshes[0].material_override != null else 0.0)
	var samples: Array[Dictionary] = []
	await _stand_before_door(level, room, 5.0)
	Input.action_press("move_forward")
	var sampler := func() -> bool:
		samples.append({frame = Engine.get_physics_frames(), angle = hinge.rotation.y, message = message.visible, override = meshes[0].material_override != null})
		return (int(knock["asked"]) >= 0 and Engine.get_physics_frames() > int(knock["asked"]) + 150) or samples.size() > 600
	await _drive(sampler)
	Input.action_release("move_forward")
	_expect(failures, int(knock["asked"]) >= 0 and knock["blocked"] == knock["asked"], "the door asked in frame %s, the level said no in frame %s" % [knock["asked"], knock["blocked"]])
	var asked_at: int = knock["asked"]

	# The door rattles: it starts within one physics frame, gives a few degrees away from the player, never towards, and is still again.
	var onset := -1
	var peak := 0.0
	var toward := 0.0
	for sample in samples:
		if sample.frame < asked_at:
			continue
		if onset < 0 and absf(sample.angle) > 0.001:
			onset = sample.frame - asked_at
		peak = minf(peak, sample.angle)
		toward = maxf(toward, sample.angle)
	_expect(failures, onset >= 0 and onset <= 1, "the rattle started %d physics frames after the door was asked, expected at most 1" % onset)
	_expect(failures, peak < deg_to_rad(-3.0) and peak > deg_to_rad(-4.6), "the door gave %.1f deg at most, expected about 4" % rad_to_deg(peak))
	_expect(failures, toward < 0.0001, "the door swung %.2f deg towards the player" % rad_to_deg(toward))
	var settled := 0
	var still := true
	for sample in samples:
		if sample.frame >= asked_at + 30:
			settled += 1
			still = still and absf(sample.angle) < 0.002
	_expect(failures, settled > 60 and still, "the door does not come to rest within half a second")
	_expect(failures, not door.get("is_open") and door.get("locked") == true and level.keys == 0, "the refused door opened or lost its lock")

	# The lock flashes on the same frame, from a private copy; the shared material is never touched.
	_expect(failures, knock["override_at_signal"] and float(knock["energy_at_signal"]) >= 4.0, "the lock did not light up at once (override %s, energy %s)" % [knock["override_at_signal"], knock["energy_at_signal"]])
	_expect(failures, shared.emission_energy_multiplier == rest_energy and (meshes[0].mesh as PrimitiveMesh).material == shared, "the flash changed the shared lock.tres (emission %s, was %s)" % [shared.emission_energy_multiplier, rest_energy])
	var flash_ended := -1
	for sample in samples:
		if sample.frame >= asked_at and not sample.override:
			flash_ended = sample.frame - asked_at
			break
	_expect(failures, flash_ended > 12 and flash_ended <= 45, "the flash lasted %d physics frames, expected about 24" % flash_ended)

	# The words: on screen in the same frame, there for 1.5 s, then gone.
	_expect(failures, knock["message_at_signal"] == true, "the message was not up in the frame of the refusal")
	var last_visible := -1
	for sample in samples:
		if sample.frame >= asked_at and sample.message:
			last_visible = sample.frame - asked_at
	_expect(failures, last_visible >= 80 and last_visible <= 105, "the message stayed for %d physics frames (%.2f s), expected 90 (1.5 s)" % [last_visible, last_visible / 60.0])
	_expect(failures, not message.visible, "the message is still up after 2.5 s")
	print("        refusal: rattle starts %d physics frame(s) after the question, peak %.1f deg away from the player, lock flash %d frames, words up for %d frames (%.2f s)" % [onset, rad_to_deg(peak), flash_ended, last_visible, last_visible / 60.0])

	# Another refusal while the words are up starts the 1.5 s again (it does not cut the second one short).
	level.emit_signal("door_blocked")
	await _wait_physics(70)
	level.emit_signal("door_blocked")
	await _wait_physics(70)
	_expect(failures, message.visible, "the second refusal did not restart the time")
	await _wait_physics(40)
	_expect(failures, not message.visible, "the message did not go away after the second refusal")

	# A new run starts without the old words.
	level.emit_signal("door_blocked")
	await _action("regenerate")
	await _wait_physics(5)
	_expect(failures, not message.visible, "R left the message up")
	await _unload(main)
	return failures

## With a key: no rattle, no words, the lock falls off the door and fades, the door opens.
func test_unlock_animation(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_with_key(step)
	var level: Node3D = main.get_node("Level")
	var room: Node3D = level.rooms[1]
	var door: Node3D = room.get("door")
	var hinge: Node3D = door.get("hinge")
	var lock_block: Node3D = door.get("lock_block")
	var meshes: Array[MeshInstance3D] = [door.get_node("Hinge/Lock/Bar"), door.get_node("Hinge/Lock/Plate")]
	var message: Label = main.get_node("HUD/MessageLabel")
	var blocked := [0]
	level.connect("door_blocked", func() -> void: blocked[0] += 1)
	_expect(failures, await _walk_into(level, room, _keys_in(room)[0]), "the key was not picked up")
	await _stand_before_door(level, room, 5.0)
	var rest_y := lock_block.position.y
	var samples: Array[Dictionary] = []
	var asked := [-1]
	door.connect("unlock_requested", func() -> void: asked[0] = Engine.get_physics_frames())
	Input.action_press("move_forward")
	var sampler := func() -> bool:
		samples.append({frame = Engine.get_physics_frames(), y = lock_block.position.y, visible = lock_block.visible, fade = meshes[0].transparency, open = door.get("is_open"), angle = hinge.rotation.y, message = message.visible, override = meshes[0].material_override != null})
		return asked[0] >= 0 and Engine.get_physics_frames() > int(asked[0]) + 80
	await _drive(sampler)
	Input.action_release("move_forward")
	_expect(failures, asked[0] >= 0 and blocked[0] == 0, "asked %s, door_blocked %d times with a key" % [asked[0], blocked[0]])
	var after: Array[Dictionary] = []
	for sample in samples:
		if sample.frame >= asked[0]:
			after.append(sample)
	_expect(failures, after.size() > 60, "only %d samples after the question" % after.size())
	if after.size() > 60:
		_expect(failures, after[1].open == true or after[0].open == true, "the door is not open one frame after the question")
		var mid := after[10] # a sixth of a second in: the lock is falling and fading, still on the door
		_expect(failures, mid.visible and mid.y < rest_y - 0.02 and mid.y > rest_y - DOOR_DROP and mid.fade > 0.02 and mid.fade < 1.0, "10 frames in the lock is at %.2f (rest %.2f), faded %.2f, visible %s: not falling and fading" % [mid.y, rest_y, mid.fade, mid.visible])
		var late := after[40]
		_expect(failures, not late.visible and late.fade >= 0.999 and late.y <= rest_y - DOOR_DROP + 0.01, "40 frames in the lock is visible %s at %.2f, faded %.2f" % [late.visible, late.y, late.fade])
		var open_wide := after[36] # 0.6 s: the swing (0.5 s) is done, the player is not through yet, so the door behind has not been told to close
		_expect(failures, absf(open_wide.angle - (-PI / 2.0)) < 0.03, "the door is at %.1f deg 0.6 s after the unlock" % rad_to_deg(open_wide.angle))
		var rattled := false
		for sample in after:
			rattled = rattled or sample.override or sample.message
		_expect(failures, not rattled, "an unlocked door flashed or showed the message")
		var toward := 0.0
		for sample in after:
			toward = maxf(toward, sample.angle)
		_expect(failures, toward < 0.0001, "the door swung towards the player")
	await _unload(main)
	return failures

const DOOR_DROP := 0.6 ## door.gd's DROP_DISTANCE, the lock's fall in metres.

#endregion

#region Runs that fetch keys

## Runs the autopilot from room 0 to the goal pad. Returns what happened.
func _full_run(chain_seed: Variant, goal_room: int, chance: float) -> Dictionary:
	var path := _fresh_save_path()
	var main := await _load_step(FINAL_STEP, true, {"save_path": path, "goal_room": goal_room, "seed_text" if chain_seed is String else "chain_seed": chain_seed, "lock_chance": chance})
	var level: Node3D = main.get_node("Level")
	var key_counts: Array[int] = []
	level.connect("keys_changed", func(count: int) -> void: key_counts.append(count))
	var blocked := [0]
	level.connect("door_blocked", func() -> void: blocked[0] += 1)
	var built := [_props_in(level.rooms[0]).size()]
	level.connect("room_entered", func(index: int) -> void: built[0] += _props_in(level.rooms[index]).size())
	var vault_height := [0.0]
	var on_tick := func() -> void:
		if level.chain.plans[level.current].type == Chain.Type.VAULT:
			vault_height[0] = maxf(vault_height[0], level.player.global_position.y)
	_fast_forward(true)
	var finished := await _walk_to_finish(level, Autopilot.new(level), 0, 60 * 60 * 6, on_tick)
	_fast_forward(false)
	var locked: Array[int] = []
	var vaults: Array[int] = []
	var locked_vaults := 0
	for plan: Object in level.chain.plans:
		if plan.locked:
			locked.append(plan.index)
			locked_vaults += 1 if plan.type == Chain.Type.VAULT and plan.index <= level.current else 0
		if plan.type == Chain.Type.VAULT and plan.index <= level.current:
			vaults.append(plan.index)
	var result := {finished = finished, time = level.run_time, key_counts = key_counts, locked = locked, blocked = blocked[0], room = level.current, goal = level.chain.goal_index, keys = level.keys, props = built[0], vaults = vaults, locked_vaults = locked_vaults, vault_height = vault_height[0], position = level.player.global_position}
	await _unload(main)
	return result

func test_more_full_runs() -> Array[String]:
	var failures: Array[String] = []
	# A seed with an early vault at lock chance 1: the vault is locked, its key is fetched, the platform is crossed.
	var vault_seed := 0
	for chain_seed in range(1, 300):
		var plans: Array = _plans_to_goal(Chain, chain_seed, 8, 1.0).plans
		if plans.any(func(plan: Object) -> bool: return plan.type == Chain.Type.VAULT and plan.index <= 5):
			vault_seed = chain_seed
			break
	_expect(failures, vault_seed > 0, "no seed with an early vault in 300")
	var runs: Array[Dictionary] = [
		{chain_seed = 43, goal_room = 20, chance = LOCK_CHANCE},
		{chain_seed = "BLUE-FOX", goal_room = 20, chance = LOCK_CHANCE},
		{chain_seed = "SEEDS YOU CAN SHARE", goal_room = 20, chance = LOCK_CHANCE},
		{chain_seed = 7, goal_room = 20, chance = LOCK_CHANCE},
		{chain_seed = 3, goal_room = 20, chance = LOCK_CHANCE},
		{chain_seed = 42, goal_room = 8, chance = 1.0},
		{chain_seed = vault_seed, goal_room = 8, chance = 1.0},
	]
	for spec in runs:
		var result := await _full_run(spec.chain_seed, spec.goal_room, spec.chance)
		var label := "seed %s, goal room %d, lock chance %.1f" % [spec.chain_seed, spec.goal_room, spec.chance]
		var expected: Array[int] = []
		var locked_count: int = result.locked.size()
		for i in locked_count:
			expected.append_array([1, 0])
		_expect(failures, result.finished and result.room == result.goal and result.keys == 0, "%s: did not finish (room %d of %d, keys %d, stopped at %s)" % [label, result.room, result.goal, result.keys, result.position])
		_expect(failures, result.key_counts == expected, "%s: key counts %s for locked rooms %s: every lock needs its key picked up and used up once" % [label, result.key_counts, result.locked])
		_expect(failures, result.blocked == 0, "%s: the autopilot, which fetches the key first, was refused %d times" % [label, result.blocked])
		_expect(failures, result.vaults.is_empty() or result.vault_height > 0.1, "%s: vaults %s, but the player never climbed a platform (highest %.3f)" % [label, result.vaults, result.vault_height])
		print("        %s: %d locked rooms %s, vaults %s (%d locked), %d props built, finished in %.1f s of game time" % [label, result.locked.size(), result.locked, result.vaults, result.locked_vaults, result.props, result.time])
	return failures

## The worst case for "props never block the way": every prop spot holds the biggest prop its room type has. The rules say
## this cannot block a path; here the real player walks it. The sets are put back afterwards.
func test_full_runs_all_spots_filled() -> Array[String]:
	var failures: Array[String] = []
	var saved_weights: Array[Array] = []
	var saved_empty: Array[float] = []
	for prop_set in Chain.PROP_SETS:
		saved_weights.append(prop_set.weights.duplicate())
		saved_empty.append(prop_set.empty_weight)
		var biggest := 0
		var area := 0.0
		for i in prop_set.scenes.size():
			var foot := Contents.footprint(prop_set.scenes[i], Transform3D.IDENTITY)
			if foot.get_area() > area:
				area = foot.get_area()
				biggest = i
		var weights: Array[float] = prop_set.weights.duplicate()
		for i in weights.size():
			weights[i] = 1.0 if i == biggest else 0.0
		prop_set.weights = weights
		prop_set.empty_weight = 0.0
	for spec: Dictionary in [{chain_seed = 42, goal_room = 20}, {chain_seed = 3, goal_room = 20}, {chain_seed = 7, goal_room = 20}]:
		var result := await _full_run(spec.chain_seed, spec.goal_room, LOCK_CHANCE)
		var label := "seed %d with every spot filled" % spec.chain_seed
		_expect(failures, result.finished and result.room == result.goal and result.keys == 0, "%s: did not finish (room %d of %d, stopped at %s)" % [label, result.room, result.goal, result.position])
		_expect(failures, result.props >= 80, "%s: only %d props were built" % [label, result.props])
		print("        %s: %d props built, %d locked rooms, vaults %s, finished in %.1f s of game time" % [label, result.props, result.locked.size(), result.vaults, result.time])
	for type in Chain.PROP_SETS.size():
		Chain.PROP_SETS[type].weights = saved_weights[type]
		Chain.PROP_SETS[type].empty_weight = saved_empty[type]
	return failures

#endregion

#region Tutorial 05: source rules for data

## Props and room weights are data: a Resource script with exports, .tres files, and a chain that only rolls and walks.
func test_data_rules() -> Array[String]:
	var failures: Array[String] = []
	for step in STEPS:
		var set_source := FileAccess.get_file_as_string("res://steps/%s/prop_set.gd" % step)
		_expect(failures, set_source.contains("extends Resource") and set_source.count("@export var") == 3 and not set_source.contains("func "), "%s/prop_set.gd is not a plain data Resource with its three exports" % step)
		for export_name: String in ["scenes", "weights", "empty_weight"]:
			_expect(failures, set_source.contains("@export var %s" % export_name), "%s/prop_set.gd has no export %s" % [step, export_name])
		var chain_source := FileAccess.get_file_as_string("res://steps/%s/room_chain.gd" % step)
		_expect(failures, not chain_source.contains("PROP_CHANCE") and not chain_source.contains("PROP_SCENES"), "%s: the chain still has step 1's fixed chance or prop list" % step)
		_expect(failures, chain_source.contains("static func weighted_pick(weights: Array[float], roll: float) -> int:"), "%s: no weighted_pick(weights, roll)" % step)
		var pick := _function_body(chain_source, "static func weighted_pick(")
		_expect(failures, not pick.contains("rand") and not pick.contains("PROP") and not pick.contains("ROOM"), "%s: weighted_pick rolls dice or knows the data: it only sums, compares and walks" % step)
		for file in DirAccess.get_files_at("res://steps/%s/props" % step):
			if file.ends_with(".tres"):
				var text := FileAccess.get_file_as_string("res://steps/%s/props/%s" % [step, file])
				_expect(failures, text.begins_with("[gd_resource type=\"Resource\"") and text.contains("res://steps/%s/prop_set.gd" % step) and text.contains("scenes = Array[PackedScene]") and text.contains("weights = Array[float]"), "%s/props/%s is not a prop set resource of its own step" % [step, file])
	for step in STEPS:
		var weights_source := FileAccess.get_file_as_string("res://steps/%s/room_weights.gd" % step)
		_expect(failures, weights_source.contains("extends Resource") and weights_source.count("func ") == 1 and weights_source.contains("func weight_of(type: int) -> float:"), "%s/room_weights.gd is not a data Resource with one lookup" % step)
		var text := FileAccess.get_file_as_string("res://steps/%s/room_weights.tres" % step)
		_expect(failures, text.contains("res://steps/%s/room_weights.gd" % step), "%s/room_weights.tres does not use its own step's script" % step)
		var chain_source := FileAccess.get_file_as_string("res://steps/%s/room_chain.gd" % step)
		var chain_code := "\n".join(_code_lines("res://steps/%s/room_chain.gd" % step))
		_expect(failures, not chain_code.contains("_shuffled_types") and not chain_code.contains(".shuffle(") and chain_code.contains("func _weighted_types() -> Array[int]:"), "%s: the chain still shuffles the room types" % step)
		_expect(failures, chain_source.contains("ROOM_WEIGHTS.weight_of(type)"), "%s: the chain does not read its room weights from the Resource" % step)
	return failures

#endregion

#region Tutorial 05: props, scenes and spots

func _prop_scene(step: String, prop_name: String) -> PackedScene:
	return load("res://steps/%s/props/%s.tscn" % [step, prop_name]) as PackedScene

## The top of a prop's collision shapes, in metres above the floor.
func _prop_height(prop: Node) -> float:
	var top := 0.0
	for child in prop.get_children():
		var shape_node := child as CollisionShape3D
		if shape_node == null:
			continue
		var half_height := 0.0
		if shape_node.shape is BoxShape3D:
			half_height = (shape_node.shape as BoxShape3D).size.y / 2.0
		elif shape_node.shape is CylinderShape3D:
			half_height = (shape_node.shape as CylinderShape3D).height / 2.0
		top = maxf(top, shape_node.position.y + half_height)
	return top

func test_prop_scenes(step: String) -> Array[String]:
	var failures: Array[String] = []
	var expected: Dictionary[String, Vector2] = { # the footprint in metres: width (x) and depth (z)
		"crate": Vector2(1.0, 1.0), "stack": Vector2(1.2, 1.2), "table": Vector2(1.6, 0.9), "shelf": Vector2(1.6, 0.4), "pillar": Vector2(0.7, 0.7),
	}
	var heights: Dictionary[String, Vector2] = { # the allowed range of the height
		"crate": Vector2(0.99, 1.01), "stack": Vector2(1.7, 1.9), "table": Vector2(0.75, 1.0), "shelf": Vector2(1.8, 2.2), "pillar": Vector2(2.99, 3.0),
	}
	var files := DirAccess.get_files_at("res://steps/%s/props" % step)
	var scene_files: Array[String] = []
	for file in files:
		if file.ends_with(".tscn"):
			scene_files.append(file)
	scene_files.sort()
	var wanted: Array[String] = []
	for prop_name in PROP_NAMES:
		wanted.append(prop_name + ".tscn")
	wanted.sort()
	_expect(failures, scene_files == wanted, "props/ has %s, expected %s" % [scene_files, wanted])
	for prop_name in PROP_NAMES:
		var scene := _prop_scene(step, prop_name)
		var prop := scene.instantiate()
		var label := "%s/props/%s.tscn" % [step, prop_name]
		_expect(failures, prop is StaticBody3D and prop.get_script() == null, "%s: the root is not a plain StaticBody3D" % label)
		var body := prop as StaticBody3D
		_expect(failures, body != null and body.collision_layer == 1, "%s: collision layer %d, expected 1 (the world layer: the player collides with it)" % [label, body.collision_layer if body != null else -1])
		var shapes := 0
		var meshes := 0
		for node in prop.find_children("*", "", true, false):
			if node is CollisionShape3D:
				shapes += 1
				_expect(failures, (node as CollisionShape3D).shape is BoxShape3D or (node as CollisionShape3D).shape is CylinderShape3D, "%s: %s has a shape the footprint check does not know" % [label, node.name])
			elif node is MeshInstance3D:
				meshes += 1
				var mesh := (node as MeshInstance3D).mesh
				_expect(failures, mesh is PrimitiveMesh and (mesh as PrimitiveMesh).material != null and (mesh as PrimitiveMesh).material.resource_path == MATERIAL_DIR + "prop.tres", "%s: %s does not use prop.tres" % [label, node.name])
				_expect(failures, (node as MeshInstance3D).layers == 1, "%s: %s is not on render layer 1 only" % [label, node.name])
		_expect(failures, shapes >= 1 and meshes >= 1, "%s: %d shapes and %d meshes" % [label, shapes, meshes])
		var foot := Contents.footprint(scene, Transform3D.IDENTITY)
		_expect(failures, absf(foot.size.x - expected[prop_name].x) < 0.01 and absf(foot.size.y - expected[prop_name].y) < 0.01, "%s: the footprint is %.2f x %.2f m, expected %.1f x %.1f" % [label, foot.size.x, foot.size.y, expected[prop_name].x, expected[prop_name].y])
		_expect(failures, absf(foot.end.y) < 0.001 and absf(foot.get_center().x) < 0.06, "%s: the footprint %s does not sit with its back edge at z = 0, centred on x" % [label, foot])
		var height := _prop_height(prop)
		_expect(failures, height >= heights[prop_name].x and height <= heights[prop_name].y, "%s: %.2f m high, expected %.2f to %.2f" % [label, height, heights[prop_name].x, heights[prop_name].y])
		# What is drawn is what is solid: the meshes cover the same floor as the shapes.
		var drawn := Rect2()
		var first := true
		for node in prop.find_children("*", "MeshInstance3D", true, false):
			var box := (node as MeshInstance3D).transform * (node as MeshInstance3D).mesh.get_aabb()
			var rect := Rect2(Vector2(box.position.x, box.position.z), Vector2(box.size.x, box.size.z))
			drawn = rect if first else drawn.merge(rect)
			first = false
		_expect(failures, absf(drawn.position.x - foot.position.x) < 0.05 and absf(drawn.end.x - foot.end.x) < 0.05 and absf(drawn.position.y - foot.position.y) < 0.05 and absf(drawn.end.y - foot.end.y) < 0.05, "%s: the meshes cover %s but the shapes %s" % [label, drawn, foot])
		prop.free()
	return failures

func test_prop_spots(step: String) -> Array[String]:
	var failures: Array[String] = []
	var finals := _final_spots()
	for room_type in ROOM_TYPES:
		var room := (load("res://steps/%s/room_%s.tscn" % [step, room_type]) as PackedScene).instantiate() as Node3D
		var label := "%s room_%s" % [step, room_type]
		var container := room.get_node_or_null("PropSpots")
		_expect(failures, container != null and container is Node3D and (container as Node3D).transform == Transform3D.IDENTITY, "%s has no PropSpots node at the room's origin" % label)
		if container == null:
			room.free()
			continue
		var spots: Array[Marker3D] = []
		for child in container.get_children():
			_expect(failures, child is Marker3D, "%s/PropSpots/%s is not a Marker3D" % [label, child.name])
			spots.append(child as Marker3D)
		_expect(failures, spots.size() >= 4 and spots.size() <= 6, "%s has %d prop spots, expected 4 to 6" % [label, spots.size()])
		var floor_box := _floor_box(room)
		var half := Vector2(floor_box.size.x, floor_box.size.z) / 2.0 - Vector2(WALL_THICKNESS, WALL_THICKNESS) # the inside of the walls
		var entrance := room.get_node("Entrance") as Marker3D
		var exit_point := room.get_node("Exit") as Marker3D
		var line_from := Vector2(entrance.position.x, entrance.position.z)
		var line_to := Vector2(exit_point.position.x, exit_point.position.z)
		var keys: Array[Vector2] = []
		for key in room.get_node("KeySpots").get_children():
			keys.append(Vector2((key as Marker3D).position.x, (key as Marker3D).position.z))
		for i in spots.size():
			var spot := spots[i]
			var at := Vector2(spot.position.x, spot.position.z)
			var front := Vector2(-spot.transform.basis.z.x, -spot.transform.basis.z.z)
			var name := "%s %s" % [label, spot.name]
			_expect(failures, is_zero_approx(spot.position.y), "%s is %.2f m above the floor" % [name, spot.position.y])
			_expect(failures, spot.transform.basis.y.is_equal_approx(Vector3.UP) and (is_equal_approx(absf(front.x), 1.0) and is_zero_approx(front.y) or is_equal_approx(absf(front.y), 1.0) and is_zero_approx(front.x)), "%s does not face along an axis of the room (front %s)" % [name, front])
			# The back of a prop is against the wall behind the spot, 5 cm away from it, and the prop faces into the room.
			var along_half := half.x if absf(front.x) > 0.5 else half.y
			var back_distance := at.dot(front) + along_half
			_expect(failures, absf(back_distance - 0.05) < 0.001, "%s is %.3f m from the wall behind it, expected 0.05" % [name, back_distance])
			_expect(failures, (Vector2.ZERO - at).dot(front) > 1.0, "%s does not face into the room" % name)
			_expect(failures, Geometry2D.get_closest_point_to_segment(at, line_from, line_to).distance_to(at) >= Contents.CORRIDOR_WIDTH / 2.0, "%s is on the walking line from the entrance to the exit" % name)
			for key in keys:
				_expect(failures, at.distance_to(key) >= 1.0, "%s is %.2f m from a key spot" % [name, at.distance_to(key)])
			for j in range(i + 1, spots.size()):
				_expect(failures, at.distance_to(Vector2(spots[j].position.x, spots[j].position.z)) >= 1.5, "%s and %s are less than 1.5 m apart" % [name, spots[j].name])
			# Every step puts them where the finished rooms have them.
			_expect(failures, i < (finals[room_type] as Array).size() and (finals[room_type] as Array)[i] == spot.transform, "%s is not where the finished room has it" % name)
		_expect(failures, spots.size() == (finals[room_type] as Array).size(), "%s has %d prop spots, the finished room has %d" % [label, spots.size(), (finals[room_type] as Array).size()])
		room.free()
	var goal := (load("res://steps/%s/room_goal.tscn" % step) as PackedScene).instantiate()
	_expect(failures, goal.get_node_or_null("PropSpots") == null, "%s: the goal room has prop spots" % step)
	goal.free()
	return failures

## The prop spots of the finished rooms, by room type: the spot transforms in scene order.
func _final_spots() -> Dictionary:
	var spots := {}
	for room_type in ROOM_TYPES:
		var room := (load("res://steps/%s/room_%s.tscn" % [FINAL_STEP, room_type]) as PackedScene).instantiate() as Node3D
		var list: Array[Transform3D] = []
		for child in room.get_node("PropSpots").get_children():
			list.append((child as Marker3D).transform)
		spots[room_type] = list
		room.free()
	return spots

## The prop bodies in a room: direct children that are static bodies (the door's hinge is deeper down).
func _props_in(room: Node3D) -> Array[Node3D]:
	var found: Array[Node3D] = []
	for child in room.get_children():
		if child is StaticBody3D and not child.is_queued_for_deletion():
			found.append(child as Node3D)
	return found

## How many prop spots a room type of a step has, by the type's name in the Type enum ("goal" has none).
func _prop_spot_count(step: String, type_name: String) -> int:
	if type_name == "goal":
		return 0
	var room := (load("res://steps/%s/room_%s.tscn" % [step, type_name]) as PackedScene).instantiate()
	var count := room.get_node("PropSpots").get_child_count()
	room.free()
	return count

func test_prop_determinism(step: String) -> Array[String]:
	var failures: Array[String] = []
	var chain_script := _chain_script(step)
	var first := _plans(chain_script, 42, 100)
	var second := _plans(chain_script, 42, 100)
	var other := _plans(chain_script, 43, 100)
	var any_props := 0
	var props_differ := false
	for i in first.size():
		var plan: Object = first[i]
		var type_name := _room_name(chain_script, plan.type)
		var spot_count := _prop_spot_count(step, type_name)
		_expect(failures, plan.props.size() == spot_count, "room %d (%s) has %d props for %d prop spots" % [i, type_name, plan.props.size(), spot_count])
		var kinds := 0
		if plan.props.size() > 0:
			kinds = chain_script.PROP_SETS[plan.type].scenes.size()
		for prop: int in plan.props:
			_expect(failures, prop >= -1 and prop < kinds, "room %d holds prop %d of %d" % [i, prop, kinds])
			any_props += 1 if prop >= 0 else 0
		_expect(failures, plan.props == second[i].props, "seed 42 twice: room %d has other props" % i)
		props_differ = props_differ or plan.props != other[i].props
	_expect(failures, any_props >= 100, "only %d props in 100 rooms" % any_props)
	_expect(failures, props_differ, "seed 43 has the props of seed 42")
	# A room's props depend on the seed, the room's index and its type only: not on the lock chance, not on the goal room.
	for chance: float in [0.0, 1.0]:
		var again := _plans(chain_script, 42, 100, chance)
		for i in 100:
			_expect(failures, again[i].props == first[i].props, "room %d has other props at lock chance %.1f" % [i, chance])
	var near := _plans_to_goal(chain_script, 42, 12)
	for i in 12:
		_expect(failures, near.plans[i].props == first[i].props, "room %d has other props with a goal room at 12" % i)
	# The goal room holds nothing.
	var goal_plan: Object = near.plans[-1]
	_expect(failures, goal_plan.type == _goal_type(chain_script) and goal_plan.props.is_empty(), "the goal room holds %s" % [goal_plan.props])
	return failures

func test_props_in_level(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step, true, {"goal_room": 20})
	var level: Node3D = main.get_node("Level")
	var checked := {}
	var built := [0]
	var pilot := Autopilot.new(level)
	var on_tick := func() -> void:
		for index: int in level.rooms.keys():
			if checked.has(index):
				continue
			checked[index] = true
			failures.append_array(_room_props_problems(step, level, index))
			built[0] += _props_in(level.rooms[index]).size()
	_fast_forward(true)
	var arrived := await _walk(level, pilot, 8, 0, on_tick)
	_fast_forward(false)
	_expect(failures, arrived, "%s: the player did not reach room 8" % step)
	_expect(failures, built[0] >= 15, "%s: only %d props were built in the first 9 rooms" % [step, built[0]])
	# Props go with their room: no prop body is left in the tree that does not belong to a live room.
	await _wait_physics(5)
	var expected := 0
	for index: int in level.rooms.keys():
		for placed: int in level.chain.plans[index].props:
			expected += 1 if placed != Chain.NO_PROP else 0
	var in_tree := 0
	for body in level.find_children("*", "StaticBody3D", true, false):
		if not body.is_queued_for_deletion() and body.get_parent().get("prop_spots") != null:
			in_tree += 1
	_expect(failures, in_tree == expected, "%s: %d prop bodies in the tree, the live rooms hold %d" % [step, in_tree, expected])
	# R builds room 0 again with its props, and the old rooms' props are gone.
	await _action("regenerate")
	await _wait_physics(5)
	failures.append_array(_room_props_problems(step, level, 0))
	in_tree = 0
	for body in level.find_children("*", "StaticBody3D", true, false):
		if not body.is_queued_for_deletion() and body.get_parent().get("prop_spots") != null:
			in_tree += 1
	_expect(failures, in_tree == _props_in(level.rooms[0]).size(), "%s: %d prop bodies after R, room 0 holds %d" % [step, in_tree, _props_in(level.rooms[0]).size()])
	await _unload(main)
	return failures

## Everything a plan says about the props of one live room, checked against the room: as problems.
func _room_props_problems(step: String, level: Node3D, index: int) -> Array[String]:
	var problems: Array[String] = []
	var room: Node3D = level.rooms[index]
	var plan: Object = level.chain.plans[index]
	var bodies := _props_in(room)
	var placed: Array[int] = []
	for i: int in plan.props.size():
		if plan.props[i] != Chain.NO_PROP:
			placed.append(i)
	var where := "%s room %d" % [step, index]
	_expect(problems, bodies.size() == placed.size(), "%s: %d props in the room, the plan places %d" % [where, bodies.size(), placed.size()])
	_expect(problems, (room.get("prop_spots") as Array).size() == plan.props.size(), "%s: the room has %d prop spots, the plan %d entries" % [where, (room.get("prop_spots") as Array).size(), plan.props.size()])
	for k in mini(bodies.size(), placed.size()):
		var spot: Marker3D = (room.get("prop_spots") as Array)[placed[k]]
		var scene: PackedScene = level.chain.prop_scene(plan.type, plan.props[placed[k]])
		_expect(problems, bodies[k].transform == spot.transform and bodies[k].get_parent() == room, "%s: prop %d is not on its spot %d" % [where, k, placed[k]])
		_expect(problems, bodies[k].scene_file_path == scene.resource_path, "%s: prop %d is %s, the plan says %s" % [where, k, bodies[k].scene_file_path, scene.resource_path])
		_expect(problems, (plan.bounds as AABB).has_point(bodies[k].global_position + Vector3(0.0, 0.5, 0.0)), "%s: prop %d is outside its room" % [where, k])
	return problems

#endregion

#region Tutorial 05: the spot rules, exhaustively

## The rules of check_contents.gd, for every prop at every spot of every room type, and for every pair of spots:
## whatever the dice give, the rules hold. Every set is widened to all five props for this, so step 1's "any prop
## anywhere" is covered, too; the sets are put back afterwards.
func test_prop_spot_rules() -> Array[String]:
	var failures: Array[String] = []
	var layouts := Contents.read_layouts()
	var chain := Chain.new(1, 20)
	var all_five: Array[PackedScene] = []
	for prop_name in PROP_NAMES:
		all_five.append(_prop_scene(FINAL_STEP, prop_name))
	var ones: Array[float] = [1.0, 1.0, 1.0, 1.0, 1.0]
	var saved_scenes: Array[Array] = []
	var saved_weights: Array[Array] = []
	for prop_set in Chain.PROP_SETS:
		saved_scenes.append(prop_set.scenes.duplicate())
		saved_weights.append(prop_set.weights.duplicate())
		prop_set.scenes = all_five
		prop_set.weights = ones
	var singles := 0
	var pairs := 0
	for type in Chain.PROP_SETS.size():
		var spot_count := layouts[type].prop_spots.size()
		_expect(failures, spot_count >= 3, "%s has %d prop spots" % [_room_name(Chain, type), spot_count])
		for spot in spot_count:
			for prop in all_five.size():
				var plan := _plan_with(type, spot_count, {spot: prop})
				singles += 1
				for problem in Contents._room_problems(chain, plan, layouts[type]):
					failures.append(problem)
				for other in range(spot + 1, spot_count):
					for other_prop in all_five.size():
						pairs += 1
						for problem in Contents._room_problems(chain, _plan_with(type, spot_count, {spot: prop, other: other_prop}), layouts[type]):
							failures.append(problem)
		if failures.size() > 8:
			break
	for type in Chain.PROP_SETS.size():
		Chain.PROP_SETS[type].scenes = saved_scenes[type]
		Chain.PROP_SETS[type].weights = saved_weights[type]
	print("        %d single props and %d pairs of props over the prop spots of %d room types: no rule broken" % [singles, pairs, Chain.PROP_SETS.size()])
	return failures

## A plan of this room type whose prop spots are empty but for the ones given (spot -> prop index).
func _plan_with(type: int, spot_count: int, placed: Dictionary) -> Chain.Plan:
	var plan := Chain.Plan.new(0, type, Transform3D.IDENTITY, AABB())
	for spot in spot_count:
		plan.props.append(int(placed[spot]) if placed.has(spot) else Chain.NO_PROP)
	return plan

func test_props_are_solid() -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(FINAL_STEP, true, {"goal_room": 6, "lock_chance": 0.0})
	var level: Node3D = main.get_node("Level")
	var player: CharacterBody3D = level.player
	var room: Node3D = level.rooms[0]
	var bodies := _props_in(room)
	_expect(failures, bodies.size() >= 2, "room 0 holds only %d props" % bodies.size())
	var tested := 0
	for body in bodies:
		var depth := Contents.footprint(load(body.scene_file_path) as PackedScene, Transform3D.IDENTITY).size.y
		var front: Vector3 = -body.transform.basis.z # the way the prop faces
		var face := body.global_position + front * depth # the middle of its front face on the floor
		var start := face + front * 2.0
		var local_start: Vector3 = room.global_transform.affine_inverse() * start
		if absf(local_start.x) > 4.0 or absf(local_start.z) > 4.0:
			continue
		var clear := true
		for other in bodies:
			if other != body:
				clear = clear and other.global_position.distance_to(start) > 2.2
		if not clear:
			continue
		# A ray at the height of a hip hits the prop from the front.
		var ray := PhysicsRayQueryParameters3D.create(face + front * 1.0 + Vector3(0.0, 0.5, 0.0), face - front * 0.2 + Vector3(0.0, 0.5, 0.0))
		var hit := level.get_world_3d().direct_space_state.intersect_ray(ray)
		_expect(failures, not hit.is_empty() and hit["collider"] == body, "a ray at 0.5 m does not hit %s" % body.name)
		# The player walks into it from 2 m away and stops at its face.
		player.global_position = start
		player.rotation.y = atan2(front.x, front.z) # facing -front, which is -Z of the player's own basis
		player.velocity = Vector3.ZERO
		await _wait_physics(3)
		Input.action_press("move_forward")
		await _wait_physics(80)
		Input.action_release("move_forward")
		var stopped := (player.global_position - face).dot(front)
		_expect(failures, stopped > 0.38 and stopped < 0.6, "%s: the player stopped %.2f m from the face, expected the capsule radius (0.4) plus a skin" % [body.name, stopped])
		_expect(failures, absf(player.global_position.y) < 0.05, "%s: the player climbed or fell (y = %.2f)" % [body.name, player.global_position.y])
		tested += 1
	_expect(failures, tested >= 1, "no prop of room 0 could be walked into")
	await _unload(main)
	return failures

#endregion

#region Tutorial 05: prop sets, the weighted pick, room weights

func test_prop_sets(step: String) -> Array[String]:
	var failures: Array[String] = []
	var chain_script := _chain_script(step)
	var names: Array[String] = ["straight", "long", "turn_left", "turn_right", "wide", "vault"]
	var prop_set_script := load("res://steps/%s/prop_set.gd" % step) as GDScript
	_expect(failures, chain_script.PROP_SETS.size() == names.size(), "%s: %d sets for %d room types" % [step, chain_script.PROP_SETS.size(), names.size()])
	var share_of := func(prop_set: Resource, wanted: Array[String]) -> float:
		var part := 0.0
		var total := 0.0
		for i: int in prop_set.scenes.size():
			total += prop_set.weights[i]
			if wanted.has((prop_set.scenes[i] as PackedScene).resource_path.get_file().get_basename()):
				part += prop_set.weights[i]
		return part / total
	for i in names.size():
		var path := "res://steps/%s/props/%s_set.tres" % [step, names[i]]
		var prop_set := load(path) as Resource
		_expect(failures, prop_set != null and prop_set.get_script() == prop_set_script, "%s is not a PropSet of its own step" % path)
		if prop_set == null:
			continue
		_expect(failures, chain_script.PROP_SETS[i] == prop_set, "%s: PROP_SETS[%d] is not %s_set.tres" % [step, i, names[i]])
		var scenes: Array = prop_set.scenes
		var weights: Array = prop_set.weights
		_expect(failures, scenes.size() == weights.size() and scenes.size() >= 3, "%s has %d scenes and %d weights" % [path, scenes.size(), weights.size()])
		var total: float = prop_set.empty_weight
		var seen := {}
		for k in mini(scenes.size(), weights.size()):
			total += weights[k]
			_expect(failures, weights[k] > 0.0, "%s: weight %d is %s" % [path, k, weights[k]])
			var scene_path: String = (scenes[k] as PackedScene).resource_path
			_expect(failures, scene_path.begins_with("res://steps/%s/props/" % step) and PROP_NAMES.has(scene_path.get_file().get_basename()) and not seen.has(scene_path), "%s: scene %d (%s) is not one of this step's props, or is listed twice" % [path, k, scene_path])
			seen[scene_path] = true
		_expect(failures, prop_set.empty_weight >= 0.0 and total > 0.0, "%s: empty weight %s, total %s" % [path, prop_set.empty_weight, total])
		var empty_share: float = prop_set.empty_weight / total
		_expect(failures, empty_share >= 0.1 and empty_share <= 0.6, "%s: %.0f percent of the spots stay empty" % [path, empty_share * 100.0])
		# Each room type has its own flavour.
		var typed := names[i]
		if typed == "long":
			var best := 0
			for k in weights.size():
				best = k if weights[k] > weights[best] else best
			_expect(failures, (scenes[best] as PackedScene).resource_path.ends_with("pillar.tscn"), "%s: the long hall does not favour pillars" % path)
		elif typed == "wide":
			_expect(failures, share_of.call(prop_set, ["table", "shelf"] as Array[String]) >= 0.5, "%s: tables and shelves are not most of the wide room" % path)
		elif typed == "vault":
			_expect(failures, share_of.call(prop_set, ["shelf", "crate", "stack"] as Array[String]) == 1.0, "%s: the vault holds more than shelves, crates and stacks" % path)
		elif typed == "straight":
			_expect(failures, scenes.size() == 5, "%s: the straight room does not use all five props" % path)
	return failures

func test_weighted_pick() -> Array[String]:
	var failures: Array[String] = []
	for step in STEPS:
		var chain_script := _chain_script(step)
		var pick := func(weights: Array[float], roll: float) -> int: return chain_script.weighted_pick(weights, roll)
		var two: Array[float] = [1.0, 3.0]
		_expect(failures, pick.call(two, 0.0) == 0 and pick.call(two, 0.2499) == 0 and pick.call(two, 0.25) == 1 and pick.call(two, 0.9999999) == 1, "%s: [1, 3] splits at a quarter" % step)
		var holes: Array[float] = [0.0, 2.0, 0.0, 2.0]
		_expect(failures, pick.call(holes, 0.0) == 1 and pick.call(holes, 0.4999) == 1 and pick.call(holes, 0.5) == 3 and pick.call(holes, 0.9999999) == 3, "%s: a weight of 0 is picked: %s %s %s %s" % [step, pick.call(holes, 0.0), pick.call(holes, 0.4999), pick.call(holes, 0.5), pick.call(holes, 0.9999999)])
		var single: Array[float] = [5.0]
		_expect(failures, pick.call(single, 0.0) == 0 and pick.call(single, 0.99) == 0, "%s: one weight is not picked" % step)
		var shares: Array[float] = [5.0, 2.0, 2.0, 1.0]
		var counts := [0, 0, 0, 0]
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for i in 100000:
			counts[pick.call(shares, rng.randf())] += 1
		for k in 4:
			_expect(failures, absf(counts[k] / 100000.0 - shares[k] / 10.0) < 0.01, "%s: weight %s came up %.3f of the time, expected %.3f" % [step, shares[k], counts[k] / 100000.0, shares[k] / 10.0])
	return failures

## The data decides: what a set holds shows in the plans in proportion, and a changed Resource changes the plans.
func test_prop_distribution() -> Array[String]:
	var failures: Array[String] = []
	var counts: Dictionary[int, Dictionary] = {} # room type -> scene path (or "") -> number of spots
	for chain_seed in range(1, PROP_SEEDS + 1):
		if chain_seed % 50 == 0:
			await process_frame
		for plan: Object in _plans_to_goal(Chain, chain_seed, 20).plans:
			for k: int in plan.props.size():
				var per_type: Dictionary = counts.get_or_add(plan.type, {})
				var key := "" if plan.props[k] == Chain.NO_PROP else (Chain.PROP_SETS[plan.type].scenes[plan.props[k]] as PackedScene).resource_path
				per_type[key] = int(per_type.get(key, 0)) + 1
	var summary := ""
	for type: int in counts:
		var prop_set: Resource = Chain.PROP_SETS[type]
		var per_type: Dictionary = counts[type]
		var spots := 0
		for key: String in per_type:
			spots += per_type[key]
		var total: float = prop_set.empty_weight
		for weight: float in prop_set.weights:
			total += weight
		var tolerance := 4.0 * sqrt(0.25 / spots) + 0.005
		var empty_share := float(per_type.get("", 0)) / spots
		_expect(failures, spots >= 200 and absf(empty_share - prop_set.empty_weight / total) < tolerance, "%s: %.3f of %d spots are empty, the set says %.3f" % [_room_name(Chain, type), empty_share, spots, prop_set.empty_weight / total])
		for k: int in prop_set.scenes.size():
			var share := float(per_type.get((prop_set.scenes[k] as PackedScene).resource_path, 0)) / spots
			_expect(failures, absf(share - prop_set.weights[k] / total) < tolerance, "%s: %s is %.3f of the spots, the set says %.3f" % [_room_name(Chain, type), (prop_set.scenes[k] as PackedScene).resource_path.get_file().get_basename(), share, prop_set.weights[k] / total])
		summary += " %s %d spots, %.0f percent empty;" % [_room_name(Chain, type), spots, empty_share * 100.0]
	print("       ", summary)

	# Change the data, change the plans: no code is touched. The straight set with no empty spots left, and the long set empty.
	var straight_set: Resource = Chain.PROP_SETS[Chain.Type.STRAIGHT]
	var long_set: Resource = Chain.PROP_SETS[Chain.Type.LONG]
	var saved_straight: float = straight_set.empty_weight
	var saved_long: float = long_set.empty_weight
	straight_set.empty_weight = 0.0
	long_set.empty_weight = 1.0e9
	var filled := 0
	var straight_spots := 0
	var long_props := 0
	var rooms_equal := true
	var reference: Array = _plans_to_goal(Chain, 42, 20).plans
	for chain_seed in range(1, 101):
		for plan: Object in _plans_to_goal(Chain, chain_seed, 20).plans:
			if plan.type == Chain.Type.STRAIGHT:
				straight_spots += plan.props.size()
				filled += plan.props.filter(func(prop: int) -> bool: return prop != Chain.NO_PROP).size()
			elif plan.type == Chain.Type.LONG:
				long_props += plan.props.filter(func(prop: int) -> bool: return prop != Chain.NO_PROP).size()
	var changed: Array = _plans_to_goal(Chain, 42, 20).plans
	for i in reference.size():
		rooms_equal = rooms_equal and reference[i].type == changed[i].type and reference[i].transform == changed[i].transform and reference[i].locked == changed[i].locked
	straight_set.empty_weight = saved_straight
	long_set.empty_weight = saved_long
	_expect(failures, straight_spots > 0 and filled == straight_spots, "with an empty weight of 0 %d of %d straight-room spots hold a prop" % [filled, straight_spots])
	_expect(failures, long_props == 0, "with a huge empty weight %d props still stand in long halls" % long_props)
	_expect(failures, rooms_equal, "changing a prop set moved a room or a lock")
	return failures

func test_room_weights(step: String) -> Array[String]:
	var failures: Array[String] = []
	var chain_script := _chain_script(step)
	var weights_script := load("res://steps/%s/room_weights.gd" % step) as GDScript
	var weights := load("res://steps/%s/room_weights.tres" % step) as Resource
	_expect(failures, weights != null and weights.get_script() == weights_script and chain_script.ROOM_WEIGHTS == weights, "%s: room_weights.tres is not the chain's ROOM_WEIGHTS" % step)
	var has_vault := true
	var names: Array[String] = ["straight", "long", "turn_left", "turn_right", "wide", "vault"]
	var ordinary_minimum := INF
	for i in names.size():
		var weight: float = weights.get(names[i])
		_expect(failures, weight > 0.0 and weight <= 6.0 and weights.weight_of(i) == weight, "%s: weight of %s is %s, weight_of(%d) is %s" % [step, names[i], weight, i, weights.weight_of(i)])
		if names[i] != "vault":
			ordinary_minimum = minf(ordinary_minimum, weight)
	_expect(failures, weights.straight == 2.0 and weights.long == 2.0 and weights.turn_left == 3.0 and weights.turn_right == 3.0 and weights.wide == 1.0, "%s: the tuned weights are 2, 2, 3, 3, 1 (straight, long, turn left, turn right, wide)" % step)
	if has_vault:
		_expect(failures, weights.vault <= ordinary_minimum and weights.min_gap >= 4 and weights.min_gap == 8, "%s: the vault weight %s is not the rarest, or min_gap is %s" % [step, weights.vault, weights.min_gap])
	# The data decides the order: a huge weight for straight makes nearly every room straight, then the weights are put back.
	var saved: float = weights.straight
	weights.straight = 1.0e6
	var straight := 0
	var total := 0
	for plan: Object in _plans(chain_script, 42, 60):
		total += 1
		straight += 1 if plan.type == 0 else 0
	weights.straight = saved
	_expect(failures, straight >= total - 2, "%s: with a straight weight of a million only %d of %d rooms are straight" % [step, straight, total])
	var first := _plans(chain_script, 42, 60)
	var second := _plans(chain_script, 42, 60)
	_expect(failures, _same_plans(first, second), "%s: the weighted order is not the same for the same seed" % step)
	return failures

func test_weighted_rooms() -> Array[String]:
	var failures: Array[String] = []
	# The mix of the rooms over 1000 seeds: the realised shares, which the heading and overlap rules bend.
	var counts := {}
	var total := 0
	var longest_straight_run := 0
	for chain_seed in range(1, SEED_COUNT + 1):
		if chain_seed % 100 == 0:
			await process_frame
		var run := 0
		for plan: Object in _plans_to_goal(Chain, chain_seed, 20).plans:
			if plan.type == Chain.Type.GOAL:
				break
			counts[plan.type] = int(counts.get(plan.type, 0)) + 1
			total += 1
			run = run + 1 if plan.type == Chain.Type.STRAIGHT else 0
			longest_straight_run = maxi(longest_straight_run, run)
	var shares := {}
	for type: int in counts:
		shares[_room_name(Chain, type)] = snappedf(float(counts[type]) / total, 0.001)
	print("        room mix, seeds 1-%d, rooms before the goal: %s, longest run of straight rooms %d" % [SEED_COUNT, shares, longest_straight_run])
	_expect(failures, counts.size() == 6, "only %d room types in 1000 runs" % counts.size())
	_expect(failures, shares["straight"] > 0.2 and shares["straight"] < 0.34, "straight rooms are %.3f of the mix" % shares["straight"])
	_expect(failures, shares["wide"] < shares["turn_left"] and shares["wide"] < shares["turn_right"] and shares["wide"] < shares["long"], "the wide room (weight 1) is not rarer than the others")
	_expect(failures, longest_straight_run <= 8, "a run of %d straight rooms" % longest_straight_run)

	# The first try of the weighted order follows the weights (nothing to filter yet: the vault is allowed). The order of a room
	# comes from the room's own stream, so the draws are spread over 20000 room numbers (a chain with that many empty plans:
	# only plans.size() is read).
	for step in STEPS:
		var chain_script := _chain_script(step)
		var chain: RefCounted = _new_chain(chain_script, 1, 20)
		var firsts := {}
		var order_problems := 0
		var drawn: float = 20000.0
		for i in 20000:
			chain.plans.resize(i)
			var order: Array[int] = chain._weighted_types()
			firsts[order[0]] = int(firsts.get(order[0], 0)) + 1
			var distinct := {}
			for type in order:
				distinct[type] = true
			if distinct.size() != order.size() or order.has(_goal_type(chain_script)):
				order_problems += 1
		_expect(failures, order_problems == 0, "%s: %d weighted orders repeat a type or contain the goal room" % [step, order_problems])
		var weight_sum := 0.0
		var kinds := _goal_type(chain_script)
		for type in kinds:
			weight_sum += chain_script.ROOM_WEIGHTS.weight_of(type)
		for type in kinds:
			var expected: float = chain_script.ROOM_WEIGHTS.weight_of(type) / weight_sum
			_expect(failures, absf(float(firsts.get(type, 0)) / drawn - expected) < 0.015, "%s: type %d is tried first in %.3f of the orders, the weights say %.3f" % [step, type, float(firsts.get(type, 0)) / drawn, expected])
	return failures

#endregion

#region Tutorial 05: the vault

func test_vault_room() -> Array[String]:
	var failures: Array[String] = []
	for step in STEPS:
		var room := (load("res://steps/%s/room_vault.tscn" % step) as PackedScene).instantiate() as Node3D
		root.add_child(room)
		(room.get("door") as Node).free() # the room puts a closed door in its exit; this test is about the hall
		await _wait_physics(5)
		var label := "%s room_vault" % step
		var floor_box := _floor_box(room)
		_expect(failures, _near(floor_box.size.x, 14.0) and _near(floor_box.size.z, 14.0), "%s: the floor is %.1f x %.1f m, expected 14 x 14" % [label, floor_box.size.x, floor_box.size.z])
		var entrance := room.get_node("Entrance") as Marker3D
		var exit_point := room.get_node("Exit") as Marker3D
		_expect(failures, entrance.position.is_equal_approx(Vector3(0.0, 0.0, 7.0)) and exit_point.position.is_equal_approx(Vector3(0.0, 0.0, -7.0)) and exit_point.transform.basis.is_equal_approx(Basis.IDENTITY), "%s: entrance %s and exit %s are not opposite" % [label, entrance.position, exit_point.position])
		var space := room.get_world_3d().direct_space_state

		# Four pillars, 1 m thick, from the floor to the ceiling, solid.
		var pillars := _parts_named(room, "Pillar")
		_expect(failures, pillars.size() == 4, "%s: %d pillars, expected 4" % [label, pillars.size()])
		for pillar in pillars:
			var part := _part(room, pillar)
			var box: AABB = part.box
			var centre := box.get_center()
			_expect(failures, _near(box.size.x, 1.0) and _near(box.size.z, 1.0) and _near(box.size.y, WALL_HEIGHT) and _near(box.position.y, 0.0), "%s: %s is %.2f m wide and %.2f m high" % [label, pillar.name, box.size.x, box.size.y])
			_expect(failures, absf(absf(centre.x) - 4.5) < 0.001 and absf(absf(centre.z) - 4.5) < 0.001, "%s: %s stands at %s, expected (+-4.5, +-4.5)" % [label, pillar.name, centre])
			_expect(failures, part.material == MATERIAL_DIR + "wall.tres", "%s: %s is not in wall.tres" % [label, pillar.name])
			var side := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(centre.x, 1.5, centre.z - 2.0), Vector3(centre.x, 1.5, centre.z + 2.0)))
			_expect(failures, not side.is_empty() and absf((side["position"] as Vector3).z - (centre.z - 0.5)) < 0.05, "%s: a ray at %s hits the pillar at %s" % [label, pillar.name, side.get("position")])

		# A raised platform in the middle: 6 x 6 m, 0.12 m high (a step the capsule climbs), in the wall material, across the way.
		# CSG: one box called Platform; the kit: four plinths of 3 x 3 m side by side.
		var platform_parts: Array[Node3D] = [room.get_node_or_null("Shell/Platform") as Node3D]
		if _is_kit_room(room):
			platform_parts = _parts_named(room, "Plinth")
		var platform := AABB()
		var area := 0.0
		for i in platform_parts.size():
			var part := _part(room, platform_parts[i])
			var box: AABB = part.box
			platform = box if i == 0 else platform.merge(box)
			area += box.size.x * box.size.z
			_expect(failures, part.material == MATERIAL_DIR + "wall.tres", "%s: the platform is not in wall.tres: only doors, keys and the goal take an accent colour" % label)
		_expect(failures, _near(platform.size.x, 6.0) and _near(platform.size.y, VAULT_PLATFORM_HEIGHT) and _near(platform.size.z, 6.0) and _near(platform.position.y, 0.0) and _near(platform.get_center().x, 0.0) and _near(platform.get_center().z, 0.0) and _near(area, 36.0), "%s: the platform is %s at %s (%.1f m2), expected 6 x 0.12 x 6 in the middle on the floor" % [label, platform.size, platform.position, area])
		var middle := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0.0, 1.0, 0.0), Vector3(0.0, -1.0, 0.0)))
		var aside := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(4.0, 1.0, 0.0), Vector3(4.0, -1.0, 0.0)))
		_expect(failures, not middle.is_empty() and absf((middle["position"] as Vector3).y - VAULT_PLATFORM_HEIGHT) < 0.01 and not aside.is_empty() and absf((aside["position"] as Vector3).y) < 0.01, "%s: the middle is at %.2f m and the side at %.2f m" % [label, (middle["position"] as Vector3).y if not middle.is_empty() else -1.0, (aside["position"] as Vector3).y if not aside.is_empty() else -1.0])
		var edge := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0.0, 0.06, 5.0), Vector3(0.0, 0.06, 1.0)))
		_expect(failures, not edge.is_empty() and absf((edge["position"] as Vector3).z - 3.0) < 0.01, "%s: the platform's edge across the walking line is not at z = 3" % label)

		var key_spots := room.get_node("KeySpots").get_child_count()
		var prop_spots := room.get_node("PropSpots").get_child_count()
		_expect(failures, key_spots == 3 and prop_spots == 6, "%s: %d key spots and %d prop spots, expected 3 and 6" % [label, key_spots, prop_spots])
		_expect(failures, room.get_node_or_null("Ceiling") != null and room.get_node_or_null("RoomLight") != null and room.get_node_or_null("Fixture") != null, "%s: ceiling, light or fixture missing" % label)
		root.remove_child(room)
		room.free()
	return failures

func test_vault_spacing() -> Array[String]:
	var failures: Array[String] = []
	var weights: Resource = Chain.ROOM_WEIGHTS
	var min_gap: int = weights.min_gap
	_expect(failures, FileAccess.get_file_as_string("res://steps/%s/room_weights.tres" % FINAL_STEP).contains("min_gap = %d" % min_gap), "min_gap %d is not the value in room_weights.tres" % min_gap)
	var vaults_total := 0
	var seeds_with := 0
	var closest := 1000
	for chain_seed in range(1, SEED_COUNT + 1):
		if chain_seed % 50 == 0:
			await process_frame
		var last := -1
		var here := 0
		for plan: Object in _plans_to_goal(Chain, chain_seed, 20).plans:
			if plan.type != Chain.Type.VAULT:
				continue
			here += 1
			_expect(failures, plan.index >= 1 and plan.index < 20, "seed %d: a vault is room %d" % [chain_seed, plan.index])
			if last >= 0:
				closest = mini(closest, plan.index - last)
				_expect(failures, plan.index - last >= min_gap, "seed %d: vaults in rooms %d and %d are %d apart, the gap is %d" % [chain_seed, last, plan.index, plan.index - last, min_gap])
			last = plan.index
		vaults_total += here
		seeds_with += 1 if here > 0 else 0
		if failures.size() > 8:
			return failures
	print("        vaults, seeds 1-%d: %.2f per run, %d seeds have one, the closest two are %d rooms apart (min_gap %d)" % [SEED_COUNT, vaults_total / float(SEED_COUNT), seeds_with, closest, min_gap])
	_expect(failures, closest == min_gap, "the closest vaults are %d apart, but the rule should be met exactly sometimes (min_gap %d)" % [closest, min_gap])
	_expect(failures, seeds_with >= SEED_COUNT * 0.75 and seeds_with <= SEED_COUNT * 0.95, "%d of %d seeds have a vault" % [seeds_with, SEED_COUNT])
	_expect(failures, vaults_total >= SEED_COUNT * 0.9 and vaults_total <= SEED_COUNT * 1.7, "%d vaults in %d runs" % [vaults_total, SEED_COUNT])

	# The boundary of the filter itself: the next room is min_gap after the last vault -> allowed; one room sooner -> never a candidate.
	var chain := Chain.new(5, 100, 0.0)
	for i in 10:
		chain.next_plan()
	chain._last_vault = 10 - min_gap
	var allowed := 0
	for i in 3000:
		allowed += 1 if (chain._weighted_types() as Array[int]).has(Chain.Type.VAULT) else 0
	chain._last_vault = 10 - min_gap + 1
	var too_soon := 0
	for i in 3000:
		too_soon += 1 if (chain._weighted_types() as Array[int]).has(Chain.Type.VAULT) else 0
	_expect(failures, allowed == 3000 and too_soon == 0, "at min_gap %d the vault is a candidate in %d of 3000 orders, one room sooner in %d" % [min_gap, allowed, too_soon])
	return failures

func test_vault_seeds() -> Array[String]:
	var failures: Array[String] = []
	for step in STEPS:
		var chain_script := _chain_script(step)
		var chain := _plans_to_goal(chain_script, 42, 20)
		var vaults: Array[int] = []
		for plan: Object in chain.plans:
			if plan.type == chain_script.Type.VAULT:
				vaults.append(plan.index)
		_expect(failures, vaults == SEED_42_VAULTS[step], "%s: seed 42 has vaults %s, expected %s" % [step, vaults, SEED_42_VAULTS[step]])
	# Some seed shows a vault before its goal room.
	var early := 0
	for chain_seed in range(1, 101):
		var plans: Array = _plans_to_goal(Chain, chain_seed, 20).plans
		early += 1 if plans.any(func(plan: Object) -> bool: return plan.type == Chain.Type.VAULT and plan.index < 20) else 0
	_expect(failures, early >= 75, "only %d of 100 seeds show a vault before the goal room" % early)
	var shown := _plans_to_goal(Chain, FAULT_SEED, 20)
	print("        seed %d, goal room 20: vaults in rooms %s, locks in rooms %s, goal room %d" % [FAULT_SEED, shown.plans.filter(func(plan: Object) -> bool: return plan.type == Chain.Type.VAULT).map(func(plan: Object) -> int: return plan.index), shown.plans.filter(func(plan: Object) -> bool: return plan.locked).map(func(plan: Object) -> int: return plan.index), shown.goal_index])
	# A vault can be locked: its key lies at one of its own key spots.
	var locked_vaults := 0
	for chain_seed in range(1, 301):
		var locked_chain := _plans_to_goal(Chain, chain_seed, 20, 1.0)
		for plan: Object in locked_chain.plans:
			if plan.type == Chain.Type.VAULT:
				if plan.index == locked_chain.goal_index - 1:
					_expect(failures, not plan.locked and plan.key_spot == -1, "seed %d: the vault in room %d, before the goal room, is locked" % [chain_seed, plan.index])
					continue # the room before the goal is never locked, a vault or not
				_expect(failures, plan.locked and plan.key_spot >= 0 and plan.key_spot < shown.key_spot_count(Chain.Type.VAULT) and shown.key_spot_count(Chain.Type.VAULT) == 3, "seed %d: the vault in room %d is not locked at lock chance 1, or its key spot is %d" % [chain_seed, plan.index, plan.key_spot])
				locked_vaults += 1
	_expect(failures, locked_vaults >= 100, "only %d locked vaults in 300 seeds" % locked_vaults)
	return failures

#endregion

#region Tutorial 05: check_contents.gd

func test_contents_check_seeds() -> Array[String]:
	var failures: Array[String] = []
	var layouts := Contents.read_layouts()
	var props := 0
	var vaults := 0
	for chance: float in [LOCK_CHANCE, 1.0]:
		for chain_seed in range(1, SEED_COUNT + 1):
			if chain_seed % 50 == 0:
				await process_frame
			var chain := Solvable.build(chain_seed, 20, chance)
			var problems := Contents.problems_of(chain, Contents.build_without_props(chain_seed, 20, chance), layouts)
			problems.append_array(Solvable.problems_of(chain, Solvable.build(chain_seed, 20, 0.0)))
			for problem in problems:
				failures.append("seed %d, chance %.1f: %s" % [chain_seed, chance, problem])
			for plan in chain.plans:
				vaults += 1 if plan.type == Chain.Type.VAULT else 0
				props += plan.props.filter(func(prop: int) -> bool: return prop != Chain.NO_PROP).size()
			if failures.size() > 8:
				return failures
	print("        seeds 1-%d at lock chance %.1f and 1.0: %d props placed, %d vaults, no rule broken" % [SEED_COUNT, LOCK_CHANCE, props, vaults])
	return failures

## A check that never fails is worth nothing: break the layouts and the plans of a good chain the way a bad level
## designer or a buggy generator could, and see that the check names it.
func test_contents_finds_faults() -> Array[String]:
	var failures: Array[String] = []
	var chain := Solvable.build(FAULT_SEED, 20, LOCK_CHANCE)
	var bare := Contents.build_without_props(FAULT_SEED, 20, LOCK_CHANCE)
	var clean := Contents.read_layouts()
	_expect(failures, Contents.problems_of(chain, bare, clean).is_empty(), "the check complains about a good chain: %s" % [Contents.problems_of(chain, bare, clean).slice(0, 3)])

	# Broken layouts: a prop spot where it must not be, one prop on every spot of that room type.
	var spot_faults: Array[Dictionary] = [
		{name = "a prop in the walking corridor", type = Chain.Type.STRAIGHT, at = Vector3(0.0, 0.0, 0.0), expect = "walking corridor"},
		{name = "a prop on a key spot", type = Chain.Type.STRAIGHT, at = Vector3(-3.5, 0.0, -0.5), expect = "key spot 0"},
		{name = "a prop in the door's swing", type = Chain.Type.STRAIGHT, at = Vector3(0.0, 0.0, -4.0), expect = "trigger or swing"},
		{name = "a prop in the wall", type = Chain.Type.STRAIGHT, at = Vector3(-4.9, 0.0, -4.9), expect = "sticks into a wall"},
		{name = "a prop on the way to a key", type = Chain.Type.LONG, at = Vector3(-1.9, 0.0, 7.0), expect = "blocks the way"},
		{name = "a prop on a pillar of the vault", type = Chain.Type.VAULT, at = Vector3(-4.5, 0.0, 5.0), expect = "pillar or a platform"},
		{name = "a prop on the platform of the vault", type = Chain.Type.VAULT, at = Vector3(2.0, 0.0, 2.0), expect = "pillar or a platform"},
		{name = "a prop in the swing of the door in the entrance", type = Chain.Type.WIDE, at = Vector3(-0.2, 0.0, 3.5), expect = "trigger or swing"},
	]
	for fault in spot_faults:
		var fault_layouts := Contents.read_layouts()
		fault_layouts[fault.type].prop_spots[0] = Transform3D(Basis.IDENTITY, fault.at)
		Contents._footprints.clear()
		var plan := _plan_with(fault.type, fault_layouts[fault.type].prop_spots.size(), {0: 0})
		var problems := Contents._room_problems(chain, plan, fault_layouts[fault.type])
		var named := false
		for problem in problems:
			named = named or problem.contains(fault.expect)
		_expect(failures, named, "the check does not find %s (expected \"%s\", got %s)" % [fault.name, fault.expect, problems.slice(0, 3)])
	var layouts := Contents.read_layouts()
	layouts[Chain.Type.STRAIGHT].prop_spots[1] = layouts[Chain.Type.STRAIGHT].prop_spots[0]
	Contents._footprints.clear()
	var doubled := Contents._room_problems(chain, _plan_with(Chain.Type.STRAIGHT, 5, {0: 0, 1: 1}), layouts[Chain.Type.STRAIGHT])
	var overlap_named := false
	for problem in doubled:
		overlap_named = overlap_named or problem.contains("overlaps the")
	_expect(failures, overlap_named, "the check does not find two props on one spot (got %s)" % [doubled.slice(0, 3)])
	Contents._footprints.clear()

	# Broken plans.
	var plan_faults: Array[Dictionary] = [
		{kind = "bad_index", name = "a prop the room type does not have", expect = "does not have"},
		{kind = "too_many", name = "more props than prop spots", expect = "props for"},
		{kind = "goal_props", name = "props in the goal room", expect = "props for 0 prop spots"},
		{kind = "close_vaults", name = "two vaults closer than min_gap", expect = "rooms apart"},
		{kind = "moved_room", name = "a prop that moves a room", expect = "not the room it is without props"},
		{kind = "moved_lock", name = "a prop that moves a lock", expect = "not the room it is without props"},
	]
	for fault in plan_faults:
		var broken := Solvable.build(FAULT_SEED, 20, LOCK_CHANCE)
		var plain := Contents.build_without_props(FAULT_SEED, 20, LOCK_CHANCE)
		_sabotage_contents(broken, fault.kind)
		var problems := Contents.problems_of(broken, plain, clean)
		var named := false
		for problem in problems:
			named = named or problem.contains(fault.expect)
		_expect(failures, named, "the check does not find %s (expected \"%s\", got %s)" % [fault.name, fault.expect, problems.slice(0, 3)])
	return failures

## The public way to the twin the check compares with: no prop spot in any room type, everything else as it was.
func test_clear_prop_spots() -> Array[String]:
	var failures: Array[String] = []
	var props_seen := 0
	for chain_seed in range(1, 41):
		var chain := Solvable.build(chain_seed, 20, LOCK_CHANCE)
		var bare := Contents.build_without_props(chain_seed, 20, LOCK_CHANCE)
		_expect(failures, chain.plans.size() == bare.plans.size(), "seed %d: %d rooms with props, %d without" % [chain_seed, chain.plans.size(), bare.plans.size()])
		for i in mini(chain.plans.size(), bare.plans.size()):
			var plan := chain.plans[i]
			var other := bare.plans[i]
			_expect(failures, plan.type == other.type and plan.transform == other.transform and plan.bounds == other.bounds and plan.locked == other.locked and plan.key_spot == other.key_spot, "seed %d: room %d is not the room it is without props" % [chain_seed, i])
			_expect(failures, other.props.is_empty(), "seed %d: room %d of the twin holds %d prop entries" % [chain_seed, i, other.props.size()])
			props_seen += plan.props.size()
	_expect(failures, props_seen > 0, "the chains of seeds 1-40 hold no props at all: the twin proves nothing")
	var fresh := Chain.new(1, 20, LOCK_CHANCE) # clearing the spots of one chain leaves the next chain alone
	var plan_zero := fresh.next_plan()
	_expect(failures, plan_zero.props.size() == 5, "a new chain lost its prop spots: room 0 has %d entries, expected 5" % plan_zero.props.size())
	return failures

func _sabotage_contents(chain: Chain, kind: String) -> void:
	match kind:
		"bad_index":
			chain.plans[0].props[0] = 99
		"too_many":
			chain.plans[1].props.append(0)
		"goal_props":
			chain.plans[-1].props.append(0)
		"close_vaults":
			var vault_at := -1
			for plan in chain.plans:
				if plan.type == Chain.Type.VAULT:
					vault_at = plan.index
			chain.plans[vault_at + 3].type = Chain.Type.VAULT # no props change: only the spacing is wrong
			chain.plans[vault_at + 3].props.clear()
			for i in 6:
				chain.plans[vault_at + 3].props.append(Chain.NO_PROP)
		"moved_room":
			chain.plans[7].transform = chain.plans[7].transform.translated(Vector3(0.0, 0.0, 1.0))
		"moved_lock":
			chain.plans[3].locked = false

func test_contents_command() -> Array[String]:
	var failures: Array[String] = []
	var executable := OS.get_executable_path()
	if executable.is_empty():
		_skip("check_contents.gd from the command line", "no executable path")
		return failures
	var output: Array = []
	var code := OS.execute(executable, ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://steps/%s/check_contents.gd" % FINAL_STEP, "--", "--seeds=40"], output, true)
	var text := ""
	for chunk: String in output:
		text += str(chunk)
	_expect(failures, code == 0 and text.contains("CONTENTS OK") and text.contains("seeds 1-40, lock chance 0.4") and text.contains("seeds 1-40, lock chance 1.0"), "exit code %d, output: %s" % [code, text.substr(0, 300)])
	return failures

#endregion

#region Tutorial 06: seeds you can share

## The seeds.gd of a step (steps 1 to 5 have one).
func _seeds_script(step: String) -> GDScript:
	return load("res://steps/%s/seeds.gd" % step) as GDScript

## The names of an action's keyboard keys ("T"), by physical key.
func _physical_keys(action: StringName) -> Array[String]:
	var keys: Array[String] = []
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			keys.append(OS.get_keycode_string((event as InputEventKey).physical_keycode))
	return keys

## Presses and releases a key like a person does: through the input system, so the control that has the focus gets it.
func _key(code: Key, unicode := 0) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.unicode = unicode
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame
		await process_frame

## A press and a release of a key within this frame, for callbacks that cannot await (the physics driver).
func _press_now(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()

func _type_text(text: String) -> void:
	for character in text:
		await _key(character.to_upper().unicode_at(0) as Key, character.unicode_at(0))

func test_seed_text() -> Array[String]:
	var failures: Array[String] = []
	for step in STEPS:
		var seeds := _seeds_script(step)
		_expect(failures, seeds.normalize("  blue-fox ") == "BLUE-FOX" and seeds.normalize("") == "" and seeds.normalize("\t42\n") == "42" and seeds.normalize("äpfel") == "ÄPFEL", "%s: normalize cuts the spaces and makes capitals" % step)
		for pair: Array in [["42", 42], [" 42 ", 42], ["007", 7], ["0", 0], ["1", 1], ["123456789", 123456789]]:
			_expect(failures, seeds.parse(pair[0]) == pair[1], "%s: parse(\"%s\") is %d, expected %d" % [step, pair[0], seeds.parse(pair[0]), pair[1]])
		# Anything that is not 1 to 9 plain digits is a text and gets hashed (is_valid_int would let +5 and -5 through).
		for text: String in ["1234567890", "+5", "-5", "4 2", "1e5", "4.2", "BLUE-FOX", "", "42a", "a42", "ÄPFEL"]:
			_expect(failures, seeds.parse(text) == seeds.text_hash(seeds.normalize(text)), "%s: parse(\"%s\") is not the hash of the text" % [step, text])
		_expect(failures, seeds.parse("blue-fox") == seeds.parse("BLUE-FOX") and seeds.parse(" Blue-Fox ") == seeds.parse("BLUE-FOX") and seeds.parse("äpfel") == seeds.parse("ÄPFEL"), "%s: case and spaces at the ends change the seed" % step)
		_expect(failures, seeds.parse("BLUE FOX") != seeds.parse("BLUE-FOX") and seeds.parse("BLUE-FOX") != seeds.parse("BLUE-FOX-2") and seeds.parse("42") != seeds.parse("43") and seeds.parse("42 ") == 42, "%s: other texts must be other seeds (and \"42 \" is 42)" % step)
		var seen := {}
		for i in 2000:
			var number: int = seeds.parse("SEED-%d" % i)
			seen[number] = true
			_expect(failures, number >= 0 and number <= 0xFFFFFFFF, "%s: SEED-%d is %d, not a 32-bit number" % [step, i, number])
		_expect(failures, seen.size() == 2000, "%s: 2000 seed texts gave %d numbers" % [step, seen.size()])
		_expect(failures, seeds.MAX_LENGTH == 24, "%s: MAX_LENGTH is %d" % [step, seeds.MAX_LENGTH])
	return failures

func test_seed_hash_and_next() -> Array[String]:
	var failures: Array[String] = []
	# FNV-1a, 32 bit: the vectors of its authors ("", "a", "foobar") and the seeds of this tutorial, all computed outside Godot.
	var vectors := {"": 0x811C9DC5, "a": 0xE40C292C, "foobar": 0xBF9CF968, "BLUE-FOX": 3245612269, "ÄPFEL": 3772709849, "locks": 2201236771, "props": 2276826577, "layout": 3401678079, "lamp": 1810951995}
	for step in STEPS:
		var seeds := _seeds_script(step)
		for text: String in vectors:
			_expect(failures, seeds.text_hash(text) == vectors[text], "%s: text_hash(\"%s\") is %d, FNV-1a says %d" % [step, text, seeds.text_hash(text), vectors[text]])
		var cases := {"42": "43", "9": "10", "0": "1", "BLUE-FOX": "BLUE-FOX-2", "BLUE-FOX-2": "BLUE-FOX-3", "blue-fox-9": "BLUE-FOX-10", " 7 ": "8", "007": "8", "": "-2", "FOX": "FOX-2", "A1B": "A1B-2", "999999999": "1000000000"}
		for text: String in cases:
			_expect(failures, seeds.next_text(text) == cases[text], "%s: next_text(\"%s\") is \"%s\", expected \"%s\"" % [step, text, seeds.next_text(text), cases[text]])
		_expect(failures, seeds.parse(seeds.next_text("42")) == 43 and seeds.parse(seeds.next_text("41")) == 42, "%s: N does not count 42, 43, 44 like before" % step)
		var text := "BLUE-FOX"
		var seen := {}
		for i in 60:
			seen[seeds.parse(text)] = true
			text = seeds.next_text(text)
		_expect(failures, seen.size() == 60, "%s: sixty times N gave %d different seeds" % [step, seen.size()])
	return failures

func test_seed_entry(step: String) -> Array[String]:
	var failures: Array[String] = []
	_expect(failures, _physical_keys("edit_seed") == ["T"] and _physical_keys("copy_seed") == ["C"], "edit_seed is %s and copy_seed %s, expected T and C" % [_physical_keys("edit_seed"), _physical_keys("copy_seed")])
	var main := await _load_step(step, true, {"goal_room": SHORT_GOAL})
	var level: Node3D = main.get_node("Level")
	var entry: Control = main.get_node("HUD/SeedEntry")
	var line: LineEdit = main.get_node("HUD/SeedEntry/Rows/Line")
	var label: Label = main.get_node("HUD/Stats/SeedLabel")
	var seeds := _seeds_script(step)
	_expect(failures, level.seed_text == "42" and level.chain_seed == 42 and label.text == "Seed 42" and not entry.visible and not level.typing, "the level starts with seed \"%s\" (%d), the HUD reads \"%s\"" % [level.seed_text, level.chain_seed, label.text])
	_expect(failures, label.get_theme_font_size("font_size") >= 32 and label.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT, "the seed label is not like the other labels")

	# T: the box is up with the current seed selected, the player stands.
	await _key(KEY_T, 116)
	_expect(failures, entry.visible and line.has_focus() and level.typing and level.player.get("frozen") == true, "T did not open the box (visible %s, focus %s, typing %s)" % [entry.visible, line.has_focus(), level.typing])
	_expect(failures, line.text == "42" and line.get_selected_text() == "42" and line.max_length == seeds.MAX_LENGTH, "the box shows \"%s\" with \"%s\" selected" % [line.text, line.get_selected_text()])
	await _type_text("blue-fox")
	_expect(failures, line.text == "blue-fox", "typing gave \"%s\"" % line.text)
	_expect(failures, level.seed_text == "42", "the seed changed while it was being typed")

	# Enter: a fresh run with the typed seed, in its canonical form, shown in the HUD.
	await _key(KEY_ENTER)
	await _wait_physics(5)
	var blue: int = seeds.parse("BLUE-FOX")
	_expect(failures, not entry.visible and not level.typing and level.player.get("frozen") == false, "Enter did not close the box and free the player")
	_expect(failures, level.seed_text == "BLUE-FOX" and level.chain_seed == blue and label.text == "Seed BLUE-FOX", "after Enter: seed \"%s\" (%d), the HUD reads \"%s\"" % [level.seed_text, level.chain_seed, label.text])
	failures.append_array(_fresh_run_problems(step, main, blue))
	_expect(failures, (main.get_node("HUD/Stats/BestLabel") as Label).text == "Best -:--.-", "the best time of the old seed is shown for the new one")

	# Esc: nothing changes, the box goes, the run goes on.
	var chain: RefCounted = level.chain
	await _key(KEY_T, 116)
	_expect(failures, line.text == "BLUE-FOX", "the box shows \"%s\", not the current seed" % line.text)
	await _type_text("xyz")
	await _key(KEY_ESCAPE)
	await _wait_physics(5)
	_expect(failures, not entry.visible and not level.typing and level.player.get("frozen") == false, "Esc did not close the box and free the player")
	_expect(failures, level.seed_text == "BLUE-FOX" and level.chain == chain and label.text == "Seed BLUE-FOX", "Esc changed the seed or restarted the run")

	# Enter on the seed as it is: the same seed, a fresh run (like R).
	await _key(KEY_T, 116)
	await _key(KEY_ENTER)
	await _wait_physics(5)
	_expect(failures, level.seed_text == "BLUE-FOX" and level.chain != chain, "Enter on the same seed did not start a fresh run")
	failures.append_array(_fresh_run_problems(step, main, blue))

	# In a run: a typed seed throws the run away, like N does.
	Input.action_press("move_forward")
	await _wait_physics(100)
	Input.action_release("move_forward")
	_expect(failures, level.state == STATE_RUNNING and level.run_time > 0.5, "the run did not get going (state %d)" % level.state)
	await _key(KEY_T, 116)
	await _type_text("run 2")
	await _key(KEY_ENTER)
	await _wait_physics(5)
	_expect(failures, level.seed_text == "RUN 2" and label.text == "Seed RUN 2" and level.chain_seed == seeds.parse("RUN 2"), "a typed seed with a space: \"%s\", label \"%s\"" % [level.seed_text, label.text])
	failures.append_array(_fresh_run_problems(step, main, seeds.parse("RUN 2")))

	# N after a typed seed counts on at its end; R keeps the seed.
	await _action("next_seed")
	await _wait_physics(5)
	_expect(failures, level.seed_text == "RUN 3" and label.text == "Seed RUN 3", "N after RUN 2 gave \"%s\"" % level.seed_text)
	await _action("regenerate")
	await _wait_physics(5)
	_expect(failures, level.seed_text == "RUN 3" and label.text == "Seed RUN 3", "R changed the seed to \"%s\"" % level.seed_text)
	_expect(failures, _same_plans(level.chain.plans, _level_plans(step, level.chain_seed, 1, level)), "room 0 is not the pure-data chain's")
	await _unload(main)
	return failures

func test_typing_is_safe(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step, true, {"goal_room": SHORT_GOAL})
	var level: Node3D = main.get_node("Level")
	var entry: Control = main.get_node("HUD/SeedEntry")
	var line: LineEdit = main.get_node("HUD/SeedEntry/Rows/Line")
	Input.action_press("move_forward")
	await _wait_physics(100)
	Input.action_release("move_forward")
	_expect(failures, level.state == STATE_RUNNING, "the run did not get going")
	var chain: RefCounted = level.chain
	var run_time: float = level.run_time
	var at: Vector3 = level.player.global_position

	await _key(KEY_T, 116)
	var quality := main.get_node_or_null("Quality")
	await _type_text("wasdrnq tc") # the keys that walk, restart, step on to the next seed, switch the quality, open and copy
	# W held down for half a second, as a person walking would while the box is up
	var hold := InputEventKey.new()
	hold.keycode = KEY_W
	hold.physical_keycode = KEY_W
	hold.pressed = true
	Input.parse_input_event(hold)
	await _wait_physics(30)
	_expect(failures, level.player.global_position.distance_to(at) < 0.01, "the player walked %.2f m while the seed box was up" % level.player.global_position.distance_to(at))
	hold = hold.duplicate() as InputEventKey
	hold.pressed = false
	Input.parse_input_event(hold)
	await _wait_physics(2)
	_expect(failures, line.text == "wasdrnq tc" or line.text == "wasdrnq tcw", "the box holds \"%s\"" % line.text)
	_expect(failures, quality == null or quality.get("current") == 2, "a Q typed into the box switched the quality")
	_expect(failures, entry.visible and level.typing and level.chain == chain and level.seed_text == "42", "a typed key restarted the run, changed the seed or closed the box")
	_expect(failures, not (main.get_node("HUD/NoticeLabel") as Label).visible, "a C typed into the box copied the seed")
	var waited: float = level.run_time
	await _wait_physics(60)
	_expect(failures, level.run_time == waited and absf(waited - run_time) < 0.1, "the clock ran while the box was up (%.3f s then %.3f s after a second)" % [waited, level.run_time])
	await _key(KEY_ESCAPE)
	_expect(failures, not entry.visible and not level.typing and level.player.get("frozen") == false, "Esc left the player frozen")
	await _wait_physics(30)
	_expect(failures, level.run_time > waited + 0.4, "the clock does not run again after the box (%.3f s)" % level.run_time)

	# The tab key must not toggle the map behind the box.
	var map: Control = main.get_node("HUD/DebugMap")
	var map_was := map.visible
	await _key(KEY_T, 116)
	await _key(KEY_TAB)
	_expect(failures, map.visible == map_was and entry.visible, "Tab toggled the map or closed the box")
	await _key(KEY_ESCAPE)

	# After the finish the player stays frozen when the box goes.
	level._set_state(STATE_FINISHED)
	await _key(KEY_T, 116)
	await _key(KEY_ESCAPE)
	_expect(failures, level.player.get("frozen") == true and level.state == STATE_FINISHED, "closing the box gave the player back after the finish")
	await _unload(main)
	return failures

func test_copy_and_limits(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step, true, {"goal_room": SHORT_GOAL})
	var level: Node3D = main.get_node("Level")
	var entry: Control = main.get_node("HUD/SeedEntry")
	var line: LineEdit = main.get_node("HUD/SeedEntry/Rows/Line")
	var notice: Label = main.get_node("HUD/NoticeLabel")
	var timer: Timer = main.get_node("HUD/NoticeTimer")
	_expect(failures, not notice.visible and timer.wait_time == 1.5 and timer.one_shot, "the notice is up at the start, or its timer is not 1.5 s")
	await _action("copy_seed")
	_expect(failures, notice.visible and notice.text == "Seed copied: 42", "C: the notice reads \"%s\" (visible %s)" % [notice.text, notice.visible])
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		_expect(failures, DisplayServer.clipboard_get() == "42", "the clipboard holds \"%s\", not the seed" % DisplayServer.clipboard_get())
	await _wait_physics(120)
	_expect(failures, not notice.visible, "the notice is still up after two seconds")
	level.use_seed("blue-fox")
	await _action("copy_seed")
	_expect(failures, notice.text == "Seed copied: BLUE-FOX", "C after a typed seed: \"%s\"" % notice.text)
	await _wait_physics(120)

	# The box takes 24 characters, and no empty seed.
	await _key(KEY_T, 116)
	await _type_text("x".repeat(30))
	_expect(failures, line.text.length() == 24, "the box took %d characters, expected 24" % line.text.length())
	var chain: RefCounted = level.chain
	for empty: String in ["", "   "]:
		line.text = empty
		await _key(KEY_ENTER)
		_expect(failures, entry.visible and level.typing and level.chain == chain, "Enter on the empty seed \"%s\" closed the box or restarted the run" % empty)
	await _key(KEY_ESCAPE)
	await _unload(main)
	return failures

## The same seed text is the same run, however it got there: the property, the box, N, R.
func test_seed_text_in_levels() -> Array[String]:
	var failures: Array[String] = []
	for step: String in [STEPS[0], FINAL_STEP]:
		var seeds := _seeds_script(step)
		var main := await _load_step(step, true, {"seed_text": " Blue-Fox ", "goal_room": 8})
		var level: Node3D = main.get_node("Level")
		var blue: int = seeds.parse("BLUE-FOX")
		_expect(failures, level.seed_text == "BLUE-FOX" and level.chain_seed == blue, "%s: the seed property \" Blue-Fox \" became \"%s\" (%d)" % [step, level.seed_text, level.chain_seed])
		var expected := _level_plans(step, blue, 6, level)
		for i in 5:
			level._spawn_room(level.chain.next_plan())
		_expect(failures, _same_plans(level.chain.plans.slice(0, 6), expected), "%s: the level's plans are not the pure-data chain's" % step)
		level.use_seed("blue-fox")
		for i in 5:
			level._spawn_room(level.chain.next_plan())
		_expect(failures, _same_plans(level.chain.plans.slice(0, 6), expected), "%s: use_seed(\"blue-fox\") is another run" % step)
		await _action("next_seed")
		_expect(failures, level.seed_text == "BLUE-FOX-2" and not _same_plans(_level_plans(step, level.chain_seed, 6, level), expected), "%s: N gave \"%s\"" % [step, level.seed_text])
		await _action("regenerate")
		_expect(failures, level.seed_text == "BLUE-FOX-2", "%s: R changed the seed to \"%s\"" % [step, level.seed_text])
		await _unload(main)
	return failures

## A restart with the player standing at the first door. Under Jolt a teleported player is still at the old place for
## the physics step right after the teleport: a trigger that is awake in that step sees the player where the player was and opens
## the door of the new room 0 at once (rooms 0 and 1 exist, the clock runs). A typed seed makes this easy to do.
## The restarts are delivered the way a key press is: at the start of a frame.
func test_restart_at_the_door(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step, true, {"goal_room": SHORT_GOAL})
	var level: Node3D = main.get_node("Level")
	for how: String in ["R", "N", "typed seed"]:
		Input.action_press("move_forward")
		await _wait_physics(100)
		Input.action_release("move_forward")
		_expect(failures, level.player.global_position.z < -4.5, "%s: the player is not at the first door (z = %.2f)" % [how, level.player.global_position.z])
		match how:
			"R", "N":
				var press := InputEventAction.new()
				press.action = &"regenerate" if how == "R" else &"next_seed"
				press.pressed = true
				Input.parse_input_event(press)
				await physics_frame
			"typed seed":
				await _key(KEY_T, 116)
				await _type_text("at the door")
				await _key(KEY_ENTER)
		var woke := false
		for i in 6:
			await physics_frame
			woke = woke or level.rooms[0].door.is_open or level.state != STATE_READY or level.rooms.size() > 1
		_expect(failures, not woke, "%s: the new room 0 opened its door at once (state %d, %d rooms)" % [how, level.state, level.rooms.size()])
		await _wait_physics(5)
	await _unload(main)
	return failures

func test_room_streams() -> Array[String]:
	var failures: Array[String] = []
	var streams: Array[String] = ["layout", "locks", "props", "lamp"]
	for step in STEPS:
		var seeds := _seeds_script(step)
		var seen := {}
		var total := 0
		for chain_seed: int in [1, 42, 43, 3245612269, 0xFFFFFFFF]:
			for stream in streams:
				for room in 30:
					var child: int = seeds.child(chain_seed, stream, room)
					total += 1
					seen[child] = true
					_expect(failures, child >= 0 and child <= 0xFFFFFFFF and child == seeds.child(chain_seed, stream, room), "%s: child(%d, %s, %d) is %d: out of range or not stable" % [step, chain_seed, stream, room, child])
					_expect(failures, child != seeds.child(chain_seed, "other", room) and child != seeds.child(chain_seed, stream, room + 1) and child != seeds.child(chain_seed ^ 1, stream, room), "%s: child(%d, %s, %d) does not depend on the stream, the room and the seed" % [step, chain_seed, stream, room])
		_expect(failures, seen.size() == total, "%s: %d child seeds, only %d different" % [step, total, seen.size()])
		# The same seed is the same dice, a started-again generator forgets what it drew.
		var first := RandomNumberGenerator.new()
		var second := RandomNumberGenerator.new()
		first.seed = seeds.child(42, "locks", 5)
		second.seed = seeds.child(42, "locks", 5)
		var rolls: Array[float] = []
		for i in 8:
			rolls.append(first.randf())
		first.seed = seeds.child(42, "locks", 5)
		for i in 8:
			_expect(failures, second.randf() == rolls[i] and first.randf() == rolls[i], "%s: the dice of a stream are not the same after starting it again" % step)
	return failures

## The chain of a step with the experiment of the video written into its source: a feature that rolls `count` more dice
## in room `room`, drawn from the lock generator right before the lock roll.
var _patched_chains := {}
func _chain_with_extra_dice(step: String, room: int, count: int) -> GDScript:
	var key := "%s/%d/%d" % [step, room, count]
	if _patched_chains.has(key):
		return _patched_chains[key]
	var source := FileAccess.get_file_as_string("res://steps/%s/room_chain.gd" % step)
	if source.count(EXPERIMENT_ANCHOR) != 1:
		return null
	var script := GDScript.new()
	script.source_code = source.replace(EXPERIMENT_ANCHOR, EXPERIMENT_LINES % [room, count] + EXPERIMENT_ANCHOR)
	script.resource_path = "res://steps/%s/room_chain_extra_dice_%d_%d.gd" % [step, room, count] # the chain's preloads are relative to this path
	if script.reload() != OK:
		return null
	_patched_chains[key] = script
	return script

func test_extra_dice_independent() -> Array[String]:
	var failures: Array[String] = []
	for step: String in [STEPS[0], FINAL_STEP]:
		var base_script := _chain_script(step)
		for room in EXPERIMENT_ROOMS:
			var patched_script := _chain_with_extra_dice(step, room, 3)
			_expect(failures, patched_script != null, "%s: the experiment does not compile or its anchor is gone" % step)
			if patched_script == null:
				continue
			var own_roll_moved := 0
			var compared := 0
			for chain_seed in range(1, EXPERIMENT_SEEDS + 1):
				if chain_seed % 25 == 0:
					await process_frame
				var base: Array = _plans_to_goal(base_script, chain_seed, 20).plans
				var patched: Array = _plans_to_goal(patched_script, chain_seed, 20).plans
				_expect(failures, base.size() == patched.size(), "%s seed %d: the experiment changed the number of rooms" % [step, chain_seed])
				for j in mini(base.size(), patched.size()):
					compared += 1
					if j == room:
						_expect(failures, base[j].type == patched[j].type and base[j].transform == patched[j].transform and base[j].props == patched[j].props and base[j].get("lamp") == patched[j].get("lamp"), "%s seed %d: the extra dice moved more than the lock roll of room %d" % [step, chain_seed, j])
						own_roll_moved += 1 if base[j].locked != patched[j].locked or base[j].key_spot != patched[j].key_spot else 0
					else:
						_expect(failures, _same_plan(base[j], patched[j], true), "%s seed %d: three more dice in room %d moved room %d" % [step, chain_seed, room, j])
				if failures.size() > 8:
					return failures
			print("        %s, three more dice in room %d: %d rooms of %d seeds compared, nothing moved; the lock roll of room %d itself changed in %d seeds" % [step, room, compared, EXPERIMENT_SEEDS, room, own_roll_moved])
			_expect(failures, own_roll_moved >= EXPERIMENT_SEEDS * 0.3, "%s room %d: the extra dice changed the room's own roll in only %d seeds: the experiment does not bite" % [step, room, own_roll_moved])
	return failures

func test_echo_after() -> Array[String]:
	var failures: Array[String] = []
	for step: String in [STEPS[0], FINAL_STEP]:
		var result: Dictionary = await Echo.measure(_chain_script(step), ECHO_SEEDS, 0, self)
		print("        %s (seeds mixed): locks agree in %.1f%% of the rooms (chance %.1f%%), %d of %d neighbour pairs echo in all %d rooms, %d of %d same-type rooms have the same props" % [step, result.agree * 100.0, result.chance * 100.0, result.echo_pairs, ECHO_SEEDS, Echo.WINDOW, result.same_props, result.same_type])
		_expect(failures, result.echo_share <= Echo.PAIR_LIMIT, "%s: %.1f%% of the neighbour seeds are one run shifted by a room" % [step, result.echo_share * 100.0])
		_expect(failures, absf(result.agree - result.chance) <= Echo.ROOM_MARGIN, "%s: the lock states agree in %.1f%% of the rooms, chance is %.1f%%" % [step, result.agree * 100.0, result.chance * 100.0])
		_expect(failures, result.props_share <= Echo.PROP_LIMIT and result.same_type >= 100, "%s: %d of %d same-type rooms have the props of their neighbour" % [step, result.same_props, result.same_type])
		_expect(failures, Echo.problems_of(result).is_empty(), "%s: the check finds an echo: %s" % [step, Echo.problems_of(result)])
	return failures

func test_echo_command() -> Array[String]:
	var failures: Array[String] = []
	var executable := OS.get_executable_path()
	if executable.is_empty():
		_skip("check_echo.gd from the command line", "no executable path")
		return failures
	var output: Array = []
	var code := OS.execute(executable, ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://steps/%s/check_echo.gd" % FINAL_STEP, "--", "--seeds=40"], output, true)
	var text := ""
	for chunk: String in output:
		text += str(chunk)
	_expect(failures, code == 0 and text.contains("ECHO NONE") and text.contains("neighbour seeds 1-41"), "exit code %d, output: %s" % [code, text.substr(0, 400)])
	return failures

## The docs of RandomNumberGenerator say it "does not have an avalanche effect, and can output similar random streams given similar
## seeds". On this engine the first numbers of seed s and seed s + 1 are not related: the echo that summed seeds make is not
## similarity but identity (the very same seed), which is why a mixed seed is the fix and a better generator is not.
func test_engine_neighbour_seeds() -> Array[String]:
	var failures: Array[String] = []
	var rng := RandomNumberGenerator.new()
	var first: Array[float] = []
	var second: Array[float] = []
	for chain_seed in range(1, 2001):
		rng.seed = chain_seed
		first.append(rng.randf())
		rng.seed = chain_seed + 1
		second.append(rng.randf())
	var mean_first := 0.0
	var mean_second := 0.0
	for i in first.size():
		mean_first += first[i] / first.size()
		mean_second += second[i] / second.size()
	var covariance := 0.0
	var variance_first := 0.0
	var variance_second := 0.0
	for i in first.size():
		covariance += (first[i] - mean_first) * (second[i] - mean_second)
		variance_first += (first[i] - mean_first) * (first[i] - mean_first)
		variance_second += (second[i] - mean_second) * (second[i] - mean_second)
	var correlation := covariance / sqrt(variance_first * variance_second)
	print("        first randf() of seed s against seed s + 1, s = 1-2000: correlation %.4f (Godot %s)" % [correlation, Engine.get_version_info().string])
	_expect(failures, absf(correlation) < 0.05, "the first numbers of neighbour seeds are related (correlation %.3f)" % correlation)
	rng.seed = 7
	var again := RandomNumberGenerator.new()
	again.seed = 7
	_expect(failures, rng.randf() == again.randf() and rng.randi() == again.randi(), "the same seed gives other numbers")
	return failures

func test_seed_mixing() -> Array[String]:
	var failures: Array[String] = []
	for step: String in [STEPS[0], FINAL_STEP]:
		var seeds := _seeds_script(step)
		# Reference values computed outside Godot (a Python version of the same 32-bit arithmetic).
		_expect(failures, seeds.mix(1, 2) == 1198951227 and seeds.mix(42, 0) == 4041602470 and seeds.mix(0xFFFFFFFF, 0xFFFFFFFF) == 2397536069 and seeds.mix(0, 0) == 436901570, "%s: mix() gives other numbers than the reference: %d %d %d %d" % [step, seeds.mix(1, 2), seeds.mix(42, 0), seeds.mix(0xFFFFFFFF, 0xFFFFFFFF), seeds.mix(0, 0)])
		_expect(failures, seeds.child(42, "locks", 5) == 1154108819 and seeds.child(42, "props", 5) == 4136909762 and seeds.child(43, "locks", 4) == 1333577071 and seeds.child(0, "layout", 0) == 1567478815 and seeds.child(3245612269, "lamp", 7) == 3441769472, "%s: child() gives other numbers than the reference" % step)
		# A bit avalanche: one changed bit of the input changes about half of the 32 bits of the result.
		var rng := RandomNumberGenerator.new()
		rng.seed = 99
		var total := 0
		var count := 0
		for bit in 32:
			for i in 60:
				var parent := rng.randi()
				var room := rng.randi() % 64
				total += _popcount(seeds.child(parent, "locks", room) ^ seeds.child(parent ^ (1 << bit), "locks", room))
				count += 1
		var mean := total / float(count)
		_expect(failures, mean >= 15.0 and mean <= 17.0, "%s: a changed bit of the seed changes %.2f of 32 bits of the child seed, expected about 16" % [step, mean])
		var neighbours := 0.0
		var rooms := 0.0
		var streams := 0.0
		for chain_seed in range(1, 501):
			neighbours += _popcount(seeds.child(chain_seed, "locks", 5) ^ seeds.child(chain_seed + 1, "locks", 5))
			rooms += _popcount(seeds.child(chain_seed, "locks", 5) ^ seeds.child(chain_seed, "locks", 6))
			streams += _popcount(seeds.child(chain_seed, "locks", 5) ^ seeds.child(chain_seed, "props", 5))
		print("        %s: changed bits of 32 in the child seed: single seed bit %.2f, neighbour seeds %.2f, neighbour rooms %.2f, another stream %.2f" % [step, mean, neighbours / 500.0, rooms / 500.0, streams / 500.0])
		_expect(failures, neighbours / 500.0 >= 15.0 and rooms / 500.0 >= 15.0 and streams / 500.0 >= 15.0, "%s: neighbour seeds %.2f, neighbour rooms %.2f, other streams %.2f changed bits: too few" % [step, neighbours / 500.0, rooms / 500.0, streams / 500.0])
	return failures

func _popcount(value: int) -> int:
	var bits := 0
	while value != 0:
		bits += value & 1
		value >>= 1
	return bits

func test_lamp_tints() -> Array[String]:
	var failures: Array[String] = []
	var tints: Array[Color] = Chain.LAMP_TINTS
	var room := (load("res://steps/%s/room_straight.tscn" % FINAL_STEP) as PackedScene).instantiate()
	var scene_color: Color = (room.get_node("RoomLight") as OmniLight3D).light_color
	room.free()
	_expect(failures, tints.size() == 5 and tints[0] == scene_color, "the first tint is not the warm white the rooms always had (%s, scene %s)" % [tints[0], scene_color])
	var distinct := {}
	for tint in tints:
		distinct[tint] = true
		_expect(failures, minf(tint.r, minf(tint.g, tint.b)) >= 0.6 and maxf(tint.r, maxf(tint.g, tint.b)) <= 1.0, "tint %s is not a light white" % tint)
	_expect(failures, distinct.size() == tints.size(), "two tints are the same colour")
	var counts := [0, 0, 0, 0, 0]
	var total := 0
	for chain_seed in range(1, SEED_COUNT + 1):
		if chain_seed % 50 == 0:
			await process_frame
		var plans: Array = _plans_to_goal(Chain, chain_seed, 20).plans
		if chain_seed <= CONTENT_SEEDS:
			_expect(failures, _same_plans(plans, _plans_to_goal(Chain, chain_seed, 20).plans), "seed %d: the lamps are not the same twice" % chain_seed)
		for plan: Object in plans:
			_expect(failures, plan.lamp >= 0 and plan.lamp < tints.size(), "seed %d room %d: lamp %d" % [chain_seed, plan.index, plan.lamp])
			if plan.type == Chain.Type.GOAL:
				_expect(failures, plan.lamp == 0, "seed %d: the goal room has lamp %d, it keeps its light" % [chain_seed, plan.lamp])
			else:
				counts[plan.lamp] += 1
				total += 1
		if failures.size() > 8:
			return failures
	var shares: Array[float] = []
	for count: int in counts:
		shares.append(snappedf(count / float(total), 0.001))
		_expect(failures, absf(count / float(total) - 0.2) < 0.02, "a tint is %.3f of the rooms, expected a fifth" % [count / float(total)])
	print("        lamp tints, seeds 1-%d, %d rooms: shares %s" % [SEED_COUNT, total, shares])
	_expect(failures, not _same_plans(_plans(Chain, 42, 30), _plans(Chain, 43, 30)) and _plans(Chain, 42, 30).map(func(plan: Object) -> int: return plan.lamp) != _plans(Chain, 43, 30).map(func(plan: Object) -> int: return plan.lamp), "seed 43 has the lamps of seed 42")
	return failures

func test_lamps_in_level() -> Array[String]:
	var failures: Array[String] = []
	var warm := Color(1.0, 0.94, 0.82)
	for step in STEPS:
		var main := await _load_step(step, true, {"goal_room": 7})
		var level: Node3D = main.get_node("Level")
		for i in 7:
			level._spawn_room(level.chain.next_plan())
		await _wait_physics(2)
		var seen := {}
		for plan: Object in level.chain.plans:
			var room: Node3D = _rooms_of(level).filter(func(candidate: Node3D) -> bool: return candidate.global_transform == plan.transform)[0]
			var light := room.get_node("RoomLight") as OmniLight3D
			if plan.type != Chain.Type.GOAL:
				_expect(failures, light.light_color == Chain.LAMP_TINTS[plan.lamp], "%s room %d: the light is %s, the plan says tint %d (%s)" % [step, plan.index, light.light_color, plan.lamp, Chain.LAMP_TINTS[plan.lamp]])
				seen[plan.lamp] = true
			else:
				_expect(failures, light.light_color == warm, "%s room %d: the light is %s, expected the warm white" % [step, plan.index, light.light_color])
		_expect(failures, seen.size() >= 3, "only %d different tints in the first six rooms of seed 42" % seen.size())
		await _unload(main)
	return failures

#endregion

#region Tutorial 09: room lights, the interior environment, volumetric fog, runtime GI, the quality switch

const LIGHT_STEP := "step_01_room_lights" ## The first step that lights the rooms from data.
const ENVIRONMENT_STEP := "step_02_world_environment"
const FOG_STEP := "step_03_volumetric_fog"
const GI_STEP := "step_04_runtime_gi"
const SCENE_LAMP_ENERGY := 1.3 ## What every room scene's RoomLight has (tutorial 08), and so the lamps of step 0.
const GLOW_THRESHOLD := 1.0 ## The HDR threshold of the glow: only what is brighter than white glows.
const SHADOW_ATLAS := 4096 ## The project's positional shadow atlas (the default).
const QUALITY_NAMES: Array[String] = ["Low", "Medium", "High"]

func _from(step: String, first: String) -> bool:
	return STEPS.find(step) >= STEPS.find(first)

func _lighting(step: String) -> Resource:
	return load("res://steps/%s/room_lighting.tres" % step)

## The floor of each room type, in the order of the chain's Type, from the Inside box of its scene.
func _floor_sizes() -> Array[Vector3]:
	var sizes: Array[Vector3] = []
	for scene in Chain.SCENES:
		var room := scene.instantiate()
		sizes.append(((room.get_node("Inside/CollisionShape3D") as CollisionShape3D).shape as BoxShape3D).size)
		room.free()
	return sizes

func test_room_lighting_data() -> Array[String]:
	var failures: Array[String] = []
	_expect(failures, not FileAccess.file_exists("res://steps/step_00_start/room_lighting.tres"), "step 0 already has room_lighting.tres")
	var sizes := _floor_sizes()
	for step: String in STEPS.slice(1):
		var data := _lighting(step)
		_expect(failures, data != null and (data.get_script() as Script).resource_path == "res://steps/%s/room_lighting.gd" % step, "%s: room_lighting.tres is not a room_lighting.gd Resource" % step)
		if data == null:
			continue
		var energy: Array[float] = data.energy
		var shadows: Array[bool] = data.shadows
		_expect(failures, energy.size() == Chain.SCENES.size() and shadows.size() == Chain.SCENES.size(), "%s: %d energies and %d shadow flags for %d room types" % [step, energy.size(), shadows.size(), Chain.SCENES.size()])
		if energy.size() != Chain.SCENES.size() or shadows.size() != Chain.SCENES.size():
			continue
		# A bigger floor never gets a weaker lamp.
		for a in sizes.size():
			for b in sizes.size():
				if sizes[a].x * sizes[a].z > sizes[b].x * sizes[b].z:
					_expect(failures, energy[a] >= energy[b], "%s: room type %d (%.0f m2) has a weaker lamp (%.1f) than room type %d (%.0f m2, %.1f)" % [step, a, sizes[a].x * sizes[a].z, energy[a], b, sizes[b].x * sizes[b].z, energy[b]])
			_expect(failures, energy[a] > SCENE_LAMP_ENERGY and energy[a] < 6.0, "%s: room type %d has energy %.1f" % [step, a, energy[a]])
		# Shadows where something stands free in the room and throws one: the vault's pillars. Nowhere else.
		for type in shadows.size():
			_expect(failures, shadows[type] == (type == Chain.Type.VAULT), "%s: room type %d has shadows %s" % [step, type, shadows[type]])
		var reach: float = data.reach
		_expect(failures, reach > 0.0 and reach <= 1.0, "%s: the lamp reaches %.2f m past the far corner, expected up to 1 m" % [step, reach])
		if _from(step, FOG_STEP):
			var fog: Array[float] = data.fog_energy
			_expect(failures, fog.size() == Chain.SCENES.size() and fog.min() > 0.0 and fog[Chain.Type.VAULT] == fog.max(), "%s: the fog energies %s (one per room type, the vault's shafts the strongest)" % [step, fog])
		else:
			_expect(failures, data.get("fog_energy") == null, "%s: room_lighting has fog energies before the fog step" % step)
	return failures

func test_room_lights_in_level(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step, true, {"goal_room": 7})
	var level: Node3D = main.get_node("Level")
	for i in 7:
		level._spawn_room(level.chain.next_plan())
	await _wait_physics(2)
	var data := _lighting(step) if _from(step, LIGHT_STEP) else null
	var types := {}
	for plan: Object in level.chain.plans:
		var room: Node3D = _rooms_of(level).filter(func(candidate: Node3D) -> bool: return candidate.global_transform == plan.transform)[0]
		var light := room.get_node("RoomLight") as OmniLight3D
		var label := "%s room %d (type %d)" % [step, plan.index, plan.type]
		types[plan.type] = true
		_expect(failures, light.light_color == Chain.LAMP_TINTS[plan.lamp], "%s: the light is %s, the plan says tint %d" % [label, light.light_color, plan.lamp])
		if data == null:
			_expect(failures, is_equal_approx(light.light_energy, SCENE_LAMP_ENERGY) and not light.shadow_enabled, "%s: step 0's lamp is not the scene's" % label)
			continue
		var size := _floor_sizes()[plan.type]
		var far_corner := Vector3(size.x / 2.0, light.position.y, size.z / 2.0).length()
		_expect(failures, is_equal_approx(light.light_energy, data.energy[plan.type]), "%s: energy %.2f, the data says %.2f" % [label, light.light_energy, data.energy[plan.type]])
		_expect(failures, light.shadow_enabled == data.shadows[plan.type], "%s: shadows %s, the data says %s" % [label, light.shadow_enabled, data.shadows[plan.type]])
		_expect(failures, light.omni_range >= far_corner and light.omni_range <= far_corner + 1.0 and is_equal_approx(light.omni_range, far_corner + data.reach), "%s: range %.2f for a far corner %.2f m away" % [label, light.omni_range, far_corner])
		if _from(step, FOG_STEP):
			_expect(failures, is_equal_approx(light.light_volumetric_fog_energy, data.fog_energy[plan.type]), "%s: fog energy %.2f, the data says %.2f" % [label, light.light_volumetric_fog_energy, data.fog_energy[plan.type]])
		else:
			_expect(failures, is_equal_approx(light.light_volumetric_fog_energy, 1.0), "%s: the fog energy changed before the fog step" % label)
	_expect(failures, types.size() >= 4, "only %d room types in the first eight rooms" % types.size())
	await _unload(main)
	# The exit: a small warm light of its own above the door, aimed at it, without shadows, with its lamp block (the
	# way out is brighter and warmer than the rest, and every light has a fixture that explains it).
	var door := (load("res://steps/%s/door.tscn" % step) as PackedScene).instantiate() as Node3D
	var exit_light := door.get_node_or_null("ExitLight") as SpotLight3D
	if not _from(step, LIGHT_STEP):
		_expect(failures, exit_light == null and door.get_node_or_null("ExitLamp") == null, "%s: the door has an exit light before step 1" % step)
	else:
		_expect(failures, exit_light != null, "%s: the door has no ExitLight" % step)
		if exit_light != null:
			var aim := -exit_light.transform.basis.z
			var to_door := (Vector3(0.0, 1.2, 0.0) - exit_light.position).normalized()
			_expect(failures, exit_light.position.y > DOORWAY_HEIGHT and exit_light.position.y < WALL_HEIGHT and exit_light.position.z > 0.2, "%s: the exit light is not above the doorway on the room's side (%s)" % [step, exit_light.position])
			_expect(failures, aim.dot(to_door) > 0.97 and exit_light.spot_range >= exit_light.position.distance_to(Vector3(0.0, 0.0, 0.0)) and exit_light.spot_range <= 5.0, "%s: the exit light does not reach the door, or reaches far beyond it" % step)
			_expect(failures, not exit_light.shadow_enabled and exit_light.light_color.r > exit_light.light_color.b + 0.2, "%s: the exit light casts shadows or is not warm" % step)
		var lamp := door.get_node_or_null("ExitLamp") as MeshInstance3D
		_expect(failures, lamp != null and lamp.layers == CEILING_LAYER and (lamp.mesh as BoxMesh).material.resource_path == MATERIAL_DIR + "fixture.tres", "%s: the exit light has no lamp block in fixture.tres on layer 2" % step)
	door.free()
	return failures

## The budget: one or two shadowed lamps that overlap per room. The level holds at most three rooms (the one behind the player,
## the one it is in, the next); the data gives shadows to the vault only, and two vaults are min_gap rooms apart.
func test_shadow_budget() -> Array[String]:
	var failures: Array[String] = []
	var data := _lighting(FINAL_STEP)
	var worst := 0
	for chain_seed in range(1, PLAN_SEEDS + 1):
		var plans: Array = _plans_to_goal(Chain, chain_seed, 20).plans
		for i in plans.size():
			var shadowed := 0
			for j in range(maxi(i - 1, 0), mini(i + 2, plans.size())):
				shadowed += 1 if data.shadows[plans[j].type] else 0
			worst = maxi(worst, shadowed)
	_expect(failures, worst <= 1, "%d shadowed lamps among three rooms that exist at once" % worst)
	for step: String in STEPS.slice(1):
		var key := (load("res://steps/%s/key.tscn" % step) as PackedScene).instantiate()
		for mesh: GeometryInstance3D in key.find_children("*", "GeometryInstance3D", true, false):
			_expect(failures, mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s: the key's %s throws a shadow: the vault's cube map would be drawn again every frame" % [step, mesh.name])
		key.free()
	print("        seeds 1-%d: at most %d shadowed lamp among the rooms that exist at once" % [PLAN_SEEDS, worst])
	return failures

## What a surface of the given linear albedo shows, lit by the environment's ambient light alone, as an sRGB value (before tonemapping).
func _ambient_shows(environment: Environment, albedo: float) -> float:
	var fill := environment.ambient_light_energy * environment.ambient_light_color.srgb_to_linear().get_luminance()
	var shown := albedo * fill
	return Color(shown, shown, shown).linear_to_srgb().r

func _wall_albedo() -> float:
	var wall := load(MATERIAL_DIR + "wall.tres") as StandardMaterial3D
	return wall.albedo_color.srgb_to_linear().r * (load(MATERIAL_DIR + "grid_1m.png") as Texture2D).get_image().get_pixel(100, 100).srgb_to_linear().r

## The brightest a material sends out on its own: emission colour times energy, linear.
func _emitted(material: StandardMaterial3D) -> float:
	if not material.emission_enabled:
		return 0.0
	var color := material.emission.srgb_to_linear()
	return maxf(color.r, maxf(color.g, color.b)) * material.emission_energy_multiplier

func test_environment(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step, false)
	var environment := (main.get_node("WorldEnvironment") as WorldEnvironment).environment
	var suns := main.find_children("*", "DirectionalLight3D", true, false)
	if not _from(step, ENVIRONMENT_STEP):
		# Tutorial 08's graybox look: a sky, a strong flat fill, a sun with shadows.
		_expect(failures, environment.background_mode == Environment.BG_SKY and environment.sky != null, "%s: the ProceduralSky is gone" % step)
		_expect(failures, suns.size() == 1 and (suns[0] as DirectionalLight3D).shadow_enabled, "%s: the sun of tutorial 08 is gone" % step)
		_expect(failures, _ambient_shows(environment, _wall_albedo()) >= 0.35, "%s: tutorial 08's flat fill is gone" % step)
		_expect(failures, environment.tonemap_mode == Environment.TONE_MAPPER_LINEAR and not environment.glow_enabled, "%s: tonemapping or glow before step 2" % step)
	else:
		_expect(failures, suns.is_empty(), "%s: a sun in a closed interior lights nothing and still renders its shadows" % step)
		_expect(failures, environment.background_mode == Environment.BG_COLOR and environment.background_color.get_luminance() < 0.05, "%s: the background is not a dark colour" % step)
		_expect(failures, environment.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR, "%s: the ambient light is not a colour" % step)
		var shows := _ambient_shows(environment, _wall_albedo())
		_expect(failures, shows >= 0.12 and shows <= 0.3, "%s: the ambient fill alone shows the walls at %.2f: below 0.12 a corner without lamp light is black, above 0.3 the lamps model nothing" % [step, shows])
		var color := environment.ambient_light_color
		_expect(failures, color.r >= color.g and color.g >= color.b and color.r - color.b < 0.1, "%s: the ambient %s is not a neutral, slightly warm fill" % [step, color])
		var weakest: float = (_lighting(step).energy as Array[float]).min()
		var fill := environment.ambient_light_energy * environment.ambient_light_color.srgb_to_linear().get_luminance()
		_expect(failures, weakest >= 10.0 * fill, "%s: the weakest lamp (%.2f) is not ten times the fill (%.3f): the lamps are the key light" % [step, weakest, fill])
		_expect(failures, environment.reflected_light_source == Environment.REFLECTION_SOURCE_DISABLED, "%s: the closed rooms reflect a sky nobody sees" % step)
		_expect(failures, environment.tonemap_mode == Environment.TONE_MAPPER_AGX, "%s: the tonemapper is %d, expected AgX (keeps the lamps' tints as they get brighter)" % [step, environment.tonemap_mode])
		_expect(failures, environment.glow_enabled and is_equal_approx(environment.glow_hdr_threshold, GLOW_THRESHOLD) and environment.glow_bloom == 0.0, "%s: glow is off, or it blooms more than what is brighter than white" % step)
		var fixture := load(MATERIAL_DIR + "fixture.tres") as StandardMaterial3D
		_expect(failures, _emitted(fixture) > GLOW_THRESHOLD, "%s: the lamp block sends %.2f, under the glow threshold: it does not glow" % [step, _emitted(fixture)])
		# The accents that glow in tutorial 08 (the key, the goal pad) may glow a little, never more than a lamp; nothing else glows.
		for accent: String in ["key", "goal"]:
			var material := load(MATERIAL_DIR + accent + ".tres") as StandardMaterial3D
			_expect(failures, _emitted(material) < _emitted(fixture), "%s: %s sends %.2f, as much as a lamp (%.2f)" % [step, accent, _emitted(material), _emitted(fixture)])
		for plain: String in ["door", "wall", "floor", "ceiling", "prop", "lock"]:
			var material := load(MATERIAL_DIR + plain + ".tres") as StandardMaterial3D
			_expect(failures, _emitted(material) < GLOW_THRESHOLD, "%s: %s sends %.2f: it would glow like a lamp" % [step, plain, _emitted(material)])
	_expect(failures, environment.volumetric_fog_enabled == _from(step, FOG_STEP), "%s: volumetric fog is %s" % [step, environment.volumetric_fog_enabled])
	_expect(failures, environment.sdfgi_enabled == _from(step, GI_STEP), "%s: SDFGI is %s" % [step, environment.sdfgi_enabled])
	await _unload(main)
	return failures

func test_volumetric_fog() -> Array[String]:
	var failures: Array[String] = []
	var sizes := _floor_sizes()
	var largest := 0.0
	var longest := 0.0
	for size in sizes:
		largest = maxf(largest, Vector2(size.x, size.z).length())
		longest = maxf(longest, maxf(size.x, size.z))
	for step: String in STEPS.slice(STEPS.find(FOG_STEP)):
		var main := await _load_step(step, false)
		var environment := (main.get_node("WorldEnvironment") as WorldEnvironment).environment
		var through := exp(-environment.volumetric_fog_density * largest)
		_expect(failures, environment.volumetric_fog_density > 0.0 and through >= 0.75, "%s: across the largest room (%.1f m) the fog lets through %.2f of the door's light, expected at least 0.75" % [step, largest, through])
		_expect(failures, through <= 0.85, "%s: across the largest room (%.1f m) the fog lets through %.2f of the door's light, expected at most 0.85: a thinner fog is not seen" % [step, largest, through])
		_expect(failures, environment.volumetric_fog_length >= longest and environment.volumetric_fog_length <= 32.0, "%s: the fog is computed over %.0f m: the longest room is %.0f m, and a longer range is coarser" % [step, environment.volumetric_fog_length, longest])
		_expect(failures, environment.volumetric_fog_ambient_inject > 0.0, "%s: the fog takes no ambient light: unlit fog is black" % step)
		_expect(failures, environment.volumetric_fog_albedo.get_luminance() > 0.85 and environment.volumetric_fog_anisotropy > 0.0, "%s: the fog is not a mist (near-white albedo, scatters forward)" % step)
		_expect(failures, environment.volumetric_fog_sky_affect == 0.0 and environment.volumetric_fog_temporal_reprojection_enabled, "%s: the fog draws on the background, or flickers without temporal reprojection" % step)
		print("        %s: density %.3f, %.0f%% of the light gets across the %.1f m of the largest room" % [step, environment.volumetric_fog_density, through * 100.0, largest])
		await _unload(main)
	return failures

func test_runtime_gi() -> Array[String]:
	var failures: Array[String] = []
	for step in STEPS:
		var gi := _from(step, GI_STEP)
		var main := await _load_step(step, false)
		var environment := (main.get_node("WorldEnvironment") as WorldEnvironment).environment
		if gi:
			_expect(failures, environment.sdfgi_enabled and not environment.sdfgi_read_sky_light and environment.sdfgi_use_occlusion, "%s: SDFGI is not set for a closed interior (on, no sky light, occlusion against leaks)" % step)
			_expect(failures, environment.sdfgi_y_scale == Environment.SDFGI_Y_SCALE_50_PERCENT and environment.sdfgi_energy >= 1.0, "%s: SDFGI's probes are not packed for 3 m high rooms (y scale %d), or its energy is %.1f" % [step, environment.sdfgi_y_scale, environment.sdfgi_energy])
		_expect(failures, main.find_children("*", "LightmapGI", true, false).is_empty() and main.find_children("*", "VoxelGI", true, false).is_empty(), "%s: a baked GI node in the scene" % step)
		await _unload(main)
		# What moves adds nothing to the GI: the door leaf and the lock swing, the key spins. The rooms' pieces stay Static.
		var expected := GeometryInstance3D.GI_MODE_DISABLED if gi else GeometryInstance3D.GI_MODE_STATIC
		var door := (load("res://steps/%s/door.tscn" % step) as PackedScene).instantiate()
		for mesh: GeometryInstance3D in door.get_node("Hinge").find_children("*", "GeometryInstance3D", true, false):
			_expect(failures, mesh.gi_mode == expected, "%s: the door's %s has GI mode %d, expected %d" % [step, mesh.name, mesh.gi_mode, expected])
		door.free()
		var key := (load("res://steps/%s/key.tscn" % step) as PackedScene).instantiate()
		for mesh: GeometryInstance3D in key.find_children("*", "GeometryInstance3D", true, false):
			_expect(failures, mesh.gi_mode == expected, "%s: the key's %s has GI mode %d, expected %d" % [step, mesh.name, mesh.gi_mode, expected])
		key.free()
		var room := (load("res://steps/%s/room_vault.tscn" % step) as PackedScene).instantiate()
		for mesh: GeometryInstance3D in room.find_children("*", "GeometryInstance3D", true, false):
			_expect(failures, mesh.gi_mode == GeometryInstance3D.GI_MODE_STATIC, "%s: the vault's %s is not Static: it would add nothing to the GI" % [step, room.get_path_to(mesh)])
		room.free()
	return failures

func test_gi_options() -> Array[String]:
	var failures: Array[String] = []
	# The engine itself: a running game can bake a VoxelGI, not a LightmapGI.
	_expect(failures, not ClassDB.class_has_method("LightmapGI", "bake") and ClassDB.class_has_method("VoxelGI", "bake") and "sdfgi_enabled" in Environment.new(), "the engine's GI classes are not what the step says")
	for step: String in STEPS.slice(STEPS.find(GI_STEP)):
		var check := load("res://steps/%s/gi_options.gd" % step) as GDScript
		var lines: Array[String] = check.call("report", "res://steps/%s/main.tscn" % step)
		_expect(failures, lines.size() == 5 and lines[1] == "LightmapGI  yes     no (editor only)" and lines[2] == "VoxelGI     yes     yes" and lines[3].begins_with("SDFGI       no"), "%s: the table:\n%s" % [step, "\n".join(lines)])
		_expect(failures, lines[-1] == "GI OK: main.tscn uses SDFGI, built while the game runs", "%s: %s" % [step, lines[-1]])
	var no_gi: Array[String] = GiOptions.report("res://steps/%s/main.tscn" % FOG_STEP)
	_expect(failures, no_gi[-1] == "GI FAILED: main.tscn uses no global illumination", "step 3: %s" % no_gi[-1])
	# A scene with a LightmapGI fails, a scene with a VoxelGI passes.
	for option: String in ["LightmapGI", "VoxelGI"]:
		var scene_root := Node3D.new()
		var node := ClassDB.instantiate(option) as Node3D
		scene_root.add_child(node)
		node.owner = scene_root
		var packed := PackedScene.new()
		packed.pack(scene_root)
		scene_root.free()
		DirAccess.make_dir_recursive_absolute(_save_dir)
		var path := _save_dir.path_join("with_%s.tscn" % option.to_lower())
		ResourceSaver.save(packed, path)
		var lines: Array[String] = GiOptions.report(path)
		if option == "LightmapGI":
			_expect(failures, lines[-1].begins_with("GI FAILED") and lines[-1].contains("only the editor can bake"), "a scene with a LightmapGI: %s" % lines[-1])
		else:
			_expect(failures, lines[-1].begins_with("GI OK") and lines[-1].contains("VoxelGI"), "a scene with a VoxelGI: %s" % lines[-1])
		DirAccess.remove_absolute(path)
	return failures

func test_gi_options_command() -> Array[String]:
	var failures: Array[String] = []
	var executable := OS.get_executable_path()
	if executable.is_empty():
		_skip("gi_options.gd from the command line", "no executable path")
		return failures
	var base: Array[String] = ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://steps/%s/gi_options.gd" % GI_STEP]
	var output: Array = []
	var code := OS.execute(executable, base, output, true)
	var text := _output_text(output)
	_expect(failures, code == 0 and text.contains("LightmapGI  yes     no (editor only)") and text.contains("GI OK: main.tscn uses SDFGI"), "step 4: exit code %d, output: %s" % [code, text.right(600)])
	var fog_step := base.duplicate()
	fog_step.append_array(["--", "--scene=res://steps/%s/main.tscn" % FOG_STEP])
	output = []
	code = OS.execute(executable, fog_step, output, true)
	text = _output_text(output)
	_expect(failures, code == 1 and text.contains("GI FAILED"), "step 3: exit code %d, output: %s" % [code, text.right(600)])
	return failures

func _quality_levels() -> Resource:
	return load("res://steps/%s/quality_levels.tres" % FINAL_STEP)

func test_quality_data() -> Array[String]:
	var failures: Array[String] = []
	var levels := _quality_levels()
	_expect(failures, levels != null and (levels.get_script() as Script).resource_path == "res://steps/%s/quality_levels.gd" % FINAL_STEP, "quality_levels.tres is not a quality_levels.gd Resource")
	if levels == null:
		return failures
	_expect(failures, levels.names == QUALITY_NAMES and levels.start_level == 2, "the levels are %s, the game starts on %d" % [levels.names, levels.start_level])
	for feature: String in ["gi", "fog", "shadows", "glow"]:
		var flags: Array[bool] = levels.get(feature)
		_expect(failures, flags.size() == QUALITY_NAMES.size() and flags[-1], "%s: %s, High must have it" % [feature, flags])
		for i in range(1, flags.size()):
			_expect(failures, not flags[i - 1] or flags[i], "%s: %s turns it on and %s off again" % [feature, QUALITY_NAMES[i - 1], QUALITY_NAMES[i]])
	_expect(failures, not levels.gi[0] and not levels.fog[0] and not levels.shadows[0] and not levels.gi[1], "Low still has an expensive part, or Medium has the GI: %s" % [[levels.gi, levels.fog, levels.shadows]])
	# High is the look of step 4.
	var main := await _load_step(FINAL_STEP, false)
	var high := (main.get_node("WorldEnvironment") as WorldEnvironment).environment
	var before := (load("res://steps/%s/main.tscn" % GI_STEP) as PackedScene).instantiate()
	var look := (before.get_node("WorldEnvironment") as WorldEnvironment).environment
	for property: String in ["sdfgi_enabled", "volumetric_fog_enabled", "glow_enabled", "volumetric_fog_density", "sdfgi_energy", "ambient_light_energy", "tonemap_mode"]:
		_expect(failures, high.get(property) == look.get(property), "High's %s is %s, step 4 has %s" % [property, high.get(property), look.get(property)])
	before.free()
	await _unload(main)
	return failures

func test_quality_switch() -> Array[String]:
	var failures: Array[String] = []
	_expect(failures, _physical_keys("cycle_quality") == ["Q"], "cycle_quality has the keys %s, expected Q" % [_physical_keys("cycle_quality")])
	var pad := false
	for event in InputMap.action_get_events("cycle_quality"):
		pad = pad or (event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == JOY_BUTTON_LEFT_SHOULDER)
	_expect(failures, pad, "cycle_quality has no left shoulder button")
	var levels := _quality_levels()
	var main := await _load_step(FINAL_STEP, true, {"goal_room": SHORT_GOAL})
	var quality := main.get_node("Quality")
	var environment := (main.get_node("WorldEnvironment") as WorldEnvironment).environment
	var label := main.get_node("HUD/QualityLabel") as Label
	_expect(failures, quality.get("current") == 2 and not label.visible and root.positional_shadow_atlas_size == SHADOW_ATLAS, "the game does not start on High with the shadows on and the label hidden")
	_expect(failures, (main.get_node("HUD/Stats/QualityHint") as Label).text == "Q  quality", "the HUD does not say Q")
	for expected: int in [0, 1, 2, 0]:
		await _key(KEY_Q, 113)
		_expect(failures, quality.get("current") == expected, "Q gave level %s, expected %d" % [quality.get("current"), expected])
		_expect(failures, environment.sdfgi_enabled == levels.gi[expected] and environment.volumetric_fog_enabled == levels.fog[expected] and environment.glow_enabled == levels.glow[expected], "%s: GI %s, fog %s, glow %s" % [QUALITY_NAMES[expected], environment.sdfgi_enabled, environment.volumetric_fog_enabled, environment.glow_enabled])
		_expect(failures, root.positional_shadow_atlas_size == (SHADOW_ATLAS if levels.shadows[expected] else 0), "%s: the shadow atlas is %d" % [QUALITY_NAMES[expected], root.positional_shadow_atlas_size])
		_expect(failures, label.visible and label.text == "Quality: " + QUALITY_NAMES[expected], "the label says \"%s\" (visible %s)" % [label.text, label.visible])
	await _wait_physics(100)
	_expect(failures, not label.visible, "the label is still up after 1.5 s")
	# The vault's lamp keeps its own flag: the level switches every shadow at once through the atlas.
	var level: Node3D = main.get_node("Level")
	for room: Node3D in _rooms_of(level):
		_expect(failures, (room.get_node("RoomLight") as OmniLight3D).shadow_enabled == _lighting(FINAL_STEP).shadows[Chain.SCENES.find(load(room.scene_file_path))], "a room's lamp lost its shadow flag")
	await _unload(main)
	_expect(failures, root.positional_shadow_atlas_size == SHADOW_ATLAS, "the shadow atlas stays at %d after the scene is gone" % root.positional_shadow_atlas_size)
	# The steps before have no switch: Q does nothing.
	var before := await _load_step(GI_STEP)
	var look := (before.get_node("WorldEnvironment") as WorldEnvironment).environment
	await _key(KEY_Q, 113)
	_expect(failures, look.sdfgi_enabled and look.volumetric_fog_enabled and root.positional_shadow_atlas_size == SHADOW_ATLAS, "Q changed step 4")
	await _unload(before)
	return failures

func test_quality_owns_its_copy() -> Array[String]:
	var failures: Array[String] = []
	var packed := load("res://steps/%s/main.tscn" % FINAL_STEP) as PackedScene
	var spare := packed.instantiate() # never enters the tree: it holds the scene's own Environment
	var shared := (spare.get_node("WorldEnvironment") as WorldEnvironment).environment
	var main := await _load_step(FINAL_STEP)
	var own := (main.get_node("WorldEnvironment") as WorldEnvironment).environment
	_expect(failures, own != shared, "the running game changes the Environment of main.tscn itself")
	await _key(KEY_Q, 113) # Low
	_expect(failures, not own.sdfgi_enabled and shared.sdfgi_enabled and shared.volumetric_fog_enabled, "Low reached the scene's own Environment")
	await _unload(main)
	_expect(failures, root.positional_shadow_atlas_size == SHADOW_ATLAS, "the shadow atlas is %d after the scene is gone" % root.positional_shadow_atlas_size)
	var again := await _load_step(FINAL_STEP)
	var fresh := (again.get_node("WorldEnvironment") as WorldEnvironment).environment
	_expect(failures, fresh.sdfgi_enabled and again.get_node("Quality").get("current") == 2, "a new game does not start on High after a game on Low")
	await _unload(again)
	spare.free()
	return failures

## One run of a seed, `ticks` long, with the autopilot; presses: Q every that many ticks (0: never).
func _quality_run(chain_seed: int, presses: int, ticks: int) -> Dictionary:
	var main := await _load_step(FINAL_STEP, true, {"goal_room": 8, "chain_seed": chain_seed})
	var level: Node3D = main.get_node("Level")
	await _wait_physics(30)
	var pilot := Autopilot.new(level)
	var snapshots: Array = []
	var state := {"ticks": 0, "switches": 0}
	_fast_forward(true)
	await _drive(func() -> bool:
		pilot.physics_step()
		state["ticks"] += 1
		if presses > 0 and state["ticks"] % presses == 0:
			_press_now(KEY_Q)
			state["switches"] += 1
		if state["ticks"] % 30 == 0:
			snapshots.append(_run_snapshot(level))
		return state["ticks"] >= ticks or level.state == STATE_FINISHED)
	pilot.release()
	_fast_forward(false)
	snapshots.append(_run_snapshot(level))
	var result := {snapshots = snapshots, plans = _plan_summary(level.chain.plans), switches = state["switches"], level = main.get_node("Quality").get("current")}
	await _unload(main)
	return result

func test_quality_changes_no_run() -> Array[String]:
	var failures: Array[String] = []
	for chain_seed: int in [42, 1000]:
		var plain := await _quality_run(chain_seed, 0, 600)
		var switched := await _quality_run(chain_seed, 37, 600)
		_expect(failures, switched.switches >= 10, "seed %d: only %d switches: the comparison would prove nothing" % [chain_seed, switched.switches])
		_expect(failures, plain.snapshots == switched.snapshots, "seed %d: the run differs when the quality switches" % chain_seed)
		_expect(failures, plain.plans == switched.plans, "seed %d: the plans differ when the quality switches" % chain_seed)
		print("        seed %d: %d snapshots equal with %d switches, the player in room %d" % [chain_seed, plain.snapshots.size(), switched.switches, plain.snapshots[-1][1]])
	return failures

## The new code of this tutorial only lights: room.gd's light_up() touches the lamp, quality.gd the Environment and the viewport,
## gi_options.gd reads scenes; none of them knows the chain, a plan, the run or the player. The level hands the lamp what it needs.
func test_light_reads_only() -> Array[String]:
	var failures: Array[String] = []
	var forbidden := RegEx.create_from_string("\\b(chain|plans?|seed\\w*|player|keys|run_time|_spawn_room|level\\.\\w+)\\b")
	for step: String in STEPS.slice(1):
		var files: Array[String] = ["room_lighting.gd"]
		if _from(step, GI_STEP):
			files.append("gi_options.gd")
		if step == FINAL_STEP:
			files.append_array(["quality.gd", "quality_levels.gd"])
		for file in files:
			for line in _code_lines("res://steps/%s/%s" % [step, file]):
				_expect(failures, forbidden.search(line) == null, "%s/%s: %s" % [step, file, line])
		var body := _function_body(FileAccess.get_file_as_string("res://steps/%s/room.gd" % step), "func light_up(")
		_expect(failures, not body.is_empty() and forbidden.search(body) == null and not body.contains("door") and not body.contains("key_spots"), "%s/room.gd: light_up() does more than light" % step)
		var level_source := FileAccess.get_file_as_string("res://steps/%s/level.gd" % step)
		_expect(failures, level_source.contains("room.light_up(Chain.LAMP_TINTS[plan.lamp], LIGHTING, plan.type)") and level_source.count("light") <= 6, "%s/level.gd: the level does more with the light than hand it the plan's tint and type" % step)
	return failures

#endregion

#region Tutorial 08: the kit from Blender, its import, the rooms built from it, the grid check

func _output_text(output: Array) -> String:
	var text := ""
	for chunk: Variant in output:
		text += str(chunk)
	return text

func _import_path(value: String) -> String:
	if value.begins_with("uid://"):
		return ResourceUID.get_id_path(ResourceUID.text_to_id(value))
	return value

func test_kit_import_settings() -> Array[String]:
	var failures: Array[String] = []
	for step in KIT_STEPS:
		for file in KIT_FILES:
			var config := ConfigFile.new()
			var path := "res://steps/%s/%s.import" % [step, file]
			if config.load(path) != OK:
				failures.append("%s cannot be read" % path)
				continue
			var piece := file.get_file().get_basename()
			var wanted: String = CheckKit.PIECES[piece].material
			var subresources: Dictionary = config.get_value("params", "_subresources", {})
			var materials: Dictionary = subresources.get("materials", {})
			_expect(failures, materials.keys() == [wanted], "%s: the materials %s, expected only %s" % [path, materials.keys(), wanted])
			if materials.has(wanted):
				var settings: Dictionary = materials[wanted]
				_expect(failures, settings.get("use_external/enabled", false) == true and _import_path(str(settings.get("use_external/path", ""))) == MATERIAL_DIR + wanted + ".tres", "%s: %s is not the project's %s.tres (%s)" % [path, wanted, wanted, settings])
			_expect(failures, config.get_value("remap", "importer", "") == "scene", "%s is not imported as a scene" % path)
			_expect(failures, config.get_value("params", "meshes/generate_lods", true) == false, "%s generates LODs" % path)
			_expect(failures, config.get_value("params", "nodes/use_name_suffixes", false) == true and config.get_value("params", "nodes/use_node_type_suffixes", false) == true, "%s: the name hints (-colonly) are switched off" % path)
	return failures

func test_kit_table(step: String) -> Array[String]:
	var failures: Array[String] = []
	var check := load("res://steps/%s/check_kit.gd" % step) as GDScript
	var lines: Array[String] = check.call("report", "res://steps/%s/kit" % step)
	_expect(failures, lines[-1].begins_with("KIT OK") and lines.size() == 2 + KIT_FILES.size() + 1, "the kit check of %s says: %s" % [step, "\n".join(lines.slice(2))])
	for file in KIT_FILES:
		var row_found := false
		for line in lines:
			row_found = row_found or line.begins_with(file.get_file().get_basename() + " ")
		_expect(failures, row_found, "no row for %s in the table" % file)
	print("        %s: %s" % [step, lines[-1]])
	return failures

func test_kit_colliders() -> Array[String]:
	var failures: Array[String] = []
	# The bodies Godot made of the -colonly boxes, named after the box without the hint.
	for step: String in KIT_STEPS:
		for file in KIT_FILES:
			var piece := file.get_file().get_basename()
			var scene := (load("res://steps/%s/%s" % [step, file]) as PackedScene).instantiate()
			var bodies := scene.find_children("*", "StaticBody3D", true, false)
			var expected: Variant = CheckKit.COLLIDERS[piece]
			var count := 1 if expected is String else (expected as Array).size()
			_expect(failures, bodies.size() == count, "%s/%s: %d bodies, expected %d" % [step, piece, bodies.size(), count])
			for body: StaticBody3D in bodies:
				_expect(failures, body.name.begins_with(piece + "_collider") and not body.name.contains("colonly"), "%s/%s: a body called %s" % [step, piece, body.name])
				_expect(failures, body.collision_layer == 1 and body.collision_mask == 1, "%s/%s: %s on layer %d mask %d, expected the world layer" % [step, piece, body.name, body.collision_layer, body.collision_mask])
				_expect(failures, body.get_child_count() == 1 and body.get_child(0) is CollisionShape3D, "%s/%s: %s is not one collision shape" % [step, piece, body.name])
			_expect(failures, scene.find_children("*", "MeshInstance3D", true, false).size() == 1, "%s/%s: a collider box kept its mesh" % [step, piece])
			scene.free()
	return failures

## A piece of the kit with a change made to it, packed as a scene again, so check_kit measures it like an imported one.
func _changed_piece(piece: String, change: Callable) -> PackedScene:
	var root_node := (load("res://steps/%s/kit/%s.glb" % [FINAL_STEP, piece]) as PackedScene).instantiate()
	change.call(root_node)
	for node in root_node.find_children("*", "", true, false):
		node.owner = root_node
	var packed := PackedScene.new()
	packed.pack(root_node)
	root_node.free()
	return packed

## The first mesh of a piece, rebuilt with its arrays changed by `change` (vertices, normals, UVs, indices).
func _change_mesh(root_node: Node, change: Callable) -> void:
	var instance := root_node.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var old := instance.mesh
	var arrays := old.surface_get_arrays(0)
	change.call(arrays)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, old.surface_get_material(0))
	instance.mesh = mesh

func _problems_with(piece: String, change: Callable) -> Array[String]:
	return CheckKit.check(piece, CheckKit.measure(_changed_piece(piece, change)))

func test_kit_check_finds_faults() -> Array[String]:
	var failures: Array[String] = []
	var none := func(_root_node: Node) -> void: pass
	_expect(failures, _problems_with("kit_wall_2m", none).is_empty(), "the wall, packed again unchanged, does not pass: %s" % [_problems_with("kit_wall_2m", none)])
	var faults := {
		"a wall twice as thick": ["kit_wall_2m", func(root_node: Node) -> void: (root_node.find_children("*", "MeshInstance3D", true, false)[0] as Node3D).scale = Vector3(1.0, 1.0, 2.0), "m, the kit says 2.00 x 3.00 x 0.20 m"],
		"a floor tile with its pivot at a corner": ["kit_floor_2x2", func(root_node: Node) -> void:
			for child: Node3D in root_node.get_children():
				child.position = Vector3(1.0, 0.0, 1.0), "its box starts at"],
		"a wall in the floor's material": ["kit_wall_2m", func(root_node: Node) -> void:
			var instance := root_node.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
			instance.mesh = instance.mesh.duplicate()
			instance.mesh.surface_set_material(0, load(MATERIAL_DIR + "floor.tres")), "material floor, the kit says wall"],
		"one face turned inside out": ["kit_wall_2m", func(root_node: Node) -> void:
			_change_mesh(root_node, func(arrays: Array) -> void:
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				var second := indices[1]
				indices[1] = indices[2]
				indices[2] = second
				arrays[Mesh.ARRAY_INDEX] = indices), "1 faces point into the piece"],
		"UVs at half a unit per metre": ["kit_corner", func(root_node: Node) -> void:
			_change_mesh(root_node, func(arrays: Array) -> void:
				var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
				for i in uvs.size():
					uvs[i] *= 0.5
				arrays[Mesh.ARRAY_TEX_UV] = uvs), "0.50 UV units per metre"],
		"a collider box left out": ["kit_doorway_2m", func(root_node: Node) -> void: root_node.get_node("kit_doorway_2m_collider_2").free(), "2 colliders, the kit says 3"],
		"a collider moved half a metre": ["kit_wall_1m", func(root_node: Node) -> void: (root_node.get_node("kit_wall_1m_collider") as Node3D).position.x = 0.5, "collider 0 is 1.00 x 3.00 x 0.20 m at"],
		"two collider boxes on each other": ["kit_corner", func(root_node: Node) -> void: (root_node.get_node("kit_corner_collider_1") as Node3D).position.z = -0.2, "colliders 0 and 1 overlap"],
		"the lintel's box down in the opening": ["kit_doorway_2m", func(root_node: Node) -> void: (root_node.get_node("kit_doorway_2m_collider_2") as Node3D).position.y = -2.4, "collider 2 is 1.60 x 0.60 x 0.20 m at"],
	}
	for fault: String in faults:
		var entry: Array = faults[fault]
		var problems := _problems_with(entry[0], entry[1])
		var found := false
		for problem in problems:
			found = found or problem.contains(entry[2])
		_expect(failures, found, "%s: not found (%s)" % [fault, problems])
	# A face across the doorway's hole, put into the measurement by hand.
	var doorway := CheckKit.measure(load("res://steps/%s/kit/kit_doorway_2m.glb" % FINAL_STEP) as PackedScene)
	(doorway.faces as Array).append(PackedVector3Array([Vector3(-0.5, 0.5, 0.1), Vector3(0.5, 0.5, 0.1), Vector3(0.0, 1.5, 0.1)]))
	var hole := CheckKit.check("kit_doorway_2m", doorway)
	_expect(failures, hole.has("kit_doorway_2m: a face lies in the opening"), "a face in the opening: not found (%s)" % [hole])
	return failures

func test_kit_command() -> Array[String]:
	var failures: Array[String] = []
	var executable := OS.get_executable_path()
	if executable.is_empty():
		_skip("check_kit.gd from the command line", "no executable path")
		return failures
	var base: Array[String] = ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://steps/%s/check_kit.gd" % FINAL_STEP]
	var output: Array = []
	var code := OS.execute(executable, base, output, true)
	var text := _output_text(output)
	_expect(failures, code == 0 and text.contains("KIT OK: 10 pieces") and text.contains("kit_doorway_2m") and text.contains("3 boxes"), "the kit: exit code %d, output: %s" % [code, text.right(600)])
	return failures

func test_kit_zoo(step: String) -> Array[String]:
	var failures: Array[String] = []
	var zoo := (load("res://steps/%s/kit_zoo.tscn" % step) as PackedScene).instantiate() as Node3D
	root.add_child(zoo)
	await _wait_physics(3)
	var check := load("res://steps/%s/check_kit.gd" % step) as GDScript
	var pieces: Array[Node3D] = []
	for child in zoo.get_node("Pieces").get_children():
		if not child is Label3D:
			pieces.append(child as Node3D)
	var labels: Array[Label3D] = zoo.get("labels")
	_expect(failures, pieces.size() == KIT_FILES.size() and labels.size() == KIT_FILES.size(), "%d pieces and %d labels, expected %d" % [pieces.size(), labels.size(), KIT_FILES.size()])
	var previous_end := -INF
	for i in mini(pieces.size(), KIT_FILES.size()):
		var name := KIT_FILES[i].get_file().get_basename()
		var piece := pieces[i]
		_expect(failures, piece.name == name and piece.scene_file_path == "res://steps/%s/%s" % [step, KIT_FILES[i]], "piece %d is %s (%s), expected %s" % [i, piece.name, piece.scene_file_path, name])
		var measured: Dictionary = check.call("measure", load(piece.scene_file_path) as PackedScene)
		var box: AABB = measured.box
		var placed := piece.transform * box
		_expect(failures, piece.basis.is_equal_approx(Basis.IDENTITY), "%s is turned: the zoo shows a piece the way it was exported" % name)
		_expect(failures, _near(placed.position.y, 1.0 if name == "kit_ceiling_2x2" else 0.0), "%s: its bottom is at %.2f m" % [name, placed.position.y])
		_expect(failures, placed.position.x >= previous_end + 1.0, "%s stands closer than 1 m to the piece before it" % name)
		previous_end = placed.end.x
		var dot := piece.get_node_or_null("Pivot") as MeshInstance3D
		_expect(failures, dot != null and dot.position == Vector3.ZERO, "%s: no pivot dot at its origin" % name)
		var text := labels[i].text
		_expect(failures, text.begins_with(name + "\n") and text.contains(CheckKit.size_text(box.size) + " m"), "%s: the label says %s" % [name, text.replace("\n", " | ")])
		var with_colliders := true
		_expect(failures, text.contains("colliders: ") == with_colliders, "%s: the label %s the colliders" % [name, "does not show" if with_colliders else "already shows"])
		_expect(failures, labels[i].global_position.y > piece.global_position.y + box.end.y, "%s: the label is not above the piece" % name)
	var figure := zoo.get_node("ScaleFigure") as MeshInstance3D
	var capsule := figure.mesh as CapsuleMesh
	var player_shape := ((zoo.get("player") as Node).get_node("CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D
	_expect(failures, capsule != null and is_equal_approx(capsule.height, player_shape.height) and is_equal_approx(capsule.radius, player_shape.radius) and is_equal_approx(figure.position.y, capsule.height / 2.0), "the scale figure is not the player's size, standing on the ground")
	root.remove_child(zoo)
	zoo.free()
	return failures

## Walks the zoo's player at each piece from the front and reports where it got to.
func test_kit_zoo_collision(step: String) -> Array[String]:
	var failures: Array[String] = []
	var zoo := (load("res://steps/%s/kit_zoo.tscn" % step) as PackedScene).instantiate() as Node3D
	root.add_child(zoo)
	await _wait_physics(3)
	var player: CharacterBody3D = zoo.get("player")
	var solid := true
	_fast_forward(true)
	for child in zoo.get_node("Pieces").get_children():
		if child is Label3D:
			continue
		var piece := child as Node3D
		var name := String(piece.name)
		var box: AABB = CheckKit.measure(load(piece.scene_file_path) as PackedScene).box
		var placed := piece.transform * box
		if name == "kit_floor_2x2": # dropped onto the tile from 1 m up: it carries the player, or the player falls through to the ground
			player.global_position = Vector3(placed.get_center().x, placed.end.y + 1.0, placed.get_center().z)
			player.velocity = Vector3.ZERO
			await _wait_physics(90 * SPEED_UP)
			var expected := placed.end.y if solid else 0.0
			_expect(failures, absf(player.global_position.y - expected) < 0.03, "%s: the player stands at y = %.2f, expected %.2f" % [name, player.global_position.y, expected])
			continue
		# In front of the piece, facing it (-Z), at a part of it a body runs into: the jamb of the doorway, the arm of the corner.
		var x := placed.get_center().x
		if name == "kit_doorway_2m":
			x = placed.position.x + 0.1
		elif name == "kit_corner":
			x = placed.position.x + 1.2
		var face := placed.position.z + (0.2 if name == "kit_corner" else placed.size.z)
		player.global_transform = Transform3D(Basis.IDENTITY, Vector3(x, 0.0, face + 2.0))
		player.velocity = Vector3.ZERO
		await _wait_physics(4)
		var ticks := {left = 48} # 4 m at 5 m/s: up to the face and 2 m on, if nothing stops the player
		Input.action_press("move_forward")
		await _drive(func() -> bool:
			ticks.left = int(ticks.left) - 1
			return int(ticks.left) <= 0)
		Input.action_release("move_forward")
		await _wait_physics(4)
		var at := player.global_position
		if name == "kit_plinth_3x3" or name == "kit_goal_pad": # a step: the player walks up onto it
			_expect(failures, absf(at.y - (placed.end.y if solid else 0.0)) < 0.03, "%s: the player is at y = %.2f on top of it" % [name, at.y])
		elif name == "kit_door_leaf": # its collider is on the door's hinge, not in the file
			_expect(failures, at.z < face - 1.0, "%s stopped the player at z = %.2f: the leaf has a collider of its own" % [name, at.z])
		elif solid:
			_expect(failures, absf(at.z - (face + PLAYER_RADIUS)) < 0.05, "%s: the player stopped at z = %.2f, its face is at %.2f" % [name, at.z, face])
		else:
			_expect(failures, at.z < face - 1.0, "%s stopped the player at z = %.2f before its colliders exist" % [name, at.z])
	_fast_forward(false)
	root.remove_child(zoo)
	zoo.free()
	return failures

## Is this room type built from the kit in this step?
func _kit_expected(step: String, room_type: String) -> bool:
	return STEPS.find(step) >= STEPS.find(KIT_FROM[room_type])

func test_kit_rooms(step: String) -> Array[String]:
	var failures: Array[String] = []
	var kit_rooms := 0
	for room_type: String in KIT_FROM:
		var room := (load("res://steps/%s/room_%s.tscn" % [step, room_type]) as PackedScene).instantiate() as Node3D
		var kit := _kit_expected(step, room_type)
		_expect(failures, _is_kit_room(room) == kit, "room_%s is %s, expected %s" % [room_type, "built from the kit" if _is_kit_room(room) else "a CSG shell", "the kit" if kit else "tutorial 07's CSG shell"])
		if kit and _is_kit_room(room):
			kit_rooms += 1
			_expect(failures, room.find_children("*", "CSGShape3D", true, false).is_empty(), "room_%s still has CSG" % room_type)
			var problems := Grid.problems_of(room, "room_" + room_type)
			_expect(failures, problems.is_empty(), "room_%s: %s" % [room_type, "; ".join(problems)])
			for piece in Grid.pieces_of(room):
				_expect(failures, piece.scene_file_path.begins_with("res://steps/%s/" % step), "room_%s: %s comes from %s, not from this step's folder" % [room_type, piece.name, piece.scene_file_path])
		room.free()
	if true: # no CSG left anywhere in the step
		for file in _step_files(step):
			if file.ends_with(".tscn"):
				_expect(failures, not FileAccess.get_file_as_string("res://steps/%s/%s" % [step, file]).contains("type=\"CSG"), "%s still has CSG" % file)
	print("        %s: %d of %d room types built from the kit" % [step, kit_rooms, KIT_FROM.size()])
	return failures

func test_kit_door_leaf() -> Array[String]:
	var failures: Array[String] = []
	for step in STEPS:
		var door := (load("res://steps/%s/door.tscn" % step) as PackedScene).instantiate() as Node3D
		var hinge := door.get_node("Hinge") as AnimatableBody3D
		var shape_node := hinge.get_node("CollisionShape3D") as CollisionShape3D
		var collider := shape_node.transform * AABB(-(shape_node.shape as BoxShape3D).size / 2.0, (shape_node.shape as BoxShape3D).size)
		var leaf := door.get_node_or_null("Hinge/Leaf") as Node3D
		var kit := true
		_expect(failures, hinge != null and hinge.sync_to_physics, "%s: the hinge is not an AnimatableBody3D that moves with the physics" % step)
		if kit:
			_expect(failures, leaf != null and leaf.scene_file_path == "res://steps/%s/kit/kit_door_leaf.glb" % step and leaf.transform == Transform3D.IDENTITY, "%s: the leaf is not the kit's door leaf on the hinge's pivot" % step)
			if leaf != null:
				var mesh_node := leaf.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
				var box := mesh_node.transform * mesh_node.mesh.get_aabb()
				_expect(failures, _near(box.position.x, collider.position.x) and _near(box.position.y, collider.position.y) and _near(box.position.z, collider.position.z) and _near(box.size.x, collider.size.x) and _near(box.size.y, collider.size.y) and _near(box.size.z, collider.size.z), "%s: the leaf's box %s is not the hinge's collider %s" % [step, box, collider])
				_expect(failures, mesh_node.mesh.surface_get_material(0).resource_path == MATERIAL_DIR + "door.tres", "%s: the leaf is not in door.tres" % step)
				_expect(failures, leaf.find_children("*", "CollisionObject3D", true, false).is_empty(), "%s: the leaf brings a body of its own: a StaticBody3D would not move with the hinge" % step)
		else:
			var slab := door.get_node("Hinge/MeshInstance3D") as MeshInstance3D
			var size := (slab.mesh as BoxMesh).size
			_expect(failures, (slab.transform * AABB(-size / 2.0, size)).is_equal_approx(collider), "%s: the slab is not the hinge's collider" % step)
		door.free()
	return failures

func test_ceiling_tile() -> Array[String]:
	var failures: Array[String] = []
	for step: String in STEPS:
		var path := "res://steps/%s/ceiling_tile.tscn" % step
		var text := FileAccess.get_file_as_string(path)
		_expect(failures, text.contains("path=\"res://steps/%s/kit/kit_ceiling_2x2.glb\"" % step) and text.contains("[node name=\"CeilingTile\" instance=ExtResource("), "%s: not a scene inherited from the kit's ceiling tile" % path)
		var tile := (load(path) as PackedScene).instantiate() as Node3D
		var meshes := tile.find_children("*", "MeshInstance3D", true, false)
		_expect(failures, meshes.size() == 1 and (meshes[0] as MeshInstance3D).layers == CEILING_LAYER, "%s: the mesh is not on layer 2 only" % path)
		var bodies := tile.find_children("*", "StaticBody3D", true, false)
		_expect(failures, bodies.size() == 1 and (bodies[0] as StaticBody3D).collision_layer == 1, "%s: no collider on the world layer: a jump would go through the ceiling" % path)
		if meshes.size() == 1:
			_expect(failures, (meshes[0] as MeshInstance3D).mesh.surface_get_material(0).resource_path == MATERIAL_DIR + "ceiling.tres", "%s is not in ceiling.tres" % path)
		tile.free()
	return failures

## A room of a step on its own in the test world, far from the others, with its door taken out.
func _lone_room(step: String, room_type: String, holder: Node3D, offset: Vector3) -> Node3D:
	var room := (load("res://steps/%s/room_%s.tscn" % [step, room_type]) as PackedScene).instantiate() as Node3D
	room.position = offset
	holder.add_child(room)
	var door: Node = room.get("door")
	if door != null:
		door.free()
	return room

## The walls of a room: each edge with its inner face and the stretches along it that are wall (not a doorway), in the room's space.
## edge: the way out of the room (the wall's normal pointing out), half: half the edge's length, face: the inner face's distance from
## the middle, doors: where along the edge the doorways are.
func _edges_of(room: Node3D) -> Array[Dictionary]:
	var half := _footprint(room) / 2.0
	var edges: Array[Dictionary] = [
		{name = "far", out = Vector3.FORWARD, along = Vector3.RIGHT, half = half.x, face = half.y - WALL_THICKNESS, doors = []},
		{name = "near", out = Vector3.BACK, along = Vector3.LEFT, half = half.x, face = half.y - WALL_THICKNESS, doors = []},
		{name = "left", out = Vector3.LEFT, along = Vector3.FORWARD, half = half.y, face = half.x - WALL_THICKNESS, doors = []},
		{name = "right", out = Vector3.RIGHT, along = Vector3.BACK, half = half.y, face = half.x - WALL_THICKNESS, doors = []},
	]
	for marker_name: String in ["Entrance", "Exit"]:
		var marker := room.get_node_or_null(marker_name) as Marker3D
		if marker == null:
			continue
		for edge in edges:
			if absf(marker.position.dot(edge.out) - (float(edge.face) + WALL_THICKNESS)) < 0.01:
				(edge.doors as Array).append(marker.position.dot(edge.along))
	return edges

## The boxes on the floor a player has to go round: the vault's pillars (the CSG ones or the kit's), as rectangles in x and z.
func _obstacles_of(room: Node3D) -> Array[Rect2]:
	var found: Array[Rect2] = []
	for pillar in _parts_named(room, "Pillar"):
		var box: AABB = _part(room, pillar).box
		found.append(Rect2(Vector2(box.position.x, box.position.z), Vector2(box.size.x, box.size.z)))
	return found

func _player_for(step: String, parent: Node3D, at: Vector3, yaw: float) -> CharacterBody3D:
	var player := (load("res://steps/%s/player.tscn" % step) as PackedScene).instantiate() as CharacterBody3D
	parent.add_child(player)
	player.global_transform = Transform3D(Basis(Vector3.UP, yaw), at)
	return player

## The yaw that makes a player face this way (its forward is -Z).
func _yaw_towards(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)

func test_walls_hold(step: String) -> Array[String]:
	var failures: Array[String] = []
	var holder := Node3D.new()
	root.add_child(holder)
	var probes: Array[Dictionary] = []
	var room_index := 0
	for room_type: String in KIT_FROM:
		var room := _lone_room(step, room_type, holder, Vector3(room_index * 60.0, 0.0, 0.0))
		room_index += 1
		var obstacles := _obstacles_of(room)
		for edge in _edges_of(room):
			var out: Vector3 = edge.out
			var along: Vector3 = edge.along
			var face: float = edge.face
			var at := -float(edge.half) + 0.5
			while at <= float(edge.half) - 0.5 + 0.001:
				var free := true
				for door: float in edge.doors:
					free = free and absf(at - door) >= DOORWAY_WIDTH / 2.0 + PLAYER_RADIUS + 0.1
				var start := along * at + out * (face - 1.5)
				for obstacle in obstacles: # the way from the start to the wall must not run into a pillar
					var path := Rect2(Vector2(start.x, start.z), Vector2.ZERO).expand(Vector2((start + out * 1.5).x, (start + out * 1.5).z)).grow(PLAYER_RADIUS + 0.1)
					free = free and not path.intersects(obstacle)
				if free:
					var player := _player_for(step, room, room.global_transform * start, _yaw_towards(out))
					probes.append({player = player, room = room_type, edge = edge.name, at = at, out = out, face = face, origin = room.global_position})
				at += 0.5
	await _wait_physics(3)
	_fast_forward(true)
	Input.action_press("move_forward")
	await _wait_physics(40 * SPEED_UP)
	Input.action_release("move_forward")
	await _wait_physics(4 * SPEED_UP)
	_fast_forward(false)
	var worst := 0.0
	for probe in probes:
		var player: CharacterBody3D = probe.player
		var local := player.global_position - (probe.origin as Vector3)
		var gap := float(probe.face) - local.dot(probe.out) # from the capsule's axis to the wall's face
		worst = maxf(worst, absf(gap - PLAYER_RADIUS))
		_expect(failures, absf(gap - PLAYER_RADIUS) < 0.05 and absf(player.global_position.y) < 0.05, "room_%s, %s wall at %.1f m: the player stopped %.2f m from the face (y = %.2f), expected %.2f" % [probe.room, probe.edge, probe.at, gap, player.global_position.y, PLAYER_RADIUS])
	print("        %s: %d pushes into %d rooms' walls, every one stopped at the face (within %.3f m)" % [step, probes.size(), KIT_FROM.size(), worst])
	root.remove_child(holder)
	holder.free()
	return failures

## The floor height under a point of a room: the vault's platform and the goal pad are a step up.
func _floor_height(room: Node3D, point: Vector3) -> float:
	var space := room.get_world_3d().direct_space_state
	var from := room.global_transform * Vector3(point.x, 1.0, point.z)
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 2.0))
	return (hit["position"] as Vector3).y if not hit.is_empty() else -1.0

## The points of a walk over the whole floor: from where the player stands, lane after lane (see _floor_lanes). Between two lanes the walk
## turns a corner, so that every leg runs along a lane's line or across at a lane's end, never diagonally past a pillar.
func _floor_route(room: Node3D) -> PackedVector3Array:
	var route := PackedVector3Array()
	var lanes := _floor_lanes(room)
	var spawn := (room.get_node("Entrance") as Marker3D).transform.translated_local(Vector3(0.0, 0.0, -1.5)).origin
	route.append(Vector3(spawn.x, 0.0, lanes[0][0].z)) # straight in from the entrance, to the line of the first lane
	for i in lanes.size():
		var lane := lanes[i]
		route.append(lane[0])
		route.append(lane[1])
		if i + 1 < lanes.size():
			var next := lanes[i + 1]
			var along_x := absf(lane[0].z - lane[1].z) < 0.001
			var next_along_x := absf(next[0].z - next[1].z) < 0.001
			route.append(Vector3(lane[1].x, 0.0, next[0].z) if along_x and next_along_x else Vector3(next[0].x, 0.0, lane[1].z))
	return route

## Lanes over the whole floor of a room, 2 m apart, first along X, then along Z, in the room's space; each lane cut short where a
## pillar stands in it. Every lane crosses the seams of the floor tiles the other way.
func _floor_lanes(room: Node3D) -> Array[PackedVector3Array]:
	var lanes: Array[PackedVector3Array] = []
	var half := _footprint(room) / 2.0 - Vector2.ONE * (WALL_THICKNESS + PLAYER_RADIUS + 0.2)
	var obstacles := _obstacles_of(room)
	for axis: int in [0, 2]:
		var across := half.y if axis == 0 else half.x
		var length := half.x if axis == 0 else half.y
		var offset := -across
		while offset <= across + 0.001:
			var low := -length
			var high := length
			for obstacle in obstacles:
				var grown := obstacle.grow(PLAYER_RADIUS + 0.15)
				var lane_at := offset
				var crosses := (grown.position.y < lane_at and grown.end.y > lane_at) if axis == 0 else (grown.position.x < lane_at and grown.end.x > lane_at)
				if crosses: # keep the part of the lane between the pillars
					var from := grown.position.x if axis == 0 else grown.position.y
					var to := grown.end.x if axis == 0 else grown.end.y
					if to < 0.0:
						low = maxf(low, to)
					else:
						high = minf(high, from)
			var a := Vector3(low, 0.0, offset) if axis == 0 else Vector3(offset, 0.0, low)
			var b := Vector3(high, 0.0, offset) if axis == 0 else Vector3(offset, 0.0, high)
			lanes.append(PackedVector3Array([a, b] if lanes.size() % 2 == 0 else [b, a]))
			offset += 2.0
	return lanes

func test_walk_every_room(step: String) -> Array[String]:
	var failures: Array[String] = []
	var holder := Node3D.new()
	root.add_child(holder)
	var walked := 0.0
	var hugged := 0.0
	_fast_forward(true)
	for room_type: String in KIT_FROM:
		var room := _lone_room(step, room_type, holder, Vector3.ZERO)
		await _wait_physics(2)
		var player := _player_for(step, room, room.global_transform * (room.get_node("Entrance") as Marker3D).transform.translated_local(Vector3(0.0, 0.0, -1.5)).origin, 0.0)
		var label := "room_%s" % room_type
		# 1. The floor: lane after lane, steering at the next point, never held, never off the floor.
		for target in _floor_route(room):
			var result := await _walk_to(room, player, target, label)
			walked += float(result.walked)
			if not str(result.problem).is_empty():
				failures.append(result.problem)
		# 2. Along every wall: pressed against it (forward and to the left), sliding past every seam, between the corners and doorways.
		for edge in _edges_of(room):
			var stops: Array[float] = [-float(edge.half)]
			for door: float in edge.doors:
				stops.append_array([door - CheckKit.CELL / 2.0, door + CheckKit.CELL / 2.0])
			stops.append(float(edge.half))
			stops.sort()
			for i in range(0, stops.size(), 2):
				if stops[i + 1] - stops[i] < 2.2: # too short a stretch to slide along
					continue
				var result := await _hug_wall(room, player, edge, stops[i] + 0.8, stops[i + 1] - 0.8, label)
				hugged += float(result.walked)
				if not str(result.problem).is_empty():
					failures.append(result.problem)
		holder.remove_child(room)
		room.free()
		await _wait_physics(2)
	_fast_forward(false)
	for action: String in ["move_forward", "move_left"]:
		Input.action_release(action)
	print("        %s: %.0f m across the floors and %.0f m along the walls of %d rooms" % [step, walked, hugged, KIT_FROM.size()])
	root.remove_child(holder)
	holder.free()
	return failures

## Walks the player to a point of the room (room space) the way a person steers: face it, walk. Held in place for 0.5 s: a problem.
func _walk_to(room: Node3D, player: CharacterBody3D, target: Vector3, label: String) -> Dictionary:
	var state := {ticks = 0, best = INF, since_best = 0, walked = 0.0, problem = "", last = player.global_position, off_floor = 0}
	var goal := room.global_transform * target
	Input.action_press("move_forward")
	await _drive(func() -> bool:
		var to_goal := Vector3(goal.x - player.global_position.x, 0.0, goal.z - player.global_position.z)
		state.walked = float(state.walked) + Vector2(player.global_position.x - (state.last as Vector3).x, player.global_position.z - (state.last as Vector3).z).length()
		state.last = player.global_position
		if to_goal.length() < 0.15:
			return true
		player.rotation.y = _yaw_towards(to_goal)
		state.ticks = int(state.ticks) + 1
		if to_goal.length() < float(state.best) - 0.01:
			state.best = to_goal.length()
			state.since_best = 0
		else:
			state.since_best = int(state.since_best) + 1
		var floor_y := _floor_height(room, room.global_transform.affine_inverse() * player.global_position)
		state.off_floor = int(state.off_floor) + 1 if absf(player.global_position.y - floor_y) > 0.05 else 0
		if int(state.off_floor) > 15: # stepping up onto the platform takes a few ticks
			state.problem = "%s: the player stands at y = %.2f where the floor is at %.2f (%s)" % [label, player.global_position.y, floor_y, _local_text(room, player)]
			return true
		if int(state.since_best) > 30:
			state.problem = "%s: the player was held at %s on the way to %s" % [label, _local_text(room, player), target]
			return true
		return int(state.ticks) > 60 * 20)
	Input.action_release("move_forward")
	if str(state.problem).is_empty() and Vector2(goal.x - player.global_position.x, goal.z - player.global_position.z).length() >= 0.15:
		state.problem = "%s: the player did not reach %s (at %s)" % [label, target, _local_text(room, player)]
	return state

## Slides the player along a wall from one point to another (along the edge, room space), pressed against it: it walks forward with
## the wall on its left and presses to the left. It has to keep its pace past every seam and stay against the wall.
func _hug_wall(room: Node3D, player: CharacterBody3D, edge: Dictionary, from: float, to: float, label: String) -> Dictionary:
	var out: Vector3 = edge.out
	var along: Vector3 = edge.along
	var start := along * from + out * (float(edge.face) - PLAYER_RADIUS - 0.2)
	var walked := 0.0
	var problem := ""
	# Walk to the start of the stretch first, through the room.
	var result := await _walk_to(room, player, start, label)
	if not str(result.problem).is_empty():
		return {walked = 0.0, problem = result.problem}
	player.rotation.y = _yaw_towards(along) # the wall is on the left: the edges run with the room on their right
	player.velocity = Vector3.ZERO
	var state := {ticks = 0, window = [], problem = ""}
	Input.action_press("move_forward")
	Input.action_press("move_left")
	await _drive(func() -> bool:
		var local := room.global_transform.affine_inverse() * player.global_position
		var at := local.dot(along)
		var window: Array = state.window
		window.append(at)
		state.ticks = int(state.ticks) + 1
		if at >= to:
			return true
		if int(state.ticks) > 20:
			var gap := float(edge.face) - local.dot(out)
			if gap > PLAYER_RADIUS + 0.03:
				state.problem = "%s, %s wall: the player came off the wall at %.1f m (%.2f m from its face)" % [label, edge.name, at, gap]
				return true
			if window.size() > 10 and at - float(window[-11]) < 0.3: # 10 ticks at 3.5 m/s are 0.59 m
				state.problem = "%s, %s wall: the player slowed down at %.1f m (%.2f m in 10 ticks)" % [label, edge.name, at, at - float(window[-11])]
				return true
		return int(state.ticks) > 60 * 10)
	Input.action_release("move_forward")
	Input.action_release("move_left")
	walked = to - from
	problem = state.problem
	var reached := (room.global_transform.affine_inverse() * player.global_position).dot(along)
	if problem.is_empty() and reached < to:
		problem = "%s, %s wall: the player stopped at %.1f m, the stretch ends at %.1f" % [label, edge.name, reached, to]
	return {walked = walked, problem = problem}

func _local_text(room: Node3D, player: CharacterBody3D) -> String:
	var local := room.global_transform.affine_inverse() * player.global_position
	return "(%.2f, %.2f, %.2f)" % [local.x, local.y, local.z]

func test_kit_fixtures() -> Array[String]:
	var failures: Array[String] = []
	var before: Array = (load("res://steps/step_00_start/check_contents.gd") as GDScript).call("read_layouts") # tutorial 08's final fixtures
	var after: Array = Contents.read_layouts()
	var counts: Array[int] = []
	for i in after.size():
		var old_rects: Array[Rect2] = before[i].fixtures
		var new_rects: Array[Rect2] = after[i].fixtures
		counts.append(new_rects.size())
		var old_area := 0.0
		var new_area := 0.0
		for rect in old_rects:
			old_area += rect.get_area()
		for rect in new_rects:
			new_area += rect.get_area()
			var inside := false
			for old in old_rects:
				inside = inside or old.grow(0.001).encloses(rect)
			_expect(failures, inside, "room type %d: the kit fixture %s lies outside tutorial 08's fixtures" % [i, rect])
		_expect(failures, absf(old_area - new_area) < 0.01, "room type %d: the kit fixtures cover %.2f m2, tutorial 08's %.2f m2" % [i, new_area, old_area])
	_expect(failures, counts[Chain.Type.VAULT] == 8 and counts[Chain.Type.GOAL] == 1, "the vault has %d fixtures (4 pillars and 4 plinths expected), the goal room %d (the pad)" % [counts[Chain.Type.VAULT], counts[Chain.Type.GOAL]])
	return failures

func test_grid_rooms() -> Array[String]:
	var failures: Array[String] = []
	for step: String in STEPS:
		for room_type: String in KIT_FROM:
			if not _kit_expected(step, room_type):
				continue
			var room := (load("res://steps/%s/room_%s.tscn" % [step, room_type]) as PackedScene).instantiate() as Node3D
			var problems := Grid.problems_of(room, "room_" + room_type)
			_expect(failures, problems.is_empty(), "%s room_%s: %s" % [step, room_type, "; ".join(problems)])
			# The schedule, worked out a second time from the room's size and its doorways.
			var footprint := _footprint(room)
			var counts := Grid.schedule(room)
			var doorways := 2 if room.get_node_or_null("Exit") != null else 1
			var tiles := int(footprint.x * footprint.y / 4.0)
			var wall_metres := 2 * (footprint.x + footprint.y) - 4 * 2 * CheckKit.CELL - doorways * CheckKit.CELL
			var counted_metres := 2.0 * int(counts.get(Grid.WALL_2M, 0)) + 1.0 * int(counts.get(Grid.WALL_1M, 0))
			_expect(failures, int(counts.get(Grid.FLOOR, 0)) == tiles and int(counts.get(Grid.CEILING, 0)) == tiles and int(counts.get(Grid.CORNER, 0)) == 4 and int(counts.get(Grid.DOORWAY, 0)) == doorways and is_equal_approx(counted_metres, wall_metres), "%s room_%s: the schedule %s, expected %d tiles, 4 corners, %d doorways and %.0f m of wall" % [step, room_type, counts, tiles, doorways, wall_metres])
			room.free()
	var paths: Array[String] = []
	for scene in Chain.SCENES:
		paths.append(scene.resource_path)
	var lines := Grid.report(paths)
	_expect(failures, lines[-1] == "GRID OK: 7 rooms, every piece on the grid, no gap, no overlap" and lines[1].begins_with("piece ") and lines.size() == 2 + Grid.PIECE_ORDER.size() + 1, "the report: %s" % "\n".join(lines))
	print("        the tile schedule of the finished rooms:")
	for line: String in lines.slice(0, -1):
		print("          " + line)
	return failures

## A room of the final step with one thing done to it, and what check_grid says about it.
func _grid_problems_after(room_type: String, change: Callable) -> Array[String]:
	var room := (load("res://steps/%s/room_%s.tscn" % [FINAL_STEP, room_type]) as PackedScene).instantiate() as Node3D
	change.call(room)
	var problems := Grid.problems_of(room, "room_" + room_type)
	room.free()
	return problems

func test_grid_finds_faults() -> Array[String]:
	var failures: Array[String] = []
	_expect(failures, _grid_problems_after("wide", func(_room: Node3D) -> void: pass).is_empty(), "room_wide fails unchanged")
	var faults := {
		"a wall nudged by 0.2 m": ["wide", func(room: Node3D) -> void: (room.get_node("Shell/Walls/Wall1") as Node3D).position.x += 0.2, "Shell/Walls/Wall1 is off the grid"],
		"a wall moved by half a metre": ["straight", func(room: Node3D) -> void: (room.get_node("Shell/Walls/Wall1") as Node3D).position.x -= 0.5, "overlap"],
		"a gap where a wall moved": ["straight", func(room: Node3D) -> void: (room.get_node("Shell/Walls/Wall1") as Node3D).position.x -= 0.5, "has a gap from"],
		"a floor tile taken out": ["vault", func(room: Node3D) -> void: room.get_node("Shell/Floor/Tile7").free(), "room_vault: the floor has a gap: 192 of 196 m2 covered"],
		"a wall twice on the same spot": ["long", func(room: Node3D) -> void:
			var copy := room.get_node("Shell/Walls/Wall3").duplicate() as Node3D
			room.get_node("Shell/Walls").add_child(copy)
			copy.owner = room, "overlap"],
		"a wall turned round": ["turn_left", func(room: Node3D) -> void: (room.get_node("Shell/Walls/Wall2") as Node3D).rotate_y(PI), "Shell/Walls/Wall2 faces out of the room"],
		"the exit's doorway one cell over": ["straight", func(room: Node3D) -> void:
			var doorway := room.get_node("Shell/Walls/ExitDoorway") as Node3D
			var wall := room.get_node("Shell/Walls/Wall1") as Node3D
			var place := doorway.position
			doorway.position = wall.position
			wall.position = place, "no doorway at the exit"],
		"a CSG box left in the shell": ["goal", func(room: Node3D) -> void:
			var box := CSGBox3D.new()
			room.get_node("Shell").add_child(box)
			box.owner = room, "is no kit piece (a CSGBox3D in the shell)"],
		"a ceiling tile 10 cm too high": ["turn_right", func(room: Node3D) -> void: (room.get_node("Ceiling/Tile5") as Node3D).position.y = 3.1, "Ceiling/Tile5 is off the grid"],
		"a floor tile on another one": ["straight", func(room: Node3D) -> void: (room.get_node("Shell/Floor/Tile2") as Node3D).position = (room.get_node("Shell/Floor/Tile1") as Node3D).position, "lie on each other"],
	}
	for fault: String in faults:
		var entry: Array = faults[fault]
		var problems := _grid_problems_after(entry[0], entry[1])
		var found := false
		for problem in problems:
			found = found or problem.contains(entry[2])
		_expect(failures, found, "%s in room_%s: not found (%s)" % [fault, entry[0], problems])
	return failures

func test_grid_command() -> Array[String]:
	var failures: Array[String] = []
	var executable := OS.get_executable_path()
	if executable.is_empty():
		_skip("check_grid.gd from the command line", "no executable path")
		return failures
	var base: Array[String] = ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://steps/%s/check_grid.gd" % FINAL_STEP]
	var output: Array = []
	var code := OS.execute(executable, base, output, true)
	var text := _output_text(output)
	_expect(failures, code == 0 and text.contains("tile schedule") and text.contains("GRID OK: 7 rooms"), "the finished rooms: exit code %d, output: %s" % [code, text.right(800)])
	return failures

#endregion

#region Tutorial 07: debug views, the record of rejected rooms, the watch, pinned seeds

const VIEW_FILES: Array[String] = ["gizmos.gd", "lines.gd", "generation_watch.gd"]
const PIN_LETTERS := {"STRAIGHT": "S", "LONG": "L", "TURN_LEFT": "<", "TURN_RIGHT": ">", "WIDE": "W", "VAULT": "V", "GOAL": "G"} ## The letters of the pinned seeds, written down here a second time on purpose.

func _step_has(step: String, file: String) -> bool:
	return FileAccess.file_exists("res://steps/%s/%s" % [step, file])

## The lines a Lines node drew in its last frame: from, to, colour.
func _drawn(lines: Node) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var points: PackedVector3Array = lines.points
	var colors: PackedColorArray = lines.colors
	for i in range(0, points.size(), 2):
		found.append({from = points[i], to = points[i + 1], color = colors[i]})
	return found

## True if a line from a to b (or from b to a) in this colour was drawn.
func _has_line(drawn: Array[Dictionary], a: Vector3, b: Vector3, color: Color) -> bool:
	for entry in drawn:
		var from: Vector3 = entry.from
		var to: Vector3 = entry.to
		var shade: Color = entry.color
		if shade.is_equal_approx(color) and ((from.is_equal_approx(a) and to.is_equal_approx(b)) or (from.is_equal_approx(b) and to.is_equal_approx(a))):
			return true
	return false

## The 12 edges of a box, each as two corners.
func _box_edges(bounds: AABB) -> Array[PackedVector3Array]:
	var edges: Array[PackedVector3Array] = []
	for a in 8:
		for b in range(a + 1, 8):
			if [1, 2, 4].has(a ^ b): # AABB.get_endpoint() counts z in bit 0, y in bit 1, x in bit 2: corners that differ in one bit share an edge
				edges.append(PackedVector3Array([bounds.get_endpoint(a), bounds.get_endpoint(b)]))
	return edges

func _has_box(drawn: Array[Dictionary], bounds: AABB, color: Color) -> bool:
	for edge in _box_edges(bounds):
		if not _has_line(drawn, edge[0], edge[1], color):
			return false
	return true

## An arrow as Lines.arrow draws it, from a marker's transform raised by `height`.
func _has_arrow(drawn: Array[Dictionary], placed: Transform3D, color: Color, height: float, length := 1.2) -> bool:
	var from := placed.origin + Vector3.UP * height
	var forward := -placed.basis.z
	var tip := from + forward * length
	return _has_line(drawn, from, tip, color) and _has_line(drawn, tip, tip - forward * 0.3 + placed.basis.x * 0.2, color) and _has_line(drawn, tip, tip - forward * 0.3 - placed.basis.x * 0.2, color)

func _has_cross(drawn: Array[Dictionary], center: Vector3, half: float, color: Color) -> bool:
	return _has_line(drawn, center - Vector3.RIGHT * half, center + Vector3.RIGHT * half, color) and _has_line(drawn, center - Vector3.UP * half, center + Vector3.UP * half, color) and _has_line(drawn, center - Vector3.BACK * half, center + Vector3.BACK * half, color)

#region Source rules

## The views read data and draw. They write nothing to the level, the chain or a plan, roll no dice and plan only a chain of their
## own; and the game code (the level, the doors, the chain, the HUD ...) does not know that they exist.
func test_views_read_only() -> Array[String]:
	var failures: Array[String] = []
	var writes := RegEx.create_from_string("\\b(level|plan|rejection|module)\\.[\\w.]*\\s*(=|\\+=|-=|\\*=|/=)[^=]")
	var changes := RegEx.create_from_string("\\blevel\\.(start|use_seed|_set_state|_spawn_room|_spawn_key|_on_\\w+|chain\\.next_plan|chain\\.clear_prop_spots|chain\\.plans\\.\\w+)\\(")
	var views_in_game := RegEx.create_from_string("\\b(Gizmos|Lines)\\b|generation_watch|toggle_gizmos|toggle_watch|step_generation")
	var game_files: Array[String] = ["level.gd", "door.gd", "room.gd", "key.gd", "player.gd", "hud.gd", "room_chain.gd", "debug_map.gd", "seed_entry.gd", "best_times.gd", "seeds.gd", "prop_set.gd", "room_weights.gd"]
	var views_seen := 0
	for step in STEPS:
		for file in VIEW_FILES:
			if not _step_has(step, file):
				continue
			views_seen += 1
			var source := "\n".join(_code_lines("res://steps/%s/%s" % [step, file]))
			for line in source.split("\n"):
				_expect(failures, writes.search(line) == null, "%s/%s writes to game data: %s" % [step, file, line])
				_expect(failures, changes.search(line) == null, "%s/%s changes the run: %s" % [step, file, line])
				_expect(failures, not line.contains("RandomNumberGenerator") and not line.contains("level.player") and not line.contains("level.rooms["), "%s/%s rolls dice or reaches into the player or a room: %s" % [step, file, line])
			var plans_a_chain := source.contains(".next_plan(")
			_expect(failures, plans_a_chain == (file == "generation_watch.gd"), "%s/%s: only the watch plans, and only a chain of its own" % [step, file])
			if file == "generation_watch.gd":
				_expect(failures, source.contains("chain = Chain.new(level.chain_seed, level.goal_room, level.lock_chance)") and not source.contains("= level.chain") and source.count("chain.next_plan()") == 1, "%s/%s does not plan a chain of its own from the level's seed" % [step, file])
	_expect(failures, views_seen == STEPS.size() * VIEW_FILES.size(), "found %d view scripts, expected %d (gizmos, lines and the watch in every step)" % [views_seen, STEPS.size() * VIEW_FILES.size()])
	for step in STEPS:
		for file in game_files:
			for line in _code_lines("res://steps/%s/%s" % [step, file]):
				_expect(failures, views_in_game.search(line) == null, "%s/%s knows about the debug views: %s" % [step, file, line])
	return failures

#endregion

#region Lines (step 1)

func test_lines() -> Array[String]:
	var failures: Array[String] = []
	for step in STEPS:
		var lines: MeshInstance3D = (load("res://steps/%s/lines.gd" % step) as GDScript).new()
		root.add_child(lines) # _ready makes the mesh and the material
		var immediate := lines.mesh as ImmediateMesh
		_expect(failures, immediate != null and lines.points.is_empty(), "%s: no ImmediateMesh after _ready" % step)
		var material := lines.material_override as StandardMaterial3D
		_expect(failures, material != null and material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and material.vertex_color_use_as_albedo and material.no_depth_test and material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "%s: the lines' material is not unlit, vertex-coloured, see-through-walls and alpha" % step)
		_expect(failures, lines.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s: lines cast shadows" % step)
		# Nothing drawn is no surface (a surface without a point is an engine error).
		lines.begin()
		lines.end()
		_expect(failures, immediate.get_surface_count() == 0, "%s: an empty frame left %d surfaces" % [step, immediate.get_surface_count()])
		# One line.
		lines.begin()
		lines.line(Vector3.ZERO, Vector3(1.0, 2.0, 3.0), Color.RED)
		_expect(failures, lines.points == PackedVector3Array([Vector3.ZERO, Vector3(1.0, 2.0, 3.0)]) and lines.colors == PackedColorArray([Color.RED, Color.RED]), "%s: line() collected %s %s" % [step, lines.points, lines.colors])
		lines.end()
		_expect(failures, immediate.get_surface_count() == 1 and immediate.get_aabb().is_equal_approx(AABB(Vector3.ZERO, Vector3(1.0, 2.0, 3.0))), "%s: one line is %d surfaces, its box is %s" % [step, immediate.get_surface_count(), immediate.get_aabb()])
		# A box: 12 edges, four of each length, every corner used three times.
		lines.begin()
		_expect(failures, lines.points.is_empty() and lines.colors.is_empty(), "%s: begin() keeps the lines of the last frame" % step)
		var bounds := AABB(Vector3(1.0, 2.0, 3.0), Vector3(4.0, 5.0, 6.0))
		lines.box(bounds, Color.GREEN)
		_expect(failures, lines.points.size() == 24 and lines.colors.size() == 24, "%s: a box is %d points, expected 24" % [step, lines.points.size()])
		var lengths := {4.0: 0, 5.0: 0, 6.0: 0}
		var corner_use := {}
		for i in range(0, lines.points.size(), 2):
			var length: float = lines.points[i].distance_to(lines.points[i + 1])
			for known: float in lengths:
				if is_equal_approx(length, known):
					lengths[known] += 1
			for point: Vector3 in [lines.points[i], lines.points[i + 1]]:
				corner_use[point] = corner_use.get(point, 0) + 1
		_expect(failures, lengths == {4.0: 4, 5.0: 4, 6.0: 4}, "%s: the edge lengths of a 4 x 5 x 6 box are %s" % [step, lengths])
		_expect(failures, corner_use.size() == 8 and corner_use.values().all(func(count: int) -> bool: return count == 3), "%s: the corners are %s" % [step, corner_use])
		_expect(failures, lines.points.size() == lines.colors.size() and lines.colors.count(Color.GREEN) == 24, "%s: the box colours" % step)
		for corner: Vector3 in corner_use:
			_expect(failures, bounds.grow(0.001).has_point(corner), "%s: a corner outside the box" % step)
		lines.end()
		_expect(failures, immediate.get_surface_count() == 1 and immediate.get_aabb().is_equal_approx(bounds), "%s: the box mesh has %d surfaces and the box %s, expected %s" % [step, immediate.get_surface_count(), immediate.get_aabb(), bounds])
		# With a thickness every line is a strip that is `thickness` pixels wide on the screen, at any distance and in either projection.
		lines.thickness = 3.0
		var camera := Camera3D.new()
		camera.fov = 75.0
		root.add_child(camera)
		camera.make_current()
		var screen_height := root.get_visible_rect().size.y
		for depth: float in [5.0, 20.0]:
			lines.begin()
			lines.line(Vector3(-1.0, 0.0, -depth), Vector3(1.0, 0.0, -depth), Color.WHITE)
			lines.end()
			var expected := 3.0 * 2.0 * depth * tan(deg_to_rad(75.0) / 2.0) / screen_height
			var strip := immediate.get_aabb()
			_expect(failures, immediate.get_surface_count() == 1 and absf(strip.size.y - expected) < expected * 0.01 and absf(strip.size.x - 2.0) < 0.001, "%s: a strip at %.0f m is %.4f m wide and %.3f long, expected %.4f and 2" % [step, depth, strip.size.y, strip.size.x, expected])
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 20.0
		lines.begin()
		lines.line(Vector3(-1.0, 0.0, -9.0), Vector3(1.0, 0.0, -9.0), Color.WHITE)
		lines.end()
		_expect(failures, absf(immediate.get_aabb().size.y - 3.0 * 20.0 / screen_height) < 0.0001, "%s: an orthographic strip is %.4f m wide, expected %.4f" % [step, immediate.get_aabb().size.y, 3.0 * 20.0 / screen_height])
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		lines.begin()
		lines.line(Vector3(0.0, 0.0, -3.0), Vector3(0.0, 0.0, -8.0), Color.WHITE) # straight away from the camera: no width to see
		lines.end()
		_expect(failures, immediate.get_surface_count() == 0, "%s: a line that points at the camera left %d surfaces" % [step, immediate.get_surface_count()])
		root.remove_child(camera)
		camera.free()
		lines.thickness = 0.0
		# Markers, from step 2.
		if lines.has_method("cross"):
			lines.begin()
			lines.cross(Vector3(1.0, 1.0, 1.0), 0.5, Color.GOLD)
			_expect(failures, lines.points.size() == 6, "%s: a cross is %d points" % [step, lines.points.size()])
			var mid := Vector3.ZERO
			for point: Vector3 in lines.points:
				mid += point / 6.0
				_expect(failures, is_equal_approx(point.distance_to(Vector3(1.0, 1.0, 1.0)), 0.5), "%s: a cross arm is not 0.5 long" % step)
			_expect(failures, mid.is_equal_approx(Vector3(1.0, 1.0, 1.0)), "%s: a cross is not centred on its point" % step)
			lines.begin()
			var turned := Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(2.0, 0.0, 0.0)) # -Z turned a quarter: it faces -X
			lines.arrow(turned, Color.GREEN, 2.0)
			_expect(failures, lines.points.size() == 6, "%s: an arrow is %d points" % [step, lines.points.size()])
			_expect(failures, lines.points[0].is_equal_approx(Vector3(2.0, 0.0, 0.0)) and lines.points[1].is_equal_approx(Vector3(0.0, 0.0, 0.0)), "%s: the shaft of an arrow goes %s to %s, expected 2 m along the way the marker faces" % [step, lines.points[0], lines.points[1]])
			_expect(failures, lines.points[2].is_equal_approx(lines.points[1]) and lines.points[4].is_equal_approx(lines.points[1]) and lines.points[3].x > 0.0 and lines.points[5].x > 0.0 and not lines.points[3].is_equal_approx(lines.points[5]), "%s: the head of the arrow does not start at the tip and point back" % step)
		root.remove_child(lines)
		lines.free()
		await process_frame
	return failures

#endregion

#region The plans do not change

## The run of every seed is the run of tutorial 06 in every step: the views and the record of rejected rooms move nothing.
func test_steps_plan_the_same() -> Array[String]:
	var failures: Array[String] = []
	var scripts: Array[GDScript] = []
	for step in STEPS:
		scripts.append(_chain_script(step))
	for chain_seed in range(1, PLAN_SEEDS + 1):
		if chain_seed % 20 == 0:
			await process_frame
		var base: Array = _plans_to_goal(scripts[0], chain_seed, 20).plans
		for i in range(1, scripts.size()):
			var other: Array = _plans_to_goal(scripts[i], chain_seed, 20).plans
			_expect(failures, _same_plans(base, other), "seed %d: %s plans another run than %s" % [chain_seed, STEPS[i], STEPS[0]])
		if failures.size() > 8:
			return failures
	return failures

#endregion

#region Gizmos (steps 1 and 2)

func test_gizmos_toggle(step: String) -> Array[String]:
	var failures: Array[String] = []
	_expect(failures, _physical_keys("toggle_gizmos") == ["F3"], "toggle_gizmos is %s, expected F3" % [_physical_keys("toggle_gizmos")])
	var main := await _load_step(step, true, {"goal_room": SHORT_GOAL})
	var level: Node3D = main.get_node("Level")
	var gizmos: Node3D = main.get_node("Gizmos")
	var lines: MeshInstance3D = gizmos.get_node("Lines")
	_expect(failures, not gizmos.visible and not lines.is_visible_in_tree() and lines.points.is_empty() and (lines.mesh as ImmediateMesh).get_surface_count() == 0, "the gizmos do not start hidden and empty")
	await _key(KEY_F3)
	await process_frame
	_expect(failures, gizmos.visible and lines.is_visible_in_tree() and lines.points.size() >= 24 and (lines.mesh as ImmediateMesh).get_surface_count() == 1, "F3 does not show the gizmos (%d points)" % lines.points.size())
	var shown: int = lines.points.size()
	await _key(KEY_F3)
	_expect(failures, not gizmos.visible and not lines.is_visible_in_tree(), "F3 does not hide the gizmos")
	level.typing = true # the seed box is up: its keys are not ours
	await _key(KEY_F3)
	_expect(failures, not gizmos.visible, "F3 reached the gizmos while the seed box was up")
	level.typing = false
	# Hidden, the node draws nothing, even when the level moves on.
	level._spawn_room(level.chain.next_plan())
	await _wait_physics(2)
	_expect(failures, lines.points.size() == shown, "a hidden gizmo node drew %d points more" % (lines.points.size() - shown))
	await _key(KEY_F3)
	await process_frame
	_expect(failures, lines.points.size() > shown, "shown again, the gizmos do not draw the new room")
	var hint: Label = main.get_node("HUD/Stats/DebugHint")
	_expect(failures, hint.text.begins_with("F3") and hint.get_parent() == main.get_node("HUD/Stats"), "the hint reads \"%s\"" % hint.text)
	await _unload(main)
	return failures

## One box per planned room: the plan's own bounds, in the colour of where the player is.
func test_gizmo_bounds(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step, true, {"goal_room": 8})
	var level: Node3D = main.get_node("Level")
	var gizmos: Node3D = main.get_node("Gizmos")
	var lines: MeshInstance3D = gizmos.get_node("Lines")
	await _key(KEY_F3)
	_fast_forward(true)
	var arrived := await _walk(level, Autopilot.new(level), 3, 0, Callable())
	_fast_forward(false)
	_expect(failures, arrived, "did not reach room 3")
	await _wait_physics(3)
	await process_frame
	var drawn := _drawn(lines)
	var plans: Array = level.chain.plans
	var current := 0
	var live := 0
	var removed := 0
	for plan: Object in plans:
		var expected: Color = gizmos.CURRENT_COLOR
		if plan.index == level.current:
			current += 1
		elif level.rooms.has(plan.index):
			expected = gizmos.LIVE_COLOR
			live += 1
		else:
			expected = gizmos.REMOVED_COLOR
			removed += 1
		_expect(failures, _has_box(drawn, plan.bounds, expected), "room %d: its bounds are not drawn in %s" % [plan.index, expected])
		_expect(failures, gizmos.color_of(plan) == expected, "room %d: color_of() says %s" % [plan.index, gizmos.color_of(plan)])
	_expect(failures, current == 1 and live >= 1 and removed >= 1, "the colours: %d current, %d live, %d removed rooms" % [current, live, removed])
	await _unload(main)
	return failures

## The markers are drawn where the room's scene has them, and the plan's choices are the bright ones.
func test_gizmo_markers(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step, true, {"goal_room": 7, "lock_chance": 1.0, "seed_text": "BLUE-FOX"})
	var level: Node3D = main.get_node("Level")
	var gizmos: Node3D = main.get_node("Gizmos")
	var lines: MeshInstance3D = gizmos.get_node("Lines")
	for i in 7:
		level._spawn_room(level.chain.next_plan())
	await _wait_physics(2)
	await _key(KEY_F3)
	await process_frame
	var drawn := _drawn(lines)
	var height: float = gizmos.ARROW_HEIGHT
	var keys := 0
	var held := 0
	var empty := 0
	for plan: Object in level.chain.plans:
		var room: Node3D = level.rooms[plan.index]
		var where := "room %d (%s)" % [plan.index, _room_name(_chain_script(step), plan.type)]
		_expect(failures, _has_arrow(drawn, room.entrance.global_transform, gizmos.ENTRANCE_COLOR, height), "%s: no entrance arrow at the room's entrance" % where)
		if plan.type == Chain.Type.GOAL:
			_expect(failures, room.exit == null, "%s: the goal room has an exit" % where)
		else:
			_expect(failures, _has_arrow(drawn, room.exit.global_transform, gizmos.EXIT_COLOR, height), "%s: no exit arrow at the room's exit" % where)
		for i: int in room.key_spots.size():
			var spot: Vector3 = room.key_spots[i].global_position
			if i == plan.key_spot:
				var key := room.get_node_or_null("Key") as Node3D
				_expect(failures, key != null and key.global_position.is_equal_approx(spot), "%s: the key does not lie at the spot the plan chose" % where)
				_expect(failures, _has_cross(drawn, spot + Vector3.UP * gizmos.KEY_CROSS_HEIGHT, gizmos.KEY_SIZE, gizmos.KEY_COLOR) and _has_line(drawn, spot, spot + Vector3.UP * gizmos.KEY_POST_HEIGHT, gizmos.KEY_COLOR), "%s: the key spot %d is not marked in gold" % [where, i])
				keys += 1
			else:
				var faint: Color = gizmos.KEY_COLOR
				faint.a = gizmos.UNUSED_ALPHA
				_expect(failures, _has_cross(drawn, spot + Vector3.UP * gizmos.SPOT_HEIGHT, gizmos.SPOT_SIZE, faint), "%s: the unused key spot %d is not marked faint" % [where, i])
		_expect(failures, (room.get_node_or_null("Key") != null) == (plan.key_spot >= 0), "%s: key spot %d and a key in the room: %s" % [where, plan.key_spot, room.get_node_or_null("Key")])
		var props := _props_in(room)
		var held_here := 0
		for i: int in room.prop_spots.size():
			var spot: Transform3D = room.prop_spots[i].global_transform
			var base: Vector3 = spot.origin + Vector3.UP * gizmos.SPOT_HEIGHT
			var color: Color = gizmos.PROP_COLOR
			if plan.props[i] != Chain.NO_PROP:
				held_here += 1
				held += 1
				_expect(failures, props.any(func(prop: Node3D) -> bool: return prop.global_position.is_equal_approx(spot.origin)), "%s: the plan holds a prop at spot %d, the room has none there" % [where, i])
			else:
				color.a = gizmos.UNUSED_ALPHA
				empty += 1
			_expect(failures, _has_cross(drawn, base, gizmos.SPOT_SIZE, color) and _has_line(drawn, base, base - spot.basis.z * gizmos.FACING_LENGTH, color), "%s: prop spot %d is not marked (%s)" % [where, i, "held" if plan.props[i] != Chain.NO_PROP else "empty"])
		_expect(failures, held_here == props.size(), "%s: %d props in the room, %d held in the plan" % [where, props.size(), held_here])
	var exit_lines := 0
	for entry in drawn:
		exit_lines += 1 if (entry.color as Color).is_equal_approx(gizmos.EXIT_COLOR) else 0
	_expect(failures, exit_lines == 3 * (level.chain.plans.size() - 1), "%d exit lines for %d rooms with an exit" % [exit_lines, level.chain.plans.size() - 1])
	_expect(failures, keys >= 2 and held >= 10 and empty >= 5, "the seed shows %d keys, %d held and %d empty prop spots: too little to check" % [keys, held, empty])
	await _unload(main)
	return failures

#endregion

#region The record of rejected rooms (step 3)

func _turns_back(plans: Array, placed: Transform3D, exit_local: Transform3D) -> bool:
	var heading := -(placed * exit_local).basis.z
	var to_start := ((plans[0].transform as Transform3D).origin - placed.origin).normalized()
	return heading.dot(Chain.START_HEADING) < -Chain.BACK_LIMIT or heading.dot(to_start) > Chain.BACK_LIMIT

## The index of the first of the first `count` plans that the box runs into, or -1.
func _first_overlap(plans: Array, count: int, box: AABB) -> int:
	var inner := box.grow(-Chain.SHRINK)
	for i in count:
		if inner.intersects(plans[i].bounds):
			return i
	return -1

## Checks every room type the chain turned down against the rules, worked out here a second time: where it would have stood,
## why it was turned down and whom it hit; and that the types it tried are the head of the order it drew.
func test_rejections_recorded() -> Array[String]:
	var failures: Array[String] = []
	for step: String in [STEPS[0], FINAL_STEP]:
		var script := _chain_script(step)
		var overlap := 0
		var heading := 0
		var rooms := 0
		var rooms_with_record := 0
		for chain_seed in range(1, REJECT_SEEDS + 1):
			if chain_seed % 25 == 0:
				await process_frame
			var chain := _new_chain(script, chain_seed, 20, LOCK_CHANCE)
			for room in 40:
				var before: int = chain.plans.size()
				var order: Array[int] = chain._weighted_types() # the order the chain is about to try: its dice are started from the seed and the room's number, drawing them changes nothing
				var goal_turn: bool = before > 0 and before == chain.goal_index
				var last: Object = chain.plans[-1] if before > 0 else null
				var plan: Object = chain.next_plan()
				var recorded: Array = plan.rejected
				var where := "%s seed %d room %d" % [step, chain_seed, plan.index]
				rooms += 1
				rooms_with_record += 1 if not recorded.is_empty() else 0
				if before == 0:
					_expect(failures, recorded.is_empty(), "%s: room 0 has a record" % where)
					continue
				var exit_point: Transform3D = last.transform * chain.module_of(last.type).exit
				var first_ordinary := 0
				if goal_turn:
					if plan.type == Chain.Type.GOAL:
						_expect(failures, recorded.is_empty(), "%s: the goal room fit, and has a record of %d rooms" % [where, recorded.size()])
						break
					first_ordinary = 1
				for r: Object in recorded:
					var module: Object = chain.module_of(r.type)
					var placed: Transform3D = exit_point * module.entrance.affine_inverse()
					_expect(failures, r.transform == placed and r.bounds == placed * module.bounds, "%s: a rejected %s is not where it would have stood" % [where, _room_name(script, r.type)])
					if r.reason == Chain.Reason.HEADING:
						heading += 1
						_expect(failures, r.hit == -1 and _turns_back(chain.plans, placed, module.exit), "%s: %s is recorded as turning back, but its heading is fine (hit %d)" % [where, _room_name(script, r.type), r.hit])
					else:
						overlap += 1
						var hit := _first_overlap(chain.plans, plan.index, r.bounds)
						_expect(failures, r.hit >= 0 and r.hit < plan.index and r.hit == hit, "%s: %s is recorded as running into room %d, it runs into room %d" % [where, _room_name(script, r.type), r.hit, hit])
						_expect(failures, not _turns_back(chain.plans, placed, module.exit), "%s: %s is recorded as an overlap, but it turns back first (the heading rule is tested first)" % [where, _room_name(script, r.type)])
				if goal_turn:
					_expect(failures, recorded.size() >= 1 and recorded[0].type == Chain.Type.GOAL and recorded[0].reason == Chain.Reason.OVERLAP, "%s: the goal room that did not fit is not the first record" % where)
				var tried: Array[int] = []
				for i in range(first_ordinary, recorded.size()):
					tried.append(recorded[i].type)
				var position := order.find(plan.type)
				_expect(failures, position >= 0, "%s: the room type %d was built, but it is not in the order (a fallback)" % [where, plan.type])
				var expected: Array[int] = []
				for i in position:
					expected.append(order[i])
				_expect(failures, tried == expected, "%s: tried %s, the order says %s" % [where, tried, expected])
				# The room that was built is the first that fits.
				var snapped_to_exit: Transform3D = exit_point * chain.module_of(plan.type).entrance.affine_inverse()
				_expect(failures, plan.transform == snapped_to_exit and not _turns_back(chain.plans, snapped_to_exit, chain.module_of(plan.type).exit) and _first_overlap(chain.plans, plan.index, plan.bounds) == -1, "%s: the room that was built does not fit" % where)
				if plan.type == Chain.Type.GOAL:
					break
			if failures.size() > 8:
				return failures
		print("        %s, seeds 1-%d: %d rooms, %d with a record; %d rooms turned down for their heading, %d for an overlap" % [step, REJECT_SEEDS, rooms, rooms_with_record, heading, overlap])
		_expect(failures, heading >= 300 and overlap >= 20 and rooms_with_record >= rooms * 0.1, "the record is too thin to prove anything: %d heading, %d overlap, %d rooms with a record of %d" % [heading, overlap, rooms_with_record, rooms])
	return failures

## A goal room that does not fit is the first record of the next plan: the chain waits one room. (The goal box is made huge by hand,
## as test_goal_waits does, because a goal room almost always fits.)
func test_rejections_goal() -> Array[String]:
	var failures: Array[String] = []
	for step: String in [STEPS[0], FINAL_STEP]:
		var script := _chain_script(step)
		for chain_seed: int in [42, 7, 313]:
			var chain := _new_chain(script, chain_seed, 6, 1.0)
			var real_bounds: AABB = chain._modules[Chain.Type.GOAL].bounds
			for i in 6:
				chain.next_plan()
			chain._modules[Chain.Type.GOAL].bounds = AABB(Vector3(-1000.0, -10.0, -1000.0), Vector3(2000.0, 20.0, 2000.0))
			var last: Object = chain.plans[-1]
			var exit_point: Transform3D = last.transform * chain.module_of(last.type).exit
			var plan: Object = chain.next_plan()
			var record: Object = plan.rejected[0] if not plan.rejected.is_empty() else null
			_expect(failures, record != null and record.type == Chain.Type.GOAL and record.reason == Chain.Reason.OVERLAP and record.hit == 0, "%s seed %d: the goal room that did not fit is not recorded as an overlap with room 0 (%s)" % [step, chain_seed, plan.rejected])
			if record != null:
				var placed: Transform3D = exit_point * chain.module_of(Chain.Type.GOAL).entrance.affine_inverse()
				_expect(failures, record.transform == placed and record.bounds == placed * chain.module_of(Chain.Type.GOAL).bounds, "%s seed %d: the goal room's record is not where it would have stood" % [step, chain_seed])
			_expect(failures, plan.type != Chain.Type.GOAL and plan.index == 6 and chain.goal_index == 7, "%s seed %d: the chain did not wait one room" % [step, chain_seed])
			chain._modules[Chain.Type.GOAL].bounds = real_bounds
			var goal: Object = chain.next_plan()
			_expect(failures, goal.type == Chain.Type.GOAL and goal.rejected.is_empty(), "%s seed %d: the goal room that fits has a record" % [step, chain_seed])
	return failures

## What a plan says about its rejected rooms, without the objects: for comparing two chains.
func _rejections_of(plan: Object) -> Array:
	var summary: Array = []
	var rejected: Variant = plan.get("rejected")
	if rejected == null:
		return summary
	for r: Object in rejected:
		summary.append([r.type, r.reason, r.transform, r.bounds, r.hit])
	return summary

func _same_rejections(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if _rejections_of(a[i]) != _rejections_of(b[i]):
			return false
	return true

#endregion

#region The flash of the rejected rooms (step 3)

func test_rejection_flash(step: String) -> Array[String]:
	var failures: Array[String] = []
	# A seed whose room 2 or later turned a room type down, so that the flash has something to show.
	var seed_number := 0
	var at := 0
	for candidate in range(1, 60):
		for plan: Object in _plans(_chain_script(step), candidate, 8):
			if not plan.rejected.is_empty():
				seed_number = candidate
				at = plan.index
				break
		if seed_number > 0:
			break
	_expect(failures, seed_number > 0, "no seed with a rejected room in its first rooms")
	var main := await _load_step(step, true, {"goal_room": 10, "chain_seed": seed_number})
	var level: Node3D = main.get_node("Level")
	var gizmos: Node3D = main.get_node("Gizmos")
	var lines: MeshInstance3D = gizmos.get_node("Lines")
	await _key(KEY_F3)
	var plan: Object = null
	for i in at:
		plan = level.chain.next_plan() # as a door asks for it
		_expect(failures, i + 1 < at or not plan.rejected.is_empty(), "the premise: room %d has a record" % at)
	await process_frame
	var flashes: Array = gizmos._flashes
	_expect(failures, flashes.size() == plan.rejected.size() and flashes.size() >= 1, "%d flashes for %d rejected rooms" % [flashes.size(), plan.rejected.size()])
	var red: Color = gizmos.REJECTED_COLOR
	var seconds: float = gizmos.FLASH_SECONDS
	_expect(failures, red.r > 0.9 and red.g < 0.2 and red.b < 0.2 and seconds > 1.0 and seconds <= 2.0, "the flash is not red or not a moment (%s, %.1f s)" % [red, seconds])
	var drawn := _drawn(lines)
	for i in flashes.size():
		var rejection: Object = plan.rejected[i]
		var alpha: float = 1.0 - (flashes[i].age as float) / seconds
		var shade := Color(red.r, red.g, red.b, alpha)
		_expect(failures, flashes[i].rejection == rejection and alpha > 0.5, "flash %d does not show rejection %d of the plan" % [i, i])
		_expect(failures, _has_box(drawn, rejection.bounds, shade), "the box of the rejected %s is not drawn in red" % _room_name(_chain_script(step), rejection.type))
		if rejection.reason == Chain.Reason.HEADING:
			var exit_marker: Transform3D = rejection.transform * level.chain.module_of(rejection.type).exit
			_expect(failures, _has_arrow(drawn, exit_marker, shade, gizmos.ARROW_HEIGHT), "the exit arrow of a room that turns back is not drawn")
	# The red fades: half the time, about half the alpha; then it is gone.
	var age_before: float = flashes[0].age
	gizmos._process(seconds / 2.0)
	var expected_alpha := 1.0 - (age_before + seconds / 2.0) / seconds
	var seen := false
	for entry in _drawn(lines):
		var shade: Color = entry.color
		if shade.r > 0.9 and shade.g < 0.2 and shade.b < 0.2:
			seen = true
			_expect(failures, absf(shade.a - expected_alpha) < 0.02, "half way through, the red has alpha %.2f, expected %.2f" % [shade.a, expected_alpha])
	_expect(failures, seen, "no red line half way through the flash")
	gizmos._process(seconds)
	_expect(failures, gizmos._flashes.is_empty(), "%d flashes left after %.1f s" % [gizmos._flashes.size(), seconds])
	var red_left := 0
	for entry in _drawn(lines):
		var shade: Color = entry.color
		red_left += 1 if shade.r > 0.9 and shade.g < 0.2 and shade.b < 0.2 else 0
	_expect(failures, red_left == 0, "%d red lines after the flash" % red_left)
	# A flash starts once per rejected room: the next frames find no new plan.
	await process_frame
	await process_frame
	_expect(failures, gizmos._flashes.is_empty(), "the same plan flashed again")
	# A room without a record flashes nothing, a restart starts the chain over.
	level.use_seed("1")
	await _wait_physics(2)
	await process_frame
	_expect(failures, gizmos._flashes.is_empty() and gizmos._chain == level.chain and gizmos._seen == 1, "after a restart the view has %d flashes and has seen %d plans" % [gizmos._flashes.size(), gizmos._seen])
	await _unload(main)
	return failures

#endregion

#region The watch (step 4)

## Asks for one room and waits until the watch has shown it. Returns false if it did not within `frames` frames.
## by_key: with a real press of Enter (four frames); without, the watch is sent the signal that Enter sends.
func _step_watch(watch: Node, by_key := false, frames := 200) -> bool:
	var shown: int = watch._shown
	if by_key:
		await _key(KEY_ENTER)
	else:
		watch.step_requested.emit()
	for i in frames:
		if watch._shown > shown:
			return true
		await process_frame
	return false

func _watch_done(watch: Node) -> bool:
	return watch.chain != null and not watch.chain.plans.is_empty() and watch.chain.plans[-1].type == Chain.Type.GOAL and watch._shown == watch.chain.plans.size()

func test_watch_steps(step: String) -> Array[String]:
	var failures: Array[String] = []
	_expect(failures, _physical_keys("toggle_watch") == ["F4"] and _physical_keys("step_generation") == ["Enter", "Kp Enter"], "toggle_watch is %s and step_generation %s, expected F4 and Enter" % [_physical_keys("toggle_watch"), _physical_keys("step_generation")])
	var main := await _load_step(step, true, {"goal_room": 12})
	var level: Node3D = main.get_node("Level")
	var watch: Node3D = main.get_node("Watch")
	watch.candidate_seconds = 0.0
	var player_camera: Camera3D = level.player.get_node("Head/Camera3D")
	_expect(failures, player_camera.current and not watch.watching and not watch.camera.current and not watch.screen.visible and not watch.lines.visible, "the watch is not asleep at the start")
	await _key(KEY_ENTER)
	_expect(failures, watch.chain == null and level.chain.plans.size() == 1, "Enter planned a room while nobody was watching")
	await _key(KEY_F4)
	_expect(failures, watch.watching and watch.camera.current and not player_camera.current and watch.screen.visible and watch.lines.visible, "F4 does not switch to the camera from above")
	_expect(failures, watch.chain != null and watch.chain.plans.is_empty() and watch.chain.get("_chain_seed") == level.chain_seed and watch.chain.goal_index == 12 and watch.chain.lock_chance == level.lock_chance and watch.chain != level.chain, "the watch's chain is not a chain of its own with the level's seed and settings")
	var look: Vector3 = -watch.camera.global_transform.basis.z
	_expect(failures, look.is_equal_approx(Vector3.DOWN) and watch.camera.projection == Camera3D.PROJECTION_ORTHOGONAL and (watch.camera.cull_mask & CEILING_LAYER) == 0 and (watch.camera.cull_mask & 1) != 0, "the camera does not look straight down, orthographic, past the ceilings")
	var aspect := root.get_visible_rect().size.aspect()
	var presses := 0
	while presses < 40 and not _watch_done(watch):
		var before: int = watch.chain.plans.size()
		var shown: bool = await _step_watch(watch, true)
		presses += 1
		_expect(failures, shown and watch.chain.plans.size() == before + 1, "press %d: %d plans after %d, one room per press" % [presses, watch.chain.plans.size(), before])
		_expect(failures, watch._shown == watch.chain.plans.size(), "press %d: %d rooms shown, %d planned" % [presses, watch._shown, watch.chain.plans.size()])
		# Everything that is shown is in the picture.
		var half := Vector2(watch.camera.size * aspect, watch.camera.size) / 2.0
		for i: int in watch._shown:
			var bounds: AABB = watch.chain.plans[i].bounds
			var middle := Vector2(watch.camera.position.x, watch.camera.position.z)
			_expect(failures, absf(bounds.position.x - middle.x) <= half.x and absf(bounds.end.x - middle.x) <= half.x and absf(bounds.position.z - middle.y) <= half.y and absf(bounds.end.z - middle.y) <= half.y, "press %d: room %d is outside the picture" % [presses, i])
		if failures.size() > 8:
			break
	_expect(failures, _watch_done(watch) and watch.chain.plans.size() == watch.chain.goal_index + 1, "the watch ended with %d plans and goal room %d" % [watch.chain.plans.size(), watch.chain.goal_index])
	_expect(failures, watch.report.text.contains("complete") and watch.report.text.contains("GOAL fits"), "the report does not say that the chain is complete: %s" % watch.report.text)
	var planned: int = watch.chain.plans.size()
	await _key(KEY_ENTER)
	await _wait_physics(3)
	_expect(failures, watch.chain.plans.size() == planned, "Enter planned a room after the goal room")
	# The level's own chain was never touched.
	_expect(failures, level.chain.plans.size() == 1 and level.state == STATE_READY and level.rooms.size() == 1, "the level's chain has %d plans after the watch" % level.chain.plans.size())
	# The seed box is up: its keys are its own.
	level.typing = true
	await _key(KEY_F4)
	_expect(failures, watch.watching, "F4 reached the watch while the seed box was up")
	level.typing = false
	await _key(KEY_F4)
	_expect(failures, not watch.watching and player_camera.current and not watch.camera.current and not watch.screen.visible and not watch.lines.visible, "F4 does not give the view back to the player")
	await _unload(main)
	return failures

## A coroutine cannot be stopped from outside: after R, N or a typed seed only the latest watch may plan, and leaving stops it.
func test_watch_restart(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step, true, {"goal_room": 12})
	var level: Node3D = main.get_node("Level")
	var watch: Node3D = main.get_node("Watch")
	watch.candidate_seconds = 0.0
	await _key(KEY_F4)
	for i in 3:
		await _step_watch(watch)
	_expect(failures, watch.chain.plans.size() == 3, "the premise: %d plans" % watch.chain.plans.size())
	# A restart while the coroutine waits for a key press: the watch starts again, and one press plans one room.
	var old_chain: RefCounted = watch.chain
	level.use_seed("7")
	await _wait_physics(2)
	_expect(failures, watch.chain != old_chain and watch.chain.plans.is_empty() and watch.chain.get("_chain_seed") == level.chain_seed and watch._shown == 0, "the restart did not start the watch again")
	await _step_watch(watch)
	_expect(failures, watch.chain.plans.size() == 1 and old_chain.plans.size() == 3, "after the restart one press planned %d rooms in the new chain and %d in the old one" % [watch.chain.plans.size(), old_chain.plans.size() - 3])
	await _step_watch(watch)
	_expect(failures, watch.chain.plans.size() == 2, "the second press planned %d rooms" % (watch.chain.plans.size() - 1))
	# A restart in the middle of a room: the old coroutine is still waiting for its timer.
	var seed_number := 0
	var at := 0
	for candidate in range(1, 60):
		for plan: Object in _plans(_chain_script(step), candidate, 8):
			if not plan.rejected.is_empty():
				seed_number = candidate
				at = plan.index
				break
		if seed_number > 0:
			break
	level.use_seed(str(seed_number))
	await _wait_physics(2)
	watch.candidate_seconds = 0.4
	for i in at:
		await _step_watch(watch)
	await _key(KEY_ENTER) # plans the room with the record: the coroutine waits for the first rejected room to leave
	_expect(failures, watch._rejection != null and watch._shown == at, "the premise: the rejected room is on the screen (%s), %d rooms shown, expected %d" % [watch._rejection, watch._shown, at])
	level.use_seed("42")
	await _wait_physics(2)
	var timer := create_timer(1.0)
	await timer.timeout # the old coroutine wakes up, finds another ticket and quits
	_expect(failures, watch._shown == 0 and watch._rejection == null and watch.chain.plans.is_empty(), "the old coroutine went on after a restart: %d rooms shown, rejection %s, %d plans" % [watch._shown, watch._rejection, watch.chain.plans.size()])
	# Leaving in the middle of a room stops the coroutine, too.
	level.use_seed(str(seed_number))
	await _wait_physics(2)
	for i in at:
		await _step_watch(watch)
	var count := [0]
	watch.room_planned.connect(func(_plan: Object) -> void: count[0] += 1)
	await _key(KEY_ENTER)
	_expect(failures, watch._rejection != null, "the premise: a rejected room is on the screen")
	await _key(KEY_F4)
	var timer_after_leaving := create_timer(1.0)
	await timer_after_leaving.timeout
	_expect(failures, count[0] == 0 and not watch.watching and watch._shown == at, "a room was shown after the watch was left (%d rooms, %d shown, expected %d)" % [count[0], watch._shown, at])
	await _unload(main)
	return failures

## Stepping through reaches the plans of the normal run, for many seeds; and the plans a walked level makes are the watch's plans.
func test_watch_same_plans(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step, true, {"goal_room": 20})
	var level: Node3D = main.get_node("Level")
	var watch: Node3D = main.get_node("Watch")
	watch.candidate_seconds = 0.0
	await _key(KEY_F4)
	var script := _chain_script(step)
	var total_presses := 0
	for chain_seed in range(1, WATCH_SEEDS + 1):
		level.use_seed(str(chain_seed))
		await _wait_physics(1)
		var presses := 0
		while presses < 60 and not _watch_done(watch):
			await _step_watch(watch)
			presses += 1
		total_presses += presses
		var normal: Array = _plans_to_goal(script, chain_seed, 20).plans
		_expect(failures, _same_plans(watch.chain.plans, normal) and _same_rejections(watch.chain.plans, normal), "seed %d: the stepped-through plans are not the plans of the normal run" % chain_seed)
		_expect(failures, presses == watch.chain.plans.size(), "seed %d: %d presses for %d rooms" % [chain_seed, presses, watch.chain.plans.size()])
		if failures.size() > 8:
			break
	print("        %s: %d seeds stepped through, %d presses, every plan and every rejected room the same as in the normal run" % [step, WATCH_SEEDS, total_presses])
	# The plans a walked level makes while the watch plans next to it.
	_fast_forward(true)
	for chain_seed: int in [42, 1000]:
		level.goal_room = 8
		level.use_seed(str(chain_seed))
		await _wait_physics(2)
		var presses := 0
		while presses < 60 and not _watch_done(watch):
			await _step_watch(watch)
			presses += 1
		var finished := await _walk_to_finish(level, Autopilot.new(level), 0, 60 * 60 * 6)
		_expect(failures, finished, "seed %d: the run did not finish" % chain_seed)
		_expect(failures, _same_plans(watch.chain.plans, level.chain.plans) and _same_rejections(watch.chain.plans, level.chain.plans), "seed %d: the plans of the walked level are not the watch's plans" % chain_seed)
	_fast_forward(false)
	await _unload(main)
	return failures

#endregion

#region All debug views on: the same run

func _run_snapshot(level: Node3D) -> Array:
	return [level.state, level.current, level.keys, level.run_time, level.player.global_position, level.player.rotation, level.rooms.keys(), level.chain.plans.size(), level.seed_text]

## Everything the plans say, rejected rooms included.
func _plan_summary(plans: Array) -> Array:
	var summary: Array = []
	for plan: Object in plans:
		summary.append([plan.index, plan.type, plan.transform, plan.bounds, plan.locked, plan.key_spot, plan.props, plan.get("lamp"), _rejections_of(plan)])
	return summary

## The autopilot walks one run of a seed for `ticks` physics ticks (or to the finish). views: every debug view of the step is on,
## and the watch (from step 4) plans a chain of its own next to the run: Enter is pressed every 0.2 s (a press while the watch
## shows a turned-down room is ignored, as for a player), the turned-down rooms stay 0.15 s.
func _view_run(step: String, chain_seed: int, views: bool, goal: int, ticks: int) -> Dictionary:
	var main := await _load_step(step, true, {"goal_room": goal, "chain_seed": chain_seed})
	var level: Node3D = main.get_node("Level")
	var lines: Node = main.get_node("Gizmos/Lines")
	var watch := main.get_node_or_null("Watch")
	if views:
		await _key(KEY_F3)
		if watch != null:
			watch.candidate_seconds = 0.15
			await _key(KEY_F4)
	await _wait_physics(30)
	var pilot := Autopilot.new(level)
	var snapshots: Array = []
	var state := {"ticks": 0}
	_fast_forward(true)
	await _drive(func() -> bool:
		pilot.physics_step()
		state["ticks"] += 1
		if views and watch != null and state["ticks"] % ENTER_EVERY_TICKS == 0:
			_press_now(KEY_ENTER)
		if state["ticks"] % 30 == 0:
			snapshots.append(_run_snapshot(level))
		return state["ticks"] >= ticks or level.state == STATE_FINISHED)
	pilot.release()
	_fast_forward(false)
	snapshots.append(_run_snapshot(level))
	var result := {
		snapshots = snapshots,
		plans = _plan_summary(level.chain.plans),
		points = lines.points.size(),
		watched = watch.chain.plans.size() if watch != null and watch.chain != null else 0,
		finished = level.state == STATE_FINISHED,
	}
	await _unload(main)
	return result

func test_views_change_nothing(step: String) -> Array[String]:
	var failures: Array[String] = []
	for chain_seed: int in [42, 1000]:
		var off := await _view_run(step, chain_seed, false, 8, 600)
		var on := await _view_run(step, chain_seed, true, 8, 600)
		_expect(failures, off.points == 0, "seed %d: the views drew while they were off" % chain_seed)
		_expect(failures, on.points > 0 and on.watched > 0, "seed %d: the views on did nothing (%d points, the watch planned %d rooms): the comparison would prove nothing" % [chain_seed, on.points, on.watched])
		var first_difference := -1
		for i in mini(off.snapshots.size(), on.snapshots.size()):
			if off.snapshots[i] != on.snapshots[i]:
				first_difference = i
				break
		_expect(failures, off.snapshots.size() == on.snapshots.size() and first_difference < 0, "seed %d: the run with the views differs after %d ticks: %s against %s" % [chain_seed, (first_difference + 1) * 30, off.snapshots[first_difference] if first_difference >= 0 else "", on.snapshots[first_difference] if first_difference >= 0 else ""])
		_expect(failures, off.plans == on.plans, "seed %d: the plans differ with the views on" % chain_seed)
		print("        %s, seed %d: %d snapshots equal, the player in room %d after %.1f s, %d line points drawn and %d rooms watched with the views on" % [step, chain_seed, on.snapshots.size(), on.snapshots[-1][1], on.snapshots[-1][3], on.points, on.watched])
	return failures

## The whole game with every view on: from the first door to the goal pad, the time, the keys and the plans are the ones of the run without.
func test_views_full_run() -> Array[String]:
	var failures: Array[String] = []
	for chain_seed: int in [42, 1000]:
		var off := await _view_run(FINAL_STEP, chain_seed, false, 8, 60 * 60 * 3)
		var on := await _view_run(FINAL_STEP, chain_seed, true, 8, 60 * 60 * 3)
		_expect(failures, off.finished and on.finished, "seed %d: a run did not finish (without %s, with %s)" % [chain_seed, off.finished, on.finished])
		_expect(failures, off.snapshots == on.snapshots and off.plans == on.plans, "seed %d: the run with every view on is not the run without: %s against %s" % [chain_seed, off.snapshots[-1], on.snapshots[-1]])
		_expect(failures, on.points > 0 and on.watched > 0, "seed %d: the views did nothing" % chain_seed)
		print("        seed %d: %d snapshots equal, the finish at %.2f s with the views on and off, the watch planned %d rooms next to it" % [chain_seed, on.snapshots.size(), on.snapshots[-1][3], on.watched])
	return failures

#endregion

#region Pinned seeds (step 5)

## The letters of a chain, worked out here without the check's code.
func _pin_types(chain: RefCounted) -> String:
	var types := ""
	for plan: Object in chain.plans:
		types += PIN_LETTERS[str(Chain.Type.find_key(plan.type))]
	return types

func test_pinned_holds() -> Array[String]:
	var failures: Array[String] = []
	var pinned: Dictionary = Pinned.PINNED
	_expect(failures, pinned.size() == 5, "%d seeds are pinned, expected 5" % pinned.size())
	var all_types := ""
	for step in STEPS:
		var script := _chain_script(step)
		for seed_text: String in pinned:
			var problems := Pinned.problems_of(script, seed_text)
			_expect(failures, problems.is_empty(), "%s, seed %s: %s" % [step, seed_text, problems])
	for seed_text: String in pinned:
		var number: int = _seeds_script(FINAL_STEP).parse(seed_text)
		var chain := _plans_to_goal(Chain, number, 20)
		var pins: Dictionary = pinned[seed_text]
		_expect(failures, _pin_types(chain) == pins.types and (pins.types as String).length() == chain.plans.size() and (pins.types as String).ends_with("G"), "seed %s: the pinned letters %s are not the chain's %s" % [seed_text, pins.types, _pin_types(chain)])
		var locks: Array[String] = []
		for plan: Object in chain.plans:
			if plan.locked:
				locks.append("%d:%d" % [plan.index, plan.key_spot])
		_expect(failures, str(locks) == str(pins.locks), "seed %s: the pinned locks %s are not the chain's %s" % [seed_text, pins.locks, locks])
		var end: Vector3 = chain.plans[-1].transform.origin
		_expect(failures, pins.end == "%.1f %.1f" % [end.x, end.z], "seed %s: the pinned end %s is not the chain's (%.1f %.1f)" % [seed_text, pins.end, end.x, end.z])
		all_types += pins.types
	# The pins cover what can go wrong: every room type, both turns, and locked rooms.
	for letter: String in ["S", "L", "<", ">", "W", "V", "G"]:
		_expect(failures, all_types.contains(letter), "no pinned seed has a room of type %s" % letter)
	return failures

## A chain script with the source of room_chain.gd changed in one place: an accident, written down.
var _accidents := {}
func _accident(label: String, old: String, replacement: String) -> GDScript:
	if _accidents.has(label):
		return _accidents[label]
	var source := FileAccess.get_file_as_string("res://steps/%s/room_chain.gd" % FINAL_STEP)
	if source.count(old) != 1:
		return null
	var script := GDScript.new()
	script.source_code = source.replace(old, replacement)
	script.resource_path = "res://steps/%s/room_chain_accident_%d.gd" % [FINAL_STEP, _accidents.size()] # the chain's preloads are relative to this path
	if script.reload() != OK:
		return null
	_accidents[label] = script
	return script

## The pinned seeds fail on a deliberate change, loudly: the seed and the first room that moved are named. The unchanged chain passes (test_pinned_holds).
func test_pinned_fails() -> Array[String]:
	var failures: Array[String] = []
	var accidents := {
		"the vault spacing taken out (accidental_change.gd)": load("res://steps/%s/accidental_change.gd" % FINAL_STEP) as GDScript,
		"the heading rule loosened (BACK_LIMIT 0.05 to 0.5)": _accident("heading", "const BACK_LIMIT := 0.05", "const BACK_LIMIT := 0.5"),
		"the lock roll and the key spot swapped": _accident("swap", "\tvar roll := _content_rng.randf()\n\tvar spot := _content_rng.randi_range(0, spot_count - 1)\n", "\tvar spot := _content_rng.randi_range(0, spot_count - 1)\n\tvar roll := _content_rng.randf()\n"),
		"one die more in the lock roll of room 5": _chain_with_extra_dice(FINAL_STEP, 5, 1),
		"the room weights are no longer read (every room type weighs 1)": _accident("weights", "weights.append(ROOM_WEIGHTS.weight_of(type))", "weights.append(1.0)"),
	}
	for label: String in accidents:
		var script: GDScript = accidents[label]
		_expect(failures, script != null, "%s: the accident does not compile or its anchor is gone" % label)
		if script == null:
			continue
		var failing := 0
		var message := ""
		for seed_text: String in Pinned.PINNED:
			var problems := Pinned.problems_of(script, seed_text)
			if not problems.is_empty():
				failing += 1
				if message.is_empty():
					message = problems[0]
		print("        %s: %d of %d pinned seeds fail, e.g. \"%s\"" % [label, failing, Pinned.PINNED.size(), message])
		_expect(failures, failing >= 1, "%s: no pinned seed notices" % label)
		_expect(failures, message.contains("pinned") or message.contains("locks") or message.contains("stands at"), "%s: the message does not say what moved: %s" % [label, message])
	# A room that moved is named by its number and its type.
	var named := false
	var sentence := RegEx.create_from_string("^room \\d+: pinned [A-Z_]+, got [A-Z_]+$")
	for seed_text: String in Pinned.PINNED:
		for line in Pinned.problems_of(accidents["the heading rule loosened (BACK_LIMIT 0.05 to 0.5)"], seed_text):
			named = named or sentence.search(line) != null
	_expect(failures, named, "no difference is named by room and type")
	return failures

func test_pinned_command() -> Array[String]:
	var failures: Array[String] = []
	var executable := OS.get_executable_path()
	if executable.is_empty():
		_skip("check_pinned.gd from the command line", "no executable path")
		return failures
	var base: Array[String] = ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://steps/%s/check_pinned.gd" % FINAL_STEP]
	var output: Array = []
	var code := OS.execute(executable, base, output, true)
	var text := ""
	for chunk: String in output:
		text += str(chunk)
	_expect(failures, code == 0 and text.contains("PINNED OK") and text.contains("as pinned") and not text.contains("FAILED"), "the pinned seeds, unchanged: exit code %d, output: %s" % [code, text.substr(0, 500)])
	for seed_text: String in Pinned.PINNED:
		_expect(failures, text.contains("seed %-10s" % seed_text), "no row for seed %s" % seed_text)
	output = []
	var accident_arguments := base.duplicate()
	accident_arguments.append_array(["--", "--chain=res://steps/%s/accidental_change.gd" % FINAL_STEP])
	code = OS.execute(executable, accident_arguments, output, true)
	text = ""
	for chunk: String in output:
		text += str(chunk)
	_expect(failures, code == 1 and text.contains("PINNED FAILED") and text.contains(": pinned ") and text.contains("--print"), "the accident: exit code %d, output: %s" % [code, text.substr(0, 700)])
	# --print writes the pins the file holds, ready to paste.
	output = []
	var print_arguments := base.duplicate()
	print_arguments.append_array(["--", "--print"])
	code = OS.execute(executable, print_arguments, output, true)
	text = ""
	for chunk: String in output:
		text += str(chunk)
	_expect(failures, code == 0 and text.contains("const PINNED := {"), "--print: exit code %d" % code)
	for seed_text: String in Pinned.PINNED:
		var pins: Dictionary = Pinned.PINNED[seed_text]
		_expect(failures, text.contains("\"%s\": {types = \"%s\", locks = %s, end = \"%s\"}" % [seed_text, pins.types, pins.locks, pins.end]), "--print does not print the pins of seed %s as they are in the file" % seed_text)
	return failures

#endregion

#endregion

#region Helpers

func _report(test_name: String, failures: Array[String]) -> void:
	var script_errors := _script_errors.count - _script_errors_reported
	_script_errors_reported = _script_errors.count
	if script_errors > 0: # the test stopped at the failing line and the engine returned an empty array, which would read as a pass
		failures.insert(0, "the test stopped with a script error: see the log")
	if failures.is_empty():
		_passed += 1
		print("PASS  ", test_name)
		return
	_failed += 1
	print("FAIL  ", test_name)
	for message: String in failures.slice(0, 8):
		print("        ", message)
	if failures.size() > 8:
		print("        ... and %d more" % (failures.size() - 8))

func _skip(test_name: String, reason: String) -> void:
	_skipped += 1
	print("SKIP  ", test_name)
	print("        ", reason)

func _expect(failures: Array[String], condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

## Instances a step's main scene. By default it waits until the CSG shapes have built their collision.
## props are set on the Level before it enters the tree (goal_room, seed_text, save_path ...; "chain_seed" is the
## seed number of steps 0, and in the others the text of its digits).
## A level that saves gets a fresh temporary save file unless props bring one.
func _load_step(step: String, settle := true, props := {}) -> Node:
	var scene: PackedScene = load("res://steps/%s/main.tscn" % step)
	var main := scene.instantiate()
	var level := main.get_node_or_null("Level")
	if level != null:
		if level.get("save_path") != null and not props.has("save_path"):
			level.set("save_path", _fresh_save_path())
		for key: String in props:
			if key == "chain_seed" and level.get("seed_text") != null:
				level.set("seed_text", str(props[key])) # from step 1 on the seed is a text; a number is the text of its digits
			else:
				level.set(key, props[key])
	root.add_child(main)
	if settle:
		await _wait_physics(10)
	return main

func _unload(main: Node) -> void:
	for action: String in ["move_forward", "move_back", "move_left", "move_right", "look_left", "look_right", "look_up", "look_down", "jump"]:
		Input.action_release(action)
	root.remove_child(main)
	main.free()
	await process_frame

## A path in the temporary test folder that no file exists at.
func _fresh_save_path() -> String:
	_save_counter += 1
	DirAccess.make_dir_recursive_absolute(_save_dir)
	return _save_dir.path_join("best_times_%d.json" % _save_counter)

func _write_file(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func _wipe_save_dir() -> void:
	if not DirAccess.dir_exists_absolute(_save_dir):
		return
	for file in DirAccess.get_files_at(_save_dir):
		DirAccess.remove_absolute(_save_dir.path_join(file))
	DirAccess.remove_absolute(_save_dir)

## Runs the simulation faster than real time with the same 1/60 s steps: the engine ticks
## SPEED_UP times as often and hands out SPEED_UP times the delta of each (smaller) tick.
func _fast_forward(on: bool) -> void:
	Engine.physics_ticks_per_second = 60 * (SPEED_UP if on else 1)
	Engine.time_scale = float(SPEED_UP) if on else 1.0

## Sets the size of the game window (headless: the root viewport) and waits for the layout.
## The engine ignores the first size it is given after start-up, so it asks again.
func _set_screen(size: Vector2i) -> void:
	for attempt in 3:
		root.size = size
		for i in 3:
			await process_frame
		if root.size == size:
			return

func _wait_physics(frames: int) -> void:
	for i in frames:
		await physics_frame

func _action(action: StringName) -> void:
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	await process_frame

#endregion
