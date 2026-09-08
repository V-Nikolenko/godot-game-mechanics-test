class_name BaseEnemy
extends CharacterBody2D

signal died

@onready var health: Health = $Health
@onready var hurt_box: HurtBox = $HurtBox
@onready var hit_flash_player: AnimationPlayer = $HitFlashAnimationPlayer

## Read by ScoreTracker via the enemy's ShipConfig — overridable per-enemy if needed.
var score_value: int = 0
## True ONLY when this enemy died from damage (so ScoreTracker can tell
## kill apart from off-screen escape on tree_exited).
var was_killed: bool = false
## True for bonus medal targets — they award points but do NOT count toward
## the wave-clear bonus.
var counts_toward_wave_clear: bool = true
## False for enemies ScoreTracker should not penalise on escape (e.g. bonus drones — see their
## config's `counts_as_escape`). Independent of `counts_toward_wave_clear`.
var counts_as_escape: bool = true

var _hit_effect: HitEffect
var _explosion_effect: ExplosionEffect

## Give this enemy a config resource of its own, at construction and again on tree entry.
##
## Both hooks are needed, and they close different windows:
##
## - `_init()` runs before `instantiate()` returns, so `config` is private for every write made
##   BEFORE the enemy enters the tree. `wave_manager.gd:177-181` applies spawn overrides in exactly
##   that gap, deliberately and with a comment saying so, so an `_enter_tree()`-only copy would
##   leave this project's own spawn-customisation idiom writing to the shared resource.
## - `_enter_tree()` catches a `config` that a `.tscn` override or `initial_props` substituted in
##   AFTER the constructor, and still runs before any CHILD's `_ready()` — which the space station
##   depends on, since its four child nodes read `_station.config` in their own `_ready()`.
##
## `ShipConfig.privatise()` is idempotent, so calling it twice costs one `duplicate()`.
## Pinned by `tests/integration/test_config_instance_isolation.gd`.
func _init() -> void:
	ShipConfig.privatise(self)


func _enter_tree() -> void:
	ShipConfig.privatise(self)


func _ready() -> void:
	hurt_box.received_damage.connect(_on_received_damage)
	health.amount_changed.connect(_on_health_changed)
	hurt_box.collision_mask = 97 | 1024  # bullets (64) + rockets (32) + layer 1 + asteroid contact (1024)
	_rotate_sprite()
	_add_contact_hitbox()

	_hit_effect = HitEffect.new()
	add_child(_hit_effect)

	_explosion_effect = ExplosionEffect.new()
	add_child(_explosion_effect)

	# Propagate scoring fields from the subclass `config` property if it exists.
	# Subclasses (LightAssaultShip, RamShip, etc.) declare `@export var config:
	# SomeConfig` — Godot exposes that via get(), so we don't need to know the
	# concrete type here.
	var cfg: Variant = get("config")
	if cfg is ShipConfig:
		score_value = cfg.score_value
		counts_toward_wave_clear = cfg.counts_toward_wave_clear
		counts_as_escape = cfg.counts_as_escape

func _rotate_sprite() -> void:
	var sprite := get_node_or_null("AnimatedSprite2D") as Node2D
	if sprite:
		sprite.rotation_degrees = 180.0

func _add_contact_hitbox() -> void:
	var col := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if not col:
		return
	add_child(HitBox.matching_shape(col, 256, 0, 20))

func _on_received_damage(damage: int) -> void:
	health.decrease(damage)

func _on_health_changed(current: int) -> void:
	hit_flash_player.play("hit")
	_hit_effect.burst()
	if current == 0:
		print("[Enemy] %s DESPAWNED (died) at position %.0f, %.0f" % [name, global_position.x, global_position.y])
		was_killed = true
		died.emit()
		_explosion_effect.explode()
		queue_free()
