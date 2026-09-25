## The mode's rule on where an AI-driven enemy may move
## (docs/plans/cmufklb100001p92xs1ey2fb1/3-plan.md §2.4-§2.5).
##
## `EnemyMover.step()` passes its limited desired velocity through `filter()` just before the one
## `move_and_slide()`. This base is the identity — Open Space has no constraint at all, so it never
## even gets one of these; the base exists as the contract `AssaultCorridorConstraint` (t11)
## extends. A constraint may hold per-enemy state (the corridor's "entered" latch), so every mover
## gets its own instance: `EnemyWorld.movement_constraint(tree)` returns a new one per call.
class_name MovementConstraint
extends RefCounted


## Returns the velocity the enemy is actually allowed to have at `_position`, given the velocity
## its brain wants. The identity here.
func filter(_position: Vector2, desired: Vector2) -> Vector2:
	return desired
