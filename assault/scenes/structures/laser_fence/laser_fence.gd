## LaserFence - a laser wall between two destructible posts (docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.11; Phase 8 t10). Behaviour:
## `STRUCTURE.md` beside this file.
##
## Two `LaserEmitter` children (`PostA`, `PostB`) and one `EnemyBeam` (a `twin_beam.tscn` instance with fence overrides: 12 damage, `avoid_weight` 1.0)
## the fence ticks itself - `_physics_process` -> `step(delta)`, hand-tickable - feeding it `set_endpoints(PostA, PostB)` each tick. The beam registers a
## `&"laser_wall"` hazard from TELEGRAPH to FADE, so AI enemies steer round the ends; the fence's owner group (a turret group's, else its own) holds both
## posts, so the beam never hurts them.
##
## **Modes.** STATIC: TELEGRAPH once, then ACTIVE held. CYCLE (a temporary barrier): OFF `off_seconds` -> TELEGRAPH -> ACTIVE `on_seconds` -> FADE -> OFF,
## starting `phase_offset` seconds into the cycle. The cycle's period is `off + telegraph + on`; the beam's short FADE runs inside the next OFF.
##
## **Collapse (F6).** The first post to die (`died`) or leave the tree cancels the beam at once (FADE) and the fence never relights; the other post stays
## a target. When the second goes, the fence frees itself `linger_seconds` later on its own physics step (no `Timer`): a dying post's `ExplosionEffect`
## spawns its particles into the post's parent, this node, so they need time to finish. The hazard is unregistered and the beam harmless meanwhile.
##
## **Not an enemy.** Never in `enemies`, never scored (`counts_toward_wave_clear` / `counts_as_escape` false); its posts are the enemies and are announced
## with `EventBus.enemy_spawned_orphan`. In Assault an `AssaultDrift` child carries both posts, and the hazard's carried velocity is the drift's. A fence
## a wave spawns removes the camera's pan from its x once in `_ready()` (`world_anchored_x`, as `TurretGroup` does); a turret group's member skips it.
class_name LaserFence
extends Node2D

## Append-only.
enum Mode { STATIC, CYCLE }

signal collapsed
signal powered_off

## Slack on summed tick deltas.
const EPS := 1e-6

@export var mode: Mode = Mode.STATIC
## CYCLE: seconds dark between flashes, and seconds lit.
@export var off_seconds: float = 2.5
@export var on_seconds: float = 3.0
## CYCLE: start this many seconds into the cycle (several barriers can alternate).
@export var phase_offset: float = 0.0
## After the last post dies the fence lives this long so the posts' explosion particles (0.5 s) can finish.
@export var linger_seconds: float = 1.0
## Assault: remove the camera's horizontal pan from x in `_ready()` (see the class doc). A turret group's member is placed already.
@export var world_anchored_x: bool = true
@export var drift_speed: float = 60.0

## Read by `ScoreTracker` for a wave spawn: the fence is never in a wave tally and never an escape.
var counts_toward_wave_clear: bool = false
var counts_as_escape: bool = false
var score_value: int = 0
## The set both posts join; the beam exempts it.
var owner_group: StringName = &""

var _group: Object = null
var _powered: bool = true
var _collapsed: bool = false
var _started: bool = false
var _clock: float = 0.0
## Post -> still alive.
var _alive: Dictionary = {}
var _linger_left: float = -1.0
var _a: Vector2 = Vector2.ZERO
var _b: Vector2 = Vector2.ZERO

@onready var _beam: EnemyBeam = $Beam
@onready var _post_a: LaserEmitter = $PostA
@onready var _post_b: LaserEmitter = $PostB
@onready var _drift: AssaultDrift = $AssaultDrift


func _init() -> void:
	owner_group = StringName("laser_fence_%d" % get_instance_id())


func _ready() -> void:
	var tree := get_tree()
	if world_anchored_x and _group == null and EnemyWorld.has_view_rect(tree) and EnemyWorld.has_projectile_world_rect(tree):
		global_position.x -= EnemyWorld.view_rect(tree).get_center().x - EnemyWorld.projectile_world_rect(tree).get_center().x
	_drift.speed = drift_speed
	_beam.setup(self, owner_group)
	for post: LaserEmitter in [_post_a, _post_b]:
		post.add_to_group(owner_group)
		_alive[post] = true
		post.died.connect(_on_post_gone.bind(post), CONNECT_ONE_SHOT)
		post.tree_exiting.connect(_on_post_gone.bind(post), CONNECT_ONE_SHOT)
	_a = _post_a.global_position
	_b = _post_b.global_position
	for post: LaserEmitter in [_post_a, _post_b]:
		EventBus.enemy_spawned_orphan.emit(post)


