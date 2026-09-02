## StationGunnery — the SpaceStation's guns (EPIC sub-item 4a).
##
## Before this, the first half of the mini-boss fight was completely passive: four turrets sat
## there while the player shot them, and nothing fired back until the armour broke. Now:
##
##   - Phase 1: every LIVE turret fires an aimed 3-bullet fan on one shared cadence. Killing a
##     turret visibly removes a gun from the volley, so the armour is also the threat.
##   - Phase 2: on `armor_broken` the turret cadence stops and the core fires precessing full
##     rings that interleave with `StationLaserPhase`'s sweeping beams.
##
## A child node of `space_station.tscn` rather than methods on `space_station.gd`, per
## `CLAUDE.md`'s composition rule and modelled on its sibling `StationLaserPhase`.
## `SpaceStation` gains only the `turrets()` data accessor and no gun logic at all.
##
## Plan and the measurements behind the numbers: `docs/plans/station-bullet-hell/`.
##
## ── The pool is authored in the scene, and must stay a direct child of the station ───────────
##
## `bullet_pool.gd:47` hardcodes its container as `get_parent().get_parent()`, with no override.
## So the `BulletPool` MUST be a direct child of `SpaceStation`: pool -> station -> enemy_container
## puts in-flight bullets in world space, like every other enemy's. Parented under this node or a
## turret it would resolve to the station itself — and because `StationLaserPhase` rotates the
## hull, the entire bullet field would then swing around with it.
##
## This node therefore does NOT create the pool, it only drives one. Creating it here is not just
## a style choice: a child cannot `add_child()` onto its own parent from `_ready()`, because
## `Node::_propagate_ready()` sets `data.blocked` on the parent before readying its children and
## `add_child()` fails hard on that. Authoring the pool in the scene makes the placement a
## structural property of the scene file instead of a comment someone can violate later.
##
## ── No self-damage, in either direction ──────────────────────────────────────────────────────
##
## `enemy_bullet.tscn`'s HitBox is layer 256 / mask 128 (the player hurtbox only), and the
## station's core HurtBox mask is `97 | 1024` = 1121, which excludes 256. So the
## `hit_mask_override` dance `StationLaserPhase` needs has no analogue here.
class_name StationGunnery
extends Node2D

## The pool to fire through. Wired in `space_station.tscn` via
## `node_paths=PackedStringArray("bullet_pool")`; the `_ready()` fallback below covers a scene
## that forgot the wiring, because an unwired export is left null with NO error printed.
@export var bullet_pool: BulletPool

## Distance from a turret's centre to its muzzle. The turret HurtBox is a CircleShape2D of
## radius 26 (`station_turret.tscn`), so the muzzle sits on the hurtbox rim.
##
## Scene geometry, not a stat — which is why this is here and not in `SpaceStationConfig`, the
## same split `StationLaserPhase.emitter_radius` uses. Final on-screen pixels at scale = 1,
## never multiplied by `ArenaCamera.WORLD_SCALE`.
@export var turret_spawn_radius: float = 26.0

## Distance from the station centre to where ring bullets appear — outside the 240x240 hull.
@export var core_spawn_radius: float = 130.0

## ── Tuning, copied from SpaceStationConfig in _ready() ────────────────────────
##
## Copied rather than read through `_station.config` per volley, because that resource is a
## SINGLE PROCESS-WIDE INSTANCE (`space_station.gd:36` `load()`s it and ResourceLoader caches),
## shared by every station in the process and by every test that preloads the `.tres`.
##
## The defaults below are the CONSERVATIVE FALLBACK for a station with no config at all: one slow
## weak bullet, a long cadence, and no ring precession. They are intentionally different from the
## shipped `.tres` values, which is what stops the config test passing vacuously.
var turret_fire_interval: float = 3.0
var turret_burst_count: int = 1
var turret_burst_arc: float = 0.0
var turret_bullet_damage: int = 4
var turret_bullet_speed: float = 150.0
var core_ring_interval: float = 4.0
var core_ring_count: int = 3
var core_ring_step: float = 0.0
var core_bullet_damage: int = 4
var core_bullet_speed: float = 150.0

var _station: SpaceStation = null
var _core_firing: bool = false

## The ring's precession counter. Runtime state lives HERE, not on the pattern resource —
## `attack_pattern_resource.gd:1-5` requires those to stay pure configuration.
var _ring_angle: float = 0.0

var _turret_timer: Timer = null
var _ring_timer: Timer = null
var _turret_pattern: RadialAttackPattern = null
var _core_pattern: RadialAttackPattern = null


