extends SceneTree
## The kit's import gate: every piece measured the way Godot imported it, written into a table and checked
## against the rules of the kit. A piece goes into a room only when it passes. Run it headless:
##   godot --headless --path godot/09-light-and-atmosphere -s res://steps/step_02_world_environment/check_kit.gd
## Exit code 0 when every piece is what the table says, 1 otherwise.
##
## What is checked for each piece:
## - scale and pivot: its box, measured from the pivot, is the one in PIECES (to the millimetre);
## - facing: that box says it, too: a wall grows from its pivot to +Z, into the room;
## - normals: every face points out of the piece (no inward face), and its normals agree with its winding;
## - material: every surface uses the project's material of its name;
## - texel density: one UV unit is one metre on every face;
## - colliders: the boxes named -colonly in Blender came in as StaticBody3D on the world layer, each one the box
##   COLLIDERS says, and together they fill the piece: no overlap, the volume of the mesh. The door leaf has none.

const KIT_FOLDER := "kit" ## Next to this script.

const CELL := 2.0 ## Metres: one cell of the room grid.
const WALL_HEIGHT := 3.0
const WALL_THICKNESS := 0.2
const SLAB := 0.2 ## Floor and ceiling.
const DOOR_WIDTH := 1.6
const DOOR_HEIGHT := 2.4
const LEAF_THICKNESS := 0.1
const PILLAR_RADIUS := 0.5
const PLINTH := 3.0
const PLINTH_HEIGHT := 0.12
const TOLERANCE := 0.001 ## A millimetre.

## Every piece of the kit: its box measured from the pivot, the material of its surfaces and the pivot rule.
## The numbers come from the constants above, so pieces that meet agree: the doorway is as high and as thick as
## the wall, a corner arm is one cell long, the floor and the ceiling are one slab.
const PIECES: Dictionary[String, Dictionary] = {
	"kit_floor_2x2": {box = AABB(Vector3(-CELL / 2.0, -SLAB, -CELL / 2.0), Vector3(CELL, SLAB, CELL)), material = "floor", pivot = "middle of the walking face"},
	"kit_ceiling_2x2": {box = AABB(Vector3(-CELL / 2.0, 0.0, -CELL / 2.0), Vector3(CELL, SLAB, CELL)), material = "ceiling", pivot = "middle of the face below"},
	"kit_wall_2m": {box = AABB(Vector3(-CELL / 2.0, 0.0, 0.0), Vector3(CELL, WALL_HEIGHT, WALL_THICKNESS)), material = "wall", pivot = "room edge, middle, on the floor"},
	"kit_wall_1m": {box = AABB(Vector3(-CELL / 4.0, 0.0, 0.0), Vector3(CELL / 2.0, WALL_HEIGHT, WALL_THICKNESS)), material = "wall", pivot = "room edge, middle, on the floor"},
	"kit_doorway_2m": {box = AABB(Vector3(-CELL / 2.0, 0.0, 0.0), Vector3(CELL, WALL_HEIGHT, WALL_THICKNESS)), material = "wall", pivot = "room edge, middle, on the floor"},
	"kit_corner": {box = AABB(Vector3.ZERO, Vector3(CELL, WALL_HEIGHT, CELL)), material = "wall", pivot = "the room's corner"},
	"kit_door_leaf": {box = AABB(Vector3(-DOOR_WIDTH, 0.0, -LEAF_THICKNESS / 2.0), Vector3(DOOR_WIDTH, DOOR_HEIGHT, LEAF_THICKNESS)), material = "door", pivot = "the hinge, on the floor"},
	"kit_pillar": {box = AABB(Vector3(-PILLAR_RADIUS, 0.0, -PILLAR_RADIUS), Vector3(PILLAR_RADIUS * 2.0, WALL_HEIGHT, PILLAR_RADIUS * 2.0)), material = "wall", pivot = "middle of the foot"},
	"kit_plinth_3x3": {box = AABB(Vector3(-PLINTH / 2.0, 0.0, -PLINTH / 2.0), Vector3(PLINTH, PLINTH_HEIGHT, PLINTH)), material = "wall", pivot = "middle of the foot"},
	"kit_goal_pad": {box = AABB(Vector3(-PLINTH / 2.0, 0.0, -PLINTH / 2.0), Vector3(PLINTH, PLINTH_HEIGHT, PLINTH)), material = "goal", pivot = "middle of the foot"},
}
## The collider boxes of every piece, measured from the pivot. They only touch, never overlap.
## The pillar's collider is a copy of its 16 sides (MESH), the door leaf has none: it moves, its collider is a
## shape on the door's hinge body.
const MESH := "mesh"
const COLLIDERS: Dictionary[String, Variant] = {
	"kit_floor_2x2": [AABB(Vector3(-CELL / 2.0, -SLAB, -CELL / 2.0), Vector3(CELL, SLAB, CELL))],
	"kit_ceiling_2x2": [AABB(Vector3(-CELL / 2.0, 0.0, -CELL / 2.0), Vector3(CELL, SLAB, CELL))],
	"kit_wall_2m": [AABB(Vector3(-CELL / 2.0, 0.0, 0.0), Vector3(CELL, WALL_HEIGHT, WALL_THICKNESS))],
	"kit_wall_1m": [AABB(Vector3(-CELL / 4.0, 0.0, 0.0), Vector3(CELL / 2.0, WALL_HEIGHT, WALL_THICKNESS))],
	"kit_doorway_2m": [ # the two jambs and the lintel between them
		AABB(Vector3(-CELL / 2.0, 0.0, 0.0), Vector3((CELL - DOOR_WIDTH) / 2.0, WALL_HEIGHT, WALL_THICKNESS)),
		AABB(Vector3(DOOR_WIDTH / 2.0, 0.0, 0.0), Vector3((CELL - DOOR_WIDTH) / 2.0, WALL_HEIGHT, WALL_THICKNESS)),
		AABB(Vector3(-DOOR_WIDTH / 2.0, DOOR_HEIGHT, 0.0), Vector3(DOOR_WIDTH, WALL_HEIGHT - DOOR_HEIGHT, WALL_THICKNESS)),
	],
	"kit_corner": [ # the arm along the edge, and the arm into the room that butts against it
		AABB(Vector3.ZERO, Vector3(CELL, WALL_HEIGHT, WALL_THICKNESS)),
		AABB(Vector3(0.0, 0.0, WALL_THICKNESS), Vector3(WALL_THICKNESS, WALL_HEIGHT, CELL - WALL_THICKNESS)),
	],
	"kit_door_leaf": [],
	"kit_pillar": MESH,
	"kit_plinth_3x3": [AABB(Vector3(-PLINTH / 2.0, 0.0, -PLINTH / 2.0), Vector3(PLINTH, PLINTH_HEIGHT, PLINTH))],
	"kit_goal_pad": [AABB(Vector3(-PLINTH / 2.0, 0.0, -PLINTH / 2.0), Vector3(PLINTH, PLINTH_HEIGHT, PLINTH))],
}
const WORLD_LAYER := 1 ## The physics layer of everything the player stands on or bumps into.

