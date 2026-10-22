extends Node
## Plays the game through the real input actions and records it: stills as PNG files, or, in Movie Maker mode, a short
## walkthrough. Needs a window and the Forward+ renderer (the fog and the GI of this tutorial exist only there); the
## video footage comes from tools/shots.gd, this is the quick check: the same three moments of seed 141 in every step
## (room 0 from where the player starts, the vault, the wide room), so the steps compare picture by picture; the vault on
## each quality level of step 5; and the squint test on every picture: blurred, does the door still stand out from the
## wall around it by its value? The text captures (gi_options.gd as a terminal shows it) need no window: a headless run
## writes them, too.
##
## Stills (PNG files, the squint table, plus the mouse and clipboard checks that only work in a window):
##   godot --path godot/09-light-and-atmosphere res://tools/capture.tscn -- --out=/abs/dir
## Movie (the finished game, seed 141 to the goal pad; convert the .avi with ffmpeg afterwards):
##   godot --path godot/09-light-and-atmosphere --write-movie /abs/file.avi --fixed-fps 30 res://tools/capture.tscn
## --out defaults to docs/captures. `-- --mode=stills` or `-- --mode=movie` overrides the mode.
## Headless dry run (no pictures but the text captures; the walks and every check still run):
##   godot --headless --fixed-fps 60 --path godot/09-light-and-atmosphere res://tools/capture.tscn
## The exit code is 1 if a screenshot could not be saved or a check failed.
##
## Saves: every level gets its own temporary best_times file (OS temp dir, wiped first), so the
## real best times of the machine are never read or written.

const Autopilot := preload("autopilot.gd")

const SETTLE_TICKS := 60 ## Physics ticks to let a fresh scene build its shapes, shadows, fog and GI.
const SHORT_GOAL := 6 ## The goal room of the quick runs.
const STATE_FINISHED := 2
const SEED := "141" ## Seed 141: rooms 0 to 6 are every room type once (straight, left turn, vault, wide, long, right turn, goal), no lock.
const BOX_SEED := "BLUE-FOX" ## What the window checks type into the seed box.
const STEPS: Array[String] = ["step_00_start", "step_01_room_lights", "step_02_world_environment", "step_03_volumetric_fog", "step_04_runtime_gi", "step_05_quality_switch"]
const FINAL_STEP := "step_05_quality_switch"
const MOMENTS: Array[int] = [0, 2, 3] ## The rooms of the stills: room 0 (straight), room 2 (the vault), room 3 (the wide room).
const SETTLE_IN_ROOM := 45 ## Physics ticks after the player enters a room before its picture.
const SQUINT_SCALE := 8 ## The squint: the picture shrunk to an eighth and back, the details gone.
const SQUINT_CONTRAST := 0.2 ## The door's value must differ from the wall around it by this much (Weber contrast), from step 1 on (the step with the exit light).
const BLACK := 0.05 ## A pixel darker than this (luminance, 0 to 1) is crushed black.
const MOST_BLACK := 0.01 ## The share of the picture below its HUD rows that may be crushed black (no crushed black over areas).

var _out_dir := ""
var _failures := 0
var _main: Node
var _level: Node3D
var _save_count := 0
var _squint: Array[String] = ["picture                                      door  wall  contrast  door hue  black"]

func _ready() -> void:
	_run()

func _run() -> void:
	await get_tree().process_frame # the scene tree is busy setting up in _ready
	_out_dir = _read_argument("--out", ProjectSettings.globalize_path("res://docs/captures"))
	var movie := OS.has_feature("movie")
	match _read_argument("--mode", ""):
		"movie":
			movie = true
		"stills":
			movie = false
	if movie:
		await _movie()
	else:
		DirAccess.make_dir_recursive_absolute(_out_dir)
		await _stills()
		await _window_checks()
	_release_inputs()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_clean_saves()
	print("capture finished, %d problems" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)

#region Stills

