# global/abilities/parry_ability.gd
class_name ParryAbility
extends AbilityBase

const _WINDOW_SEC: float = 0.15
const _RADIUS: float = 24.0

var _area: Area2D = null
var _window_left: float = 0.0

func get_display_name() -> String: return "Parry"
func get_icon() -> Texture2D: return null
func get_cooldown() -> float: return 1.0

func activate(ctx: AbilityController) -> bool:
	if _window_left > 0.0:
		return false
	_open_window(ctx)
	return true

func tick(_ctx: AbilityController, delta: float) -> void:
	if _window_left <= 0.0:
		return
	_window_left = max(0.0, _window_left - delta)
	if _window_left == 0.0:
		_close_window()

func deactivate(_ctx: AbilityController) -> void:
	_close_window()

func _open_window(ctx: AbilityController) -> void:
	_window_left = _WINDOW_SEC
	_area = Area2D.new()
	_area.collision_layer = 0
	_area.collision_mask = 256  # enemy bullet HitBox layer
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = _RADIUS
	shape.shape = circle
	_area.add_child(shape)
	_area.area_entered.connect(_on_area_entered)
	ctx.actor.add_child(_area)
	var sprite := ctx.actor.get_node_or_null("SpriteAnchor/ShipSprite2D") as CanvasItem
	if sprite:
		sprite.modulate = Color(0.4, 1.0, 1.0, 1.0)
		var t := ctx.actor.create_tween()
		t.tween_property(sprite, "modulate", Color(1, 1, 1, 1), _WINDOW_SEC)

func _close_window() -> void:
	if _area and is_instance_valid(_area):
		if _area.area_entered.is_connected(_on_area_entered):
			_area.area_entered.disconnect(_on_area_entered)
		_area.queue_free()
	_area = null

func _on_area_entered(area: Area2D) -> void:
	var node: Node = area
	while node and not (node is EnemyBullet):
		node = node.get_parent()
	if node is EnemyBullet:
		_close_window()
		_window_left = 0.0
		(node as EnemyBullet).become_friendly()
