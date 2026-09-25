## The Assault corridor's velocity filter (docs/plans/cmufklb100001p92xs1ey2fb1/3-plan.md §2.5,
## §2.5a, P-7).
##
## AI-driven enemies work in world space and know nothing about the screen, so a fresh spawn above
## the screen (`wave_manager.gd:175`) or an enemy the brain sends too far from the fight needs a
## rule that steers it back without ever teleporting it (P-7's rejected clamp). This constraint is
## a velocity filter between `EnemyMover`'s desired velocity and its one `move_and_slide()`: inside
## the corridor it does nothing; leaving it adds an inward pressure that grows with distance; past
## the hard band (IDEAS §34) the enemy is forced to re-enter regardless of what its brain asks for.
##
## `filter()` works per axis (x and y independently) against `visible`, the corridor rect derived
## from `ArenaCamera`'s own constants — the single source of the numbers, never duplicated here.
## Every Assault spawn starts above the screen, so a not-yet-entered enemy is governed by rule 1
## only, on whichever axis is still outside, whatever band its distance would otherwise fall into;
## the tangential axis (already inside) always passes through unchanged. `entered` latches true the
## first time the enemy is fully inside `visible` and never resets — which is why the provider
## (`ArenaCamera.enemy_movement_constraint()`) hands out a fresh instance per mover.
class_name AssaultCorridorConstraint
extends MovementConstraint

## Speed floor (px/s) an axis is raised to while entering, so a spawn never drifts in slower than this.
@export var entry_speed: float = 60.0
## Width (px) of the inward-pressure ramp just outside `visible`.
@export var soft_band: float = 120.0
## Distance (px) past `visible` beyond which the enemy is forced back in regardless of its own
## request (IDEAS §34's "forced to re-enter").
@export var hard_band: float = 450.0
## Inward pressure (px/s) added at and beyond `soft_band`, ramping from 0 across it.
@export var edge_pressure: float = 200.0

## Latches true the first time the enemy is fully inside `visible`. Never resets.
var _entered: bool = false


func filter(position: Vector2, desired: Vector2) -> Vector2:
	var visible := _visible_rect()
	var sx := _axis_state(position.x, visible.position.x, visible.end.x)
	var sy := _axis_state(position.y, visible.position.y, visible.end.y)

	if not _entered and sx.y <= 0.0 and sy.y <= 0.0:
		_entered = true

	return Vector2(
		_apply_axis(sx.x, sx.y, desired.x),
		_apply_axis(sy.x, sy.y, desired.y))


## `x` = outward sign for this axis (-1 past the low edge, +1 past the high edge, 0 inside),
## `y` = `d`, the distance outside `visible` on this axis (0 when inside).
func _axis_state(pos: float, lo: float, hi: float) -> Vector2:
	if pos < lo:
		return Vector2(-1.0, lo - pos)
	if pos > hi:
		return Vector2(1.0, pos - hi)
	return Vector2(0.0, 0.0)


func _apply_axis(side: float, d: float, v: float) -> float:
	if d <= 0.0:
		return v  # inside visible on this axis: untouched, whatever the other axis is doing

	var u := v * side  # v's component along the outward direction: positive = outward

	if not _entered:
		return minf(u, -entry_speed) * side  # discard outward, floor the inward speed

	if d <= soft_band:
		u -= edge_pressure * d / soft_band
	elif d < hard_band:
		var outward := maxf(u, 0.0) * (1.0 - (d - soft_band) / (hard_band - soft_band))
		var inward := minf(u, 0.0)
		u = outward + inward - edge_pressure
	else:
		u = minf(u, 0.0) - edge_pressure  # outward removed entirely, full pressure

	return u * side


func _visible_rect() -> Rect2:
	var pinned_centre := Vector2(ArenaCamera.SCREEN_W, ArenaCamera.SCREEN_H) * 0.5
	var half := Vector2(
		ArenaCamera.SCREEN_W * 0.5 + ArenaCamera.H_LIMIT,
		ArenaCamera.SCREEN_H * 0.5 + ArenaCamera.V_LIMIT)
	return Rect2(pinned_centre - half, half * 2.0)
