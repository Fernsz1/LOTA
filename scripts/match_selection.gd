extends Node
## Carries the two players' picks from the character-select screen through the
## loading screen and intro card into the fight scene. Also holds the fight scene
## resource once the loading screen finishes an async load, so the intro screen can
## hand it straight to change_scene_to_packed() without loading it a second time.
## `winner` carries the match result from MatchManager to the results screen (2.6).

var p1_data: CharacterData = null
var p1_color: Color = Color(0.2, 0.5, 0.9, 1)
var p2_data: CharacterData = null
var p2_color: Color = Color(0.9, 0.55, 0.15, 1)

var pending_scene: PackedScene = null

var winner: int = 0
