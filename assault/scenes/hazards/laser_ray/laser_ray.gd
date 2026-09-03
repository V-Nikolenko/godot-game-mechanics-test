# assault/scenes/hazards/laser_ray/laser_ray.gd
## Segmented vertical laser that kills any entity (player, enemy, asteroid) in one hit.
##
## Geometry: the emitter is at the node origin (0,0). The beam is built from
## `segment_count` identical 128×128 tiles stacked along LOCAL +Y, so it extends
## "downward" in local space. The spawner (wave manager / level) rotates and
## positions the LaserRay node to aim it — 0° points down, -90° points up,
## 45° diagonal, etc.
##
## All segments share the SpriteFrames authored on the BeamSprite template and
## are started together, so the whole beam animates as one (every tile shows the
## same frame). Segment 0 is the "master": only its animation_finished drives the
## state machine; _play_all() switches every segment in lockstep.
##
## Sequence: laser_init → laser_increase → laser_idle (active + looping) → laser_dissolve
## While idle, hitting a HurtBox plays laser_damage briefly, then returns to laser_idle.
##
## SpriteFrames are authored in laser_ray.tscn (built by the editor from the real
## texture). This script only adjusts loop flags so the state machine can advance.
class_name LaserRay
extends Node2D

## ── Exports ──────────────────────────────────────────────────────────────────

## Number of 128px tiles stacked to form the beam. Beam length = segment_count × 128.
@export_range(1, 64) var segment_count: int = 12

## Seconds the laser holds the small "warning" line (laser_init) before charging
## up, giving the player time to dodge. 0.0 = advance as soon as the init frame
## finishes (no telegraph).
@export var warn_duration: float = 0.0

## Seconds the laser stays active (idle) before auto-dissolving.
## Set to 0.0 to keep it alive until dissolve() is called manually.
@export var active_duration: float = 4.0

## If true, the laser fires automatically when added to the scene.
@export var auto_start: bool = true

## When true, the laser PULSES forever instead of dissolving once: after each active phase
## it goes dark for off_duration, then re-fires. Used by the race hazard gauntlet.
@export var loop: bool = false

## Seconds the beam stays dark between pulses when loop is true.
@export var off_duration: float = 1.8

## Overrides the default multi-layer hit mask (_HIT_MASK) when non-zero. Must be assigned
## BEFORE add_child(), because _ready() is what reads it.
##
## For emitters mounted ON an entity that would otherwise sit inside their own beam:
## SpaceStation's laser phase sets 128 (player hurtbox only) so the boss does not kill
## itself with its own beam — its core HurtBox is on layer 512, which _HIT_MASK covers.
##
## 0 means "use the default", NOT "collide with nothing": a beam that collides with
## nothing is inert, and that is not a configuration anyone wants.
@export_flags_2d_physics var hit_mask_override: int = 0

## When true, register as a race track hazard: join group "race_hazards" and expose the
## hazard contract (danger_rect / is_lethal_now / is_safe_to_cross / is_full_width) so the
## central race HazardSystem applies the (shield-bypassing) kill. The built-in HitZone is
## then left disabled to avoid the assault HurtBox/game-over damage path.
@export var race_hazard: bool = false

## ── Constants ────────────────────────────────────────────────────────────────

## Size of one tile in pixels (square sprite-sheet cell).
const _TILE: float = 128.0

## Visible beam width in pixels (the lit core inside each 128px tile).
const _BEAM_WIDTH: float = 56.0

## One-hit kill damage — exceeds any entity's max health.
const _KILL_DAMAGE: int = 9999

## Collision mask covers every known HurtBox layer:
##   128 = player_hurtbox (layer 8)
##   256 = enemy HurtBox set in code (drone_interceptor, kamikaze_drone)
##   512 = enemy_hurtbox (layer 10) used by most enemies and asteroids in .tscn
const _HIT_MASK: int = 128 | 256 | 512

## Animations that must play once and emit animation_finished (NOT loop).
const _ONESHOT_ANIMS: Array[StringName] = [
	&"laser_init", &"laser_increase", &"laser_dissolve", &"laser_damage",
]

## ── State ────────────────────────────────────────────────────────────────────

enum _Phase { INIT, INCREASE, IDLE, DISSOLVE, DONE, OFF }

