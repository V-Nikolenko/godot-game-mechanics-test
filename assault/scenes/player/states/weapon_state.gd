# assault/scenes/player/states/weapon_state.gd
class_name WeaponState
extends State

signal weapon_changed(mode: WeaponModeResource)

@export_category("State Dependencies")
@export var actor: CharacterBody2D
@export var weapon_muzzles: Array[Marker2D]
@export var movement_controller: MovementController

@export_category("Heat Component")
@export var heat_component: Overheat

const _MODES_DIR := "res://assault/scenes/player/weapons/modes/"

var _modes: Dictionary = {}  # { StringName: WeaponModeResource }
var _active_id: StringName = &"default"
var _cooldown: float = 0.0
var _gun_index: int = 0
var _behaviors: Dictionary = {}  # { int: WeaponBehavior }

func _ready() -> void:
	_load_modes()
	_build_behaviors()
	movement_controller.action_single_press.connect(_on_action)
	if not UpgradeState.is_unlocked(_active_id):
		_active_id = _first_unlocked_id()
	_emit_changed()

func _load_modes() -> void:
	for id: StringName in UpgradeState.ALL_IDS:
		var path := _MODES_DIR + String(id) + ".tres"
		if not ResourceLoader.exists(path):
			continue
		var res := load(path) as WeaponModeResource
		if res:
			_modes[id] = res

func _build_behaviors() -> void:
	_behaviors[WeaponModeResource.Behavior.STRAIGHT] = StraightBehavior.new()
	_behaviors[WeaponModeResource.Behavior.LONG]     = LongRangeBehavior.new()
	_behaviors[WeaponModeResource.Behavior.SPREAD]   = SpreadBehavior.new()
	_behaviors[WeaponModeResource.Behavior.BEAM]     = BeamBehavior.new()

func _first_unlocked_id() -> StringName:
	var unlocked := UpgradeState.unlocked_ids()
	return unlocked[0] if not unlocked.is_empty() else &"default"

func _on_action(key_name: String) -> void:
	if key_name == "cycle_weapon":
		_cycle()
	elif key_name == "shoot":
		_try_fire_once()

func _try_fire_once() -> void:
	if not actor.can_attack:
		return
	var mode: WeaponModeResource = _modes.get(_active_id)
	if mode == null:
		return
	if mode.behavior == WeaponModeResource.Behavior.BEAM:
		return
	if _cooldown > 0.0:
		return
	_fire(mode)
	## Shorter cooldown with fire_rate_multiplier > 1.0 (e.g. Overdrive sets 2.0).
	var _frm = actor.get("fire_rate_multiplier")
	var multiplier: float = _frm if _frm != null else 1.0
	_cooldown = mode.fire_interval / maxf(multiplier, 0.01)

func _fire(mode: WeaponModeResource) -> void:
	if weapon_muzzles.is_empty():
		return
	_gun_index = (_gun_index + 1) % weapon_muzzles.size()
	var muzzle: Marker2D = weapon_muzzles[_gun_index]
	var beh: WeaponBehavior = _behaviors.get(mode.behavior)
	if beh == null:
		return
	beh.fire(self, mode, muzzle)
	heat_component.increase_heat(mode.heat_per_shot)

func _physics_process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown = max(0.0, _cooldown - delta)

	var mode: WeaponModeResource = _modes.get(_active_id)
	if mode == null:
		return

	if mode.behavior == WeaponModeResource.Behavior.BEAM:
		var beam: BeamBehavior = _behaviors[WeaponModeResource.Behavior.BEAM]
		if Input.is_action_pressed("shoot") and actor.can_attack:
			if weapon_muzzles.is_empty():
				return
			beam.tick(self, mode, weapon_muzzles[0], delta)
			heat_component.increase_heat(mode.heat_per_shot * delta)
		else:
			beam.release(self)

func _cycle() -> void:
	var unlocked := UpgradeState.unlocked_ids()
	if unlocked.is_empty():
		return
	var i := unlocked.find(_active_id)
	var next_i := 0 if i < 0 else (i + 1) % unlocked.size()
	var prev_id := _active_id
	_active_id = unlocked[next_i]
	if prev_id != _active_id:
		var beam: BeamBehavior = _behaviors[WeaponModeResource.Behavior.BEAM]
		beam.release(self)
		_cooldown = 0.0
		_emit_changed()

## Public: call this to (re-)emit the current mode — used by HUD chips connecting late.
func emit_current_mode() -> void:
	_emit_changed()

## Public: return the currently active weapon ID.
func get_active_id() -> StringName:
	return _active_id

## Public: switch to a specific weapon by ID. No-op if ID is not unlocked.
## Mirrors _cycle() behaviour: releases beam, resets cooldown, emits changed signal.
func select_weapon(id: StringName) -> void:
	if not UpgradeState.is_unlocked(id):
		return
	if id == _active_id:
		return
	_active_id = id
	var beam: BeamBehavior = _behaviors[WeaponModeResource.Behavior.BEAM]
	beam.release(self)
	_cooldown = 0.0
	_emit_changed()

func _emit_changed() -> void:
	var mode: WeaponModeResource = _modes.get(_active_id)
	if mode:
		weapon_changed.emit(mode)
