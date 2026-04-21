extends CanvasLayer

@onready var health_bar: ProgressBar   = $HealthBar
@onready var weapon_icon: TextureRect  = $WeaponContainer/WeaponIcon
@onready var cooldown_overlay: ColorRect = $WeaponContainer/CooldownOverlay

var _cooldown_timer: Timer = null

func _ready() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() == 0:
		return

	var health := players[0].get_node("HealthComponent") as Health
	if health:
		health_bar.max_value = health.max_health
		health_bar.value = health.current_health
		health.amount_changed.connect(_on_health_changed)

	var rocket_state := players[0].get_node_or_null("AttackStateMachine/WarheadMissileShootingState") as RocketState
	if rocket_state:
		weapon_icon.texture = rocket_state.get_current_icon()
		rocket_state.weapon_changed.connect(_on_weapon_changed)
		_cooldown_timer = rocket_state.get_node("CooldownTimer") as Timer

func _process(_delta: float) -> void:
	if _cooldown_timer == null or _cooldown_timer.is_stopped():
		cooldown_overlay.visible = false
		return

	var progress := 1.0 - _cooldown_timer.time_left / _cooldown_timer.wait_time
	var container := cooldown_overlay.get_parent() as Control
	var h: float = container.size.y
	cooldown_overlay.position.y = progress * h
	cooldown_overlay.size = Vector2(container.size.x, (1.0 - progress) * h)
	cooldown_overlay.visible = true

func _on_health_changed(current: int) -> void:
	health_bar.value = current

func _on_weapon_changed(icon: Texture2D) -> void:
	weapon_icon.texture = icon
