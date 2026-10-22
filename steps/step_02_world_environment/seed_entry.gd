extends PanelContainer
## The box where a seed is typed (T). It only asks: it sends the text, and the level decides what to do with it.
## While it is up the level waits (see Level._on_seed_entry_opened).

const Level := preload("level.gd")
const Seeds := preload("seeds.gd")

signal opened ## The box is up.
signal closed ## The box is gone again, with a seed or without.
signal seed_submitted(text: String) ## Enter: a seed to start a run with, already in its canonical form.

@export var level: Level

@onready var line: LineEdit = $Rows/Line

func _ready() -> void:
	line.max_length = Seeds.MAX_LENGTH
	line.text_submitted.connect(_on_text_submitted)
	line.gui_input.connect(_on_line_input)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("edit_seed") and not visible:
		open()
		get_viewport().set_input_as_handled()

## Shows the box with the current seed selected: typing replaces it, Enter keeps it.
func open() -> void:
	line.text = level.seed_text
	show()
	line.grab_focus()
	opened.emit()

func close() -> void:
	hide()
	line.release_focus()
	closed.emit()

func _on_text_submitted(text: String) -> void:
	var clean := Seeds.normalize(text)
	if clean.is_empty():
		return # nothing to start with: the box stays
	close()
	seed_submitted.emit(clean)

## Esc closes the box and changes nothing. Tab would toggle the map behind it, so it is swallowed.
func _on_line_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_debug"):
		get_viewport().set_input_as_handled()
