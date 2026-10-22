extends Resource
## How each room type is lit. One data file (room_lighting.tres), tuned in the inspector and never in code.
## Every list has one entry per room type, in the order of the chain's Type: straight, long, turn_left,
## turn_right, wide, vault, goal. The tint is not here: it is the plan's (its own stream of dice, tutorial 06).

@export var energy: Array[float] = [] ## How bright the lamp is. A bigger room gets a brighter lamp.
@export var shadows: Array[bool] = [] ## Shadows cost six renders of the room (a cube map), so only where something throws one.
@export var reach := 0.5 ## Metres past the farthest corner of the floor. Light without shadows passes through walls: a short range keeps it out of the room next door.
