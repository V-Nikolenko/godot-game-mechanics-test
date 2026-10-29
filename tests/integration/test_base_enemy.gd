## Characterization tests for `BaseEnemy` (`assault/scenes/enemies/base_enemy.gd`), taken before
## the Phase 1 architecture rework touches it (`docs/plans/cmufklb100001p92xs1ey2fb1/3-plan.md`
## §3 step 1, "t1-pin-base-enemy"). These pin what the class does TODAY, quirks included, so the
## rework (DefenseProfile in t5, the death-print/`sprite_forward_angle` debt in t6, the brain/mover
## split in t10) lands against a known-good baseline instead of guessing what must survive.
##
## ── The roster sweep ──────────────────────────────────────────────────────────────────────────
##
## `_ENEMY_ROOT`'s subdirectories are swept for `<dir>/<dir>.tscn`, and only kept when the
## INSTANTIATED root `is BaseEnemy` — not merely "the directory has a scene", which is what
## excludes `enemy_ordnance/*.tscn` and similar non-enemy scenes without a hand-written
## skip list. Same sweep shape as `test_config_instance_isolation.gd`, checking type instead of
## config presence. A new enemy directory is covered automatically the day it lands.
##
## `station_turret.tscn` is an explicit extra case, not part of the sweep: `StationTurret` is a
## plain `Node2D` (never moves, never scores, survives its own death as visible wreckage — see its
## own file header), so it cannot satisfy `is BaseEnemy` and has no `died`/`was_killed`/scoring
## surface to pin. Only its hurtbox mask is comparable.
##
## ── Why ram_corvette and space_station are not in the generic damage/death sweep ─────────────────
##
## `RamCorvette._on_received_damage()` deflects every hit while any of its three `ArmorPlate`s lives,
## exactly like the station's core does while a turret lives, so a single lethal-sized hit on a fresh
## Corvette deals nothing. Its plate-by-plate vulnerability (bullets glance off, each rocket breaks the
## plate it hits, only then does the hull take damage) is owned by `test_ram_corvette.gd`.
##
## `SpaceStation` overrides both `_on_received_damage()` (deflects everything while a turret is
## alive) and `_on_health_changed()` (holds the wreck in the tree for `death_duration` seconds
## instead of freeing in the same frame — see `space_station.gd:184-218`). Reproducing that here
## would just re-implement `test_station_death_sequence.gd`, which already owns it. This file pins
## only what SpaceStation shares with the rest of the roster: its post-`_ready()` hurtbox mask and
## its scoring fields.
##
## ── Harness notes ─────────────────────────────────────────────────────────────────────────────
##
## 1. Each enemy is parented to a throwaway container `Node2D` via `add_child_autofree`, never to
##    the test directly — `ExplosionEffect` parents its particles to the actor's parent and
##    `BulletPool` resolves `get_parent().get_parent()` as its container. Same rule as
##    `test_config_instance_isolation.gd` and `test_enemy_contact_damage.gd`.
## 2. Damage is delivered by emitting `hurt_box.received_damage` directly, not through a physical
##    HitBox overlap — same technique `test_station_death_sequence.gd` and
##    `test_player_bullet_lifetime.gd` use. It bypasses the hurtbox's `collision_mask` entirely,
##    which is fine: the mask is pinned separately, by its own value, not by what it lets through.
## 3. No `await` anywhere. `container.add_child(entity)` runs `_ready()` synchronously because the
##    container is already inside the tree, and every signal in this chain
##    (`received_damage` -> `amount_changed` -> `died`) is a direct (synchronous) connection, so
##    `queue_free()` has already been called by the time `emit()` returns.
extends GutTest

const _ENEMY_ROOT := "res://assault/scenes/enemies"
const _STATION_TURRET_SCENE := "res://assault/scenes/enemies/space_station/station_turret.tscn"

## `DefenseProfile.apply_to()`: `hurt_box.collision_mask = 97 | 1024` (the default profile's mask).
## Spelled out rather than computed so a change to that value is what this test is pinned against,
## not a copy of the same expression.
const _DEFAULT_MASK_AFTER_READY := 1121

## `bomber`, `bonus_drone`, `razor_drone`, `gunship`, `gatling_interceptor`, `swarm_drone`,
## `fighter`, `ram_corvette`, `sniper`, `space_station`, `missile_corvette`, `support_ship`, `mine_layer`,
## `defense_turret`, `power_source`, `shield_generator`, `laser_emitter`. A sweep that finds fewer has broken, and every assertion below is vacuous on a
## broken sweep.
const _MIN_ROSTER_SIZE := 17

