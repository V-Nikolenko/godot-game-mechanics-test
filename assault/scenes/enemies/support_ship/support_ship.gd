class_name SupportShip
extends BaseEnemy

## The Support Ship (docs/plans/cmufs7elw001pnm2xr3b6fteb/3-plan.md §2.11; task t10): an unarmed hull with a dish
## projector. A `SupportShipBrain` decides and an `EnemyMover` moves it, driven through `BaseEnemy`'s shared
## brain/mover tick, so this script defines no `_physics_process`.
##
## `_ready()` copies the config onto every node that uses it (the `.tres` wins over the scene). It runs AFTER its
## children's `_ready()`, so the brain builds its `EngagementBudget` on its first tick.
##
## SHELL (t10). The contact profile is NONE: the `ContactHitBox` exists so the geometry gates hold, but it is closed
## and carries `collision_damage` 0, so touching this ship hurts nobody. It never repairs another support
## (`can_be_repaired()` is false). The `Projector` is folded (`scale.y` 0, the Sniper barrel idiom) and the `Tether`
## is a world-space `Line2D`, hidden; t11-t13 unfold and draw them while it supports. It has no weapon and no pool, so
## there is no rail fallback: `on_suspended()` only drops the ward and folds the projector.
##
## Spawn with b.support_ship().at(x, y).

@export var config: SupportShipConfig = load("res://assault/scenes/enemies/support_ship/support_ship_config.tres")

@onready var _support_brain: SupportShipBrain = $Brain
@onready var _support_mover: EnemyMover = $EnemyMover
@onready var projector: Sprite2D = $Projector
@onready var tether: Line2D = $Tether


func _ready() -> void:
	super._ready()
	add_to_group("enemies")
	if config:
		_apply_config(config)
	fold_projector()


func _apply_config(cfg: SupportShipConfig) -> void:
	health.max_health = cfg.max_health
	health.current_health = cfg.max_health
	score_value = cfg.score_value
	if contact_hit_box:
		contact_hit_box.damage = cfg.collision_damage

	_support_mover.max_speed = cfg.max_speed
	_support_mover.acceleration = cfg.acceleration
	_support_mover.max_turn_rate = cfg.max_turn_rate

	_support_brain.config = cfg


## Supports never repair each other, so a support is never a ward's healer-of-a-healer (plan F12).
func can_be_repaired() -> bool:
	return false


## Folds the dish instantly and hides the tether: the folded look is `scale.y` 0.
func fold_projector() -> void:
	projector.scale.y = 0.0
	tether.visible = false
