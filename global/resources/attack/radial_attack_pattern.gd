## RadialAttackPattern — fires N bullets spread around a base direction in one shot.
##
## Generalises both shapes a multi-emitter boss needs, which is why it is one resource and not
## two: `arc >= TAU` is a full evenly-spaced ring (spacing `TAU / count`, no duplicate at the
## seam), and `arc < TAU` is a fan of that angular width CENTRED on the base direction
## (spacing `arc / (count - 1)`).
##
## ── This pattern deliberately IGNORES `ship.rotation` ────────────────────────────────────────
##
## Its two siblings both fold the hull's rotation into their non-aimed branch
## (`aimed_attack_pattern.gd:31` and `gatling_attack_pattern.gd:35`, both
## `Vector2.DOWN.rotated(ship.rotation)`). This one must not, and the divergence is a contract
## rather than an oversight: `StationLaserPhase._physics_process` rotates the station at
## 0.5 rad/s during exactly the phase the core's ring fires in. Over one 2.0 s ring interval that
## is 1.0 rad of hull rotation against a 0.628 rad ring spacing, so folding in `ship.rotation`
## would add ~1.6 spacings of uncontrolled drift per ring on top of the designed precession —
## and the ring would no longer have the lane-coverage property `core_ring_step` is tuned for.
##
## `base_angle` is therefore ABSOLUTE in world space, and the caller owns any precession.
##
## Runtime state stays in the calling node, never here: `attack_pattern_resource.gd:1-5` requires
## these resources to be configuration only so ships can share one `.tres`.
class_name RadialAttackPattern
extends AttackPatternResource

## Bullets per shot. 0 or fewer fires nothing.
@export var bullet_count: int = 10

## `>= TAU` → a full ring. `< TAU` → a fan of this angular width centred on the base direction.
@export var arc: float = TAU

## Base direction in radians, absolute in world space. See the header: the caller advances this
## between shots to precess a ring.
@export var base_angle: float = 0.0

## When true, `base_angle` is added to the angle toward the player, falling back to
## `Vector2.DOWN` when there is no player — the same fallback `aimed_attack_pattern.gd:27` uses.
@export var aim_at_player: bool = false

@export var bullet_damage: int = 10
@export var bullet_speed: float = 220.0

## Each bullet spawns this far from the ship ALONG ITS OWN ANGLE, so a ring emerges from the hull
## rim and a fan from the barrel mouth rather than from the entity's centre. Final on-screen
## pixels at scale = 1 — never multiplied by `ArenaCamera.WORLD_SCALE`.
@export var spawn_radius: float = 0.0


func fire(ship: Node2D, pool: BulletPool) -> void:
	if bullet_count <= 0:
		return

	var centre := base_angle
	if aim_at_player:
		## `players[0]`, not the nearest — matches `aimed_attack_pattern.gd:22-24` and
		## `gatling_attack_pattern.gd:29-31`. There is only ever one player.
		var players := ship.get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			centre += ((players[0] as Node2D).global_position - ship.global_position).angle()
		else:
			centre += Vector2.DOWN.angle()

	var start := centre
	var step := 0.0
	if arc >= TAU:
		## A full ring closes on itself, so the spacing divides by `count`, not `count - 1`.
		## Using `count - 1` here would put the first and last bullet on the same angle.
		step = TAU / float(bullet_count)
	elif bullet_count > 1:
		step = arc / float(bullet_count - 1)
		start = centre - arc * 0.5
	## bullet_count == 1 keeps step 0 and start == centre — the lone bullet sits on the base
	## angle, and nothing divides by `count - 1` == 0.

	for i in bullet_count:
		var angle := start + float(i) * step
		var dir := Vector2.RIGHT.rotated(angle)
		var bullet := pool.acquire(ship.global_position + dir * spawn_radius) as EnemyBullet
		if bullet == null:
			## Pool exhausted — it has already pushed a warning. Fire what we have and stop.
			return
		var hb := bullet.get_node_or_null("HitBox") as HitBox
		if hb:
			hb.damage = bullet_damage
		bullet.speed = bullet_speed
		bullet.set_direction(dir)
