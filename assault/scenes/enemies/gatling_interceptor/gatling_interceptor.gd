# assault/scenes/enemies/gatling_interceptor/gatling_interceptor.gd
class_name GatlingInterceptor
extends BaseEnemy

## The Tier 2 suppression gunship (docs/plans/cmufs7ekv000lnm2x7nbswijy/3-plan.md §2.6, §2.8; task
## plan docs/plans/cmulwkar600c1qj2xnqykqsvo/3-plan.md). A `GatlingInterceptorBrain` decides and an
## `EnemyMover` moves it, driven through `BaseEnemy`'s shared brain/mover tick, so this script defines
## no `_physics_process`.
##
## `_ready()` copies the config onto every node that uses it (the `.tres` wins over the scene) and
## builds the stream's `GatlingAttackPattern` per instance from flat config fields, with the brain's
## `rng` (a scene sub-resource would be shared by every Gatling). It runs AFTER its children's
## `_ready()`, so the brain builds its `EngagementBudget` on its first tick.
##
## `StreamPool` is a direct child of this root: `BulletPool` resolves its container as
## `get_parent().get_parent()`, so a pool authored under the `AttackController` would put live rounds
## under the ship and they would move with it.
##
## Rails: while an `EnemyPathMover` owns the motion, `GatlingInterceptorBrain.on_suspended()` runs the
## legacy constant stream from the config's `rail_*` fields.
##
## Spawn with b.gatling_interceptor().at(x, y); `.move()` is only needed until level 1 leaves its rails.

@export var config: GatlingInterceptorConfig = preload(
		"res://assault/scenes/enemies/gatling_interceptor/gatling_interceptor_config.tres")

@onready var _gatling_brain: GatlingInterceptorBrain = $Brain
@onready var _gatling_mover: EnemyMover = $EnemyMover
@onready var _attack: AttackController = $Attack


func _ready() -> void:
	super._ready()
	add_to_group("enemies")
	if config:
		_apply_config(config)


func _apply_config(cfg: GatlingInterceptorConfig) -> void:
	health.max_health = cfg.max_health
	health.current_health = cfg.max_health
	score_value = cfg.score_value
	if contact_hit_box:
		contact_hit_box.damage = cfg.collision_damage

	_gatling_mover.max_speed = cfg.max_speed
	_gatling_mover.acceleration = cfg.acceleration
	_gatling_mover.braking = cfg.braking
	_gatling_mover.max_turn_rate = cfg.turn_rate

	var stream := GatlingAttackPattern.new()
	stream.fire_interval = cfg.stream_interval  # unused while brain-driven: the brain sequences rounds
	stream.bullet_damage = cfg.round_damage
	stream.bullet_speed = cfg.round_speed
	stream.spread_angle = cfg.stream_spread
	stream.aim_at_player = true
	stream.accuracy = cfg.accuracy
	stream.rng = _gatling_brain.rng
	_attack.pattern = stream

	_gatling_brain.config = cfg
