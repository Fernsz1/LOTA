class_name CharacterData
extends Resource

# Preloaded (not the bare class_name) so this compiles under headless --script
# tests, where the project's global class registry isn't loaded (same pattern
# as hit_resolver.gd). MD is MoveData.
const MD := preload("res://scripts/combat/move_data.gd")

@export var character_name: String = ""
@export var max_health: int = 1000              # authored; not consumed for the bar in v1 (see plan)
@export var walk_speed: float = 5.0             # px/frame (was 180.0 per-second — wrong unit)
@export var walk_b_speed: float = 4.5           # px/frame, back-walk
@export var jump_velocity: float = -13.0        # px/frame, up is negative
@export var jump_f_speed: float = 3.5           # px/frame, horizontal on fwd/back jump
@export var gravity: float = 0.565              # px/frame^2 added each airborne frame

@export var move_fast: MD
@export var move_heavy: MD
@export var move_skill: MD
@export var move_ultimate: MD
