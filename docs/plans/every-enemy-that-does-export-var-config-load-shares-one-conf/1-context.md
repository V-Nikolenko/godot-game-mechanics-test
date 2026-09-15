# Context — per-instance ship config resources

## The finding, restated

`@export var config: XConfig = load("res://.../x_config.tres")` appears on 10 entity scripts.
`ResourceLoader` caches by path, so **every instance in the process holds the same object**, and
it is the same object a test's `preload()` hands back. Verified by measurement (`/tmp/settest.gd`,
Godot 4.6.3): two freshly-constructed nodes with that initializer compare `==` to each other and
to a separate `load()` of the same path.

Two consequences:

1. **Runtime:** writing `enemy.config.max_health = …` on one enemy rewrites the shipped balance
   data for every other live enemy of that type, for the rest of the process. Nothing in
   non-addon code does this today (`grep -rn "config\.\w* *="` finds only GUT's own files), so
   the defect is latent, not live.
2. **Tests:** a test that tunes a value through `config` silently clobbers the values a later
   test in the same run asserts. This is not hypothetical — it is why the laser-phase test plan
   was rejected in review round 2, and it is already written up as a trap in three test headers
   and in `tests/README.md:533`.

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `global/resources/ship_config.gd` | `ShipConfig`, base of all 10 ship configs (`max_health`, `collision_damage`, `score_value`, `counts_toward_wave_clear`) | The one type that identifies a "ship stats resource"; the natural place for a shared helper |
| `assault/scenes/enemies/base_enemy.gd` | `BaseEnemy`; `_ready()` already reads `get("config")` generically to lift `score_value` / `counts_toward_wave_clear` | 9 of the 10 sites inherit it — a single fix point |
| `assault/scenes/enemies/{bomber,ram_ship,light_assault_ship,gunship,kamikaze_drone,bonus_drone,interceptor,drone_interceptor,space_station}/*.gd` | the 9 enemy scripts declaring the export | The sites; interceptor + drone_interceptor use `preload(...)`, the rest `load(...)` — identical caching either way |
| `assault/scenes/allies/ally_fighter/ally_fighter.gd` | `AllyFighter`, **not** a `BaseEnemy` (extends `CharacterBody2D` directly) | The one site a `BaseEnemy` fix would miss |
| `assault/scenes/enemies/space_station/station_{gunnery,laser_phase,reinforcements,death_sequence}.gd` | child nodes that read `_station.config` in their **own `_ready()`**, which runs *before* the station's | Constrains *when* a copy may be swapped in: children ready before parents |
| `tests/README.md:531-537` | documents the sharing as a trap tests must work around | Becomes stale the moment the sharing ends |
| `tests/integration/test_station_{laser_phase,gunnery,reinforcements,death_sequence}.gd` | headers repeat "never write to `station.config`" | Same; `test_station_laser_phase.gd:367` asserts in prose that `station.config` *is* the `preload()`ed object |

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `BaseEnemy._ready()` (`base_enemy.gd:35-41`) | The established generic `get("config")` + `is ShipConfig` idiom — no subclass type knowledge needed |
| `Resource.duplicate()` | Engine-native per-instance copy. All 10 config classes are **flat** (`grep` for `Resource`/`PackedScene`/`Texture2D`/`Curve`/`Array[` exports across the 10 `*_config.gd` finds nothing), so a shallow duplicate is a complete copy |
| `tests/integration/test_enemy_hurtbox_geometry.gd:314-334` | The `DirAccess.get_directories()` sweep over `assault/scenes/{enemies,allies}` that finds every entity scene, so a new enemy cannot escape an invariant |
| `tests/integration/test_enemy_contact_damage.gd` harness notes | The container-`Node2D` parenting rule and "`_ready()` must actually run" rule for spawning enemies in a test |

## Conventions that constrain this

- **Config-driven enemies** (`CLAUDE.md`): stats live in `*_config.tres`, applied in `_ready()`;
  the `.tres` wins over the scene's Health node. A fix must not change any shipped value.
- **Composition over inheritance**: acceptable to put the copy in `BaseEnemy`, but the helper
  itself should be a plain function on `ShipConfig`, usable by the non-`BaseEnemy` `AllyFighter`.
- **Tests are GUT and mostly characterization**; invariant tests are the documented exception and
  this is squarely one (`test_enemy_contact_damage.gd` is the closest sibling — an invariant over
  balance data rather than over files).
- **Signal arity / verbose-gated logging** — not touched by this change.

## Measured engine facts this plan rests on

Both measured in this repo with Godot 4.6.3, not recalled:

1. **A GDScript inline setter is NOT called for the member's own initializer.** A node declaring
   `@export var config = load(...): set(value): config = value.duplicate()` still ends up sharing
   the cached resource. So a setter alone cannot fix the default — the initializer must copy too.
2. **No `.tscn` in `assault/scenes/{enemies,allies}` stores a `config` override** (`grep` for
   `config = ` / `config = ExtResource` finds nothing), and **no enemy script defines `_init()` or
   `_enter_tree()`**, so neither hook is currently in use and adding one collides with nothing.

## Open questions for research

- Is per-instance duplication the idiomatic Godot answer, or is the intended mechanism
  `resource_local_to_scene` / `setup_local_to_scene()`? What are the limits of each?
- What does the engine community report as the actual failure mode of shared resources
  (the "shared resource between instances" class of bug), and what is the cost of duplicating?
- Is there a cheaper stance — keep sharing and enforce read-only — that shipped projects prefer?
