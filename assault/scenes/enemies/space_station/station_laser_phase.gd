## StationLaserPhase — the SpaceStation's second phase (EPIC sub-item 3).
##
## Once the last turret dies, the station stops being a stationary damage-sponge: it starts
## rotating and fires telegraphed `LaserRay` beams outward from its hull on a repeating cycle,
## so the player has to keep moving. Every beam shows a warning line for ~2 s before it can hurt
## anything — a death is always a read the player missed, never an ambush.
##
## A child node of `space_station.tscn` rather than methods on `space_station.gd`, per
## `CLAUDE.md`'s composition rule: the station is already assembled from components, and this is
## one more child. `SpaceStation` gains only the `armor_broken` signal and no laser logic at all.
##
## Plan and the measurements behind the numbers: `docs/plans/station-laser-phase/`.
##
## ── The self-destruct trap ───────────────────────────────────────────────────────────────────
##
## `LaserRay`'s default hit mask is `128 | 256 | 512`, and the station's own core `HurtBox` is on
## layer 512 — deliberately kept live, because two shipped systems drive damage straight into
## `received_damage` with no physics. A beam fired from inside the hull on the default mask takes
## the station 600 -> 0 HP in one frame. Every beam this node spawns therefore sets
## `hit_mask_override = 128` (player hurtbox only), BEFORE `add_child()`, because that is when
## `LaserRay._ready()` reads it.
##
## The overlap is angle-dependent: at `emitter_radius = 140` an axis-aligned beam clears the
## 240x240 core hurtbox by 20 px, but a diagonal emitter sits ~30 px INSIDE the hull. So the
## suicide only reproduces on the diagonal volleys — which is why the regression test forces one.
class_name StationLaserPhase
extends Node2D

const _LASER_SCENE: PackedScene = preload("res://assault/scenes/hazards/laser_ray/laser_ray.tscn")

## Player hurtbox layer, and nothing else. See the self-destruct note above.
const _PLAYER_HURTBOX_MASK: int = 128

## Base local angle of each volley, cycled in order. Deliberately NOT `randf()`: random attack
## ordering is the documented boss-design mistake — it cannot be balanced and it cannot be
## tested. The station is rotating underneath anyway, so every volley's WORLD angle differs; the
## list adds a second, controlled axis of variation with a known value range.
##
## Indices 2 and 3 are BOTH diagonal, so a read-vs-increment off-by-one in `_fire_volley()`
## cannot silently disarm the self-damage regression test.
const _VOLLEY_ANGLES: Array[float] = [0.0, PI * 0.5, PI * 0.25, PI * 0.75]

## Distance from the station centre to each beam's emitter, in FINAL ON-SCREEN PIXELS at
## scale = 1. Everything inside `space_station.tscn` is authored that way and must NOT be
## multiplied by `ArenaCamera.WORLD_SCALE` — only the wave spawn offset is scaled.
##
## Scene geometry, not a stat, which is why it lives here and not in `SpaceStationConfig`.
@export var emitter_radius: float = 140.0

## ── Timings, copied from SpaceStationConfig in _ready() ───────────────────────
##
## Copied rather than read through `_station.config` on every volley, because that resource is a
## SINGLE PROCESS-WIDE INSTANCE: `space_station.gd` `load()`s it and ResourceLoader caches, so
## every station in the process — and every test that `preload()`s the `.tres` — shares one
## object. Reading through it at runtime is reading mutable global state; writing to it (as a
## test shortening the timings would have to) permanently rewrites the shipped values.
##
## Copying is also the exact "`.tres` applied in `_ready()`" pattern `space_station.gd` already
## uses for `health.max_health` and the turret HP.
##
## The defaults below are the CONSERVATIVE FALLBACK for a station with no config at all — longer
## telegraph, shorter lethal window, slower cycle, no rotation, one beam. They are intentionally
## different from the shipped `.tres` values, which is what stops the config test from passing
## vacuously.
var warn_duration: float = 2.0
var active_duration: float = 1.0
var volley_interval: float = 8.0
var rotation_speed: float = 0.0
var beam_count: int = 1

var _station: SpaceStation = null
var _active: bool = false
## Cycles `_VOLLEY_ANGLES`. Read for the current volley, THEN incremented. No setter and no
## export: GDScript has no access modifiers, so a test writing `phase._volley_index = 2` to force
## a diagonal volley adds zero production surface.
var _volley_index: int = 0
var _volley_timer: Timer = null


