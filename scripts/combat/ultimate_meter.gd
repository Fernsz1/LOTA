class_name UltimateMeter
extends RefCounted
## Ultimate meter (spec .local/2026-07-04). Pure logic — no Node, no input, no
## physics (house pattern: HitResolver, GrabRules). The CharacterController owns
## one. Charges on damage DEALT (DEAL_RATE) and damage TAKEN (TAKE_RATE = 2x —
## the losing player reaches their ultimate sooner). A full bar gates the
## ultimate; consumed on use. The two rates are THE balance levers, tuned for
## ~1 ultimate per player per round (deal 1000 + take 500 == exactly full).

const MAX_METER: float = 100.0
const DEAL_RATE: float = 0.05   # meter per point of damage dealt
const TAKE_RATE: float = 0.10   # meter per point of damage taken

var value: float = 0.0

func gain_dealt(damage: int) -> void:
	value = minf(MAX_METER, value + damage * DEAL_RATE)

func gain_taken(damage: int) -> void:
	value = minf(MAX_METER, value + damage * TAKE_RATE)

func is_full() -> bool:
	return value >= MAX_METER

## Only legal on a full bar — gate call sites with is_full().
func consume() -> void:
	assert(is_full(), "consume() on a non-full meter — gate with is_full() first")
	value = 0.0

## 0..1 for the HUD bar.
func fraction() -> float:
	return value / MAX_METER

## Training mode: pin the bar full so ultimates are always practicable.
func fill() -> void:
	value = MAX_METER