## The doorway's hole: no face may lie in it.
const OPENING := AABB(Vector3(-DOOR_WIDTH / 2.0, 0.0, 0.0), Vector3(DOOR_WIDTH, DOOR_HEIGHT, WALL_THICKNESS))
const PROBE := 0.01 ## Metres in front of and behind a face, for the inside test.
const RAY := Vector3(0.123, 0.456, 0.789) ## A slanted way out of the piece, so a ray never runs along an edge.

func _initialize() -> void:
	var folder := (get_script() as Script).resource_path.get_base_dir().path_join(KIT_FOLDER)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--kit="):
			folder = argument.trim_prefix("--kit=")
	var lines := report(folder)
	for line in lines:
		print(line)
	quit(0 if lines[-1].begins_with("KIT OK") else 1)

## The table of the kit in this folder and what is wrong with it. The last line says KIT OK or KIT FAILED.
static func report(folder: String) -> Array[String]:
	var lines: Array[String] = ["kit in %s (%d pieces)" % [folder, PIECES.size()]]
	lines.append("%-16s %-20s %-21s %5s  %-8s %6s  %-8s  %s" % ["piece", "size x y z (m)", "from the pivot (m)", "tris", "material", "inward", "UV per m", "colliders"])
	var problems: Array[String] = []
	for piece: String in PIECES:
		var path := folder.path_join(piece + ".glb")
		if not ResourceLoader.exists(path):
			problems.append("%s: missing" % piece)
			continue
		var measured := measure(load(path) as PackedScene)
		var box: AABB = measured.box
		lines.append("%-16s %-20s %-21s %5d  %-8s %6d  %-8.2f  %s" % [piece, "%.2f x %.2f x %.2f" % [box.size.x, box.size.y, box.size.z],
			"%.2f %.2f %.2f" % [box.position.x, box.position.y, box.position.z], measured.triangles, measured.material, measured.inward, measured.texel,
			collider_text(piece, measured)])
		problems.append_array(check(piece, measured))
	for problem in problems:
		lines.append("  " + problem)
	if problems.is_empty():
		lines.append("KIT OK: %d pieces as the table says" % PIECES.size())
	else:
		lines.append("KIT FAILED: %d problems" % problems.size())
	return lines

