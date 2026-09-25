## ProjectileLifetime — world-space lifetime rules for a projectile: `max_time`, `max_distance`
## from the origin, and (optionally) the Assault mode's world rect. Add it as a child of the
## projectile ("the host"). See docs/plans/cmufklb100001p92xs1ey2fb1/3-plan.md §2.9.
##
## Godot runs a child's `_physics_process` after its parent's (tree order), so by the time this
## component checks its rules the host has already moved this frame — the same order
## `enemy_bullet.gd` used before this component existed.
##
## It never frees anything, which keeps the one-owner rule: the first rule that trips emits the
## host's `expired` signal exactly once — duck-typed via `has_signal("expired")`, so this component
## has no dependency on `EnemyBullet` — and then latches until the next `reset()`. A pooled bullet
## recycles through `BulletPool`'s `expired` connection; an unpooled one frees itself through its
## own `expired -> queue_free` wiring. `expire_now()` is IDEAS §12's `explicit_destroy()`: the same
## emit, through the same latch, so it can never double-fire alongside a rule. It has no caller in
## Phase 1 — it exists for a future recall-on-owner-death weapon.
##
## Arms LAZILY: on `reset()`, or on its own first physics tick, whichever comes first — never in
## `_ready()`. Arming records the origin (`host.global_position` at that moment), zeroes the clock,
## clears the latch, and resolves the world rect through `EnemyWorld.projectile_world_rect()`. This
## exists because the unpooled sniper shot (`sniper_enemy.gd`'s `_phase_fire()`) is never `reset()`
## — it is positioned at the muzzle only *after* `add_child()`, so arming in `_ready()` would record
## the wrong origin (the parent's) and never see the world rect. Arming on the first physics tick
## instead means the origin is read after that tick's movement, at most one frame of travel past
## the muzzle — immaterial next to the margin `max_distance` carries over the legacy rect diagonal.
##
## `persist_after_owner_death` is documented only in Phase 1: a future flag that will tell
## `BulletPool` to skip `cancel_active()` for a flagged projectile, so it can outlive its owner
## (Phase 5, rockets).
class_name ProjectileLifetime
extends Node

## Seconds since arming before this expires. 0 disables the rule.
@export var max_time: float = 0.0
## Distance in px from the origin before this expires. 0 disables the rule.
@export var max_distance: float = 0.0
## When true and a mode provides a world rect (`EnemyWorld.has_projectile_world_rect`), expire on
## leaving it. With no provider (Open Space, or a level whose camera is not a provider) this rule
## is a no-op — only `max_time` and `max_distance` apply.
@export var use_world_rect: bool = true

var _host: Node = null
var _armed: bool = false
var _expired: bool = false
var _origin: Vector2 = Vector2.ZERO
var _clock: float = 0.0
var _has_rect: bool = false
var _rect: Rect2 = Rect2()


func _ready() -> void:
	_host = get_parent()


## Re-arms: records a fresh origin, zeroes the clock, clears the expired latch, and re-resolves
## the world rect. Called by `EnemyBullet.reset()` when `BulletPool.acquire()` hands out a bullet.
func reset() -> void:
	_arm()


## IDEAS §12's `explicit_destroy()`: emits the host's `expired` immediately, through the same
## latch as every other rule, so it can never emit twice for the same life.
func expire_now() -> void:
	_emit_expired()


func _physics_process(delta: float) -> void:
	if not _armed:
		_arm()
	_clock += delta
	if _expired:
		return

	var pos: Vector2 = (_host as Node2D).global_position

	if max_time > 0.0 and _clock >= max_time:
		_emit_expired()
		return
	if max_distance > 0.0 and _origin.distance_to(pos) >= max_distance:
		_emit_expired()
		return
	if use_world_rect and _has_rect:
		var right: float = _rect.position.x + _rect.size.x
		var bottom: float = _rect.position.y + _rect.size.y
		if pos.x < _rect.position.x or pos.x > right \
				or pos.y < _rect.position.y or pos.y > bottom:
			_emit_expired()
			return


func _arm() -> void:
	_host = get_parent()
	_origin = (_host as Node2D).global_position
	_clock = 0.0
	_expired = false
	_has_rect = use_world_rect and EnemyWorld.has_projectile_world_rect(get_tree())
	_rect = EnemyWorld.projectile_world_rect(get_tree()) if _has_rect else Rect2()
	_armed = true


func _emit_expired() -> void:
	if _expired:
		return
	_expired = true
	if _host != null and _host.has_signal("expired"):
		_host.expired.emit()
