# global/entities/player_base.gd
## Base class for all player implementations.
## Provides shared component references, multiplier variables,
## damage-reduction helper, and EventBus signal emission.
## Subclasses call super() in _ready(), then add mission-specific setup.
class_name PlayerBase
extends CharacterBody2D

## The boost's efficiency changed: a disruption started, got stronger, or ended (1.0).
signal boost_disruption_changed(efficiency: float)

## An EMP started (true) or ended (false) on this ship.
signal emp_changed(active: bool)

## Below this efficiency every boost verb (Shift boost, Boost Drive, dash, warp) is refused before anything is spent.
const MIN_BOOST_EFFICIENCY: float = 0.15

## Component references — assigned in _setup_components().
var health_component: Health = null
var shield_component: Shield = null
var overheat_component: Overheat = null

## Effect emitters — instantiated in _setup_effects() by subclass.
var _hit_effect: HitEffect = null
var _explosion_effect: ExplosionEffect = null
var _thruster: ThrusterEffect = null        ## Left engine (also used by EngineBoostModule).
var _thruster_right: ThrusterEffect = null  ## Right engine.
var temp_health_component: TempHealth = null

## Invincibility after any hit — prevents burst-kill from simultaneous projectiles.
## Covers shield absorbs, temp-HP drains, and health damage equally.
@export var invincibility_sec: float = 0.5
var _is_invincible: bool = false
var _invincibility_timer: Timer = null

## Temporary damage boost (applied by temporary_damage_up pickup).
var _temp_damage_bonus: float = 0.0
var _base_damage_multiplier: float = 1.0
var _temp_damage_timer: Timer = null

## Multipliers written by ship modules (FinalResortModule, OverclockModule, etc.).
## WeaponState reads these when computing damage and cooldowns.
var damage_multiplier: float = 1.0
var fire_rate_multiplier: float = 1.0
## 0.0 = no reduction; 0.5 = take 50% damage. Written by ArmorPlatingAbility.
var damage_reduction: float = 0.0
## When true, overheat can exceed heat_limit without locking weapons.
var overdrive_active: bool = false
var can_attack: bool = true
## Set by PierceModule. Behaviors read this to enable bullet pierce.
var pierce_module_active: bool = false
## Set by EngineBoostModule while the boost is active.
## player_ship._handle_thrust() skips damping/cap when this is true.
var engine_boost_active: bool = false

## Knockback impulse (px/s) applied e.g. when ramming a dash-panel wall. Decays to
## zero over a fraction of a second. While active it OVERRIDES input-driven movement
## (move_state yields to it) so the player is actually shoved off the wall instead of
## the held movement key instantly cancelling the push. Driven via move_and_slide so
## it still respects solid walls. World bounds clamped in apply_knockback_motion().
var _knockback: Vector2 = Vector2.ZERO
const _KNOCKBACK_DECAY: float = 1200.0  ## px/s² — how fast the impulse bleeds off

## Boost disruption (Phase 7 plan §2.6): the live strength (0 when none) and the seconds left, accumulated delta.
var _disruption_strength: float = 0.0
var _disruption_left: float = 0.0
## EMP (Phase 7 plan §2.8): the seconds left of the longest EMP, accumulated delta.
var _emp_left: float = 0.0
## Drives the ring's flicker only.
var _disruption_clock: float = 0.0
## The violet spark ring shown for the duration. Code-built on the first disruption, no PNG.
var _disruption_ring: Line2D = null
const _DISRUPTION_RING_COLOR: Color = Color(0.72, 0.4, 1.0, 1.0)
const _DISRUPTION_RING_POINTS: int = 24
const _DISRUPTION_RING_RADII: Vector2 = Vector2(20.0, 23.0)  ## alternating inner / outer: a jagged spark ring

func _ready() -> void:
	add_to_group("player")
	_setup_components()
	_setup_effects()

## Assigns component references and connects Health / Shield / Overheat signals.
## Subclass may call super() then add extra setup afterward.
func _setup_components() -> void:
	health_component = $HealthComponent
	shield_component = $ShieldComponent
	overheat_component = $OverheatComponent

	if health_component:
		health_component.amount_changed.connect(_on_health_changed)
	if overheat_component:
		overheat_component.overheat.connect(_on_overheat_updated)
	temp_health_component = get_node_or_null("TempHealthComponent") as TempHealth
	_invincibility_timer = Timer.new()
	_invincibility_timer.one_shot = true
	_invincibility_timer.timeout.connect(_on_invincibility_expired)
	add_child(_invincibility_timer)
	_temp_damage_timer = Timer.new()
	_temp_damage_timer.one_shot = true
	_temp_damage_timer.timeout.connect(_on_temp_damage_expired)
	add_child(_temp_damage_timer)
	## Restore temporary buffs saved before the last level transition or quit.
	SessionState.apply_to(self)
	_setup_bubble_shield()

