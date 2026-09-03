## ScoreConfig — tunable scoring constants for an assault mission.
##
## A default `.tres` lives at res://global/resources/score_config_default.tres.
## ScoreTracker exports a reference; designers can override per-level.
class_name ScoreConfig
extends Resource

## How much combo grows per kill.
@export_range(0.0, 1.0, 0.01) var combo_step: float = 0.1
## Maximum combo multiplier reachable through kills.
@export_range(1.0, 16.0, 0.1) var combo_cap: float = 8.0
## Seconds of inactivity before combo resets to x1.
@export_range(0.5, 10.0, 0.1) var combo_decay_seconds: float = 4.0

## Combo is multiplied by this when the player takes damage.
@export_range(0.0, 1.0, 0.05) var damage_combo_multiplier: float = 0.5
## Combo is multiplied by this when an enemy escapes off-screen alive.
@export_range(0.0, 1.0, 0.05) var escape_combo_multiplier: float = 0.75

## Seconds of damage-free play between passive survival bonuses.
@export_range(1.0, 60.0, 0.5) var survival_interval: float = 15.0
## Flat points awarded per survival interval.
@export var survival_bonus: int = 50

## Wave-clear bonus formula: sum(base_values) * (base_mult + per_enemy * count).
@export var wave_clear_base_multiplier: float = 1.0
@export var wave_clear_per_enemy_bonus: float = 0.5
