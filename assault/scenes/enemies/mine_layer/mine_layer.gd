class_name MineLayer
extends BaseEnemy

## The Mine Layer (docs/plans/cmug23omu000lm52wu7rak0q5/3-plan.md §2.11; task t10): a slow minelaying specialist. A
## `MineLayerBrain` decides and an `EnemyMover` moves it, driven through `BaseEnemy`'s shared brain/mover tick, so this
## script defines no `_physics_process`.
##
## `_ready()` copies the config onto every node that uses it (the `.tres` wins over the scene) and joins group
## `enemies` (`BaseEnemy` does not; placed `Hostility.ALL` mines look for that group).
##
## One root `BulletPool` per variant with a weight above 0 (`ProximityPool`, `ChainPool`, `PulsePool`, `HomingPool`), all
## with `persist_after_owner_death`: `BulletPool` resolves its container as `get_parent().get_parent()`, and a mine
## already laid must outlive the layer that laid it. Sizes are authored in the scene and gated against
## `EnemyMineScenes.pool_size_for()` by `tests/integration/test_mine_layer.gd`.
##
## `drop_mine()` is the only place a layer configures a mine. It sets the arm delay, the eject time and the life by
## mode, and never a trigger, warning or blast number: the variant scene owns those.
##
## Rails: while an `EnemyPathMover` owns the motion (`is_ai_suspended()`), `_process` drops a PROXIMITY mine at the
## dispenser every `config.rail_mine_interval`. It only runs a clock and spawns; nothing here writes motion.
##
## Spawn with b.mine_layer().at(x, y).

@export var config: MineLayerConfig = load("res://assault/scenes/enemies/mine_layer/mine_layer_config.tres")

## Smallest fraction of the closed `scale.y` an open hatch keeps (a zero scale is not a valid transform).
const HATCH_MIN_SCALE := 0.001

var _rail_clock: float = 0.0
var _hatch_open: float = 0.0
var _hatch_base_y: float = 1.0

@onready var _layer_brain: MineLayerBrain = $Brain
@onready var _layer_mover: EnemyMover = $EnemyMover
@onready var dispenser: Marker2D = $Dispenser
@onready var _hatch: Sprite2D = $Hatch


func _ready() -> void:
	super._ready()
	add_to_group("enemies")
	_hatch_base_y = _hatch.scale.y
	set_hatch_open(0.0)
	if config:
		_apply_config(config)


func _apply_config(cfg: MineLayerConfig) -> void:
	health.max_health = cfg.max_health
	health.current_health = cfg.max_health
	score_value = cfg.score_value
	if contact_hit_box:
		contact_hit_box.damage = cfg.collision_damage

	_layer_mover.max_speed = cfg.max_speed
	_layer_mover.acceleration = cfg.acceleration
	_layer_mover.max_turn_rate = cfg.max_turn_rate

	_layer_brain.config = cfg


## The rail fallback clock: active only while a rail owns the layer.
func _process(delta: float) -> void:
	if not is_ai_suspended() or config == null:
		return
	_rail_clock += delta
	if _rail_clock >= config.rail_mine_interval:
		_rail_clock -= config.rail_mine_interval
		var mine := drop_mine(EnemyMine.Variant.PROXIMITY, dispenser.global_position)
		if mine != null:
			mine.mine_life = config.assault_mine_life  # a rail is an Assault thing, whatever the tree says


## Takes a mine of `variant` from its pool at the dispenser and launches it so it comes to rest on `rest_point`
## (the Bomber's eject rule: launch at about `2 * distance / eject_time`, decaying linearly to 0). Falls back to the
## PROXIMITY pool when `variant`'s pool is absent or exhausted. Null when nothing could be acquired.
##
## Sets ONLY `arm_delay`, `eject_time` and the life (by mode); every trigger, warning and blast number stays what the
## variant scene authors, so a PULSE mine keeps its blast of 8.
func drop_mine(variant: EnemyMine.Variant, rest_point: Vector2) -> EnemyMine:
	var at := dispenser.global_position
	var mine := _acquire(variant, at)
	if mine == null and variant != EnemyMine.Variant.PROXIMITY:
		mine = _acquire(EnemyMine.Variant.PROXIMITY, at)
	if mine == null:
		return null
	mine.arm_delay = config.mine_arm_delay
	mine.eject_time = config.mine_eject_time
	var lifetime := mine.get_node_or_null("ProjectileLifetime") as ProjectileLifetime
	if EnemyWorld.arena(get_tree()) != null:
		mine.mine_life = config.assault_mine_life
	else:
		mine.mine_life = config.open_space_mine_life
		if lifetime != null:
			lifetime.max_time = config.open_space_mine_backstop
	var to_rest := rest_point - at
	var dist := to_rest.length()
	# The mine moves in discrete ticks and its first tick already decays, so the distance covered is `v * (T - dt) / 2`,
	# not `v * T / 2`: launching at `2d / (T - dt)` is what lands it on the point (a bare `2d / T` stops d * dt / T short).
	var span := config.mine_eject_time - 1.0 / float(Engine.physics_ticks_per_second)
	var speed := 2.0 * dist / span if span > 0.0 else 0.0
	mine.launch(to_rest / dist if dist > 0.0 else Vector2.ZERO, speed, rest_point)
	return mine


func _acquire(variant: EnemyMine.Variant, at: Vector2) -> EnemyMine:
	var pool := _pool_for(variant)
	if pool == null:
		return null
	return pool.acquire(at) as EnemyMine


func _pool_for(variant: EnemyMine.Variant) -> BulletPool:
	var key := String(EnemyMine.Variant.keys()[variant]).capitalize() + "Pool"
	return get_node_or_null(key) as BulletPool


## The dispenser hatch (plan §2.13): `open` 0 is closed over the rack, 1 is open. The hatch is a plate over the rack
## whose `scale.y` collapses toward 0 as it opens, floored at `HATCH_MIN_SCALE` because Godot rejects a zero scale.
## The brain eases `open` between 0 and 1 over `config.hatch_seconds`; tests read `hatch_open()` or `scale.y` with a tolerance.
func set_hatch_open(open: float) -> void:
	_hatch_open = clampf(open, 0.0, 1.0)
	_hatch.scale.y = _hatch_base_y * maxf(1.0 - _hatch_open, HATCH_MIN_SCALE)


func hatch_open() -> float:
	return _hatch_open
