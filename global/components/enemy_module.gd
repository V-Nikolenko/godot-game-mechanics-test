## EnemyModule — one destructible part of a large enemy: a gun battery, an engine, a hangar, a core, a weak point (Phase 10 §2.1,
## docs/plans/cmug23oo90029m52wae4clve0/3-plan.md; built in t2). One script for every heavy and boss; it never reads its host's type.
##
## SCENE SHAPE. Authored under a `Modules` `Node2D` of the enemy, never as a direct child of the enemy root (the hurtbox-geometry
## gate's one-direct-child-HurtBox rule, the station's `Turrets` / the Ram's `Plates` precedent):
##   Sprite (Sprite2D)          `intact_texture`, then `wreck_texture` (or, with none, `WRECK_TINT` on this child)
##   HurtBox (HurtBox)          one shape; layer ENEMY_HURTBOX is written here
##   Health                     written from `max_health`; created when absent; never read when `max_health` is 0
##   DefenseProfile (optional)  applied to this part's own HurtBox (`BaseEnemy` applies only the root's); without one the mask is
##                              PLAYER_HITBOX | PLAYER_ROCKETS | HAZARD_CONTACT and the types are whatever the HurtBox authors (none = all)
##   MountSlots (optional)      `TurretMountSlot`s; `ModularHull.build_mounts()` (t3) builds them and calls `attach_mount()`
##   HomingPoint (optional)     Marker2D: `homing_point()`
##   Light (optional)           the part's state light; OFF (a `StateLight`) or hidden on destruction
## Built here: `Sparks` (a `LowHealthSmoke` at `damaged_ratio`, the DAMAGED look), a hit burst and a white deflect ping.
##
## ONE DECISION POINT for projectiles. A player bullet or rocket asks `deflects_hit(hit_box)` through `ArmorQuery` (the hurtbox's
## parent is this part). `_resolve()` decides each HitBox once (cached per instance id, erased on `area_exited`, the `ArmorPlate`
## shape): deflect when the part is a wreck from an EARLIER physics frame, locked (`is_vulnerable()` false) or the hit's type is not
## accepted; consume otherwise. Destruction leaves `_vulnerable` alone, so a part killed this physics frame still answers consume:
## the killing shot is spent whichever `area_entered` (the bullet's or the hurtbox's) Godot runs first.
##
## DAMAGE ONLY THROUGH `HurtBox.received_damage`, i.e. after the hurtbox's own type filter and absorber slot, so an `EnemyShield`
## attached to this part's HurtBox absorbs first (a local shield, which an `ArmorPlate` can never have). The resolver never applies
## damage. A locked part ignores EVERY damage and pings instead: that check is the only guard against the direct emitters (the player
## beam, the nova, a level `LaserRay`), which emit `received_damage` themselves and skip both hurtbox filters, so a LASER-only part
## is still hurt by the nova. `deflected` fires once per refused hit, from whichever filter refused it: the vulnerability check (in the
## `received_damage` handler) or the hurtbox's type filter (this part's own `area_entered`, since a filtered hit never reaches
## `received_damage`). An absorbed hit fires neither (the shield flares itself).
##
## DESTROYED = WRECKAGE THAT STAYS (IDEAS §23): `Health` reaching 0, or `destroy()`, once only. The part leaves `enemy_parts`, its
## hurtbox closes (deferred: a kill lands inside a physics flush), its mounts power down, its sprite turns to the wreck, its light
## goes out, a burst goes into the HOST's parent (so it neither turns with the hull nor dies with it, the `StationTurret` re-homing),
## and `destroyed` fires. The node stays in the tree until its host is freed. It blocks nothing (Ph19).
##
## `is_armored()` answers true while locked or wrecked. Projectiles never see it (`ArmorQuery` asks `deflects_hit` first); it is what
## `EnemyShield` reads, so a shield on a locked part absorbs nothing, as on an armoured hull.
##
## Tests: tests/integration/test_enemy_module.gd (fixture tests/helpers/fixture_modular_host.tscn).
class_name EnemyModule
extends Node2D

## Each hit this part took, after its own filters; `amount` is the incoming damage (an indestructible part reports it too).
signal damaged(module: EnemyModule, amount: int)
## Once, when the part becomes a wreck.
signal destroyed(module: EnemyModule)
## Once per refused hit (locked part, or a damage type the hurtbox does not accept).
signal deflected(module: EnemyModule)
## On every change of `set_vulnerable()` (never on a wreck).
signal vulnerability_changed(module: EnemyModule, vulnerable: bool)

