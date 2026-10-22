extends RefCounted
## Seeds you can share. A seed is a text a person can type, read out and copy ("BLUE-FOX", "42"). The game turns
## it into a number for its random generators. Only static functions, no state: the same text is the same
## number on every machine, in every run.
## A run is a tree of seeds: the run's seed is the root, every room has a seed of its own for each kind of dice
## (child()), and a room's dice depend on nothing but the run, the kind and the room's number.

const MASK := 0xFFFFFFFF ## Seeds are 32-bit numbers.
const MAX_LENGTH := 24 ## The most characters a seed text may have.
const MAX_DIGITS := 9 ## Plain digits up to this length are the number itself.

## What a person typed, made canonical: no spaces at the ends, capital letters. "blue-fox " and "BLUE-FOX" are one seed.
static func normalize(text: String) -> String:
	return text.strip_edges().to_upper()

## The number of a seed text. Plain digits are that number, so the seeds 1, 42 and 1000 of the earlier tutorials
## stay what they were. Any other text is hashed.
static func parse(text: String) -> int:
	var clean := normalize(text)
	if _is_number(clean):
		return clean.to_int()
	return text_hash(clean)

## A text as a number: FNV-1a over its UTF-8 bytes, 32 bit. Our own five lines, because hash() and String.hash()
## are the engine's: the docs promise a number, not that it stays the same in the next version. A seed somebody
## sends to a friend has to be the same number tomorrow.
static func text_hash(text: String) -> int:
	var hashed := 0x811C9DC5 # FNV offset basis
	for byte in text.to_utf8_buffer():
		hashed = ((hashed ^ byte) * 0x01000193) & MASK # FNV prime
	return hashed

## The seed of one stream of dice in one room: the run's seed, the name of the stream and the number of the room,
## mixed (not added: see mix()). A room draws from its own stream, so what happens in room 5 can never move room 6,
## and the rooms of two runs are strangers to each other.
static func child(parent: int, stream: String, index: int) -> int:
	return mix(index, mix(text_hash(stream), parent))

## Two numbers into one, so that changing a single bit of either changes about half of the 32 bits of the result
## (a bit avalanche; this is the mixer of Squirrel Eiserloh's SquirrelNoise). Adding seeds gives neighbours:
## seed + room is the same number for (seed 42, room 6) and (seed 43, room 5), and two rooms with the same seed
## roll the same dice. Mixed, the neighbours are strangers.
static func mix(position: int, salt: int) -> int:
	var mixed := (position * 0xB5297A4D + salt) & MASK
	mixed ^= mixed >> 8
	mixed = (mixed + 0x68E31DA4) & MASK
	mixed ^= (mixed << 8) & MASK
	mixed = (mixed * 0x1B56C4E9) & MASK
	mixed ^= mixed >> 8
	return mixed

## The seed after this one, for the N key: a number goes up by one, a text gets a number at its end that goes up
## ("BLUE-FOX" -> "BLUE-FOX-2" -> "BLUE-FOX-3", "42" -> "43").
static func next_text(text: String) -> String:
	var clean := normalize(text)
	var digits := 0
	while digits < clean.length() and clean[clean.length() - 1 - digits].is_valid_int():
		digits += 1
	if digits == 0:
		return clean + "-2"
	var number := clean.substr(clean.length() - digits).to_int() + 1
	return clean.substr(0, clean.length() - digits) + str(number)

## Only the digits 0 to 9, 1 to MAX_DIGITS of them. (is_valid_int() would also let +5 and -5 through.)
static func _is_number(text: String) -> bool:
	return text.length() <= MAX_DIGITS and text.is_valid_int() and text[0] != "-" and text[0] != "+"
