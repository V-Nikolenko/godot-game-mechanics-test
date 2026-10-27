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

@export_group("Drifting")
## DRIFTING: px/s along the launch direction (or `drift_direction`), from the end of the eject.
@export var drift_speed: float = 35.0
## DRIFTING: the direction a PLACED mine drifts in (a launched mine takes its launch direction). ZERO = still.
@export var drift_direction: Vector2 = Vector2.ZERO
## DRIFTING: > 0 ping-pongs within this distance of its start and never fizzles on distance (placed fields).
@export var drift_leash: float = 0.0
## DRIFTING with no leash: fizzles once it has travelled this far.
@export var drift_max_distance: float = 1400.0

@export_group("Homing")
## HOMING: notices the player inside this radius.
@export var notice_radius: float = 260.0
## HOMING: creep speed. Any player faster than this outruns it.
@export var home_speed: float = 60.0
@export var home_turn_rate: float = 2.0
## HOMING: stops creeping when the player is beyond this.
@export var home_lose_radius: float = 380.0
## HOMING: holds once this far from its launch point.
@export var home_max_distance: float = 900.0

@export_group("Chain")
## CHAIN: a detonation sets off every live mine whose centre is within this radius.
@export var chain_radius: float = 150.0
## CHAIN: seconds from a detonation to each chained mine's own (no warning; a chain is physical).
@export var chain_delay: float = 0.2
## A shot detonates the mine (CHAIN) instead of defusing it.
@export var shot_detonates: bool = false

@export_group("Pulse")
## PULSE: a detonation disrupts every player whose centre is within this radius (plan §2.7).
@export var pulse_radius: float = 170.0
## PULSE: the boost-disruption strength (efficiency becomes 1 - strength) and its seconds.
@export var disrupt_strength: float = 0.6
@export var disrupt_seconds: float = 2.5

@export_group("EMP")
## EMP: a detonation reaches every player whose centre is within this radius, through `EmpPulse` (plan §2.8). The scene
## authors `blast_damage` 0, so no `ContactBlast` and no `pulse_damage` follow it.
@export var emp_radius: float = 190.0
@export var emp_seconds: float = 2.0

## Seconds between two recomputations of a chain mine's links.
const LINK_REFRESH := 0.5
const LINK_COLOR := Color(1.0, 0.55, 0.15, 0.35)

const _MINE_RESET_PROPS: Array[StringName] = [
	&"hostility", &"hazard_pad", &"registers_hazard", &"placed_life",
	&"drift_speed", &"drift_direction", &"drift_leash", &"drift_max_distance",
	&"notice_radius", &"home_speed", &"home_turn_rate", &"home_lose_radius", &"home_max_distance",
	&"chain_radius", &"chain_delay", &"shot_detonates",
	&"pulse_radius", &"disrupt_strength", &"disrupt_seconds",
	&"emp_radius", &"emp_seconds",
]

var _info := HazardInfo.new()
## Velocity the mine's PARENT gives it (a moving `Minefield` carries its mines): added to its own motion in the
## `HazardInfo`, so the avoidance stage leads a carried mine too. The mine never moves itself by it.
var carry_velocity: Vector2 = Vector2.ZERO : set = set_carry_velocity
var _own_velocity: Vector2 = Vector2.ZERO
var _launched: bool = false
var _registered: bool = false
var _placed_started: bool = false
## DRIFTING: the unit drift direction, the distance travelled since the eject, and the signed leash offset.
var _drift_dir: Vector2 = Vector2.ZERO
var _drift_travelled: float = 0.0
var _drift_offset: float = 0.0
var _drift_sign: float = 1.0
## HOMING: where it was launched (global), and whether it currently has the player.
var _home_origin: Vector2 = Vector2.ZERO
var _noticing: bool = false
## CHAIN: set off by a neighbour (`chain_trigger()`), the seconds it waits, and its own clock for them.
var _chained: bool = false
var _chain_wait: float = 0.0
var _chain_clock: float = 0.0
## CHAIN: the neighbours it links to, refreshed every `LINK_REFRESH` seconds of its own clock.
var _link_mines: Array = []
var _link_clock: float = 0.0


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
	_drift_dir = Vector2.ZERO
	_drift_travelled = 0.0
	_drift_offset = 0.0
	_drift_sign = 1.0
	_noticing = false
	_clear_chain()
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
	_set_velocity(Vector2.ZERO)
	_info.position = global_position
	_drift_travelled = 0.0
	_drift_offset = 0.0
	_drift_sign = 1.0
	_noticing = false
	_clear_chain()
	_home_origin = global_position
	_drift_dir = (dir if dir != Vector2.ZERO else drift_direction).normalized()
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


