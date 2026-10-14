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
## Sizing guidance:
##   pool_size >= ceil(max_bullet_lifetime / fire_interval) + a small margin.
##   EnemyBullet expires at the 740×740 arena edge (not the viewport edge), so
##   max_lifetime ≈ arena_diagonal / bullet_speed ≈ 1047 / 250 ≈ 4.2 s.
##   E.g. forward fighters: 1047/420 / 0.3s ≈ 9 → pool_size 20 is comfortable.
##
## Cleanup on exit:
##   _exit_tree() calls queue_free() on every in-flight bullet still owned by
##   this pool. Without this, bullets orphaned in the container when the enemy
##   ship is killed never expire (their recycle callback targets a freed pool)
##   and accumulate until the scene restarts.
##
## Outliving the owner (`persist_after_owner_death`):
##   With the flag on, _exit_tree() hands every in-flight bullet over instead of freeing it. The
##   pool disconnects its recycle callable, the bullet becomes self-owned (`expired -> queue_free`,
##   one-shot) and leaves _active, so exactly one owner holds it at every instant. A bullet whose
##   `expired` already fired this frame (its deferred recycle is queued) is freed on the spot, since
##   nothing would ever emit `expired` for it again. Used by ordnance that must outlast its ship
##   (a bomber's mines). `cancel_active()` ignores the flag.
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
## When true, bullets still in flight when this pool leaves the tree keep flying and free themselves
## on their own `expired`, instead of being freed with the owner. Default false: rounds vanish with
## their shooter.
@export var persist_after_owner_death: bool = false

var _idle: Array[Node] = []
## Tracks every in-flight bullet so _exit_tree can clean them up.
var _active: Array[Node] = []
var _container: Node
## The recycle Callable connected to each bullet's `expired`, kept so it can be disconnected on handover.
var _recycle_calls: Dictionary = {}
## In-flight bullets whose `expired` has fired and whose deferred _recycle has not run yet.
var _expired_pending: Dictionary = {}

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
		var recycle_call: Callable = _on_bullet_expired.bind(bullet)
		_recycle_calls[bullet] = recycle_call
		bullet.expired.connect(recycle_call)
		_idle.append(bullet)

## Returns an idle bullet placed at spawn_pos, already reset and enabled.
## Returns null and logs a warning if all bullets are currently in flight —
## increase pool_size on the owning ship if this fires regularly.
func acquire(spawn_pos: Vector2) -> Node:
	if _idle.is_empty():
		push_warning("[BulletPool] Pool exhausted (%s) — increase pool_size" \
				% bullet_scene.resource_path.get_file())
		return null
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

func _on_bullet_expired(bullet: Node) -> void:
	_expired_pending[bullet] = true
	call_deferred("_recycle", bullet)

## Called (deferred) when a bullet's `expired` signal fires.
## Private — ships never call this directly.
func _recycle(bullet: Node) -> void:
	_expired_pending.erase(bullet)
	# Ignore a bullet this pool does not own: one already recycled (`expired` fired twice in the same
	# frame, hit + off-screen), or one handed over / cancelled in the frame the owner died.
	if not _active.has(bullet):
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

## Frees every bullet currently in flight and clears the active list.
##
## NOTE this permanently SHRINKS the pool. _recycle() is the only path back into
## _idle, and this frees the bullets instead, so capacity is not recovered —
## acquire() keeps working only while _idle is non-empty.
##
## Called by _exit_tree(), and directly by a ship that must stop being dangerous
## before it leaves the tree. StationGunnery._stop() uses it on the boss's death:
## the wreck lingers for its death sequence, so _exit_tree() no longer fires at
## the moment of death and a dead station would otherwise keep a full ring of
## live bullets in the air.
func cancel_active() -> void:
	for bullet: Node in _active:
		if is_instance_valid(bullet):
			bullet.queue_free()
	_active.clear()

## Releases every in-flight bullet to its own devices (`persist_after_owner_death`).
func _hand_over_active() -> void:
	for bullet: Node in _active:
		if not is_instance_valid(bullet):
			continue
		var recycle_call: Callable = _recycle_calls.get(bullet, Callable())
		if recycle_call.is_valid() and bullet.expired.is_connected(recycle_call):
			bullet.expired.disconnect(recycle_call)
		_recycle_calls.erase(bullet)
		if _expired_pending.has(bullet):
			# Already expired this frame; no further `expired` will come, so it ends here.
			bullet.queue_free()
		else:
			bullet.expired.connect(bullet.queue_free, CONNECT_ONE_SHOT)
	_expired_pending.clear()
	_active.clear()

## When the enemy ship is destroyed, free every bullet still in flight — or, with
## `persist_after_owner_death`, hand them over to their own lifetime.
## Without this, bullets orphaned in the container have no live pool to
## return to (the expired callback targets a freed object and is silently
## dropped), so they accumulate until the scene reloads.
func _exit_tree() -> void:
	if persist_after_owner_death:
		_hand_over_active()
	else:
		cancel_active()
