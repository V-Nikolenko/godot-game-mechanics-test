## EnemyRocket - the enemy rocket family's common contract (docs/plans/cmufs7elw001pnm2xr3b6fteb/3-plan.md §2.6,
## §2.7). One script; `kind` and the authored exports differ per scene, and **the tuning lives in those exports** (one
## source of truth per kind, whoever fires it; a difficulty tier sets exports before `launch()`).
##
## A sibling of `EnemyOrdnance`, not new kinds on it: a rocket has a heading, a nose-up rotation, a launch boost and an
## impact trigger. Never in group `enemies`, never scored.
##
## Contract with its launcher (a ship's `BulletPool`, or a fixture):
##   - `signal expired` - emitted exactly once per life: a detonation, a shoot-down or a lifetime fizzle. A pool
##     recycles on it; an unpooled rocket is freed by `expired -> queue_free`. Nothing here frees itself. A detonation
##     or a shoot-down emits it two physics ticks later (the rocket hidden meanwhile) - see `_end_after_overlaps()`.
##   - `reset()` restores the authored exports and a fresh, unlaunched state (`BulletPool.acquire()` calls it).
##   - `launch(dir, aim_point, launcher)` starts a life. The launcher passes nothing else; it may answer duck-typed
##     `launch_velocity() -> Vector2` (its component along `dir` is inherited) and `rocket_clear_radius() -> float`.
##
## Collision (no layer renamed):
##   - `HitBox` layer 32 (alone), mask 128 | 512, `ROCKET`. Closed until the rocket is clear of its launcher's CURRENT
##     position by `rocket_clear_radius() + body_radius + arm_clearance` - the rocket alone owns that rule. Enemy
##     hurtboxes (mask 1121), enemy ordnance, Ram plates and asteroids see it and take `impact_damage`; the player's and
##     allies' hurtboxes (mask 1281) never do - the HitBox only sees them and detonates the rocket, and the
##     `ContactBlast` (256) that follows is their only damage.
##   - `HurtBox` layer 512, mask 96: the shoot-down. Its `received_damage` is NOT connected; the rocket resolves every
##     area in its own `area_entered`: another rocket's HitBox and a `CONTACT` HitBox (the ally fighter's ram box on 64)
##     are ignored, anything else (a player bullet or missile) defuses it - a pop, no blast.
##
## It writes its own `global_position` and `rotation` (nose-up art: `rotation = heading.angle() + PI / 2`, the player
## missiles' convention, so `RocketTrail`'s local +Y exhaust leaves the tail) on ONE accumulated clock of physics deltas.
class_name EnemyRocket
extends Area2D

signal expired

enum Kind { DUMB, PURSUIT, CLUSTER, WARHEAD, SUBMUNITION }

@export var kind: Kind = Kind.DUMB

@export_group("Flight")
## Speed during the boost (plus the launcher's inherited speed along the launch direction).
@export var launch_speed: float = 140.0
@export var cruise_speed: float = 520.0
## Straight, unsteered flight at `launch_speed`: the visible launch.
@export var boost_seconds: float = 0.25
## px/s^2 from the boost speed to `cruise_speed` after the boost.
@export var accel: float = 900.0

@export_group("Guidance")
## rad/s. 0 = a straight (dumb) rocket.
@export var turn_rate: float = 0.0
## Seconds of steering after the boost; the heading freezes afterwards.
@export var guidance_seconds: float = 0.0
## Longest intercept (s) the rocket leads; beyond it, it aims at the player's position this far ahead.
@export var lead_max: float = 0.8

@export_group("Damage")
## What the impact deals to enemies, ordnance, plates and asteroids. The player never takes it.
@export var impact_damage: int = 16
@export var blast_radius: float = 36.0
## The player-facing number: the blast is the only thing that hurts the player or an ally.
@export var blast_damage: int = 16
@export var blast_frames: int = 3

@export_group("Body")
## Extra px past the launcher's clear radius and the rocket's own radius before the impact HitBox opens.
@export var arm_clearance: float = 8.0
@export var body_radius: float = 6.0

