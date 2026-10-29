## DefenseTurretBrain - the Stationary Defense Turret's decisions (docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.7; Phase 8 t6).
##
## No mover: the turret never moves itself (in Assault its `AssaultDrift` scrolls it). Each physics tick, through `BaseEnemy._physics_process`:
## - **Perception.** Open Space: the player within `perceive_radius`, kept until beyond `lose_radius`. Assault: the turret's centre inside
##   `EnemyWorld.view_rect()` - it never perceives, so never fires, from off-screen.
## - SCAN -> NOTICING (one `StateLight.blink_once()`) -> ENGAGED after `notice_time`; losing the player drops back to SCAN.
## - ENGAGED: `can_fire = can_see_player() or mount.fires_past_cover()` per mount (the rocket battery fires past cover, the Missile Corvette
##   rule; every other variant holds fire without line of sight), then `mount.tick(delta, target, can_fire)`. The LOS ray runs only on the
##   physics step, so a hand-ticked row (no physics frame) counts the line as clear.
## - SCAN / NOTICING: every mount `scan(delta)`. UNPOWERED (`power_down()`, never left in this phase): every mount `tick(…, false)`, which droops.
##
## The brain owns the host's `StateLight`: CHARGING while any mount is in TELEGRAPH, COMMIT while one `is_committed()`, ARMED while one is in
## TRACK / FIRE / COOLDOWN with its `can_fire`, OFF otherwise. It writes the light only when the wanted state differs, so the NOTICING blink is
## never cut short. A tow is always refused (moot: no mover).
class_name DefenseTurretBrain
extends EnemyBrain

## Append-only.
enum Phase { SCAN, NOTICING, ENGAGED, UNPOWERED }

signal phase_changed(new_phase: int)

## Test seam: start ENGAGED (Assault view gating still applies).
@export var start_engaged: bool = false

var config: DefenseTurretConfig
var phase: int = Phase.SCAN

var _clock: float = 0.0
var _mounts: Array[TurretMount] = []
## Each mount's last `can_fire`, for the light.
var _can_fire: Dictionary = {}
var _light: StateLight


func _ready() -> void:
	super._ready()
	if actor != null:
		_light = actor.get_node_or_null("StateLight") as StateLight
	if start_engaged:
		phase = Phase.ENGAGED


## The host hands over the mounts it built (they exist only after the host's own `_ready()`).
func bind_mounts(mounts: Array[TurretMount]) -> void:
	_mounts = mounts.duplicate()


func enter_phase(new_phase: int) -> void:
	if phase == new_phase:
		return
	phase = new_phase
	_clock = 0.0
	phase_changed.emit(new_phase)


## Unpowered: every mount powers down, the light goes OFF; never left in this phase. Idempotent.
func power_down() -> void:
	if phase == Phase.UNPOWERED:
		return
	enter_phase(Phase.UNPOWERED)
	for mount in _mounts:
		mount.power_down()
		_can_fire[mount] = false
	if _light != null:
		_light.set_state(StateLight.State.OFF)


func accepts_tow() -> bool:
	return false


func tick(delta: float) -> void:
	if actor == null or config == null or not actor.is_inside_tree():
		return
	var target := TargetInfo.player(actor.get_tree())
	if phase == Phase.UNPOWERED:
		for mount in _mounts:
			mount.tick(delta, target, false)
		return
	_clock += delta
	var perceived := _perceives(target)
	match phase:
		Phase.SCAN:
			if perceived:
				enter_phase(Phase.NOTICING)
				if _light != null:
					_light.blink_once()
		Phase.NOTICING:
			if not perceived:
				enter_phase(Phase.SCAN)
			elif _clock + TurretMount.CLOCK_EPS >= config.notice_time:
				enter_phase(Phase.ENGAGED)
		Phase.ENGAGED:
			if not perceived:
				enter_phase(Phase.SCAN)
	if phase == Phase.ENGAGED:
		var sees := true
		if Engine.is_in_physics_frame():
			sees = can_see_player()
		for mount in _mounts:
			var can_fire := sees or mount.fires_past_cover()
			_can_fire[mount] = can_fire
			mount.tick(delta, target, can_fire)
	else:
		for mount in _mounts:
			_can_fire[mount] = false
			mount.scan(delta)
	_update_light()


func _perceives(target: TargetInfo) -> bool:
	if not target.has_target:
		return false
	var tree := actor.get_tree()
	if EnemyWorld.has_view_rect(tree):
		return EnemyWorld.view_rect(tree).has_point(actor.global_position)
	var radius := config.lose_radius if phase == Phase.NOTICING or phase == Phase.ENGAGED else config.perceive_radius
	return target.distance_from(actor.global_position) <= radius


func _update_light() -> void:
	if _light == null:
		return
	var want: int = StateLight.State.OFF
	if phase == Phase.ENGAGED:
		var charging := false
		var committed := false
		var armed := false
		for mount in _mounts:
			var p := mount.phase()
			if p == TurretMount.Phase.TELEGRAPH:
				charging = true
			if mount.is_committed():
				committed = true
			if _can_fire.get(mount, false) and p in [TurretMount.Phase.TRACK, TurretMount.Phase.FIRE, TurretMount.Phase.COOLDOWN]:
				armed = true
		if charging:
			want = StateLight.State.CHARGING
		elif committed:
			want = StateLight.State.COMMIT
		elif armed:
			want = StateLight.State.ARMED
	if _light.get_state() != want:
		_light.set_state(want)