func _stills() -> void:
	# Step 4's choice as a terminal shows it: the engine's GI options, and step 3, which has none.
	_save_command_output("04-gi-options.txt", "res://steps/step_04_runtime_gi/gi_options.gd", [], 0, "GI OK")
	_save_command_output("04-gi-options-step-3.txt", "res://steps/step_04_runtime_gi/gi_options.gd", ["--scene=res://steps/step_03_volumetric_fog/main.tscn"], 1, "GI FAILED")

	# The same three moments of seed 141 in every step: the steps side by side.
	for i in STEPS.size():
		await _walk_and_shoot(STEPS[i], "%02d-%s" % [i, STEPS[i].substr(8).replace("_", "-")], -1)
	# Step 5: the vault on every quality level, from the same spot.
	for quality in 3:
		await _walk_and_shoot(FINAL_STEP, "05-quality-%s" % ["low", "medium", "high"][quality], quality, [2])
	if DisplayServer.get_name() != "headless":
		_save_text("squint.txt", "\n".join(_squint))

	# The real thing: the finished game, seed 141, the whole run.
	_load(FINAL_STEP, SHORT_GOAL)
	_level.seed_text = SEED
	_level.start()
	var finisher := Autopilot.new(_level)
	await _drive_until(finisher, func() -> bool: return _level.state == STATE_FINISHED, 150 * 60)
	finisher.release()
	await _ticks(15)
	await _save("05-finished")
	await _unload()

## Walks seed 141 with the autopilot and takes a picture SETTLE_IN_ROOM ticks after the player enters each room of `rooms`
## (room 0: after the settle, before the walk). quality: the level of step 5's switch, -1 for the step as it is.
func _walk_and_shoot(step: String, prefix: String, quality: int, rooms: Array[int] = MOMENTS) -> void:
	_load(step, SHORT_GOAL)
	_level.seed_text = SEED
	_level.start()
	if quality >= 0:
		_main.get_node("Quality").call("apply", quality)
	await _ticks(SETTLE_TICKS)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE # a released mouse turns nothing: no stray motion of the real mouse tilts the view
	if rooms.has(0):
		await _shoot(prefix + "-room-0", step)
	var pilot := Autopilot.new(_level)
	for room in rooms:
		if room == 0:
			continue
		await _drive_until(pilot, func() -> bool: return _level.current >= room)
		await _drive_ticks(pilot, SETTLE_IN_ROOM)
		pilot.release()
		await _ticks(30) # the player stops; the fog and the GI settle
		await _shoot("%s-room-%d" % [prefix, room], step)
	pilot.release()
	await _unload()

