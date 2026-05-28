# assault/scenes/player/weapons/behaviors/sniper_behavior.gd
class_name SniperBehavior
extends WeaponBehavior

## Press / hold / release lifecycle for the Sniper Shot weapon mode.
##
## Usage from WeaponState._physics_process():
##   if just_pressed and can_attack and cooldown <= 0:
##       sniper.start_charge(self, mode, muzzle)
##   if sniper.is_charging():
##       sniper.tick(delta)
##       if not actor.can_attack: sniper.cancel()
##   if just_released and sniper.is_charging():
##       sniper.fire_from_charge(self, mode)

## Speed is defined on the sniper_bullet.tscn scene (1400 px/s) so we don't
## override it here — the scene's exported default is used directly.
const CHARGE_TIME   : float = 0.6
const CONE_HALF_DEG : float = 25.0

var _charging   : bool                = false
var _charge_time: float               = 0.0
## All 5 initial angles (radians). Index 0 = –25°, 1 = +25°, 2–4 = inner random.
var _initial_angles: Array[float]     = []
var _muzzle     : Marker2D            = null
var _visualizer : SniperAimVisualizer = null

## fire() is unused — SNIPER is driven by start_charge / tick / fire_from_charge.
func fire(_state: Node, _mode: WeaponModeResource, _muzzle: Marker2D) -> void:
	pass

## Called on is_action_just_pressed("shoot") when conditions are met.
func start_charge(_state: Node, _mode: WeaponModeResource, muzzle: Marker2D) -> void:
	_muzzle      = muzzle
	_charge_time = 0.0
	_charging    = true

	var half_rad := deg_to_rad(CONE_HALF_DEG)
	_initial_angles = [
		-half_rad,
		 half_rad,
		randf_range(-half_rad, half_rad),
		randf_range(-half_rad, half_rad),
		randf_range(-half_rad, half_rad),
	]

	_visualizer = SniperAimVisualizer.new()
	_visualizer.initial_angles = _initial_angles
	muzzle.add_child(_visualizer)

## Returns true between start_charge and fire_from_charge / cancel.
func is_charging() -> bool:
	return _charging

## Called every physics frame while the player holds the shoot button.
func tick(delta: float) -> void:
	if not _charging:
		return
	_charge_time += delta
	var t := clampf(_charge_time / CHARGE_TIME, 0.0, 1.0)
	if is_instance_valid(_visualizer):
		_visualizer.update_charge(t)

## Called on is_action_just_released("shoot") while charging.
## Spawns the bullet, destroys the visualizer, clears charge state.
func fire_from_charge(state: Node, mode: WeaponModeResource) -> void:
	if not _charging:
		return
	var actor: Node2D = state.get("actor")
	if actor == null or mode.projectile_scene == null:
		cancel()
		return

	## Pick one of the three inner-line current angles (indices 2–4).
	var t            := clampf(_charge_time / CHARGE_TIME, 0.0, 1.0)
	var chosen_init  : float = _initial_angles[2 + randi() % 3]
	var fire_angle   : float = chosen_init * (1.0 - t)

	var bullet: Bullet = mode.projectile_scene.instantiate()
	bullet.global_position  = _muzzle.global_position + Vector2.UP.rotated(actor.rotation)
	bullet.rotation         = actor.rotation + fire_angle
	bullet.range_px         = mode.range_px
	bullet.damage           = mode.damage
	bullet.shooter_velocity = actor.velocity
	bullet.unlimited_pierce = true
	bullet.no_damage_decay  = true
	state.add_child(bullet)

	_destroy_visualizer()
	_charging = false

## Called when the charge is cancelled (weapon switch, overheat, player death).
## No bullet is fired; no cooldown is applied.
func cancel() -> void:
	_destroy_visualizer()
	_charging = false

func _destroy_visualizer() -> void:
	if is_instance_valid(_visualizer):
		_visualizer.queue_free()
	_visualizer = null
