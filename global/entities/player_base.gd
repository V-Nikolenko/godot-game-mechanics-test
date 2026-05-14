# global/entities/player_base.gd
## Base class for all player implementations.
## Provides shared component references, multiplier variables,
## damage-reduction helper, and EventBus signal emission.
## Subclasses call super() in _ready(), then add mission-specific setup.
class_name PlayerBase
extends CharacterBody2D

## Component references — assigned in _setup_components().
var health_component: Health = null
var shield_component: Shield = null
var overheat_component: Overheat = null

## Effect emitters — instantiated in _setup_effects() by subclass.
var _hit_effect: HitEffect = null
var _explosion_effect: ExplosionEffect = null
var _thruster: ThrusterEffect = null

## Multipliers written by ship modules (OverdriveModule, FinalResortModule, etc.).
## WeaponState reads these when computing damage and cooldowns.
var damage_multiplier: float = 1.0
var fire_rate_multiplier: float = 1.0
## 0.0 = no reduction; 0.5 = take 50% damage. Written by ArmorPlatingAbility.
var damage_reduction: float = 0.0
## When true, overheat can exceed heat_limit without locking weapons.
var overdrive_active: bool = false
var can_attack: bool = true

func _ready() -> void:
	add_to_group("player")
	_setup_components()
	_setup_effects()

## Assigns component references and connects Health / Shield / Overheat signals.
## Subclass may call super() then add extra setup afterward.
func _setup_components() -> void:
	health_component = $HealthComponent
	shield_component = $ShieldComponent
	overheat_component = $OverheatComponent

	if health_component:
		health_component.amount_changed.connect(_on_health_changed)
	if shield_component:
		shield_component.shield_changed.connect(_on_shield_changed)
		shield_component.shield_depleted.connect(_on_shield_depleted)
	if overheat_component:
		overheat_component.overheat.connect(_on_overheat_updated)

## Override in subclass to instantiate and configure particle effect nodes.
func _setup_effects() -> void:
	pass

## Shared damage handler. Call this from your scene-connected hurt-box method.
## Applies damage_reduction, routes damage through shield, then health.
func _apply_damage(damage: int) -> void:
	var effective: int = roundi(damage * (1.0 - damage_reduction))
	var overflow := shield_component.absorb(effective)
	if overflow > 0:
		health_component.decrease(overflow)

## Called when health changes. Override in subclass (call super() first)
## to preserve EventBus emission and add mission-specific death handling.
func _on_health_changed(current: int) -> void:
	EventBus.player_health_changed.emit(current, health_component.max_health)

## Called when shield absorbs or restores. Emits EventBus signal.
func _on_shield_changed(current: int, maximum: int) -> void:
	EventBus.player_shield_changed.emit(current, maximum)

## Called when shield reaches zero. Emits EventBus signal.
func _on_shield_depleted() -> void:
	EventBus.player_shield_depleted.emit()

## Called every 0.1 s with current overheat percentage (0–100).
## Override in subclass (call super() first) to preserve EventBus emission
## and add mission-specific can_attack gating.
func _on_overheat_updated(pct: float) -> void:
	EventBus.player_overheat_changed.emit(pct)
