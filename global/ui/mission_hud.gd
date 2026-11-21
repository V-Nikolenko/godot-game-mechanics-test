# global/ui/mission_hud.gd
## Unified HUD for all missions that use health/shield, a weapon icon,
## and the player weapon-selection menu.
## Used by assault/scenes/gui/hud.tscn and open_space/scenes/gui/hud.tscn.
extends CanvasLayer

@onready var health_shield_bar: HealthShieldBar = $HealthShieldBar
@onready var shield_icon_strip: ShieldIconStrip = $ShieldIconStrip
@onready var weapon_icon: TextureRect  = $WeaponContainer/WeaponIcon
@onready var cooldown_overlay: ColorRect = $WeaponContainer/CooldownOverlay
@onready var player_menu: PlayerMenu = $PlayerMenu

var _cooldown_timer: Timer = null

## Phase 9 lock tells, code-built in _ready so both HUD scenes get them: a chip beside the weapon icon and a padlock over it.
var _jammed_chip: JammedChip = null
var _lock_glyph: LockGlyph = null
## The player the tells read; looked up lazily (a hub ship can arrive after the HUD).
var _lock_player: Node = null

func _ready() -> void:
	_build_lock_tells()
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
	if health:
		var temp_health: TempHealth = p.get_node_or_null("TempHealthComponent") as TempHealth
		health_shield_bar.setup(health, temp_health)
	if shield:
		shield_icon_strip.setup(shield)

	var rocket_state := p.get_node_or_null("AttackStateMachine/WarheadMissileShootingState") as RocketState
	if rocket_state:
		weapon_icon.texture = rocket_state.get_current_icon()
		rocket_state.weapon_changed.connect(_on_weapon_changed)
		_cooldown_timer = rocket_state.get_node("CooldownTimer") as Timer

	var weapon_state := p.get_node_or_null("AttackStateMachine/WeaponState") as WeaponState
	player_menu.connect_states(weapon_state, rocket_state)

func _build_lock_tells() -> void:
	var container := weapon_icon.get_parent() as Control
	var width: float = container.offset_right - container.offset_left
	var height: float = container.offset_bottom - container.offset_top
	_jammed_chip = JammedChip.new()
	_jammed_chip.anchor_top = 1.0
	_jammed_chip.anchor_bottom = 1.0
	_jammed_chip.offset_left = container.offset_right + 6.0
	_jammed_chip.offset_top = container.offset_top
	_jammed_chip.offset_right = _jammed_chip.offset_left + JammedChip.BAR_WIDTH
	_jammed_chip.offset_bottom = _jammed_chip.offset_top + 18.0
	add_child(_jammed_chip)
	_lock_glyph = LockGlyph.new()
	_lock_glyph.position = Vector2(
		(width - LockGlyph.GLYPH_SIZE.x) * 0.5, (height - LockGlyph.GLYPH_SIZE.y) * 0.5)
	container.add_child(_lock_glyph)

## The first node in group `player` that answers the lock API, connected to its refusals once; null when there is none.
func _find_lock_player() -> Node:
	if is_instance_valid(_lock_player):
		return _lock_player
	_lock_player = null
	var p := get_tree().get_first_node_in_group(&"player")
	if p == null or not p.has_method(&"abilities_locked"):
		return null
	_lock_player = p
	if p.has_signal(&"ability_press_refused"):
		p.connect(&"ability_press_refused", _on_press_refused)
	return p

func _on_press_refused() -> void:
	_jammed_chip.flash()

## Chip, bar and glyph follow the player's lock; with no player nothing shows.
func _update_lock_tells(delta: float) -> void:
	var p := _find_lock_player()
	if p == null or not bool(p.call(&"abilities_locked")):
		_jammed_chip.clear()
		_lock_glyph.visible = false
		return
	_jammed_chip.show_lock(float(p.call(&"ability_lock_fill")))
	_jammed_chip.step(delta)
	_lock_glyph.visible = true

func _process(delta: float) -> void:
	_update_lock_tells(delta)
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
