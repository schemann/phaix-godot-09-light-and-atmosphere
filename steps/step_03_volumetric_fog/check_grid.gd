extends SceneTree
## The grid check of the rooms built from the kit, like check_solvable.gd a small script with an exit code.
## For every room type of the chain it reads the room's scene and checks what a modular kit promises
## (every piece snaps on the grid, no gap, no overlapping wall):
## - every piece stands on the snap grid, turned in quarter turns only;
## - the floor tiles and the ceiling tiles cover the room exactly: no gap, no tile on another;
## - every wall edge is closed exactly once by walls, doorways and corners, and every piece faces into the room;
## - there is a doorway at the entrance and at the exit, and no doorway anywhere else;
## - nothing but kit pieces in the shell.
## It also prints the tile schedule: how many of each piece every room type takes.
##
##   godot --headless --path godot/09-light-and-atmosphere -s res://steps/step_03_volumetric_fog/check_grid.gd
##
## Option: `-- --room=res://path/to/room.tscn` checks that one scene. The exit code is 0 if every room
## passes and 1 if any fails.

const Chain := preload("room_chain.gd")

const SNAP := 0.5 ## Metres. Every pivot of the kit lands on this grid.
const CELL := 2.0 ## Metres. A floor or ceiling tile, a wall, a doorway, a corner arm.
const CEILING_HEIGHT := 3.0
const TOLERANCE := 0.001
const KIT := "/kit/"
const FLOOR := "kit_floor_2x2"
const CEILING := "ceiling_tile"
const WALL_2M := "kit_wall_2m"
const WALL_1M := "kit_wall_1m"
const DOORWAY := "kit_doorway_2m"
const CORNER := "kit_corner"
const FIXTURES: Array[String] = ["kit_pillar", "kit_plinth_3x3", "kit_goal_pad"]
const PIECE_ORDER: Array[String] = [FLOOR, CEILING, WALL_2M, WALL_1M, DOORWAY, CORNER, "kit_pillar", "kit_plinth_3x3", "kit_goal_pad"]
const ROOM_NAMES: Array[String] = ["straight", "long", "turn_left", "turn_right", "wide", "vault", "goal"] ## In the order of Chain.Type.

func _initialize() -> void:
	var paths: Array[String] = []
	for scene in Chain.SCENES:
		paths.append(scene.resource_path)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--room="):
			paths = [argument.trim_prefix("--room=")]
	var lines := report(paths)
	for line in lines:
		print(line)
	quit(0 if lines[-1].begins_with("GRID OK") else 1)

## The tile schedule and the problems of these room scenes. The last line says GRID OK or GRID FAILED.
static func report(paths: Array[String]) -> Array[String]:
	var counts: Array[Dictionary] = []
	var names: Array[String] = []
	var problems: Array[String] = []
	for path in paths:
		var room := (load(path) as PackedScene).instantiate() as Node3D
		var room_name := path.get_file().get_basename()
		names.append(room_name.trim_prefix("room_"))
		counts.append(schedule(room))
		problems.append_array(problems_of(room, room_name))
		room.free()
	var lines: Array[String] = ["tile schedule: kit pieces per room"]
	var header := "%-16s" % "piece"
	for name in names:
		header += " %10s" % name
	lines.append(header)
	for piece in PIECE_ORDER:
		var row := "%-16s" % piece
		for count in counts:
			row += " %10d" % int(count.get(piece, 0))
		lines.append(row)
	for problem in problems:
		lines.append("  " + problem)
	if problems.is_empty():
		lines.append("GRID OK: %d rooms, every piece on the grid, no gap, no overlap" % paths.size())
	else:
		lines.append("GRID FAILED: %d problems" % problems.size())
	return lines

## How many of each kit piece the room takes.
static func schedule(room: Node3D) -> Dictionary:
	var counts := {}
	for piece in pieces_of(room):
		var kind := kind_of(piece)
		counts[kind] = int(counts.get(kind, 0)) + 1
	return counts

## Every kit piece of the room: the instances in the shell and in the ceiling, the ones of the scene and the ones a running
## room has added (the wall that seals room 0 has no owner).
static func pieces_of(room: Node3D) -> Array[Node3D]:
	var found: Array[Node3D] = []
	for group: String in ["Shell", "Ceiling"]:
		var parent := room.get_node_or_null(group)
		if parent == null:
			continue
		for node in parent.find_children("*", "Node3D", true, false):
			if (node.owner == room or node.owner == null) and not node.scene_file_path.is_empty():
				found.append(node as Node3D)
	return found