@onready var _template: AnimatedSprite2D = $BeamSprite
@onready var _hit_zone: Area2D           = $HitZone
@onready var _hit_shape: CollisionShape2D = $HitZone/HitShape

var _phase:           _Phase = _Phase.INIT
## True while laser_damage flash is playing — prevents re-triggering mid-flash.
var _damage_flashing: bool   = false
## Every beam tile, top-to-bottom; index 0 is the master that drives the state machine.
var _segments:        Array[AnimatedSprite2D] = []
## Repeating timer active only during IDLE: re-damages bodies already inside
## the zone that survived the first hit (e.g. player with invincibility frames
## or shield charges). Fires every 0.1 s — fast enough that shields deplete
## quickly, slow enough to avoid spam.
var _continuous_timer: Timer = null

## ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	_build_segments()
	_build_collision()

	if race_hazard:
		add_to_group("race_hazards")

	_hit_zone.collision_mask = hit_mask_override if hit_mask_override != 0 else _HIT_MASK
	_hit_zone.monitoring  = false
	_hit_zone.monitorable = false

	_continuous_timer = Timer.new()
	_continuous_timer.wait_time = 0.1
	_continuous_timer.one_shot  = false
	_continuous_timer.timeout.connect(_on_continuous_tick)
	add_child(_continuous_timer)

	## Only the master segment drives state transitions.
	_segments[0].animation_finished.connect(_on_animation_finished)
	_hit_zone.area_entered.connect(_on_area_entered)

	if auto_start:
		start()

## Build the beam: reuse the BeamSprite template as segment 0, then clone the
## remaining tiles so they all share the same SpriteFrames and stay frame-synced.
func _build_segments() -> void:
	var frames: SpriteFrames = _template.sprite_frames
	## Force the one-shot animations to non-looping so animation_finished fires;
	## leave laser_idle as-authored (looping) so the active beam holds.
	if frames != null:
		for anim: StringName in _ONESHOT_ANIMS:
			if frames.has_animation(anim):
				frames.set_animation_loop(anim, false)

	_segments.clear()
	## Segment 0 = the template node already in the scene.
	_template.position = Vector2(0.0, _TILE * 0.5)
	_template.rotation = 0.0
	_template.scale = Vector2.ONE
	_segments.append(_template)

	## Remaining segments are clones sharing the same SpriteFrames resource.
	for i: int in range(1, segment_count):
		var seg := AnimatedSprite2D.new()
		seg.sprite_frames = frames
		seg.position = Vector2(0.0, _TILE * (float(i) + 0.5))
		add_child(seg)
		_segments.append(seg)

## Size and place the vertical hit box so it covers exactly the lit beam.
func _build_collision() -> void:
	var length: float = _TILE * float(segment_count)
	var rect := RectangleShape2D.new()
	rect.size = Vector2(_BEAM_WIDTH, length)
	_hit_shape.shape = rect
	_hit_shape.position = Vector2(0.0, length * 0.5)

## Kick off the laser sequence from the outside if auto_start is false.
func start() -> void:
	_phase = _Phase.INIT
	_play_all(&"laser_init")
	## Hold the warning line for warn_duration, then charge up. With warn_duration
	## <= 0 we advance the moment the init frame finishes (see _on_animation_finished).
	if warn_duration > 0.0:
		get_tree().create_timer(warn_duration).timeout.connect(_begin_increase)

## Force the laser into the dissolve phase early (e.g. called by a LevelDirector).
func dissolve() -> void:
	if _phase == _Phase.IDLE:
		_begin_dissolve()

## Play the same animation on every segment so the whole beam stays in sync.
func _play_all(anim: StringName) -> void:
	for seg: AnimatedSprite2D in _segments:
		seg.play(anim)

## ── Animation state machine ──────────────────────────────────────────────────