@export_group("Lifetime")
## Pushed into the `ProjectileLifetime` child; expiry by it is a fizzle (pop, no blast).
@export var max_time: float = 4.0
@export var max_distance: float = 1800.0

@export_group("Cluster")
## CLUSTER: splits when the player is within this many px, or `split_time` s after launch if never that close.
@export var split_distance: float = 260.0
@export var split_time: float = 2.0
@export_range(3, 5) var cluster_count: int = 4
## Total spread of the children, centred on the direction to the predicted point.
@export var cluster_fan_deg: float = 36.0
## What a CLUSTER splits into (unpooled, self-freeing). Set on cluster_rocket.tscn only.
@export var submunition_scene: PackedScene

@export_group("Proximity")
## WARHEAD: radius of the `ProximityArea` that notices the player's hurtbox.
@export var trigger_radius: float = 70.0
## Seconds after launch before the proximity trigger is live (independent of the launcher clearance).
@export var prox_arm_seconds: float = 0.6
## From the trigger to the detonation: the rocket is stopped dead and blinking.
@export var warning_time: float = 0.4

## Properties `reset()` restores. Captured once in `_ready()`.
const _RESET_PROPS: Array[StringName] = [
	&"launch_speed", &"cruise_speed", &"boost_seconds", &"accel", &"turn_rate", &"guidance_seconds",
	&"lead_max", &"impact_damage", &"blast_radius", &"blast_damage", &"blast_frames", &"arm_clearance",
	&"body_radius", &"max_time", &"max_distance", &"split_distance", &"split_time", &"cluster_count",
	&"cluster_fan_deg", &"trigger_radius", &"prox_arm_seconds", &"warning_time",
]

var _authored: Dictionary = {}
var _heading: Vector2 = Vector2.DOWN
var _speed: float = 0.0
var _aim: Vector2 = Vector2.ZERO
var _clock: float = 0.0
var _launched: bool = false
var _armed: bool = false
var _done: bool = false
## Set by a detonation or a shoot-down: physics ticks left before `expired` goes out (see `_end_after_overlaps()`).
var _expire_in: int = 0
var _launcher: Node = null
var _had_launcher: bool = false
var _clear_radius: float = 0.0
var _launch_point: Vector2 = Vector2.ZERO
## WARHEAD: the proximity trigger has fired; the rocket is stopped and counting `_warning_clock` to its blast.
var _triggered: bool = false
var _warning_clock: float = 0.0

@onready var _hit_box: HitBox = $HitBox as HitBox
@onready var _hit_shape: CollisionShape2D = $HitBox/CollisionShape2D as CollisionShape2D
@onready var _hurt_box: HurtBox = $HurtBox as HurtBox
@onready var _hurt_shape: CollisionShape2D = $HurtBox/CollisionShape2D as CollisionShape2D
@onready var _lifetime: ProjectileLifetime = $ProjectileLifetime as ProjectileLifetime
@onready var _proximity: Area2D = get_node_or_null("ProximityArea") as Area2D
@onready var _proximity_shape: CollisionShape2D = get_node_or_null("ProximityArea/CollisionShape2D") as CollisionShape2D
@onready var _pop: ExplosionEffect = get_node_or_null("Pop") as ExplosionEffect
@onready var _blink: Sprite2D = get_node_or_null("BlinkLight") as Sprite2D


func _ready() -> void:
	for prop in _RESET_PROPS:
		_authored[prop] = get(prop)
	# Scene instances share sub-resources; the radii are set per instance.
	_hit_shape.shape = _hit_shape.shape.duplicate()
	_hurt_shape.shape = _hurt_shape.shape.duplicate()
	if _proximity_shape != null:
		_proximity_shape.shape = _proximity_shape.shape.duplicate()
	_apply_exports()
	_hit_box.area_entered.connect(_on_hit_box_area_entered)
	_hurt_box.area_entered.connect(_on_hurt_box_area_entered)
	expired.connect(_on_expired)
	if _blink != null:
		_blink.texture = _build_glow_texture()
	_update_blink()
	queue_redraw()


