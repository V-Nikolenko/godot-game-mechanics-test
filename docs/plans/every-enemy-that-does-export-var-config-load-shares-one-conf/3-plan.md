# Per-instance ship config resources

> **Revision 2** — rewritten after review round 1 (`4-review.md`, `VERDICT: CHANGES_REQUESTED`).
> Changes: the copy now happens at **construction** as well as on tree entry (D1); the
> `PackedScene.pack()` justification is **withdrawn** as an out-of-tree artifact and the raw
> measurements are recorded in `probes/` (D4); test 6 is redesigned as an identity check taken from
> inside a child's `_ready()` (D2); build step 1's red/green expectations are corrected and the red
> run is pinned to an isolated process (D3); the prose-retirement list is replaced with the full
> 12-file table (D5); the copy lives in one static helper on `ShipConfig` (D6); the vacuous
> `test_project_load_integrity.gd` risk row is replaced (D7).

## Problem

Nothing the player sees is broken **today** — this is a latent defect and a live test hazard.

Ten entity scripts declare `@export var config: XConfig = load("res://.../x_config.tres")`.
`ResourceLoader` caches by path, so **every entity of a type in the process holds the same
object**, and it is the same object a test's `preload()` returns. Measured, Godot 4.6.3:
`station_a.config == station_b.config == load(path)` is `true`.

Two consequences:

- **Runtime:** the first line of code that writes `enemy.config.max_health = …` — a difficulty
  scaler, an elite variant, a boss rage phase — rewrites the shipped balance data for every other
  live entity of that type, and for the rest of the process. That is a bug with no symptom at the
  site that causes it. It is also reachable through this project's *supported* spawn-customisation
  idiom: `WaveManager` applies `initial_props` to a freshly instantiated entity **before**
  `add_child` (`wave_manager.gd:177-181`).
- **Tests:** a test that tunes a value through `config` silently clobbers the values a later test
  in the same run asserts. This already nearly happened: it is why the laser-phase test plan was
  rejected in review round 2, and it is currently defended by **prose only** — the same warning
  restated across twelve files. Prose has no failure signal.

What should change: **each entity instance owns its config, from the moment it is constructed.**
Writing to one entity's config affects that entity and nothing else, and the shipped `.tres` on
disk stays the single source of truth. And the guarantee should be enforced by the gate rather
than by a paragraph someone has to remember to read.

## Design

### One helper on `ShipConfig`, called from two lifecycle hooks

`global/resources/ship_config.gd` gains a static helper — a plain function on the type that
identifies a ship-stats resource, so the two entity base classes share one copy of the subtle part:

```gdscript
## Replace `node`'s `config` with a copy private to that node, if it still holds the shared,
## process-wide resource `ResourceLoader` caches.
##
## Idempotent by construction: `duplicate()` blanks `resource_path`, so a blank path IS the marker
## of an already-private copy and a second call is a no-op. That is what makes it safe to call from
## both `_init()` and `_enter_tree()`, and what stops a re-parent discarding runtime state.
##
## A node with no `config` property, or one holding something that is not a `ShipConfig`, is left
## alone — same generic `get()`/`is ShipConfig` idiom as `BaseEnemy._ready()`.
static func privatise(node: Object) -> void:
	var cfg: Variant = node.get("config")
	if cfg is ShipConfig and not (cfg as ShipConfig).resource_path.is_empty():
		node.set("config", (cfg as ShipConfig).duplicate())
```

Called from **both** hooks, on both entity roots:

```gdscript
func _init() -> void:
	ShipConfig.privatise(self)

func _enter_tree() -> void:
	ShipConfig.privatise(self)
```

- `assault/scenes/enemies/base_enemy.gd` — covers 9 of the 10 entities.
- `assault/scenes/allies/ally_fighter/ally_fighter.gd` — the one that extends `CharacterBody2D`
  directly.

**No change to any of the 10 declaration lines and no change to any `.tres`.**

### Why both hooks, and why that is not belt-and-braces

They close different windows, and neither alone is sufficient:

- **`_init()` closes the window that matters.** It runs at construction, so `entity.config` is
  private *before* `instantiate()` even returns. Without it, every write between `instantiate()`
  and `add_child()` still lands on the shared resource — and that is exactly where
  `wave_manager.gd:177-181` and `station_reinforcements.gd:237-242` apply spawn overrides, both with
  a comment saying they do it deliberately. Review finding D1 measured the failure: a pre-`add_child`
  write of `13` was still `13` on a later spawn.
- **`_enter_tree()` catches what `_init()` cannot see.** A `.tscn`-stored `config` override, or one
  supplied through `initial_props`, is applied *after* the constructor and would re-install a shared
  object. `_enter_tree()` runs after any such override and still before any child's `_ready()`.