## Enemies whose damage/death flow diverges from the generic BaseEnemy path enough that a shared
## loop would either be meaningless (space_station never frees on the lethal frame) or wrong
## (ram_corvette's hull deflects every hit while a plate lives, like the station's core). Each is
## owned by its own suite (`test_station_death_sequence.gd`, `test_ram_corvette.gd`).
const _EXCLUDED_FROM_GENERIC_DAMAGE_FLOW := ["ram_corvette", "space_station"]


## `{name, scene}` per top-level directory under `_ENEMY_ROOT` whose `<dir>/<dir>.tscn` exists and
## whose instantiated root `is BaseEnemy`.
func _sweep() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var dir := DirAccess.open(_ENEMY_ROOT)
	assert_not_null(dir, "cannot open %s" % _ENEMY_ROOT)
	if dir == null:
		return found
	for sub in dir.get_directories():
		var scene_path := "%s/%s/%s.tscn" % [_ENEMY_ROOT, sub, sub]
		if not ResourceLoader.exists(scene_path):
			continue
		var scene := load(scene_path) as PackedScene
		if scene == null:
			continue
		# Never added to the tree, so _ready() does not run — just enough to check the type.
		var probe := scene.instantiate()
		var is_base_enemy := probe is BaseEnemy
		probe.free()
		if not is_base_enemy:
			continue
		found.append({"name": sub, "scene": scene_path})
	return found


## Harness note 1.
func _spawn(scene_path: String) -> Node:
	var container := Node2D.new()
	add_child_autofree(container)
	var scene := load(scene_path) as PackedScene
	assert_not_null(scene, "%s failed to load" % scene_path)
	var entity := scene.instantiate()
	container.add_child(entity)
	return entity


# ── 1. Hurtbox mask ───────────────────────────────────────────────────────────

func test_hurtbox_mask_after_ready_matches_the_pinned_value() -> void:
	var checked := 0
	for entry in _sweep():
		var entity := _spawn(entry["scene"]) as BaseEnemy
		assert_not_null(entity, "%s: root is not a BaseEnemy" % entry["name"])
		if entity == null:
			continue
		checked += 1
		# No enemy narrows the mask any more: the Ram Corvette's armour is a deflection rule (t16).
		assert_eq(
			entity.hurt_box.collision_mask, _DEFAULT_MASK_AFTER_READY,
			"%s: post-_ready() hurtbox mask must equal the pinned value" % entry["name"]
		)
	assert_gte(
		checked, _MIN_ROSTER_SIZE,
		"the roster sweep found only %d BaseEnemy scenes; every assertion above is vacuous below that" % checked
	)


## `entity` is typed `Node`/`BaseEnemy` throughout this file, deliberately never `RamCorvette` or
## `StationTurret`. Statically referencing either of those two class names from this script — even
## in a branch that never runs — makes the GDScript compiler resolve them at script-load time, and
## in this suite that leaves `station_turret_destroyed.png` and its `RID`s still allocated at
## process exit (`GATE FAIL: the GUT run leaked objects at exit`). Both classes only add moving
## parts BaseEnemy doesn't have; every field this file reads (`hurt_box`, `health`, `died`,
## `was_killed`) is already on `BaseEnemy`, or reachable by node name for the turret.
func _hurt_box(entity: Node) -> HurtBox:
	return entity.get_node_or_null("HurtBox") as HurtBox


func test_station_turret_hurtbox_mask_matches_the_pinned_value() -> void:
	var turret := _spawn(_STATION_TURRET_SCENE)
	var hurt_box := _hurt_box(turret)
	assert_not_null(hurt_box, "station_turret.tscn root has no HurtBox child")
	if hurt_box == null:
		return
	assert_eq(
		hurt_box.collision_mask, _DEFAULT_MASK_AFTER_READY,
		"the station turret's post-_ready() hurtbox mask must equal the pinned value"
	)


# ── 2. Damage -> hit flash -> died -> queue_free ──────────────────────────────

