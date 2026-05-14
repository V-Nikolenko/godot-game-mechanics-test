# open_space/scenes/entities/player/player_ship.gd
## Open-space-mission player. Extends PlayerBase for shared health/shield/overheat,
## multiplier variables, and EventBus emission.
class_name OpenSpacePlayerShip
extends PlayerBase

@export_category("Movement")
@export var rotation_speed_deg: float = 220.0
@export var thrust_acceleration: float = 380.0
@export var reverse_acceleration: float = 220.0
@export var max_speed: float = 420.0
@export var damping: float = 0.6

@export_category("Boost")
@export var boost_redirect_speed: float = 200.0
@export var boost_duration_sec: float = 0.3
@export var boost_speed_threshold: float = 180.0

## Set true by WarpModule.apply(). Not used in open space (no DashState), but
## the property must exist so WarpModule can set/clear it without error.
var warp_module_active: bool = false
## Set true by OverclockModule.apply(). Allows firing past overheat.
var overclock_module_active: bool = false

var _boost_timer: float = 0.0

## Active module instances — created lazily in _apply_module().
var _module_pool: Dictionary = {}  # { StringName: ShipModuleBase }

func _ready() -> void:
	super()  # add_to_group, _setup_components, _setup_effects
	rotation = 0.0

	## Connect module state signals for live equip/unequip during gameplay.
	ShipModuleState.module_equipped.connect(_on_module_equipped)
	ShipModuleState.module_unequipped.connect(_on_module_unequipped)
	## Apply modules already equipped from a previous session.
	for slot: StringName in ShipModuleState.SLOTS:
		var id: StringName = ShipModuleState.get_equipped(slot)
		if id != &"":
			_apply_module(id)

func _setup_effects() -> void:
	_hit_effect = HitEffect.new()
	_hit_effect.amount = 10
	_hit_effect.lifetime = 0.25
	_hit_effect.color = Color(1.0, 0.35, 0.1)
	add_child(_hit_effect)

	_explosion_effect = ExplosionEffect.new()
	_explosion_effect.amount = 30
	_explosion_effect.lifetime = 0.7
	_explosion_effect.color = Color(1.0, 0.4, 0.05)
	_explosion_effect.always_process = true
	add_child(_explosion_effect)

	_thruster = ThrusterEffect.new()
	_thruster.position = Vector2(0.0, 14.0)
	add_child(_thruster)

func _physics_process(delta: float) -> void:
	_handle_rotation(delta)
	_handle_thrust(delta)
	move_and_slide()
	## Tick all equipped modules every frame (handles cooldowns, timed effects).
	for id: StringName in _module_pool.keys():
		_module_pool[id].tick(self, delta)

func _input(event: InputEvent) -> void:
	## _input fires before _unhandled_input — modules get first pick of H-key.
	if not event.is_action_pressed("use_ability"):
		return
	for id: StringName in _module_pool.keys():
		var mod: ShipModuleBase = _module_pool[id]
		if mod.try_activate(self):
			get_viewport().set_input_as_handled()
			return  ## Consumed by module.

func _handle_rotation(delta: float) -> void:
	var turn: float = 0.0
	if Input.is_action_pressed("move_left"):
		turn -= 1.0
	if Input.is_action_pressed("move_right"):
		turn += 1.0
	rotation += deg_to_rad(rotation_speed_deg) * turn * delta

func _handle_thrust(delta: float) -> void:
	var forward: Vector2 = Vector2.UP.rotated(rotation)
	var thrust_input: float = 0.0
	if Input.is_action_pressed("move_up"):
		thrust_input += 1.0
	if Input.is_action_pressed("move_down"):
		thrust_input -= 1.0

	_boost_timer = max(_boost_timer - delta, 0.0)

	if Input.is_action_just_pressed("move_up") and _boost_timer <= 0.0:
		var backward_speed := -velocity.dot(forward)
		if backward_speed >= boost_speed_threshold:
			_trigger_flip_boost(forward)

	if thrust_input > 0.0:
		velocity += forward * thrust_acceleration * delta
		_thruster.set_state(
				ThrusterEffect.State.BOOST if _boost_timer > 0.0
				else ThrusterEffect.State.THRUST)
	elif thrust_input < 0.0:
		velocity -= forward * reverse_acceleration * delta
		_thruster.set_state(ThrusterEffect.State.THRUST)
	else:
		velocity = velocity.lerp(Vector2.ZERO, clamp(damping * delta, 0.0, 1.0))
		_thruster.set_state(
				ThrusterEffect.State.BOOST if _boost_timer > 0.0
				else ThrusterEffect.State.IDLE)

	if velocity.length() > max_speed:
		velocity = velocity.normalized() * max_speed

func _trigger_flip_boost(forward: Vector2) -> void:
	velocity = forward * boost_redirect_speed
	_boost_timer = boost_duration_sec

func _get_or_create_module(id: StringName) -> ShipModuleBase:
	if not _module_pool.has(id):
		var inst: ShipModuleBase = _create_module(id)
		if inst != null:
			_module_pool[id] = inst
	return _module_pool.get(id, null)

func _create_module(id: StringName) -> ShipModuleBase:
	match id:
		&"armor_plating":      return ArmorPlatingModule.new()
		&"parry":              return ParryModule.new()
		&"trajectory_calc":    return TrajectoryCalcModule.new()
		&"warp":               return WarpModule.new()
		&"overclock":          return OverclockModule.new()
		&"emp_blast":          return EMPBlastModule.new()
		&"shield_overload":    return ShieldOverloadModule.new()
		&"final_resort":       return FinalResortModule.new()
		&"plasma_nova":        return PlasmaNovaModule.new()
		&"overdrive":          return OverdriveModule.new()
		&"overheat_nullifier": return OverheatNullifierModule.new()
		_:
			push_warning("OpenSpacePlayerShip: unknown module id '%s'" % id)
			return null

func _apply_module(id: StringName) -> void:
	var mod := _get_or_create_module(id)
	if mod:
		mod.apply(self)

func _remove_module(id: StringName) -> void:
	var mod: ShipModuleBase = _module_pool.get(id, null) as ShipModuleBase
	if mod:
		mod.remove(self)
		_module_pool.erase(id)

func _on_module_equipped(_slot: StringName, module_id: StringName) -> void:
	if module_id != &"":
		_apply_module(module_id)

func _on_module_unequipped(_slot: StringName, prev_id: StringName) -> void:
	if prev_id != &"":
		_remove_module(prev_id)

## Scene-connected: HurtBox.received_damage → _on_received_damage.
func _on_received_damage(damage: int) -> void:
	_apply_damage(damage)
	_hit_effect.burst()

## Override: emit EventBus, handle death with delayed scene reload.
func _on_health_changed(current: int) -> void:
	super(current)  # emits EventBus.player_health_changed
	if current == 0:
		_explosion_effect.explode()
		await get_tree().create_timer(1.2).timeout
		if is_instance_valid(self):
			get_tree().reload_current_scene()

## Override: overheat gating with overclock and overdrive module support.
func _on_overheat_updated(pct: float) -> void:
	super(pct)  # emits EventBus.player_overheat_changed
	## Overclock module: never lock weapons, even at 100% heat.
	if overclock_module_active:
		can_attack = true
		return
	## Overdrive module: suppresses overheat lock while active.
	if overdrive_active:
		can_attack = true
		return
	can_attack = pct < 100.0
