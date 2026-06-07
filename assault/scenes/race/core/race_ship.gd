## RaceShip — the shared AI-racer chassis. It wires the shared components, applies the brain's
## intents to the transform (X from the mover toward desired_x; Y from RaceWorld via track_y),
## and routes damage uniformly. It contains NO decision logic — every choice lives in the
## bespoke RacerStateMachine + State children that make each racer unique.
class_name RaceShip
extends CharacterBody2D

const _BUBBLE_SHIELD_SCENE := preload("res://global/components/bubble_shield.tscn")
## VisualShader that flashes the sprite white on hit. Each racer gets its own
## ShaderMaterial.new() instance so one ship's flash doesn't affect others.
const _HIT_SHADER: Shader = preload("res://assault/assets/shader/hit_flash_vs.tres")

@onready var participant: RaceParticipant = $RaceParticipant
@onready var sensors: Sensors = $Sensors
@onready var weapon: RacerWeapon = $RacerWeapon
@onready var mover: LateralMover = $LateralMover
@onready var brain: RacerStateMachine = $Brain
@onready var health: Health = $Health
@onready var shield: Shield = $Shield
@onready var hurt_box: HurtBox = $HurtBox
## CanvasItem so both Sprite2D (other racers) and AnimatedSprite2D (Booster Gold, future)
## can be used as the visual node without changing DamageReaction's modulate-flash.
@onready var _sprite: CanvasItem = $Sprite2D
@onready var _reaction: DamageReaction = $DamageReaction

## Brain writes this each frame; the chassis glides X toward it.
var desired_x: float = 0.0

var _world: RaceWorld = null
var _hit_tween: Tween = null
## Tracks HP so we only flash when real HP decreases (shield-absorbed hits don't flash).
var _prev_hp: int = 0

func _ready() -> void:
	add_to_group("racers")
	desired_x = global_position.x
	hurt_box.collision_layer = 512
	hurt_box.collision_mask = 64 | 256 | 1024
	_reaction.setup(health, shield, hurt_box, _sprite)
	## White shader flash instead of red modulate. Each racer owns its own material
	## so toggling one ship's shader_parameter/enabled doesn't affect siblings.
	var mat := ShaderMaterial.new()
	mat.shader = _HIT_SHADER
	mat.set_shader_parameter("enabled", false)
	mat.set_shader_parameter("flash_color", Color(1, 1, 1, 1))
	_sprite.material = mat
	## Neutralise DamageReaction's red modulate — WHITE→WHITE is invisible.
	_reaction.flash_color = Color.WHITE
	## Flash only when HP actually decreases — shield absorptions must NOT trigger it.
	## (on_hit fires before consume_one(), so we can't use it to check shield state.)
	_prev_hp = health.current_health
	health.amount_changed.connect(func(new_hp: int) -> void:
		if new_hp < _prev_hp:
			_play_hit_flash()
		_prev_hp = new_hp
	)
	## on_hit: economy penalty only; visual is handled by health.amount_changed above.
	_reaction.on_hit = func(_dmg: int) -> void: participant.lose_top_speed_on_hit()
	## Bubble shield visual — mirrors PlayerBase._setup_bubble_shield().
	var bs := _BUBBLE_SHIELD_SCENE.instantiate() as BubbleShield
	add_child(bs)
	bs.setup(shield)
	_world = get_tree().get_first_node_in_group("race_world") as RaceWorld
	sensors.setup(self)
	weapon.setup(self)
	brain.setup(self)

## Flash the white hit shader for 0.2 s. Killing the previous tween first ensures
## rapid hits restart the flash cleanly rather than cutting it short.
func _play_hit_flash() -> void:
	var mat := _sprite.material as ShaderMaterial
	if mat == null:
		return
	if _hit_tween and _hit_tween.is_valid():
		_hit_tween.kill()
	mat.set_shader_parameter("enabled", true)
	_hit_tween = create_tween()
	_hit_tween.tween_interval(0.2)
	_hit_tween.tween_callback(func(): mat.set_shader_parameter("enabled", false))

func _physics_process(delta: float) -> void:
	brain.tick(delta)
	var x := mover.step(global_position.x, desired_x, delta)
	var y := _world.get_screen_y(participant) if _world else global_position.y
	global_position = Vector2(x, y)

# ── Intent helpers the bespoke States call (actions, not decisions) ───────────────────
func set_forward_floor() -> void: participant.set_cruise_factor(1.0)
func set_forward_coast(f: float = 0.6) -> void: participant.set_cruise_factor(f)

## Match a target's pace, holding `gap` track_y behind it (positive gap = behind).
func set_forward_match(target: RaceParticipant, gap: float) -> void:
	if target == null:
		participant.set_cruise_factor(0.85); return
	var want := target.track_y - gap
	var err := want - participant.track_y       ## >0 = behind desired ⇒ speed up
	participant.set_cruise_factor(clampf(0.85 + err * 0.002, 0.0, 1.0))

func steer_toward(x: float) -> void: desired_x = x
func add_avoidance(lookahead: float = 240.0) -> void:
	desired_x += mover.avoidance_nudge(self, lookahead)

func is_lined_up(target: RaceParticipant, tol: float) -> bool:
	return target != null and absf(global_position.x - target.global_x()) < tol \
		and participant.track_y < target.track_y      ## target ahead of me

func muzzle() -> Vector2:
	return global_position + Vector2(0.0, -24.0)

var _dir_cache: RaceDirector = null
func _director() -> RaceDirector:
	if _dir_cache == null:
		_dir_cache = get_tree().get_first_node_in_group("race_director") as RaceDirector
	return _dir_cache