func test_lethal_damage_kills_and_frees_the_enemy() -> void:
	var checked := 0
	for entry in _sweep():
		if entry["name"] in _EXCLUDED_FROM_GENERIC_DAMAGE_FLOW:
			continue
		var entity := _spawn(entry["scene"]) as BaseEnemy
		assert_not_null(entity, "%s: root is not a BaseEnemy" % entry["name"])
		if entity == null:
			continue
		checked += 1
		watch_signals(entity)

		var lethal: int = entity.health.max_health
		entity.hurt_box.received_damage.emit(lethal)

		assert_signal_emit_count(entity, "died", 1, "%s: died must fire exactly once" % entry["name"])
		assert_true(entity.was_killed, "%s: was_killed must be set" % entry["name"])
		assert_true(
			entity.is_queued_for_deletion(),
			"%s: a dead enemy must be queued for deletion" % entry["name"]
		)
		assert_eq(
			entity.hit_flash_player.current_animation, "hit",
			"%s: the hit-flash animation must have played on the way to death" % entry["name"]
		)
	assert_gte(checked, _MIN_ROSTER_SIZE - _EXCLUDED_FROM_GENERIC_DAMAGE_FLOW.size(), "roster sweep too small")


func test_non_lethal_damage_does_not_emit_died() -> void:
	var checked := 0
	for entry in _sweep():
		if entry["name"] in _EXCLUDED_FROM_GENERIC_DAMAGE_FLOW:
			continue
		var entity := _spawn(entry["scene"]) as BaseEnemy
		assert_not_null(entity, "%s: root is not a BaseEnemy" % entry["name"])
		if entity == null:
			continue
		# bonus_drone ships with max_health = 1 (a deliberate one-hit medal target), so there is
		# no damage amount that is both non-zero and non-lethal for it.
		if entity.health.max_health <= 1:
			continue
		checked += 1
		watch_signals(entity)

		entity.hurt_box.received_damage.emit(1)

		assert_signal_not_emitted(entity, "died", "%s: a non-lethal hit must not emit died" % entry["name"])
		assert_false(entity.was_killed, "%s: was_killed must stay false" % entry["name"])
		assert_false(
			entity.is_queued_for_deletion(),
			"%s: a non-lethal hit must not free the enemy" % entry["name"]
		)
		assert_eq(
			entity.hit_flash_player.current_animation, "hit",
			"%s: the hit-flash animation must still play on a non-lethal hit" % entry["name"]
		)
	assert_gte(checked, 1, "roster sweep found no enemy that can take non-lethal damage")


# ── 3. Scoring fields copied from config ──────────────────────────────────────

func test_scoring_fields_are_copied_from_config() -> void:
	var checked := 0
	for entry in _sweep():
		var entity := _spawn(entry["scene"]) as BaseEnemy
		assert_not_null(entity, "%s: root is not a BaseEnemy" % entry["name"])
		if entity == null:
			continue
		var cfg: Variant = entity.get("config")
		if not (cfg is ShipConfig):
			continue
		checked += 1
		var ship_cfg := cfg as ShipConfig
		assert_eq(entity.score_value, ship_cfg.score_value, "%s: score_value" % entry["name"])
		assert_eq(
			entity.counts_toward_wave_clear, ship_cfg.counts_toward_wave_clear,
			"%s: counts_toward_wave_clear" % entry["name"]
		)
		assert_eq(
			entity.counts_as_escape, ship_cfg.counts_as_escape, "%s: counts_as_escape" % entry["name"]
		)
	assert_gte(checked, _MIN_ROSTER_SIZE, "roster sweep too small")


## The Sniper takes its score from `SniperConfig` like the rest of the roster (it used to hardcode 50 in
## `_ready()`, because it had no `config` property). Pinned on its own, against the shipped `.tres`, so the
## value is the legacy 50 and not whatever a future config default happens to be.
func test_sniper_score_value_is_copied_from_its_config() -> void:
	var sniper := _spawn("res://assault/scenes/enemies/sniper/sniper.tscn")
	assert_true(sniper.get("config") is SniperConfig, "the sniper now has a config property")
	assert_eq(sniper.get("score_value"), (load("res://assault/scenes/enemies/sniper/sniper_config.tres") as SniperConfig).score_value)
	assert_eq(sniper.get("score_value"), 50)


# ── 4. AnimatedSprite2D 180° flip ─────────────────────────────────────────────

func test_animated_sprite_is_flipped_180_degrees() -> void:
	for name in ["fighter"]:
		var entity := _spawn("%s/%s/%s.tscn" % [_ENEMY_ROOT, name, name])
		var sprite := entity.get_node_or_null("AnimatedSprite2D") as Node2D
		assert_not_null(sprite, "%s: expected an AnimatedSprite2D child" % name)
		if sprite == null:
			continue
		assert_eq(sprite.rotation_degrees, 180.0, "%s: AnimatedSprite2D must be rotated 180°" % name)


