extends CharacterBody2D

@onready var hurt_box: HurtBox = $HurtBox
@onready var heatlh_component: Health = $HealthComponent
@onready var overheat_component: Overheat = $OverheatComponent

var can_attack: bool = true

@onready var game_over_scene: PackedScene = preload("res://assault/scenes/gui/game_over.tscn")

# ── Particle effect components ────────────────────────────────────────────────
var _hit_effect: HitEffect
var _explosion_effect: ExplosionEffect
var _low_health_smoke: LowHealthSmoke
var _thruster: ThrusterEffect

## Speed thresholds for thruster visual state.
## Dash speed is 350 px/s; normal move speed is ~180-200 px/s.
## Only the FORWARD component (−Y, ship faces up) drives BOOST so that
## a side barrel-roll does not turn the trail blue.
const _DASH_SPEED_THRESHOLD: float = 280.0
const _MOVE_SPEED_THRESHOLD: float = 10.0

func _ready() -> void:
	add_to_group("player")
	overheat_component.overheat.connect(handle_overheat)
	heatlh_component.amount_changed.connect(_on_health_changed)

	var bar := OverheatBar.new()
	bar.position = Vector2(0, 22)
	add_child(bar)
	bar.setup(overheat_component)

	_setup_effect_components()

func _setup_effect_components() -> void:
	_hit_effect = HitEffect.new()
	_hit_effect.amount = 10
	_hit_effect.lifetime = 0.25
	_hit_effect.color = Color(1.0, 0.35, 0.1)
	_hit_effect.min_velocity = 40.0
	_hit_effect.max_velocity = 100.0
	add_child(_hit_effect)

	_explosion_effect = ExplosionEffect.new()
	_explosion_effect.amount = 30
	_explosion_effect.lifetime = 0.7
	_explosion_effect.color = Color(1.0, 0.4, 0.05)
	_explosion_effect.min_velocity = 80.0
	_explosion_effect.max_velocity = 240.0
	_explosion_effect.min_scale = 2.0
	_explosion_effect.max_scale = 5.5
	_explosion_effect.always_process = true
	add_child(_explosion_effect)

	_low_health_smoke = LowHealthSmoke.new()
	_low_health_smoke.threshold = 0.3
	add_child(_low_health_smoke)
	_low_health_smoke.setup(heatlh_component)

	# Thruster sits at the rear exhaust point. Local +Y = behind the ship
	# when the sprite faces UP; particles emit in world space so the trail
	# stays behind as the ship moves sideways during dashes.
	_thruster = ThrusterEffect.new()
	_thruster.position = Vector2(0.0, 14.0)
	add_child(_thruster)

func _physics_process(_delta: float) -> void:
	var speed := velocity.length()
	# Use only the forward (−Y) component for BOOST so a side barrel-roll
	# stays orange rather than going blue.
	var forward_speed := -velocity.y
	if forward_speed >= _DASH_SPEED_THRESHOLD:
		_thruster.set_state(ThrusterEffect.State.BOOST)
	elif speed >= _MOVE_SPEED_THRESHOLD:
		_thruster.set_state(ThrusterEffect.State.THRUST)
	else:
		_thruster.set_state(ThrusterEffect.State.IDLE)

func _on_health_changed(current: int) -> void:
	_hit_effect.burst()

	if current == 0:
		_explosion_effect.explode()
		get_tree().paused = true
		var go := game_over_scene.instantiate()
		get_tree().root.add_child(go)
		get_tree().paused = false

func _on_hurt_box_received_damage(damage: int) -> void:
	heatlh_component.decrease(damage)

func handle_overheat(overheat_percentage: float) -> void:
	if (overheat_percentage >= 100):
		can_attack = false
		return

	if (overheat_percentage >= 80 && !can_attack):
		return

	if (overheat_percentage < 80 && !can_attack):
		can_attack = true
		return
