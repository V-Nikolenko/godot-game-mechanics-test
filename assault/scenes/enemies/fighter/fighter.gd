class_name Fighter
extends BaseEnemy

## The gun-armed Tier 1 fighter (docs/plans/cmufs7ekv000lnm2x7nbswijy/3-plan.md §2.4; task
## t8a-fighter-shell). It replaces the legacy Light Assault Ship: a `FighterBrain` decides and an
## `EnemyMover` moves it, driven through `BaseEnemy`'s shared brain/mover tick, so this script
## defines no `_physics_process`.
##
## `_ready()` copies the config onto every node that uses it (the `.tres` wins over the scene) and
## builds the two attack patterns per instance from flat config fields (a scene sub-resource would be
## shared by every fighter). It runs AFTER its children's `_ready()`, so the brain builds its
## `EngagementBudget` on its first tick.
##
## Both bullet pools are direct children of this root: `BulletPool` resolves its container as
## `get_parent().get_parent()`, so a pool authored under an `AttackController` would put live bullets
## under the ship and they would move with it.
##
## Rails: while an `EnemyPathMover` owns the motion, `FighterBrain.on_suspended()` runs the legacy
## weapon (Pulse rounds). `aim_mode` is read there and nowhere else.
##
## Spawn with b.fighter().at(x, y); `.move()` is only needed until level 1 leaves its rails.

@export var config: FighterConfig = load("res://assault/scenes/enemies/fighter/fighter_config.tres")

## Rail fallback only. Overrides config.aim_mode when set via SpawnConfig.shoot_forward() /
## shoot_at_player() before the node enters the tree: "FORWARD" or "PLAYER". Empty = use the config
## default. An AI fighter ignores it.
var aim_mode: String = ""

## The squad board, written by `WaveManager` / `SectorHub` before `add_child` (duck-typed through
## `in`). Null = a squad of one. The brain reads its role every tick (epic §2.5).
var squad: SquadController

@onready var _fighter_brain: FighterBrain = $Brain
@onready var _fighter_mover: EnemyMover = $EnemyMover
@onready var _aimed_attack: AttackController = $AimedAttack
@onready var _forward_attack: AttackController = $ForwardAttack


func _ready() -> void:
	super._ready()
	add_to_group("enemies")
	if config:
		_apply_config(config)
	if squad != null:
		var target := TargetInfo.player(get_tree())
		if target.has_target:
			squad.update_target(target.position, _fighter_brain.heading_ref(target))
		squad.join(self)


func _apply_config(cfg: FighterConfig) -> void:
	health.max_health = cfg.max_health
	health.current_health = cfg.max_health
	score_value = cfg.score_value
	if contact_hit_box:
		contact_hit_box.damage = cfg.collision_damage

	_fighter_mover.max_speed = cfg.max_speed
	_fighter_mover.acceleration = cfg.acceleration
	_fighter_mover.braking = cfg.braking
	_fighter_mover.max_turn_rate = cfg.turn_rate

	var aimed := AimedAttackPattern.new()
	aimed.bullet_damage = cfg.aimed_damage
	aimed.bullet_speed = cfg.aimed_speed
	aimed.aim_at_player = true
	aimed.accuracy = cfg.aimed_accuracy
	aimed.spread_angle = cfg.aimed_spread
	aimed.rng = _fighter_brain.rng
	_aimed_attack.pattern = aimed

	var forward := AimedAttackPattern.new()
	forward.bullet_damage = cfg.forward_damage
	forward.bullet_speed = cfg.forward_speed
	forward.aim_at_player = false
	forward.spread_angle = cfg.forward_spread
	forward.rng = _fighter_brain.rng
	_forward_attack.pattern = forward

	_fighter_brain.config = cfg
	_fighter_brain.rail_aim_mode = aim_mode if not aim_mode.is_empty() else cfg.aim_mode