## Append-only.
enum Role { WEAPON, ENGINE, HANGAR, CORE, WEAK_POINT }
## Append-only.
enum VisualState { INTACT, DAMAGED, WRECK }

const GROUP := &"enemy_parts"
## On the `Sprite` child of a wreck with no `wreck_texture`. Never on this node: the player beam writes its heat tint on the part node.
const WRECK_TINT := Color(0.35, 0.35, 0.4)
## The hurtbox mask of a part with no `DefenseProfile`.
const DEFAULT_MASK := CollisionLayers.PLAYER_HITBOX | CollisionLayers.PLAYER_ROCKETS | CollisionLayers.HAZARD_CONTACT
const _SPARK_COLOR := Color(1.0, 0.8, 0.35, 0.9)

## Unique within the host (`ModularHull.module(id)`).
@export var module_id: StringName = &""
@export var role: Role = Role.WEAPON
## Written into `Health` in `_ready()`. 0 = indestructible: `Health` is never read, damage is still reported and forwarded.
@export var max_health: int = 100
@export var starts_vulnerable: bool = true
## Share of every hit `ModularHull` forwards to the host's `Health` (0 = none).
@export var hull_share: float = 0.0
@export var intact_texture: Texture2D
## Null: the intact texture stays, tinted `WRECK_TINT`.
@export var wreck_texture: Texture2D
## DAMAGED (and the sparks) at or below this fraction of `max_health`.
@export_range(0.0, 1.0, 0.01) var damaged_ratio: float = 0.5

var sprite: Sprite2D
var hurt_box: HurtBox
## The part's `Health`; null for an indestructible part that authors none.
var health: Health
## The part's own profile, or null.
var defense_profile: DefenseProfile

var _vulnerable: bool = true
var _destroyed: bool = false
var _destroyed_frame: int = -1
## HitBox instance id -> true when the part consumes that hit.
var _decisions: Dictionary = {}
var _mounts: Array[TurretMount] = []
var _sparks: LowHealthSmoke
var _hit_effect: HitEffect
var _ping: HitEffect
var _light: Node
var _homing_marker: Node2D


func _ready() -> void:
	add_to_group(GROUP)
	_vulnerable = starts_vulnerable
	sprite = get_node_or_null(^"Sprite") as Sprite2D
	if sprite != null and intact_texture != null:
		sprite.texture = intact_texture
	_homing_marker = get_node_or_null(^"HomingPoint") as Node2D
	_light = get_node_or_null(^"Light")

	health = get_node_or_null(^"Health") as Health
	if max_health > 0:
		if health == null:
			health = Health.new()
			health.name = "Health"
			add_child(health)
		health.max_health = max_health
		health.current_health = max_health
		_sparks = LowHealthSmoke.new()
		_sparks.name = "Sparks"
		_sparks.threshold = damaged_ratio
		_sparks.color = _SPARK_COLOR
		_sparks.amount = 8
		_sparks.min_velocity = 40.0
		_sparks.max_velocity = 110.0
		add_child(_sparks)
		_sparks.setup(health)

	hurt_box = get_node_or_null(^"HurtBox") as HurtBox
	if hurt_box != null:
		hurt_box.collision_layer = CollisionLayers.ENEMY_HURTBOX
		for child in get_children():
			if child is DefenseProfile:
				defense_profile = child
				break
		if defense_profile != null:
			defense_profile.apply_to(hurt_box)
		else:
			hurt_box.collision_mask = DEFAULT_MASK
		hurt_box.received_damage.connect(_on_received_damage)
		hurt_box.area_entered.connect(_on_hurt_box_area_entered)
		hurt_box.area_exited.connect(_on_hurt_box_area_exited)

	_hit_effect = HitEffect.new()
	add_child(_hit_effect)
	_ping = HitEffect.new()
	_ping.color = Color.WHITE
	_ping.amount = 6
	_ping.lifetime = 0.15
	_ping.min_velocity = 20.0
	_ping.max_velocity = 60.0
	add_child(_ping)


func is_destroyed() -> bool:
	return _destroyed


func is_vulnerable() -> bool:
	return _vulnerable


## A no-op on a wreck or when unchanged. A host changing it from inside a physics callback defers the call (the Ram `_expose` rule).
func set_vulnerable(on: bool) -> void:
	if _destroyed or on == _vulnerable:
		return
	_vulnerable = on
	vulnerability_changed.emit(self, on)


