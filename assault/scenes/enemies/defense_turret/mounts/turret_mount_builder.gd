## TurretMountBuilder - the one place a `TurretMount` and its `BulletPool`s are built (docs/plans/cmug23oo90029m52wae4clve0/3-plan.md §2.3;
## Phase 10 t3). Extracted unchanged from `DefenseTurret._build_mounts()`'s loop body so a ship module (`ModularHull.build_mounts()`) builds mounts
## exactly as a turret does.
##
## `build()` instantiates the slot's variant scene (or [param variant_override] when >= 0), copies the slot's `rest_bearing_deg` (or
## [param bearing_override] when not NAN), a non-negative `turn_rate_override` and `traverse_deg_override`, hands the mount [param rng] and
## [param telegraph_gate], adds it under the slot, builds each `pool_specs()` pool as a **root child of [param host]** named
## `"<spec name>_<index>"` (so rounds land in the host's container and the names are unique over one running index) and calls `setup()`.
## Returns null, with a warning, for a variant that has no scene.
class_name TurretMountBuilder
extends RefCounted


static func build(host: Node2D, slot: TurretMountSlot, index: int, rng: RandomNumberGenerator, owner_group: StringName,
		telegraph_gate: Callable = Callable(), variant_override: int = -1, bearing_override: float = NAN) -> TurretMount:
	var wanted: int = variant_override if variant_override >= 0 else int(slot.variant)
	var scene := TurretMountScenes.scene_for(wanted)
	if scene == null:
		push_warning("TurretMountBuilder: mount variant %d is not built yet; slot %s stays empty" % [wanted, slot.name])
		return null
	var mount := scene.instantiate() as TurretMount
	mount.rest_bearing_deg = slot.rest_bearing_deg if is_nan(bearing_override) else bearing_override
	if slot.turn_rate_override >= 0.0:
		mount.turn_rate = slot.turn_rate_override
	if slot.traverse_deg_override >= 0.0:
		mount.traverse_deg = slot.traverse_deg_override
	mount.rng = rng
	mount.telegraph_gate = telegraph_gate
	slot.add_child(mount)
	var pools := {}
	for spec in mount.pool_specs():
		var pool := BulletPool.new()
		pool.name = "%s_%d" % [spec["name"], index]
		pool.bullet_scene = spec["scene"]
		pool.pool_size = spec["size"]
		pool.persist_after_owner_death = spec["persist"]
		host.add_child(pool)
		pools[spec["name"]] = pool
	mount.setup(host, pools, owner_group)
	return mount