## A picture, and the squint test on it: the door the player looks at, against the wall around it, both blurred.
func _shoot(file_name: String, step: String) -> void:
	await _save(file_name)
	if DisplayServer.get_name() == "headless":
		return
	var door: Node3D = _level.rooms[_level.current].door
	if door == null:
		return
	var camera := get_viewport().get_camera_3d()
	var leaf := door.get_node("Hinge/Leaf").find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var box := leaf.global_transform * leaf.mesh.get_aabb()
	var rect := Rect2()
	for corner in 8:
		var point := box.get_endpoint(corner)
		if camera.is_position_behind(point):
			return
		var screen := camera.unproject_position(point)
		rect = Rect2(screen, Vector2.ZERO) if corner == 0 else rect.expand(screen)
	var image := get_viewport().get_texture().get_image()
	var size := image.get_size()
	var dark := 0
	var total := 0
	for y in range(floori(size.y / 3.0), size.y, 8): # below the map and the stats: only the room
		for x in range(0, size.x, 8):
			total += 1
			dark += 1 if image.get_pixel(x, y).get_luminance() < BLACK else 0
	var black := dark / float(total)
	image.resize(floori(size.x / float(SQUINT_SCALE)), floori(size.y / float(SQUINT_SCALE)), Image.INTERPOLATE_TRILINEAR)
	image.resize(size.x, size.y, Image.INTERPOLATE_BILINEAR)
	var inner := rect.grow_individual(-rect.size.x * 0.2, -rect.size.y * 0.15, -rect.size.x * 0.2, -rect.size.y * 0.15)
	var outer := rect.grow_individual(rect.size.x * 0.6, 0.0, rect.size.x * 0.6, -rect.size.y * 0.1)
	var door_color := _mean(image, inner, Rect2())
	var wall_color := _mean(image, outer, rect.grow(rect.size.x * 0.1))
	var door_value := door_color.get_luminance()
	var wall_value := wall_color.get_luminance()
	var contrast := absf(door_value - wall_value) / maxf(wall_value, 0.001)
	_squint.append("%-44s %.2f  %.2f  %8.2f  %.3f     %.1f%%" % [file_name, door_value, wall_value, contrast, door_color.h, black * 100.0])
	_check(black <= MOST_BLACK, "%s: %.1f%% of the room is crushed black, at most %.0f%% allowed" % [file_name, black * 100.0, MOST_BLACK * 100.0])
	if STEPS.find(step) >= 1:
		_check(contrast >= SQUINT_CONTRAST, "%s: the squint test: the door (%.2f) against the wall (%.2f), contrast %.2f, expected at least %.2f" % [file_name, door_value, wall_value, contrast, SQUINT_CONTRAST])
		_check(door_color.h > 0.03 and door_color.h < 0.17 and door_color.s > 0.3, "%s: the door does not read orange when blurred (hue %.3f, saturation %.2f)" % [file_name, door_color.h, door_color.s])

## The mean colour of the pixels inside `area` and not inside `hole` (an empty hole: none left out).
func _mean(image: Image, area: Rect2, hole: Rect2) -> Color:
	var bounds := Rect2i(area).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	var sum := Color(0, 0, 0, 0)
	var count := 0
	for y in range(bounds.position.y, bounds.end.y, 2):
		for x in range(bounds.position.x, bounds.end.x, 2):
			if hole.has_area() and hole.has_point(Vector2(x, y)):
				continue
			var pixel := image.get_pixel(x, y)
			sum += Color(pixel.r, pixel.g, pixel.b, 0)
			count += 1
	return Color(sum.r / maxi(count, 1), sum.g / maxi(count, 1), sum.b / maxi(count, 1))

## A text file for the captures folder: no window needed.
func _save_text(file_name: String, text: String) -> void:
	var file := FileAccess.open(_out_dir.path_join(file_name), FileAccess.WRITE)
	if file == null:
		printerr("FAIL  could not write ", file_name)
		_failures += 1
		return
	file.store_string(text.strip_edges() + "\n")
	file.close()
	print("SAVED ", _out_dir.path_join(file_name))

## A check as a terminal shows it. Needs the executable; the file gets the exit code, too. Text needs no window, so the file is
## written in a headless run, too.
func _save_command_output(file_name: String, script: String, arguments: Array[String], expected_code: int, expected_text: String) -> void:
	var output: Array = []
	var command: Array[String] = ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", script]
	if not arguments.is_empty():
		command.append("--")
		command.append_array(arguments)
	var code := OS.execute(OS.get_executable_path(), command, output, true)
	var text := "$ godot --headless --path godot/09-light-and-atmosphere -s %s%s\n" % [script.trim_prefix("res://"), (" -- " + " ".join(arguments)) if not arguments.is_empty() else ""]
	for chunk: String in output:
		text += str(chunk)
	text += "exit code %d\n" % code
	_check(code == expected_code and text.contains(expected_text), "%s finishes with \"%s\" and exit code %d (got %d)" % [script.get_file(), expected_text, expected_code, code])
	_save_text(file_name, text)

