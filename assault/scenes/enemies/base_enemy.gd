class_name BaseEnemy
extends CharacterBody2D

signal died

@onready var health: Health = $Health
@onready var hurt_box: HurtBox = $HurtBox
@onready var hit_flash_player: AnimationPlayer = $HitFlashAnimationPlayer
@onready var contact_hit_box: HitBox = get_node_or_null("ContactHitBox") as HitBox

## The direction the *art's nose* points in texture space, before any node rotation is applied.
## Default is nose-down, the Assault path-mover convention (`EnemyPathMover`'s facing rule reads
## this). A ported enemy whose art points up sets `-PI / 2` instead — `atan2(dir.x, -dir.y)` equals
## `dir.angle() + PI / 2`, so its on-screen facing is unchanged from before it declared this.
@export var sprite_forward_angle: float = PI / 2

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

## Resolved in `_ready()`: the scene-authored `DefenseProfile` child if there is one, otherwise a
## default one (all `accepts_*` true, mask 1121) created on the fly. Exposed so a subclass can
## call `apply_alternate()` on it, as `RamShip` does.
var defense_profile: DefenseProfile

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
	defense_profile = _resolve_defense_profile()
	defense_profile.apply_to(hurt_box)
	_rotate_sprite()

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

## Returns the scene-authored `DefenseProfile` child if there is one, so a scene that places one
## (e.g. the ram ship) never gets a second, default-flagged profile alongside it.
func _resolve_defense_profile() -> DefenseProfile:
	for child in get_children():
		if child is DefenseProfile:
			return child
	var profile := DefenseProfile.new()
	add_child(profile)
	return profile


## Rotates a child `AnimatedSprite2D` 180° (light assault ship, ram ship). This is a child-sprite
## art correction, independent of `sprite_forward_angle`: those two ships' animated art is drawn
## facing the opposite way from the body's own facing convention, and this rotation is what makes
## them agree on screen. It says nothing about the body's own rotation or facing.
func _rotate_sprite() -> void:
	var sprite := get_node_or_null("AnimatedSprite2D") as Node2D
	if sprite:
		sprite.rotation_degrees = 180.0

## Virtual damage hook: called whenever this enemy's `HurtBox` reports a hit. The default applies
## the damage to `health`. A subclass overrides this to change what a hit does — e.g. `RamShip`'s
## first hit only arms it, and `SpaceStation` deflects every hit while a turret is alive.
func _on_received_damage(damage: int) -> void:
	health.decrease(damage)

## Virtual death hook: called on every `health.amount_changed`. The default plays the hit-flash
## animation on any change, and on reaching 0 sets `was_killed`, emits `died`, plays the explosion
## and frees the enemy. A subclass overrides this to change what death does — e.g. `SpaceStation`
## holds its wreck in the tree for `death_duration` seconds instead of freeing immediately.
func _on_health_changed(current: int) -> void:
	hit_flash_player.play("hit")
	_hit_effect.burst()
	if current == 0:
		if OS.is_stdout_verbose():
			print("[Enemy] %s DESPAWNED (died) at position %.0f, %.0f" % [name, global_position.x, global_position.y])
		was_killed = true
		died.emit()
		_explosion_effect.explode()
		queue_free()
