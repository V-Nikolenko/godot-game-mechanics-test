# assault/scenes/player/states/reflect_state.gd
class_name ReflectState
extends Node

@export var actor: CharacterBody2D
@export var movement_controller: MovementController
@export_range(0.05, 0.5, 0.01) var window_sec: float = 0.15
@export_range(0.1, 5.0, 0.05) var cooldown_sec: float = 1.0
@export var reflect_radius: float = 24.0

var _cooldown_left: float = 0.0
var _window_left: float = 0.0
var _area: Area2D = null

func _ready() -> void:
	movement_controller.action_single_press.connect(_on_action)

func _physics_process(delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left = max(0.0, _cooldown_left - delta)
	if _window_left > 0.0:
		_window_left = max(0.0, _window_left - delta)
		if _window_left == 0.0:
			_close_window()

func _on_action(key_name: String) -> void:
	if key_name != "reflect":
		return
	if not UpgradeState.is_unlocked(&"reflect"):
		return
	if _cooldown_left > 0.0 or _window_left > 0.0:
		return
	_open_window()

func _open_window() -> void:
	_window_left = window_sec
	_cooldown_left = cooldown_sec

	_area = Area2D.new()
	_area.collision_layer = 0
	_area.collision_mask = 256  # enemy bullet HitBox layer (verified from enemy_bullet.tscn)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = reflect_radius
	shape.shape = circle
	_area.add_child(shape)
	_area.area_entered.connect(_on_area_entered)
	actor.add_child(_area)

	# Visual flash — cyan modulate on the player sprite for the window duration.
	var sprite := actor.get_node_or_null("SpriteAnchor/ShipSprite2D") as CanvasItem
	if sprite:
		sprite.modulate = Color(0.4, 1.0, 1.0, 1.0)
		var t := actor.create_tween()
		t.tween_property(sprite, "modulate", Color(1, 1, 1, 1), window_sec)

func _close_window() -> void:
	if _area and is_instance_valid(_area):
		if _area.area_entered.is_connected(_on_area_entered):
			_area.area_entered.disconnect(_on_area_entered)
		_area.queue_free()
	_area = null

func _on_area_entered(area: Area2D) -> void:
	# The area_entered fires for the HitBox child of an EnemyBullet.
	# Walk up to find an EnemyBullet root.
	var node: Node = area
	while node and not (node is EnemyBullet):
		node = node.get_parent()
	if node is EnemyBullet:
		_close_window()  # remove the reflect area before flipping the bullet
		(node as EnemyBullet).become_friendly()
