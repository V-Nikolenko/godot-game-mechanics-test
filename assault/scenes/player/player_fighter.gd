# assault/scenes/player/player_fighter.gd
## Assault-mission player. Extends PlayerBase for shared health/shield/overheat,
## multiplier variables, and EventBus emission.
class_name AssaultPlayer
extends PlayerBase

@onready var game_over_scene: PackedScene = preload("res://assault/scenes/gui/game_over.tscn")

const _DASH_SPEED_THRESHOLD: float = 280.0
const _MOVE_SPEED_THRESHOLD: float = 10.0

func _ready() -> void:
	super()  # add_to_group, _setup_components, _setup_effects

	var bar := OverheatBar.new()
	bar.position = Vector2(0, 22)
	add_child(bar)
	bar.setup(overheat_component)

func _setup_effects() -> void:
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

	var low_health_smoke := LowHealthSmoke.new()
	low_health_smoke.threshold = 0.3
	add_child(low_health_smoke)
	low_health_smoke.setup(health_component)

	_thruster = ThrusterEffect.new()
	_thruster.position = Vector2(0.0, 14.0)
	add_child(_thruster)

func _physics_process(_delta: float) -> void:
	if DialogPlayer.is_active:
		velocity = Vector2.ZERO
		return
	var speed := velocity.length()
	var forward_speed  := -velocity.y
	var backward_speed :=  velocity.y
	if forward_speed >= _DASH_SPEED_THRESHOLD:
		_thruster.set_state(ThrusterEffect.State.BOOST)
	elif backward_speed >= _DASH_SPEED_THRESHOLD:
		_thruster.set_state(ThrusterEffect.State.IDLE)
	elif speed >= _MOVE_SPEED_THRESHOLD:
		_thruster.set_state(ThrusterEffect.State.THRUST)
	else:
		_thruster.set_state(ThrusterEffect.State.IDLE)

## Scene-connected: HurtBox.received_damage → _on_hurt_box_received_damage.
func _on_hurt_box_received_damage(damage: int) -> void:
	_apply_damage(damage)

## Override: emit EventBus, play hit effect, handle death.
func _on_health_changed(current: int) -> void:
	super(current)  # emits EventBus.player_health_changed
	_hit_effect.burst()
	if current == 0:
		_explosion_effect.explode()
		get_tree().paused = true
		var go := game_over_scene.instantiate()
		get_tree().root.add_child(go)
		get_tree().paused = false

## Override: complex overheat gating with overdrive and 80% hysteresis.
func _on_overheat_updated(pct: float) -> void:
	super(pct)  # emits EventBus.player_overheat_changed
	if overdrive_active:
		can_attack = true
		return
	if pct >= 100:
		can_attack = false
		return
	if pct >= 80 and not can_attack:
		return
	if pct < 80 and not can_attack:
		can_attack = true
