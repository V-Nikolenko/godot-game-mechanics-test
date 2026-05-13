# assault/scenes/player/player_fighter.gd
## Assault-mission player. Extends PlayerBase for shared health/shield/overheat,
## multiplier variables, and EventBus emission.
class_name AssaultPlayer
extends PlayerBase

@onready var game_over_scene: PackedScene = preload("res://assault/scenes/gui/game_over.tscn")

const _DASH_SPEED_THRESHOLD: float = 280.0
const _MOVE_SPEED_THRESHOLD: float = 10.0

## Set true by WarpModule.apply(). DashState reads this to teleport instead of roll.
var warp_module_active: bool = false
## Set true by OverclockModule.apply(). Allows firing past overheat.
var overclock_module_active: bool = false

## Active module instances — created lazily in _apply_module().
var _module_pool: Dictionary = {}  # { StringName: ShipModuleBase }

func _ready() -> void:
	super()  # add_to_group, _setup_components, _setup_effects

	var bar := OverheatBar.new()
	bar.position = Vector2(0, 22)
	add_child(bar)
	bar.setup(overheat_component)

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
	_hit_effect.min_velocity = 40.0
	_hit_effect.max_velocity = 100.0
	add_child(_hit_effect)

	_explosion_effect = ExplosionEffect.new()
	_explosion_effect.amount = 30
	_explosion_effect.lifetime = 0.7
	_explosion_effect.color = Color(1.0, 0.4, 0.05)
	_explosion_effect.min_velocity = 80.0
	_explosion_effect.max_velocity = 240.0
	_explosion_effect.min_scale = 2.0
	_explosion_effect.max_scale = 5.5
	_explosion_effect.always_process = true
	add_child(_explosion_effect)

	var low_health_smoke := LowHealthSmoke.new()
	low_health_smoke.threshold = 0.3
	add_child(low_health_smoke)
	low_health_smoke.setup(health_component)

	_thruster = ThrusterEffect.new()
	_thruster.position = Vector2(0.0, 14.0)
	add_child(_thruster)

func _physics_process(_delta: float) -> void:
	if DialogPlayer.is_active:
		velocity = Vector2.ZERO
		return
	var speed := velocity.length()
	var forward_speed  := -velocity.y
	var backward_speed :=  velocity.y
	if forward_speed >= _DASH_SPEED_THRESHOLD:
		_thruster.set_state(ThrusterEffect.State.BOOST)
	elif backward_speed >= _DASH_SPEED_THRESHOLD:
		_thruster.set_state(ThrusterEffect.State.IDLE)
	elif speed >= _MOVE_SPEED_THRESHOLD:
		_thruster.set_state(ThrusterEffect.State.THRUST)
	else:
		_thruster.set_state(ThrusterEffect.State.IDLE)
	## Tick all equipped modules every frame (handles cooldowns, timed effects).
	for id: StringName in _module_pool.keys():
		_module_pool[id].tick(self, _delta)

func _unhandled_input(event: InputEvent) -> void:
	## Route use_ability (H) to active modules first.
	## If no module consumes it, the event falls through to AbilityController.
	if event.is_action_pressed("use_ability"):
		for id: StringName in _module_pool.keys():
			var mod: ShipModuleBase = _module_pool[id]
			if mod.try_activate(self):
				get_viewport().set_input_as_handled()
				return  ## Consumed by module; AbilityController won't see it.

func _get_or_create_module(id: StringName) -> ShipModuleBase:
	if not _module_pool.has(id):
		var inst: ShipModuleBase = _create_module(id)
		if inst != null:
			_module_pool[id] = inst
	return _module_pool.get(id, null)

func _create_module(id: StringName) -> ShipModuleBase:
	match id:
		&"armor_plating":   return ArmorPlatingModule.new()
		&"parry":           return ParryModule.new()
		&"trajectory_calc": return TrajectoryCalcModule.new()
		&"warp":            return WarpModule.new()
		&"overclock":       return OverclockModule.new()
		_:
			push_warning("AssaultPlayer: unknown module id '%s'" % id)
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

## Scene-connected: HurtBox.received_damage → _on_hurt_box_received_damage.
func _on_hurt_box_received_damage(damage: int) -> void:
	_apply_damage(damage)

## Override: emit EventBus, play hit effect, handle death.
func _on_health_changed(current: int) -> void:
	super(current)  # emits EventBus.player_health_changed
	_hit_effect.burst()
	if current == 0:
		_explosion_effect.explode()
		get_tree().paused = true
		var go := game_over_scene.instantiate()
		get_tree().root.add_child(go)
		get_tree().paused = false

## Override: complex overheat gating with overdrive and 80% hysteresis.
func _on_overheat_updated(pct: float) -> void:
	super(pct)  # emits EventBus.player_overheat_changed
	## Overclock module: never lock weapons, even at 100% heat.
	if overclock_module_active:
		can_attack = true
		return
	if overdrive_active:
		can_attack = true
		return
	if pct >= 100:
		can_attack = false
		return
	if pct >= 80 and not can_attack:
		return
	if pct < 80 and not can_attack:
		can_attack = true
