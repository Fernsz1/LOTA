extends Node2D
## Runtime controller for the Map Select screen (MapRoot). Also the single source
## of truth for region grouping + metadata, read by the @tool map_generator.gd.

const BASE_COLOR := Color("#343d46")

## adm1_pcode -> macro-region id. Verified against .local/philippines_optimized.json.
const GROUPS := {
	"PH01": "NorthernLuzon", "PH02": "NorthernLuzon", "PH14": "NorthernLuzon",
	"PH03": "CentralLuzon", "PH13": "CentralLuzon",
	"PH04": "SouthernLuzon", "PH17": "SouthernLuzon", "PH05": "SouthernLuzon",
	"PH06": "Visayas", "PH07": "Visayas", "PH08": "Visayas",
	"PH09": "Mindanao", "PH10": "Mindanao", "PH11": "Mindanao",
	"PH12": "Mindanao", "PH16": "Mindanao", "PH19": "Mindanao",
}

## macro-region id -> display name, stage StageData resource, hover neon color.
const REGIONS := {
	"NorthernLuzon": {"display": "Northern Luzon",
		"stage": "res://stages/mountain_festival/mountain_festival_data.tres",
		"neon": Color("#ffd700")},
	"CentralLuzon": {"display": "Central Luzon",
		"stage": "res://stages/heritage_plaza/heritage_plaza_data.tres",
		"neon": Color("#8a2be2")},
	"SouthernLuzon": {"display": "Southern Luzon",
		"stage": "res://stages/bahay_kubo/bahay_kubo_data.tres",
		"neon": Color("#ff2d55")},
	"Visayas": {"display": "Visayas",
		"stage": "res://stages/beach_court/beach_court_data.tres",
		"neon": Color("#00e5ff")},
	"Mindanao": {"display": "Mindanao",
		"stage": "res://stages/barangay_ring/barangay_ring_data.tres",
		"neon": Color("#39ff14")},
}