## What only a window can show: the captured mouse and the clipboard. Esc releases the mouse, a click takes it again, the seed box
## gives it to the pointer and back, C puts the seed on the clipboard, the finish gives the mouse back and R takes it again.
func _window_checks() -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP  window checks: the headless display server never reports a captured mouse, and has no clipboard")
		return
	_load(FINAL_STEP, SHORT_GOAL)
	var player: CharacterBody3D = _level.player
	var head: Node3D = player.get_node("Head")
	await _ticks(SETTLE_TICKS)
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "the mouse is captured at the start")

	var yaw := player.rotation.y
	await _mouse_motion(Vector2(100.0, 0.0))
	_check(is_equal_approx(player.rotation.y - yaw, -0.2), "100 px to the right turn the body by -0.2 rad (got %.3f)" % (player.rotation.y - yaw))
	_check(is_zero_approx(head.rotation.x), "yaw does not tilt the head")

	await _press("ui_cancel")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Esc releases the mouse")
	yaw = player.rotation.y
	await _mouse_motion(Vector2(100.0, 0.0))
	_check(player.rotation.y == yaw, "the view stays put while the mouse is released")
	await _click()
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "a click captures the mouse again")

	# The seed box: T gives the pointer to the box and stops the view, Esc and Enter give the mouse back.
	await _press_key(KEY_T)
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "T releases the mouse for the seed box")
	yaw = player.rotation.y
	await _mouse_motion(Vector2(100.0, 0.0))
	_check(player.rotation.y == yaw, "the view stays put while the seed box is up")
	await _press_key(KEY_ESCAPE)
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not (_main.get_node("HUD/SeedEntry") as Control).visible, "Esc closes the box and captures the mouse")
	await _mouse_motion(Vector2(100.0, 0.0))
	_check(player.rotation.y != yaw, "the view turns again after the box")
	await _press_key(KEY_T)
	await _type(BOX_SEED)
	await _press_key(KEY_ENTER)
	await _ticks(10)
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and _level.seed_text == BOX_SEED, "Enter starts the run with the typed seed and captures the mouse")

	# C puts the seed on the clipboard: paste it into the box and it is the same seed.
	DisplayServer.clipboard_set("something else")
	await _press("copy_seed")
	_check(DisplayServer.clipboard_get() == BOX_SEED, "C puts \"%s\" on the clipboard, it holds \"%s\"" % [BOX_SEED, DisplayServer.clipboard_get()])
	await _press_key(KEY_T)
	var line: LineEdit = _main.get_node("HUD/SeedEntry/Rows/Line")
	line.text = ""
	line.insert_text_at_caret(DisplayServer.clipboard_get())
	_check(line.text == BOX_SEED, "the box takes the copied seed (\"%s\")" % line.text)
	await _press_key(KEY_ESCAPE)

	# The finish releases the mouse, and a click does not take it back: the run is over.
	var pilot := Autopilot.new(_level)
	await _drive_until(pilot, func() -> bool: return _level.state == STATE_FINISHED)
	pilot.release()
	await _ticks(10)
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "the finish releases the mouse")
	yaw = player.rotation.y
	await _mouse_motion(Vector2(100.0, 0.0))
	_check(player.rotation.y == yaw, "the view stays put after the finish")
	await _click()
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "a click after the finish does not capture the mouse")
	await _press_key(KEY_T)
	await _press_key(KEY_ESCAPE)
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "closing the box after the finish does not capture the mouse")

	# R: a new run, the mouse is the player's again.
	await _press("regenerate")
	await _ticks(5)
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "R captures the mouse again")
	yaw = player.rotation.y
	await _mouse_motion(Vector2(100.0, 0.0))
	_check(player.rotation.y != yaw, "the view turns after R")
	await _unload()

func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS  ", message)
	else:
		printerr("FAIL  ", message)
		_failures += 1

#endregion
#region Movie

## The finished game, seed 141 from room 0 to the goal pad: every room type once, each lamp in its tint.
func _movie() -> void:
	_load(FINAL_STEP, SHORT_GOAL)
	_level.seed_text = SEED
	_level.start()
	await _ticks(60) # room 0
	var pilot := Autopilot.new(_level)
	await _drive_until(pilot, func() -> bool: return _level.state == STATE_FINISHED)
	pilot.release()
	await _ticks(90) # Finished!
	await _unload()

