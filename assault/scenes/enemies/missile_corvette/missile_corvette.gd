class_name MissileCorvette
extends BaseEnemy

## The Missile Corvette (docs/plans/cmufs7elw001pnm2xr3b6fteb/3-plan.md §2.9; task t7): a wide hull with two launch
## tubes and four rocket racks. A `MissileCorvetteBrain` decides and an `EnemyMover` moves it, driven through
## `BaseEnemy`'s shared brain/mover tick, so this script defines no `_physics_process`.
##
## `_ready()` copies the config onto every node that uses it (the `.tres` wins over the scene). It runs AFTER its
## children's `_ready()`, so the brain builds its `EngagementBudget` on its first tick.
##
## ROCKETS. `DumbPool`, `PursuitPool`, `ClusterPool` and `WarheadPool` are direct children of this root, all with
## `persist_after_owner_death`: `BulletPool` resolves its container as `get_parent().get_parent()`, and a rocket
## already in flight must outlive the corvette that fired it. Their sizes are authored in the scene and gated against
## `EnemyRocketScenes.pool_size_for()` by `tests/integration/test_missile_corvette.gd`.
##
## `fire()` is the one place a rocket is taken from a pool. It sets NO rocket field: arming, speeds and damage are
## the rocket's own (§2.6). This script answers the two duck-typed launcher questions the rocket asks:
## `launch_velocity()` (inherited along the launch direction) and `rocket_clear_radius()` (the hull radius, so the
## rocket arms only once it is clear of the hull and the corvette never hits itself).
##
## RAILS. While an `EnemyPathMover` owns the motion (`is_ai_suspended()`), `velocity` stays 0 because the rail writes
## `global_position`, so the corvette observes the position change per PHYSICS tick (`SceneTree.physics_frame`: a render
## frame can hold zero or several ticks, which would make a per-frame reading jitter) for `launch_velocity()`, and
## `_process` runs the
## fallback clock: a Dumb rocket DOWN every `config.rail_rocket_interval`. Nothing here writes motion.
##
## Spawn with b.missile_corvette().at(x, y). Nothing places it on a rail; the fallback keeps a future `.move()` from
## being silent.

## The hull radius (px): the shared body / hurtbox / contact shape.
const HULL_RADIUS := 40.0
## How far below a rail corvette its fallback rocket is aimed (px).
const RAIL_AIM_RANGE := 600.0

@export var config: MissileCorvetteConfig = load("res://assault/scenes/enemies/missile_corvette/missile_corvette_config.tres")

## Rockets `fire()` could not launch because a pool was exhausted.
var rockets_refused: int = 0

var _rail_clock: float = 0.0
var _last_position: Vector2 = Vector2.ZERO
var _observed_velocity: Vector2 = Vector2.ZERO
var _next_tube: int = 0

@onready var _corvette_brain: MissileCorvetteBrain = $Brain
@onready var _corvette_mover: EnemyMover = $EnemyMover
@onready var _tubes: Array[Marker2D] = [$Tubes/TubeL, $Tubes/TubeR]
@onready var _tube_lights: Array[Sprite2D] = [$Tubes/TubeLightL, $Tubes/TubeLightR]
@onready var _pools: Dictionary = {
	EnemyRocket.Kind.DUMB: $DumbPool,
	EnemyRocket.Kind.PURSUIT: $PursuitPool,
	EnemyRocket.Kind.CLUSTER: $ClusterPool,
	EnemyRocket.Kind.WARHEAD: $WarheadPool,
}


func _ready() -> void:
	super._ready()
	add_to_group("enemies")
	var glow := _build_glow_texture()
	for light in _tube_lights:
		light.texture = glow
	set_tube_glow(0.0)
	_last_position = global_position
	get_tree().physics_frame.connect(_on_physics_frame)
	if config:
		_apply_config(config)


func _apply_config(cfg: MissileCorvetteConfig) -> void:
	health.max_health = cfg.max_health
	health.current_health = cfg.max_health
	score_value = cfg.score_value
	if contact_hit_box:
		contact_hit_box.damage = cfg.collision_damage

	_corvette_mover.max_speed = cfg.max_speed
	_corvette_mover.acceleration = cfg.acceleration
	_corvette_mover.max_turn_rate = cfg.max_turn_rate

	_corvette_brain.config = cfg


## The rail fallback clock (plan §2.9): active only while a rail owns the corvette.
func _process(delta: float) -> void:
	if not is_ai_suspended() or config == null:
		return
	_rail_clock += delta
	if _rail_clock >= config.rail_rocket_interval:
		_rail_clock -= config.rail_rocket_interval
		fire(EnemyRocket.Kind.DUMB, global_position + Vector2.DOWN * RAIL_AIM_RANGE)


## Takes a rocket of `kind` from its pool at the next tube's position and launches it at `aim_point`. Alternates
## tubes. Returns the rocket, or null when the pool is exhausted (counted in `rockets_refused`). Sets no rocket field.
func fire(kind: EnemyRocket.Kind, aim_point: Vector2) -> EnemyRocket:
	var tube := _tubes[_next_tube]
	_next_tube = (_next_tube + 1) % _tubes.size()
	var rocket := (_pools[kind] as BulletPool).acquire(tube.global_position) as EnemyRocket
	if rocket == null:
		rockets_refused += 1
		return null
	rocket.launch((aim_point - tube.global_position).normalized(), aim_point, self)
	return rocket


## The global position of the tube the next `fire()` launches from (the brain aims each rocket from it).
func next_tube_position() -> Vector2:
	return _tubes[_next_tube].global_position


## Duck-typed launcher question (`EnemyRocket.launch`): how fast the corvette is moving. `velocity` under AI; on a
## rail, where `EnemyPathMover` writes the position and `velocity` stays 0, the position change observed over the
## last frame.
func launch_velocity() -> Vector2:
	return _observed_velocity if is_ai_suspended() else velocity


## Duck-typed launcher question: the hull radius, so a rocket arms only once clear of it.
func rocket_clear_radius() -> float:
	return HULL_RADIUS


## Lights both tube lamps: 0 = dark, 1 = full (the telegraph drives it).
func set_tube_glow(amount: float) -> void:
	for light in _tube_lights:
		light.modulate = Color(1.0, 0.45, 0.2, clampf(amount, 0.0, 1.0) * 0.85)


## A soft radial dot, built in code (never scene-authored: the sprite-transparency sweep reads scene textures).
static func _build_glow_texture() -> Texture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color.WHITE)
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 12
	texture.height = 12
	return texture


## One reading per physics tick: the position change since the previous tick over that tick's delta. (A rail writes
## the position in its own `_physics_process`, so between two `physics_frame`s the move is exactly one tick's.)
func _on_physics_frame() -> void:
	_observe_motion(get_physics_process_delta_time())


## The observation itself; also the hand-stepping seam for tests that move the corvette themselves.
func _observe_motion(delta: float) -> void:
	if delta > 0.0:
		_observed_velocity = (global_position - _last_position) / delta
	_last_position = global_position
