## EnemyShield — a temporary, directional shield on an enemy: it eats hits from one side, breaks,
## reboots and regenerates. Never a second health bar (R5.29): the capacity is small, refilling
## waits for a lull, a break takes it down for `reboot_seconds`, and it covers an arc, not the hull.
##
## HOW IT TAKES A HIT. `attach(hurt_box)` puts it in that `HurtBox`'s one absorber slot
## (`HurtBox.set_absorber`). The hurtbox asks `absorbs_hit(hit_box)` once per hit, inside its own
## `area_entered`; on true it emits `hit_absorbed` instead of `received_damage`, so the hull never
## hears of it. The projectile is not told: its target answers neither `deflects_hit` nor
## `is_armored` for the shield, so `ArmorQuery` reports no deflection and the shot is consumed
## (the shield eats bullets; a pierce charge is spent; a player rocket detonates). Direct emitters
## (beam, nova, dash, ...) call `received_damage.emit()` themselves and bypass the shield, exactly
## as they bypass an `ArmorPlate`.
##
## THE HOST is the attached hurtbox's parent: bearings are measured from its `global_position`,
## and a shield attached to a part's own hurtbox (a local module) protects that part only. While
## the host answers the hit-blind `is_armored() == true` the shield absorbs nothing — an armoured
## hull lets every shot through to its plates, so a shield in front would drain on shots that
## never touch the hull. It never asks `deflects_hit`: an `ArmorPlate`'s answer damages the plate.
##
## FACING is a world direction, `Vector2.DOWN` until told otherwise (the Assault nose-down
## convention: toward the player). `face()` snaps it; `set_threat_point()` / `sustain()` make it
## turn toward the bearing of a point at no more than `turn_rate` rad/s. The shield never writes
## its own or its host's `rotation`: it draws in world angles converted to local.
##
## SUSTAIN MODE (a projected shield): it lapses unless `sustain()` was called within `heartbeat`
## seconds (counted from creation for the first call): it releases the hurtbox slot at once, then
## fades for `fade_seconds` and frees.
##
## LIMITATION: a shield does not cover an `ArmorPlate` — the plate damages itself in its own
## `area_entered`, not through `received_damage`. A local-module shield goes on a plain part
## (its own `HurtBox` -> `received_damage` -> `Health`).
##
## Every clock is accumulated physics `delta` (`_tick`, hand-tickable in tests).
## Docs: docs/plans/cmufs7elw001pnm2xr3b6fteb/3-plan.md §2.3; tests: tests/unit/test_enemy_shield.gd,
## tests/integration/test_enemy_shield_hits.gd.
class_name EnemyShield
extends Node2D

## Emitted for every absorbed hit, after its damage was taken off the points.
signal absorbed(hit_box: HitBox, remaining: int)
## Emitted once when a hit takes the points to 0; the shield reboots for `reboot_seconds`.
signal broken()
## Emitted each time the points climb back to `capacity` after any loss (once per refill).
signal restored()
## Emitted once when a sustained shield missed its heartbeat; it fades out and frees itself.
signal lapsed()

const COLOR := Color(0.35, 0.9, 1.0)
const FLARE_SECONDS: float = 0.12
const BURST_SECONDS: float = 0.3
const _BURST_STROKES: int = 10
const _WIDTH: float = 2.0

## Width of the protected arc in degrees; >= 360 is a bubble (every direction). May change while
## attached: the next hit reads the new value.
@export var arc_deg: float = 110.0
## Points; an absorbed hit subtracts its `HitBox.damage`.
@export var capacity: int = 40
## Seconds after the last absorbed hit before refilling starts. Every absorbed hit restarts it.
@export var regen_delay: float = 3.0
## Empty -> full refill time (linear).
@export var regen_seconds: float = 1.5
## After a break: absorbs nothing for this long, then refills from 0.
@export var reboot_seconds: float = 4.0
## rad/s the facing turns toward the threat point.
@export var turn_rate: float = 1.6
## Drawn radius (the owner sets hull radius + 6).
@export var radius: float = 40.0
## When true the shield lapses unless `sustain()` was called within `heartbeat`.
@export var sustain_mode: bool = false
## Seconds of grace after the last `sustain()`.
@export var heartbeat: float = 0.3
## Fade-out time, then `queue_free()`, once a sustained shield lapses.
@export var fade_seconds: float = 0.3

var _hurt_box: HurtBox
## Points lost, so a `capacity` set after construction is read live.
var _lost: float = 0.0
var _facing: Vector2 = Vector2.DOWN
var _threat_point: Vector2 = Vector2.INF
var _since_hit: float = INF
var _rebooting: bool = false
var _reboot_left: float = 0.0
## True from a break until the refill reaches full (drawn as the arc growing from its centre).
var _refilling_after_break: bool = false
var _since_sustain: float = 0.0
var _lapsed: bool = false
var _fade_left: float = 0.0
var _flare_left: float = 0.0
var _burst_left: float = 0.0


## Takes `hurt_box`'s absorber slot. False when another live absorber holds it.
func attach(hurt_box: HurtBox) -> bool:
	if hurt_box == null:
		return false
	if _hurt_box != null and _hurt_box != hurt_box and is_instance_valid(_hurt_box):
		_hurt_box.clear_absorber(self)
	if not hurt_box.set_absorber(self):
		return false
	_hurt_box = hurt_box
	return true


func _enter_tree() -> void:
	# Re-entering after a re-parent: take the slot back (a no-op before the first `attach`).
	if not _lapsed and _hurt_box != null and is_instance_valid(_hurt_box):
		_hurt_box.set_absorber(self)


