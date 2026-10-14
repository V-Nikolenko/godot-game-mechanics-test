## The Sniper's aim line, and the rail fallback that fires it (docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md
## §2.5 "Telegraph", §2.8 "Sniper").
##
## It is the sniper's OWN `Node2D` (review C9): the player weapon's `SniperAimVisualizer` is shared and is
## not touched. The line is drawn in global space from the muzzle toward an aim point, extended to
## `max(distance + 300, 900)` px so it reaches past the player when the sniper is off camera. Tracking is a
## dim red line of width 1; a locked one is bright near-white, width 3. The decoy is a dim orange
## line of width 1 (`show_decoy_line()`).
##
## Rails: while an `EnemyPathMover` owns the sniper, `SniperBrain.on_suspended()` calls
## `start_rail_cycle()`. This node then runs its own `_process` cycle at the legacy timings - AIM
## `rail_aim_seconds` tracking at `rail_track_rate`, LOCK `rail_lock_seconds` frozen, then one round at
## `rail_fallback_speed` - up to `rail_shot_count` shots. The aim direction lives HERE: nothing in this
## script writes the ship's `rotation` (the path mover owns it on a rail, which retires the two-writer
## conflict the legacy sniper had), so the single-writer gate stays empty.
class_name SniperTelegraph
extends Node2D

enum RailPhase { OFF, AIM, LOCK }

## The line extends past the aim point by this much, and is never shorter than `MIN_LENGTH` (px).
const EXTEND := 300.0
const MIN_LENGTH := 900.0
const TRACKING_COLOR := Color(1.0, 0.1, 0.1, 0.55)
const TRACKING_WIDTH := 1.0
const LOCKED_COLOR := Color(1.0, 0.96, 0.9, 1.0)
const LOCKED_WIDTH := 3.0
## The decoy line (SniperConfig.decoy_telegraph): dim orange, width 1 - never the lock's colour or width.
const DECOY_COLOR := Color(1.0, 0.55, 0.1, 0.45)
const DECOY_WIDTH := 1.0

## Set by `sniper.gd` in `_ready()`.
var config: SniperConfig = SniperConfig.new()
var muzzle: Marker2D
var pool: BulletPool

## Drawing state.
var line_visible: bool = false
var line_locked: bool = false
var line_color: Color = TRACKING_COLOR
var line_width: float = TRACKING_WIDTH
var _aim_point: Vector2 = Vector2.ZERO

## Rail cycle state.
var rail_phase: int = RailPhase.OFF
var rail_shots_fired: int = 0
var _rail_time: float = 0.0
var _rail_aim_angle: float = PI / 2.0  # DOWN, the legacy nose-down start
var _rail_lock_point: Vector2 = Vector2.ZERO


func _ready() -> void:
	set_process(false)  # costs nothing until a rail cycle starts


## Shows the line toward `aim_point`; `locked` picks the bright, wide look.
func show_line(aim_point: Vector2, locked: bool) -> void:
	_aim_point = aim_point
	line_locked = locked
	line_color = LOCKED_COLOR if locked else TRACKING_COLOR
	line_width = LOCKED_WIDTH if locked else TRACKING_WIDTH
	line_visible = true
	queue_redraw()


## Shows the decoy: a dim orange line toward `aim_point`, which is not where the shot would go.
func show_decoy_line(aim_point: Vector2) -> void:
	_aim_point = aim_point
	line_locked = false
	line_color = DECOY_COLOR
	line_width = DECOY_WIDTH
	line_visible = true
	queue_redraw()


func hide_line() -> void:
	if line_visible:
		line_visible = false
		queue_redraw()


## The two global endpoints the line is drawn between, or an empty array while it is hidden.
func line_points() -> PackedVector2Array:
	if not line_visible or muzzle == null:
		return PackedVector2Array()
	var from := muzzle.global_position
	var to_aim := _aim_point - from
	var dir := to_aim.normalized() if to_aim.length_squared() > 0.000001 else Vector2.DOWN
	var length := maxf(to_aim.length() + EXTEND, MIN_LENGTH)
	return PackedVector2Array([from, from + dir * length])


func _draw() -> void:
	var pts := line_points()
	if pts.is_empty():
		return
	draw_line(to_local(pts[0]), to_local(pts[1]), line_color, line_width)


# ── The rail fallback (§2.8) ─────────────────────────────────────────────────────────────────────

## Begins the legacy aim / lock / fire cycle. Idempotent while it is running.
func start_rail_cycle() -> void:
	if rail_phase != RailPhase.OFF:
		return
	rail_shots_fired = 0
	_begin_rail_aim()
	set_process(true)


func stop_rail_cycle() -> void:
	rail_phase = RailPhase.OFF
	set_process(false)
	hide_line()


func _begin_rail_aim() -> void:
	rail_phase = RailPhase.AIM
	_rail_time = 0.0


func _process(delta: float) -> void:
	if rail_phase == RailPhase.OFF or muzzle == null:
		return
	_rail_time += delta
	var from := muzzle.global_position
	if rail_phase == RailPhase.AIM:
		var target := TargetInfo.player(get_tree())
		if target.has_target:
			var wanted := (target.position - from).angle()
			_rail_aim_angle = lerp_angle(_rail_aim_angle, wanted, clampf(delta * config.rail_track_rate, 0.0, 1.0))
		show_line(from + Vector2.from_angle(_rail_aim_angle) * 1000.0, false)
		if _rail_time >= config.rail_aim_seconds:
			rail_phase = RailPhase.LOCK
			_rail_time = 0.0
			_rail_lock_point = from + Vector2.from_angle(_rail_aim_angle) * 1000.0
	else:
		show_line(_rail_lock_point, true)
		if _rail_time >= config.rail_lock_seconds:
			_fire_rail_shot(from)
			rail_shots_fired += 1
			if rail_shots_fired < config.rail_shot_count:
				_begin_rail_aim()
			else:
				stop_rail_cycle()


## One round from the pool, at the fallback speed and damage, along the locked line. Null when the pool is
## exhausted (the pool logs a warning).
func _fire_rail_shot(from: Vector2) -> EnemyBullet:
	if pool == null:
		return null
	var round_ := pool.acquire(from) as EnemyBullet
	if round_ == null:
		return null
	round_.set_direction(_rail_lock_point - from)
	round_.speed = config.rail_fallback_speed
	var hit_box := round_.get_node_or_null("HitBox") as HitBox
	if hit_box != null:
		hit_box.damage = config.rail_fallback_damage
	return round_
