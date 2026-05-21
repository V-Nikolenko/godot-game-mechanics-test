class_name BigAsteroid
extends AsteroidBase

## Assign small_asteroid.tscn here once that scene is created.
@export var split_scene: PackedScene

@export var split_min: int = 2
@export var split_max: int = 4
## Fallback absolute speed used when this big asteroid has no inherited motion
## (e.g. it was spawned at rest before any movement could update its position).
@export var split_fallback_speed: float = 70.0
## Fraction of the parent's last known speed applied to each shard.
## 0.5 → shards continue in roughly the same direction at half speed.
@export_range(0.1, 1.0, 0.05) var split_speed_factor: float = 0.5
## Max angular spread (radians) applied randomly to each shard around the
## inherited direction. Small value keeps shards in a tight cone.
@export var split_cone_spread: float = 0.35  # ~±20°

# Sampled in _process so we know how the big asteroid was moving at the
# moment it died. EnemyPathMover sets global_position directly (without
# touching velocity), so we can't read `velocity` here.
var _prev_pos: Vector2
var _last_velocity: Vector2 = Vector2.DOWN * 70.0

func _ready() -> void:
	super._ready()
	_prev_pos = global_position

func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	var v: Vector2 = (global_position - _prev_pos) / delta
	if v.length_squared() > 1.0:
		_last_velocity = v
	_prev_pos = global_position

func _on_destroyed() -> void:
	if split_scene == null:
		return
	var parent: Node = get_parent()
	if parent == null:
		return

	# Shards inherit the parent's direction at a reduced speed. If we never
	# saw measurable motion (e.g. spawned and killed within a frame), fall
	# back to "downward" which matches every Level 1 asteroid trajectory.
	var inherited_speed: float = _last_velocity.length() * split_speed_factor
	var shard_speed: float = maxf(inherited_speed, split_fallback_speed * split_speed_factor)
	var base_dir: Vector2 = (
		_last_velocity.normalized() if _last_velocity.length_squared() > 1.0
		else Vector2.DOWN
	)

	var count: int = randi_range(split_min, split_max)
	for i in count:
		var small: SmallAsteroid = split_scene.instantiate() as SmallAsteroid
		small.global_position = global_position
		var spread: float = randf_range(-split_cone_spread, split_cone_spread)
		# drift_velocity is consumed by SmallAsteroid._physics_process for
		# direct global_position movement — bypassing move_and_slide which
		# could be inert depending on physics layer setup.
		small.drift_velocity = base_dir.rotated(spread) * shard_speed
		parent.call_deferred("add_child", small)
		# ScoreTracker needs to know about this shard so killing it awards
		# points. Wave membership is -1 (no wave clear bonus contribution).
		# _announce_shard is deferred on SELF so it runs AFTER add_child
		# (both deferred calls land in the same message queue in FIFO order,
		# and add_child was queued first).  This ensures _ready() has run and
		# the shard is properly in the tree when ScoreTracker connects to it.
		call_deferred("_announce_shard", small)


## Deferred companion to _on_destroyed — fires after add_child so the shard
## is fully initialised in the scene tree before ScoreTracker registers it.
func _announce_shard(shard: Node) -> void:
	if is_instance_valid(shard):
		EventBus.enemy_spawned_orphan.emit(shard)
