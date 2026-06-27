extends GutTest
## Unit tests for InputBuffer pure logic (Hybrid verification).

func test_push_then_read_current() -> void:
	var b := InputBuffer.new()
	b.push(InputBuffer.RIGHT | InputBuffer.FAST)
	assert_eq(b.get_state(0), InputBuffer.RIGHT | InputBuffer.FAST)

func test_get_state_age_reads_history() -> void:
	var b := InputBuffer.new()
	b.push(InputBuffer.LEFT)
	b.push(InputBuffer.RIGHT)
	assert_eq(b.get_state(0), InputBuffer.RIGHT)
	assert_eq(b.get_state(1), InputBuffer.LEFT)

func test_ring_wraps_to_newest() -> void:
	var b := InputBuffer.new()
	for i in InputBuffer.SIZE + 10:
		b.push(i & 0xFF)
	assert_eq(b.get_state(0), (InputBuffer.SIZE + 9) & 0xFF)

func test_is_held_requires_all_bits() -> void:
	var b := InputBuffer.new()
	b.push(InputBuffer.DOWN | InputBuffer.FAST)
	assert_true(b.is_held(InputBuffer.DOWN))
	assert_true(b.is_held(InputBuffer.DOWN | InputBuffer.FAST))
	assert_false(b.is_held(InputBuffer.UP))

func test_pressed_within_detects_rising_edge() -> void:
	var b := InputBuffer.new()
	b.push(0)
	b.push(InputBuffer.FAST)   # rising edge here
	b.push(InputBuffer.FAST)
	b.push(InputBuffer.FAST)
	assert_true(b.pressed_within(InputBuffer.FAST, 4))

func test_pressed_within_respects_window() -> void:
	var b := InputBuffer.new()
	b.push(InputBuffer.FAST)   # the only rising edge
	for i in 5:
		b.push(InputBuffer.FAST)
	# edge is now 6 frames old; a 4-frame window must not see it
	assert_false(b.pressed_within(InputBuffer.FAST, 4))