#endregion

#region Helpers

func _read_argument(name_with_dashes: String, fallback: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(name_with_dashes + "="):
			return argument.trim_prefix(name_with_dashes + "=")
	return fallback

## Loads a step. goal: the level's goal_room (0 = its own). save_path: its best times file (default: a fresh temporary one).
func _load(step: String, goal := 0, save_path := "") -> void:
	_main = (load("res://steps/%s/main.tscn" % step) as PackedScene).instantiate()
	_level = _main.get_node("Level")
	if goal > 0:
		_level.set("goal_room", goal)
	if _level.get("save_path") != null:
		_level.set("save_path", save_path if not save_path.is_empty() else _fresh_save_path())
	# Under the root, not under this node: this node keeps running while the tree is paused.
	get_tree().root.add_child(_main)

func _unload() -> void:
	_release_inputs()
	get_tree().root.remove_child(_main)
	_main.queue_free()
	await get_tree().process_frame

func _release_inputs() -> void:
	for action: String in ["move_forward", "move_back", "look_left", "look_right", "look_up", "look_down", "jump"]:
		Input.action_release(action)

func _ticks(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

## The autopilot walks for count physics ticks.
func _drive_ticks(pilot: RefCounted, count: int) -> void:
	for i in count:
		pilot.physics_step()
		await get_tree().physics_frame

## The autopilot walks until the condition holds (or for 60 s, or `limit` ticks, at most).
func _drive_until(pilot: RefCounted, condition: Callable, limit := 3600) -> void:
	for i in limit:
		if condition.call():
			return
		pilot.physics_step()
		await get_tree().physics_frame
	printerr("FAIL  the walk did not reach its goal in %.0f s" % (limit / 60.0))
	_failures += 1

## Presses and releases an input action as an event, like a key press.
func _press(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await _ticks(2)
	event = InputEventAction.new()
	event.action = action
	event.pressed = false
	Input.parse_input_event(event)
	await _ticks(2)

func _click() -> void:
	for pressed: bool in [true, false]: # a click is a press and a release: a held button changes how a text box takes the focus
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		Input.parse_input_event(click)
		await _ticks(2)

## Presses and releases a key through the input system, like a keyboard does.
func _press_key(code: Key, unicode := 0) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.unicode = unicode
		event.pressed = pressed
		Input.parse_input_event(event)
		await _ticks(2)

## Types a text into whatever has the focus: every character is a key press that carries it.
func _type(text: String) -> void:
	for character in text:
		await _press_key(character.to_upper().unicode_at(0) as Key, character.unicode_at(0))

func _mouse_motion(relative: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.relative = relative
	Input.parse_input_event(motion)
	await _ticks(2)

func _save(file_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP  %s.png (headless: nothing is rendered)" % file_name)
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := _out_dir.path_join(file_name + ".png")
	if image == null or image.is_empty() or image.save_png(path) != OK:
		printerr("FAIL  could not save ", path)
		_failures += 1
		return
	print("SAVED ", path, " ", image.get_size())

func _save_dir() -> String:
	return OS.get_temp_dir().path_join("phaix-godot-09-capture")

## A path in the temporary folder that no file exists at.
func _fresh_save_path() -> String:
	_save_count += 1
	DirAccess.make_dir_recursive_absolute(_save_dir())
	var path := _save_dir().path_join("best_times_%d.json" % _save_count)
	for suffix: String in ["", ".bad", ".tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)
	return path

func _clean_saves() -> void:
	if not DirAccess.dir_exists_absolute(_save_dir()):
		return
	for file in DirAccess.get_files_at(_save_dir()):
		DirAccess.remove_absolute(_save_dir().path_join(file))
	DirAccess.remove_absolute(_save_dir())

#endregion
