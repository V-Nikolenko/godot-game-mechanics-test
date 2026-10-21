## A dead hull or a derelict structure: solid cover for ships, sight lines and shots of BOTH sides (plan §2.8,
## docs/plans/cmug23om70001m52wqfwclf3l/3-plan.md; build choices in docs/plans/cmvg30aax007rqs2x14trnuf9/3-plan.md).
##
## - The body is on layer 1 (ENVIRONMENT): every ship body stops on it, `LineOfSight.clear()` stops at it through
##   `blocks_line_of_sight()`, and the player's beam stops at it (and cannot cut it: the beam damages only
##   `enemies` / `asteroids`).
## - A `HurtBox` the size of the body takes player bullets, player rockets and enemy rockets into `Health`. Enemy rounds
##   stop on the `ContactHitBox` (1024) because this answers `stops_enemy_rounds()`; an asteroid does not.
## - The `ContactHitBox` shares the body's shape, so only a wreck that MOVES into a ship hurts it: a ship flying into a
##   still wreck comes to rest touching the body, and no ship's hurtbox is larger than its body (gated in test_wreck.gd),
##   so it never reaches the box. The box arms `contact_arm_delay` after entering the tree, so a wreck born on top of the
##   player does not hurt it at once.
## - It is a hazard (`kind = &"wreck"`, no forces) the AI avoids and claims as cover; never in `enemies`, never scored.
##
## Moved by its own position writes (the `SmallAsteroid` drift precedent; it is not an enemy, so the mover rule does not
## apply). One owner: Open Space retires it (a fade) at the end of `lifetime`, Assault when `ProjectileLifetime`
## (world rect + 30 s cap) emits `expired`; HP 0 frees it with an explosion. Clocks are accumulated `delta`, never a `Timer`.
class_name Wreck
extends CharacterBody2D

## `ProjectileLifetime`'s host signal (Assault: the wreck left the world rect, or the 30 s cap). Ends in `retire()`.
signal expired
## HP reached 0. Emitted once, just before the wreck frees itself (t12 hangs the explosive blast on it).
signal destroyed(world_position: Vector2)

const RETIRE_FADE := 0.5
const GROUP: StringName = &"wrecks"
## Penetration along the drift (px) at which the wreck holds even when no hit has registered (see `_yield`).
const YIELD_DEPTH := 1.5

## True for every wreck and structure; `LineOfSight` reads it through `blocks_line_of_sight()`.
@export var blocks_los: bool = true
## Open Space drift, px/s. In Assault only its x is used (see `assault_drift`).
@export var drift_velocity: Vector2 = Vector2.ZERO
## Open Space life in seconds (0 = permanent). The last `lifetime_fade` seconds are a fade.
@export var lifetime: float = 40.0
@export var lifetime_fade: float = 2.0
## Assault: the wreck always drifts down at this speed (px/s), whatever y velocity it inherited.
@export var assault_drift: float = 60.0
@export var health_amount: int = 200
@export var contact_damage: int = 10
@export var contact_arm_delay: float = 0.6
@export_range(0.0, 1.0) var avoid_weight: float = 0.6
## Stop drifting into a ship body it touches (the clamp-edge rule). Off only in the test that proves the rule matters.
@export var yield_to_ships: bool = true

## Set by `spawn_into()`: a runtime wreck, as opposed to a structure placed in a scene (t11's alive cap counts these only).
var spawned: bool = false

@onready var _body_shape: CollisionShape2D = $CollisionShape2D
@onready var _health: Health = $Health
@onready var _hurt_box: HurtBox = $HurtBox
@onready var _contact: HitBox = $ContactHitBox
@onready var _contact_shape: CollisionShape2D = $ContactHitBox/CollisionShape2D
@onready var _lifetime: ProjectileLifetime = $ProjectileLifetime

var _info := HazardInfo.new()
var _age: float = 0.0
var _armed: bool = false
var _assault: bool = false
var _retiring: bool = false
var _fade_time: float = 0.0
var _fade_clock: float = 0.0
var _dead: bool = false
var _holding: bool = false
var _overlap_travel: float = 0.0
var _born_checked: bool = false
## Instance ids of ships the body already overlapped on its first tick; the yield ignores them until they separate.
var _ignored: Dictionary = {}
var _query: PhysicsShapeQueryParameters2D
var _hit_effect: HitEffect
var _explosion: ExplosionEffect
var _pending_transform: bool = false
var _at: Vector2 = Vector2.ZERO
var _rot: float = 0.0


## Adds the wreck to [param container] at the next message flush, at [param at] / [param rot]. Safe inside an
## `area_entered` callback (a kill by a bullet), where adding a body synchronously is refused. The deferred call is
## made on the WRECK (`HazardField.spawn_into` / `ContactBlast.spawn` pattern), so a freed container leaks nothing.
func spawn_into(container: Node, at: Vector2, rot: float = 0.0) -> void:
	_at = at
	_rot = rot
	_pending_transform = true
	spawned = true
	_attach.call_deferred(container)


