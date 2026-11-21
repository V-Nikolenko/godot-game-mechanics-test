## The Hijack Pulse's control dart (Phase 9 §2.11, docs/plans/cmug23onr001pm52w9swwophy/3-plan.md; task plan
## docs/plans/cmw5k4yk700amqs2xuk3t1oge/3-plan.md). One dart per claim: the Hacker Frigate fires it from its hull centre at one player
## homing rocket during PULSE, and it homes exactly on that rocket (no turn limit) until it is within `claim_radius`, then calls
## `rocket.retarget(player, -1.0, source)` (the rocket's own `hijack_seconds`) and expires on the same tick. Non-damaging, and it has **no
## collision areas**: it claims by distance, so it needs no layer.
##
## It ends with no claim when its rocket is freed, leaves the tree, refuses (`can_be_retargeted()` false: claimed by another, inside a lit
## jammer, done) or when the source that fired it is freed. A `ProjectileLifetime` child (`max_time` 1.6, `max_distance` 1400) is the backstop:
## 1400 / 900 = 1.56 s fits 1.6 s (the round lifetime sweep), so a rocket receding at full range can outrun it, by design.
##
## Pooled: the Hacker's `DartPool` (`BulletPool`, no `persist_after_owner_death`) recycles it on `expired`, so a dying Hacker's darts go with
## it. It never frees itself and never draws the claim's tether (the rocket does, `homing_missile.is_tether_visible()`).
class_name HijackPulse
extends Node2D

## Once per flight, through the lifetime's latch: a claim, a refused or vanished target, or a lifetime rule.
signal expired

const _CORE := Color(1.0, 0.95, 0.85)
const _RIM := Color(1.0, 0.7, 0.3)
## The diamond's length along the heading (px).
const _SIZE := 6.0
const _TRAIL_POINTS := 3
const _TRAIL_ALPHA: Array[float] = [0.6, 0.4, 0.2]

## px/s, straight at the rocket's current position every tick.
@export var speed: float = 900.0
## Within this distance (inclusive) of its rocket's centre the dart claims it.
@export var claim_radius: float = 16.0

@onready var _lifetime: ProjectileLifetime = $ProjectileLifetime

var _rocket: Node2D = null
var _source: Node = null
var _had_source: bool = false
var _flying: bool = false
## World positions, newest first.
var _trail: Array[Vector2] = []


func _ready() -> void:
	expired.connect(_on_expired)


## `BulletPool.acquire()`: a clean dart, its lifetime re-armed where the pool placed it.
func reset() -> void:
	_rocket = null
	_source = null
	_had_source = false
	_flying = false
	_trail.clear()
	rotation = 0.0
	if _lifetime != null:
		_lifetime.reset()


## Sends the dart at [param rocket] from [param source]'s hull centre (when the source is a `Node2D`); the lifetime measures from there. A
## null rocket ends it at once.
func launch(rocket: Node2D, source: Node) -> void:
	_rocket = rocket
	_source = source
	_had_source = source != null
	_trail.clear()
	if source is Node2D:
		global_position = (source as Node2D).global_position
	_lifetime.reset()
	if not is_instance_valid(rocket):
		_end()
		return
	_flying = true
	var to := rocket.global_position - global_position
	if to.length_squared() > 0.0:
		rotation = to.angle()
	queue_redraw()


func is_flying() -> bool:
	return _flying


## The rocket it was sent at (null after `reset()`).
func rocket() -> Node2D:
	return _rocket if is_instance_valid(_rocket) else null


func source() -> Node:
	return _source if is_instance_valid(_source) else null


func _physics_process(delta: float) -> void:
	if not _flying:
		return
	if (_had_source and not _alive(_source)) or not _rocket_claimable():
		_end()
		return
	_trail.push_front(global_position)
	if _trail.size() > _TRAIL_POINTS:
		_trail.resize(_TRAIL_POINTS)
	var to := _rocket.global_position - global_position
	var d := to.length()
	if d > 0.0:
		rotation = to.angle()
		global_position += to / d * minf(speed * delta, d)
	if global_position.distance_to(_rocket.global_position) <= claim_radius:
		_claim()
		_end()
		return
	queue_redraw()


## The player is `players[0]` of group `player`, the `TargetInfo.player()` rule.
func _claim() -> void:
	var players := get_tree().get_nodes_in_group(&"player")
	var player: Node2D = players[0] as Node2D if not players.is_empty() else null
	if player == null or not is_instance_valid(player):
		return
	var ok: bool = _rocket.call(&"retarget", player, -1.0, _source)
	if OS.is_stdout_verbose():
		print("[HijackPulse] claim %s" % ("taken" if ok else "refused"))


func _rocket_claimable() -> bool:
	if not _alive(_rocket) or not _rocket.is_inside_tree():
		return false
	return _rocket.has_method(&"can_be_retargeted") and _rocket.call(&"can_be_retargeted") == true


func _alive(n: Variant) -> bool:
	return is_instance_valid(n) and not (n as Node).is_queued_for_deletion()


func _end() -> void:
	_flying = false
	_lifetime.expire_now()


func _on_expired() -> void:
	_flying = false
	queue_redraw()


## A white-amber diamond along the heading and a 3-point fading trail, code-drawn.
func _draw() -> void:
	if not _flying:
		return
	for i in _trail.size():
		var p := to_local(_trail[i])
		draw_circle(p, 1.5, Color(_RIM, _TRAIL_ALPHA[i]))
	var h := _SIZE * 0.5
	var w := _SIZE * 0.35
	var diamond := PackedVector2Array([Vector2(h, 0.0), Vector2(0.0, w), Vector2(-h, 0.0), Vector2(0.0, -w)])
	draw_colored_polygon(diamond, _CORE)
	draw_polyline(diamond + PackedVector2Array([diamond[0]]), _RIM, 1.0)