## Sets this mine off [param delay] seconds (of its own clock) from now. No warning, armed or not: a chain is
## physical. Ignored once done, fading, not launched, or already chained (the first delay stands).
func chain_trigger(delay: float) -> void:
	if _done or _fizzling or _chained or not _launched:
		return
	_chained = true
	_chain_wait = maxf(delay, 0.0)
	_chain_clock = 0.0


func is_chained() -> bool:
	return _chained


## Global positions of the live mines within `chain_radius` of this CHAIN mine, as of its last refresh (every
## `LINK_REFRESH` s); the "fuse links" it draws. Empty for any other variant.
func link_points() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for m in _link_mines:
		if is_instance_valid(m) and not m._done and not m._fizzling:
			out.append(m.global_position)
	return out


## The other live mines whose CENTRE is within `chain_radius`. `Hazards.around()` includes each mine's footprint
## (trigger + pad), so the centre distance decides. Untyped on purpose: a script that names its own `class_name`
## (`Array[EnemyMine]`, `as EnemyMine`) is a reference cycle the engine reports as a leak at exit.
func _chain_neighbours() -> Array:
	var out: Array = []
	for info: HazardInfo in Hazards.around(global_position, chain_radius):
		var other := info.source as EnemyOrdnance
		if other == null or other == self or not other.has_method(&"chain_trigger") or other._done or other._fizzling:
			continue
		if global_position.distance_to(other.global_position) <= chain_radius:
			out.append(other)
	return out


func _refresh_links() -> void:
	_link_mines = _chain_neighbours()


func _clear_chain() -> void:
	_chained = false
	_chain_wait = 0.0
	_chain_clock = 0.0
	_link_mines.clear()
	_link_clock = 0.0


## A chained mine ignores its trigger, warning and fizzle: it goes off when its chain delay has run.
func _update_trigger(delta: float) -> void:
	if _chained and not _fizzling:
		_chain_clock += delta
		if _chain_clock >= _chain_wait:
			_detonate()
		return
	super(delta)


## A CHAIN mine's blast sets off every neighbour; any other variant propagates nothing.
func _propagate_chain() -> void:
	for other in _chain_neighbours():
		other.chain_trigger(chain_delay)


## A shot detonates a `shot_detonates` mine (CHAIN) instead of defusing it.
func _on_health_changed(current_health: int) -> void:
	if current_health <= 0 and shot_detonates and not _fizzling:
		_detonate()
		return
	super(current_health)


## Motion by variant. DRIFTING and HOMING write `position` only (a hazard, never a ship's velocity), so a moving
## parent carries them and the Assault corridor needs no physics. Every other variant keeps the eject-then-still rule.
func _move_mine(delta: float) -> void:
	super(delta)
	if _fizzling or _done:
		_set_velocity(Vector2.ZERO)
		return
	match variant:
		Variant.DRIFTING:
			_drift(delta)
		Variant.HOMING:
			_creep(delta)


## DRIFTING: `drift_speed` along the direction once the eject is over. Unleashed, it fizzles at `drift_max_distance`;
## leashed, it ping-pongs within `drift_leash` of where it started and never fizzles on distance.
func _drift(delta: float) -> void:
	_set_velocity(Vector2.ZERO)
	if _drift_dir == Vector2.ZERO or _clock <= eject_time:
		return
	var live := minf(delta, _clock - eject_time)
	var step := drift_speed * live
	if drift_leash > 0.0:
		var next := _drift_offset + step * _drift_sign
		if absf(next) > drift_leash:
			next = clampf(next, -drift_leash, drift_leash)
			_drift_sign = -_drift_sign
		_set_velocity(_drift_dir * drift_speed * _drift_sign)
		position += _drift_dir * (next - _drift_offset)
		_drift_offset = next
		return
	step = minf(step, maxf(drift_max_distance - _drift_travelled, 0.0))
	position += _drift_dir * step
	_drift_travelled += step
	_set_velocity(_drift_dir * drift_speed)
	if _drift_travelled >= drift_max_distance:
		retire()


## HOMING: once armed it notices a player within `notice_radius`, creeps toward them at `home_speed` (turning at
## `home_turn_rate`) until they are past `home_lose_radius`, and holds `home_max_distance` from where it was launched.
func _creep(delta: float) -> void:
	_set_velocity(Vector2.ZERO)
	if not is_armed():
		return
	var target := TargetInfo.player(get_tree())
	if not target.has_target:
		_noticing = false
		return
	var gap := global_position.distance_to(target.position)
	if _noticing and gap > home_lose_radius:
		_noticing = false
	elif not _noticing and gap <= notice_radius:
		_noticing = true
	if not _noticing:
		return
	_heading = Steering.turn_toward(_heading, target.position - global_position, home_turn_rate, delta)
	var next := global_position + _heading * home_speed * delta
	var from_origin := next - _home_origin
	if from_origin.length() > home_max_distance:
		next = _home_origin + from_origin.normalized() * home_max_distance
	if global_position.distance_to(_home_origin) >= home_max_distance - 0.001 and from_origin.length() >= home_max_distance:
		return
	_set_velocity((next - global_position) / delta)
	global_position = next