func _ready() -> void:
	_station = get_parent() as SpaceStation
	if _station == null:
		## A plain Node2D dropped in the wrong place must not crash.
		push_warning("StationGunnery has no SpaceStation parent; disabling.")
		return

	if bullet_pool == null:
		bullet_pool = get_parent().get_node_or_null("BulletPool") as BulletPool
	if bullet_pool == null:
		push_warning("StationGunnery has no BulletPool sibling; disabling.")
		return

	## Godot readies children before parents, so this runs BEFORE SpaceStation._ready(). Safe for
	## `config`, which is an @export initialised at property-init time. NOT safe for anything the
	## station derives in its own _ready() — see the lazy turret resolution in _live_turrets().
	var cfg := _station.config
	if cfg != null:
		turret_fire_interval = cfg.turret_fire_interval
		turret_burst_count = cfg.turret_burst_count
		turret_burst_arc = cfg.turret_burst_arc
		turret_bullet_damage = cfg.turret_bullet_damage
		turret_bullet_speed = cfg.turret_bullet_speed
		core_ring_interval = cfg.core_ring_interval
		core_ring_count = cfg.core_ring_count
		core_ring_step = cfg.core_ring_step
		core_bullet_damage = cfg.core_bullet_damage
		core_bullet_speed = cfg.core_bullet_speed

	## Built with .new() and never loaded from a shared .tres, so writing `base_angle` between
	## shots cannot leak into another ship. `interceptor.gd:36` does the same.
	_turret_pattern = RadialAttackPattern.new()
	_core_pattern = RadialAttackPattern.new()

	_turret_timer = Timer.new()
	_turret_timer.one_shot = false
	_turret_timer.timeout.connect(fire_turret_volley)
	add_child(_turret_timer)

	_ring_timer = Timer.new()
	_ring_timer.one_shot = false
	_ring_timer.timeout.connect(fire_core_ring)
	add_child(_ring_timer)

	_station.armor_broken.connect(_on_armor_broken)
	## Zero-argument signal, declared and emitted that way, so a zero-arg handler is correct.
	_station.died.connect(_stop)

	## The first volley lands one full interval after spawn, never on spawn: that gap is the
	## player's grace period to register the boss, and it needs no extra config field.
	if turret_fire_interval > 0.0:
		_turret_timer.start(turret_fire_interval)


func is_core_firing() -> bool:
	return _core_firing


## Resolved lazily on every volley, never cached in _ready(): `SpaceStation.turret_root` is
## @onready, so it is still null while this node's _ready() runs. Doing it per volley is also
## what makes destroyed turrets drop out of the firing list for free.
func _live_turrets() -> Array[StationTurret]:
	var out: Array[StationTurret] = []
	if _station == null:
		return out
	for t in _station.turrets():
		if t.is_alive():
			out.append(t)
	return out


## Mirrors RadialAttackPattern's own aiming, including the DOWN fallback, so the barrel and the
## bullets it emits can never disagree.
func _player_direction_from(origin: Vector2) -> Vector2:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		return ((players[0] as Node2D).global_position - origin).normalized()
	return Vector2.DOWN


## Push the node's current field values onto the patterns immediately before firing, rather than
## once in _ready(). Keeps the node's fields the single source of truth — which is also what lets
## a test override a cadence or a count on the node and have it take effect.
func _sync_patterns() -> void:
	_turret_pattern.bullet_count = turret_burst_count
	_turret_pattern.arc = turret_burst_arc
	_turret_pattern.aim_at_player = true
	_turret_pattern.base_angle = 0.0
	_turret_pattern.bullet_damage = turret_bullet_damage
	_turret_pattern.bullet_speed = turret_bullet_speed
	_turret_pattern.spawn_radius = turret_spawn_radius

	_core_pattern.bullet_count = core_ring_count
	_core_pattern.arc = TAU
	_core_pattern.aim_at_player = false
	_core_pattern.bullet_damage = core_bullet_damage
	_core_pattern.bullet_speed = core_bullet_speed
	_core_pattern.spawn_radius = core_spawn_radius


## One fan per LIVE turret, all on the same tick. Public so tests can drive a volley without
## waiting out a real interval.
func fire_turret_volley() -> void:
	if _core_firing or _station == null or bullet_pool == null:
		return
	_sync_patterns()
	for t in _live_turrets():
		var dir := _player_direction_from(t.global_position)
		## The turret sprite's barrels point along local -Y, and no turret sets `rotation`, so
		## without this every barrel points at the top of the screen while firing elsewhere.
		## `global_rotation`, not `rotation`, so it stays correct while the hull rotates.
		t.global_rotation = dir.angle() + PI / 2.0
		_turret_pattern.fire(t, bullet_pool)


## One full ring from the core, precessing by core_ring_step each time. Public for the same
## reason as fire_turret_volley().
func fire_core_ring() -> void:
	if not _core_firing or _station == null or bullet_pool == null:
		return
	_sync_patterns()
	_core_pattern.base_angle = _ring_angle
	_core_pattern.fire(_station, bullet_pool)
	_ring_angle = fposmod(_ring_angle + core_ring_step, TAU)


func _on_armor_broken() -> void:
	if _core_firing:
		return
	_core_firing = true
	_turret_timer.stop()
	## The first ring lands one interval after the handover, not immediately:
	## `StationLaserPhase._on_armor_broken()` already fires a beam volley on this same frame, and
	## stacking a ring on top of it would spike the phase change rather than introduce it.
	if core_ring_interval > 0.0:
		_ring_timer.start(core_ring_interval)


## Nothing this node drives may outlive the station. In-flight bullets are freed by
## `BulletPool._exit_tree()`; this stops anything further being fired in the same frame.
## It matters for `LevelSection.ENEMIES_CLEARED`, which polls the enemy container's child count —
## a bullet left in the container after the boss dies holds the section open.
func _stop() -> void:
	_core_firing = false
	if _turret_timer != null:
		_turret_timer.stop()
	if _ring_timer != null:
		_ring_timer.stop()