## Boundary: an enemy with a plain Sprite2D (no AnimatedSprite2D) is untouched by the flip —
## _rotate_sprite() looks up the node by name and does nothing when it is absent.
func test_enemies_without_an_animated_sprite_are_unaffected_by_the_flip() -> void:
	var checked := 0
	for entry in _sweep():
		if entry["name"] == "fighter":
			continue
		var entity := _spawn(entry["scene"])
		checked += 1
		assert_null(
			entity.get_node_or_null("AnimatedSprite2D"),
			"%s: expected no AnimatedSprite2D child" % entry["name"]
		)
	assert_gte(checked, _MIN_ROSTER_SIZE - 1, "roster sweep too small")


# ── 5. ContactProfile resolution (task cmuj4y8qx006cp52x77tfozc2, INTENT) ─────────────────────────
#
# Intent tests, not characterization: they pin the new contract (docs/plans/cmufs7ek60001nm2x6d0bt2et/
# 3-plan.md §2.3) that every legacy enemy resolves a default COLLISION profile — the mode that never
# touches the hitbox, so today's behaviour is unchanged — and that a scene-authored profile wins.

const _CONTACT_FIXTURE := preload("res://tests/helpers/contact_fixture.gd")

## Phase 2+ enemies that author their own `ContactProfile` in the scene, with the mode they declare. Every
## other enemy in the sweep is legacy and must resolve the default COLLISION.
const _AUTHORED_CONTACT_MODES := {
	"swarm_drone": ContactProfile.Mode.EXPLOSIVE,
	"razor_drone": ContactProfile.Mode.RAMMING,
	"ram_corvette": ContactProfile.Mode.ARMOR,
	"missile_corvette": ContactProfile.Mode.COLLISION,
	"support_ship": ContactProfile.Mode.NONE,
	"defense_turret": ContactProfile.Mode.NONE,
	"power_source": ContactProfile.Mode.NONE,
	"shield_generator": ContactProfile.Mode.NONE,
	"laser_emitter": ContactProfile.Mode.NONE,
}


func test_every_legacy_enemy_resolves_exactly_one_collision_contact_profile() -> void:
	var checked := 0
	for entry in _sweep():
		var entity := _spawn(entry["scene"]) as BaseEnemy
		if entity == null:
			continue
		checked += 1
		assert_not_null(entity.contact_profile, "%s: a contact profile is resolved" % entry["name"])
		if entity.contact_profile == null:
			continue
		var expected_mode: int = _AUTHORED_CONTACT_MODES.get(entry["name"], ContactProfile.Mode.COLLISION)
		assert_eq(entity.contact_profile.mode, expected_mode, "%s: resolved mode" % entry["name"])
		var profiles := entity.get_children().filter(func(c: Node) -> bool: return c is ContactProfile)
		assert_eq(profiles.size(), 1, "%s: exactly one ContactProfile child" % entry["name"])
		if entity.contact_hit_box != null and expected_mode == ContactProfile.Mode.COLLISION:
			assert_true(entity.contact_hit_box.monitorable, "%s: COLLISION leaves the hitbox monitorable" % entry["name"])
			assert_true(entity.contact_hit_box.monitoring, "%s: COLLISION leaves the hitbox monitoring" % entry["name"])
	assert_gte(checked, _MIN_ROSTER_SIZE, "roster sweep too small")


## Boundary: the Bonus Drone authors no ContactHitBox, and still resolves cleanly (no error is
## raised — GUT would fail this test on one).
func test_the_bonus_drone_resolves_a_profile_without_a_contact_hitbox() -> void:
	var drone := _spawn("%s/bonus_drone/bonus_drone.tscn" % _ENEMY_ROOT) as BaseEnemy
	assert_null(drone.contact_hit_box, "the bonus drone has no ContactHitBox")
	assert_not_null(drone.contact_profile)
	assert_false(drone.contact_profile.is_armed())
	drone.suspend_ai()  # arming a hitbox-less profile is harmless
	assert_eq(drone.hurt_box.collision_mask, _DEFAULT_MASK_AFTER_READY, "hurtbox mask unchanged")