func _ready() -> void:
	set_physics_process(false)

	_station = get_parent() as SpaceStation
	if _station == null:
		## A plain Node2D dropped in the wrong place must not crash.
		push_warning("StationLaserPhase has no SpaceStation parent; disabling.")
		return

	## Godot readies children before parents, so this runs BEFORE SpaceStation._ready(). Safe
	## here because `config` is an @export initialised at property-init time, before any _ready()
	## — and we read nothing that SpaceStation._ready() derives from it. Do not add a read that
	## depends on station-derived state.
	var cfg := _station.config
	if cfg != null:
		warn_duration = cfg.laser_warn_duration
		active_duration = cfg.laser_active_duration
		volley_interval = cfg.laser_volley_interval
		rotation_speed = cfg.laser_rotation_speed
		beam_count = cfg.laser_beam_count

	_volley_timer = Timer.new()
	_volley_timer.one_shot = false
	_volley_timer.timeout.connect(_fire_volley)
	add_child(_volley_timer)

	_station.armor_broken.connect(_on_armor_broken)
	## Zero-argument signal, declared and emitted that way (unlike `Health.amount_changed`), so a
	## zero-arg handler is correct and raises no engine error.
	_station.died.connect(_stop)


func is_active() -> bool:
	return _active


## Rotating the station sweeps every live beam for free: beams are children of this node, which
## is a child of the station. No per-beam rotation code.
##
## Constant angular velocity, no easing — predictability is what makes a sweep dodgeable.
func _physics_process(delta: float) -> void:
	if not _active or _station == null:
		return
	_station.rotation += rotation_speed * delta


func _on_armor_broken() -> void:
	if _active:
		return
	_active = true
	set_physics_process(true)
	## Fire the first volley immediately so the phase change is legible, then cycle. The beam's
	## own warning window is the telegraph; an extra interval of nothing would just read as the
	## boss having stopped.
	_fire_volley()
	if volley_interval > 0.0:
		_volley_timer.start(volley_interval)


func _fire_volley() -> void:
	if not _active:
		return
	var base: float = _VOLLEY_ANGLES[_volley_index % _VOLLEY_ANGLES.size()]
	_volley_index += 1
	var n: int = maxi(beam_count, 1)
	for i in n:
		_spawn_beam(base + float(i) * TAU / float(n))


func _spawn_beam(angle: float) -> void:
	var laser := _LASER_SCENE.instantiate() as LaserRay
	## Order matters. `auto_start` defaults to true, so an early add_child() would telegraph a
	## frame at this node's origin with rotation 0 before we place it — the shipped spawn
	## sequence in `level_1_director.gd` does the same dance.
	laser.auto_start = false
	laser.warn_duration = warn_duration
	laser.active_duration = active_duration
	## MUST be set before add_child(): _ready() is what reads it.
	laser.hit_mask_override = _PLAYER_HURTBOX_MASK
	add_child(laser)
	## LaserRay extends along its local +Y, so the emitter offset uses the same axis.
	laser.position = Vector2(0.0, emitter_radius).rotated(angle)
	laser.rotation = angle
	laser.start()


## Nothing this node creates may outlive the station.
##
## `BaseEnemy` emits `died` and `queue_free()`s in the same call, so the beams would go with the
## subtree at end-of-frame anyway — but a beam that is lethal THIS frame would still get one kill
## out of a boss that is already dead. It also matters for `LevelSection.ENEMIES_CLEARED`, which
## polls the enemy container's child count.
func _stop() -> void:
	_active = false
	set_physics_process(false)
	if _volley_timer != null:
		_volley_timer.stop()
	for child in get_children():
		var laser := child as LaserRay
		if laser == null:
			continue
		if laser.is_lethal_now():
			laser.dissolve()
		else:
			## dissolve() is a no-op outside the IDLE phase, so a beam still warming up needs
			## the explicit free.
			laser.queue_free()


## Live beams, for tests and for sub-item 4.
func live_beams() -> Array[LaserRay]:
	var out: Array[LaserRay] = []
	for child in get_children():
		var laser := child as LaserRay
		if laser != null and is_instance_valid(laser):
			out.append(laser)
	return out