The base-class-in-`_init()` arrangement rests on one measured fact, because `config` is declared on
each **subclass** while the copy lives in `BaseEnemy`: **a base class's `_init()` body runs after
the subclass's member initializers**, so `get("config")` there already holds the loaded resource.
Verified: `probes/probe_init_ordering.gd`, raw output in `probes/README.md`.

The `_enter_tree()`-before-child-`_ready()` ordering is likewise measured, and it is load-bearing:
all four station children read `_station.config` in their own `_ready()`
(`station_gunnery.gd:88-104`, `station_laser_phase.gd:80-93`, `station_reinforcements.gd:99-110`,
`station_death_sequence.gd:99-110`), which runs before the station's.

`grep -rn "func _enter_tree"` over `assault/ open_space/ global/ infiltration/` returns nothing, and
no entity script defines `_init()`, so neither hook collides with anything today.

### Alternatives rejected

- **`resource_local_to_scene = true` on the `.tres`.** Measured **inert** for our pattern: with the
  flag on, two `instantiate()` calls of a node whose script does `@export var config = load(path)`
  still compare `==`. The flag is applied by `PackedScene.instantiate()` to resources the *scene
  file stores*, and none of our scenes store a `config` override. Making it work would mean moving
  all 10 references into the `.tscn` files — two files to remember per new enemy, with no runtime
  signal when one is forgotten — and that arrangement is the one with the open engine bug for
  dynamically instantiated nested scenes ([godot#77380](https://github.com/godotengine/godot/issues/77380)),
  which is how `WaveManager` spawns everything.
- **Keep sharing; enforce "never write to `config`" in prose.** The current state, and a defensible
  stance — the community rule is "Resources for tuning values, plain variables for runtime state",
  and nothing in non-addon code writes to `config` today. Rejected because it has no failure signal,
  it already came within one review round of being violated, and the cost of the alternative is one
  helper, four two-line hooks and ~13.6 µs per spawn.
- **`_enter_tree()` alone** (revision 1's design). Rejected on measurement: it leaves the
  pre-`add_child` window open, which is precisely the window the project's own spawn-override idiom
  runs in.
- **The property initializer, `load(p).duplicate()` at all 10 sites.** More diff, ten places for the
  next enemy to get wrong, and it cannot honour a scene-stored or `initial_props` override at all.
  Revision 1 also rejected it because packing such a node embeds a `[sub_resource]`; **that
  justification is withdrawn** — re-measured in `probes/probe_pack_serialisation.gd`, all three copy
  sites embed once the node is actually in the tree, so `pack()` does not discriminate between them.
  (The editor-save scenario that row modelled does not arise either: non-`@tool` GDScript gets a
  placeholder instance in the editor, so no copy exists there to serialise. Reasoning, not
  measurement — noted as such in `probes/README.md`.)
- **`duplicate(true)` (deep).** Unnecessary: all 10 config classes are flat (`1-context.md`,
  re-verified in review), and the deep form has its own hole — resources inside `Array`/`Dictionary`
  properties are never duplicated. Instead of paying for a deep copy that would not be complete
  anyway, the test plan **pins flatness**, so the day a config gains a nested resource the gate
  says so.

## Build sequence

1. **Write `tests/integration/test_config_instance_isolation.gd`** (full test plan below) and run it
   against unmodified code, **in its own process**:
   `godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/integration/test_config_instance_isolation.gd -gexit`.
   Expected: **tests 1, 4, 5 and 6 fail; tests 2 and 3 pass.** It must be run in isolation and the
   result discarded, because on the broken build tests 4, 5 and 6 write into the shipped shared
   resource that every other test file's `preload()`ed `const` also holds — running the red pass
   inside the full suite would corrupt `test_enemy_contact_damage.gd` and the `test_station_*` files
   in a file-order-dependent way. Record the raw red output in `5-progress.md`.
2. **`global/resources/ship_config.gd`:** add `ShipConfig.privatise()`.
3. **`base_enemy.gd`:** add `_init()` and `_enter_tree()`, with the doc comment explaining why both.
   Re-run the new file: everything green except the ally row (step 4).
4. **`ally_fighter.gd`:** the same two hooks. Re-run the new file: all six green.
5. **Run the full suite.** `test_station_{laser_phase,gunnery,reinforcements,death_sequence}.gd`,
   `test_space_station.gd`, `test_enemy_contact_damage.gd`, `test_contact_hitbox_geometry.gd` and
   `test_enemy_hurtbox_geometry.gd` all read config-derived values and are the ones that would notice
   balance drift. Then `./scripts/check-test-leaks.sh`.
6. **Retire the stale prose.** Twelve files repeat "`config` is a single process-wide object"; after
   this change that is false of `entity.config` and true only of what `load()`/`preload()` returns.
   Every one of these must be corrected — several are *production* source, and several are
   justifications for decisions that stay correct for a **different** reason, so they are rewritten,
   not deleted:

   | File | Lines | What must the new text say |
   |---|---|---|
   | `tests/README.md` | 531-537 | Replace the trap with the new rule: `entity.config` is private per instance and safe to tune from a test; the object `load()`/`preload()` returns is still process-wide and must never be written |
   | `assault/scenes/enemies/space_station/space_station.gd` | 49-54 | "Never write to `station.config`" is no longer true; state that it is a private copy and point at the new invariant test |
   | `assault/scenes/enemies/space_station/space_station_config.gd` | 20-21, 56, 116, 151 | Four blocks repeating the sharing claim |
   | `assault/scenes/enemies/space_station/station_gunnery.gd` | 57-58, 102 | The **decision survives, the reason changes**: the node copies its tuning once because its own fields are the tunable surface the tests use and the conservative fallback defaults live there — not because the resource is shared |
   | `assault/scenes/enemies/space_station/station_laser_phase.gd` | 52-53, 90 | Same rewrite |
   | `assault/scenes/enemies/space_station/station_reinforcements.gd` | 73-74, 107 | Same rewrite |
   | `assault/scenes/enemies/space_station/station_death_sequence.gd` | 84, 108 | Same rewrite |
   | `assault/scenes/enemies/space_station/ENEMY.md` | 656 | Doc restating the sharing |
   | `docs/architecture/modules/assault.md` | 307, 342 | Same |
   | `tests/integration/test_station_gunnery.gd` | 9-11, 130 | Header point 1 |
   | `tests/integration/test_station_reinforcements.gd` | 10-11 | Header point 1 |
   | `tests/integration/test_station_death_sequence.gd` | 14-15, 283 | Header point 1 |
   | `tests/integration/test_station_laser_phase.gd` | 12-16, 111, 365-367 | Header point 1, plus the comment asserting in prose that `station.config` **is** the `preload()`ed object — now false |

7. **Docs** via the `updating-project-docs` skill: `docs/architecture/modules/global.md`
   (`ShipConfig` / the entity recipe), `docs/architecture/modules/assault.md`,
   `assault/scenes/enemies/space_station/ENEMY.md`, `docs/architecture/PROJECT.md` → Conventions, and
   `CLAUDE.md`'s config-driven-enemies bullet and its list of invariant tests.

## Test plan

New file `tests/integration/test_config_instance_isolation.gd` — an **invariant** test, in the
family of `test_enemy_contact_damage.gd`. Entities are spawned into a throwaway container `Node2D`
under `add_child_autofree` and added to the tree, per that file's harness notes 1 and 2
(`ExplosionEffect` parents particles to `actor.get_parent()`; `_ready()` must actually run).

The roster is a **`DirAccess` sweep**, not a hand-written list — `assault/scenes/enemies` and
`assault/scenes/allies`, top-level directories only, entity scene at `<dir>/<dir>.tscn`, following
`test_enemy_hurtbox_geometry.gd:65-68,317-334`. The shipped `.tres` is found by globbing the same
directory for exactly one `*config*.tres` (true for all ten today; the test asserts the "exactly
one" so an ambiguous directory fails loudly rather than silently picking one). `sniper_enemy` has no
config and is skipped by the `is ShipConfig` check.

| # | Test | Red on unmodified code? |
|---|---|---|
| 1 | `test_two_instances_never_share_a_config` | **yes** |
| 2 | `test_the_copy_carries_every_shipped_value` | no (passes trivially — it is the drift guard) |
| 3 | `test_configs_are_flat_so_a_shallow_copy_is_complete` | no (a true statement today — it is the early warning) |
| 4 | `test_writing_to_one_entitys_config_cannot_reach_another` | **yes** |
| 5 | `test_reentering_the_tree_keeps_the_same_private_copy` | **yes** |
| 6 | `test_station_children_see_the_private_copy_in_their_ready` | **yes** |

1. **`test_two_instances_never_share_a_config`** — for every swept scene: spawn two, assert
   `a.config != b.config`, and that neither is `load(<shipped .tres>)`. Guarded by
   `assert_gte(checked, 10, …)` so it cannot pass vacuously if the sweep breaks.
2. **`test_the_copy_carries_every_shipped_value`** — for every swept scene, compare each property in
   `cfg.get_script().get_script_property_list()` (script-declared only, so `script` and
   `resource_path` are excluded) against the value in the loaded `.tres`. The no-balance-drift guard;
   it also catches a `duplicate()` that drops a field.
3. **`test_configs_are_flat_so_a_shallow_copy_is_complete`** — for every shipped `*_config.tres`,
   assert no script-declared property is `TYPE_OBJECT`, `TYPE_ARRAY` or `TYPE_DICTIONARY`.
   `duplicate()` is shallow, and resources inside arrays/dictionaries are never duplicated even by
   `duplicate(true)`, so a nested field would make test 1's isolation a lie for that field. The
   failure message names the remedy (a per-class deep copy).
4. **The defect, stated directly.** `test_writing_to_one_entitys_config_cannot_reach_another`:
   spawn two gunships, set `a.config.max_health = 1`, assert `b.config.max_health` unchanged, that
   `load("…/gunship_config.tres").max_health` is unchanged, and that a **third** gunship spawned
   afterwards still gets the shipped value. Then the same assertions for a write made to a gunship
   that has been `instantiate()`d but **not yet added to the tree** — the D1 window, and the reason
   `_init()` is in the design.
5. **Boundary case — the idempotence guard.** `test_reentering_the_tree_keeps_the_same_private_copy`:
   spawn an entity, assert its config is private (`resource_path.is_empty()`), write a sentinel,
   `remove_child` then `add_child` again, and assert the config is the *same object* and still holds
   the sentinel. This pins the `resource_path.is_empty()` check in `privatise()`; without that check
   the second `_enter_tree()` copies the copy, silently discarding per-instance state.
6. **Boundary case — the ordering the design rests on.**
   `test_station_children_see_the_private_copy_in_their_ready`: attach a throwaway probe `Node`
   (test-local inner class `ConfigProbe`, deliberately not named `Test*` so GUT does not treat it as
   an inner test collection) as a child of a `SpaceStation` **before** adding the station to the
   tree; its `_ready()` records `get_parent().config`. Assert the recorded object is
   **identical** to `station.config` afterwards **and** that `recorded.resource_path.is_empty()`.
   An identity check is required: review finding D2 showed that comparing *values* is green even for
   a `_ready()`-time copy, because the children copy identical numbers from the shared original.
   Then repeat for a second station and assert the two recorded objects differ.

## Risks

| Risk | Check |
|---|---|
| A shipped balance value changes | Test 2 compares every field against the `.tres` on disk, for all ten entities |
| `duplicate()` loses the script type, so `config is GunshipConfig` stops holding | Measured (and reproduced in review): `duplicate()` preserves the script and copies every storage property with 0 mismatches. Tests 1–2 exercise it on all ten |
| The base-class `_init()` does not see a subclass `@export` member | Measured: `probes/probe_init_ordering.gd`. Also covered end-to-end by test 4's pre-`add_child` half |
| A subclass later defines `_init()`/`_enter_tree()` without `super()` and silently loses the copy | Test 1's sweep covers every entity scene, so it fails the gate rather than shipping |
| Spawning all ten entities in one file leaks unfreed children (the `ExplosionEffect` trap) | Container `Node2D` + `add_child_autofree`, per `test_enemy_contact_damage.gd` harness note 1; then `./scripts/check-test-leaks.sh`, since GUT reports leaks only at process exit and the gate's `FATAL` regex misses them |
| Per-spawn cost | Measured 13.6 µs per `duplicate()` (1000 calls in 13.6 ms), now paid at most twice per entity. A dense wave is tens of spawns |
| Twelve files now state the opposite of the truth, several of them production source | Build step 6's table lists every file and line, and says which of them keep their decision but change their reason |
| A regression in the copy is invisible to the rest of the gate | Acknowledged: `test_project_load_integrity.gd` cannot see this change at all — it uses `can_instantiate()` and never adds a node to a tree (`:174-206`), so neither hook fires there. The whole net for this change is the new file plus `scripts/check-test-leaks.sh` |

## Out of scope

- **`ScoreTracker.score_config`** (`score_tracker.gd:26,52`) — the same `preload`-and-share pattern,
  but `ScoreConfig` extends `Resource`, not `ShipConfig`, and there is one `ScoreTracker` per level,
  so there is no cross-instance contamination to fix. Recorded as a follow-up task instead.
- **`AttackPatternResource` and the movement/formation/wave/level resources.** Also shared, and
  deliberately so — `station_gunnery.gd:79` states those must stay pure configuration. Widening the
  copy to them is a separate decision with its own blast radius.
- **Deep duplication.** Test 3 makes the flat assumption explicit and enforced; the day it fails is
  the day to design the deep copy.
- **Any change to a balance number.** This change is value-neutral by construction and test 2 pins it.