## Instantiates the bubble-shield visual and wires it to the shield component.
## Looks for SpriteAnchor so it works in both assault and open-space scenes.
func _setup_bubble_shield() -> void:
	if shield_component == null:
		return
	var anchor := get_node_or_null("SpriteAnchor") as Node2D
	if anchor == null:
		return
	var shield_visual: BubbleShield = (
		preload("res://global/components/bubble_shield.tscn").instantiate() as BubbleShield
	)
	anchor.add_child(shield_visual)
	shield_visual.setup(shield_component)

## Override in subclass to instantiate and configure particle effect nodes.
func _setup_effects() -> void:
	pass

## damage_reduction intentionally applies ONLY when health takes the hit.
## Shields are binary (1 hit = 1 charge, regardless of damage), so reducing
## "damage" against a shield has no meaningful effect in the new model.
func _apply_damage(damage: int) -> void:
	if _is_invincible:
		return
	var effective: int = roundi(damage * (1.0 - damage_reduction))
	if shield_component and shield_component.consume_one():
		_start_invincibility()
		return                            ## one charge absorbed
	if temp_health_component and temp_health_component.current_temp > 0:
		effective = temp_health_component.take_damage(effective)
		if effective <= 0:
			_start_invincibility()
			return                        ## fully absorbed by temp HP
	if health_component:
		health_component.decrease(effective)
	_start_invincibility()


func _start_invincibility() -> void:
	_is_invincible = true
	_invincibility_timer.start(invincibility_sec)


func _on_invincibility_expired() -> void:
	_is_invincible = false

## Begin a knockback shove. impulse is an instantaneous velocity (px/s); it decays
## to zero over the next few frames. Overrides input movement while it lasts.
func apply_knockback(impulse: Vector2) -> void:
	_knockback = impulse

## True while a knockback is still being applied. move_state checks this and yields
## so input cannot cancel the shove mid-flight.
func is_knockback_active() -> bool:
	return _knockback.length_squared() > 1.0

## Advance one physics step of knockback motion through move_and_slide (so it respects
## walls), then bleed the impulse toward zero. Call once per physics frame while active.
func apply_knockback_motion(delta: float) -> void:
	velocity = _knockback
	move_and_slide()
	## Same world bounds move_state enforces, so a shove can't fling the ship off-screen.
	global_position.x = clampf(global_position.x, -100.0, 1380.0)
	global_position.y = clampf(global_position.y, -380.0, 1100.0)
	_knockback = _knockback.move_toward(Vector2.ZERO, _KNOCKBACK_DECAY * delta)

## 1 minus the strongest slow at this ship's position (Hazards.penalty_at, capped at Hazards.MAX_PENALTY).
## 1.0 when no hazard exists. Read, never cached: thrust, speed ceilings and dash / move speed multiply by
## it where they are read, so the exported values themselves are never written.
func hazard_speed_factor() -> float:
	if Hazards.count() == 0:
		return 1.0
	return 1.0 - Hazards.penalty_at(global_position)

## Weakens every boost verb for `seconds`. `strength` is 0..1. The strongest strength and the longest time win; two
## disruptions never stack. Emits boost_disruption_changed when the efficiency changes (a start or a stronger one).
func apply_boost_disruption(strength: float, seconds: float) -> void:
	strength = clampf(strength, 0.0, 1.0)
	if strength <= 0.0 or seconds <= 0.0:
		return
	var before: float = boost_efficiency()
	_disruption_strength = maxf(_disruption_strength, strength)
	_disruption_left = maxf(_disruption_left, seconds)
	_show_disruption_ring(true)
	if boost_efficiency() != before:
		boost_disruption_changed.emit(boost_efficiency())

## 1 - the live strength while disrupted, else 1.0. Read where it is used, never cached.
func boost_efficiency() -> float:
	if _disruption_left <= 0.0:
		return 1.0
	return 1.0 - _disruption_strength

## The speed of normal flight, which a disrupted boost speed never drops below. Overridden by each ship.
func cruise_speed() -> float:
	return 0.0

