# assault/scenes/enemies/drone_interceptor/drone_interceptor.gd
class_name DroneInterceptor
extends BaseEnemy

## Kamikaze pursuit unit. Orbits the player briefly, then locks direction and commits to a
## one-way dash — exploding on contact with the player.
##
## The phase logic (ENTER/ORBIT/DASH) lives in the sibling `DroneInterceptorBrain`, driven by
## `EnemyMover`, through the shared brain/mover tick loop in `BaseEnemy._physics_process`
## (docs/plans/cmufklb100001p92xs1ey2fb1/3-plan.md §2.11 — the Phase 1 architecture's proof
## consumer). This script only copies the shipped config onto the brain and keeps the
## contact-kill behaviour, both unchanged from before the port.
##
## Spawn with b.drone_interceptor().at(x, y) — no .move() needed.

@export var config: DroneInterceptorConfig = preload(
		"res://assault/scenes/enemies/drone_interceptor/drone_interceptor_config.tres")

@onready var _drone_brain: DroneInterceptorBrain = $Brain

# ─────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	super._ready()
	add_to_group("enemies")
	if config:
		health.max_health           = config.max_health
		health.current_health       = config.max_health
		score_value                 = config.score_value
		_drone_brain.orbit_radius         = config.orbit_radius
		_drone_brain.orbit_speed          = config.orbit_speed
		_drone_brain.approach_speed       = config.approach_speed
		_drone_brain.orbit_correct_speed  = config.orbit_correct_speed
		_drone_brain.dash_speed           = config.dash_speed
		_drone_brain.dash_prediction_time = config.dash_prediction_time
		_drone_brain.dash_max_distance    = config.dash_max_distance

	if contact_hit_box:
		contact_hit_box.damage = config.collision_damage if config else 30
		contact_hit_box.area_entered.connect(_on_contact_hit)

# ─── CONTACT KILL ─────────────────────────────────────────────────────────────

func _on_contact_hit(_area: Area2D) -> void:
	## Guard against double-firing before queue_free processes.
	if health.current_health > 0:
		health.set_health(0)
