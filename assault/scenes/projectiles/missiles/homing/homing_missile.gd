class_name homing_missile
extends Area2D

## The player's homing rocket. Unclaimed, it flies at its `locked_target` (instant turns) or straight. Phase 9 §2.5
## (docs/plans/cmug23onr001pm52w9swwophy/3-plan.md) adds the seeking-ordnance retarget contract a claimer (the Hacker
## Frigate's dart) calls through `SeekingOrdnance`, duck-typed like `is_armored()`:
##   - `can_be_retargeted()`, `retarget(target, seconds, source)`, `is_retargeted()`, `jam_guidance(source)`,
##     `signal retargeted(source)` and `signal retarget_ended()`.
##   - A claimed ("hijacked") rocket turns at `hijack_turn_rate` toward its new target at `hijack_speed` for its window,
##     then fizzles. It hurts the player only through a small `ContactBlast` once armed (`hijack_arm_seconds` and
##     `hijack_arm_clearance`), keeps its full HitBox damage on enemies (the lure), and is shot down by one player
##     bullet through a `HurtBox` (512 / 64) that is open only while hijacked.
##   - Inside a lit jammer field (`Hazards.jammer_at`) every seeker flies straight, hijacked or not.
## Every end of life goes through `_finish()`: blast, fizzle, shoot-down, a hit, source death and the
## `ProjectileLifetime` backstop, so `retarget_ended` always fires for a hijack and `expired` fires once.
## The hijack tuning lives on `homing_missile.tscn` (the Ph5 rule: weapon tuning lives in the projectile scene).

## Emitted once per life, by the `ProjectileLifetime` child when a time, distance or world-rect rule trips (Assault
## world rect, 6 s, 2400 px) or by `_finish()` through the same latch. Wired to `_on_expired()`.
signal expired
## A claimer took this rocket over; [param source] is the claimer (null when it named none).
signal retargeted(source: Node)
## A hijack ended: blast, fizzle, shoot-down, a hit, source death or the lifetime backstop. Once per hijack.
signal retarget_ended()

## IDEAS §21: amber = hacked, shown on the rocket's light (its sprite tint and trail), never a recoloured hull.
const _AMBER := Color(1.0, 0.7, 0.3)
const _AMBER_TRAIL_DEATH := Color(1.0, 0.35, 0.05, 0.0)
const _BRACKET_RADIUS := 12.0
const _BRACKET_TICK := 4.0
const _BRACKET_SPIN := 3.0
## The clock rule: a countdown is over at `x <= 1e-6`.
const _EPS := 1e-6

@export var speed: float = 500.0
@export var locked_target: Node

@export_group("Hijack")
## px/s the hijacked rocket eases to over `hijack_ease_seconds`.
@export var hijack_speed: float = 380.0
## rad/s; the hijacked turn is limited (`Steering.turn_toward`), so a hijacked rocket can be dodged.
@export var hijack_turn_rate: float = 1.6
## The window a claimer gets when it passes a negative `seconds`; then the rocket fizzles.
@export var hijack_seconds: float = 2.5
@export var hijack_ease_seconds: float = 0.5
## The only damage a hijacked rocket deals the player: a `ContactBlast` (layer 256).
@export var hijack_blast_damage: int = 18
@export var hijack_blast_radius: float = 40.0
@export var hijack_blast_frames: int = 3
## Armed and this close to the target's centre -> the blast.
@export var hijack_trigger_radius: float = 30.0
## Arming: this long since the claim AND at least `hijack_arm_clearance` px from the target on some tick since it.
@export var hijack_arm_seconds: float = 0.25
@export var hijack_arm_clearance: float = 60.0
## How long the claim's tether line shows after a successful `retarget()`.
@export var tether_seconds: float = 0.3

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _hit_box: HitBox = $HitBox
@onready var _hit_shape: CollisionShape2D = $HitBox/CollisionShape2D
@onready var _hurt_box: HurtBox = $HurtBox
@onready var _hurt_shape: CollisionShape2D = $HurtBox/CollisionShape2D
@onready var _lifetime: ProjectileLifetime = $ProjectileLifetime
@onready var _pop: ExplosionEffect = get_node_or_null("Pop") as ExplosionEffect

var _trail: RocketTrail
var _done: bool = false
## A latch: a rocket is claimed at most once.
var _claimed: bool = false
var _hijacked: bool = false
var _hijack_target: Node2D = null
var _hijack_source: Node = null
var _had_source: bool = false
var _hijack_left: float = 0.0
var _since_claim: float = 0.0
var _cleared: bool = false
var _guidance_jammed: bool = false
var _heading: Vector2 = Vector2.UP
var _tether_left: float = 0.0
var _bracket_angle: float = 0.0


func _ready() -> void:
	animated_sprite.play("default")
	_trail = RocketTrail.new()
	add_child(_trail)
	expired.connect(_on_expired)
	add_to_group(SeekingOrdnance.GROUP)


