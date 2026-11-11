## ModularHull — a modular enemy's coordinator for its parts (Phase 10 §2.2, docs/plans/cmug23oo90029m52wae4clve0/3-plan.md; built in
## t2, `build_mounts()` arrives in t3). A `Node` child of the host root named `ModularHull`.
##
## In `_ready()` it collects the `EnemyModule`s that are direct children of the sibling `Modules` node (`Modules/*`, tree order) and
## connects their signals. It forwards `hull_share` of every hit a part takes to the host's `Health` child (in the same call as the
## hit), re-emits `module_damaged` / `module_destroyed`, and answers queries. It holds no gameplay rule of any enemy: what losing a
## part means (an attack gone, slower turning, an exposed core) is the host's, so a later phase can swap the consequence driver behind
## this seam (Ph18).
##
## Tests: tests/integration/test_enemy_module.gd.
class_name ModularHull
extends Node

## Re-emitted for each part's `destroyed`, after it.
signal module_destroyed(module: EnemyModule)
## Re-emitted for each part's `damaged`, after the `hull_share` forwarding.
signal module_damaged(module: EnemyModule, amount: int)

var _modules: Array[EnemyModule] = []
var _host_health: Health


func _ready() -> void:
	var host := get_parent()
	if host == null:
		return
	_host_health = host.get_node_or_null(^"Health") as Health
	var holder := host.get_node_or_null(^"Modules")
	if holder == null:
		return
	for child in holder.get_children():
		var part := child as EnemyModule
		if part == null:
			continue
		_modules.append(part)
		part.damaged.connect(_on_module_damaged)
		part.destroyed.connect(_on_module_destroyed)


## Every part, in tree order (wrecks included).
func modules() -> Array[EnemyModule]:
	return _modules.duplicate()


## The part with [param id], or null.
func module(id: StringName) -> EnemyModule:
	for part in _modules:
		if part.module_id == id:
			return part
	return null


## The parts of [param role] that are not wrecks, in tree order.
func live(role: EnemyModule.Role) -> Array[EnemyModule]:
	var out: Array[EnemyModule] = []
	for part in _modules:
		if part.role == role and not part.is_destroyed():
			out.append(part)
	return out


## How many parts whose role is in [param roles] are wrecks; an empty [param roles] counts every role.
func destroyed_count(roles: Array = []) -> int:
	var n := 0
	for part in _modules:
		if part.is_destroyed() and (roles.is_empty() or roles.has(part.role)):
			n += 1
	return n


## The mounts attached to the part with [param id]; empty when there is no such part.
func mounts_of(id: StringName) -> Array[TurretMount]:
	var part := module(id)
	if part == null:
		var none: Array[TurretMount] = []
		return none
	return part.mounts()


func _on_module_damaged(part: EnemyModule, amount: int) -> void:
	if part.hull_share > 0.0 and _host_health != null:
		var share := roundi(float(amount) * part.hull_share)
		if share > 0:
			_host_health.decrease(share)
	module_damaged.emit(part, amount)


func _on_module_destroyed(part: EnemyModule) -> void:
	module_destroyed.emit(part)
