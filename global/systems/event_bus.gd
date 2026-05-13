# global/systems/event_bus.gd
## Centralized event bus for decoupling gameplay systems from UI.
## Subscribe here instead of querying the player via get_nodes_in_group().
## Registered as an autoload named "EventBus" in project.godot.
extends Node

# ── Player health & shield ────────────────────────────────────────────────────

## Emitted whenever the player's health value changes (including on death).
signal player_health_changed(current: int, maximum: int)

## Emitted whenever the player's shield value changes.
signal player_shield_changed(current: int, maximum: int)

## Emitted when the player's shield reaches zero.
signal player_shield_depleted

## Emitted when the player's shield recovers from zero to any positive value.
signal player_shield_restored

# ── Overheat ──────────────────────────────────────────────────────────────────

## Emitted every 0.1 s with the current heat percentage (0.0 – 100.0).
signal player_overheat_changed(percentage: float)

# ── Weapons ───────────────────────────────────────────────────────────────────

## Emitted when the player switches main weapon mode.
signal player_weapon_changed(mode: WeaponModeResource)

## Emitted when the player switches sub-weapon (rocket type).
signal player_rocket_changed(icon: Texture2D)

# ── Player lifecycle ──────────────────────────────────────────────────────────

## Emitted when the player dies (health reaches zero).
signal player_died

# ── Abilities ─────────────────────────────────────────────────────────────────

## Emitted when an ability is activated.
signal ability_activated(id: StringName, damage_mult: float, fire_rate_mult: float)

## Emitted when an ability is deactivated / deselected.
signal ability_deselected

# ── Mission events ────────────────────────────────────────────────────────────

## Emitted when a new wave starts in an assault mission.
signal mission_wave_started(wave_index: int)

## Emitted when the current mission is completed successfully.
signal mission_complete

## Emitted when the current mission is failed.
signal mission_failed