## Restores the authored exports and a fresh, unlaunched state. Called by `BulletPool.acquire()`.
func reset() -> void:
	for prop in _RESET_PROPS:
		set(prop, _authored[prop])
	_heading = Vector2.DOWN
	_speed = 0.0
	_aim = Vector2.ZERO
	_clock = 0.0
	_launched = false
	_armed = false
	_done = false
	_expire_in = 0
	_launcher = null
	_had_launcher = false
	_clear_radius = 0.0
	_triggered = false
	_warning_clock = 0.0
	modulate = Color.WHITE
	show()
	_apply_exports()
	if _proximity != null:
		_proximity.set_deferred("monitoring", true)
	_hit_box.set_deferred("monitoring", false)
	_hit_box.set_deferred("monitorable", false)
	_hurt_box.set_deferred("monitoring", true)
	_hurt_box.set_deferred("monitorable", true)
	_hit_shape.set_deferred("disabled", false)
	_hurt_shape.set_deferred("disabled", false)
	_lifetime.set_physics_process(true)
	_lifetime.reset()
	_update_blink()
	queue_redraw()


## Starts a life. `launcher` may be null (a submunition): arming then measures from the launch point with radius 0.
func launch(dir: Vector2, aim_point: Vector2, launcher: Node) -> void:
	_heading = dir.normalized() if dir != Vector2.ZERO else Vector2.DOWN
	var inherited := 0.0
	_launcher = launcher if is_instance_valid(launcher) else null
	_had_launcher = _launcher != null
	_clear_radius = 0.0
	if _launcher != null:
		if _launcher.has_method(&"launch_velocity"):
			inherited = maxf(0.0, (_launcher.launch_velocity() as Vector2).dot(_heading))
		if _launcher.has_method(&"rocket_clear_radius"):
			_clear_radius = float(_launcher.rocket_clear_radius())
	_speed = launch_speed + inherited
	_aim = aim_point
	_launch_point = global_position
	_clock = 0.0
	_launched = true
	# Exports set after `acquire()` (a difficulty tier) reach the children here.
	_apply_exports()
	rotation = _heading.angle() + PI / 2.0
	queue_redraw()


## The current unit heading.
func heading() -> Vector2:
	return _heading


func speed() -> float:
	return _speed


## Heavy, guided ordnance bends in gravity wells and anomalies (`Hazards.bend_heading()`, speed unchanged); 1.0 = fully.
func hazard_pull_scale() -> float:
	return 1.0


## True once the impact HitBox has been opened (it is clear of its launcher).
func is_armed() -> bool:
	return _armed


## True inside the steering window: after the boost, before `boost_seconds + guidance_seconds`.
func is_guiding() -> bool:
	return _launched and not _done and not _triggered and turn_rate > 0.0 \
			and _clock >= boost_seconds and _clock < boost_seconds + guidance_seconds


## The point the rocket is steering at: the launch aim until guidance replaces it.
func aim_point() -> Vector2:
	return _aim


func _physics_process(delta: float) -> void:
	_tick(delta)


## One flight step. Tests hand-tick it (physics process off) with a fixed delta.
func _tick(delta: float) -> void:
	if _expire_in > 0:
		_expire_in -= 1
		if _expire_in == 0:
			expired.emit()
		return
	if _done or not _launched:
		return
	if _triggered:
		# Stopped dead: nothing moves until the blast.
		_warning_clock += delta
		_clock += delta
		if _warning_clock >= warning_time - 1e-6:
			_detonate()
		_update_blink()
		queue_redraw()
		return
	if kind == Kind.CLUSTER and _should_split(delta):
		_split()
		return
	if is_guiding():
		_steer(delta)
	if Hazards.count() > 0:
		_heading = Hazards.bend_heading(_heading, _speed, global_position, delta, hazard_pull_scale())
	if _clock >= boost_seconds:
		_speed = move_toward(_speed, cruise_speed, accel * delta)
	global_position += _heading * _speed * delta
	rotation = _heading.angle() + PI / 2.0
	_clock += delta
	if not _armed:
		_update_arming()
	if kind == Kind.WARHEAD and _clock >= prox_arm_seconds - 1e-6 and _player_in_range():
		_triggered = true
		_warning_clock = 0.0
		_speed = 0.0
	_update_blink()
	queue_redraw()


