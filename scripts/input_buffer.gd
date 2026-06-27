class_name InputBuffer
extends RefCounted
## Fixed-size ring of per-frame input bitmasks for ONE player. Pure logic, no
## engine polling — unit-tested. Perf: preallocated PackedInt32Array, power-of-two
## size → bitwise index wrap, one int per frame (no per-frame allocation).

const SIZE: int = 64        # power of two; ≥ 30-frame retention (feel-reference §4)
const MASK: int = SIZE - 1

# Input bits — 4 directions + 4 attack buttons. Confirm the button set in 1.3.
const UP: int       = 1 << 0
const DOWN: int     = 1 << 1
const LEFT: int     = 1 << 2
const RIGHT: int    = 1 << 3
const FAST: int     = 1 << 4
const HEAVY: int    = 1 << 5
const SKILL: int    = 1 << 6
const ULTIMATE: int = 1 << 7

var _buf: PackedInt32Array = PackedInt32Array()
var _head: int = 0          # index of the most-recently written frame

func _init() -> void:
	_buf.resize(SIZE)         # zero-filled = "no input" history

## Append one frame's input bitmask. Call once per physics frame.
func push(state: int) -> void:
	_head = (_head + 1) & MASK
	_buf[_head] = state

## Bitmask `age` frames ago. 0 = current, 1 = previous, … up to SIZE-1.
func get_state(age: int = 0) -> int:
	assert(age >= 0 and age < SIZE)
	return _buf[(_head - age) & MASK]

## Are ALL of `bits` held on the current frame?
func is_held(bits: int) -> bool:
	return (_buf[_head] & bits) == bits

## Rising edge: did `bits` go up→down within the last `window` frames?
## The action-buffer primitive (feel-reference §4: ~4-frame window).
func pressed_within(bits: int, window: int) -> bool:
	assert(window >= 1 and window < SIZE)
	for age in window:
		var now: int = _buf[(_head - age) & MASK]
		var prev: int = _buf[(_head - age - 1) & MASK]
		if (now & bits) == bits and (prev & bits) != bits:
			return true
	return false
