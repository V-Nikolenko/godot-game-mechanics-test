## ContactProfile — per-enemy rule for what TOUCHING this enemy does, the offensive twin of
## `DefenseProfile` (docs/plans/cmufs7ek60001nm2x6d0bt2et/3-plan.md §2.3).
##
## | Mode      | `ContactHitBox`            | On a registered touch                           |
## |-----------|----------------------------|-------------------------------------------------|
## | NONE      | disabled                   | nothing                                         |
## | COLLISION | never touched (always on)  | `contact_made` — every legacy enemy, the default |
## | RAMMING   | on only while armed        | `contact_made`                                  |
## | EXPLOSIVE | on only while armed        | `contact_made`, then `detonate()`               |
## | ARMOR     | on from `setup()`, armable | `contact_made`; never detonates; optional shove |
##
## Damage stays whatever the `ContactHitBox` carries (`config.collision_damage`) in every mode, so
## `test_enemy_contact_damage.gd` keeps its single rule: "ramming hurts only while committed" is
## full damage while armed and none at rest, not a second damage field.
##
## EXPLOSIVE also detonates when its owner dies WHILE ARMED (it listens to the `Health` passed to
## `setup()`), so shooting a committed drone point-blank sets its blast off; dying unarmed never
## does. The blast is a separate `ContactBlast` in the owner's parent that outlives the owner.
##
## ARMOR (plan cmufs7ele0015nm2xvag3vrwc §2.6.3) is the profile of an armoured hull: armed at `setup()` so
## touching it hurts at all times, it never detonates and never harms its owner, and `set_armed(false)`
## closes the hitbox (a Corvette whose plates are gone). With `shove_speed > 0` each armed touch also calls
## the duck-typed `apply_knockback(dir * shove_speed)` on the touched hurtbox's parent, `dir` pointing
## owner -> target; a target without the method is skipped.
##
## Arming toggles `monitorable` and `monitoring` with `set_deferred`, so it is legal from a physics
## callback. It never reads or writes motion and holds no timer.
##
## A node, not a `Resource`: armed/detonated is per-instance runtime state (same reason as
## `DefenseProfile`). `BaseEnemy._ready()` resolves a scene-authored one or creates a COLLISION one.
class_name ContactProfile
extends Node

## ARMOR is appended (value 4) so serialized scene ints do not shift.
enum Mode { NONE, COLLISION, RAMMING, EXPLOSIVE, ARMOR }

## Emitted once per registered touch (NONE never; RAMMING / EXPLOSIVE / ARMOR only while armed).
signal contact_made(area: Area2D)
## EXPLOSIVE only, at most once, with the global position the blast was spawned at.
signal detonated(position: Vector2)

@export var mode: Mode = Mode.COLLISION
## EXPLOSIVE only (px).
@export var blast_radius: float = 0.0
## EXPLOSIVE only.
@export var blast_damage: int = 0
## EXPLOSIVE only: how many physics frames the blast stays live. At least `ContactBlast.MIN_FRAMES`;
## a lower value is clamped in `setup()` with an error.
@export var blast_frames: int = 3
## ARMOR only (px/s): impulse handed to the touched target's `apply_knockback()`. 0 disables the shove.
@export var shove_speed: float = 0.0

var _actor: Node2D = null
var _hit_box: HitBox = null
var _armed: bool = false
var _detonated: bool = false
var _is_set_up: bool = false


## Called once by `BaseEnemy._ready()`. [param hit_box] and [param health] may be null (the Bonus
## Drone has no `ContactHitBox`). A second call is ignored, so nothing is connected twice.
func setup(actor: Node2D, hit_box: HitBox, health: Health) -> void:
	if _is_set_up:
		return
	_is_set_up = true
	_actor = actor
	_hit_box = hit_box
	if blast_frames < ContactBlast.MIN_FRAMES:
		push_error("ContactProfile: blast_frames %d is below %d; clamped" % [blast_frames, ContactBlast.MIN_FRAMES])
		blast_frames = ContactBlast.MIN_FRAMES
	if _hit_box != null:
		_hit_box.area_entered.connect(_on_contact)
	if health != null:
		health.amount_changed.connect(_on_health_changed)
	match mode:
		Mode.NONE, Mode.RAMMING, Mode.EXPLOSIVE:
			_apply_enabled(false)
		Mode.COLLISION:
			pass  # Never touched: every legacy enemy keeps its hitbox exactly as authored.
		Mode.ARMOR:
			_armed = true
			_apply_enabled(true)


## RAMMING / EXPLOSIVE / ARMOR only; a no-op for NONE and COLLISION.
func set_armed(armed: bool) -> void:
	if not _is_armable():
		return
	_armed = armed
	_apply_enabled(armed)


func is_armed() -> bool:
	return _armed


## EXPLOSIVE only; idempotent. Spawns one `ContactBlast` into the owner's parent at the owner's
## global position and emits `detonated` once.
func detonate() -> void:
	if mode != Mode.EXPLOSIVE or _detonated:
		return
	# Set BEFORE spawning: a contact handler that kills the owner re-enters here through
	# `_on_health_changed` while this call is still on the stack.
	_detonated = true
	if _actor == null or not is_instance_valid(_actor) or not _actor.is_inside_tree() or _actor.get_parent() == null:
		push_warning("ContactProfile: owner is not in the tree; blast suppressed")
		return
	var at := _actor.global_position
	ContactBlast.spawn(_actor.get_parent(), at, blast_radius, blast_damage, blast_frames)
	detonated.emit(at)


func _is_armable() -> bool:
	return mode == Mode.RAMMING or mode == Mode.EXPLOSIVE or mode == Mode.ARMOR


func _apply_enabled(enabled: bool) -> void:
	if _hit_box == null or not is_instance_valid(_hit_box):
		return
	_hit_box.set_deferred("monitorable", enabled)
	_hit_box.set_deferred("monitoring", enabled)


func _on_contact(area: Area2D) -> void:
	if mode == Mode.NONE:
		return
	# Belt and braces: in the one flush before a deferred disarm lands, the box can still report.
	if _is_armable() and not _armed:
		return
	contact_made.emit(area)
	if mode == Mode.EXPLOSIVE:
		detonate()
	elif mode == Mode.ARMOR:
		_shove(area)


## ARMOR only. Duck-typed: the touched hurtbox's parent is the target (as for the player's `HurtBox`),
## and a target that does not expose `apply_knockback` is simply left alone.
func _shove(area: Area2D) -> void:
	if shove_speed <= 0.0 or _actor == null or not is_instance_valid(_actor) or area == null:
		return
	var target := area.get_parent() as Node2D
	if target == null or not target.has_method("apply_knockback"):
		return
	var dir := target.global_position - _actor.global_position
	# Dead centre has no direction; push along the owner's facing rather than not at all.
	dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector2.DOWN.rotated(_actor.global_rotation)
	target.apply_knockback(dir * shove_speed)


func _on_health_changed(current_health: int) -> void:
	if current_health == 0 and mode == Mode.EXPLOSIVE and _armed:
		detonate()
