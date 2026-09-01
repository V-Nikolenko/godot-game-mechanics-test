## StationTurret — one individually destructible gun emplacement on the SpaceStation.
##
## A plain Node2D rather than a BaseEnemy: it never moves, never scores, and must survive its
## own death as visible wreckage so the station reads as damaged rather than as a station that
## grew smaller. Keeping it in the tree also makes SpaceStation.live_turret_count() a
## deterministic read instead of a queue_free() frame-timing race.
class_name StationTurret
extends Node2D

## Fired exactly once, when this turret is destroyed. SpaceStation derives no state from it —
## the armour rule reads is_alive() live — but sub-items 3 and 4 want the event hook for the
## laser phase and for escalating fire from the survivors.
signal destroyed(turret: StationTurret)

const _TEXTURE_DESTROYED: Texture2D = preload("res://assault/assets/sprites/enemies/station_turret_destroyed.png")

@onready var health: Health = $Health
@onready var hurt_box: HurtBox = $HurtBox
@onready var sprite: Sprite2D = $Sprite2D

var _alive: bool = true
var _hit_effect: HitEffect


func _ready() -> void:
	hurt_box.received_damage.connect(_on_received_damage)
	health.amount_changed.connect(_on_health_changed)

	## BaseEnemy._ready() sets these for every other enemy; a plain Node2D has nothing doing it.
	## Layer 512 (enemy_hurtbox) is what the projectile HitBoxes monitor — their mask is 513.
	## The mask mirrors base_enemy.gd:25: bullets (64) + rockets (32) + layer 1 + asteroids
	## (1024). Copying the gunship scene's raw `collision_mask = 65` instead would omit bit 6
	## and the player's homing and warhead missiles would pass straight through every turret.
	hurt_box.collision_layer = 512
	hurt_box.collision_mask = 97 | 1024

	_hit_effect = HitEffect.new()
	add_child(_hit_effect)


func is_alive() -> bool:
	return _alive


func _on_received_damage(damage: int) -> void:
	if not _alive:
		return
	health.decrease(damage)


## Takes one argument: `Health.amount_changed` is DECLARED with zero parameters but EMITTED with
## one (health_component.gd:4 vs :42). A zero-arg handler raises an engine error at runtime and
## fails the GUT test that provoked it.
func _on_health_changed(current: int) -> void:
	if not _alive:
		return
	_hit_effect.burst()
	if current <= 0:
		_destroy()


func _destroy() -> void:
	## Guarded by the `_alive` checks above because Health.set_health() emits amount_changed on
	## EVERY call including 0 -> 0 (health_component.gd:40-42), so a dead turret hit again would
	## otherwise re-enter here and re-emit `destroyed`.
	_alive = false
	sprite.texture = _TEXTURE_DESTROYED

	## All three matter. `monitorable = false` only stops the projectile's HitBox seeing us;
	## HurtBox._on_area_entered fires off our OWN `monitoring` (hurtbox_component.gd:10-18), so
	## `monitoring = false` is what actually closes the intake. The shape disable makes it
	## unambiguous.
	hurt_box.set_deferred("monitoring", false)
	hurt_box.set_deferred("monitorable", false)
	var shape := hurt_box.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape:
		shape.set_deferred("disabled", true)

	var explosion := ExplosionEffect.new()
	add_child(explosion)
	explosion.explode()

	destroyed.emit(self)
