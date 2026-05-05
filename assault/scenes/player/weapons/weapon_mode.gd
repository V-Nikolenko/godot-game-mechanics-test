# assault/scenes/player/weapons/weapon_mode.gd
class_name WeaponModeResource
extends Resource

enum Behavior { STRAIGHT, LONG, BEAM, SPREAD, HOMING }

@export var id: StringName = &""
@export var display_name: String = ""
@export var icon: Texture2D
@export var behavior: WeaponModeResource.Behavior = WeaponModeResource.Behavior.STRAIGHT

## Projectile scene used by STRAIGHT / LONG / SPREAD / HOMING. Ignored for BEAM.
@export var projectile_scene: PackedScene

## Per-shot range cap in pixels. 0 = no cap (off-screen exits).
@export var range_px: float = 0.0

## Seconds between shots. Ignored for BEAM (continuous while held).
@export_range(0.02, 2.0, 0.01) var fire_interval: float = 0.18

@export var damage: int = 10

## For STRAIGHT/LONG/SPREAD/HOMING: heat per shot. For BEAM: heat per second.
@export_range(0.0, 20.0, 0.1) var heat_per_shot: float = 1.0

## SPREAD only: number of pellets per shot.
@export_range(1, 12) var pellet_count: int = 1

## SPREAD only: total fan width in degrees.
@export_range(0.0, 180.0, 1.0) var pellet_spread_deg: float = 60.0

## HOMING only.
@export_range(0.0, 720.0, 5.0) var homing_turn_rate_deg_per_sec: float = 90.0
@export_range(0.1, 6.0, 0.05) var homing_lifetime_sec: float = 1.6

## BEAM only.
@export_range(0.0, 500.0, 1.0) var beam_dps: float = 30.0
