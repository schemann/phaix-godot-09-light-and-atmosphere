extends SceneTree
## Pins seeds. A seed is a promise: the run you saw is the run a friend gets. Nothing in the game fails when somebody
## changes the generator and that promise breaks (every room still fits, every lock still has its key), so this check
## remembers what a few seeds looked like when the generator was right, and fails loudly when they look different.
## Data only: no level is started, the chain is asked for its plans and the plans are compared with PINNED.
##
##   godot --headless --path godot/09-light-and-atmosphere -s res://steps/step_01_room_lights/check_pinned.gd
##
## Options: `-- --chain=res://steps/step_01_room_lights/accidental_change.gd` checks another chain (this one is a
## generator that was changed by accident). `-- --print` prints the pins of the chain as they stand now, ready to paste
## into PINNED: do that once, after you changed the generator on purpose. The exit code is 0 if every pin holds and 1
## if one does not, so a build server can run it.

const Chain := preload("room_chain.gd")
const Seeds := preload("seeds.gd")

const GOAL_ROOM := 20 ## The level's defaults: the run a player gets.
const LOCK_CHANCE := 0.4
const MAX_PLANS := 100 ## A chain that has not reached its goal room by now is broken.
const LETTERS := "SL<>WVG" ## One letter per room type, in the order of the chain's Type enum: straight, long, turn left, turn right, wide, vault, goal.

## What the chains of five seeds looked like when they were right. Per seed: a letter for every room, the rooms that are
## locked (room:key spot), and where the last room stands (x z, metres).
const PINNED := {
	"1": {types = "SWLL>S<LSVS>LLLWLS<SG", locks = ["1:2", "2:1", "6:1", "10:2", "12:1", "17:2"], end = "126.0 -136.0"},
	"42": {types = "S>SWSL<LSW><>LS<L>SLG", locks = ["3:2", "6:0", "7:0", "10:0", "11:2", "13:2", "16:2", "17:1"], end = "150.0 -92.0"},
	"1000": {types = "SLWLWS>L<V><L><>SLS<G", locks = ["3:1", "7:2", "8:0", "12:2", "13:1", "14:2", "16:1", "18:2"], end = "104.0 -150.0"},
	"BLUE-FOX": {types = "SWLVS>WSLL<L>VSL<LSSG", locks = ["4:0", "5:1", "11:0", "15:1", "16:0", "17:1"], end = "122.0 -136.0"},
	"WATCH-ME": {types = "SSLW>SLW<SSS><>S<LS>G", locks = ["4:2", "5:0", "6:1", "8:1", "10:1", "11:1", "12:1", "13:0", "15:1", "16:1", "17:0"], end = "94.0 -132.0"},
}

func _initialize() -> void:
	var chain_path := "res://steps/step_01_room_lights/room_chain.gd"
	var print_pins := false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--chain="):
			chain_path = argument.trim_prefix("--chain=")
		elif argument == "--print":
			print_pins = true
	var chain_script := load(chain_path) as GDScript

	if print_pins:
		print("const PINNED := {")
		for seed_text: String in PINNED:
			var pins := pins_of(chain_script, seed_text)
			print("\t\"%s\": {types = \"%s\", locks = %s, end = \"%s\"}," % [seed_text, pins.types, pins.locks, pins.end])
		print("}")
		quit(0)
		return

	print("pinned seeds, chain %s" % chain_path.trim_prefix("res://"))
	var failed := 0
	for seed_text: String in PINNED:
		await process_frame # every chain reads seven room scenes: let the engine empty its queue now and then
		var problems := problems_of(chain_script, seed_text)
		var pins := PINNED[seed_text] as Dictionary
		if problems.is_empty():
			print("  seed %-10s %2d rooms, %d locked: as pinned" % [seed_text, pins.types.length(), pins.locks.size()])
		else:
			failed += 1
			for problem in problems:
				printerr("  seed %-10s %s" % [seed_text, problem])
	if failed == 0:
		print("PINNED OK")
	else:
		print("PINNED FAILED: %d of %d seeds are not the runs they were" % [failed, PINNED.size()])
		print("Changed the generator on purpose? Run with -- --print and paste the new pins into PINNED.")
	quit(1 if failed > 0 else 0)

## The chain of a seed in the words of the pins.
static func pins_of(chain_script: GDScript, seed_text: String) -> Dictionary:
	var chain: RefCounted = chain_script.new(Seeds.parse(seed_text), GOAL_ROOM, LOCK_CHANCE)
	while chain.plans.size() < MAX_PLANS:
		if chain.next_plan().type == Chain.Type.GOAL:
			break
	var types := ""
	var locks: Array[String] = []
	for plan: Object in chain.plans:
		types += LETTERS[plan.type]
		if plan.locked:
			locks.append("%d:%d" % [plan.index, plan.key_spot])
	var end: Vector3 = chain.plans[-1].transform.origin
	return {types = types, locks = locks, end = "%.1f %.1f" % [end.x, end.z]}

## Every way the chain of a seed differs from its pins, as sentences. Empty: the seed is as pinned.
static func problems_of(chain_script: GDScript, seed_text: String) -> Array[String]:
	var problems: Array[String] = []
	var pinned := PINNED[seed_text] as Dictionary
	var now := pins_of(chain_script, seed_text)
	var then := pinned.types as String
	var got := now.types as String
	for room in mini(then.length(), got.length()):
		if then[room] != got[room]:
			problems.append("room %d: pinned %s, got %s" % [room, _name_of(then[room]), _name_of(got[room])])
			break # the rooms after the first difference are all moved, too
	if then.length() != got.length():
		problems.append("%d rooms pinned, %d rooms now" % [then.length(), got.length()])
	if str(pinned.locks) != str(now.locks):
		problems.append("locks (room:key spot) pinned %s, got %s" % [pinned.locks, now.locks])
	if pinned.end != now.end:
		problems.append("the last room stands at %s, pinned %s" % [now.end, pinned.end])
	return problems

## "W" -> "WIDE".
static func _name_of(letter: String) -> String:
	return str(Chain.Type.find_key(LETTERS.find(letter)))
