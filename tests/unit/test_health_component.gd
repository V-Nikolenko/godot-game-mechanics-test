## Characterization tests for the Health component (global/components/health_component.gd).
##
## NOTE on the signal: `amount_changed` is declared AND emitted with one `int`. A
## zero-argument handler still raises an engine error, so these tests always connect
## one-argument callables. Until 2026-09-03 the declaration said zero parameters while
## the emit passed one; `test_amount_changed_declares_the_int_it_emits` pins the fix.
extends GutTest

var _host: Node2D
var _health: Health
var _seen: Array[int]


func before_each() -> void:
	## _ready() must have run or `invincibility_timer` is still null. The host parent is
	## no longer required by decrease() (see test_decrease_on_a_parentless_health_does_not_crash)
	## but is kept so these tests exercise the normal, in-tree shape.
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


func test_amount_changed_declares_the_int_it_emits() -> void:
	## Not characterization — this asserts intent. The signal is emitted with one
	## argument (`amount_changed.emit(current_health)`), so it must be DECLARED with
	## one, or every reader and every editor completion lies about its shape.
	##
	## This does NOT make a zero-argument handler legal: emitting one argument to a
	## zero-argument callable is still an engine error. Connect one-arg callables.
	var args := _signal_args(_health, "amount_changed")
	assert_eq(args.size(), 1, "amount_changed is emitted with one argument")
	assert_eq(args[0]["type"], TYPE_INT, "and that argument is the new health value")


func test_decrease_on_a_parentless_health_does_not_crash() -> void:
	## Health.decrease() used to build a log line from `get_parent().name`
	## unconditionally, so a component not yet in the tree died on its first hit.
	var orphan := Health.new()
	orphan.max_health = 50
	orphan.current_health = 50
	orphan._ready()
	orphan.decrease(10)
	assert_eq(orphan.current_health, 40, "damage lands with no parent attached")
	orphan.free()


## PropertyInfo dictionaries for one of `obj`'s signals, or [] if it has no such signal.
func _signal_args(obj: Object, signal_name: String) -> Array:
	for s in obj.get_signal_list():
		if s["name"] == signal_name:
			return s["args"]
	return []
