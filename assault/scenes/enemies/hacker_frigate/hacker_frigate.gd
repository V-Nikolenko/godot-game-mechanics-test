## The Hacker Frigate (docs/plans/cmug23onr001pm52w9swwophy/3-plan.md §2.10; Phase 9 t8, task plan docs/plans/cmw5k4yk400aiqs2xujalkqzf/3-plan.md):
## an electronic-warfare frigate that attacks the player's tools, not the hull (IDEAS §6.4). It hangs back at medium-long range on a lopsided
## arc, slides out of the player's nose and off their flight line, breaks off hard when rushed and stays on screen in Assault. t9 adds the
## Hijack Pulse (TELEGRAPH / PULSE are stubs until then). Behaviour: `ENEMY.md` beside this file.
##
## A `HackerFrigateBrain` decides and an `EnemyMover` moves it, through `BaseEnemy`'s shared tick, so this script defines no
## `_physics_process` and writes no motion. One `CircleShape2D` r 40 is shared by the body, the `HurtBox` and the `ContactHitBox` (COLLISION,
## 15). `Hull` is a placeholder `Polygon2D` until the art task (t12; the hit flash animates its `self_modulate`); `Dish` is the antenna part
## that unfolds in TELEGRAPH (t9), with the `StateLight` on it (IDEAS §21: a state shows on a part, never a recoloured hull).
##
## `_ready()` copies the config onto every node that uses it (the `.tres` wins over the scene) and joins group `enemies`.
##
## Spawn with b.hacker_frigate().at(x, y). Never in an ENEMIES_CLEARED section (test_engagement_deadline.gd).
class_name HackerFrigate
extends BaseEnemy

@export var config: HackerFrigateConfig = load("res://assault/scenes/enemies/hacker_frigate/hacker_frigate_config.tres")

@onready var _hacker_brain: HackerFrigateBrain = $Brain
@onready var _hacker_mover: EnemyMover = $EnemyMover
@onready var _dish: Node2D = $Dish


func _ready() -> void:
	super._ready()
	add_to_group("enemies")
	if config:
		_apply_config(config)


func _apply_config(cfg: HackerFrigateConfig) -> void:
	health.max_health = cfg.max_health
	health.current_health = cfg.max_health
	score_value = cfg.score_value
	if contact_hit_box:
		contact_hit_box.damage = cfg.collision_damage
	_hacker_mover.max_speed = cfg.max_speed
	_hacker_mover.acceleration = cfg.acceleration
	_hacker_mover.max_turn_rate = cfg.max_turn_rate
	_hacker_brain.config = cfg


func brain() -> HackerFrigateBrain:
	return _hacker_brain


## The antenna part (t9 unfolds it, t12 draws it).
func dish() -> Node2D:
	return _dish


func state_light() -> StateLight:
	return get_node_or_null("Dish/StateLight") as StateLight


## The body circle's radius (the scene's shared `CircleShape2D`).
func body_radius() -> float:
	var cs := get_node_or_null("CollisionShape2D") as CollisionShape2D
	var circle := cs.shape as CircleShape2D if cs != null else null
	return circle.radius if circle != null else 0.0
