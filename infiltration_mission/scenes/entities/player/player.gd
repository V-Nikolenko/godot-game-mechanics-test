extends CharacterBody2D

@export var speed: float = 100.0

# --- DASH SETTINGS ---
@export var dash_speed: float = 300.0
@export var dash_duration: float = 0.2
@export var dash_cooldown: float = 0.5

# --- AFTERIMAGE ---
@export var afterimage_scene: PackedScene
@export var afterimage_interval: float = 0.05
var afterimage_timer: float = 0.0

# --- JUMP PHYSICS ---
@export var jump_force: float = 250.0
@export var gravity: float = 600.0

const iso_diagonal_y_scale: float = 0.5

# --- DASH STATE ---
var dash_timer: float = 0.0
var dash_cooldown_timer: float = 0.0
var is_dashing: bool = false

# --- JUMP (FAKE Z AXIS) ---
var z_position: float = 0.0
var z_velocity: float = 0.0
var is_jumping: bool = false

# --- MOVEMENT MEMORY ---
var last_move_dir: Vector2 = Vector2.RIGHT

# --- REFERENCES ---
@onready var player_sprite = $Player
@onready var shadow = $player_shadow


func _physics_process(delta: float) -> void:
	# --- TIMERS ---
	dash_timer -= delta
	dash_cooldown_timer -= delta
	afterimage_timer -= delta

	if dash_timer <= 0:
		is_dashing = false

	# --- INPUT ---
	var input_dir: Vector2 = Input.get_vector(
		"move_left", "move_right",
		"move_up", "move_down"
	)

	if input_dir != Vector2.ZERO:
		last_move_dir = input_dir

	# --- DASH INPUT ---
	if Input.is_action_just_pressed("dash") and dash_cooldown_timer <= 0:
		is_dashing = true
		dash_timer = dash_duration
		dash_cooldown_timer = dash_cooldown

	# --- JUMP INPUT ---
	if Input.is_action_just_pressed("jump") and not is_jumping:
		is_jumping = true
		z_velocity = jump_force

	# --- APPLY GRAVITY (Z AXIS) ---
	if is_jumping:
		z_velocity -= gravity * delta
		z_position += z_velocity * delta

		if z_position <= 0:
			z_position = 0
			z_velocity = 0
			is_jumping = false

	# --- AFTERIMAGES ---
	if is_dashing:
		if afterimage_timer <= 0:
			_spawn_afterimage()
			afterimage_timer = afterimage_interval

	# --- MOVEMENT ---
	if is_dashing:
		var dash_dir = _get_isometric_dir(last_move_dir)
		velocity = dash_dir * dash_speed
	else:
		if input_dir == Vector2.ZERO:
			velocity = Vector2.ZERO
		else:
			var move_dir = _get_isometric_dir(input_dir)
			velocity = move_dir * speed

	move_and_slide()

	# --- VISUAL HEIGHT OFFSET ---
	player_sprite.position.y = -z_position

	# --- SHADOW SCALE ---
	shadow.scale = Vector2.ONE * (1.0 - clamp(z_position / 300.0, 0.0, 0.5))


func _get_isometric_dir(dir: Vector2) -> Vector2:
	var result = dir

	if dir.x != 0.0 and dir.y != 0.0:
		result.y *= iso_diagonal_y_scale

	return result.normalized()


func _spawn_afterimage() -> void:
	if afterimage_scene == null:
		return

	var ghost = afterimage_scene.instantiate()

	# Add to parent so it stays in world space
	get_parent().add_child(ghost)

	ghost.global_position = global_position
	ghost.z_index = player_sprite.z_index - 1

	var ghost_sprite = ghost.get_node("Sprite2D")

	# Copy texture/frame (works for Sprite2D atlas)
	ghost_sprite.texture = player_sprite.texture
	ghost_sprite.hframes = player_sprite.hframes
	ghost_sprite.vframes = player_sprite.vframes
	ghost_sprite.frame = player_sprite.frame

	# Flip support
	if player_sprite.has_method("is_flipped_h"):
		ghost_sprite.flip_h = player_sprite.flip_h

	# Preserve jump height offset
	ghost_sprite.position = player_sprite.position

	# Tint effect
	ghost_sprite.modulate = Color(0.6, 0.8, 1.0, 0.7)