func _on_animation_finished() -> void:
	match _segments[0].animation:
		&"laser_init":
			## With a warning telegraph, a timer (started in start()) drives the
			## transition instead — hold on the init frame until it fires.
			if warn_duration <= 0.0:
				_begin_increase()

		&"laser_increase":
			_phase = _Phase.IDLE
			## laser_idle is looping — animation_finished will NOT fire again until
			## we interrupt it ourselves with laser_damage or laser_dissolve.
			_play_all(&"laser_idle")
			## Race hazards are killed centrally by HazardSystem (shield-bypassing); leave the
			## built-in HurtBox HitZone off so it doesn't also fire the assault damage path.
			_hit_zone.monitoring  = not race_hazard
			_hit_zone.monitorable = not race_hazard
			## When monitoring turns on, Godot immediately emits area_entered for any
			## HurtBox already overlapping the zone — no separate startup check needed.
			## The continuous timer handles re-hits for shielded / invincible targets.
			_continuous_timer.start()
			if active_duration > 0.0:
				get_tree().create_timer(active_duration).timeout.connect(_begin_dissolve)

		&"laser_damage":
			_damage_flashing = false
			## Return to the idle loop after the flash.
			if _phase == _Phase.IDLE:
				_play_all(&"laser_idle")

		&"laser_dissolve":
			if loop:
				## Pulse: go dark, then re-fire after off_duration (do NOT free).
				_phase = _Phase.OFF
				get_tree().create_timer(off_duration).timeout.connect(start)
			else:
				_phase = _Phase.DONE
				queue_free()

func _begin_increase() -> void:
	if _phase != _Phase.INIT:
		return
	_phase = _Phase.INCREASE
	_play_all(&"laser_increase")

func _begin_dissolve() -> void:
	if _phase != _Phase.IDLE:
		return
	_phase = _Phase.DISSOLVE
	_continuous_timer.stop()
	_hit_zone.monitoring  = false
	_hit_zone.monitorable = false
	_play_all(&"laser_dissolve")

## ── Damage ───────────────────────────────────────────────────────────────────

## Re-damages every HurtBox currently inside the zone.
## Handles the edge-case where a target entered while invincible (PlayerBase has
## 0.5 s invincibility after any hit) or has shield charges that need depleting.
func _on_continuous_tick() -> void:
	if _phase != _Phase.IDLE:
		return
	for area: Area2D in _hit_zone.get_overlapping_areas():
		if not is_instance_valid(area):
			continue
		var hb := area as HurtBox
		if hb == null:
			continue
		hb.received_damage.emit(_KILL_DAMAGE)
		_flash_damage()

func _on_area_entered(area: Area2D) -> void:
	if _phase != _Phase.IDLE:
		return
	var hb := area as HurtBox
	if hb == null:
		return
	## Bypass the HitBox type-filter: the laser is not a HitBox, it kills directly.
	hb.received_damage.emit(_KILL_DAMAGE)
	_flash_damage()

## Show the damage flash once; ignore further hits until the flash finishes.
func _flash_damage() -> void:
	if _damage_flashing:
		return
	_damage_flashing = true
	_play_all(&"laser_damage")

## ── Race hazard contract (only meaningful when race_hazard = true) ─────────────
## Consumed by HazardSystem (lethal contact) and Sensors (AI avoidance/timing).

## Lethal only while the beam is fully active (IDLE phase).
func is_lethal_now() -> bool:
	return _phase == _Phase.IDLE

## Only safe to cross while the beam is fully dark between pulses.
func is_safe_to_cross() -> bool:
	return _phase == _Phase.OFF

## True when the beam runs across the lane (≈±90° = horizontal): a full-width TIMING gate
## the AI must wait out. A vertical beam (rotation ≈0) is a lateral band, dodged via safe_x.
func is_full_width() -> bool:
	return absf(cos(rotation)) < 0.5

## World-space AABB of the lethal beam, derived from the HitZone shape (handles rotation).
func danger_rect() -> Rect2:
	var rect := _hit_shape.shape as RectangleShape2D
	if rect == null:
		return Rect2(global_position, Vector2.ZERO)
	var xform := _hit_shape.get_global_transform()
	var hs := rect.size * 0.5
	var corners := [
		xform * Vector2(-hs.x, -hs.y), xform * Vector2(hs.x, -hs.y),
		xform * Vector2(hs.x, hs.y), xform * Vector2(-hs.x, hs.y),
	]
	var mn: Vector2 = corners[0]
	var mx: Vector2 = corners[0]
	for c in corners:
		mn = mn.min(c)
		mx = mx.max(c)
	return Rect2(mn, mx - mn)
