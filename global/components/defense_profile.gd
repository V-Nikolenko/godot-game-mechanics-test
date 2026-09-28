## DefenseProfile — per-enemy data for what a HurtBox accepts, replacing the hardcoded mask
## `BaseEnemy` used to write for every enemy alike.
##
## `mask()` folds the `accepts_*` flags into a `CollisionLayers` bitmask. `apply_to(hurt_box)`
## writes that mask (and `accepted_damage_types`) onto a real `HurtBox`, and remembers it so a
## later `apply_alternate()` can re-apply without the caller holding the `HurtBox` reference.
##
## `apply_alternate()` is a one-way, permanent switch to a second flag set — exactly the ram
## ship's "armour breaks on the first missile hit and never re-forms" rule, and no more: there is
## no way back to the primary flags once switched. General multi-state armour is a later phase.
##
## A node, not a `Resource`: armour state (which set of flags is currently active) is runtime
## state that must be per-instance. A shared `Resource` would leak one ram ship's broken armour
## to every other ram ship, the exact trap `ShipConfig.privatise()` exists to avoid.
class_name DefenseProfile
extends Node

@export var accepts_player_bullets: bool = true
@export var accepts_player_rockets: bool = true
@export var accepts_environment: bool = true
@export var accepts_hazard_contact: bool = true

## Empty means "all damage types accepted" — see `HurtBox.accepted_damage_types`.
@export var accepted_damage_types: Array[HitBox.DamageType] = []

## The flags `apply_alternate()` switches to. Default to the primary flags, so a profile that
## never overrides them treats `apply_alternate()` as a no-op.
@export var alternate_accepts_player_bullets: bool = true
@export var alternate_accepts_player_rockets: bool = true
@export var alternate_accepts_environment: bool = true
@export var alternate_accepts_hazard_contact: bool = true

var _hurt_box: HurtBox = null


func mask() -> int:
	var m := 0
	if accepts_player_bullets:
		m |= CollisionLayers.PLAYER_HITBOX
	if accepts_player_rockets:
		m |= CollisionLayers.PLAYER_ROCKETS
	if accepts_environment:
		m |= CollisionLayers.ENVIRONMENT
	if accepts_hazard_contact:
		m |= CollisionLayers.HAZARD_CONTACT
	return m


func apply_to(hurt_box: HurtBox) -> void:
	_hurt_box = hurt_box
	hurt_box.collision_mask = mask()
	hurt_box.accepted_damage_types = accepted_damage_types


## One-way. Switches the primary flags to the alternate set and re-applies to the last `HurtBox`
## passed to `apply_to()`, if any. Calling it again is idempotent — the flags are already the
## alternate ones, so the mask does not change.
func apply_alternate() -> void:
	accepts_player_bullets = alternate_accepts_player_bullets
	accepts_player_rockets = alternate_accepts_player_rockets
	accepts_environment = alternate_accepts_environment
	accepts_hazard_contact = alternate_accepts_hazard_contact
	if _hurt_box:
		_hurt_box.collision_mask = mask()