## What one imported piece is: its box, triangles, material, faces that point inward, and UV units per metre
## (the smallest and largest edge ratio), measured in the space of the piece's root (its pivot).
static func measure(scene: PackedScene) -> Dictionary:
	var piece_root := scene.instantiate() as Node3D
	var triangles: Array[PackedVector3Array] = []
	var normals: Array[PackedVector3Array] = []
	var uvs: Array[PackedVector2Array] = []
	var materials: Array[String] = []
	for node in piece_root.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		var to_root := _to_root(piece_root, instance)
		var mesh := instance.mesh
		for surface in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface)
			materials.append(material.resource_path.get_file().get_basename() if material != null and material.resource_path.begins_with("res://materials/") else "?")
			var arrays := mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var vertex_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var vertex_uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for i in range(0, indices.size(), 3):
				var corners := PackedVector3Array()
				var corner_normals := PackedVector3Array()
				var corner_uvs := PackedVector2Array()
				for k in 3:
					corners.append(to_root * vertices[indices[i + k]])
					corner_normals.append((to_root.basis * vertex_normals[indices[i + k]]).normalized())
					corner_uvs.append(vertex_uvs[indices[i + k]])
				triangles.append(corners)
				normals.append(corner_normals)
				uvs.append(corner_uvs)
	var colliders: Array[Dictionary] = []
	for node in piece_root.find_children("*", "CollisionShape3D", true, false):
		var shape_node := node as CollisionShape3D
		var body := shape_node.get_parent() as CollisionObject3D
		var to_root := _to_root(piece_root, shape_node)
		var faces := PackedVector3Array()
		if shape_node.shape is ConcavePolygonShape3D:
			for point in (shape_node.shape as ConcavePolygonShape3D).get_faces():
				faces.append(to_root * point)
		colliders.append({body = body.get_class() if body != null else "none", layer = body.collision_layer if body != null else 0,
			shape = shape_node.shape.get_class(), faces = faces})
	piece_root.free()
	var box := AABB(triangles[0][0], Vector3.ZERO)
	var inward := 0
	var texel_low := INF
	var texel_high := 0.0
	for t in triangles.size():
		var corners := triangles[t]
		for corner in corners:
			box = box.expand(corner)
		var outward := face_normal(corners)
		var middle := (corners[0] + corners[1] + corners[2]) / 3.0
		var agrees := true
		for corner_normal in normals[t]:
			agrees = agrees and corner_normal.dot(outward) > 0.0
		if not agrees or _inside(middle + outward * PROBE, triangles) or not _inside(middle - outward * PROBE, triangles):
			inward += 1
		for k in 3:
			var length := corners[k].distance_to(corners[(k + 1) % 3])
			if length > TOLERANCE:
				var ratio := uvs[t][k].distance_to(uvs[t][(k + 1) % 3]) / length
				texel_low = minf(texel_low, ratio)
				texel_high = maxf(texel_high, ratio)
	var names: Array[String] = []
	for material in materials:
		if not names.has(material):
			names.append(material)
	return {box = box, triangles = triangles.size(), faces = triangles, material = ",".join(names), inward = inward,
		texel = texel_low if absf(texel_low - 1.0) > absf(texel_high - 1.0) else texel_high, colliders = colliders}

## The colliders of a measured piece, the way the table shows them: "1 box", "3 boxes", "mesh", "none".
static func collider_text(piece: String, measured: Dictionary) -> String:
	var colliders: Array[Dictionary] = measured.colliders
	if colliders.is_empty():
		return "none"
	if COLLIDERS[piece] is String:
		return "its mesh"
	var boxes := 0
	for collider in colliders:
		boxes += 1 if _is_box(collider.faces) else 0
	if boxes == colliders.size():
		return "%d box%s" % [boxes, "" if boxes == 1 else "es"]
	return "%d shapes" % colliders.size()

## The way a triangle faces. Godot draws the side from which its corners run clockwise.
static func face_normal(corners: PackedVector3Array) -> Vector3:
	return (corners[2] - corners[0]).cross(corners[1] - corners[0]).normalized()

