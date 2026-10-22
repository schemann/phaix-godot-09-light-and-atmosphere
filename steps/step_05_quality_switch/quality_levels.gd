extends Resource
## The quality levels, from the cheapest to the most expensive, and what each one turns on. One data file
## (quality_levels.tres), tuned in the inspector and never in code. Every list has one entry per level.
## The budget: every level holds 16.7 ms a frame (60 frames a second) on the machine it is meant for. The README
## has the frame times measured for each level (tools/frame_times.gd).

@export var names: Array[String] = [] ## What the player reads when the level changes.
@export var gi: Array[bool] = [] ## SDFGI, the indirect light: the most expensive part of the look.
@export var fog: Array[bool] = [] ## The volumetric fog.
@export var shadows: Array[bool] = [] ## The lamps' shadows (only the room types whose lighting data asks for them have any).
@export var glow: Array[bool] = [] ## The glow around the lamps.
@export var start_level := 2 ## The level a game starts with.
