# global/ui/mission_hud.gd
## Unified HUD for all missions that use health/shield, a weapon icon,
## and the player weapon-selection menu.
## Used by assault/scenes/gui/hud.tscn and open_space/scenes/gui/hud.tscn.
extends CanvasLayer

@onready var health_shield_bar: HealthShieldBar = $HealthShieldBar
@onready var weapon_icon: TextureRect  = $WeaponContainer/WeaponIcon
@onready var cooldown_overlay: ColorRect = $WeaponContainer/CooldownOverlay
@onready var player_menu: PlayerMenu = $PlayerMenu

var _cooldown_timer: Timer = null

func _ready() -> void:
	## Wait one frame so the player node is fully initialised before querying it.
	await get_tree().process_frame
	if not is_inside_tree():
		player_menu.connect_states(null, null)
		return

	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		player_menu.connect_states(null, null)
		return
	var p := players[0]

	var health := p.get_node_or_null("HealthComponent") as Health
	var shield := p.get_node_or_null("ShieldComponent") as Shield
	if health and shield:
		health_shield_bar.setup(health, shield)

	var rocket_state := p.get_node_or_null("AttackStateMachine/WarheadMissileShootingState") as RocketState
	if rocket_state:
		weapon_icon.texture = rocket_state.get_current_icon()
		rocket_state.weapon_changed.connect(_on_weapon_changed)
		_cooldown_timer = rocket_state.get_node("CooldownTimer") as Timer

	var weapon_state := p.get_node_or_null("AttackStateMachine/WeaponState") as WeaponState
	player_menu.connect_states(weapon_state, rocket_state)

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

func _on_weapon_changed(icon: Texture2D) -> void:
	weapon_icon.texture = icon
