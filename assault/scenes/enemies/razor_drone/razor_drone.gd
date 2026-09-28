# assault/scenes/enemies/razor_drone/razor_drone.gd
class_name RazorDrone
extends BaseEnemy

## Blade-like pursuit drone that evolves Phase 1's Drone Interceptor
## (docs/plans/cmufs7ek60001nm2x6d0bt2et/3-plan.md §2.8.2; task plan
## docs/plans/cmuj4y8rr007gp52xxs8dec5s/3-plan.md). It orbits the player, sometimes reverses, and
## sometimes feints a dash past them before attacking from the far side. Only a real dash shows the
## white commit flash and arms its RAMMING contact. It survives its dash, and after a miss it fires
## one pulse shot while it curves back round. In Assault it keeps to the corridor, attacks from a
## side lane and leaves after `engage_seconds`.
##
## The phase logic lives in the sibling `RazorDroneBrain`, driven through `BaseEnemy`'s shared
## brain/mover tick; this script defines no `_physics_process`. It copies the config onto every node
## that uses it (the `.tres` wins over the scene), builds the pulse pattern, and forwards a registered
## touch to the brain. A touch no longer kills the drone.
##
## Spawn with b.razor_drone().at(x, y) — no .move() needed.

@export var config: RazorDroneConfig = preload(
		"res://assault/scenes/enemies/razor_drone/razor_drone_config.tres")

@onready var _drone_brain: RazorDroneBrain = $Brain
@onready var _drone_mover: EnemyMover = $EnemyMover
@onready var _attack: AttackController = $AttackController


func _ready() -> void:
	super._ready()
	add_to_group("enemies")
	if config:
		_apply_config(config)
	contact_profile.contact_made.connect(_drone_brain.on_contact)


func _apply_config(cfg: RazorDroneConfig) -> void:
	health.max_health = cfg.max_health
	health.current_health = cfg.max_health
	score_value = cfg.score_value
	if contact_hit_box:
		contact_hit_box.damage = cfg.collision_damage

	_drone_mover.acceleration = cfg.acceleration
	_drone_mover.braking = cfg.braking
	_drone_mover.max_turn_rate = cfg.max_turn_rate

	# Built per instance: a scene sub-resource would be shared by every Razor Drone.
	var pattern := AimedAttackPattern.new()
	pattern.bullet_damage = cfg.pulse_damage
	pattern.bullet_speed = cfg.pulse_speed
	pattern.aim_at_player = true
	pattern.accuracy = 0.0
	pattern.spawn_offset = Vector2.ZERO
	_attack.pattern = pattern

	var b := _drone_brain
	b.orbit_radius = cfg.orbit_radius
	b.orbit_speed = cfg.orbit_speed
	b.approach_speed = cfg.approach_speed
	b.orbit_correct_speed = cfg.orbit_correct_speed
	b.braking = cfg.braking
	b.reverse_chance = cfg.reverse_chance
	b.reverse_seconds = cfg.reverse_seconds
	b.fake_chance = cfg.fake_chance
	b.fake_windup_scale = cfg.fake_windup_scale
	b.feint_lunge_speed = cfg.feint_lunge_speed
	b.feint_lunge_seconds = cfg.feint_lunge_seconds
	b.feint_clearance_px = cfg.feint_clearance_px
	b.windup_seconds = cfg.windup_seconds
	b.commit_flash_seconds = cfg.commit_flash_seconds
	b.dash_speed = cfg.dash_speed
	b.dash_prediction_time = cfg.dash_prediction_time
	b.overshoot_px = cfg.overshoot_px
	b.max_dash_seconds = cfg.max_dash_seconds
	b.overshoot_speed = cfg.overshoot_speed
	b.overshoot_turn_rate = cfg.overshoot_turn_rate
	b.overshoot_max_seconds = cfg.overshoot_max_seconds
	b.engage_seconds = cfg.engage_seconds
	b.exit_speed = cfg.exit_speed
	b.side_lane_min_deg = cfg.side_lane_min_deg
	b.side_lane_max_deg = cfg.side_lane_max_deg
	b.idle_radius = cfg.idle_radius
	b.idle_radius_jitter = cfg.idle_radius_jitter
	b.idle_speed = cfg.idle_speed
	b.idle_speed_jitter = cfg.idle_speed_jitter
	b.perceive_radius = cfg.perceive_radius
	b.lose_radius = cfg.lose_radius
	b.notice_time = cfg.notice_time