func test_a_scene_authored_contact_profile_is_used_instead_of_a_default() -> void:
	var container := Node2D.new()
	add_child_autofree(container)
	var authored := _CONTACT_FIXTURE.profile(ContactProfile.Mode.RAMMING)
	var entity := _CONTACT_FIXTURE.build_enemy(authored, Vector2.ZERO)
	container.add_child(entity)
	assert_same(entity.contact_profile, authored)
	var profiles := entity.get_children().filter(func(c: Node) -> bool: return c is ContactProfile)
	assert_eq(profiles.size(), 1, "no default profile is added alongside an authored one")


# ── 6. Repair and tow hooks (epic cmufs7elw001pnm2xr3b6fteb, t3; INTENT) ──────────────────────────────
#
# Intent tests (docs/plans/cmufs7elw001pnm2xr3b6fteb/3-plan.md §2.4): `repair()` is silent (the hit flash
# and burst belong to health going DOWN), and `accept_tow()` lets an ally nudge an enemy only while its own
# brain allows it. Hand-ticked; no `await`. Brains are reached by node name and phase names, never by
# `RamCorvette` / `SniperBrain` class references (see the leak note above `_hurt_box`).

const _FIXTURE_ENEMY: PackedScene = preload("res://tests/helpers/fixture_enemy.tscn")
const _HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const _DT := 1.0 / 60.0

## brain-owning enemy directory -> the phases whose `accepts_tow()` is false (plan §2.4 table).
const _REFUSING_PHASES := {
	"sniper": ["DECOY", "AIM", "LOCK", "FIRE"],
	"ram_corvette": ["WIND_UP", "CHARGE"],
	"bomber": ["RUN"],
	"fighter": ["RUN_IN"],
	"gatling_interceptor": ["SPIN_UP", "STREAM"],
	"razor_drone": ["WINDUP", "DASH", "FEINT_WINDUP", "FEINT_LUNGE"],
	"swarm_drone": ["WINDUP", "BURST"],
	"missile_corvette": ["TELEGRAPH", "SALVO"],
}


func _fixture() -> BaseEnemy:
	var container := Node2D.new()
	add_child_autofree(container)
	var enemy := _FIXTURE_ENEMY.instantiate() as BaseEnemy
	container.add_child(enemy)
	enemy.set_physics_process(false)  # hand-ticked
	return enemy


## Damages through the real hurtbox signal, then clears the feedback so a later assertion sees only what
## the next call did.
func _hit_and_clear(enemy: BaseEnemy, amount: int) -> void:
	enemy.hurt_box.received_damage.emit(amount)
	enemy.hit_flash_player.stop()
	enemy._hit_effect._particles.emitting = false


func test_repair_restores_health_without_flash_or_burst() -> void:
	var enemy := _fixture()
	_hit_and_clear(enemy, 6)
	assert_eq(enemy.health.current_health, 4, "sanity: damaged to 4")
	assert_eq(enemy.repair(3), 3, "3 HP restored")
	assert_eq(enemy.health.current_health, 7)
	assert_false(enemy.hit_flash_player.is_playing(), "a repair does not play the hit flash")
	assert_false(enemy._hit_effect._particles.emitting, "a repair does not fire the hit burst")


func test_repair_is_capped_at_max_health_and_returns_what_was_restored() -> void:
	var enemy := _fixture()
	_hit_and_clear(enemy, 4)
	assert_eq(enemy.repair(10), 4, "only the missing 4 HP come back")
	assert_eq(enemy.health.current_health, enemy.health.max_health)
	assert_eq(enemy.repair(5), 0, "at full health a repair restores nothing")
	assert_false(enemy.hit_flash_player.is_playing(), "and still does not flash")


func test_a_hit_after_a_repair_still_flashes_and_bursts() -> void:
	var enemy := _fixture()
	_hit_and_clear(enemy, 5)
	enemy.repair(3)
	enemy.hurt_box.received_damage.emit(1)
	assert_eq(enemy.hit_flash_player.current_animation, "hit", "the flash still plays on a hit")
	assert_true(enemy._hit_effect._particles.emitting, "and so does the burst")


func test_repair_of_a_non_positive_amount_returns_zero() -> void:
	var enemy := _fixture()
	_hit_and_clear(enemy, 5)
	assert_eq(enemy.repair(0), 0)
	assert_eq(enemy.repair(-3), 0)
	assert_eq(enemy.health.current_health, 5, "health is untouched")


