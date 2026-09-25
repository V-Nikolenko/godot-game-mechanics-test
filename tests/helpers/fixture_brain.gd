## The fixture enemy's brain (`tests/helpers/fixture_enemy.tscn`), configured by the test.
##
## Every tick it records itself, requests `desired_velocity` (or `desired_velocity * tick_count`
## when `ramp` is on, so a test can tell which tick a velocity came from), faces `face_point` when
## set, and every `decision_interval` seconds of accumulated delta draws one `rng.randf()` into
## `decisions` — the "decision sequence" a seed must reproduce.
##
## No `class_name`: test-only. The file name ends in `_brain.gd`, so the single-writer sweep
## covers it like any real brain.
extends EnemyBrain

var desired_velocity: Vector2 = Vector2.ZERO
var ramp: bool = false
var face_point: Vector2 = Vector2.INF
var decision_interval: float = 0.25

var tick_count: int = 0
var tick_log: Array[float] = []
var suspended_count: int = 0
var decisions: Array[float] = []

var _decision_clock: float = 0.0


func tick(delta: float) -> void:
	tick_count += 1
	tick_log.append(delta)

	_decision_clock += delta
	while decision_interval > 0.0 and _decision_clock >= decision_interval:
		_decision_clock -= decision_interval
		decisions.append(rng.randf())

	if mover == null:
		return
	mover.request_velocity(desired_velocity * tick_count if ramp else desired_velocity)
	if face_point != Vector2.INF:
		mover.face_toward(face_point)


func on_suspended() -> void:
	suspended_count += 1
