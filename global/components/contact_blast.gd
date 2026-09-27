## ContactBlast — the short-lived damage area an EXPLOSIVE `ContactProfile` leaves behind.
##
## Built in code by `spawn()`, never scene-authored. It is a separate node from the drone that set
## it off, re-homed into the drone's parent exactly as `ExplosionEffect` re-homes its particles,
## because both detonation triggers (contact, death) free the drone in the same frame: a child blast
## would be freed before any physics step could report it (docs/plans/cmufs7ek60001nm2x6d0bt2et/
## 3-plan.md §2.3, epic review B1).
##
## - Layer 256 (`enemy_hitbox`), mask 0: the player's `HurtBox` (mask 1281) detects it through its
##   own `area_entered`, exactly like an `EnemyBullet`. It never hits other enemies.
## - Monitorable from the moment it enters the tree, so the first physics step after the message
##   flush sees it; no deferred toggling.
## - It owns its lifetime: `frames` physics frames (minimum 2) on its own counter, then
##   `queue_free()`. Never `create_timer()` — a timer outlives a freed test tree and leaks.
class_name ContactBlast
extends HitBox

## Below 2 the blast is freed in the iteration after the step that created its pair, before
## `flush_queries` reports the overlap.
const MIN_FRAMES := 2

var _at: Vector2 = Vector2.ZERO
var _frames: int = 3
var _frames_alive: int = 0


## Builds a blast and parents it to [param container] at the next message flush, at the global
## position [param at]. Safe to call from inside an `area_entered` callback, where adding a physics
## body synchronously is refused ("Can't change this state while flushing queries").
##
## The deferred call is made on the BLAST, not `container.add_child.call_deferred(blast)`: a
## deferred call whose target is freed first is silently dropped, and the orphan blast would leak.
## `_attach()` frees the blast instead when the container is gone.
static func spawn(container: Node, at: Vector2, radius: float, damage: int, frames: int) -> ContactBlast:
	var blast := ContactBlast.new()
	blast.name = "ContactBlast"
	blast.collision_layer = CollisionLayers.ENEMY_HITBOX
	blast.collision_mask = 0
	blast.monitorable = true
	blast.monitoring = false
	blast.damage = damage
	blast.damage_type = HitBox.DamageType.CONTACT
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	blast.add_child(shape)
	blast._at = at
	blast._frames = maxi(frames, MIN_FRAMES)
	blast._attach.call_deferred(container)
	return blast


## Untyped on purpose: a typed `Node` parameter makes the deferred call itself fail on a freed
## container ("Cannot convert argument 1 from Object to Object") before this body can clean up.
## `queue_free()`, not `free()`: an object cannot free itself from inside its own deferred call.
func _attach(container) -> void:
	if is_instance_valid(container) and (container as Node).is_inside_tree():
		(container as Node).add_child(self)
	else:
		queue_free()


## Position after parenting: a parentless Node2D's `global_position` is only its local position,
## so setting it before `add_child()` would re-apply the container's transform on top.
func _enter_tree() -> void:
	global_position = _at


func _physics_process(_delta: float) -> void:
	if is_queued_for_deletion():
		return
	_frames_alive += 1
	if _frames_alive >= _frames:
		queue_free()
