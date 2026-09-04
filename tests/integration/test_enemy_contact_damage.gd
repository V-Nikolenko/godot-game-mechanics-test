## Invariant test: every assault enemy's contact HitBox deals the damage its `*_config.tres` says.
##
## NOT characterization. Config-driven enemy stats are a `CLAUDE.md` convention — "assault enemies
## load stats from a `*_config.tres` applied in `_ready()`" — and a `.tres` field the runtime never
## reads is a silent lie in the balance data, not a quirk to pin. So a failure here is a bug to fix.
##
## ── Why this file exists ─────────────────────────────────────────────────────────────────────
##
## `BaseEnemy._add_contact_hitbox()` (`base_enemy.gd:49-60`) builds the contact HitBox with a
## hardcoded `damage = 20` and never looks at `config`. It runs from `BaseEnemy._ready()`, i.e.
## BEFORE the subclass has had a chance to read its own `.tres`, so every enemy that wants its
## configured `collision_damage` has to re-apply it afterwards. Most do
## (`bomber.gd:23-26`, `light_assault_ship.gd:20-23`, `ram_ship.gd:20-23`,
## `space_station.gd:119-122`) or override the helper outright (`drone_interceptor.gd:141-153`,
## `kamikaze_drone.gd:51-63`, `bonus_drone.gd:29-30`).
##
## The `Gunship` did not, so `gunship_config.tres`'s `collision_damage = 30` was dead and the
## heaviest ship in the roster rammed for 20. Nothing could see it: the field parses, the enemy
## works, and no test read the HitBox. This file closes that hole for the whole roster at once, so
## the next enemy that forgets the re-apply fails the gate instead of shipping.
##
## ── Reading the table ────────────────────────────────────────────────────────────────────────
##
## The two enemies with no `collision_damage` line in their `.tres` (`interceptor_config.tres`,
## and `sniper_enemy` which has no config at all) inherit `ShipConfig`'s default of 20
## (`ship_config.gd:8`), which happens to equal the base helper's hardcoded 20. They are listed
## anyway: the assertion is still meaningful, and if either default ever moves the mismatch
## surfaces here rather than in playtesting.
##
## `bonus_drone` is the one deliberate exception — it overrides `_add_contact_hitbox()` to add
## nothing at all, which is the correct realisation of its `collision_damage = 0`. `no_hitbox`
## marks that, and the test asserts BOTH halves (no HitBox *and* a config that agrees), so
## flipping the `.tres` to a non-zero value without touching the script fails.
##
## ── Harness notes ────────────────────────────────────────────────────────────────────────────
##
## 1. **Each enemy is parented to a throwaway container `Node2D`, not to the test directly.**
##    `ExplosionEffect` parents its particles to `actor.get_parent()` and `BulletPool` reparents
##    bullets into the same place (`bullet_pool.gd:47`), so the enemy needs a parent it can
##    scribble on. Same rule as `test_station_reinforcements.gd`.
## 2. **`_ready()` must actually run** — `health`/`hurt_box` are `@onready` and the whole config
##    application happens there — so every enemy is added to the tree, never just instantiated.
## 3. **Only DIRECT children are searched for the HitBox.** Bullets carry their own HitBox, but
##    they live under the enemy's `BulletPool`, and the station's turrets live under `Turrets`.
##    `HitBox.new()` is called in exactly four places in non-addon code
##    (`base_enemy.gd`, `drone_interceptor.gd`, `kamikaze_drone.gd`, `ally_fighter.gd`), and the
##    first three all `add_child()` straight onto the enemy — so "direct child" is unambiguous.
extends GutTest

