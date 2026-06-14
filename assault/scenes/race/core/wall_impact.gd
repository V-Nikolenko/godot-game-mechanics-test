## WallImpact — stateless reaction helper shared by DashPanel walls and TrackSideWalls.
## Both detectors call resolve() after confirming a ship has clipped a wall; this single
## method owns the "hit a wall" reaction so it is never duplicated.
class_name WallImpact
extends RefCounted

## Lateral speed (px/s) given to the player as a knockback velocity impulse.
## Decays via PlayerBase.apply_knockback_motion and survives held input because
## move_state yields while knockback is active.
const KNOCKBACK_PLAYER_SPEED: float = 420.0

## Apply wall-hit reaction to a ship.
## push_dir: +1 shoves toward +X (right / centre from the left wall),
##           -1 shoves toward -X (left / centre from the right wall).
## damage   : HP (after shield) to deal via the HurtBox path.
## ai_push  : positional nudge in pixels applied to assignment-driven AI ships.
static func resolve(ship: Node2D, push_dir: float, damage: int, ai_push: float) -> void:
	## Route damage through HurtBox → DamageReaction / PlayerBase so the shield
	## absorbs the first N hits before HP drops — identical path as bullets/mines.
	var hb := ship.get_node_or_null("HurtBox") as HurtBox
	if hb:
		hb.received_damage.emit(damage)

	if ship.has_method("steer_toward"):
		## AI racer: assignment-driven, not physics — nudge desired_x laterally then
		## let LateralMover glide back toward the lane from the pushed position.
		ship.global_position.x += push_dir * ai_push
		ship.steer_toward(ship.global_position.x)
	elif ship.has_method("apply_knockback"):
		## Player: velocity impulse that decays at 1200 px/s² and can't be cancelled
		## by held input while active. Pure lateral — Y is owned by PlayerRaceController.
		ship.apply_knockback(Vector2(push_dir * KNOCKBACK_PLAYER_SPEED, 0.0))
