# assault/scenes/enemies/swarm_drone/swarm_drone.gd
class_name SwarmDrone
extends BaseEnemy

## Small, cheap contact drone that replaces the Kamikaze Drone and the Open Space hub's old
## ambient drone spawn (docs/plans/cmufs7ek60001nm2x6d0bt2et/3-plan.md §2.7). Corkscrews in,
## spirals close, winds up
## (yellow light), rams the player's predicted position (red light, EXPLOSIVE contact armed), and on
## a miss curves round for one more pass. In Assault it leaves by the nearest edge after
## `engage_seconds`.
##
## The phase logic lives in the sibling `SwarmDroneBrain`, driven through `BaseEnemy`'s shared
## brain/mover tick — this script defines no `_physics_process`. It copies the config onto every
## node that uses it (the `.tres` wins over the scene) and turns a registered contact into its own
## death, which scores as a kill.
##
## Spawn with no `.move()`: a rail suspends the brain (`BaseEnemy.suspend_ai()`), which also arms
## the contact profile so a rail-driven drone still hurts on contact like the Kamikaze did.

@export var config: SwarmDroneConfig = preload(
		"res://assault/scenes/enemies/swarm_drone/swarm_drone_config.tres")

## The squad board, written by `WaveManager` / `SectorHub` before `add_child` (duck-typed through
## `in`). Null = a squad of one.
var squad: SquadController

@onready var _drone_brain: SwarmDroneBrain = $Brain
@onready var _drone_mover: EnemyMover = $EnemyMover


func _ready() -> void:
	super._ready()
	add_to_group("enemies")
	if config:
		_apply_config(config)
	contact_profile.contact_made.connect(_on_contact_made)
	if squad != null:
		var target := TargetInfo.player(get_tree())
		if target.has_target:
			squad.update_target(target.position, target.velocity.normalized())
		squad.join(self)


func _apply_config(cfg: SwarmDroneConfig) -> void:
	health.max_health = cfg.max_health
	health.current_health = cfg.max_health
	score_value = cfg.score_value
	if contact_hit_box:
		contact_hit_box.damage = cfg.collision_damage
	contact_profile.blast_radius = cfg.blast_radius
	contact_profile.blast_damage = cfg.blast_damage

	_drone_mover.max_speed = cfg.max_speed
	_drone_mover.acceleration = cfg.acceleration
	_drone_mover.braking = cfg.braking
	_drone_mover.max_turn_rate = cfg.max_turn_rate

	_drone_brain.max_speed = cfg.max_speed
	_drone_brain.braking = cfg.braking
	_drone_brain.corkscrew_amplitude = cfg.corkscrew_amplitude
	_drone_brain.corkscrew_frequency = cfg.corkscrew_frequency
	_drone_brain.windup_seconds = cfg.windup_seconds
	_drone_brain.burst_speed = cfg.burst_speed
	_drone_brain.burst_seconds = cfg.burst_seconds
	_drone_brain.lead_time_min = cfg.lead_time_min
	_drone_brain.lead_time_max = cfg.lead_time_max
	_drone_brain.overshoot_seconds = cfg.overshoot_seconds
	_drone_brain.overshoot_turn_rate = cfg.overshoot_turn_rate
	_drone_brain.second_passes = cfg.second_passes
	_drone_brain.engage_seconds = cfg.engage_seconds
	_drone_brain.exit_speed = cfg.exit_speed
	_drone_brain.rear_orbit_radius = cfg.rear_orbit_radius
	_drone_brain.rear_orbit_speed = cfg.rear_orbit_speed
	_drone_brain.flank_distance = cfg.flank_distance
	_drone_brain.flank_angle_deg = cfg.flank_angle_deg
	_drone_brain.separation_radius = cfg.separation_radius
	_drone_brain.flock_nudge_cap = cfg.flock_nudge_cap
	_drone_brain.evade_radius = cfg.evade_radius
	_drone_brain.rear_engage_seconds = cfg.rear_engage_seconds
	_drone_brain.perceive_radius = cfg.perceive_radius
	_drone_brain.lose_radius = cfg.lose_radius
	_drone_brain.notice_time = cfg.notice_time
	_drone_brain.idle_radius = cfg.idle_radius
	_drone_brain.idle_speed = cfg.idle_speed


## A registered touch (only ever while armed — EXPLOSIVE): the profile has already detonated; the
## drone dies with it, scored as a kill (Kamikaze parity). Guarded, because the hitbox can report
## once more before the deferred free lands.
func _on_contact_made(_area: Area2D) -> void:
	if health.current_health > 0:
		health.set_health(0)
