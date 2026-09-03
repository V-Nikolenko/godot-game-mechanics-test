## GunshipConfig — tuning for the reworked Gunship.
## Gunship manages its own ENTER/HOLD/RETREAT movement via AI.
class_name GunshipConfig
extends ShipConfig

## Seconds between burst pairs.
@export var burst_interval: float = 1.0
## Delay between left and right shot within a burst (seconds).
@export var burst_gap: float = 0.12
## Damage per bullet.
@export var bullet_damage: int = 15
## Bullet travel speed in px/s.
@export var bullet_speed: float = 260.0
## Entry and retreat speed in px/s.
@export var entry_speed: float = 60.0
## Pixels below viewport top edge where the ship holds position.
@export var hold_y_offset: float = 55.0
## Maximum horizontal tracking speed in px/s.
@export var track_speed: float = 70.0
## Enable/disable horizontal player tracking during HOLD.
@export var track_player: bool = true
## HP fraction (0–1) at which the ship transitions to RETREAT.
@export var retreat_hp_ratio: float = 0.3