## The excess rule: only the part of `speed` above `floor_speed` shrinks with the efficiency. Returns `speed` itself
## when undisrupted, so an undisrupted boost is bit-identical to one without the hook.
func disrupted_speed(speed: float, floor_speed: float) -> float:
	var eff: float = boost_efficiency()
	if eff >= 1.0:
		return speed
	return floor_speed + (speed - floor_speed) * eff

## An EMP hit (`EmpPulse.emit()`): the longest time wins and `emp_changed(true)` fires on the start. Phase 7's
## stand-in effect is a full boost disruption (efficiency 0), so the Shift boost, the Boost Drive, the dash and the
## warp are all refused for the window. PHASE 9 REPLACES THE EFFECT (the stand-in line below), not this signature,
## `is_emp_disrupted()` or `emp_changed`.
func apply_emp(seconds: float, _source: Node) -> void:
	if seconds <= 0.0:
		return
	var was_active: bool = is_emp_disrupted()
	_emp_left = maxf(_emp_left, seconds)
	apply_boost_disruption(1.0, seconds)  # Phase 7 stand-in, Phase 9's to replace.
	if not was_active:
		emp_changed.emit(true)

func is_emp_disrupted() -> bool:
	return _emp_left > 0.0

## The disruption's clock, a hand-steppable seam like BoostMeter.step(). Called from each ship's _physics_process.
func _step_disruption(delta: float) -> void:
	_step_emp(delta)
	if _disruption_left <= 0.0:
		return
	_disruption_left -= delta
	if _disruption_left <= 0.0:
		_disruption_left = 0.0
		_disruption_strength = 0.0
		_show_disruption_ring(false)
		boost_disruption_changed.emit(1.0)
		return
	_disruption_clock += delta
	if _disruption_ring != null:
		_disruption_ring.rotation = _disruption_clock * 2.5
		_disruption_ring.modulate.a = 0.55 + 0.45 * absf(sin(_disruption_clock * 21.0))

func _step_emp(delta: float) -> void:
	if _emp_left <= 0.0:
		return
	_emp_left -= delta
	if _emp_left <= 0.0:
		_emp_left = 0.0
		emp_changed.emit(false)

func _show_disruption_ring(on: bool) -> void:
	if _disruption_ring == null:
		if not on:
			return
		_disruption_ring = Line2D.new()
		_disruption_ring.name = "BoostDisruptionRing"
		_disruption_ring.closed = true
		_disruption_ring.width = 1.5
		_disruption_ring.default_color = _DISRUPTION_RING_COLOR
		for i in range(_DISRUPTION_RING_POINTS):
			var r: float = _DISRUPTION_RING_RADII.x if i % 2 == 0 else _DISRUPTION_RING_RADII.y
			_disruption_ring.add_point(Vector2.RIGHT.rotated(TAU * i / _DISRUPTION_RING_POINTS) * r)
		add_child(_disruption_ring)
	_disruption_ring.visible = on
	_disruption_clock = 0.0
	_disruption_ring.modulate = Color.WHITE

## Called when health changes. Override in subclass (call super() first)
## to preserve EventBus emission and add mission-specific death handling.
func _on_health_changed(current: int) -> void:
	EventBus.player_health_changed.emit(current, health_component.max_health)

## Called every 0.1 s with current overheat percentage (0–100).
## Override in subclass (call super() first) to preserve EventBus emission
## and add mission-specific can_attack gating.
func _on_overheat_updated(pct: float) -> void:
	EventBus.player_overheat_changed.emit(pct)


## Called by temporary_damage_up pickup.
## bonus is the fractional increase (0.5 = +50%). duration is seconds.
## Restores to the exact baseline on expiry — avoids float drift from repeated re-application.
func apply_temp_damage_buff(bonus: float, duration: float) -> void:
	if _temp_damage_timer and not _temp_damage_timer.is_stopped():
		## Re-application while active: restore cleanly before re-buffing.
		damage_multiplier = _base_damage_multiplier
	else:
		## No buff active: snapshot the current baseline.
		_base_damage_multiplier = damage_multiplier
	_temp_damage_bonus = bonus
	damage_multiplier = _base_damage_multiplier + bonus
	_temp_damage_timer.start(duration)
	## Persist so the buff survives level transitions and game restarts.
	var expiry: float = Time.get_unix_time_from_system() + duration
	SessionState.save_temp_damage_buff(bonus, expiry)


func _on_temp_damage_expired() -> void:
	damage_multiplier = _base_damage_multiplier
	_temp_damage_bonus = 0.0
	SessionState.clear_temp_damage_buff()
