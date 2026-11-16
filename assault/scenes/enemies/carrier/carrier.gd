class_name Carrier
extends BaseEnemy

## The Carrier (docs/plans/cmug23oo90029m52wae4clve0/3-plan.md §2.6; Phase 10 t6, task plan docs/plans/cmwafsrb700afqs2yd3qqvvrb/3-plan.md): a capital
## ship that does not chase the player, it controls space. A `CarrierBrain` decides and an `EnemyMover` moves it through `BaseEnemy`'s shared tick.
##
## THE HULL IS ARMOUR. `deflects_hit()` / `is_armored()` answer true always, so every player projectile crossing the 176 x 280 hull overlaps it without
## being consumed and reaches whichever part it meets; `_on_received_damage` refuses every hit (white flash, `armor_deflected`), so bullets, rockets,
## the beam, the nova and a level laser never lower the hull `Health`. THE PARTS are seven `EnemyModule`s under `Modules` with a `ModularHull` beside them:
## two engines aft, two gun batteries amidships, two hangars (locked: t8 opens them with the doors) and the core (locked). Every part's hurtbox lies within
## `config.module_x_extent` of the centre in x (level 1's lane maths, §2.13).
##
## THE CORE opens when `core_exposure_count` (3) outer parts (engines, guns, hangars) are wrecks: `set_vulnerable(true)` deferred (the third kill lands in a
## physics flush, so the next physics frame sees an open core), its plating art opens and the brain panics on its next tick. Until then a hit on the
## core pings and does nothing, against bullets, rockets, the beam and the nova alike (the part's own lock). THE CORE'S DEATH IS THE CARRIER'S: it sets
## the hull `Health` to 0, the normal `BaseEnemy` death, and every wreck goes with the hull.
##
## ASSAULT. A crossing, not a budget: the brain holds a constant 90 px/s straight down that an EMP does not stop (`apply_emp` re-commits it when a window
## grows); this root frees the hull once its top edge is below the projectile world rect. That check lives here, not in the brain, because the brain is
## not ticked during an EMP window: the Assault life stays fixed by spawn y and speed. A wave spawn is world-anchored in x (the `TurretGroup` rule).
##
## Nose-down art (`sprite_forward_angle` PI/2): the nose is local +y, port (the hull's left) is local +x, the stern local -y.
## Root body layer 0 / mask 0 (the station's rule, t6 D1): it ploughs through, and the player can fly onto the hull; the ARMOR contact (15 and a 220 px/s
## shove) lands on entry.
##
## Spawn with `b.carrier().at(x, y)`. Gated by `tests/integration/test_carrier.gd`.

## Every hit the armoured hull refused, with its damage.
signal armor_deflected(damage: int)
## Once, when the third outer part dies and the core opens.
signal core_exposed

@export var config: CarrierConfig = load("res://assault/scenes/enemies/carrier/carrier_config.tres")
## A wave spawn lands at a camera-relative point; this removes the camera's pan from x once in `_ready()` (the `TurretGroup` rule), so `.at(x, y)` lands at
## world x `640 + 2·x`. No effect without an Assault view rect.
@export var world_anchored_x: bool = true
## The core's opened plating, shown on the core `Sprite` from the frame after exposure (t9 draws the real one).
@export var core_open_texture: Texture2D

## A rocket arms this far beyond the hull's half-diagonal (px), so it never hits its own hull.
const ROCKET_CLEARANCE := 4.0
const CORE := &"core"
## The outer parts whose wrecks count toward the core's exposure.
const OUTER_ROLES: Array = [EnemyModule.Role.ENGINE, EnemyModule.Role.WEAPON, EnemyModule.Role.HANGAR]

var _owner_group: StringName = &""
var _core_exposed: bool = false

@onready var _carrier_brain: CarrierBrain = $Brain
@onready var _carrier_mover: EnemyMover = $EnemyMover
@onready var _hull: ModularHull = $ModularHull


func _ready() -> void:
	super._ready()
	add_to_group("enemies")
	_owner_group = StringName("carrier_%d" % get_instance_id())
	add_to_group(_owner_group)
	if config:
		_apply_config(config)
	var tree := get_tree()
	if world_anchored_x and EnemyWorld.has_view_rect(tree) and EnemyWorld.has_projectile_world_rect(tree):
		global_position.x -= EnemyWorld.view_rect(tree).get_center().x - EnemyWorld.projectile_world_rect(tree).get_center().x
	_hull.module_destroyed.connect(_on_module_destroyed)
	var core := core_module()
	if core != null:
		core.destroyed.connect(_on_core_destroyed)
	_carrier_brain.bind_hull(_hull)