## WARHEAD: a POLL of the proximity overlaps, not an `area_entered`, so a player already inside when the trigger
## arms still sets it off (the Ph4 B1b rule).
func _player_in_range() -> bool:
	if _proximity == null:
		return false
	for area in _proximity.get_overlapping_areas():
		if area.collision_layer & CollisionLayers.PLAYER_HURTBOX:
			return true
	return false


## True once the proximity trigger has fired and the rocket is counting down to its blast.
func is_triggered() -> bool:
	return _triggered


## CLUSTER: within `split_distance` of the player, or on the tick that reaches `split_time` since launch.
func _should_split(delta: float) -> bool:
	if _clock + delta >= split_time - 1e-6:
		return true
	var target := TargetInfo.player(get_tree())
	return target.has_target and global_position.distance_to(target.position) <= split_distance


## CLUSTER: gone, not exploded. `cluster_count` unpooled submunitions go into the container (this rocket's parent),
## fanned across `cluster_fan_deg` and centred on the predicted point; `expired` follows with no blast.
func _split() -> void:
	if _done:
		return
	_mark_done()
	var parent := get_parent()
	if submunition_scene != null and parent != null:
		var children: Array[EnemyRocket] = []
		for i in maxi(cluster_count, 1):
			children.append(submunition_scene.instantiate() as EnemyRocket)
		var child_speed := children[0].launch_speed
		var centre := _heading
		var target := TargetInfo.player(get_tree())
		if target.has_target:
			var predicted := target.predicted_position(
					global_position.distance_to(target.position) / maxf(child_speed, 1.0))
			if predicted.distance_to(global_position) > 1e-3:
				centre = (predicted - global_position).normalized()
		var n := children.size()
		for i in n:
			var child := children[i]
			var offset_deg := 0.0 if n == 1 else -cluster_fan_deg * 0.5 + cluster_fan_deg * float(i) / float(n - 1)
			var dir := centre.rotated(deg_to_rad(offset_deg))
			parent.add_child(child)
			child.global_position = global_position
			child.reset()
			child.expired.connect(child.queue_free)
			child.launch(dir, global_position + dir * 400.0, null)
	_pop_here()
	_end_after_overlaps()


## Lead pursuit with a turn cap: the intercept point, or the player's position `lead_max` ahead when the intercept
## fails or lies further out than that. No player: no turn at all (the heading is kept).
func _steer(delta: float) -> void:
	var target := TargetInfo.player(get_tree())
	if not target.has_target:
		return
	var result := target.intercept(global_position, _speed)
	if result.ok and float(result.time) <= lead_max:
		_aim = result.point
	else:
		_aim = target.predicted_position(lead_max)
	_heading = Steering.turn_toward(_heading, _aim - global_position, turn_rate, delta)


func _update_arming() -> void:
	var from := _launch_point
	var radius := 0.0
	if _had_launcher:
		if not is_instance_valid(_launcher) or not (_launcher as Node).is_inside_tree():
			_arm()
			return
		from = (_launcher as Node2D).global_position
		radius = _clear_radius
	if global_position.distance_to(from) >= radius + body_radius + arm_clearance:
		_arm()


func _arm() -> void:
	_armed = true
	_hit_box.set_deferred("monitoring", true)
	_hit_box.set_deferred("monitorable", true)


## The exports the children carry: impact damage, both radii and the lifetime caps.
func _apply_exports() -> void:
	_hit_box.damage = impact_damage
	_hit_box.damage_type = HitBox.DamageType.ROCKET
	(_hit_shape.shape as CircleShape2D).radius = body_radius
	(_hurt_shape.shape as CircleShape2D).radius = body_radius + 2.0
	_lifetime.max_time = max_time
	_lifetime.max_distance = max_distance
	if _proximity_shape != null:
		(_proximity_shape.shape as CircleShape2D).radius = trigger_radius