func set_carry_velocity(value: Vector2) -> void:
	carry_velocity = value
	_info.velocity = _own_velocity + value


func _set_velocity(own: Vector2) -> void:
	_own_velocity = own
	_info.velocity = own + carry_velocity


func hazard_info() -> HazardInfo:
	_info.position = global_position if is_inside_tree() else position
	return _info


func _physics_process(delta: float) -> void:
	super(delta)
	if variant == Variant.CHAIN and _launched and not _done and not _fizzling:
		_link_clock += delta
		if _link_clock >= LINK_REFRESH:
			_link_clock = 0.0
			_refresh_links()
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
	# A mine that deals no damage (EMP) blasts nothing: no `ContactBlast`, no `pulse_damage`.
	if blast_damage > 0:
		if hostility == Hostility.ALL:
			Hazards.pulse_damage(get_tree(), global_position, blast_radius, blast_damage)
		else:
			ContactBlast.spawn(get_parent(), global_position, blast_radius, blast_damage, blast_frames)
	if variant == Variant.CHAIN:
		_propagate_chain()
	elif variant == Variant.PULSE:
		_disrupt_players(pulse_radius, disrupt_strength, disrupt_seconds)
		PulseRing.spawn(get_parent(), global_position, pulse_radius)
	elif variant == Variant.EMP:
		EmpPulse.emit(get_tree(), global_position, emp_radius, emp_seconds, self)
		EmpRing.spawn(get_parent(), global_position, emp_radius)


## Calls the duck-typed `apply_boost_disruption(strength, seconds)` on every node in group `player` whose CENTRE is
## within [param radius] (the `Hazards.pulse_damage()` distance rule). Returns how many it reached. A player without the
## hook is skipped.
func _disrupt_players(radius: float, strength: float, seconds: float) -> int:
	var reached := 0
	for node in get_tree().get_nodes_in_group(&"player"):
		var ship := node as Node2D
		if ship == null or ship.is_queued_for_deletion() or not ship.has_method(&"apply_boost_disruption"):
			continue
		if ship.global_position.distance_to(global_position) > radius:
			continue
		ship.apply_boost_disruption(strength, seconds)
		reached += 1
	return reached


## The radius of the effect ring the mine shows while it is warning: `pulse_radius` (PULSE, violet) or `emp_radius` (EMP,
## blue-white), else 0.
func effect_ring_radius() -> float:
	if not _warning or _done:
		return 0.0
	match variant:
		Variant.PULSE:
			return pulse_radius
		Variant.EMP:
			return emp_radius
	return 0.0


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


## The state overlay on top of `EnemyOrdnance._draw()` (the body is the scene's `Sprite`). A homing mine shows its `Eye`
## sprite (a lens that looks at the player) while it is noticing.
func _draw() -> void:
	super()
	_update_eye()
	if variant == Variant.CHAIN and not _done and not _fizzling:
		_draw_links()
	if effect_ring_radius() > 0.0:
		draw_arc(Vector2.ZERO, effect_ring_radius(), 0.0, TAU, 48, EmpRing.COLOR if variant == Variant.EMP else PulseRing.COLOR, 2.0)


## HOMING: shows the `Eye` sprite, nudged toward the player, only while the mine is noticing and live.
func _update_eye() -> void:
	var eye := get_node_or_null("Eye") as Sprite2D
	if eye == null:
		return
	var seeing: bool = variant == Variant.HOMING and _noticing and not _done
	eye.visible = seeing
	if not seeing:
		return
	var target := TargetInfo.player(get_tree())
	var look := (target.position - global_position).normalized() if target.has_target else _heading
	eye.position = look * body_radius * 0.4
	if _sprite != null:
		eye.modulate.a = _sprite.modulate.a


## The "fuse links": a faint dotted line to each neighbour. Where both ends are CHAIN mines only the one with the lower
## instance id draws it, so a shared link is not drawn twice (and does not read brighter than a single one).
func _draw_links() -> void:
	for m in _link_mines:
		if not is_instance_valid(m) or m._done or m._fizzling:
			continue
		if m.variant == Variant.CHAIN and m.get_instance_id() < get_instance_id():
			continue
		draw_dashed_line(Vector2.ZERO, to_local(m.global_position), LINK_COLOR, 1.0, 4.0)