func _physics_process(delta: float) -> void:
	step(delta)


## One fence tick (hand-tickable): the schedule, the endpoints, the beam, the posts' lights, the carried hazard velocity, the linger.
func step(delta: float) -> void:
	if _linger_left >= 0.0:
		_linger_left -= delta
		_tick_beam(delta)
		if _linger_left <= EPS and not is_queued_for_deletion():
			queue_free()
		return
	if _powered and not _collapsed:
		_drive_schedule(delta)
	_tick_beam(delta)
	_update_lights()


## Down for good: the beam is cancelled, the posts' lights go out and it never restarts. Ignored once off.
func set_powered(on: bool) -> void:
	if on or not _powered:
		return
	_powered = false
	if is_node_ready():
		_beam.cancel()
		_update_lights()
	powered_off.emit()


func is_powered() -> bool:
	return _powered


## Call before `add_child`: the fence joins `group.owner_group` (read duck-typed) and, being placed by the group, skips the world anchor.
func set_turret_group(group: Object) -> void:
	if is_node_ready():
		push_warning("LaserFence: set_turret_group() after _ready() is ignored; call it before add_child")
		return
	_group = group
	world_anchored_x = false
	if group != null:
		var named: Variant = group.get("owner_group")
		if named != null and StringName(named) != &"":
			owner_group = StringName(named)


func turret_group() -> Object:
	return _group


func beam() -> EnemyBeam:
	return _beam


func post_a() -> LaserEmitter:
	return _post_a


func post_b() -> LaserEmitter:
	return _post_b


## The live posts (not freed, not queued for deletion).
func posts() -> Array[LaserEmitter]:
	var out: Array[LaserEmitter] = []
	for post: Variant in [_post_a, _post_b]:
		if is_instance_valid(post) and not (post as Node).is_queued_for_deletion() and _alive.get(post, false):
			out.append(post as LaserEmitter)
	return out


## True once a post has gone: the beam is down for good.
func is_collapsed() -> bool:
	return _collapsed


## The beam is warning or lit.
func is_lit() -> bool:
	var p := _beam.phase()
	return p == EnemyBeam.Phase.TELEGRAPH or p == EnemyBeam.Phase.ACTIVE


## The structures' answer to the player's mining beam: a fence is never a wall.
func is_laser_blocking() -> bool:
	return false


## CYCLE: seconds from one flash's start to the next (`off + telegraph + on`).
func cycle_period() -> float:
	return off_seconds + _beam.telegraph_seconds + on_seconds


func _drive_schedule(delta: float) -> void:
	if mode == Mode.STATIC:
		if not _started:
			_started = true
			_beam.start()
		return
	var tele := _beam.telegraph_seconds
	var period := cycle_period()
	if not _started:
		_started = true
		_clock = fposmod(phase_offset, period)
		if _clock + EPS >= off_seconds + tele:
			_beam.start(0.0)
		elif _clock + EPS >= off_seconds:
			_beam.start(off_seconds + tele - _clock)
	var prev := _clock
	_clock += delta
	if prev + EPS < off_seconds and _clock + EPS >= off_seconds:
		_beam.start()
	while _clock + EPS >= period:
		_clock -= period
		_beam.cancel()
		if _clock + EPS >= off_seconds:
			_beam.start()


func _tick_beam(delta: float) -> void:
	for post in posts():
		if post == _post_a:
			_a = post.global_position
		else:
			_b = post.global_position
	_beam.set_endpoints(_a, _b)
	_beam.tick(delta)
	var info := _beam.hazard_info()
	if info != null:
		var carried := _drift.velocity()
		if carried != Vector2.ZERO:
			info.velocity = carried


func _update_lights() -> void:
	var want: int = StateLight.State.OFF
	if _powered and not _collapsed:
		match _beam.phase():
			EnemyBeam.Phase.TELEGRAPH:
				want = StateLight.State.CHARGING
			EnemyBeam.Phase.ACTIVE:
				want = StateLight.State.ARMED
	for post in posts():
		var light := post.state_light()
		if light != null and light.get_state() != want:
			light.set_state(want)


func _on_post_gone(post: LaserEmitter) -> void:
	if not _alive.get(post, false):
		return
	_alive[post] = false
	var first := not _collapsed
	_collapsed = true
	_beam.cancel()
	_update_lights()
	if first:
		collapsed.emit()
	if _linger_left < 0.0 and not _alive.values().has(true):
		_linger_left = linger_seconds
