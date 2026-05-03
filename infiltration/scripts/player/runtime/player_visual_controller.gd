extends RefCounted
class_name PlayerVisualController

var player_sprite: Sprite2D
var shadow_sprite: Sprite2D
var dash_particles: GPUParticles2D
var player_base_position: Vector2
var shadow_base_position: Vector2


func _init(sprite: Sprite2D, shadow: Sprite2D, particles: GPUParticles2D) -> void:
	player_sprite = sprite
	shadow_sprite = shadow
	dash_particles = particles
	player_base_position = player_sprite.position
	shadow_base_position = shadow_sprite.position


func apply_height(environment_height: float, z_position: float) -> void:
	player_sprite.position = player_base_position + Vector2(0.0, -(environment_height + z_position))
	shadow_sprite.position = shadow_base_position + Vector2(0.0, -environment_height)
	shadow_sprite.scale = Vector2.ONE * (1.0 - clampf(z_position / 300.0, 0.0, 0.5))


func update_dash_particles(is_dashing: bool, dash_direction: Vector2, z_position: float) -> void:
	if dash_particles == null:
		return

	if not is_dashing:
		dash_particles.emitting = false
		return

	var particle_material := dash_particles.process_material as ParticleProcessMaterial
	if particle_material != null and dash_direction != Vector2.ZERO:
		particle_material.direction = Vector3(-dash_direction.x, -dash_direction.y, 0.0)

	dash_particles.position = Vector2(0.0, -z_position + 4.0)
	if not dash_particles.emitting:
		dash_particles.restart()
	dash_particles.emitting = true
