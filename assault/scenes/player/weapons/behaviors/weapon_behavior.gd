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
## USE THIS INSTEAD OF `state.add_child(bullet)`. Player bullets are unpooled, and nothing else in
## the game frees them: `Bullet.expired` fires on an ordinary hit as well as at the screen edge, so
## it cannot be wired to `queue_free` without consuming shots on first contact. Before this existed
## every shot the player ever fired stayed in the level — travelling, running `_physics_process`
## and holding a live HitBox — until the mission ended.
##
## Pinned by `test_player_bullet_lifetime.gd::test_every_weapon_behavior_hands_off_its_projectile_s_lifetime`,
## which enumerates `WeaponBehavior` subclasses from the project class list, so a behaviour added
## later cannot quietly reopen the leak.
func _launch(state: Node, bullet: Bullet) -> void:
	state.add_child(bullet)
	bullet.free_when_offscreen()
