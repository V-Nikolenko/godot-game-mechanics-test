## Intent test for `RamCorvette`'s two-phase armour gimmick and its config `max_health`.
##
## NOT characterization for the config-application case: `ram_corvette.gd` never applied
## `config.max_health`, so the scene's bare `Health` default (100) ran instead of the shipped
## `ram_corvette_config.tres` value (999) — a config field a developer can read but the runtime never
## honours, the same class of defect `test_enemy_contact_damage.gd` closed for `collision_damage`.
## Fixed by applying it in `_ready()`, matching every other config-driven enemy
## (`bomber.gd:19-20`, `fighter.gd:19-20`, etc).
##
## The mask assertions ARE characterization, and deliberately so: the armour gimmick (bullet-proof
## until a missile strips it, per `ram_corvette/ENEMY.md`) is intentional design, confirmed
## independently by `bullet.gd`'s piercing-sniper path treating the `ram_ships` group like
## `asteroids`. Pinning it here means a future "fix" of the mask without reading `ENEMY.md` fails
## the gate instead of silently reopening a filed and closed design question.
##
## Parented to a throwaway container `Node2D`, per `test_enemy_contact_damage.gd`'s harness note:
## `ExplosionEffect`/`BulletPool` reparent onto the enemy's parent, so it needs one it can own.
extends GutTest

const RAM_CORVETTE_SCENE: PackedScene = preload("res://assault/scenes/enemies/ram_corvette/ram_corvette.tscn")
const RAM_CONFIG: RamCorvetteConfig = preload("res://assault/scenes/enemies/ram_corvette/ram_corvette_config.tres")

## The player's primary bullet is `collision_layer = 64` (`bullet.tscn:44`).
const PLAYER_BULLET_LAYER: int = 64


func _spawn() -> RamCorvette:
	var container := Node2D.new()
	add_child_autofree(container)
	var ram := RAM_CORVETTE_SCENE.instantiate() as RamCorvette
	assert_not_null(ram, "ram_corvette.tscn root is not a RamCorvette")
	container.add_child(ram)
	return ram


func test_applies_config_max_health_on_ready() -> void:
	var ram := _spawn()
	assert_eq(
		ram.health.max_health, RAM_CONFIG.max_health,
		"ram_corvette must apply ram_corvette_config.tres's max_health, not the scene's bare Health default"
	)
	assert_eq(ram.health.current_health, RAM_CONFIG.max_health)


func test_hurtbox_mask_excludes_player_bullet_layer_while_armoured() -> void:
	var ram := _spawn()
	assert_eq(
		ram.hurt_box.collision_mask & PLAYER_BULLET_LAYER, 0,
		"armoured ram_corvette must be immune to the player's primary bullet layer (intended design)"
	)


func test_first_hit_strips_armour_and_opens_hurtbox_to_bullets() -> void:
	var ram := _spawn()
	ram._on_received_damage(1)  # simulates a missile HurtBox hit
	assert_ne(
		ram.hurt_box.collision_mask & PLAYER_BULLET_LAYER, 0,
		"the first hit must strip the armour and open the hurtbox to bullets"
	)
	assert_eq(ram.health.current_health, 100, "armour-strip must reset HP to the documented 100")


func test_second_hit_after_armour_stripped_deals_damage() -> void:
	var ram := _spawn()
	ram._on_received_damage(1)  # strips armour, resets HP to 100
	ram._on_received_damage(30)
	assert_eq(
		ram.health.current_health, 70,
		"once armour is stripped, hits must deal normal damage instead of retriggering the phase change"
	)


func test_emp_and_engine_boost_still_skip_the_ram() -> void:
	var ram := _spawn()
	var emp := EMPBlastModule.new()
	var boost := EngineBoostModule.new()
	autofree(emp)
	autofree(boost)
	assert_true(emp._is_immune(ram), "EMP must skip the Ram Corvette (_IMMUNE_CLASSES name)")
	assert_true(boost._is_immune(ram), "engine boost must skip the Ram Corvette (_IMMUNE_CLASSES name)")
