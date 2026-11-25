class_name HeavyGunship
extends BaseEnemy

## The Heavy Gunship (docs/plans/cmug23oo90029m52wae4clve0/3-plan.md §2.4, §2.5; Phase 10 t4 and t5, task plans
## docs/plans/cmwafsrb100a7qs2yvre9y1o2/3-plan.md and docs/plans/cmwafsrb400abqs2yt38khcyu/3-plan.md): a mobile gun platform built from parts. A
## `HeavyGunshipBrain` decides and an `EnemyMover` moves it, through `BaseEnemy`'s shared tick, so this script defines no `_physics_process`, reads no
## camera and never parks.
##
## THE HULL is vulnerable: the root `Health` is the phase bar (the brain's `HullPhase`), and the body, the root `HurtBox` and the `ContactHitBox`
## share one 112 x 144 `RectangleShape2D`. THE PARTS are six `EnemyModule`s under `Modules` with a `ModularHull` beside them: two side batteries, the
## nose cannon (with a frontal shield of its own), the rear missiles and two weak-point vents (indestructible, open only in the brain's VENT,
## `hull_share` 1.0: an open vent doubles a hit). Each part carries a `Light` the brain drives. **The flush-edge rule:** every part's
## hurtbox is a rectangle whose outer side lies exactly on the hull rectangle's side (its exposed edge), so a shot entering the outline through
## that edge overlaps the part and the hull in the same physics step and both take it (a part hit is also a hull hit, owner choice 3); a shot
## entering elsewhere hits only the hull. Each part's `HomingPoint` is its exposed-edge midpoint, and `homing_point()` steers a player rocket there.
## Gated by `tests/integration/test_heavy_gunship.gd`; t9's art may not move or resize a shape.
##
## Nose-down art (`sprite_forward_angle` PI/2): the nose is local +y, so port (the hull's left) is local +x.
##
## MOUNTS. `_ready()` builds the parts' mounts through `ModularHull.build_mounts()` (pools as root children, so rounds land in the container),
## each gated by the brain's `attack_gate`, sets up the cannon's local `EnemyShield` (t5) and hands the hull to the brain. The host answers the
## duck-typed launcher questions a rocket mount asks.
##
## Spawn with `b.heavy_gunship().at(x, y)`.

@export var config: HeavyGunshipConfig = load("res://assault/scenes/enemies/heavy_gunship/heavy_gunship_config.tres")

## A rocket arms this far beyond the hull's half-diagonal (px), so it never hits its own hull.
const ROCKET_CLEARANCE := 4.0

var _owner_group: StringName = &""

@onready var _gunship_brain: HeavyGunshipBrain = $Brain
@onready var _gunship_mover: EnemyMover = $EnemyMover
@onready var _hull: ModularHull = $ModularHull


func _ready() -> void:
	super._ready()
	add_to_group("enemies")
	_owner_group = StringName("heavy_gunship_%d" % get_instance_id())
	add_to_group(_owner_group)
	if config:
		_apply_config(config)
	_hull.build_mounts(self, _gunship_brain.rng, _owner_group, _gunship_brain.attack_gate)
	_setup_cannon_shield()
	_gunship_brain.bind_mounts(_hull)


## The nose cannon's local `EnemyShield` (t5): the config's numbers, the cannon hurtbox's absorber slot, facing the nose (the brain keeps it
## there). Freed with the cannon, so a wreck draws no arc. Looked up with `get_node_or_null`: the exit probe strips `Modules`.
func _setup_cannon_shield() -> void:
	var cannon := _hull.module(HeavyGunshipBrain.CANNON)
	if cannon == null:
		return
	var shield := cannon.get_node_or_null(^"Shield") as EnemyShield
	if shield == null or cannon.hurt_box == null:
		return
	if config:
		shield.arc_deg = config.shield_arc_deg
		shield.capacity = config.shield_capacity
		shield.regen_delay = config.shield_regen_delay
		shield.regen_seconds = config.shield_regen_seconds
		shield.reboot_seconds = config.shield_reboot_seconds
	shield.attach(cannon.hurt_box)
	shield.face(Vector2.RIGHT.rotated(rotation + sprite_forward_angle))
	_hull.module_destroyed.connect(_on_module_destroyed)


## A destroyed cannon takes its shield with it (`EnemyShield._exit_tree()` releases the absorber slot).
func _on_module_destroyed(part: EnemyModule) -> void:
	if part.module_id != HeavyGunshipBrain.CANNON:
		return
	var shield := part.get_node_or_null(^"Shield")
	if shield != null and not shield.is_queued_for_deletion():
		shield.queue_free()


func _apply_config(cfg: HeavyGunshipConfig) -> void:
	health.max_health = cfg.max_health
	health.current_health = cfg.max_health
	score_value = cfg.score_value
	## The scene-authored ContactHitBox never reads the config; pinned for the whole roster by test_enemy_contact_damage.gd.
	if contact_hit_box:
		contact_hit_box.damage = cfg.collision_damage
	_gunship_mover.max_speed = cfg.max_speed
	_gunship_mover.acceleration = cfg.acceleration
	_gunship_mover.braking = cfg.braking
	_gunship_mover.max_turn_rate = cfg.max_turn_rate
	_gunship_brain.config = cfg


## The parts' coordinator.
func modular_hull() -> ModularHull:
	return _hull


## The group every mount's weapon exempts (this hull).
func owner_group() -> StringName:
	return _owner_group


## The body rectangle's size (px).
func body_size() -> Vector2:
	var shape := ($CollisionShape2D as CollisionShape2D).shape as RectangleShape2D
	return shape.size if shape != null else Vector2.ZERO


## The player's mining beam passes over the hull and burns the parts it crosses (a target, not a wall).
func is_laser_blocking() -> bool:
	return false


## Duck-typed launcher question (`EnemyRocket.launch`, the rocket battery): the hull's own velocity.
func launch_velocity() -> Vector2:
	return velocity


## Duck-typed launcher question: the hull's half-diagonal + 4, so a rocket arms only once clear of the whole rectangle.
func rocket_clear_radius() -> float:
	return body_size().length() * 0.5 + ROCKET_CLEARANCE


## Where a player homing rocket coming from [param from] steers: the `homing_point()` (exposed-edge midpoint) of the nearest live vulnerable part,
## else the hull centre.
func homing_point(from: Vector2) -> Vector2:
	var best := global_position
	var best_d := INF
	if _hull == null:
		return best
	for part in _hull.modules():
		if part.is_destroyed() or not part.is_vulnerable():
			continue
		var p := part.homing_point()
		var d := from.distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = p
	return best
