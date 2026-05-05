# assault/scenes/player/weapons/behaviors/weapon_behavior.gd
class_name WeaponBehavior
extends RefCounted

## Strategy interface for firing a single shot. Subclasses override fire().
## state is the WeaponState node — used for add_child and accessing actor rotation.
## mode is the active WeaponModeResource.
## muzzle is the Marker2D the projectile spawns from.
func fire(_state: Node, _mode: WeaponModeResource, _muzzle: Marker2D) -> void:
	push_error("WeaponBehavior.fire() not implemented")
