## EnemyMine - the mine family (docs/plans/cmug23omu000lm52wu7rak0q5/3-plan.md §2.1). One script for every
## variant; the variant's numbers (trigger, warning, blast, effect) live in its scene. PROXIMITY is the Bomber's
## `enemy_ordnance/mine.tscn` itself; the other variants are `mines/<variant>_mine.tscn`.
##
## It keeps the `EnemyOrdnance` contract (`expired` once per life, `reset()`, `launch()`, the trigger POLL, a shot
## defuses) and overrides its three mine hooks (`_move_mine`, `_trigger_seen`, `_on_detonated`). A mine is never in
## group `enemies` and never scored.
##
## A HAZARD while it is a live, launched mine: `hazard_info()` returns one `HazardInfo` (kind `&"mine"`, radius
## `trigger_radius + hazard_pad`, `avoid_weight` 1.0, measured in plan §2.3), so enemies steer round it. It
## registers on `launch()`, NOT in `_enter_tree()`: an idle pooled mine sits in the tree (disabled) and would
## otherwise plant a phantom hazard at its pool. It unregisters the moment it starts to fade, in `_mark_done()`
## and in `_exit_tree()`; a reparent of a live mine re-registers in `_enter_tree()`.
##
## HOSTILITY. PLAYER (every mine an enemy lays) is set off only by layer-128 hurtboxes and blasts through
## `ContactBlast`. ALL (placed mines) is also set off by a layer-512 area whose parent is in group `enemies` (a
## ship's hull hurtbox; not a mine, a rocket's box or a plate) and blasts through `Hazards.pulse_damage()`, which
## hurts both sides. The `ProximityArea` mask is set from `hostility` in `launch()`, so a value set after `_ready()`
## still counts.
##
## PLACED (`placed = true`): self-owned (`expired -> queue_free`), backstop off, `mine_life = placed_life`
## (default 0 = never fizzles; never the scene's authored life, which is the Bomber's), and it launches itself. The
## setup is DEFERRED from `_ready()`, so a parent (a `Minefield`) that sets `placed` / `hostility` in its own
## `_ready()` - which runs after its children's - is already seen.
class_name EnemyMine
extends EnemyOrdnance

enum Variant { PROXIMITY, DRIFTING, HOMING, CHAIN, PULSE, EMP }
enum Hostility { PLAYER, ALL }

@export var variant: Variant = Variant.PROXIMITY
@export var hostility: Hostility = Hostility.PLAYER

@export_group("Hazard")
## Added to `trigger_radius` for the avoidance footprint (plan §2.3: 60 keeps a 0.8 ship >= 145 px out).
@export var hazard_pad: float = 60.0
## False: never registers (the tests' control, and a pre-approved lever on `mine.tscn`).
@export var registers_hazard: bool = true

@export_group("Placed")
## A standalone mine: owns itself and launches itself (see the header).
@export var placed: bool = false
## A placed mine's `mine_life`. 0 = never fizzles.
@export var placed_life: float = 0.0

const _MINE_RESET_PROPS: Array[StringName] = [&"hostility", &"hazard_pad", &"registers_hazard", &"placed_life"]

var _info := HazardInfo.new()
var _launched: bool = false
var _registered: bool = false
var _placed_started: bool = false


func _reset_props() -> Array:
	return super() + _MINE_RESET_PROPS


func _ready() -> void:
	super()
	_start_if_placed.call_deferred()


func _enter_tree() -> void:
	if _should_register():
		_register()


func _exit_tree() -> void:
	_unregister()


func reset() -> void:
	super()
	_launched = false
	_unregister()


func launch(dir: Vector2, speed: float, target_point: Vector2) -> void:
	super(dir, speed, target_point)
	_proximity.collision_mask = CollisionLayers.PLAYER_HURTBOX
	if hostility == Hostility.ALL:
		_proximity.collision_mask |= CollisionLayers.ENEMY_HURTBOX
	_launched = true
	_info.kind = &"mine"
	_info.source = self
	_info.radius = trigger_radius + hazard_pad
	_info.avoid_weight = 1.0
	_info.velocity = Vector2.ZERO
	_info.position = global_position
	if _should_register():
		_register()


## Starts the fizzle now: the `fizzle_time` fade, no blast, then one `expired`. A no-op once fading or done.
func retire() -> void:
	if _done or _fizzling:
		return
	_fizzling = true
	_fizzle_clock = 0.0
	_unregister()


func is_fizzling() -> bool:
	return _fizzling


func hazard_info() -> HazardInfo:
	_info.position = global_position if is_inside_tree() else position
	return _info


func _physics_process(delta: float) -> void:
	super(delta)
	if not _registered:
		return
	if _should_register():
		_info.position = global_position
	else:
		_unregister()


func _trigger_seen() -> bool:
	for area in _proximity.get_overlapping_areas():
		if area.collision_layer & CollisionLayers.PLAYER_HURTBOX:
			return true
		if hostility == Hostility.ALL and area.collision_layer & CollisionLayers.ENEMY_HURTBOX:
			var parent := area.get_parent()
			if parent != null and parent.is_in_group(&"enemies"):
				return true
	return false


func _on_detonated() -> void:
	if hostility == Hostility.ALL:
		Hazards.pulse_damage(get_tree(), global_position, blast_radius, blast_damage)
	else:
		ContactBlast.spawn(get_parent(), global_position, blast_radius, blast_damage, blast_frames)


func _mark_done() -> void:
	super()
	_unregister()


func _start_if_placed() -> void:
	if not placed or _placed_started or not is_inside_tree():
		return
	_placed_started = true
	if not expired.is_connected(queue_free):
		expired.connect(queue_free)
	if _lifetime:
		_lifetime.max_time = 0.0
		_lifetime.use_world_rect = false
	mine_life = placed_life
	launch(Vector2.ZERO, 0.0, global_position)


func _should_register() -> bool:
	return _launched and registers_hazard and not _done and not _fizzling


func _register() -> void:
	Hazards.register(self)
	_registered = true


func _unregister() -> void:
	Hazards.unregister(self)
	_registered = false