func _physics_process(delta: float) -> void:
	if _done:
		return
	if _hijacked:
		_hijack_step(delta)
	elif locked_target and locked_target.is_inside_tree() and not _jammed_here():
		_fly_to_target(delta)
	else:
		_fly_forward(delta)


func _fly_to_target(delta: float) -> void:
	## A target made of parts (the Ram Corvette's plates) names the point to steer at, so a rocket
	## fired from behind meets a plate instead of parking at the hull centre.
	var aim: Vector2 = locked_target.global_position
	if locked_target.has_method("homing_point"):
		aim = locked_target.homing_point(global_position)
	var direction := (aim - global_position).normalized()
	if Hazards.count() > 0:
		direction = Hazards.bend_heading(direction, speed, global_position, delta, hazard_pull_scale())
	rotation = direction.angle() + PI / 2
	global_position += direction * speed * delta


func _fly_forward(delta: float) -> void:
	var forward := Vector2.UP.rotated(rotation)
	if Hazards.count() > 0:
		var bent := Hazards.bend_heading(forward, speed, global_position, delta, hazard_pull_scale())
		if bent != forward:
			forward = bent
			rotation = bent.angle() + PI / 2
	global_position += forward * speed * delta


## One hijacked tick: source check, clocks, eased speed, the turn-limited heading, the move, arming and the blast,
## then the end of the window.
func _hijack_step(delta: float) -> void:
	if _had_source and not is_instance_valid(_hijack_source):
		_finish(false)
		return
	_since_claim += delta
	_hijack_left -= delta
	if _tether_left > 0.0:
		_tether_left -= delta
		if _tether_left <= _EPS:
			_tether_left = 0.0
	_bracket_angle = wrapf(_bracket_angle + _BRACKET_SPIN * delta, 0.0, TAU)
	var v := hijack_speed
	if hijack_ease_seconds > 0.0:
		v = lerpf(speed, hijack_speed, clampf(_since_claim / hijack_ease_seconds, 0.0, 1.0))
	var has_target := _target_alive()
	if has_target and not _guidance_jammed and not _jammed_here():
		_heading = Steering.turn_toward(_heading, _hijack_target.global_position - global_position, hijack_turn_rate, delta)
	if Hazards.count() > 0:
		_heading = Hazards.bend_heading(_heading, v, global_position, delta, hazard_pull_scale())
	global_position += _heading * v * delta
	rotation = _heading.angle() + PI / 2
	if has_target:
		var d := global_position.distance_to(_hijack_target.global_position)
		if d >= hijack_arm_clearance:
			_cleared = true
		if _cleared and _since_claim >= hijack_arm_seconds - _EPS and d <= hijack_trigger_radius:
			ContactBlast.spawn(get_parent(), global_position, hijack_blast_radius, hijack_blast_damage, hijack_blast_frames)
			_finish(true)
			return
	if _hijack_left <= _EPS:
		_finish(false)
		return
	queue_redraw()


func _target_alive() -> bool:
	return is_instance_valid(_hijack_target) and _hijack_target.is_inside_tree()


## Seekers fly straight inside a lit jammer field (Phase 9 §2.2). `count()` first: no hazard, no walk.
func _jammed_here() -> bool:
	return Hazards.count() > 0 and Hazards.jammer_at(global_position) != null


# --- The retarget contract (SeekingOrdnance) ----------------------------------------------------------------------


## False once claimed (a rocket is claimed at most once), once done, outside the tree, or inside a lit jammer field.
func can_be_retargeted() -> bool:
	return not _claimed and not _done and is_inside_tree() and not _jammed_here()


## Hijacks the rocket toward [param target] for [param seconds] (a negative value uses this rocket's own
## `hijack_seconds`). [param source] is the claimer: freeing it fizzles the rocket; null means none to lose.
## Refused (false, nothing changes) for an invalid target or when `can_be_retargeted()` is false.
func retarget(target: Node2D, seconds: float, source: Node) -> bool:
	if not is_instance_valid(target) or not can_be_retargeted():
		return false
	_claimed = true
	_hijacked = true
	_hijack_target = target
	_hijack_source = source
	_had_source = source != null
	_hijack_left = seconds if seconds >= 0.0 else hijack_seconds
	_since_claim = 0.0
	_heading = Vector2.UP.rotated(rotation)
	_cleared = global_position.distance_to(target.global_position) >= hijack_arm_clearance
	_guidance_jammed = false
	locked_target = null
	_tether_left = tether_seconds if _had_source else 0.0
	_show_tell()
	# Deferred: a claim can come from a physics callback (the dart's area_entered).
	_hurt_box.set_deferred("monitoring", true)
	_hurt_box.set_deferred("monitorable", true)
	retargeted.emit(source)
	EventBus.player_ordnance_hijacked.emit(self, source)
	queue_redraw()
	return true


func is_retargeted() -> bool:
	return _hijacked and not _done


## EMP (Phase 9 §2.6): drops the lock, so the rocket flies forward; a hijacked rocket also loses its guidance and
## flies straight until its window ends.
func jam_guidance(_source: Node) -> void:
	locked_target = null
	if _hijacked:
		_guidance_jammed = true