## Untyped on purpose: a typed `Node` parameter makes the deferred call itself fail on a freed container.
## `queue_free()`, not `free()`: an object cannot free itself from inside its own deferred call.
func _attach(container) -> void:
	if is_instance_valid(container) and (container as Node).is_inside_tree():
		(container as Node).add_child(self)
	else:
		queue_free()


## A parentless Node2D's `global_position` is only its local position, so the stored transform is applied here.
func _enter_tree() -> void:
	if _pending_transform:
		global_position = _at
		rotation = _rot
		_pending_transform = false
	_assault = EnemyWorld.arena(get_tree()) != null
	if not _retiring:
		Hazards.register(self)


func _exit_tree() -> void:
	Hazards.unregister(self)


func _ready() -> void:
	add_to_group(GROUP)
	# Health clamps to max_health (default 100), so both are set.
	_health.max_health = health_amount
	_health.set_health(health_amount)
	_hurt_box.received_damage.connect(_on_received_damage)
	_health.amount_changed.connect(_on_health_changed)
	_contact.damage = contact_damage
	_contact.damage_type = HitBox.DamageType.CONTACT
	expired.connect(_on_expired)
	# A property, not the processing flag (READY would switch that back on): Open Space has no world rect and the
	# 30 s cap must not cut the 40 s Open Space life, nor ever end a permanent structure.
	if not _assault:
		_lifetime.max_time = 0.0
	_hit_effect = HitEffect.new()
	add_child(_hit_effect)
	_explosion = ExplosionEffect.new()
	add_child(_explosion)
	_refresh_info(Vector2.ZERO)


func _physics_process(delta: float) -> void:
	_age += delta
	if not _armed and not _retiring and _age >= contact_arm_delay:
		_armed = true
		_arm_contact()
	if _retiring:
		_fade_clock += delta
		modulate.a = clampf(1.0 - _fade_clock / _fade_time, 0.0, 1.0) if _fade_time > 0.0 else 0.0
		if _fade_clock >= _fade_time:
			queue_free()
			return
	elif not _assault and lifetime > 0.0 and _age >= lifetime - lifetime_fade:
		retire(lifetime_fade)
	var v := wanted_velocity()
	if yield_to_ships and v != Vector2.ZERO and not _retiring:
		v = _yield(v, delta)
	global_position += v * delta
	velocity = v
	_refresh_info(v)


## The drift this wreck wants this tick: Assault `(drift_velocity.x, assault_drift)`, Open Space `drift_velocity`.
func wanted_velocity() -> Vector2:
	if _assault:
		return Vector2(drift_velocity.x, assault_drift)
	return drift_velocity


## Takes the wreck out of play without vanishing on screen: unregistered, non-colliding and unhittable at once, then a
## fade of [param fade] seconds and `queue_free()`. Used by the Open Space lifetime end, the Assault `expired` and t11's
## alive cap. Final: once retiring, it takes no damage and never emits `destroyed`.
func retire(fade: float = RETIRE_FADE) -> void:
	if _retiring or _dead:
		return
	_retiring = true
	_fade_time = maxf(fade, 0.0)
	_fade_clock = 0.0
	_info.claimer_id = 0
	Hazards.unregister(self)
	# Layer writes are legal inside a physics flush; `monitoring` / `monitorable` are not.
	collision_layer = 0
	_hurt_box.collision_layer = 0
	_hurt_box.set_deferred(&"monitoring", false)
	_contact.collision_layer = 0
	_contact.set_deferred(&"monitorable", false)


## Arms the contact box. The SHAPE is switched on too, not just `monitorable`: Godot keeps an area pair it built while
## the box was unmonitorable (any hurtbox within the broadphase margin, a few px) and never reports that overlap once
## `monitorable` flips, so a wreck armed close to a ship would never hurt it. A shape switched on gets fresh pairs.
func _arm_contact() -> void:
	_contact.set_deferred(&"monitorable", true)
	_contact_shape.set_deferred(&"disabled", false)


func is_retiring() -> bool:
	return _retiring


func is_armed() -> bool:
	return _armed


func hazard_info() -> HazardInfo:
	_info.position = global_position if is_inside_tree() else position
	return _info


func try_claim(node: Node) -> bool:
	return _info.try_claim(node)


func release(node: Node) -> void:
	_info.release(node)


func is_claimed_by(node: Node) -> bool:
	return _info.is_claimed_by(node)


## Duck-typed by `LineOfSight`.
func blocks_line_of_sight() -> bool:
	return blocks_los


## Duck-typed by `EnemyBullet`: a round that touches this wreck's contact box ends there (two-sided cover).
func stops_enemy_rounds() -> bool:
	return true


