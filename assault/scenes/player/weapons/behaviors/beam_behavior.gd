# assault/scenes/player/weapons/behaviors/beam_behavior.gd
class_name BeamBehavior
extends WeaponBehavior

const _BEAM_SCENE: PackedScene = preload("res://assault/scenes/projectiles/piercing_beam/piercing_beam.tscn")
## Full ray length — covers viewport from any player Y position.
const _RAY_LENGTH: float = 1200.0
## Collision mask for blocking bodies: layer 1 (environment) + 1024 (asteroids).
const _RAY_BLOCK_MASK: int = 1 | 1024

## How fast a target heats up (0→1 in 1/_HEAT_RATE seconds of continuous fire).
const _HEAT_RATE: float = 0.7
## How fast a target cools down (1→0 in 1/_COOL_RATE seconds after laser leaves).
const _COOL_RATE: float = 1.0
## DPS multiplier at full heat — laser triples in power on an overheated target.
const _MAX_DPS_MULT: float = 3.0

## One PiercingBeam visual per muzzle — all share the same far endpoint.
var _beams: Array[PiercingBeam] = []
## Per-target fractional damage accumulator { instance_id: float }
var _accum: Dictionary = {}
## Per-target heat level { instance_id: float 0.0–1.0 }
var _target_heat: Dictionary = {}
## Per-target node reference for modulate updates { instance_id: Node2D }
var _target_nodes: Dictionary = {}

## fire() is unused for BEAM — beam is continuous while shoot held.
func fire(_state: Node, _mode: WeaponModeResource, _muzzle: Marker2D) -> void:
	pass

## Called every physics frame while shoot is held.
## muzzles: all weapon muzzles — each gets its own beam visual to the shared hit point.
func tick(state: Node, mode: WeaponModeResource, muzzles: Array[Marker2D], delta: float) -> void:
	var actor: Node2D = state.get("actor")
	if actor == null:
		return

	## Grow / shrink beam pool to match current muzzle count.
	while _beams.size() < muzzles.size():
		var b: PiercingBeam = _BEAM_SCENE.instantiate()
		state.add_child(b)
		_beams.append(b)
	while _beams.size() > muzzles.size():
		var b: PiercingBeam = _beams.pop_back()
		if b != null and is_instance_valid(b):
			b.queue_free()

	if muzzles.is_empty():
		return

	## Cast one ray forward from the first muzzle to find the shared collision point.
	var ref_pos: Vector2 = muzzles[0].global_position
	var dir: Vector2 = Vector2.UP.rotated(actor.rotation)
	var to: Vector2 = ref_pos + dir * _RAY_LENGTH

	var space := actor.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(ref_pos, to)
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

	## Targets = enemies + asteroids (mining laser damages both).
	var all_targets: Array = []
	all_targets.append_array(actor.get_tree().get_nodes_in_group("enemies"))
	all_targets.append_array(actor.get_tree().get_nodes_in_group("asteroids"))

	var seg_dir: Vector2 = blocker_point - ref_pos
	var seg_len: float = seg_dir.length()
	var _dm = actor.get("damage_multiplier")
	var actor_multiplier: float = _dm if _dm != null else 1.0

	## IDs hit this frame — used to avoid cooling targets that are currently burning.
	var hit_ids: Array = []

	if seg_len > 0.0:
		var seg_unit: Vector2 = seg_dir / seg_len
		for e in all_targets:
			var n := e as Node2D
			if n == null or n == blocker_collider:
				continue
			var rel: Vector2 = n.global_position - ref_pos
			var t: float = rel.dot(seg_unit)
			if t < 0.0 or t > seg_len:
				continue
			var perp: float = abs(rel.dot(seg_unit.rotated(PI / 2.0)))
			if perp > 12.0:
				continue
			var hb := n.get_node_or_null("HurtBox") as HurtBox
			if hb == null:
				continue

			## Heat buildup for this target.
			var id: int = n.get_instance_id()
			hit_ids.append(id)
			var heat: float = minf(1.0, _target_heat.get(id, 0.0) + _HEAT_RATE * delta)
			_target_heat[id] = heat
			_target_nodes[id] = n

			## Tint target from white → red as heat climbs.
			n.modulate = Color(1.0, 1.0 - heat, 1.0 - heat, 1.0)

			## Apply heat-scaled DPS.
			var mult: float = lerpf(1.0, _MAX_DPS_MULT, heat)
			_accumulate_and_apply(hb, mode.beam_dps * delta * actor_multiplier * mult)

	## Draw each beam from its own muzzle to the shared collision point.
	for i: int in muzzles.size():
		_beams[i].set_endpoints(muzzles[i].global_position, blocker_point)

## Gradually cool every tracked target (call each frame when laser is not firing).
func cool_targets(delta: float) -> void:
	var done: Array[int] = []
	for id: int in _target_heat.keys():
		var heat: float = maxf(0.0, _target_heat[id] - _COOL_RATE * delta)
		_target_heat[id] = heat
		var node: Node2D = _target_nodes.get(id) as Node2D
		if node != null and is_instance_valid(node):
			node.modulate = Color(1.0, 1.0 - heat, 1.0 - heat, 1.0)
		if heat <= 0.0:
			done.append(id)
	for id: int in done:
		_target_heat.erase(id)
		_target_nodes.erase(id)

## Free all beam visuals when shoot is released or mode changes.
## Target heat is intentionally kept so cooling continues after release.
func release(_state: Node) -> void:
	for b in _beams:
		if b != null and is_instance_valid(b):
			b.queue_free()
	_beams.clear()
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
