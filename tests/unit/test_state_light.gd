## Unit tests for StateLight — the single small light an enemy shows to telegraph its attack
## intent (docs/plans/cmufs7ek60001nm2x6d0bt2et/3-plan.md §2.9).
## INTENT: new component, so this pins the contract rather than characterizing existing behaviour.
extends GutTest

var _light: StateLight


func before_each() -> void:
	_light = StateLight.new()
	add_child_autofree(_light)


func test_off_is_invisible() -> void:
	assert_eq(_light.get_state(), StateLight.State.OFF, "OFF is the default state")
	assert_eq(_light.modulate.a, 0.0, "OFF has zero alpha")


func test_armed_is_red() -> void:
	_light.set_state(StateLight.State.ARMED)
	assert_eq(_light.modulate, Color(Color.RED, StateLight.MAX_ALPHA))


func test_charging_is_yellow() -> void:
	_light.set_state(StateLight.State.CHARGING)
	assert_eq(_light.modulate, Color(Color.YELLOW, StateLight.MAX_ALPHA))


func test_commit_is_white() -> void:
	_light.set_state(StateLight.State.COMMIT)
	assert_eq(_light.modulate, Color(Color.WHITE, StateLight.MAX_ALPHA))


func test_modulate_alpha_never_exceeds_cap_in_any_state() -> void:
	## Color stores components as float32, so a modulate.a built from the float64 constant
	## 0.85 comes back as 0.85000002384186 - an epsilon that accounts for storage, not headroom.
	var epsilon := 0.0001
	for s in [StateLight.State.OFF, StateLight.State.ARMED, StateLight.State.CHARGING, StateLight.State.COMMIT]:
		_light.set_state(s)
		assert_true(_light.modulate.a <= StateLight.MAX_ALPHA + epsilon, "state %d" % s)


func test_blink_once_shows_charging_immediately() -> void:
	_light.set_state(StateLight.State.ARMED)
	_light.blink_once()
	assert_eq(_light.modulate, Color(Color.YELLOW, StateLight.MAX_ALPHA), "blink flashes yellow first")


func test_blink_once_returns_to_the_previous_state() -> void:
	_light.set_state(StateLight.State.ARMED)
	_light.blink_once()
	simulate(_light, 20, StateLight.BLINK_SECONDS / 10.0)
	assert_eq(_light.get_state(), StateLight.State.ARMED, "back to the state active before the blink")
	assert_eq(_light.modulate, Color(Color.RED, StateLight.MAX_ALPHA))


func test_blink_once_from_off_returns_to_off() -> void:
	_light.blink_once()
	simulate(_light, 20, StateLight.BLINK_SECONDS / 10.0)
	assert_eq(_light.get_state(), StateLight.State.OFF)
	assert_eq(_light.modulate.a, 0.0)


func test_set_state_cancels_an_in_progress_blink() -> void:
	_light.set_state(StateLight.State.ARMED)
	_light.blink_once()
	_light.set_state(StateLight.State.COMMIT)
	simulate(_light, 20, StateLight.BLINK_SECONDS / 10.0)
	assert_eq(_light.get_state(), StateLight.State.COMMIT, "the later set_state wins, not the stale blink")


func test_generated_texture_corner_pixel_is_fully_transparent() -> void:
	var sprite: Sprite2D = _light.get_node("Light")
	var image: Image = sprite.texture.get_image()
	assert_eq(image.get_pixel(0, 0).a, 0.0)
	assert_eq(image.get_width(), StateLight.TEXTURE_SIZE)
	assert_eq(image.get_height(), StateLight.TEXTURE_SIZE)
