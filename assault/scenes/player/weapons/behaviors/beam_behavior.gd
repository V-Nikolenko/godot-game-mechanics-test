# assault/scenes/player/weapons/behaviors/beam_behavior.gd
class_name BeamBehavior
extends WeaponBehavior

const _BEAM_SCENE: PackedScene = preload("res://assault/scenes/projectiles/piercing_beam/piercing_beam.tscn")
## Full ray length — covers viewport from any player Y position.
const _RAY_LENGTH: float = 1200.0
## Collision mask for blocking bodies: layer 1 (environment) + 1024 (asteroids).
const _RAY_BLOCK_MASK: int = 1 | 1024

var _beam: PiercingBeam = null
## Per-target fractional damage accumulator { instance_id: float }
var _accum: Dictionary = {}

## fire() is unused for BEAM — beam is continuous while shoot held.
func fire(_state: Node, _mode: WeaponModeResource, _muzzle: Marker2D) -> void:
	pass

## Called every physics frame while shoot is held.
func tick(state: Node, mode: WeaponModeResource, muzzle: Marker2D, delta: float) -> void:
	var actor: Node2D = state.get("actor")
	if actor == null:
		return

	if _beam == null or not is_instance_valid(_beam):
		_beam = _BEAM_SCENE.instantiate()
		state.add_child(_beam)

	var from: Vector2 = muzzle.global_position
	var dir: Vector2 = Vector2.UP.rotated(actor.rotation)
	var to: Vector2 = from + dir * _RAY_LENGTH

	# Raycast to find first blocker (asteroid or undamaged ram-ship)
	var space := actor.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.collision_mask = _RAY_BLOCK_MASK
	var blocker_point: Vector2 = to
	var blocker_collider: Object = null
	var hit: Dictionary = space.intersect_ray(query)
	if not hit.is_empty():
		var coll: Object = hit.get("collider", null) as Object
		var is_block := true
		if coll != null and coll.has_method("is_laser_blocking"):
			is_block = coll.is_laser_blocking()
		if is_block:
			blocker_point = hit.get("position", to)
			blocker_collider = coll

	# Damage every enemy whose center is within ~12 px of the beam segment
	var enemies := actor.get_tree().get_nodes_in_group("enemies")
	var seg_dir: Vector2 = blocker_point - from
	var seg_len: float = seg_dir.length()
	if seg_len > 0.0:
		var seg_unit: Vector2 = seg_dir / seg_len
		var actor_multiplier: float = actor.get("damage_multiplier") if actor != null else 1.0
		var dmg_this_frame: float = mode.beam_dps * delta * actor_multiplier
		for e in enemies:
			var n := e as Node2D
			if n == null or n == blocker_collider:
				continue
			var rel: Vector2 = n.global_position - from
			var t: float = rel.dot(seg_unit)
			if t < 0.0 or t > seg_len:
				continue
			var perp: float = abs(rel.dot(seg_unit.rotated(PI / 2.0)))
			if perp > 12.0:
				continue
			var hb := n.get_node_or_null("HurtBox") as HurtBox
			if hb == null:
				continue
			_accumulate_and_apply(hb, dmg_this_frame)

	_beam.set_endpoints(from, blocker_point)

## Free the beam visual when shoot is released or mode changes.
func release(_state: Node) -> void:
	if _beam != null and is_instance_valid(_beam):
		_beam.queue_free()
	_beam = null
	_accum.clear()

## Accumulates fractional DPS damage to avoid sub-integer loss at 60 FPS.
func _accumulate_and_apply(hb: HurtBox, amount: float) -> void:
	var key := hb.get_instance_id()
	var v: float = _accum.get(key, 0.0) + amount
	var whole: int = int(v)
	if whole > 0:
		hb.received_damage.emit(whole)
		v -= float(whole)
	_accum[key] = v
