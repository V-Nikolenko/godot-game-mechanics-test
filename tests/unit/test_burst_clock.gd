## Unit tests for BurstClock (global/enemy_ai/burst_clock.gd).
## docs/plans/cmufs7ekv000lnm2x7nbswijy/3-plan.md §2.3.
extends GutTest


func test_start_zero_fires_nothing() -> void:
	var clock := BurstClock.new()
	clock.start(0, 0.1)
	assert_false(clock.is_running())
	assert_eq(clock.advance(10.0), 0)
	assert_eq(clock.shots_fired, 0)


func test_start_4_gap_0_1_advancing_by_0_05_gives_shots_at_0_0_1_0_2_0_3() -> void:
	var clock := BurstClock.new()
	clock.start(4, 0.1)
	assert_true(clock.is_running())

	# The first shot is due immediately on the first advance, whatever delta is.
	assert_eq(clock.advance(0.05), 1, "shot 1 due on the first advance")
	assert_eq(clock.advance(0.05), 1, "shot 2, at 0.1")
	assert_eq(clock.advance(0.05), 0, "no shot yet at 0.15")
	assert_eq(clock.advance(0.05), 1, "shot 3, at 0.2")
	assert_eq(clock.advance(0.05), 0, "no shot yet at 0.25")
	assert_eq(clock.advance(0.05), 1, "shot 4, at 0.3")
	assert_eq(clock.shots_fired, 4)
	assert_false(clock.is_running(), "burst exhausted after the 4th shot")
	assert_eq(clock.advance(1.0), 0, "an exhausted clock never fires again")


func test_a_single_long_advance_returns_exactly_the_burst_size_never_more() -> void:
	var clock := BurstClock.new()
	clock.start(4, 0.1)
	assert_eq(clock.advance(1.0), 4, "capped at count, even though 1.0 / 0.1 = 10 gaps elapsed")
	assert_eq(clock.shots_fired, 4)
	assert_false(clock.is_running())
	assert_eq(clock.advance(1.0), 0)


func test_stop_mid_burst_ends_it() -> void:
	var clock := BurstClock.new()
	clock.start(4, 0.1)
	assert_eq(clock.advance(0.05), 1)
	clock.stop()
	assert_false(clock.is_running())
	assert_eq(clock.advance(10.0), 0, "stop() must not let the burst resume")
	assert_eq(clock.shots_fired, 1, "shots already fired before stop() are not undone")


func test_start_again_after_a_finished_burst_resets_shots_fired() -> void:
	var clock := BurstClock.new()
	clock.start(2, 0.1)
	clock.advance(0.2)
	assert_eq(clock.shots_fired, 2)
	clock.start(3, 0.1)
	assert_eq(clock.shots_fired, 0, "start() resets the counter for the new burst")
	assert_eq(clock.advance(1.0), 3)


func test_zero_gap_fires_the_whole_burst_on_the_first_advance() -> void:
	var clock := BurstClock.new()
	clock.start(5, 0.0)
	assert_eq(clock.advance(0.0), 5, "a zero gap must not hang: the whole burst is due at once")
	assert_false(clock.is_running())