## `scene`: the enemy to instantiate. `config_path`: its `.tres`, or "" when it has none.
## `no_hitbox`: this enemy is expected to carry no contact HitBox at all.
## `expected`: used only when `config_path` is "" — the damage the base helper hardcodes.
const ROSTER: Array[Dictionary] = [
	{
		"name": "bomber",
		"scene": "res://assault/scenes/enemies/bomber/bomber.tscn",
		"config": "res://assault/scenes/enemies/bomber/bomber_config.tres",
	},
	{
		"name": "bonus_drone",
		"scene": "res://assault/scenes/enemies/bonus_drone/bonus_drone.tscn",
		"config": "res://assault/scenes/enemies/bonus_drone/bonus_drone_config.tres",
		"no_hitbox": true,
	},
	{
		"name": "drone_interceptor",
		"scene": "res://assault/scenes/enemies/drone_interceptor/drone_interceptor.tscn",
		"config": "res://assault/scenes/enemies/drone_interceptor/drone_interceptor_config.tres",
	},
	{
		"name": "gunship",
		"scene": "res://assault/scenes/enemies/gunship/gunship.tscn",
		"config": "res://assault/scenes/enemies/gunship/gunship_config.tres",
	},
	{
		"name": "interceptor",
		"scene": "res://assault/scenes/enemies/interceptor/interceptor.tscn",
		"config": "res://assault/scenes/enemies/interceptor/interceptor_config.tres",
	},
	{
		"name": "kamikaze_drone",
		"scene": "res://assault/scenes/enemies/kamikaze_drone/kamikaze_drone.tscn",
		"config": "res://assault/scenes/enemies/kamikaze_drone/drone_config.tres",
	},
	{
		"name": "light_assault_ship",
		"scene": "res://assault/scenes/enemies/light_assault_ship/light_assault_ship.tscn",
		"config": "res://assault/scenes/enemies/light_assault_ship/fighter_config.tres",
	},
	{
		"name": "ram_ship",
		"scene": "res://assault/scenes/enemies/ram_ship/ram_ship.tscn",
		"config": "res://assault/scenes/enemies/ram_ship/ram_config.tres",
	},
	{
		"name": "space_station",
		"scene": "res://assault/scenes/enemies/space_station/space_station.tscn",
		"config": "res://assault/scenes/enemies/space_station/space_station_config.tres",
	},
	{
		"name": "sniper_enemy",
		"scene": "res://assault/scenes/enemies/sniper_enemy/sniper_enemy.tscn",
		"config": "",
		"expected": 20,
	},
]

## `ShipConfig.collision_damage` default, and the value `BaseEnemy._add_contact_hitbox()`
## hardcodes. The two agreeing is what makes the config-less entries above assertable.
const SHIP_CONFIG_DEFAULT_DAMAGE: int = 20


func _spawn(entry: Dictionary) -> BaseEnemy:
	var container := Node2D.new()
	add_child_autofree(container)
	var scene: PackedScene = load(entry["scene"]) as PackedScene
	assert_not_null(scene, "%s: scene failed to load" % entry["name"])
	var enemy := scene.instantiate() as BaseEnemy
	assert_not_null(enemy, "%s: root is not a BaseEnemy" % entry["name"])
	container.add_child(enemy)
	return enemy


## Direct children only — see harness note 3 in the file header.
func _contact_hitbox(enemy: BaseEnemy) -> HitBox:
	for child in enemy.get_children():
		var hb := child as HitBox
		if hb != null:
			return hb
	return null


func _expected_damage(entry: Dictionary) -> int:
	var path: String = entry["config"]
	if path.is_empty():
		return entry["expected"]
	var cfg := load(path) as ShipConfig
	assert_not_null(cfg, "%s: config failed to load as a ShipConfig" % entry["name"])
	return cfg.collision_damage


func test_every_enemy_contact_hitbox_matches_its_config() -> void:
	for entry in ROSTER:
		if entry.get("no_hitbox", false):
			continue
		var enemy := _spawn(entry)
		var hb := _contact_hitbox(enemy)
		assert_not_null(hb, "%s: has no contact HitBox as a direct child" % entry["name"])
		if hb == null:
			continue
		assert_eq(
			hb.damage,
			_expected_damage(entry),
			"%s: contact HitBox damage must equal its config's collision_damage" % entry["name"]
		)


## The exception, asserted from both sides so neither half can drift alone: the enemy adds no
## contact HitBox, AND its config asks for zero contact damage.
func test_bonus_drone_has_no_contact_hitbox_and_a_zero_damage_config() -> void:
	for entry in ROSTER:
		if not entry.get("no_hitbox", false):
			continue
		var enemy := _spawn(entry)
		assert_null(
			_contact_hitbox(enemy),
			"%s: is declared contact-harmless but carries a HitBox" % entry["name"]
		)
		assert_eq(
			_expected_damage(entry),
			0,
			"%s: adds no contact HitBox, so its config must ask for 0 collision damage" % entry["name"]
		)


## The specific regression this file was written for. Kept as its own named test so a failure
## reads as "the gunship stopped using its config" rather than as one line of a roster sweep.
func test_gunship_rams_for_its_configured_collision_damage() -> void:
	var entry: Dictionary = {}
	for e in ROSTER:
		if e["name"] == "gunship":
			entry = e
	var cfg := load(entry["config"]) as GunshipConfig
	assert_eq(cfg.collision_damage, 30, "gunship_config.tres is the source of truth for this test")
	assert_ne(
		cfg.collision_damage,
		SHIP_CONFIG_DEFAULT_DAMAGE,
		"the config must differ from the base helper's hardcoded value or this test is vacuous"
	)
	var gunship := _spawn(entry)
	var hb := _contact_hitbox(gunship)
	assert_not_null(hb, "gunship: has no contact HitBox as a direct child")
	if hb != null:
		assert_eq(hb.damage, cfg.collision_damage)