## What is wrong with a measured piece, against its row of PIECES.
static func check(piece: String, measured: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	var expected: AABB = PIECES[piece].box
	var box: AABB = measured.box
	if not _same(box.size, expected.size):
		problems.append("%s: %s m, the kit says %s m" % [piece, size_text(box.size), size_text(expected.size)])
	elif not _same(box.position, expected.position):
		problems.append("%s: its box starts at %s from the pivot, the kit says %s (pivot: %s)" % [piece, box.position, expected.position, PIECES[piece].pivot])
	if measured.material != PIECES[piece].material:
		problems.append("%s: material %s, the kit says %s (res://materials/%s.tres)" % [piece, measured.material, PIECES[piece].material, PIECES[piece].material])
	if measured.inward != 0:
		problems.append("%s: %d faces point into the piece" % [piece, measured.inward])
	if absf(float(measured.texel) - 1.0) > 0.01:
		problems.append("%s: %.2f UV units per metre on some face, the kit says 1" % [piece, measured.texel])
	problems.append_array(_check_colliders(piece, measured))
	if piece == "kit_doorway_2m":
		var hole := OPENING.grow(-TOLERANCE)
		for corners: PackedVector3Array in measured.faces:
			if hole.has_point((corners[0] + corners[1] + corners[2]) / 3.0):
				problems.append("%s: a face lies in the opening" % piece)
				break
	return problems

## The colliders against COLLIDERS: the bodies, the boxes, and that together they fill the piece.
static func _check_colliders(piece: String, measured: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	var colliders: Array[Dictionary] = measured.colliders
	var expected: Variant = COLLIDERS[piece]
	var count := 1 if expected is String else (expected as Array).size()
	if colliders.size() != count:
		problems.append("%s: %d colliders, the kit says %d" % [piece, colliders.size(), count])
		return problems
	var volume := 0.0
	var boxes: Array[AABB] = []
	for i in colliders.size():
		var collider := colliders[i]
		var faces: PackedVector3Array = collider.faces
		if collider.body != "StaticBody3D" or collider.shape != "ConcavePolygonShape3D" or collider.layer != WORLD_LAYER:
			problems.append("%s: collider %d is a %s with a %s on layers %d, expected a StaticBody3D with a ConcavePolygonShape3D on layer 1" % [piece, i, collider.body, collider.shape, collider.layer])
			continue
		volume += _volume(faces)
		var box := _bounds(faces)
		boxes.append(box)
		if expected is String: # a copy of the mesh
			if faces.size() != int(measured.triangles) * 3 or not _same(box.position, (measured.box as AABB).position) or not _same(box.size, (measured.box as AABB).size):
				problems.append("%s: its collider is not a copy of its mesh (%d triangles, box %s)" % [piece, int(faces.size() / 3.0), box])
			continue
		var wanted: AABB = (expected as Array)[i]
		if not _is_box(faces):
			problems.append("%s: collider %d is not a box" % [piece, i])
		elif not (_same(box.position, wanted.position) and _same(box.size, wanted.size)):
			problems.append("%s: collider %d is %s m at %s, the kit says %s m at %s" % [piece, i, size_text(box.size), box.position, size_text(wanted.size), wanted.position])
	for a in boxes.size():
		for b in range(a + 1, boxes.size()):
			var both := boxes[a].intersection(boxes[b])
			if both.size.x > TOLERANCE and both.size.y > TOLERANCE and both.size.z > TOLERANCE:
				problems.append("%s: colliders %d and %d overlap" % [piece, a, b])
	var mesh_faces := PackedVector3Array()
	for corners: PackedVector3Array in measured.faces:
		mesh_faces.append_array(corners)
	var mesh_volume := _volume(mesh_faces)
	if count > 0 and absf(volume - mesh_volume) > 0.001:
		problems.append("%s: the colliders hold %.3f m3, the mesh %.3f m3: they do not fill the piece" % [piece, volume, mesh_volume])
	return problems

## The volume a closed set of triangles encloses (the divergence theorem: one tetrahedron per face).
static func _volume(faces: PackedVector3Array) -> float:
	var sum := 0.0
	for i in range(0, faces.size(), 3):
		sum += faces[i].dot(faces[i + 1].cross(faces[i + 2]))
	return absf(sum) / 6.0

static func _bounds(points: PackedVector3Array) -> AABB:
	var box := AABB(points[0], Vector3.ZERO)
	for point in points:
		box = box.expand(point)
	return box

## A box: 12 triangles, every corner on a corner of their bounds.
static func _is_box(faces: PackedVector3Array) -> bool:
	if faces.size() != 36:
		return false
	var box := _bounds(faces)
	for point in faces:
		for axis in 3:
			if absf(point[axis] - box.position[axis]) > TOLERANCE and absf(point[axis] - box.end[axis]) > TOLERANCE:
				return false
	return true

static func _to_root(piece_root: Node3D, node: Node3D) -> Transform3D:
	var placed := Transform3D.IDENTITY
	var walk: Node = node
	while walk != piece_root:
		placed = (walk as Node3D).transform * placed
		walk = walk.get_parent()
	return placed

## Inside a closed piece: a ray from the point crosses its faces an odd number of times.
static func _inside(point: Vector3, triangles: Array[PackedVector3Array]) -> bool:
	var crossings := 0
	for corners in triangles:
		if Geometry3D.ray_intersects_triangle(point, RAY, corners[0], corners[1], corners[2]) != null:
			crossings += 1
	return crossings % 2 == 1

static func _same(a: Vector3, b: Vector3) -> bool:
	return absf(a.x - b.x) <= TOLERANCE and absf(a.y - b.y) <= TOLERANCE and absf(a.z - b.z) <= TOLERANCE

static func size_text(size: Vector3) -> String:
	return "%.2f x %.2f x %.2f" % [size.x, size.y, size.z]