func test_repair_of_a_dead_or_queued_enemy_returns_zero() -> void:
	var dead := _fixture()
	dead.hurt_box.received_damage.emit(dead.health.max_health)
	assert_eq(dead.health.current_health, 0, "sanity: dead")
	assert_eq(dead.repair(5), 0, "a dead enemy is not repaired")
	assert_eq(dead.health.current_health, 0, "and stays at 0")

	var queued := _fixture()
	_hit_and_clear(queued, 5)
	queued.queue_free()
	assert_eq(queued.repair(5), 0, "an enemy queued for deletion is not repaired")
	assert_eq(queued.health.current_health, 5)


func test_the_space_station_refuses_repair() -> void:
	var station := _spawn("%s/space_station/space_station.tscn" % _ENEMY_ROOT) as BaseEnemy
	assert_false(station.can_be_repaired(), "the station answers false")
	station.health.current_health = station.health.max_health - 10
	var before: int = station.health.current_health
	assert_eq(station.repair(5), 0, "and repair() returns 0 on it")
	assert_eq(station.health.current_health, before, "health is untouched")
	assert_true(_fixture().can_be_repaired(), "an ordinary enemy can be repaired")


# ── tow ───────────────────────────────────────────────────────────────────────────────────────────

func test_a_live_ai_driven_enemy_accepts_a_tow_and_moves_along_it() -> void:
	var enemy := _fixture()
	assert_true(enemy.is_ai_driven(), "a brain and a mover, not suspended")
	assert_true(enemy.accept_tow(Vector2(100.0, 0.0)), "the tow is accepted")
	enemy._physics_process(_DT)
	assert_gt(enemy.velocity.x, 0.0, "the next step moves along the nudge")


func test_a_suspended_enemy_refuses_a_tow() -> void:
	var enemy := _fixture()
	enemy.suspend_ai()
	assert_false(enemy.is_ai_driven(), "a rail owns it")
	assert_false(enemy.accept_tow(Vector2(100.0, 0.0)))
	assert_eq(enemy._mover._nudge, Vector2.ZERO, "no nudge was left on the mover")


func test_an_enemy_without_a_brain_refuses_a_tow() -> void:
	var container := Node2D.new()
	add_child_autofree(container)
	var enemy := _FIXTURE_ENEMY.instantiate() as BaseEnemy
	enemy.get_node("Brain").free()  # the mover stays: a nudge accepted here would never be applied
	container.add_child(enemy)
	assert_false(enemy.is_ai_driven())
	assert_false(enemy.accept_tow(Vector2(100.0, 0.0)))
	assert_eq(enemy._mover._nudge, Vector2.ZERO, "no nudge was left on the mover")


func test_a_boosting_enemy_refuses_a_tow() -> void:
	var enemy := _fixture()
	enemy._mover.boost(Vector2.RIGHT, 300.0, 1.0)
	assert_false(enemy.accept_tow(Vector2(0.0, 100.0)))
	assert_eq(enemy._mover._nudge, Vector2.ZERO, "no nudge was left on the mover")


func test_the_mover_max_speed_is_reported_and_zero_without_a_mover() -> void:
	var enemy := _fixture()
	enemy._mover.max_speed = 275.0
	assert_eq(enemy.ai_mover_max_speed(), 275.0)
	var container := Node2D.new()
	add_child_autofree(container)
	var bare := _FIXTURE_ENEMY.instantiate() as BaseEnemy
	bare.get_node("EnemyMover").free()
	container.add_child(bare)
	assert_eq(bare.ai_mover_max_speed(), 0.0, "no mover, no speed")


func test_legacy_enemies_are_not_ai_driven() -> void:
	for dir in ["gunship", "bonus_drone"]:
		var enemy := _spawn("%s/%s/%s.tscn" % [_ENEMY_ROOT, dir, dir]) as BaseEnemy
		assert_false(enemy.is_ai_driven(), "%s has no brain" % dir)
		assert_false(enemy.accept_tow(Vector2(100.0, 0.0)), "%s refuses a tow" % dir)


