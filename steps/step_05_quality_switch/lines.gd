extends MeshInstance3D
## Lines in 3D, drawn again every frame. Call begin(), then line() and box() as often as you like, then end().
## The lines of the last frame stay in `points` and `colors` until the next begin(), so anything can read what was drawn.
## The points are in world space: this node sits at the origin of the world.

@export var thickness := 3.0 ## Pixels. A line the engine draws is one pixel wide, too thin to see in a video. With a thickness every line becomes a thin strip that faces the camera and is this wide on the screen at any distance. 0 draws plain lines.

var points := PackedVector3Array() ## Two points per line.
var colors := PackedColorArray() ## One colour per point.

func _ready() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED # a line is a colour, not a lit surface
	material.vertex_color_use_as_albedo = true # the colour comes from the points
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA # so a line can fade out
	material.no_depth_test = true # the lines show through walls: they are about what is behind them
	material.cull_mode = BaseMaterial3D.CULL_DISABLED # a strip is seen from either side
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh = ImmediateMesh.new()

## Forgets the lines of the last frame.
func begin() -> void:
	points.clear()
	colors.clear()

func line(from: Vector3, to: Vector3, color: Color) -> void:
	points.append(from)
	points.append(to)
	colors.append(color)
	colors.append(color)

## The 12 edges of a box: the four of the floor, the four of the ceiling and the four posts between them.
func box(bounds: AABB, color: Color) -> void:
	var low := bounds.position
	var high := bounds.end
	var corners: Array[Vector2] = [Vector2(low.x, low.z), Vector2(high.x, low.z), Vector2(high.x, high.z), Vector2(low.x, high.z)] ## (x, z) of the four corners, in a ring.
	for i in 4:
		var from := corners[i]
		var to := corners[(i + 1) % 4]
		line(Vector3(from.x, low.y, from.y), Vector3(to.x, low.y, to.y), color)
		line(Vector3(from.x, high.y, from.y), Vector3(to.x, high.y, to.y), color)
		line(Vector3(from.x, low.y, from.y), Vector3(from.x, high.y, from.y), color)

## Three lines through a point, along the three axes: the usual way to mark a spot. half is half the length of a line.
func cross(center: Vector3, half: float, color: Color) -> void:
	line(center - Vector3.RIGHT * half, center + Vector3.RIGHT * half, color)
	line(center - Vector3.UP * half, center + Vector3.UP * half, color)
	line(center - Vector3.BACK * half, center + Vector3.BACK * half, color)

## An arrow along the -Z of a transform (the way a marker faces), from its origin. The head is two lines in the floor plane.
func arrow(placed: Transform3D, color: Color, length := 1.2) -> void:
	var forward := -placed.basis.z
	var side := placed.basis.x
	var tip := placed.origin + forward * length
	line(placed.origin, tip, color)
	line(tip, tip - forward * 0.3 + side * 0.2, color)
	line(tip, tip - forward * 0.3 - side * 0.2, color)

## Hands the collected lines to the mesh.
func end() -> void:
	var immediate := mesh as ImmediateMesh
	immediate.clear_surfaces()
	var primitive := Mesh.PRIMITIVE_LINES
	var vertices := points
	var shades := colors
	var camera := get_viewport().get_camera_3d()
	if thickness > 0.0 and camera != null:
		primitive = Mesh.PRIMITIVE_TRIANGLES
		vertices = PackedVector3Array()
		shades = PackedColorArray()
		for i in range(0, points.size(), 2):
			_add_strip(vertices, shades, camera, i)
	if vertices.is_empty():
		return # a surface without a point is an error
	immediate.surface_begin(primitive)
	for i in vertices.size():
		immediate.surface_set_color(shades[i])
		immediate.surface_add_vertex(vertices[i])
	immediate.surface_end()

## The line that starts at point i, as two triangles. The strip lies across the line and across the way the camera looks, so the camera sees its full width.
func _add_strip(vertices: PackedVector3Array, shades: PackedColorArray, camera: Camera3D, i: int) -> void:
	var from := points[i]
	var to := points[i + 1]
	var to_camera := camera.global_basis.z if camera.projection == Camera3D.PROJECTION_ORTHOGONAL else camera.global_position - (from + to) / 2.0
	var across := (to - from).cross(to_camera)
	if across.is_zero_approx():
		return # the line points at the camera: there is no width to see
	across = across.normalized()
	var width_from := across * _half_width(camera, from)
	var width_to := across * _half_width(camera, to)
	var corners: Array[Vector3] = [from - width_from, from + width_from, to + width_to, to - width_to]
	for corner: int in [0, 1, 2, 0, 2, 3]:
		vertices.append(corners[corner])
		shades.append(colors[i if corner < 2 else i + 1])

## Half the width of a strip at a point, in metres: `thickness` pixels at that distance from the camera.
func _half_width(camera: Camera3D, point: Vector3) -> float:
	var screen_height := get_viewport().get_visible_rect().size.y
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		return thickness / 2.0 * camera.size / screen_height
	var depth := maxf(0.05, (point - camera.global_position).dot(-camera.global_basis.z))
	return thickness / 2.0 * 2.0 * depth * tan(deg_to_rad(camera.fov) / 2.0) / screen_height
