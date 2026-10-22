extends Node3D
## The kit zoo: every piece of the kit on its own, in a row, with its measured size and its colliders above it and a dot on
## its pivot, next to a figure as big as the player. Walk along the row with the game's camera before a piece goes into a room
## Open this scene and press F6.

const CheckKit := preload("check_kit.gd")
const PlayerScene := preload("player.tscn")
const PIVOT_MATERIAL := preload("res://materials/fixture.tres")

## The pieces in the order of the kit's table (check_kit.gd).
const SCENES: Array[PackedScene] = [
	preload("kit/kit_floor_2x2.glb"),
	preload("kit/kit_ceiling_2x2.glb"),
	preload("kit/kit_wall_2m.glb"),
	preload("kit/kit_wall_1m.glb"),
	preload("kit/kit_doorway_2m.glb"),
	preload("kit/kit_corner.glb"),
	preload("kit/kit_door_leaf.glb"),
	preload("kit/kit_pillar.glb"),
	preload("kit/kit_plinth_3x3.glb"),
	preload("kit/kit_goal_pad.glb"),
]
const GAP := 1.5 ## Metres between two pieces.
const LABEL_ABOVE := 0.6 ## Metres from the top of a piece to its label.
const CEILING_LIFT := 1.0 ## Every piece stands on the ground; the ceiling tile hangs this high, at the height of the player's body.
const SPAWN := Vector3(0.0, 0.0, 7.0) ## Where the player starts: in front of the row, looking at it.

var player: CharacterBody3D
var labels: Array[Label3D] = [] ## One per piece, in the order of SCENES.

@onready var pieces: Node3D = $Pieces

func _ready() -> void:
	var names: Array[String] = []
	names.assign(CheckKit.PIECES.keys())
	var widths := 0.0
	for scene in SCENES:
		widths += (CheckKit.measure(scene).box as AABB).size.x
	var x := -(widths + GAP * (SCENES.size() - 1)) / 2.0
	for i in SCENES.size():
		var measured := CheckKit.measure(SCENES[i])
		var box: AABB = measured.box
		var piece := SCENES[i].instantiate() as Node3D
		piece.name = names[i]
		piece.position = Vector3(x - box.position.x, -box.position.y + (CEILING_LIFT if names[i] == "kit_ceiling_2x2" else 0.0), -box.position.z)
		pieces.add_child(piece)
		_add_pivot_dot(piece)
		var label := Label3D.new()
		label.text = "%s\n%s m\ncolliders: %s" % [names[i], CheckKit.size_text(box.size), CheckKit.collider_text(names[i], measured)]
		label.position = piece.position + Vector3(box.get_center().x, box.end.y + LABEL_ABOVE, box.get_center().z)
		label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		label.pixel_size = 0.004
		label.font_size = 48
		label.outline_size = 12
		pieces.add_child(label)
		labels.append(label)
		x += box.size.x + GAP
	player = PlayerScene.instantiate() as CharacterBody3D
	player.position = SPAWN
	add_child(player)

## A small glowing dot where the piece's pivot is.
func _add_pivot_dot(piece: Node3D) -> void:
	var dot := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.06
	sphere.height = 0.12
	sphere.material = PIVOT_MATERIAL
	dot.mesh = sphere
	dot.name = "Pivot"
	piece.add_child(dot)