## Every committed or telegraphed phase of each shipped brain refuses; every other phase accepts.
func test_each_brain_refuses_a_tow_in_exactly_its_committed_phases() -> void:
	for dir in _REFUSING_PHASES:
		var h = _HARNESS.open_space()
		add_child_autofree(h.root)
		var enemy := load("%s/%s/%s.tscn" % [_ENEMY_ROOT, dir, dir]).instantiate() as BaseEnemy
		enemy.get_node("Brain").start_engaged = true
		h.root.add_child(enemy)
		enemy.set_physics_process(false)
		var brain: EnemyBrain = enemy.get_node("Brain")
		var phases: Dictionary = (brain.get_script() as GDScript).get_script_constant_map()["Phase"]
		var refusing: Array = _REFUSING_PHASES[dir]
		for phase_name in refusing:
			assert_true(phases.has(phase_name), "%s has a phase %s" % [dir, phase_name])
			brain.enter_phase(phases[phase_name])
			assert_false(brain.accepts_tow(), "%s %s refuses a tow" % [dir, phase_name])
			assert_false(enemy.accept_tow(Vector2(50.0, 0.0)), "%s %s: the enemy refuses too" % [dir, phase_name])
		# One unlisted phase through the real entry code, then every other by setting the field.
		var unlisted_name: String = "APPROACH" if phases.has("APPROACH") else "ENTER"
		brain.enter_phase(phases[unlisted_name])
		assert_true(brain.accepts_tow(), "%s %s accepts a tow" % [dir, unlisted_name])
		for phase_name in phases:
			if phase_name in refusing:
				continue
			brain.phase = phases[phase_name]
			assert_true(brain.accepts_tow(), "%s %s accepts a tow" % [dir, phase_name])
		h.root.queue_free()


## The mover-less structures with a brain (Phase 8: the defense turret, the shield generator) have no mover, so they have no accepting phase and cannot
## join `_REFUSING_PHASES` (that table needs one): their brain and root refuse a tow in every phase. Reached by node path and the
## script's constant map, never by class name (the leak note above `_hurt_box`).
func test_a_mover_less_structure_brain_refuses_a_tow_in_every_phase() -> void:
	for dir in ["defense_turret", "shield_generator"]:
		var h = _HARNESS.open_space()
		add_child_autofree(h.root)
		var enemy := load("%s/%s/%s.tscn" % [_ENEMY_ROOT, dir, dir]).instantiate() as BaseEnemy
		h.root.add_child(enemy)
		enemy.set_physics_process(false)
		var brain: EnemyBrain = enemy.get_node("Brain")
		var phases: Dictionary = (brain.get_script() as GDScript).get_script_constant_map()["Phase"]
		assert_gt(phases.size(), 0, "the %s brain declares its phases" % dir)
		for phase_name in phases:
			brain.phase = phases[phase_name]
			assert_false(brain.accepts_tow(), "%s %s: the brain refuses a tow" % [dir, phase_name])
			assert_false(enemy.accept_tow(Vector2(50.0, 0.0)), "%s %s: the enemy refuses too" % [dir, phase_name])


# ── telegraph is not moved (boundary) ─────────────────────────────────────────────────────────────

const _TOW := Vector2(400.0, 0.0)


## One hand-ticked step: the enemy's own tick, then its velocity integrated.
func _step_enemy(enemy: BaseEnemy) -> void:
	var before := enemy.global_position
	enemy._physics_process(_DT)
	enemy.global_position = before + enemy.velocity * _DT


## `mode` 0 = never offered a tow, 1 = offered `accept_tow` every tick of LOCK, 2 = the refusal bypassed
## (the nudge written straight to the mover). Returns {drift: largest muzzle distance from where LOCK
## began, accepted: how many offers were accepted, round_dot: the fired round's heading against the locked
## line}.
func _sniper_lock_run(mode: int) -> Dictionary:
	var h = _HARNESS.open_space()
	add_child(h.root)
	h.player.global_position = Vector2(640.0, 560.0)
	var sniper := load("%s/sniper/sniper.tscn" % _ENEMY_ROOT).instantiate() as BaseEnemy
	var brain = sniper.get_node("Brain")
	brain.start_engaged = true
	brain.rng_seed = 4242
	sniper.config.engage_seconds = 1000.0
	sniper.global_position = Vector2(640.0, 80.0)
	h.root.add_child(sniper)
	sniper.set_physics_process(false)
	var phases: Dictionary = (brain.get_script() as GDScript).get_script_constant_map()["Phase"]
	var pool := sniper.get_node("RailPool") as BulletPool
	var muzzle := sniper.get_node("Muzzle") as Marker2D
	var result := {"reached": false, "drift": 0.0, "accepted": 0, "round_dot": -1.0}
	var t := 0.0
	while t < 15.0 and brain.phase != phases["LOCK"]:
		_step_enemy(sniper)
		t += _DT
		for r in pool._active.duplicate():
			r.expired.emit()
			pool._recycle(r)
	if brain.phase == phases["LOCK"]:
		result["reached"] = true
		var start := muzzle.global_position
		while brain.phase == phases["LOCK"] and brain.shots_fired == 0:
			if mode == 1:
				if sniper.accept_tow(_TOW):
					result["accepted"] += 1
			elif mode == 2:
				sniper._mover.add_nudge(_TOW)
			_step_enemy(sniper)
			result["drift"] = maxf(result["drift"], muzzle.global_position.distance_to(start))
		var round_ = brain.last_round
		if round_ != null:
			var heading := Vector2.DOWN.rotated(round_.rotation)
			result["round_dot"] = heading.dot((brain.lock_point - round_.global_position).normalized())
	h.root.free()
	return result


