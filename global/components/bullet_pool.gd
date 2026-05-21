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
## Auto-growth:
##   If all bullets are in flight when acquire() is called, the pool creates one
##   extra bullet on the fly instead of dropping the shot. The pool never shrinks,
##   so it converges to the natural high-water mark for the fire pattern.
##
## Cleanup on exit:
##   _exit_tree() calls queue_free() on every in-flight bullet still owned by
##   this pool. Without this, bullets orphaned in the container when the enemy
##   ship is killed never expire (their recycle callback targets a freed pool)
##   and accumulate until the scene restarts.
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
## Tracks every in-flight bullet so _exit_tree can clean them up.
var _active: Array[Node] = []
var _container: Node

func _ready() -> void:
	# Resolve the active container: pool's parent is the ship,
	# ship's parent is the level container (e.g. enemy_container).
	_container = get_parent().get_parent()
	_prewarm()

func _prewarm() -> void:
	for i: int in pool_size:
		_idle.append(_create_bullet())

## Creates one bullet, wires its expired signal, and returns it idle.
## Used by both _prewarm and the auto-grow path in acquire().
func _create_bullet() -> Node:
	var bullet: Node = bullet_scene.instantiate()
	bullet.process_mode = Node.PROCESS_MODE_DISABLED
	bullet.visible = false
	add_child(bullet)
	bullet.expired.connect(func(): call_deferred("_recycle", bullet))
	return bullet

## Returns an idle bullet placed at spawn_pos, already reset and enabled.
## If all bullets are currently in flight the pool grows by one rather than
## dropping the shot (no more "Pool exhausted" warnings in normal play).
func acquire(spawn_pos: Vector2) -> Node:
	if _idle.is_empty():
		# Auto-grow: create one extra bullet so no shot is ever dropped.
		# This converges to the natural high-water mark for the fire pattern.
		_idle.append(_create_bullet())
	var bullet: Node = _idle.pop_back()
	bullet.reparent(_container, false)
	bullet.global_position = spawn_pos
	# Pool resets state before handing the bullet to the ship.
	if bullet.has_method("reset"):
		bullet.reset()
	bullet.process_mode = Node.PROCESS_MODE_INHERIT
	bullet.visible = true
	_active.append(bullet)
	return bullet

## Called automatically when a bullet's `expired` signal fires.
## Private — ships never call this directly.
func _recycle(bullet: Node) -> void:
	# Guard against `expired` firing twice in the same frame (hit + off-screen).
	if _idle.has(bullet):
		return
	_active.erase(bullet)
	bullet.visible = false
	bullet.process_mode = Node.PROCESS_MODE_DISABLED
	if not is_queued_for_deletion():
		bullet.reparent(self, false)
		_idle.append(bullet)
	else:
		# This pool's owner ship is being freed — discard the bullet too.
		bullet.queue_free()

## When the enemy ship is destroyed, free every bullet still in flight.
## Without this, bullets orphaned in the container have no live pool to
## return to (the expired callback targets a freed object and is silently
## dropped), so they accumulate until the scene reloads.
func _exit_tree() -> void:
	for bullet: Node in _active:
		if is_instance_valid(bullet):
			bullet.queue_free()
	_active.clear()