## Duck-typed by `Bullet`: cover stops even the player's piercing Sniper Shot, as an asteroid does.
func stops_piercing() -> bool:
	return true


## The body circle's radius in world px (scene scale included).
func body_radius() -> float:
	var circle := _body_shape.shape as CircleShape2D if _body_shape != null else null
	if circle == null:
		return 0.0
	var s := _body_shape.global_scale.x if is_inside_tree() else _body_shape.scale.x * scale.x
	return circle.radius * absf(s)


func _on_received_damage(amount: int) -> void:
	if _dead or _retiring:
		return
	_hit_effect.burst()
	_health.decrease(amount)


func _on_health_changed(current: int) -> void:
	if _dead or _retiring or current > 0:
		return
	_dead = true
	_explosion.explode()
	destroyed.emit(global_position)
	queue_free()


func _on_expired() -> void:
	retire()


## The clamp-edge rule (t10 plan, revision 2): a wreck never keeps drifting into a ship body. It holds only once the
## ship's hurtbox has registered the contact box (so a drifting wreck still hurts what it runs into) or once it is
## `YIELD_DEPTH` deep (an unarmed box, a rolling player, a ship with no hurtbox); then it backs off by everything it
## travelled while overlapping that ship and waits until its next position is clear of every ship ahead. Ships the body
## already overlapped on its first tick (a wreck born on top of one) are ignored until they separate. Without this an
## idle Assault player at the bottom clamp edge, which nothing ever depenetrates, would sit inside a wreck for the whole
## crossing.
func _yield(v: Vector2, delta: float) -> Vector2:
	if not is_inside_tree():
		return v
	if not _born_checked:
		_born_checked = true
		for ship in _ships_overlapping(global_position, Vector2.ZERO, false):
			_ignored[ship.get_instance_id()] = true
	elif not _ignored.is_empty():
		var still := {}
		for ship in _ships_overlapping(global_position, Vector2.ZERO, false):
			if _ignored.has(ship.get_instance_id()):
				still[ship.get_instance_id()] = true
		_ignored = still
	var step := v.length() * delta
	if _holding:
		if not _ships_overlapping(global_position + v * delta, v, true).is_empty():
			return Vector2.ZERO
		_holding = false
		_overlap_travel = step
		return v
	var touching := _ships_overlapping(global_position, v, true)
	if touching.is_empty():
		# This step may be the one that runs into a ship: count it, so a back-off undoes it.
		_overlap_travel = step
		return v
	for ship in touching:
		if _registered(ship) or _deeper_than(YIELD_DEPTH, v, ship):
			global_position -= v.normalized() * _overlap_travel
			_overlap_travel = 0.0
			_holding = true
			return Vector2.ZERO
	_overlap_travel += step
	return v


## Ships (groups `player` / `enemies`) whose body the wreck's body overlaps at [param at]. With a non-zero [param v]
## only those ahead of it; with [param skip_ignored] not those born inside the wreck.
func _ships_overlapping(at: Vector2, v: Vector2, skip_ignored: bool) -> Array[Node2D]:
	var found: Array[Node2D] = []
	if _body_shape == null or _body_shape.shape == null:
		return found
	if _query == null:
		_query = PhysicsShapeQueryParameters2D.new()
		_query.collide_with_areas = false
		_query.collide_with_bodies = true
		_query.collision_mask = CollisionLayers.ENVIRONMENT | CollisionLayers.ENVIRONMENT_PLAYER
		_query.exclude = [get_rid()]
	_query.shape = _body_shape.shape
	var t := _body_shape.global_transform
	t.origin += at - global_position
	_query.transform = t
	for hit in get_world_2d().direct_space_state.intersect_shape(_query, 16):
		var ship := hit.get("collider") as Node2D
		if ship == null or not (ship.is_in_group(&"player") or ship.is_in_group(&"enemies")):
			continue
		if skip_ignored and _ignored.has(ship.get_instance_id()):
			continue
		if v == Vector2.ZERO or (ship.global_position - at).dot(v) > 0.0:
			found.append(ship)
	return found


## True once the ship's hurtbox has seen this wreck's armed contact box: the hit is in.
func _registered(ship: Node2D) -> bool:
	var box := Hazards.hurt_box_of(ship)
	return box != null and _contact.monitorable and box.overlaps_area(_contact)


## True when the body would still overlap [param ship] [param depth] px back along the drift.
func _deeper_than(depth: float, v: Vector2, ship: Node2D) -> bool:
	return _ships_overlapping(global_position - v.normalized() * depth, v, true).has(ship)


func _refresh_info(v: Vector2) -> void:
	_info.position = global_position if is_inside_tree() else position
	_info.kind = &"wreck"
	_info.source = self
	_info.radius = body_radius()
	_info.avoid_weight = avoid_weight
	_info.velocity = v
	_info.line_of_sight_blocker = blocks_los