## The piece's name in the kit: the file it is an instance of.
static func kind_of(piece: Node3D) -> String:
	return piece.scene_file_path.get_file().get_basename()

## Where the piece stands in the room (its parents are plain groups, they may be moved too).
static func placed(room: Node3D, piece: Node3D) -> Transform3D:
	var transform := piece.transform
	var parent := piece.get_parent()
	while parent != room:
		transform = (parent as Node3D).transform * transform
		parent = parent.get_parent()
	return transform

## What is wrong with the room's kit pieces. An empty list: the room passes.
static func problems_of(room: Node3D, room_name: String) -> Array[String]:
	var problems: Array[String] = []
	var inside := room.get_node("Inside/CollisionShape3D") as CollisionShape3D
	var size := (inside.shape as BoxShape3D).size
	var half := Vector2(size.x, size.z) / 2.0
	var floor_tiles: Array[Rect2] = []
	var ceiling_tiles: Array[Rect2] = []
	var edges := {"far": [], "near": [], "left": [], "right": []} # edge -> [from, to, piece name]
	var doorways: Array[Vector3] = []
	for node in room.get_node("Shell").find_children("*", "", true, false):
		if node.owner == room and node.scene_file_path.is_empty() and not node.get_class() == "Node3D":
			problems.append("%s: %s is no kit piece (a %s in the shell)" % [room_name, room.get_path_to(node), node.get_class()])
	for piece in pieces_of(room):
		var kind := kind_of(piece)
		var where := placed(room, piece)
		var label := "%s: %s" % [room_name, room.get_path_to(piece)]
		if not piece.scene_file_path.contains(KIT) and kind != CEILING:
			problems.append("%s is no kit piece (%s)" % [label, piece.scene_file_path])
			continue
		if not _on_grid(where):
			problems.append("%s is off the grid: at %s, turned %s" % [label, _point_text(where.origin), _turn_text(where.basis)])
			continue
		match kind:
			FLOOR, CEILING:
				var height := 0.0 if kind == FLOOR else CEILING_HEIGHT
				if absf(where.origin.y - height) > TOLERANCE:
					problems.append("%s is at a height of %.2f m, not %.2f" % [label, where.origin.y, height])
				var tile := Rect2(Vector2(where.origin.x, where.origin.z) - Vector2.ONE * CELL / 2.0, Vector2.ONE * CELL)
				(floor_tiles if kind == FLOOR else ceiling_tiles).append(tile)
			WALL_2M, WALL_1M, DOORWAY:
				var length := CELL / 2.0 if kind == WALL_1M else CELL
				_add_segment(problems, edges, label, where, Vector3(-length / 2.0, 0.0, 0.0), Vector3(length / 2.0, 0.0, 0.0), half)
				if kind == DOORWAY:
					doorways.append(where.origin)
			CORNER:
				_add_segment(problems, edges, label, where, Vector3.ZERO, Vector3(CELL, 0.0, 0.0), half)
				_add_segment(problems, edges, label, where, Vector3.ZERO, Vector3(0.0, 0.0, CELL), half)
			_:
				if not FIXTURES.has(kind):
					problems.append("%s is a %s, which the grid check does not know" % [label, kind])
				elif absf(where.origin.x) >= half.x or absf(where.origin.z) >= half.y:
					problems.append("%s stands outside the room" % label)
	problems.append_array(_tiles_cover(room_name + ": the floor", floor_tiles, half))
	problems.append_array(_tiles_cover(room_name + ": the ceiling", ceiling_tiles, half))
	for edge: String in edges:
		problems.append_array(_edge_closed("%s: the %s wall" % [room_name, edge], edges[edge], half.y if edge == "left" or edge == "right" else half.x))
	for marker_name: String in ["Entrance", "Exit"]:
		var marker := room.get_node_or_null(marker_name) as Marker3D
		if marker == null:
			continue
		var found := -1
		for i in doorways.size():
			if doorways[i].distance_to(marker.position) < TOLERANCE:
				found = i
		if found < 0:
			problems.append("%s: no doorway at the %s (%s)" % [room_name, marker_name.to_lower(), _point_text(marker.position)])
		else:
			doorways.remove_at(found)
	for extra in doorways:
		problems.append("%s: a doorway at %s leads nowhere (no entrance or exit there)" % [room_name, _point_text(extra)])
	return problems