## `BaseEnemy`'s tick, then the Assault free-below check (here, so an EMP window cannot skip it).
func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if is_queued_for_deletion() or not _carrier_brain.assault:
		return
	var tree := get_tree()
	if not EnemyWorld.has_projectile_world_rect(tree):
		return
	if global_position.y - body_size().y * 0.5 > EnemyWorld.projectile_world_rect(tree).end.y:
		if OS.is_stdout_verbose():
			print("[Carrier] %s left the corridor at y %.0f" % [name, global_position.y])
		queue_free()


func _apply_config(cfg: CarrierConfig) -> void:
	health.max_health = cfg.max_health
	health.current_health = cfg.max_health
	score_value = cfg.score_value
	## The scene-authored ContactHitBox never reads the config; pinned for the whole roster by test_enemy_contact_damage.gd.
	if contact_hit_box:
		contact_hit_box.damage = cfg.collision_damage
	_carrier_mover.max_speed = cfg.max_speed
	_carrier_mover.acceleration = cfg.acceleration
	_carrier_mover.braking = cfg.braking
	_carrier_mover.max_turn_rate = cfg.max_turn_rate
	_carrier_brain.config = cfg


## A second EMP inside a running window only extends it (`BaseEnemy.apply_emp` tells the brain about a window's start alone): the brain re-commits its
## crossing for the longer window, or the boost would run out and stop the hull (acceleration 0 in Assault) for the rest of it.
func apply_emp(seconds: float, source: Node) -> void:
	var before := emp_seconds_left()
	super.apply_emp(seconds, source)
	if before > 0.0 and emp_seconds_left() > before:
		_carrier_brain.on_emp_refreshed()


## The parts' coordinator.
func modular_hull() -> ModularHull:
	return _hull if _hull != null else get_node("ModularHull") as ModularHull


## The CORE part.
func core_module() -> EnemyModule:
	return modular_hull().module(CORE)


## True from the moment the third outer part died (the core's lock lifts one physics frame later).
func is_core_exposed() -> bool:
	return _core_exposed


## The group every carrier weapon exempts (this hull and, from t8, its launched children).
func owner_group() -> StringName:
	return _owner_group


## The body rectangle's size (px).
func body_size() -> Vector2:
	var shape := ($CollisionShape2D as CollisionShape2D).shape as RectangleShape2D
	return shape.size if shape != null else Vector2.ZERO


## The hull is armour: no player projectile is ever consumed by it (it flies on to the parts).
func deflects_hit(_hit_box: HitBox) -> bool:
	return true


func is_armored() -> bool:
	return true


## The player's mining beam passes over the hull and burns the parts it crosses.
func is_laser_blocking() -> bool:
	return false


func can_be_repaired() -> bool:
	return false


## Duck-typed, read by `SupportShipBrain.is_candidate()` (owner choice 7): a shield on an armoured hull would never absorb.
func accepts_ward() -> bool:
	return false


## Duck-typed launcher question (a rocket mount, t7): the hull's own velocity.
func launch_velocity() -> Vector2:
	return velocity


## Duck-typed launcher question: the hull's half-diagonal + 4, so a rocket arms only once clear of the whole rectangle.
func rocket_clear_radius() -> float:
	return body_size().length() * 0.5 + ROCKET_CLEARANCE


## Where a player homing rocket coming from [param from] steers: the nearest live vulnerable part's `homing_point()` (its centre), else the hull centre.
func homing_point(from: Vector2) -> Vector2:
	var best := global_position
	var best_d := INF
	for part in modular_hull().modules():
		if part.is_destroyed() or not part.is_vulnerable():
			continue
		var p := part.homing_point()
		var d := from.distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = p
	return best


## Armour: every hit is refused with a flash; the hull `Health` moves only when the core dies.
func _on_received_damage(damage: int) -> void:
	armor_deflected.emit(damage)
	hit_flash_player.play("hit")


func _on_module_destroyed(_part: EnemyModule) -> void:
	if _core_exposed or config == null:
		return
	if _hull.destroyed_count(OUTER_ROLES) < config.core_exposure_count:
		return
	_core_exposed = true
	var core := core_module()
	if core != null:
		core.call_deferred(&"set_vulnerable", true)
	_open_core_plating.call_deferred()
	core_exposed.emit()


func _open_core_plating() -> void:
	var core := core_module()
	if core == null or core.is_destroyed() or core.sprite == null or core_open_texture == null:
		return
	core.sprite.texture = core_open_texture


func _on_core_destroyed(_part: EnemyModule) -> void:
	if health.current_health > 0:
		health.set_health(0)
