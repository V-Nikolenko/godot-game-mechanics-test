## Characterization tests for the Health component (global/components/health_component.gd).
##
## NOTE on the signal: `Health` declares `signal amount_changed` with NO parameters
## but emits it with one (`amount_changed.emit(current_health)`). A one-argument
## handler receives the value fine — which is why the shipped code works — but a
## zero-argument handler raises an engine error. These tests therefore always
## connect one-argument callables. Logged in BACKLOG.md → Discovered.
extends GutTest

var _host: Node2D
var _health: Health
var _seen: Array[int]


func before_each() -> void:
	## Health.decrease() prints get_parent().name, so it needs a parent, and
	## _ready() must have run or `invincibility_timer` is still null.
	_host = Node2D.new()
	add_child_autofree(_host)
	_health = Health.new()
	_seen = []
	_host.add_child(_health)
	_health.amount_changed.connect(func(v: int) -> void: _seen.append(v))


func test_defaults() -> void:
	assert_eq(_health.max_health, 100)
	assert_eq(_health.current_health, 100)
	assert_false(_health.invincibility_frames_enabled, "i-frames are opt-in")
	assert_eq(_health.invincibility_time_in_sec, 0.5)


func test_ready_clamps_current_health_into_range() -> void:
	var host := Node2D.new()
	add_child_autofree(host)
	var h := Health.new()
	h.max_health = 40
	h.current_health = 999
	host.add_child(h)
	assert_eq(h.current_health, 40, "current above max is clamped down on ready")

	var h2 := Health.new()
	h2.max_health = 40
	h2.current_health = -5
	host.add_child(h2)
	assert_eq(h2.current_health, 0, "negative current is clamped up to 0")


func test_decrease_subtracts_and_emits() -> void:
	_health.decrease(30)
	assert_eq(_health.current_health, 70)
	assert_eq(_seen, [70] as Array[int])


func test_decrease_floors_at_zero() -> void:
	_health.decrease(1000)
	assert_eq(_health.current_health, 0, "health never goes negative")
	assert_eq(_seen, [0] as Array[int])


func test_increase_heals_up_to_max() -> void:
	_health.decrease(60)
	_health.increase(20)
	assert_eq(_health.current_health, 60)
	_health.increase(1000)
	assert_eq(_health.current_health, 100, "healing is capped at max_health")


func test_increase_always_emits_even_when_nothing_changed() -> void:
	## CHARACTERIZED: set_health() emits unconditionally, so a no-op heal at full
	## health still fires amount_changed. Anything reacting to the signal (HUD,
	## DamageReaction) must tolerate repeats.
	_health.increase(10)
	assert_eq(_health.current_health, 100)
	assert_eq(_seen, [100] as Array[int], "a no-op heal still emits")


func test_set_health_is_not_clamped() -> void:
	## CHARACTERIZED: set_health() is the raw setter used by increase/decrease
	## after they clamp. Called directly it will happily store an illegal value.
	_health.set_health(500)
	assert_eq(_health.current_health, 500, "set_health does no clamping of its own")


func test_damage_is_free_of_invincibility_by_default() -> void:
	_health.decrease(10)
	_health.decrease(10)
	assert_eq(_health.current_health, 80, "without i-frames every hit lands")


func test_invincibility_frames_swallow_follow_up_hits() -> void:
	_health.invincibility_frames_enabled = true
	_health.invincibility_time_in_sec = 5.0
	_health.decrease(10)
	assert_eq(_health.current_health, 90, "the first hit lands")
	_health.decrease(10)
	_health.decrease(10)
	assert_eq(_health.current_health, 90, "hits during the i-frame window are ignored")
	assert_eq(_seen, [90] as Array[int], "and they emit nothing")


func test_invincibility_expires_and_damage_lands_again() -> void:
	_health.invincibility_frames_enabled = true
	_health.invincibility_time_in_sec = 0.05
	_health.decrease(10)
	assert_eq(_health.current_health, 90)
	await wait_seconds(0.2)
	_health.decrease(10)
	assert_eq(_health.current_health, 80, "damage resumes once the timer runs out")


func test_healing_ignores_invincibility() -> void:
	## CHARACTERIZED: only decrease() checks the i-frame timer, so a heal still
	## applies while the entity is invincible.
	_health.invincibility_frames_enabled = true
	_health.invincibility_time_in_sec = 5.0
	_health.decrease(50)
	assert_eq(_health.current_health, 50)
	_health.increase(20)
	assert_eq(_health.current_health, 70, "increase() is not gated by i-frames")
