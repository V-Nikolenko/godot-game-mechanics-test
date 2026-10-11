class_name Sniper
extends BaseEnemy

## The Sniper (docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md §2.5, §2.8; task t12-sniper-shell): a
## `SniperBrain` decides and an `EnemyMover` moves it, driven through `BaseEnemy`'s shared brain/mover tick,
## so this script defines no `_physics_process` and no `_process`. It replaces the legacy sniper, whose
## fly-in constant had to equal the length of the path's fly-in step and whose `_process` fought the path mover
## for the ship's rotation.
##
## `_ready()` copies the config onto every node that uses it (the `.tres` wins over the scene). It runs AFTER
## its children's `_ready()`, so the brain builds its `EngagementBudget` on its first tick.
##
## `RailPool` is a direct child of this root: `BulletPool` resolves its container as
## `get_parent().get_parent()`. It does NOT persist after the sniper's death: a round dies with its shooter.
##
## The art points up (the muzzle is at the nose, local (0, -20)), so `sprite_forward_angle` is -PI / 2 and the
## mover's facing rule gives `rotation = heading + PI / 2`, the convention `Vector2.UP.rotated(rotation)` reads.
##
## Rails: while an `EnemyPathMover` owns the motion, `SniperBrain.on_suspended()` starts the `Telegraph`'s own
## legacy aim / lock / fire cycle. It never writes `rotation`.
##
## Spawn with b.sniper().at(x, y); `.move()` is only needed until level 1 leaves its rails.

@export var config: SniperConfig = load("res://assault/scenes/enemies/sniper/sniper_config.tres")

@onready var _sniper_brain: SniperBrain = $Brain
@onready var _sniper_mover: EnemyMover = $EnemyMover
@onready var _telegraph: SniperTelegraph = $Telegraph
@onready var _muzzle: Marker2D = $Muzzle
@onready var _rail_pool: BulletPool = $RailPool
@onready var _barrel: Sprite2D = $Barrel


func _ready() -> void:
	super._ready()
	add_to_group("enemies")
	if config:
		_apply_config(config)


func _apply_config(cfg: SniperConfig) -> void:
	health.max_health = cfg.max_health
	health.current_health = cfg.max_health
	score_value = cfg.score_value
	if contact_hit_box:
		contact_hit_box.damage = cfg.collision_damage

	_sniper_mover.max_speed = cfg.max_speed
	_sniper_mover.acceleration = cfg.acceleration
	_sniper_mover.braking = cfg.braking
	_sniper_mover.max_turn_rate = cfg.max_turn_rate

	_sniper_brain.config = cfg
	_sniper_brain.telegraph = _telegraph
	_sniper_brain.muzzle = _muzzle
	_sniper_brain.pool = _rail_pool
	_sniper_brain.barrel = _barrel
	_telegraph.config = cfg
	_telegraph.muzzle = _muzzle
	_telegraph.pool = _rail_pool
