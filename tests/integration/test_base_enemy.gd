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
## excludes `bomber/bomb.tscn` (a HitBox-less projectile, not an enemy) without a hand-written
## skip list. Same sweep shape as `test_config_instance_isolation.gd`, checking type instead of
## config presence. A new enemy directory is covered automatically the day it lands.
##
## `station_turret.tscn` is an explicit extra case, not part of the sweep: `StationTurret` is a
## plain `Node2D` (never moves, never scores, survives its own death as visible wreckage — see its
## own file header), so it cannot satisfy `is BaseEnemy` and has no `died`/`was_killed`/scoring
## surface to pin. Only its hurtbox mask is comparable.
##
## ── Why ram_ship and space_station are not in the generic damage/death sweep ─────────────────
##
## `RamShip._on_received_damage()` (`ram_ship.gd:27-31`) does not call `health.decrease()` on its
## first hit at all — that hit only arms it (mask 33 -> 97) — so a single lethal-sized hit behaves
## completely differently there than on every other enemy. It gets its own dedicated test.
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
const _RAM_SHIP_SCENE := "res://assault/scenes/enemies/ram_ship/ram_ship.tscn"

## `base_enemy.gd:51`: `hurt_box.collision_mask = 97 | 1024`. Spelled out rather than computed so
## a change to that line is what this test is pinned against, not a copy of the same expression.
const _DEFAULT_MASK_AFTER_READY := 1121

## `ram_ship.gd:21`, applied after `super._ready()` sets the default above.
const _RAM_MASK_BEFORE_HIT := 33
## `ram_ship.gd:45`, applied inside `_enter_damaged_state()` on the first received hit.
const _RAM_MASK_AFTER_HIT := 97

## `bomber`, `bonus_drone`, `drone_interceptor`, `gunship`, `interceptor`, `kamikaze_drone`,
## `light_assault_ship`, `ram_ship`, `sniper_enemy`, `space_station`. A sweep that finds fewer has
## broken, and every assertion below is vacuous on a broken sweep.
const _MIN_ROSTER_SIZE := 10

## Enemies whose damage/death flow diverges from the generic BaseEnemy path enough that a shared
## loop would either be meaningless (space_station never frees on the lethal frame) or wrong
## (ram_ship's first hit deals no damage at all). Both get their own dedicated test below.
const _EXCLUDED_FROM_GENERIC_DAMAGE_FLOW := ["ram_ship", "space_station"]


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
		# ram_ship is the one enemy whose scene-authored _ready() narrows the mask BaseEnemy
		# just set — see test_ram_ship_hurtbox_mask_flips_after_its_first_hit below.
		var expected: int = _RAM_MASK_BEFORE_HIT if entry["name"] == "ram_ship" else _DEFAULT_MASK_AFTER_READY
		assert_eq(
			entity.hurt_box.collision_mask, expected,
			"%s: post-_ready() hurtbox mask must equal the pinned value" % entry["name"]
		)
	assert_gte(
		checked, _MIN_ROSTER_SIZE,
		"the roster sweep found only %d BaseEnemy scenes; every assertion above is vacuous below that" % checked
	)


## `entity` is typed `Node`/`BaseEnemy` throughout this file, deliberately never `RamShip` or
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


func test_ram_ship_hurtbox_mask_flips_after_its_first_hit_and_never_reverts() -> void:
	var ram := _spawn(_RAM_SHIP_SCENE) as BaseEnemy
	assert_not_null(ram, "ram_ship.tscn root is not a BaseEnemy")
	if ram == null:
		return
	assert_eq(ram.hurt_box.collision_mask, _RAM_MASK_BEFORE_HIT, "mask before any hit")

	ram.hurt_box.received_damage.emit(9999)
	assert_eq(ram.hurt_box.collision_mask, _RAM_MASK_AFTER_HIT, "mask after the first received hit")

	# Boundary: a second hit (now processed as ordinary damage, not an arming hit) must not
	# revert the mask.
	ram.hurt_box.received_damage.emit(1)
	assert_eq(ram.hurt_box.collision_mask, _RAM_MASK_AFTER_HIT, "mask must never revert once armed")


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


func test_ram_ships_first_hit_only_arms_it_and_deals_no_damage() -> void:
	var ram := _spawn(_RAM_SHIP_SCENE) as BaseEnemy
	assert_not_null(ram, "ram_ship.tscn root is not a BaseEnemy")
	if ram == null:
		return
	watch_signals(ram)
	assert_eq(ram.health.max_health, 999, "ram_config.tres is the source of truth for this test")

	ram.hurt_box.received_damage.emit(9999)

	# _enter_damaged_state() (ram_ship.gd:41-49) resets HP to a flat 100/100 as part of arming —
	# not "no change" — so two ordinary bullets can finish an otherwise 999-HP hull. This is the
	# damage amount, not health.decrease(), so `amount_changed`/`_on_health_changed` never fire.
	assert_eq(ram.health.max_health, 100, "arming resets max_health to a flat 100")
	assert_eq(ram.health.current_health, 100, "arming resets current_health to a flat 100")
	assert_signal_not_emitted(ram, "died", "the arming hit must not kill the ram ship")
	assert_false(ram.was_killed)
	assert_false(ram.is_queued_for_deletion())


func test_ram_ship_dies_on_a_lethal_hit_after_being_armed() -> void:
	var ram := _spawn(_RAM_SHIP_SCENE) as BaseEnemy
	assert_not_null(ram, "ram_ship.tscn root is not a BaseEnemy")
	if ram == null:
		return
	watch_signals(ram)

	ram.hurt_box.received_damage.emit(9999)  # arms it; _enter_damaged_state() resets HP to 100/100
	ram.hurt_box.received_damage.emit(ram.health.max_health)  # now ordinary lethal damage

	assert_signal_emit_count(ram, "died", 1, "died must fire exactly once")
	assert_true(ram.was_killed)
	assert_true(ram.is_queued_for_deletion())


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
			continue  # sniper_enemy has no `config` property at all.
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
	assert_gte(checked, _MIN_ROSTER_SIZE - 1, "roster sweep too small (sniper_enemy is the one exception)")


## sniper_enemy has no `config` property, so BaseEnemy's generic copy never runs for it — it
## hardcodes its score instead (`sniper_enemy.gd:45`). Pinned on its own since the generic sweep
## above cannot see it.
func test_sniper_enemy_hardcodes_its_score_value() -> void:
	var sniper := _spawn("res://assault/scenes/enemies/sniper_enemy/sniper_enemy.tscn")
	assert_eq(sniper.get("score_value"), 50)


# ── 4. AnimatedSprite2D 180° flip ─────────────────────────────────────────────

func test_animated_sprite_is_flipped_180_degrees() -> void:
	for name in ["light_assault_ship", "ram_ship"]:
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
		if entry["name"] in ["light_assault_ship", "ram_ship"]:
			continue
		var entity := _spawn(entry["scene"])
		checked += 1
		assert_null(
			entity.get_node_or_null("AnimatedSprite2D"),
			"%s: expected no AnimatedSprite2D child" % entry["name"]
		)
	assert_gte(checked, _MIN_ROSTER_SIZE - 2, "roster sweep too small")
