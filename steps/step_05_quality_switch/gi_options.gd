extends SceneTree
## Which global illumination works for rooms that are built while the game runs? Indirect light that has to be baked
## is only usable if the running game can bake it, and only worth it if that bake fits between two frames. This small
## script asks the engine (like check_grid.gd, a script with an exit code) and checks what main.tscn uses:
## - LightmapGI: baked, and the engine has no bake() to call from a running game: lightmaps are baked in the editor;
## - VoxelGI: baked, and the running game can call bake(), but the game waits until it is done;
## - SDFGI: nothing to bake: the Environment builds it around the camera, from whatever geometry is there.
##
##   godot --headless --path godot/09-light-and-atmosphere -s res://steps/step_05_quality_switch/gi_options.gd
##
## Option: `-- --scene=res://path/to/main.tscn` checks that scene. The exit code is 0 if the scene lights its rooms with
## a GI the running game can build, 1 if it uses none or one that only the editor can bake.

const MAIN := "res://steps/step_05_quality_switch/main.tscn"

func _initialize() -> void:
	var path := MAIN
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--scene="):
			path = argument.trim_prefix("--scene=")
	var lines := report(path)
	for line in lines:
		print(line)
	quit(0 if lines[-1].begins_with("GI OK") else 1)

## The three options as the engine offers them, then the one the scene uses. The last line says GI OK or GI FAILED.
static func report(path: String) -> Array[String]:
	var lines: Array[String] = ["option      baked   bake() in the running game"]
	for option: String in ["LightmapGI", "VoxelGI"]:
		lines.append("%-11s yes     %s" % [option, "yes" if ClassDB.class_has_method(option, "bake") else "no (editor only)"])
	lines.append("%-11s no      nothing to bake (Environment.sdfgi_enabled)" % "SDFGI")

	var main := (load(path) as PackedScene).instantiate()
	var used: Array[String] = []
	var world := main.find_children("*", "WorldEnvironment", true, false)
	if not world.is_empty() and (world[0] as WorldEnvironment).environment.sdfgi_enabled:
		used.append("SDFGI")
	for option: String in ["VoxelGI", "LightmapGI"]:
		if not main.find_children("*", option, true, false).is_empty():
			used.append(option)
	main.free()

	if used.is_empty():
		lines.append("GI FAILED: %s uses no global illumination" % path.get_file())
	elif used.has("LightmapGI"):
		lines.append("GI FAILED: %s uses LightmapGI, which only the editor can bake: the rooms do not exist yet" % path.get_file())
	else:
		lines.append("GI OK: %s uses %s, built while the game runs" % [path.get_file(), ", ".join(used)])
	return lines
