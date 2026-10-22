extends "room_chain.gd"
## An accident, for the pinned seeds to catch. Somebody finds the vault rule in the way ("a rare room is rare anyway")
## and takes the spacing out. Every room still fits, no room overlaps, every lock still has its key and the game still
## plays, but the runs of a lot of seeds are not the runs they were.
##
##   godot --headless --path godot/09-light-and-atmosphere -s res://steps/step_04_runtime_gi/check_pinned.gd \
##     -- --chain=res://steps/step_04_runtime_gi/accidental_change.gd

func _vault_too_soon() -> bool:
	return false
