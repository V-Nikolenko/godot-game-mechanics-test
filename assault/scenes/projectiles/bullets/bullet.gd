## Bullet — the player's primary projectile (also pooled by AllyFighter).
##
## LIFETIME.
##
##   1. **A bullet is consumed by the first hit that actually deals damage** — `expired` fires and
##      (on the unpooled player path, via `WeaponBehavior._launch()`) frees the bullet. A
##      **deflected** hit does NOT count: `_on_hit_box_area_entered()` checks whether the target
##      reports `is_armored() == true` (duck-typed, same idiom as `is_laser_blocking()` in
##      `beam_behavior.gd`) and, if so, returns without emitting `expired` or spending a pierce
##      charge — the bullet keeps flying, at full damage, exactly as if the hit never happened.
##      This is deliberate and load-bearing: the space-station boss's armoured core spans the
##      whole hull, so a shot aimed at a turret has to survive crossing it, and the core's
##      `is_armored()` query is what tells this bullet the crossing was a deflection, not a kill.
##      See `space_station/ENEMY.md` -> "Core hurtbox". `PierceModule` raises the number of
##      *damaging* hits a bullet survives before `expired` fires (see `MAX_PIERCE` below).
##   2. **An unpooled bullet frees itself when it leaves the screen**, via `free_when_offscreen()`.
##
## `expired` means "this bullet's flight is over" for both consumers: `WeaponBehavior._launch()`
## connects it to `queue_free` for unpooled player bullets, and `BulletPool` connects it to a
## deferred recycle for `AllyFighter`'s pooled ones (`_launch()` is never called on that path, so
## the two wirings never collide). Any future entity that needs to deflect a bullet without
## consuming it must expose its own `is_armored()`-shaped query — nothing else grants the
## exemption.
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
	if _hit_is_deflected(area):
		## Armour refused the damage (SpaceStation core while a turret still lives). The hit still
		## registers visually on the target's own side; the bullet did not — no expired, no pierce
		## charge spent, keep flying.
		return
	if pierces_remaining > 0:
		## HurtBox already emitted received_damage(hb.damage) this physics step.
		## Defer the damage reduction so HurtBox reads the un-reduced value first.
		call_deferred("_apply_pierce")
		return
	expired.emit()


## True when the hurtbox we just overlapped refused to apply damage (e.g. the space-station core
## while any turret still lives). Duck-typed against `is_armored()` rather than a shared base
## class or a cached HurtBox flag — same idiom as `is_laser_blocking()` in `beam_behavior.gd`.
## Safe to query synchronously regardless of physics-signal ordering: `SpaceStation.is_armored()`
## depends only on live turret count, which a hit against the core itself never changes.
func _hit_is_deflected(area: Area2D) -> bool:
	var target := area.get_parent()
	return target != null and target.has_method("is_armored") and target.is_armored()
