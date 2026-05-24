class_name Bullet
extends Area2D

signal expired

@export var speed: float = 500.0
## 0 = no cap (despawn only when off-screen).
@export var range_px: float = 0.0
## Damage applied via the child HitBox. Pushed in _ready().
@export var damage: int = 50

## Velocity inherited from the shooting actor so bullets keep up with a fast ship.
var shooter_velocity: Vector2 = Vector2.ZERO

## Pierce support. Set by behaviors when PierceModule is equipped.
## Each hit decrements this; bullet is destroyed only when it reaches 0.
const MAX_PIERCE: int = 3
const PIERCE_DAMAGE_FACTOR: float = 0.55  ## 45% damage reduction per pierce.
var pierces_remaining: int = 0

## Sniper-bullet flags. When unlimited_pierce is true the bullet passes through
## every regular enemy at full damage, but stops on asteroids and ram-ships.
@export var unlimited_pierce: bool = false
@export var no_damage_decay: bool = false

var _traveled: float = 0.0

func _ready() -> void:
	var hb := get_node_or_null("HitBox") as HitBox
	if hb:
		hb.damage = damage

func reset() -> void:
	rotation = 0.0
	_traveled = 0.0

func _physics_process(delta: float) -> void:
	var step := speed * delta
	var forward := Vector2.UP.rotated(rotation)
	## Own speed in the firing direction, plus actor velocity so the bullet
	## doesn't appear to hang when the ship moves faster than bullet speed.
	global_position += forward * step + shooter_velocity * delta
	if range_px > 0.0:
		_traveled += step
		if _traveled >= range_px:
			expired.emit()
			queue_free()

func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	expired.emit()

## Called deferred after a pierce hit so the HurtBox reads damage at its original
## value before we reduce it for the next target.
func _apply_pierce() -> void:
	if not is_instance_valid(self):
		return
	pierces_remaining -= 1
	if no_damage_decay:
		return
	var hb := get_node_or_null("HitBox") as HitBox
	if hb:
		hb.damage = maxi(1, roundi(hb.damage * PIERCE_DAMAGE_FACTOR))

func _on_hit_box_area_entered(area: Area2D) -> void:
	if unlimited_pierce:
		var parent := area.get_parent()
		## Asteroids and ram-ships block the sniper bullet without taking damage.
		## Zero the HitBox damage first so the HurtBox reads 0 if it fires after us.
		if parent.is_in_group("asteroids") or parent.is_in_group("ram_ships"):
			var hb := get_node_or_null("HitBox") as HitBox
			if hb:
				hb.damage = 0
			expired.emit()
			queue_free()
		## Regular enemies: bullet passes through — do nothing, keep flying.
		return
	if pierces_remaining > 0:
		## HurtBox already emitted received_damage(hb.damage) this physics step.
		## Defer the damage reduction so HurtBox reads the un-reduced value first.
		call_deferred("_apply_pierce")
		return
	expired.emit()
