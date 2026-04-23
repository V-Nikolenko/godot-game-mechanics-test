## BulletPool — pre-allocates a fixed number of bullets and recycles them.
##
## How it works:
##   - On _ready(), instantiates pool_size bullets as idle children of this node.
##   - Each bullet's `expired` signal is connected to _recycle() — the pool
##     observes bullets; bullets have no knowledge of the pool.
##   - Active bullets are reparented to the level container so they travel
##     independently of the ship. Idle bullets stay here (disabled + invisible).
##   - When expired fires, the pool resets and reclaims the bullet automatically.
##
## Usage from a ship:
##   1. Create a BulletPool node, set bullet_scene and pool_size.
##   2. add_child(bullet_pool) — _ready() handles all setup automatically.
##   3. Call acquire(spawn_pos) to get a ready bullet.
##   4. Configure direction/rotation on the returned bullet — pool already
##      called reset() on it.
##
## Container resolution:
##   The pool expects to be a grandchild of the active container
##   (pool → ship → container). This matches the wave-manager scene hierarchy.
class_name BulletPool
extends Node

@export var bullet_scene: PackedScene
@export var pool_size: int = 10

var _idle: Array[Node] = []
var _container: Node

func _ready() -> void:
	# Resolve the active container: pool's parent is the ship,
	# ship's parent is the level container (e.g. enemy_container).
	_container = get_parent().get_parent()
	_prewarm()

func _prewarm() -> void:
	for i: int in pool_size:
		var bullet: Node = bullet_scene.instantiate()
		bullet.process_mode = Node.PROCESS_MODE_DISABLED
		bullet.visible = false
		add_child(bullet)
		# Pool subscribes to the bullet's expired signal — bullet stays pool-agnostic.
		# Defer the recycle call to avoid "during a physics callback" errors when
		# expired fires from _on_hit_box_area_entered().
		bullet.expired.connect(func(): call_deferred("_recycle", bullet))
		_idle.append(bullet)

## Returns an idle bullet placed at spawn_pos, already reset and enabled.
## Returns null and logs a warning if all bullets are currently in flight.
func acquire(spawn_pos: Vector2) -> Node:
	if _idle.is_empty():
		push_warning("[BulletPool] Pool exhausted (%s)" % bullet_scene.resource_path.get_file())
		return null
	var bullet: Node = _idle.pop_back()
	bullet.reparent(_container, false)
	bullet.global_position = spawn_pos
	# Pool resets state before handing the bullet to the ship.
	if bullet.has_method("reset"):
		bullet.reset()
	bullet.process_mode = Node.PROCESS_MODE_INHERIT
	bullet.visible = true
	return bullet

## Called automatically when a bullet's `expired` signal fires.
## Private — ships never call this directly.
func _recycle(bullet: Node) -> void:
	# Guard against `expired` firing twice in the same frame (hit + off-screen).
	if _idle.has(bullet):
		return
	bullet.visible = false
	bullet.process_mode = Node.PROCESS_MODE_DISABLED
	if not is_queued_for_deletion():
		bullet.reparent(self, false)
		_idle.append(bullet)
	else:
		# This pool's owner ship is being freed — discard the bullet too.
		bullet.queue_free()
