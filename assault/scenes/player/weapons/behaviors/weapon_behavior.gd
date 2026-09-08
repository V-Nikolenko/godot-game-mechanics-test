# assault/scenes/player/weapons/behaviors/weapon_behavior.gd
class_name WeaponBehavior
extends RefCounted

## Strategy interface for firing a single shot. Subclasses override fire().
## state is the WeaponState node — used for add_child and accessing actor rotation.
## mode is the active WeaponModeResource.
## muzzle is the Marker2D the projectile spawns from.
func fire(_state: Node, _mode: WeaponModeResource, _muzzle: Marker2D) -> void:
	push_error("WeaponBehavior.fire() not implemented")

## Spawns a configured bullet into the world and hands it its own lifetime.
##
## USE THIS INSTEAD OF `state.add_child(bullet)`. Player bullets are unpooled, so nothing else in
## the game frees them. Two things end a bullet's flight, and both are wired here:
##   - `free_when_offscreen()` frees it once it leaves the screen.
##   - `expired -> queue_free` frees it on the first hit that actually deals damage (a deflected
##     hit — see `bullet.gd`'s header — does not emit `expired`, so it does not free the bullet).
## `AllyFighter`'s pooled bullets never go through `_launch()` (`BulletPool.acquire()` is a
## separate spawn path), so this connection never reaches a bullet the pool still owns.
##
## Pinned by `test_player_bullet_lifetime.gd::test_every_weapon_behavior_hands_off_its_projectile_s_lifetime`,
## which enumerates `WeaponBehavior` subclasses from the project class list, so a behaviour added
## later cannot quietly reopen the leak.
func _launch(state: Node, bullet: Bullet) -> void:
	state.add_child(bullet)
	bullet.free_when_offscreen()
	bullet.expired.connect(bullet.queue_free)
