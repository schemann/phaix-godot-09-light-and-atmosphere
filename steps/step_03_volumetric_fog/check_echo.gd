extends SceneTree
## Measures the deep echo: two seeds whose rooms are the same rooms, shifted by one. When a room's seed is the run's
## seed plus the room's number, seed 43's room 5 has the seed of seed 42's room 6, so it rolls the same dice, and
## the whole run of seed 43 is seed 42 one room earlier. Data only, like the other checks: no level is started, the
## chain is asked for its plans and the plans are compared.
##
##   godot --headless --path godot/09-light-and-atmosphere -s res://steps/step_03_volumetric_fog/check_echo.gd
##
## Options: `-- --seeds=200` measures seeds 1 to 200 (the default), `-- --chain=res://steps/step_03_room_seeds/room_chain.gd`
## measures another step's chain: this is the number before the fix. The exit code is 0 if there is no echo
## and 1 if there is, so a build server can run it.
##
## Two things are compared for every pair of neighbour seeds (s, s + 1), room k of s + 1 against room k + 1 of s:
## the locks (does the room have the same lock state?) and the props (same room type: the same props?).

const DEFAULT_SEEDS := 200
const GOAL_ROOM := 20
const LOCK_CHANCE := 0.4 ## The level's default.
const FIRST_ROOM := 1 ## Room 0 is skipped: it is always a straight room and never locked.
const WINDOW := 12 ## Rooms compared per pair: 1 to 12. All of them agreeing by chance is below one in a thousand.
const PAIR_LIMIT := 0.02 ## At most this share of the pairs may agree in every room of the window.
const ROOM_MARGIN := 0.05 ## The lock states of single rooms may agree this much more often than chance.
const PROP_LIMIT := 0.05 ## At most this share of the same-type rooms may have the same props.
const SHOW_PAIRS := 3 ## How many pairs are printed as rows.

func _initialize() -> void:
	var seed_count := DEFAULT_SEEDS
	var chain_path := "res://steps/step_03_volumetric_fog/room_chain.gd"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seeds="):
			seed_count = int(argument.trim_prefix("--seeds="))
		elif argument.begins_with("--chain="):
			chain_path = argument.trim_prefix("--chain=")

	var result := await measure(load(chain_path) as GDScript, seed_count, SHOW_PAIRS, self)
	print("deep echo, chain %s" % chain_path.trim_prefix("res://"))
	for row: String in result.rows:
		print(row)
	print("neighbour seeds 1-%d, rooms %d to %d, room k of seed s + 1 against room k + 1 of seed s:" % [seed_count + 1, FIRST_ROOM, FIRST_ROOM + WINDOW - 1])
	print("  locks: %.1f%% of the rooms agree (chance for a lock rate of %.0f%%: %.1f%%)" % [result.agree * 100.0, result.lock_rate * 100.0, result.chance * 100.0])
	print("  pairs that agree in all %d rooms: %d of %d (%.1f%%, limit %.0f%%)" % [WINDOW, result.echo_pairs, seed_count, result.echo_share * 100.0, PAIR_LIMIT * 100.0])
	print("  props: %d of %d same-type rooms have the same props (%.1f%%, limit %.0f%%)" % [result.same_props, result.same_type, result.props_share * 100.0, PROP_LIMIT * 100.0])
	var problems := problems_of(result)
	if problems.is_empty():
		print("ECHO NONE")
	else:
		for problem in problems:
			print("  " + problem)
		print("ECHO FOUND")
	quit(1 if not problems.is_empty() else 0)

## The lock states and prop lists of the rooms 0 to FIRST_ROOM + WINDOW of a seed.
static func rooms_of(chain_script: GDScript, chain_seed: int) -> Array:
	var chain: RefCounted = chain_script.new(chain_seed, GOAL_ROOM, LOCK_CHANCE)
	for i in FIRST_ROOM + WINDOW + 1:
		chain.next_plan()
	return chain.plans

## Compares seed s + 1 with seed s for s = 1 to seed_count. host: a node or tree to await frames on (the chains read
## room scenes; the engine empties its queue between frames).
static func measure(chain_script: GDScript, seed_count: int, show_pairs: int, host: Object) -> Dictionary:
	var compared := 0
	var agreeing := 0
	var locked := 0
	var echo_pairs := 0
	var same_type := 0
	var same_props := 0
	var rows: Array[String] = []
	var previous := rooms_of(chain_script, 1)
	for chain_seed in range(1, seed_count + 1):
		if chain_seed % 20 == 0:
			await (host.get_tree() if host is Node else host as SceneTree).process_frame
		var next := rooms_of(chain_script, chain_seed + 1)
		var all_agree := true
		for k in range(FIRST_ROOM, FIRST_ROOM + WINDOW):
			var mine: Object = next[k] # seed s + 1, room k
			var theirs: Object = previous[k + 1] # seed s, room k + 1
			compared += 1
			locked += 1 if mine.locked else 0
			if mine.locked == theirs.locked:
				agreeing += 1
			else:
				all_agree = false
			if mine.type == theirs.type:
				same_type += 1
				same_props += 1 if mine.props == theirs.props else 0
		echo_pairs += 1 if all_agree else 0
		if chain_seed <= show_pairs:
			rows.append("  seed %-4d rooms %d-%d: %s" % [chain_seed, FIRST_ROOM + 1, FIRST_ROOM + WINDOW, _lock_row(previous, FIRST_ROOM + 1)])
			rows.append("  seed %-4d rooms %d-%d: %s" % [chain_seed + 1, FIRST_ROOM, FIRST_ROOM + WINDOW - 1, _lock_row(next, FIRST_ROOM)])
			rows.append("")
		previous = next
	var rate := float(locked) / compared
	return {
		compared = compared,
		agree = float(agreeing) / compared,
		lock_rate = rate,
		chance = rate * rate + (1.0 - rate) * (1.0 - rate),
		echo_pairs = echo_pairs,
		echo_share = float(echo_pairs) / seed_count,
		same_type = same_type,
		same_props = same_props,
		props_share = float(same_props) / maxi(same_type, 1),
		rows = rows,
	}

## What is wrong with a measurement: empty if there is no echo.
static func problems_of(result: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	if result.echo_share > PAIR_LIMIT:
		problems.append("%.1f%% of the neighbour seeds are one run shifted by a room (limit %.0f%%)" % [result.echo_share * 100.0, PAIR_LIMIT * 100.0])
	if result.agree > result.chance + ROOM_MARGIN:
		problems.append("the lock states agree in %.1f%% of the rooms, chance is %.1f%%" % [result.agree * 100.0, result.chance * 100.0])
	if result.props_share > PROP_LIMIT:
		problems.append("%.1f%% of the same-type rooms have the props of their neighbour (limit %.0f%%)" % [result.props_share * 100.0, PROP_LIMIT * 100.0])
	return problems

## "..##.#" : a locked room is a #, an open one a dot.
static func _lock_row(plans: Array, first: int) -> String:
	var row := ""
	for k in range(first, first + WINDOW):
		row += "#" if plans[k].locked else "."
	return row
