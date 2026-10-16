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
## t12: the brain drives the dish and the tether through `set_projector_open()` / `show_tether()` / `hide_tether()`; the
## tether is cyan while it projects, pale green for a moment after a repair pulse and dim when a rock blocks the line.
##
## Spawn with b.support_ship().at(x, y).

## The tether while projecting, flashing after a repair pulse, and the alpha it is drawn at when the line is blocked.
const TETHER_COLOR := Color(0.4, 0.9, 1.0, 0.8)
const TETHER_REPAIR_COLOR := Color(0.65, 1.0, 0.65, 1.0)
const TETHER_DIM_ALPHA := 0.25

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


## Sets the dish's unfold, 0 (folded) to 1 (open), eased out like the Sniper's barrel. A visual pose, not motion.
func set_projector_open(share: float) -> void:
	var s := clampf(share, 0.0, 1.0)
	projector.scale.y = 1.0 - (1.0 - s) * (1.0 - s)


## Draws the world-space tether from the projector to `to`.
func show_tether(to: Vector2, color: Color) -> void:
	tether.points = PackedVector2Array([projector.global_position, to])
	tether.default_color = color
	tether.visible = true


func hide_tether() -> void:
	tether.visible = false
