class_name RamShip
extends BaseEnemy

@export var speed: float = 110.0

var _damaged: bool = false

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	super._ready()
	hurt_box.collision_mask = 33  # missiles only (32 + 1); bullets ignored
	for child in get_children():
		if child is HitBox:
			(child as HitBox).damage = 50

# Override: first missile hit triggers damaged state instead of dealing damage.
# Subsequent hits (bullets and missiles) deal damage normally.
func _on_received_damage(damage: int) -> void:
	if not _damaged:
		_enter_damaged_state()
	else:
		health.decrease(damage)

func _enter_damaged_state() -> void:
	_damaged = true
	hit_flash_player.play("hit")

	var damaged_tex: Texture2D = load("res://assault/assets/sprites/ram_ship_damaged.png")
	var frames := SpriteFrames.new()
	frames.add_animation("default")
	frames.add_frame("default", damaged_tex, 1.0)
	_sprite.sprite_frames = frames
	_sprite.play("default")

	# Now vulnerable to bullets too
	hurt_box.collision_mask = 97

	# Reset to standard ship HP so two bullets finish it
	health.max_health = 100
	health.current_health = 100

func _physics_process(delta: float) -> void:
	velocity = Vector2(0, speed)
	move_and_slide()
	_check_off_screen()

func _check_off_screen() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var cam := get_viewport().get_camera_2d()
	if not cam:
		return
	if global_position.y > cam.global_position.y + viewport_size.y * 0.5 + 60.0:
		queue_free()
