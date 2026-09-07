# Progress — per-instance ship config resources

- [x] Step 1 — `tests/integration/test_config_instance_isolation.gd` written and run RED, in an
      isolated process (`-gtest=…test_config_instance_isolation.gd`), before any source change.
- [x] Step 2 — `ShipConfig.privatise()` in `global/resources/ship_config.gd`
- [x] Step 3 — `_init()` + `_enter_tree()` on `base_enemy.gd`
- [x] Step 4 — `_init()` + `_enter_tree()` on `ally_fighter.gd`; new file 6/6 green
- [x] Step 5 — full suite 338/338, `./scripts/check-test-leaks.sh` → LEAK CHECK PASS
- [x] Step 6 — stale prose retired in 13 files
- [x] Step 7 — docs updated via `updating-project-docs`

**Resume at:** done.
**Deviations from plan:** none.

## Step 1 — the red run (raw)

```
godot --headless --path . -s addons/gut/gut_cmdln.gd \
  -gtest=res://tests/integration/test_config_instance_isolation.gd -gexit

Scripts               1
Tests                 6
Passing Tests         2
Failing Tests         4
Asserts           272/310
```

Failing: `test_two_instances_never_share_a_config`,
`test_writing_to_one_entitys_config_cannot_reach_another`,
`test_reentering_the_tree_keeps_the_same_private_copy`,
`test_station_children_see_the_private_copy_in_their_ready` — tests 1, 4, 5 and 6, exactly as
`3-plan.md` predicts. Tests 2 (no balance drift) and 3 (flatness) pass, as predicted: on the broken
build the "copy" *is* the shipped resource, so it trivially matches.

Representative failures, all ten entities affected:

```
ram_ship: the instance holds the ResourceLoader-cached `.../ram_config.tres` itself
space_station: two instances share ONE config object
ally_fighter: a private copy has a blank resource_path ... (failed)
[1] expected to equal [200]: writing one gunship's config.max_health rewrote the shipped
                             gunship_config.tres in memory
[7] expected to equal [200]: a write to an entity that is instantiated but NOT YET in the tree
                             reached the shipped resource
two stations' children saw the SAME config object
```

Run in isolation deliberately: on the broken build tests 4, 5 and 6 write into the shipped shared
resource that every other test file's `preload()`ed `const` also holds, so a red run inside the full
suite would corrupt `test_enemy_contact_damage.gd` and the `test_station_*` files in a
file-order-dependent way. The result was discarded and the process exited.

## Step 2-4 — the change

- `global/resources/ship_config.gd` — `static func privatise(node: Object)`; `duplicate()` guarded
  by `not resource_path.is_empty()`, which is what makes it idempotent across the two call sites.
- `assault/scenes/enemies/base_enemy.gd` — `_init()` + `_enter_tree()`, both `ShipConfig.privatise(self)`.
- `assault/scenes/allies/ally_fighter/ally_fighter.gd` — the same pair.

New file green immediately after step 4: `Tests 6 / Passing Tests 6 / Asserts 310`.

## Step 5 — verification

```
./scripts/check-test-leaks.sh   → 39 scripts, 338 tests, 338 passing, 1797 asserts
                                  LEAK CHECK PASS - suite green, nothing leaked
bash /agent/verify.sh           → GATE PASS
```

(332 before this cycle, +6 from the new file. Nothing else moved.)

## Step 6 — the 13 files whose prose was retired

Source: `space_station.gd`, `space_station_config.gd` (4 blocks), `station_gunnery.gd`,
`station_laser_phase.gd`, `station_reinforcements.gd`, `station_death_sequence.gd`.
Docs: `tests/README.md`, `ENEMY.md`, `docs/architecture/modules/assault.md`.
Tests: `test_station_{gunnery,reinforcements,death_sequence,laser_phase}.gd`.

The four "copied rather than read through `_station.config`" blocks keep their **decision** and
change their **reason**: the node's own fields are the tunable surface the tests override and the
fallback for a station with no config at all. The "never write to `station.config`" rule is
narrowed to its still-true form: never write to what `load()`/`preload()` returns.

## Step 7 — docs

`docs/architecture/modules/global.md` (new `ShipConfig` / per-instance-config subsection),
`docs/architecture/modules/assault.md` (new **Per-instance config resources** subsection),
`docs/architecture/PROJECT.md` (config-driven convention + the invariant-test list),
`CLAUDE.md` (same two places).

## Deviations from plan

None in mechanism. Two additions the plan did not spell out, both from review round 2's
non-blocking findings: the two residual windows (`Node.duplicate()`, and `entity.config = load(...)`
on an entity already in the tree) are recorded in the new test's header, in `tests/README.md` and
in `global.md` rather than fixed, since neither is reachable from non-addon code today.