## A piece on the grid: its pivot on the snap grid, on the floor or at the ceiling, turned about Y in quarter turns.
static func _on_grid(where: Transform3D) -> bool:
	for axis in 3:
		var nearest := snappedf(where.origin[axis], SNAP)
		if absf(where.origin[axis] - nearest) > TOLERANCE:
			return false
		for row in 3:
			var value := where.basis[axis][row]
			if absf(value - roundf(value)) > TOLERANCE:
				return false
	return where.basis.y.is_equal_approx(Vector3.UP)

## A stretch of wall from a to b (in the piece's own space) on an edge of the room. It must lie on the edge and
## the piece must face into the room there.
static func _add_segment(problems: Array[String], edges: Dictionary, label: String, where: Transform3D, a: Vector3, b: Vector3, half: Vector2) -> void:
	var from := where * a
	var to := where * b
	var inward := where.basis.z if a.x != b.x else where.basis.x # the room side of this stretch
	var edge := ""
	if absf(from.z + half.y) < TOLERANCE and absf(to.z + half.y) < TOLERANCE:
		edge = "far"
	elif absf(from.z - half.y) < TOLERANCE and absf(to.z - half.y) < TOLERANCE:
		edge = "near"
	elif absf(from.x + half.x) < TOLERANCE and absf(to.x + half.x) < TOLERANCE:
		edge = "left"
	elif absf(from.x - half.x) < TOLERANCE and absf(to.x - half.x) < TOLERANCE:
		edge = "right"
	if edge.is_empty():
		problems.append("%s is not on an edge of the room (%s to %s)" % [label, _point_text(from), _point_text(to)])
		return
	var into_room := {"far": Vector3.BACK, "near": Vector3.FORWARD, "left": Vector3.RIGHT, "right": Vector3.LEFT}
	if not inward.is_equal_approx(into_room[edge]):
		problems.append("%s faces out of the room" % label)
	var along_x := edge == "far" or edge == "near"
	var s := from.x if along_x else from.z
	var e := to.x if along_x else to.z
	(edges[edge] as Array).append([minf(s, e), maxf(s, e), label.get_slice(": ", 1)])

## The stretches of one edge, from -half to +half: every metre once.
static func _edge_closed(label: String, stretches: Array, half: float) -> Array[String]:
	var problems: Array[String] = []
	stretches.sort_custom(func(p: Array, q: Array) -> bool: return float(p[0]) < float(q[0]))
	var reached := -half
	var last := "the corner"
	for stretch: Array in stretches:
		var start := float(stretch[0])
		if start > reached + TOLERANCE:
			problems.append("%s has a gap from %.1f to %.1f m" % [label, reached, start])
		elif start < reached - TOLERANCE:
			problems.append("%s: %s and %s overlap from %.1f to %.1f m" % [label, last, stretch[2], start, minf(reached, float(stretch[1]))])
		reached = maxf(reached, float(stretch[1]))
		last = stretch[2]
	if reached < half - TOLERANCE:
		problems.append("%s has a gap from %.1f to %.1f m" % [label, reached, half])
	return problems

## Tiles that cover the room's footprint exactly: each inside, none on another, together the whole area.
static func _tiles_cover(label: String, tiles: Array[Rect2], half: Vector2) -> Array[String]:
	var problems: Array[String] = []
	var footprint := Rect2(-half, half * 2.0).grow(TOLERANCE)
	var area := 0.0
	for i in tiles.size():
		if not footprint.encloses(tiles[i]):
			problems.append("%s: a tile at %s reaches out of the room" % [label, tiles[i].get_center()])
		area += tiles[i].get_area()
		for j in range(i + 1, tiles.size()):
			var both := tiles[i].intersection(tiles[j])
			if both.size.x > TOLERANCE and both.size.y > TOLERANCE:
				problems.append("%s: the tiles at %s and %s lie on each other" % [label, tiles[i].get_center(), tiles[j].get_center()])
	var room_area := half.x * half.y * 4.0
	if absf(area - room_area) > TOLERANCE and problems.is_empty():
		problems.append("%s has a gap: %.0f of %.0f m2 covered" % [label, area, room_area])
	return problems

static func _point_text(point: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [point.x, point.y, point.z]

static func _turn_text(basis: Basis) -> String:
	return "%.0f degrees" % rad_to_deg(basis.get_euler().y)
