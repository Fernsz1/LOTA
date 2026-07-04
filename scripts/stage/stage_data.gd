class_name StageData
extends Resource
## 7.2/7.5 — a stage's data format, mirroring CharacterData's role for characters.
## Placeholder-flat (no art yet, per docs/conventions.md) — background + floor color
## is the whole "stage" until real backgrounds exist.

@export var stage_name: String = ""
@export var background_color: Color = Color(0.07, 0.08, 0.11, 1)
@export var floor_color: Color = Color(0.25, 0.25, 0.25, 1)