func test_a_locking_sniper_is_not_towed_and_fires_along_the_locked_line() -> void:
	var run := _sniper_lock_run(1)
	assert_true(run["reached"], "LOCK was reached")
	assert_eq(run["accepted"], 0, "every tow offered through LOCK was refused")
	assert_lte(run["drift"], 1.0, "the muzzle stays within 1 px of where LOCK began")
	assert_gt(run["round_dot"], 0.9999, "the round leaves along the locked line")


## Control: the same run with the refusal bypassed moves far - proof the row above can fail.
func test_a_sniper_whose_refusal_is_bypassed_is_dragged_off_its_line() -> void:
	var run := _sniper_lock_run(2)
	assert_true(run["reached"], "LOCK was reached")
	assert_gt(run["drift"], 50.0, "without the refusal the muzzle moves > 50 px")


## The positions of a real Ram Corvette (relative to where WIND_UP began) at the end of each WIND_UP tick.
## `mode` as in `_sniper_lock_run`. The ram crawls under its own brain, so the baseline is the untowed run.
func _ram_wind_up_run(mode: int) -> Dictionary:
	var h = _HARNESS.open_space()
	add_child(h.root)
	h.player.global_position = Vector2(640.0, 560.0)
	var ram := load("%s/ram_corvette/ram_corvette.tscn" % _ENEMY_ROOT).instantiate() as BaseEnemy
	var brain = ram.get_node("Brain")
	brain.start_engaged = true
	brain.rng_seed = 1717
	ram.config.engage_seconds = 1000.0
	ram.global_position = Vector2(300.0, 100.0)
	h.root.add_child(ram)
	ram.set_physics_process(false)
	var wind_up: int = (brain.get_script() as GDScript).get_script_constant_map()["Phase"]["WIND_UP"]
	var result := {"reached": false, "path": [] as Array[Vector2], "accepted": 0}
	var t := 0.0
	while t < 6.0 and brain.phase != wind_up:
		_step_enemy(ram)
		t += _DT
	if brain.phase == wind_up:
		result["reached"] = true
		var start := ram.global_position
		while brain.phase == wind_up:
			if mode == 1:
				if ram.accept_tow(_TOW):
					result["accepted"] += 1
			elif mode == 2:
				ram._mover.add_nudge(_TOW)
			_step_enemy(ram)
			result["path"].append(ram.global_position - start)
	h.root.free()
	return result


func _largest_gap(a: Array, b: Array) -> float:
	var gap := 0.0
	for i in mini(a.size(), b.size()):
		gap = maxf(gap, (a[i] as Vector2).distance_to(b[i]))
	return gap


func test_a_winding_up_ram_is_not_towed() -> void:
	var baseline := _ram_wind_up_run(0)
	var towed := _ram_wind_up_run(1)
	assert_true(baseline["reached"] and towed["reached"], "WIND_UP was reached")
	assert_gt((baseline["path"] as Array).size(), 20, "sanity: a real wind-up")
	assert_eq(towed["accepted"], 0, "every tow offered through WIND_UP was refused")
	assert_eq((towed["path"] as Array).size(), (baseline["path"] as Array).size(), "same length")
	assert_lte(_largest_gap(towed["path"], baseline["path"]), 1.0,
		"within 1 px of where its own brain takes it")


func test_a_ram_whose_refusal_is_bypassed_is_dragged_off_its_wind_up() -> void:
	var baseline := _ram_wind_up_run(0)
	var control := _ram_wind_up_run(2)
	assert_gt(_largest_gap(control["path"], baseline["path"]), 50.0, "without the refusal it moves > 50 px")