func _exit_tree() -> void:
	if _hurt_box != null and is_instance_valid(_hurt_box):
		_hurt_box.clear_absorber(self)


func _physics_process(delta: float) -> void:
	_tick(delta)


## The arc turns toward the bearing from the host to `world` at `turn_rate`.
func set_threat_point(world: Vector2) -> void:
	_threat_point = world


## Points the arc along `world_dir` at once (owner setup).
func face(world_dir: Vector2) -> void:
	if world_dir.length_squared() > 0.0:
		_facing = world_dir.normalized()


## Refreshes the heartbeat (`sustain_mode`) and sets the threat point.
func sustain(threat_point: Vector2) -> void:
	_since_sustain = 0.0
	set_threat_point(threat_point)


func points() -> int:
	return maxi(0, floori(float(capacity) - _lost))


func is_up() -> bool:
	return not _rebooting and not _lapsed and points() > 0


## The arc's centre as a world direction.
func facing() -> Vector2:
	return _facing


## The absorber hook `HurtBox` asks once per hit. One decision per call; true means the hit was
## taken (points spent, possibly breaking the shield) and must not reach the hull.
func absorbs_hit(hit_box: HitBox) -> bool:
	if hit_box == null or not is_up():
		return false
	var host := _host()
	if host == null:
		return false
	if host.has_method("is_armored") and host.is_armored():
		return false
	if arc_deg < 360.0:
		var bearing := hit_box.global_position - host.global_position
		if bearing.length_squared() > 0.0 \
				and absf(_facing.angle_to(bearing)) > deg_to_rad(arc_deg) * 0.5:
			return false

	# The breaking hit is absorbed whole: no bleed-through.
	_lost = minf(float(capacity), _lost + float(hit_box.damage))
	_since_hit = 0.0
	_flare_left = FLARE_SECONDS
	var remaining := points()
	absorbed.emit(hit_box, remaining)
	if remaining <= 0:
		_break()
	queue_redraw()
	return true


func _host() -> Node2D:
	if _hurt_box != null and is_instance_valid(_hurt_box):
		return _hurt_box.get_parent() as Node2D
	return get_parent() as Node2D


func _break() -> void:
	_lost = float(capacity)
	_rebooting = true
	_reboot_left = reboot_seconds
	_refilling_after_break = true
	_burst_left = BURST_SECONDS
	broken.emit()


## The slot is released here, not after the fade (the fade only draws), so a projector that
## re-acquires the same ward during the fade can attach a new shield.
func _lapse() -> void:
	_lapsed = true
	_fade_left = fade_seconds
	if _hurt_box != null and is_instance_valid(_hurt_box):
		_hurt_box.clear_absorber(self)
	lapsed.emit()


func _tick(delta: float) -> void:
	_flare_left = maxf(0.0, _flare_left - delta)
	_burst_left = maxf(0.0, _burst_left - delta)
	queue_redraw()
	if _lapsed:
		_fade_left -= delta
		if _fade_left <= 0.0 and not is_queued_for_deletion():
			queue_free()
		return
	if sustain_mode:
		_since_sustain += delta
		if _since_sustain > heartbeat:
			_lapse()
			return

	_turn(delta)

	if _rebooting:
		_reboot_left -= delta
		if _reboot_left <= 0.0:
			_rebooting = false
			_since_hit = regen_delay  # refill from 0 at once
		return
	if _lost <= 0.0:
		return
	_since_hit += delta
	if _since_hit < regen_delay:
		return
	var rate := float(capacity) / regen_seconds if regen_seconds > 0.0 else INF
	_lost = maxf(0.0, _lost - rate * delta)
	if _lost <= 0.0:
		_refilling_after_break = false
		restored.emit()


func _turn(delta: float) -> void:
	if _threat_point == Vector2.INF:
		return
	var host := _host()
	if host == null:
		return
	var want := _threat_point - host.global_position
	if want.length_squared() < 0.0001:
		return
	var max_step := turn_rate * delta
	_facing = _facing.rotated(clampf(_facing.angle_to(want), -max_step, max_step)).normalized()


func _draw() -> void:
	var fade := 1.0
	if _lapsed:
		fade = clampf(_fade_left / fade_seconds, 0.0, 1.0) if fade_seconds > 0.0 else 0.0
	var centre := _facing.angle() - global_rotation

	if _burst_left > 0.0:
		var t := 1.0 - _burst_left / BURST_SECONDS
		var burst := Color(COLOR, (1.0 - t) * fade)
		for i in _BURST_STROKES:
			var dir := Vector2.RIGHT.rotated(centre + TAU * float(i) / float(_BURST_STROKES))
			draw_line(dir * (radius + 4.0 * t), dir * (radius + 4.0 + 12.0 * t), burst, _WIDTH)
	if _rebooting or capacity <= 0:
		return

	var frac := clampf((float(capacity) - _lost) / float(capacity), 0.0, 1.0)
	var half := PI if arc_deg >= 360.0 else deg_to_rad(arc_deg) * 0.5
	if _refilling_after_break:
		half *= frac  # the refill grows back from the centre
	var alpha := 0.25 + 0.55 * frac
	var width := _WIDTH
	if _flare_left > 0.0:
		alpha = 1.0
		width = _WIDTH * 1.5
	var color := Color(COLOR, alpha * fade)
	if half >= PI:
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, color, width)
	elif half > 0.0:
		draw_arc(Vector2.ZERO, radius, centre - half, centre + half, maxi(4, int(half * 16.0)), color, width)