## True while the claim's tether line is drawn: `tether_seconds` after the claim, while the source still exists.
func is_tether_visible() -> bool:
	return _hijacked and not _done and _tether_left > 0.0 \
			and is_instance_valid(_hijack_source) and _hijack_source is Node2D


# --- End of life ----------------------------------------------------------------------------------------------------


## The `ProjectileLifetime` expired (or `_finish()` emitted through its latch): the backstop end, no blast.
func _on_expired() -> void:
	if not _done:
		_finish(false, true)


## The one end of life. Latches first, so it runs once; a hijack's end pops and emits `retarget_ended`; every area is
## closed deferred (this can run inside a physics callback, the `EnemyRocket._mark_done()` pattern); `expired` goes
## out once through the lifetime's own latch; then the rocket frees itself at the end of the frame. Unlike
## `EnemyRocket` it does not wait two ticks: that delay exists for a pool that re-parents a live rocket, and this
## rocket is never pooled.
func _finish(blasted: bool, from_expiry: bool = false) -> void:
	if _done:
		return
	_done = true
	var was_hijacked := _hijacked
	_hijacked = false
	if was_hijacked:
		if OS.is_stdout_verbose():
			print("[homing_missile] hijack ended: %s" % ("blast" if blasted else "no blast"))
		_pop_here()
		retarget_ended.emit()
	_hit_box.set_deferred("monitoring", false)
	_hit_box.set_deferred("monitorable", false)
	_hurt_box.set_deferred("monitoring", false)
	_hurt_box.set_deferred("monitorable", false)
	_hit_shape.set_deferred("disabled", true)
	_hurt_shape.set_deferred("disabled", true)
	hide()
	_lifetime.set_physics_process(false)
	if not from_expiry:
		_lifetime.expire_now()
	queue_free()


func _pop_here() -> void:
	if _pop:
		_pop.explode(global_position, get_parent())


## Guided ordnance bends in gravity wells and anomalies (`Hazards.bend_heading()`, speed unchanged).
func hazard_pull_scale() -> float:
	return 1.0


func _on_hit_box_area_entered(area: Area2D) -> void:
	# The self-hit guard: never this rocket's own shoot-down HurtBox, a salvo-mate's, or any other player homing
	# rocket (only primary fire shoots a hijacked one down).
	if _done or _is_player_homing(area.get_parent()):
		return
	if _hit_is_deflected(area):
		return
	_finish(false)


## The shoot-down: one damaging player hit on the HurtBox, which is open only while hijacked.
func _on_hurt_box_received_damage(_damage: int) -> void:
	if _hijacked:
		_finish(false)


## Script identity rather than `is homing_missile`: a precaution, so this script never names its own `class_name`
## (DECISIONS.md, Phase 9 t4). No subclass exists, so the two agree.
func _is_player_homing(node: Node) -> bool:
	return node != null and node.get_script() == get_script()


## True when the hurtbox we just overlapped refused to apply damage (e.g. the space-station core
## while any turret still lives). Duck-typed against `is_armored()`, same idiom as
## `bullet.gd::_hit_is_deflected` — a rocket gets the same exemption a bullet already has, so it
## survives crossing the boss's armoured core instead of detonating on it before reaching a turret.
func _hit_is_deflected(area: Area2D) -> bool:
	return ArmorQuery.deflects(area, get_node_or_null("HitBox") as HitBox)


# --- The tell -------------------------------------------------------------------------------------------------------


func _show_tell() -> void:
	animated_sprite.self_modulate = _AMBER
	if _trail != null:
		_trail.set_colors(_AMBER, _AMBER_TRAIL_DEATH)


## While hijacked: a spinning target bracket (four corner ticks, world-aligned), and for `tether_seconds` after the
## claim a line from the claimer to the rocket, white at the claimer, amber here, fading out.
func _draw() -> void:
	if not is_retargeted():
		return
	if is_tether_visible():
		var k := _tether_left / tether_seconds if tether_seconds > 0.0 else 0.0
		var from := to_local((_hijack_source as Node2D).global_position)
		draw_polyline_colors(PackedVector2Array([from, Vector2.ZERO]),
				PackedColorArray([Color(1.0, 1.0, 1.0, k), Color(_AMBER, k)]), 1.5)
	draw_set_transform(Vector2.ZERO, -rotation + _bracket_angle)
	for i in 4:
		var corner := Vector2.from_angle(PI / 4.0 + i * PI / 2.0) * _BRACKET_RADIUS
		var next := Vector2.from_angle(PI / 4.0 + (i + 1) * PI / 2.0) * _BRACKET_RADIUS
		var prev := Vector2.from_angle(PI / 4.0 + (i - 1) * PI / 2.0) * _BRACKET_RADIUS
		draw_line(corner, corner + (next - corner).normalized() * _BRACKET_TICK, _AMBER, 1.0)
		draw_line(corner, corner + (prev - corner).normalized() * _BRACKET_TICK, _AMBER, 1.0)
	draw_set_transform(Vector2.ZERO, 0.0)
