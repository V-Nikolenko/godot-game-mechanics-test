class_name Bomber
extends BaseEnemy

## The Bomber (docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md §2.4, §2.8; task t9-bomber-shell): a
## `BomberBrain` decides and an `EnemyMover` moves it, driven through `BaseEnemy`'s shared brain/mover
## tick, so this script defines no `_physics_process`.
##
## `_ready()` copies the config onto every node that uses it (the `.tres` wins over the scene). It runs
## AFTER its children's `_ready()`, so the brain builds its `EngagementBudget` on its first tick.
##
## `GravityBombPool`, `MinePool` and `PursuitBombPool` are direct children of this root, all with
## `persist_after_owner_death`: `BulletPool` resolves its container as `get_parent().get_parent()`, and a
## bomb or mine already dropped must outlive the bomber that dropped it (the pool hands it over when the
## bomber leaves the tree). Their sizes are authored in the scene and gated against
## `EnemyOrdnanceScenes.pool_size_for()` by `tests/integration/test_bomber.gd`.
##
## Rails: while an `EnemyPathMover` owns the motion (`is_ai_suspended()`), `_process` drops a gravity
## bomb DOWN every `config.rail_bomb_interval`, today's bomb. It only runs a clock and spawns; nothing
## here writes motion.
##
## Spawn with b.bomber().at(x, y); `.move()` is only needed until level 1 leaves its rails.

@export var config: BomberConfig = load("res://assault/scenes/enemies/bomber/bomber_config.tres")

var _rail_clock: float = 0.0

@onready var _bomber_brain: BomberBrain = $Brain
@onready var _bomber_mover: EnemyMover = $EnemyMover
@onready var _gravity_pool: BulletPool = $GravityBombPool
@onready var _mine_pool: BulletPool = $MinePool
@onready var _pursuit_pool: BulletPool = $PursuitBombPool


func _ready() -> void:
	super._ready()
	add_to_group("enemies")
	if config:
		_apply_config(config)


func _apply_config(cfg: BomberConfig) -> void:
	health.max_health = cfg.max_health
	health.current_health = cfg.max_health
	score_value = cfg.score_value
	if contact_hit_box:
		contact_hit_box.damage = cfg.collision_damage

	_bomber_mover.max_speed = cfg.max_speed
	_bomber_mover.acceleration = cfg.acceleration
	_bomber_mover.max_turn_rate = cfg.max_turn_rate

	_bomber_brain.config = cfg


## The rail fallback clock (plan §2.8): active only while a rail owns the bomber.
func _process(delta: float) -> void:
	if not is_ai_suspended() or config == null:
		return
	_rail_clock += delta
	if _rail_clock >= config.rail_bomb_interval:
		_rail_clock -= config.rail_bomb_interval
		drop(EnemyOrdnance.Kind.GRAVITY_BOMB, Vector2.DOWN, config.rail_bomb_speed,
				global_position + Vector2.DOWN * config.rail_bomb_range)


## Takes ordnance of `kind` from its pool, sets its trigger and blast from the config, and launches it
## from the bomber's position. Null when the pool is exhausted (the pool logs a warning).
func drop(kind: EnemyOrdnance.Kind, dir: Vector2, speed: float, target_point: Vector2) -> EnemyOrdnance:
	var o := _pool_for(kind).acquire(global_position) as EnemyOrdnance
	if o == null:
		return null
	match kind:
		EnemyOrdnance.Kind.GRAVITY_BOMB:
			o.trigger_radius = config.trigger_radius
			o.arm_delay = config.gravity_bomb_arm_delay
			o.warning_time = config.gravity_bomb_fuse
			o.blast_radius = config.gravity_blast_radius
			o.blast_damage = config.gravity_blast_damage
		EnemyOrdnance.Kind.MINE:
			o.trigger_radius = config.trigger_radius
			o.arm_delay = config.mine_arm_delay
			o.warning_time = config.mine_warning
			o.mine_life = config.mine_life
			o.blast_radius = config.mine_blast_radius
			o.blast_damage = config.mine_blast_damage
		EnemyOrdnance.Kind.PURSUIT_BOMB:
			o.trigger_radius = config.pursuit_trigger_radius
			o.steer_window = config.pursuit_steer_window
			o.turn_rate = config.pursuit_turn_rate
			o.steer_lead = config.pursuit_lead
			o.final_speed = config.pursuit_final_speed
			o.blast_radius = config.pursuit_blast_radius
			o.blast_damage = config.pursuit_blast_damage
	o.launch(dir, speed, target_point)
	return o


func _pool_for(kind: EnemyOrdnance.Kind) -> BulletPool:
	match kind:
		EnemyOrdnance.Kind.MINE:
			return _mine_pool
		EnemyOrdnance.Kind.PURSUIT_BOMB:
			return _pursuit_pool
		_:
			return _gravity_pool
