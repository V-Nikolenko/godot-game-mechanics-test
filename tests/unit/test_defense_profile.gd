## Unit tests for DefenseProfile (global/components/defense_profile.gd), the per-enemy data that
## replaced BaseEnemy's hardcoded `hurt_box.collision_mask = 97 | 1024`
## (docs/plans/cmufklb100001p92xs1ey2fb1/3-plan.md §2.8, task t5-defense-profile).
extends GutTest

const RAM_SHIP_SCENE := "res://assault/scenes/enemies/ram_ship/ram_ship.tscn"

## Mirrors CollisionLayers so a drift in the constants file shows up as a mismatch here too.
const _PLAYER_HITBOX := 64
const _PLAYER_ROCKETS := 32
const _ENVIRONMENT := 1
const _HAZARD_CONTACT := 1024
const _ALL_FLAGS_MASK := _PLAYER_HITBOX | _PLAYER_ROCKETS | _ENVIRONMENT | _HAZARD_CONTACT


func _make() -> DefenseProfile:
	var p := DefenseProfile.new()
	add_child_autofree(p)
	return p


# ── mask() ─────────────────────────────────────────────────────────────────

func test_default_flags_give_the_legacy_mask() -> void:
	var p := _make()
	assert_eq(p.mask(), 1121, "every accepts_* flag defaults true")
	assert_eq(p.mask(), _ALL_FLAGS_MASK)


## Every one of the 16 combinations of the four accepts_* flags produces exactly the OR of the
## named bits for the flags left on, and no others.
func test_mask_for_every_flag_combination() -> void:
	for bits in range(16):
		var p := _make()
		p.accepts_player_bullets = bool(bits & 1)
		p.accepts_player_rockets = bool(bits & 2)
		p.accepts_environment = bool(bits & 4)
		p.accepts_hazard_contact = bool(bits & 8)

		var expected := 0
		if p.accepts_player_bullets:
			expected |= _PLAYER_HITBOX
		if p.accepts_player_rockets:
			expected |= _PLAYER_ROCKETS
		if p.accepts_environment:
			expected |= _ENVIRONMENT
		if p.accepts_hazard_contact:
			expected |= _HAZARD_CONTACT

		assert_eq(
			p.mask(), expected,
			"bits=%d (bullets=%s rockets=%s environment=%s hazard=%s)" % [
				bits, p.accepts_player_bullets, p.accepts_player_rockets,
				p.accepts_environment, p.accepts_hazard_contact
			]
		)


func test_all_flags_off_gives_a_zero_mask() -> void:
	var p := _make()
	p.accepts_player_bullets = false
	p.accepts_player_rockets = false
	p.accepts_environment = false
	p.accepts_hazard_contact = false
	assert_eq(p.mask(), 0)


func test_accepted_damage_types_defaults_empty() -> void:
	var p := _make()
	assert_eq(p.accepted_damage_types, [])


# ── apply_to() ─────────────────────────────────────────────────────────────

func test_apply_to_writes_the_mask_and_damage_types_onto_the_hurt_box() -> void:
	var p := _make()
	p.accepts_player_bullets = false
	p.accepted_damage_types = [HitBox.DamageType.LASER]
	var hb := HurtBox.new()
	add_child_autofree(hb)

	p.apply_to(hb)

	assert_eq(hb.collision_mask, p.mask())
	assert_eq(hb.accepted_damage_types, [HitBox.DamageType.LASER])


# ── apply_alternate() ──────────────────────────────────────────────────────

func test_apply_alternate_switches_to_the_alternate_flags_and_reapplies() -> void:
	var p := _make()
	# The ram ship's shape: primary 33 (rockets + environment), alternate 97 (+ bullets).
	p.accepts_player_bullets = false
	p.accepts_hazard_contact = false
	p.alternate_accepts_hazard_contact = false
	var hb := HurtBox.new()
	add_child_autofree(hb)
	p.apply_to(hb)
	assert_eq(hb.collision_mask, 33, "primary mask before apply_alternate()")

	p.apply_alternate()

	assert_eq(hb.collision_mask, 97, "alternate mask re-applied to the same hurt box")
	assert_true(p.accepts_player_bullets)


func test_apply_alternate_is_one_way_and_idempotent() -> void:
	var p := _make()
	p.accepts_player_bullets = false
	var hb := HurtBox.new()
	add_child_autofree(hb)
	p.apply_to(hb)

	p.apply_alternate()
	var mask_after_first := hb.collision_mask

	# A second call must not revert or change anything further.
	p.apply_alternate()
	assert_eq(hb.collision_mask, mask_after_first, "a second apply_alternate() must be a no-op")


## Boundary: apply_alternate() before apply_to() has been called must not crash — there is no
## hurt box to re-apply to yet.
func test_apply_alternate_without_a_prior_apply_to_does_not_crash() -> void:
	var p := _make()
	p.apply_alternate()
	assert_true(p.accepts_player_bullets)


# ── BaseEnemy resolution: a scene-authored profile is not duplicated ────────

func test_scene_authored_profile_is_not_duplicated_by_base_enemy() -> void:
	var container := Node2D.new()
	add_child_autofree(container)
	var scene := load(RAM_SHIP_SCENE) as PackedScene
	assert_not_null(scene, "%s failed to load" % RAM_SHIP_SCENE)
	var ram := scene.instantiate() as BaseEnemy
	container.add_child(ram)  # runs _ready()

	var profiles: Array[Node] = []
	for child in ram.get_children():
		if child is DefenseProfile:
			profiles.append(child)

	assert_eq(profiles.size(), 1, "BaseEnemy must reuse the scene-authored DefenseProfile, not add a second one")
	assert_eq(ram.defense_profile, profiles[0], "BaseEnemy.defense_profile must be the scene-authored instance")
