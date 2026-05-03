## ThrusterEffect — continuous engine flame for the Open Space player ship.
## Follows the same CPUParticles2D-wrapper pattern as RocketTrail.
## Three visual states reflect engine power:
##   IDLE   → small dim flicker (coasting / no input)
##   THRUST → bright orange-yellow flame (normal forward/reverse thrust)
##   BOOST  → large cyan afterburner (flip-boost impulse)
##
## Usage: create in _setup_effects(), set position to engine exhaust offset,
## add_child() to the ship, then call set_state() each physics frame.
class_name ThrusterEffect
extends Node2D

enum State { IDLE, THRUST, BOOST, POWER }

var _particles: CPUParticles2D
var _current_state: int = State.IDLE

func _ready() -> void:
	_particles = CPUParticles2D.new()

	# ── Fixed properties (never change between states) ─────────────────────
	_particles.emitting = true
	_particles.one_shot = false
	_particles.explosiveness = 0.0
	# local_coords=false: particles are emitted into world space and trail
	# behind the ship as it moves, just like RocketTrail on missiles.
	_particles.local_coords = false
	# local +Y = backward when ship faces UP (Vector2.UP = local -Y).
	_particles.direction = Vector2(0.0, 1.0)
	_particles.spread = 14.0
	_particles.gravity = Vector2.ZERO
	_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINT

	add_child(_particles)
	_apply_idle()

## Call every physics frame from the ship script.
## Transitions are instant; duplicate calls for the same state are no-ops.
func set_state(state: int) -> void:
	if state == _current_state:
		return
	_current_state = state
	match state:
		State.IDLE:   _apply_idle()
		State.THRUST: _apply_thrust()
		State.BOOST:  _apply_boost()
		State.POWER:  _apply_power()

# ── Per-state configuration ────────────────────────────────────────────────

func _apply_idle() -> void:
	_particles.amount = 6
	_particles.lifetime = 0.18
	_particles.initial_velocity_min = 18.0
	_particles.initial_velocity_max = 35.0
	_particles.scale_amount_min = 1.2
	_particles.scale_amount_max = 2.2
	_set_gradient(Color(0.9, 0.45, 0.05, 0.5), Color(0.8, 0.2, 0.0, 0.0))

func _apply_thrust() -> void:
	_particles.amount = 14
	_particles.lifetime = 0.28
	_particles.initial_velocity_min = 50.0
	_particles.initial_velocity_max = 95.0
	_particles.scale_amount_min = 2.0
	_particles.scale_amount_max = 4.5
	_set_gradient(Color(1.0, 0.75, 0.1, 1.0), Color(1.0, 0.2, 0.0, 0.0))

func _apply_boost() -> void:
	_particles.amount = 24
	_particles.lifetime = 0.42
	_particles.initial_velocity_min = 100.0
	_particles.initial_velocity_max = 190.0
	_particles.scale_amount_min = 3.5
	_particles.scale_amount_max = 7.0
	_set_gradient(Color(0.35, 0.9, 1.0, 1.0), Color(0.0, 0.4, 1.0, 0.0))

## POWER: same large size as BOOST but with THRUST's yellow-orange palette.
## Used in cutscenes where the ship is still moving fast but no longer in
## the cyan afterburner phase — large warm flame, not cyan.
func _apply_power() -> void:
	_particles.amount = 24
	_particles.lifetime = 0.42
	_particles.initial_velocity_min = 100.0
	_particles.initial_velocity_max = 190.0
	_particles.scale_amount_min = 3.5
	_particles.scale_amount_max = 7.0
	_set_gradient(Color(1.0, 0.75, 0.1, 1.0), Color(1.0, 0.2, 0.0, 0.0))

func _set_gradient(birth: Color, death: Color) -> void:
	var grad := Gradient.new()
	grad.set_color(0, birth)
	grad.set_color(1, death)
	_particles.color_ramp = grad