## The `ArmorQuery` hook: true when this hit must NOT consume the projectile.
func deflects_hit(hit_box: HitBox) -> bool:
	if hit_box == null:
		return true
	return not _resolve(hit_box)


## Read by `EnemyShield` (it never absorbs for an armoured host): true while locked or wrecked.
func is_armored() -> bool:
	return _destroyed or not _vulnerable


func visual_state() -> VisualState:
	if _destroyed:
		return VisualState.WRECK
	# `LowHealthSmoke`'s own comparison, so the sparks and the state never disagree at the boundary.
	if max_health > 0 and health != null and health.max_health > 0 \
			and float(health.current_health) / float(health.max_health) <= damaged_ratio:
		return VisualState.DAMAGED
	return VisualState.INTACT


## Where a homing projectile aims at this part: the `HomingPoint` marker, else the part's centre.
func homing_point() -> Vector2:
	return _homing_marker.global_position if _homing_marker != null else global_position


func mounts() -> Array[TurretMount]:
	return _mounts.duplicate()


## Ties a mount to this part: it powers down when the part is destroyed (at once on a wreck).
func attach_mount(mount: TurretMount) -> void:
	if mount == null or _mounts.has(mount):
		return
	_mounts.append(mount)
	if _destroyed:
		mount.power_down()


## Makes the part a wreck now (also a locked or an indestructible one: a scripted kill). Once only.
func destroy() -> void:
	if _destroyed:
		return
	_destroyed = true
	_destroyed_frame = Engine.get_physics_frames()
	remove_from_group(GROUP)
	if hurt_box != null:
		# Deferred: a kill lands inside a physics flush. `monitoring` is what closes the intake, `monitorable` stops projectiles seeing
		# the part, the shapes make it unambiguous (`station_turret.gd`).
		hurt_box.set_deferred(&"monitoring", false)
		hurt_box.set_deferred(&"monitorable", false)
		for child in hurt_box.get_children():
			if child is CollisionShape2D or child is CollisionPolygon2D:
				child.set_deferred(&"disabled", true)
	for mount in _mounts:
		if is_instance_valid(mount):
			mount.power_down()
	if sprite != null:
		if wreck_texture != null:
			sprite.texture = wreck_texture
		else:
			sprite.modulate = WRECK_TINT
	if _sparks != null:
		_sparks.deactivate()
	if _light is StateLight:
		(_light as StateLight).set_state(StateLight.State.OFF)
	elif _light is CanvasItem:
		(_light as CanvasItem).visible = false
	var host := _host()
	var effect := ExplosionEffect.new()
	add_child(effect)
	effect.explode(null, host.get_parent() if host != null else null)
	effect.queue_free()
	destroyed.emit(self)


func _on_received_damage(damage: int) -> void:
	if _destroyed:
		return
	if not _vulnerable:
		_deflect()
		return
	if max_health > 0 and health != null:
		health.decrease(damage)
	damaged.emit(self, damage)
	_hit_effect.burst()
	if max_health > 0 and health != null and health.current_health <= 0:
		destroy()


## A HitBox the hurtbox's own type filter drops never reaches `received_damage`: ping for it here.
func _on_hurt_box_area_entered(area: Area2D) -> void:
	var hit_box := area as HitBox
	if hit_box == null or _destroyed:
		return
	if not _accepts_type(hit_box):
		_deflect()


func _on_hurt_box_area_exited(area: Area2D) -> void:
	_decisions.erase(area.get_instance_id())


## Decides a HitBox once. True when the part consumes it.
func _resolve(hit_box: HitBox) -> bool:
	var id := hit_box.get_instance_id()
	if _decisions.has(id):
		return _decisions[id]
	for stale in _decisions.keys():
		if not is_instance_id_valid(stale):
			_decisions.erase(stale)
	var wreck_from_earlier_frame := _destroyed and _destroyed_frame < Engine.get_physics_frames()
	var consume := not wreck_from_earlier_frame and _vulnerable and _accepts_type(hit_box)
	_decisions[id] = consume
	return consume


func _accepts_type(hit_box: HitBox) -> bool:
	return hurt_box == null or hurt_box.accepted_damage_types.is_empty() \
		or hurt_box.accepted_damage_types.has(hit_box.damage_type)


func _deflect() -> void:
	deflected.emit(self)
	_ping.burst()


## The enemy this part belongs to: the parent of its `Modules` node.
func _host() -> Node:
	var holder := get_parent()
	return holder.get_parent() if holder != null else null
