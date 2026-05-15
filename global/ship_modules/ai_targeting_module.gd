# global/ship_modules/ai_targeting_module.gd
class_name AITargetingModule
extends ShipModuleBase

const _COOLDOWN: float = 15.0
const _MAX_RANGE: float = 900.0

## Visual: thin green line drawn from player to nearest enemy.
const _LINE_COLOR: Color = Color(0.15, 1.0, 0.45, 0.45)
const _LINE_WIDTH: float = 1.5

var _cooldown_left: float = 0.0
var _indicator: Line2D = null

func get_display_name() -> String: return "AI Targeting"
func get_description() -> String:
	return "Passive: draws a targeting line toward the nearest enemy. Active (H): instantly snaps weapon aim to face the nearest enemy. 15-second cooldown."
func get_icon() -> Texture2D:
	return preload("res://assault/assets/sprites/ui/icon_ship_module_ai.png")
func get_slot() -> StringName: return &"cockpit"

func apply(player: Node) -> void:
	_spawn_indicator(player as Node2D)

func remove(_player: Node) -> void:
	_remove_indicator()

func try_activate(player: Node) -> bool:
	if _cooldown_left > 0.0:
		return false
	var actor := player as Node2D
	var target := _find_nearest_enemy(actor)
	if target == null:
		return false
	_cooldown_left = _COOLDOWN
	## Snap rotation so Vector2.UP.rotated(rotation) points toward target.
	var dir: Vector2 = target.global_position - actor.global_position
	actor.rotation = dir.angle() + PI * 0.5
	return true

func tick(player: Node, delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left -= delta
	_update_indicator(player as Node2D)

func _find_nearest_enemy(actor: Node2D) -> Node2D:
	if actor == null:
		return null
	var enemies := actor.get_tree().get_nodes_in_group("enemies")
	var nearest: Node2D = null
	var nearest_sq: float = _MAX_RANGE * _MAX_RANGE
	for e: Node in enemies:
		var n := e as Node2D
		if n == null:
			continue
		var d: float = n.global_position.distance_squared_to(actor.global_position)
		if d < nearest_sq:
			nearest_sq = d
			nearest = n
	return nearest

func _spawn_indicator(actor: Node2D) -> void:
	if actor == null:
		return
	_remove_indicator()
	var line := Line2D.new()
	line.top_level = true  ## World-space draw; not affected by ship rotation.
	line.width = _LINE_WIDTH
	line.default_color = _LINE_COLOR
	line.points = PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
	actor.add_child(line)
	_indicator = line

func _update_indicator(actor: Node2D) -> void:
	if not is_instance_valid(_indicator):
		_indicator = null
		return
	var target := _find_nearest_enemy(actor)
	if target == null:
		_indicator.visible = false
		return
	_indicator.visible = true
	_indicator.points = PackedVector2Array([actor.global_position, target.global_position])

func _remove_indicator() -> void:
	if is_instance_valid(_indicator):
		_indicator.queue_free()
	_indicator = null
