extends Node
## Global 60 Hz frame counter. Autoloaded as `GameClock` (no class_name — it is a
## singleton). Everything timing-sensitive reads `GameClock.frame`; frames are the
## unit (docs/conventions.md → "Frames are the unit").

var frame: int = 0

func _physics_process(_delta: float) -> void:
	frame += 1