func _on_hit_box_area_entered(area: Area2D) -> void:
	if _done or not _armed:
		return
	if area.get_parent() is EnemyRocket:
		return
	if ArmorQuery.deflects(area, _hit_box):
		return
	_detonate()


func _on_hurt_box_area_entered(area: Area2D) -> void:
	if _done:
		return
	var hb := area as HitBox
	if hb == null or hb.get_parent() is EnemyRocket:
		return
	if hb.damage_type == HitBox.DamageType.CONTACT:
		return
	_defuse()


## Blasts into the parent and ends the life. Exactly once: `_done` latches before anything else.
func _detonate() -> void:
	if _done:
		return
	_mark_done()
	ContactBlast.spawn(get_parent(), global_position, blast_radius, blast_damage, blast_frames)
	_pop_here()
	_end_after_overlaps()


## Shot down: a pop, no blast, end of life.
func _defuse() -> void:
	if _done:
		return
	_mark_done()
	_pop_here()
	_end_after_overlaps()


## Ends the life two physics ticks later, hidden meanwhile. A detonation or a shoot-down happens inside a physics
## callback, while the impact HitBox (or the HurtBox) still overlaps what it met. A pool recycles on `expired` by
## re-parenting the rocket, and `Area2D` re-emits `area_entered` for an overlapping area that re-enters the tree while
## the physics server still reports the pair - so recycling at once hits the enemy a second time. `_mark_done()` closes
## the areas AND disables their shapes (deferred, at the end of this frame; switching `monitorable` off alone leaves
## the existing pair in place - measured), the server drops the pair in this frame's step, and the exit is delivered in
## the next frame's query flush, which Godot runs before that frame's `_physics_process`: so the second tick is the
## first clean one. Pinned by `test_enemy_rockets.gd` (the enemy takes `impact_damage` exactly once).
func _end_after_overlaps() -> void:
	hide()
	_expire_in = 2


## Any `expired` - ours or the `ProjectileLifetime` backstop's - ends the life. From the backstop it is a fizzle.
func _on_expired() -> void:
	if _done:
		return
	_mark_done()
	_pop_here()


func _pop_here() -> void:
	if _pop:
		_pop.explode(global_position, get_parent())


func _mark_done() -> void:
	if _done:
		return
	_done = true
	# Every area is closed deferred: this can run inside a physics callback.
	_hit_box.set_deferred("monitoring", false)
	_hit_box.set_deferred("monitorable", false)
	_hurt_box.set_deferred("monitoring", false)
	_hurt_box.set_deferred("monitorable", false)
	_hit_shape.set_deferred("disabled", true)
	_hurt_shape.set_deferred("disabled", true)
	if _proximity != null:
		_proximity.set_deferred("monitoring", false)
	# Keeps the backstop from emitting a second `expired` in the frame this life ended.
	_lifetime.set_physics_process(false)


## The body is the scene's `Sprite2D` (nose-up art). Only the WARHEAD's warning ring is drawn: the blast radius it is
## about to fill, faint, while it is stopped and counting down.
func _draw() -> void:
	if _triggered:
		draw_arc(Vector2.ZERO, blast_radius, 0.0, TAU, 40, Color(1.0, 0.3, 0.15, 0.35), 1.5)


## The WARHEAD's `BlinkLight`: a dim steady glow in flight, a 12 Hz blink between the trigger and the blast.
func _update_blink() -> void:
	if _blink == null:
		return
	var alpha := 0.35
	if _triggered:
		alpha = 1.0 if fmod(_warning_clock * 12.0, 1.0) < 0.5 else 0.0
	_blink.modulate = Color(1.0, 0.55, 0.2, alpha)


## A soft radial dot, built in code (never scene-authored: the sprite-transparency sweep reads scene textures).
static func _build_glow_texture() -> Texture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color.WHITE)
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 12
	texture.height = 12
	return texture
