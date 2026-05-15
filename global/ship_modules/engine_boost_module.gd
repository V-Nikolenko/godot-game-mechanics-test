# global/ship_modules/engine_boost_module.gd
class_name EngineBoostModule
extends ShipModuleBase

const _BOOST_SPEED: float = 900.0    ## px/s at the very start of the dash.
const _BOOST_END_SPEED: float = 300.0 ## px/s at the tail end (ease-out target).
const _BOOST_DURATION: float = 0.4   ## Seconds of the boost window.
const _DAMAGE: int = 45              ## Damage per enemy hit during boost.
const _HIT_RADIUS: float = 32.0      ## px around ship center to detect enemies.
const _COOLDOWN: float = 2.0

## Classes immune to boost damage (asteroids, ram ships — indestructible by design).
const _IMMUNE_CLASSES: Array[String] = ["BigAsteroid", "SmallAsteroid", "Asteroid", "RamShip"]

const _SPRITE_PATH: String = "SpriteAnchor/ShipSprite2D"
const _BOOST_COLOR: Color = Color(0.35, 0.85, 1.0, 1.0)

var _active: bool = false
var _time_left: float = 0.0
var _cooldown_left: float = 0.0
var _prev_damage_reduction: float = 0.0
var _hit_this_boost: Array[Node] = []
## Locked at activation so velocity stays perfectly straight every frame.
var _boost_dir: Vector2 = Vector2.ZERO

func get_display_name() -> String: return "Boost Drive"
func get_description() -> String:
	return "Press H to supercharge engines. Blasts the ship forward with a speed burst that rapidly decelerates over 0.4 seconds. Invincible during boost. Deals 45 damage to anything in the path — asteroids and ram ships are immune to damage. 2-second cooldown."
func get_icon() -> Texture2D:
	return preload("res://assault/assets/sprites/ui/icon_ship_module_engine_boost.png")
func get_slot() -> StringName: return &"engines"

func apply(_player: Node) -> void:
	pass

func remove(player: Node) -> void:
	if _active:
		_end_boost(player)

func try_activate(player: Node) -> bool:
	if _active or _cooldown_left > 0.0:
		return false
	_active = true
	_time_left = _BOOST_DURATION
	_hit_this_boost.clear()

	## Invincibility.
	_prev_damage_reduction = float(player.get("damage_reduction"))
	player.set("damage_reduction", 1.0)

	## Lock boost direction at activation so tick() re-asserts it every frame.
	var actor := player as Node2D
	if actor:
		_boost_dir = Vector2.UP.rotated(actor.rotation)
		player.set("velocity", _boost_dir * _BOOST_SPEED)

	## Tell _handle_thrust() to skip so damping / max_speed-cap don't fight us.
	player.set("engine_boost_active", true)

	## Visual: bright cyan tint.
	var sprite := player.get_node_or_null(_SPRITE_PATH) as CanvasItem
	if sprite:
		sprite.modulate = _BOOST_COLOR

	return true

func tick(player: Node, delta: float) -> void:
	if _active:
		## Ease-out: starts at _BOOST_SPEED, curves quickly down to _BOOST_END_SPEED.
		## progress goes 1→0 as time runs out; squaring it makes the drop sharp early.
		if _boost_dir != Vector2.ZERO:
			var progress: float = _time_left / _BOOST_DURATION
			var eased: float = progress * progress
			var speed: float = lerpf(_BOOST_END_SPEED, _BOOST_SPEED, eased)
			player.set("velocity", _boost_dir * speed)
		## Force thruster to cyan BOOST visual (overrides player's normal state).
		var thruster: ThrusterEffect = player.get("_thruster") as ThrusterEffect
		if thruster:
			thruster.set_state(ThrusterEffect.State.BOOST)
		_time_left -= delta
		_damage_nearby_enemies(player)
		if _time_left <= 0.0:
			_end_boost(player)
	elif _cooldown_left > 0.0:
		_cooldown_left -= delta

func _end_boost(player: Node) -> void:
	if not _active:
		return
	_active = false
	_time_left = 0.0
	_cooldown_left = _COOLDOWN
	_hit_this_boost.clear()
	_boost_dir = Vector2.ZERO
	player.set("damage_reduction", _prev_damage_reduction)
	player.set("engine_boost_active", false)
	var sprite := player.get_node_or_null(_SPRITE_PATH) as CanvasItem
	if sprite:
		player.create_tween().tween_property(sprite, "modulate", Color.WHITE, 0.2)

func _damage_nearby_enemies(player: Node) -> void:
	var actor := player as Node2D
	if actor == null:
		return
	for e: Node in player.get_tree().get_nodes_in_group("enemies"):
		if e in _hit_this_boost:
			continue
		if _is_immune(e):
			continue
		var n := e as Node2D
		if n == null:
			continue
		if n.global_position.distance_to(actor.global_position) > _HIT_RADIUS:
			continue
		var hb := n.get_node_or_null("HurtBox") as HurtBox
		if hb:
			hb.received_damage.emit(_DAMAGE)
		_hit_this_boost.append(e)

func _is_immune(node: Node) -> bool:
	for cls: String in _IMMUNE_CLASSES:
		if node.is_class(cls):
			return true
		var scr: Script = node.get_script() as Script
		if scr != null and scr.get_global_name() == cls:
			return true
	return false
