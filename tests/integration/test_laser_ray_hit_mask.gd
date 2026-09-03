## Pins `LaserRay.hit_mask_override` — the additive export added for the station laser phase
## (EPIC sub-item 3, `docs/plans/station-laser-phase/3-plan.md` §2).
##
## NOT a characterization test: the export is new code, so these assert intent.
##
## Why it matters: `LaserRay`'s default `_HIT_MASK` is `128 | 256 | 512`, and 512 is the layer the
## space station's own core `HurtBox` sits on (`space_station.tscn:68-71`). A beam fired from a
## node mounted on the station therefore damages the station — measured, the boss goes 600 -> 0 HP
## in one frame. The override lets that one emitter narrow its mask to the player hurtbox alone.
##
## The default case is the important half: the race hazards and Level 1's static laser columns all
## depend on the full `128 | 256 | 512`, so a change that silently narrowed it would break them
## with no other test to notice.
##
## Lives in integration/ rather than unit/ because it instances a real scene — `LaserRay._ready()`
## needs `$BeamSprite` and `$HitZone` (`tests/README.md`: unit/ is "no scene loading").
extends GutTest

const LASER_SCENE: PackedScene = preload("res://assault/scenes/hazards/laser_ray/laser_ray.tscn")

## The shipped default, duplicated here deliberately rather than read from the script: the point
## of the test is to fail if `_HIT_MASK` changes, so it must not track it.
const DEFAULT_MASK: int = 128 | 256 | 512

## Player hurtbox only — what the station laser phase uses.
const PLAYER_ONLY: int = 128


func _spawn(override: int) -> LaserRay:
	var laser := LASER_SCENE.instantiate() as LaserRay
	laser.auto_start = false
	## Must be set BEFORE add_child(): _ready() is what reads it.
	laser.hit_mask_override = override
	add_child_autofree(laser)
	return laser


func test_default_hit_mask_is_unchanged_when_override_is_zero() -> void:
	var laser := _spawn(0)
	assert_eq(laser.get_node("HitZone").collision_mask, DEFAULT_MASK,
		"an unconfigured LaserRay must still hit player (128), code-set enemy (256) and "
		+ "scene-set enemy/asteroid (512) hurtboxes")


func test_override_replaces_the_default_mask_entirely() -> void:
	var laser := _spawn(PLAYER_ONLY)
	var mask: int = laser.get_node("HitZone").collision_mask
	assert_eq(mask, PLAYER_ONLY, "the override replaces the mask, it does not OR into it")
	assert_eq(mask & 512, 0, "layer 512 must be clear — that is the station core's own hurtbox")
	assert_eq(mask & 256, 0, "layer 256 must be clear")


## Boundary: 0 means "use the default", not "collide with nothing". A beam that collides with
## nothing is inert, so the falsy-looking value must NOT be taken literally.
func test_zero_means_default_and_never_an_inert_beam() -> void:
	var laser := _spawn(0)
	assert_ne(laser.get_node("HitZone").collision_mask, 0,
		"hit_mask_override == 0 must fall back to _HIT_MASK, never produce a beam that hits nothing")


## The export must survive the round trip through the scene instance untouched, so a caller can
## read back what it set. Guards against a setter that normalises or clamps the value.
func test_override_value_is_readable_after_ready() -> void:
	var laser := _spawn(PLAYER_ONLY)
	assert_eq(laser.hit_mask_override, PLAYER_ONLY, "the export keeps the value it was assigned")
