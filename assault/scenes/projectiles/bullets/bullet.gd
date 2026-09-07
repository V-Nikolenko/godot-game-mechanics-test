## Bullet — the player's primary projectile (also pooled by AllyFighter).
##
## LIFETIME. Two rules, and they pull in opposite directions:
##
##   1. **A bullet is NOT consumed by a hurtbox it overlaps.** `_on_hit_box_area_entered()` emits
##      `expired` and keeps flying. This is deliberate and load-bearing: the space-station boss
##      needs shots aimed at its turrets to survive crossing the armoured core, or the turrets —
##      and so the boss — are unkillable. See `space_station/ENEMY.md` -> "Core hurtbox".
##   2. **An unpooled bullet frees itself when it leaves the screen**, via `free_when_offscreen()`.
##
## Because of rule 1, `expired` means "something happened", NOT "I am done" — it fires on an
## ordinary hit as well as at the range cap and the screen edge. **Never wire `expired` to
## `queue_free` on the player path**: that consumes the shot on first contact and breaks rule 1.
## `BulletPool` connects to it legitimately because recycling is reversible; freeing is not.
class_name Bullet
extends Area2D

signal expired

@export var speed: float = 900.0
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

## Hands this bullet's lifetime to itself: it frees when it leaves the viewport.
##
## OPT-IN, AND IT MUST STAY OPT-IN. `AllyFighter` recycles this same scene through a `BulletPool`
## (`ally_fighter.gd:11,22`), and `docs/BULLET_POOL.md` states the rule: *the pool is smart,
## bullets are dumb*. Moving this free into `_on_visible_on_screen_notifier_2d_screen_exited()`
## would make every pooled bullet destroy itself on its first trip off-screen — `_recycle()` still
## returns it to `_idle` (the deferred call runs before the delete queue flushes), so the pool's
## size looks healthy while filling with freed instances, and `acquire()` then errors and returns
## null. Pinned by `test_player_bullet_lifetime.gd::test_a_pooled_bullet_survives_leaving_the_screen`.
##
## Called by `WeaponBehavior._launch()`, which is how every player spawn site gets it.
func free_when_offscreen() -> void:
	var notifier := get_node_or_null("VisibleOnScreenNotifier2D") as VisibleOnScreenNotifier2D
	if notifier == null:
		push_warning("[Bullet] %s has no VisibleOnScreenNotifier2D — it will never despawn" % name)
		return
	if not notifier.screen_exited.is_connected(queue_free):
		notifier.screen_exited.connect(queue_free)

func _physics_process(delta: float) -> void:
	var step := speed * delta
	var forward := Vector2.UP.rotated(rotation)
	## Only the forward component of shooter velocity boosts the bullet.
	## Backward / lateral movement is ignored — clamped to 0 so the ship
	## moving backwards or sideways never slows or deflects the bullet.
	var forward_bonus: float = maxf(0.0, shooter_velocity.dot(forward))
	global_position += forward * (step + forward_bonus * delta)
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
