## JammingStructure - a tower that locks the player's H abilities and K rockets inside its field (docs/plans/cmug23onr001pm52w9swwophy/3-plan.md
## §2.8 / §2.9; Phase 9 t7). Behaviour: `ENEMY.md` beside this file. Three variants share this script: `jamming_structure.tscn` (local),
## `sector_jammer/sector_jammer.tscn` and `pulsed_jammer/pulsed_jammer.tscn` (scene + config only).
##
## A `BaseEnemy` with **no brain and no mover** (the Ph8 static-structure rule): `ContactProfile` NONE, no `ContactHitBox`, an `AssaultDrift`
## child in Assault, `is_laser_blocking()` false, joins `enemies` here. Its child `Field` is a `HazardField` (kind `&"jammer"`, `avoid_weight`
## 0, `disables_abilities`): the player SAMPLES it through `Hazards.jammer_at()` (the ability lock), enemies ignore it, seekers fly straight in
## it. `_ready()` writes the config's radius, stabilisation and cycle onto it.
##
## EMP: `answers_emp()` is true. `apply_emp()` runs BaseEnemy's window (the `EmpStatic` overlay, `is_emp_disrupted()`, counted in
## `BaseEnemy._physics_process` ahead of the no-brain return) and suppresses the field for the window, so an EMP switches the tower off while
## it stays in physics and shootable.
class_name JammingStructure
extends BaseEnemy

## The light blinks this fast in TELEGRAPH (CHARGING / OFF halves).
const BLINK_PERIOD := 0.2

@export var config: JammingStructureConfig = load("res://assault/scenes/enemies/jamming_structure/jamming_structure_config.tres")
## A wave spawn lands at a camera-relative point; this removes the camera's pan from x once in `_ready()` (the `TurretGroup` rule), so
## `.at(x, y)` lands at world x `640 + 2·x`. No effect without an Assault view rect.
@export var world_anchored_x: bool = true

var _blink_clock: float = 0.0

@onready var _drift: AssaultDrift = $AssaultDrift
@onready var _field: HazardField = $Field
@onready var _light: StateLight = $StateLight


func _ready() -> void:
	super._ready()
	add_to_group("enemies")
	if config:
		health.max_health = config.max_health
		health.current_health = config.max_health
		_drift.speed = config.assault_drift_speed
		_field.radius = config.field_radius
		_field.stabilise_seconds = config.stabilise_seconds
		_field.cycle_telegraph = config.cycle_telegraph
		_field.cycle_active = config.cycle_active
		_field.cycle_quiet = config.cycle_quiet
		_field.restart_cycle()
	var tree := get_tree()
	if world_anchored_x and EnemyWorld.has_view_rect(tree) and EnemyWorld.has_projectile_world_rect(tree):
		global_position.x -= EnemyWorld.view_rect(tree).get_center().x - EnemyWorld.projectile_world_rect(tree).get_center().x
	_update_light(0.0)


func _process(delta: float) -> void:
	_update_light(delta)


## The jamming field (a `HazardField`).
func field() -> HazardField:
	return _field if _field != null else get_node("Field") as HazardField


## The player's mining beam passes over the tower and burns it (a target, not a wall).
func is_laser_blocking() -> bool:
	return false


## Every EMP source reaches a jammer (it has no brain, so the BaseEnemy default would say no).
func answers_emp() -> bool:
	return true


## BaseEnemy's window (overlay, clock, longest wins) plus the field switched off for [param seconds]. Called on a refresh too:
## `HazardField.suppress()` keeps the longest window itself.
func apply_emp(seconds: float, source: Node) -> void:
	if seconds <= 0.0:
		return
	super.apply_emp(seconds, source)
	field().suppress(seconds)


## The emitter light (visual only, hand-callable): ARMED while the field is lit, blinking CHARGING in TELEGRAPH, OFF when QUIET or suppressed.
func _update_light(delta: float) -> void:
	if _light == null:
		return
	var f := field()
	var state: int = StateLight.State.OFF
	if not f.is_suppressed():
		match f.phase():
			HazardField.Phase.ACTIVE:
				state = StateLight.State.ARMED
			HazardField.Phase.TELEGRAPH:
				_blink_clock += delta
				if fposmod(_blink_clock, BLINK_PERIOD) < BLINK_PERIOD * 0.5:
					state = StateLight.State.CHARGING
	if f.phase() != HazardField.Phase.TELEGRAPH:
		_blink_clock = 0.0
	if _light.get_state() != state:
		_light.set_state(state)
