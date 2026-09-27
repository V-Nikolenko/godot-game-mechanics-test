## How long an Assault AI enemy may stay in the fight before the level needs it gone
## (docs/plans/cmufs7ek60001nm2x6d0bt2et/3-plan.md §2.6).
##
## The corridor constraint (`AssaultCorridorConstraint`) forces an AI-driven enemy to keep
## re-entering the play area, so without this it lives until killed — stalling an
## `ENEMIES_CLEARED` section forever. A brain owns one of these, calls `update(delta)` on every
## tick from the moment it spawns, and on the first `true` enters DISENGAGE: releases its mover's
## constraint (`EnemyMover.release_constraint()`), raises `max_speed` to its exit speed, seeks the
## nearest point outside `EnemyWorld.projectile_world_rect()`, and frees itself once outside that
## rect.
##
## `active` is resolved once, from the `SceneTree` passed to the constructor: true only when
## `EnemyWorld.arena(tree)` finds a provider, i.e. only in Assault. In Open Space there is no
## corridor to escape, so `update()` is a permanent no-op and always returns `false` — the same
## enemy class runs forever there, which is the point.
class_name EngagementBudget
extends RefCounted

## Seconds this budget allows before `update()` starts reporting expired. Fixed at construction.
var seconds: float

## Resolved once at construction: true only when the tree has an Assault arena provider.
var active: bool

var _elapsed: float = 0.0
var _expired: bool = false


func _init(p_seconds: float, tree: SceneTree) -> void:
	seconds = p_seconds
	active = EnemyWorld.arena(tree) != null


## Advances the clock by `delta` and returns whether it has expired. Always `false` when not
## `active`. Once expired, every later call keeps returning `true` — the caller checks this once
## per tick and only acts the first time it turns true.
func update(delta: float) -> bool:
	if not active:
		return false
	if not _expired:
		_elapsed += delta
		if _elapsed >= seconds:
			_expired = true
	return _expired
