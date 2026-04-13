extends RefCounted
class_name PlayerVisualController

var player_sprite: Sprite2D
var shadow_sprite: Sprite2D
var afterimage_scene: PackedScene


func _init(sprite: Sprite2D, shadow: Sprite2D, dash_afterimage_scene: PackedScene) -> void:
	player_sprite = sprite
	shadow_sprite = shadow
	afterimage_scene = dash_afterimage_scene


func apply_height(z_position: float) -> void:
	player_sprite.position.y = -z_position
	shadow_sprite.scale = Vector2.ONE * (1.0 - clampf(z_position / 300.0, 0.0, 0.5))


func spawn_afterimage(world_parent: Node, global_position: Vector2) -> void:
	if afterimage_scene == null:
		return

	var ghost := afterimage_scene.instantiate()
	world_parent.add_child(ghost)
	ghost.global_position = global_position
	ghost.z_index = player_sprite.z_index - 1

	var ghost_sprite: Sprite2D = ghost.get_node("Sprite2D")
	ghost_sprite.texture = player_sprite.texture
	ghost_sprite.hframes = player_sprite.hframes
	ghost_sprite.vframes = player_sprite.vframes
	ghost_sprite.frame = player_sprite.frame
	ghost_sprite.flip_h = player_sprite.flip_h
	ghost_sprite.position = player_sprite.position
	ghost_sprite.modulate = Color(0.6, 0.8, 1.0, 0.7)
