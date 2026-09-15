# Review — per-instance ship config resources

VERDICT: CHANGES_REQUESTED

The diagnosis is right, the mechanism works, and I reproduced most of the plan's engine claims
independently. But the plan leaves the *largest half of the hazard open* (writes before the node
enters the tree), then proposes to rewrite the existing correct warning into prose that actively
encourages that hazard; one of its two boundary tests cannot fail; its red-first expectations are
wrong for one test and unsafe to run in-suite for two; and the single measurement that disqualifies
both simpler alternatives is unrecorded and contradicted by my own probe.

None of this is fatal to the approach. All of it is cheap to fix before implementation starts.

---

## What I verified as correct

Probes below were run with `godot --headless --path /work/repo -s <script>` on
`4.6.3.stable.official.7d41c59c4` (scratch dir `res://_probe_review/`, deleted afterwards).

- **The `get("config")` / `is ShipConfig` idiom is real and the proposed method fits it.**
  `assault/scenes/enemies/base_enemy.gd:39-42` is exactly that block (the plan cites 35-41; the
  comment starts at 35, the code at 39). `ShipConfig` at `global/resources/ship_config.gd:4-13` is
  the common base and every one of the 10 config classes extends it, including
  `AllyFighterConfig` (`assault/scenes/allies/ally_fighter/ally_config.gd:2-3`).
- **No collision.** `grep -rn "func _enter_tree"` over `assault/ open_space/ global/ infiltration/`
  returns **nothing** — there is no `_enter_tree()` anywhere in non-addon code. `_init()` exists only
  on `wave_builder.gd:20`, `formation_resource.gd:14` and four `infiltration/scripts/player/runtime/*`
  helper classes, none of them an entity. No `@tool` script exists under `assault/` or `global/`.
- **9-of-10 / 1-of-10 split is right.** Every enemy under `assault/scenes/enemies/*/` extends
  `BaseEnemy` (including `SpaceStation`, `space_station.gd:17-18`); `AllyFighter`
  (`ally_fighter.gd:1-2`) extends `CharacterBody2D` directly. Two sites is correct.
- **The ordering claim is correct and load-bearing in principle.** All four station children resolve
  `_station` and read `_station.config` in their own `_ready()`:
  `station_gunnery.gd:88-104`, `station_laser_phase.gd:80-93`, `station_reinforcements.gd:99-110`,
  `station_death_sequence.gd:99-110`. Probe: a parent whose `_enter_tree()` installs the copy is seen
  *as the copy* by its child's `_ready()`, and the child's object is identical to the one the parent
  ends up holding (`child saw copy: true | child saw the SAME object parent now holds: true`).
- **`duplicate()` behaves as claimed.** `GunshipConfig` duplicate: `dup is GunshipConfig: true`,
  `dup.resource_path == ""`, values equal, and a write to the copy leaves both the original and a
  fresh `load()` at 200. Isolation across two spawns and the `resource_path.is_empty()` idempotence
  guard both hold on re-parent (`reparent keeps same object: true, sentinel kept`).
- **The test harness precedent is real.** `tests/integration/test_enemy_hurtbox_geometry.gd:65-68`
  (`_ENEMY_DIRS` = enemies + allies) and `:317-334` are the `DirAccess.get_directories()` +
  `"%s/%s/%s.tscn"` sweep the plan copies. `test_enemy_contact_damage.gd:36-43` really does carry the
  container-`Node2D` and "`_ready()` must actually run" harness notes, and `_spawn()` at `:114-116`
  implements them.
- **The sweep's assumptions hold today.** All 11 entity directories have `<dir>/<dir>.tscn`; each has
  **exactly one** `*config*.tres` except `sniper_enemy`, which has none (so the `is ShipConfig` skip is
  the right filter). That is 10 configs, so `assert_gte(checked, 10, …)` is exactly tight.
- **Flatness holds.** No `@export` on any of the 10 `*_config.gd` is `Array`, `Dictionary`,
  `Resource`, `Texture*`, `PackedScene`, `Curve` or `NodePath`. Test 3 is a true statement today.
- **Nothing is reinvented.** `global/components/` has no config-copy helper and `global/resources/`
  holds only `ship_config.gd` / `score_config.gd` and the attack/formation/movement/wave/level
  resource folders. No `CLAUDE.md` convention is contradicted: no `.tres` changes, no balance change,
  no design-unit coordinate arithmetic, and no test asserts config *identity* that the change would
  break (`test_station_gunnery.gd:120-131`, `test_station_death_sequence.gd:260-283` and
  `test_station_laser_phase.gd:370-380` all compare *values*, so they stay green).

---

## Blocking findings

### D1 — The change does not close the hazard it exists to close, and the proposed prose rewrite makes it worse

`3-plan.md:104-109` (build step 5) instructs: rewrite the warnings to say *"the **instance's**
`config` is private and safe to tune from a test."*

That statement is false for the window that matters. `_enter_tree()` fires on `add_child()`. Every
write to `instance.config` **before** the node enters the tree still lands on the process-wide cached
resource. Probe (identical object ids printed for `preload()`, `load()` and a fresh instance's
`config`):

```
HELD id=-9223372009910565436  load() id=-9223372009910565436  px.config id (pre-add)=-9223372009910565436
after pre-add write: HELD.max_health=13  load().max_health=13
later spawn py.max_health=13 (shipped 200)
```

A second entity spawned afterwards inherits `13`. That is precisely the defect in `1-context.md`,
surviving the fix.

This is not a theoretical window — **it is this project's documented spawn-override idiom.**
`assault/scenes/systems/wave_manager/wave_manager.gd:177-181`:

```
	# Apply initial props BEFORE add_child so values are readable during _ready().
	if spawn.has("on_spawned"):
		spawn.on_spawned.call(entity)
	enemy_container.add_child(entity)
```

and `assault/scenes/enemies/space_station/station_reinforcements.gd:237-242` repeats it with the same
comment. So `WaveBuilder.prop(...)` — the one supported way to customise a spawn — runs entirely
inside the unprotected window. A "difficulty scaler / elite variant" (the plan's own motivating
example at `3-plan.md:14-16`) written the idiomatic way would poison the cache exactly as before,
while `tests/README.md` now told the author it was safe.

Required: either close the window or scope the promise honestly.

- **Preferred:** copy at construction *and* keep the idempotent `_enter_tree()` guard. The
  `resource_path.is_empty()` check makes the two compose safely — `_init()` privatises the default so
  there is no unprotected window at all, and `_enter_tree()` still privatises anything an override
  (`.tscn`-stored or `initial_props`) substituted in afterwards. The plan never considers the
  combination; it treats the two as mutually exclusive rows of a table.
- **Minimum:** if `_enter_tree()`-only is kept, the new prose must say *"private only once the entity
  is in the tree; a write before `add_child()` still hits the shipped resource"*, and test 4 must be
  extended with a pre-`add_child` write asserting the shipped `.tres` is unchanged — which on the
  `_enter_tree()`-only design would **fail**, which is the honest outcome.

### D2 — Test 6 cannot fail; it does not pin the thing the design rests on

`3-plan.md:149-154` defines `test_station_children_read_the_per_instance_config` as: spawn two
stations, assert `a.config != b.config`, and assert each station's `StationGunnery` copied timings
equal the shipped `.tres`.

Move the copy from `_enter_tree()` into `SpaceStation._ready()` and **both assertions still pass**:
the four children copy from the shared original, whose values are identical to the copy's, and the
two stations still end up with different objects. The test is green on the design it claims to
reject, so `3-plan.md:154` ("this is what makes `_enter_tree()` load-bearing") is not enforced by
anything.

The check has to be an *identity* check made from inside a child's `_ready()`. My probe is the shape
that works: attach a throwaway probe `Node` to the station instance before `add_child`, have its
`_ready()` record `get_parent().config`, then assert `recorded == station.config` **and**
`recorded.resource_path.is_empty()`. A `_ready()`-time copy fails both.

### D3 — The red-first expectations in build step 1 are wrong, and running the red pass in-suite corrupts it

`3-plan.md:95-97`: *"Tests 1, 4 and 5 must **fail**; 2, 3 and 6 must pass."*

- **Test 5 passes on unmodified code.** On today's build `config` *is* the cached resource, a sentinel
  write persists, `remove_child`/`add_child` changes nothing, and the object is trivially the same one
  — both of test 5's assertions hold. It is still a worthwhile guard (delete the
  `resource_path.is_empty()` check and the identity assertion goes red *after* the fix), but it is not
  a red-before test and the plan will read as a failed step-1 gate when it comes up green.
- **Tests 4 and 5 poison the run they are red in.** Both write into `config` (`max_health = 1`, and a
  sentinel), which on unmodified code is the shipped shared object held alive by every
  `preload()`ed `const` in the suite. Run as part of the full suite, step 1 silently corrupts
  `test_enemy_contact_damage.gd`, `test_station_*` and anything else asserting shipped values, in a
  later-file-dependent way. Step 1 must specify `-gtest=res://tests/integration/test_config_instance_isolation.gd`
  in isolation, and the plan should say why.

### D4 — The measurement that disqualifies both simpler alternatives is unrecorded, and my reproduction contradicts it

The decision table at `3-plan.md:55-59` rejects the property initializer and `_init()` solely because
`PackedScene.pack()` would write `[sub_resource]`, and asserts `_enter_tree()` writes
`config = ExtResource(...)` instead. `2-research.md` contains **no row for this** — the measurement
exists only as the sentence "Measured this cycle with scratch scenes … deleted after"
(`3-plan.md:61-62`). Nothing is reproducible.

My reproduction disagrees. Packing a live in-tree node and saving it:

```
PACK probe_parent.gd (_enter_tree)     sub_resource=true  config_line=true
PACK probe_init.gd   (_init)           sub_resource=true  config_line=true
PACK probe_initializer.gd              sub_resource=true  config_line=true
```

All three embed. The plan's row is presumably measured on a *not-yet-in-tree* node, where
`_enter_tree()` has not run — but that is not the scenario the row describes. And the scenario it
*does* describe (a human opening the enemy in the editor and saving) cannot be modelled by any of
these probes at all: in the editor a non-`@tool` GDScript gets a placeholder instance, so `_init()`,
`_enter_tree()` and `_ready()` all never run, and what `pack()` stores is decided by comparing the
placeholder's value against the script's cached default — which plausibly makes the `_init()` row
"no sub_resource" too.

Since this table is the whole justification for choosing the mechanism that leaves D1 open, it needs
to be settled properly: paste the probe script and its raw output into the plan folder (or into
`2-research.md`), state explicitly whether the node was in the tree, and — if the editor-save concern
is the real driver — say how it was reproduced in an actual editor save rather than a headless
`pack()`. If it cannot be reproduced, the row should be dropped and `_init()` reconsidered on the
merits, because `_init()` alone closes D1.

### D5 — "Retire the stale prose" is materially incomplete

`3-plan.md:104-109` lists `tests/README.md:531-537`, "the point-1 headers of the four station tests",
and `test_station_laser_phase.gd:365-367`. The README citation is exact (I checked: 531 is the
heading, 533-537 the trap). But `grep -rni "process-wide\|ResourceLoader caches"` finds the same claim
in **eight more files the plan does not name**, several of them production source, all of which become
factually wrong the moment the copy lands:

| File | Lines |
|---|---|
| `assault/scenes/enemies/space_station/space_station.gd` | 49-54 (incl. "Never write to `station.config`") |
| `assault/scenes/enemies/space_station/space_station_config.gd` | 20-21, 56, 116, 151 — four separate blocks |
| `assault/scenes/enemies/space_station/station_gunnery.gd` | 57-58, 102 |
| `assault/scenes/enemies/space_station/station_laser_phase.gd` | 52-53, 90 |
| `assault/scenes/enemies/space_station/station_reinforcements.gd` | 73-74, 107 |
| `assault/scenes/enemies/space_station/station_death_sequence.gd` | 84, 108 |
| `assault/scenes/enemies/space_station/ENEMY.md` | 656 |
| `docs/architecture/modules/assault.md` | 307, 342 |
| `tests/integration/test_station_gunnery.gd` | 9-11, 130 |
| `tests/integration/test_station_reinforcements.gd` | 10-11 |
| `tests/integration/test_station_death_sequence.gd` | 14-15, 283 |
| `tests/integration/test_station_laser_phase.gd` | 12-16, 111, 367 |

Step 6's doc list (`global.md`, `PROJECT.md`, `CLAUDE.md`) does not cover `assault.md` or the station
`ENEMY.md` either. Note also that several of these blocks are *justifications for real design
decisions* ("copied rather than read per volley") that stay correct for other reasons — they need
rewriting, not deletion, and the plan should say which reason survives. `3-plan.md:165` claims the
sites "are listed explicitly so the step cannot be half-done"; as listed, it will be.

---

## Non-blocking, fix while you are in there

- **D6 — the helper should live on `ShipConfig`, per your own context doc.** `1-context.md` says the
  helper "should be a plain function on `ShipConfig`, usable by the non-`BaseEnemy` `AllyFighter`";
  the plan instead pastes the same five lines into `base_enemy.gd` and `ally_fighter.gd`, including
  the subtle `resource_path.is_empty()` guard. One static `ShipConfig.privatise(node)` called from two
  `_enter_tree()`s is the same diff size, keeps the guard in one place, and matches
  composition-over-inheritance better. The third non-`BaseEnemy` entity will thank you.
- **D7 — one risk row is vacuous.** `3-plan.md:166` expects `test_project_load_integrity.gd` to catch a
  blank-`resource_path` regression. That file never adds anything to a tree
  (`test_project_load_integrity.gd:174-206` uses `can_instantiate()`, not `instantiate()` + `add_child`),
  so `_enter_tree()` never fires there and it cannot see this change at all. Drop the row or replace it
  with the real net: the new file plus `scripts/check-test-leaks.sh` (which exists, `scripts/check-test-leaks.sh`).
- **Scope.** Two ~5-line methods, one test file, ~12 comment blocks and 4 docs is a reasonable single
  session — *provided* D5's real file list is used for estimating rather than the plan's short one. If
  D1 is answered with the `_init()` + `_enter_tree()` combination the code delta grows by about three
  lines and nothing else changes.
- Nice touch worth keeping: test 3 (flatness) is a genuine early-warning invariant, and grounding the
  roster in the `DirAccess` sweep rather than a hand list is the right call — it is the gap
  `test_enemy_contact_damage.gd` still has.

---

## What approval needs

1. D1 answered — either the construction-time copy is added (preferred), or the prose and test 4 are
   corrected to state the pre-`add_child` window honestly.
2. D2 — test 6 redesigned as an identity check recorded from inside a child's `_ready()`.
3. D3 — step 1's expected red/green corrected for test 5, and the red pass pinned to `-gtest=` in
   isolation with the poisoning reason stated.
4. D4 — the `pack()` measurement recorded reproducibly (script + raw output + in-tree/out-of-tree
   status), or the row withdrawn and `_init()` re-evaluated.
5. D5 — step 5's file list replaced with the full table above, and step 6's doc list extended with
   `docs/architecture/modules/assault.md` and `assault/scenes/enemies/space_station/ENEMY.md`.

---

# Review round 2 — revision 2 of `3-plan.md`

VERDICT: APPROVED

All five blocking findings are answered, and answered with evidence rather than assertion. I did not
take the revision on trust: I applied the **exact patch the plan describes** to the three real files,
ran probes against the real `Gunship`/`SpaceStation`/`AllyFighter` classes, ran the full gate, and
then reverted. Everything the plan claims holds. Two residual windows and a handful of line-reference
imprecisions are worth fixing in passing, but none of them is worth a third round.

## Independent verification

I temporarily added `ShipConfig.privatise()` to `global/resources/ship_config.gd` and the two hooks to
`assault/scenes/enemies/base_enemy.gd:22-26` and
`assault/scenes/allies/ally_fighter/ally_fighter.gd:16-20`, exactly as written at `3-plan.md:56-70`.
Probe output, against the real classes (not the plan's stand-ins):

```
A) pre-add a.config private? true | is GunshipConfig: true | max_health: 200
B) shipped load().max_health after pre-add write = 200 (shipped 200)
B) later spawn reads 200
B) a.config != b.config -> true | a kept 13? 13
C) probe.recorded == s1.config -> true | recorded private? true
C) two stations' recorded objects differ -> true
C) gunnery core_ring_step=0.24 shipped=0.24
F) entities with config swept: 10 | failures: []
```

Then the gate, with the patch in place:

```
Scripts 38   Tests 332   Passing Tests 332   Asserts 1487   Time 18.272s
---- All tests passed! ----
LEAK CHECK PASS - suite green, nothing leaked
```

Files restored afterwards; `git status` shows no source modifications.

### (a) The `_init()` + `_enter_tree()` pair composes safely — confirmed

- **The base-class `_init()` really does see the subclass `@export`.** Row A: a real `Gunship`
  instantiated from `gunship.tscn` has a private, correctly-typed `GunshipConfig` carrying the
  shipped `max_health = 200` *before* `add_child`. The plan's stand-in probe
  (`probes/probe_init_ordering.gd`) reproduced with the production class hierarchy
  (`BaseEnemy extends CharacterBody2D`, `Gunship extends BaseEnemy`).
- **D1's window is closed.** Row B: the pre-`add_child` write of `13` left `load(gunship_config.tres)`
  at `200` and a later spawn at `200`, while the written instance kept its `13`. Compare round 1's
  measurement on the `_enter_tree()`-only design, where the same write left a later spawn reading `13`.
- **Idempotence holds across the pair.** The second call (from `_enter_tree`) is a no-op because
  `duplicate()` blanks `resource_path` — row B shows the instance kept its `13` rather than being
  re-copied from a fresh load.
- **The `_enter_tree()` half still earns its place.** `wave_manager.gd:177-181` and
  `station_reinforcements.gd:237-242` apply `initial_props` after construction and before
  `add_child`, so it is the only hook that can privatise a substituted override. Correctly argued at
  `3-plan.md:88-90`.
- **No collisions.** Re-confirmed: no `func _enter_tree` anywhere in `assault/ open_space/ global/
  infiltration/`, and `_init()` exists only on `wave_builder.gd:20`, `formation_resource.gd:14` and
  four `infiltration/scripts/player/runtime/*` helper classes — none an entity. No `@tool` script
  under `assault/` or `global/`. The 332/332 run also clears the one thing I could not settle by
  reading: adding `_init()` to a doubled base class does not upset GUT's doubler.
- **No balance drift.** Row C: the station's gunnery still copies `core_ring_step = 0.24` from the
  shipped `.tres`, and the whole suite — including `test_station_{gunnery,laser_phase,reinforcements,
  death_sequence}.gd`, `test_enemy_contact_damage.gd`, `test_contact_hitbox_geometry.gd`,
  `test_enemy_hurtbox_geometry.gd` — is green. Build step 5's expectation is empirically correct.

**Third windows — two exist, both unreachable today (N1, non-blocking).** The plan says the pair
closes "the window"; it closes both windows it names, but not quite all of them:

```
D) Node.duplicate(): c.config == d.config -> true
E) post-add assignment (entity.config = load(...)) leaves it shared: private? false
```

- `Node.duplicate()` on a live entity yields two nodes sharing **one private copy**: the new node's
  `_init()` privatises its default, `duplicate()` then overwrites the property with the source's
  copy, and `_enter_tree()` skips it because the path is already blank — the idempotence guard
  cannot tell "already private to *me*" from "already private to *someone else*".
- Assigning a shared resource to `config` after the node is in the tree fires neither hook.

Neither is reachable: `grep -rn "\.duplicate()"` over non-addon code returns **only** `addons/gut/`
hits (no `Node.duplicate()` in game code), and `grep -rn "\.config *="` finds no assignment site in
`assault/`, `global/`, `open_space/` or `infiltration/`. Please add one line to *Out of scope* or
*Risks* recording them, so the next reader does not infer a stronger guarantee than the design gives
— and so that the day someone adds `entity.duplicate()` to a spawner, the note is there.

### (b) The revised test 6 can genuinely fail — confirmed

`3-plan.md:228-236` is the right shape and row C proves it runs against the real
`space_station.tscn`. Its three assertions behave as a test must:

| Build | `recorded == station.config` | `recorded.resource_path.is_empty()` | two stations' recorded objects differ |
|---|---|---|---|
| Unmodified (today) | passes (both are the shared object) | **fails** | **fails** |
| Copy moved to `SpaceStation._ready()` | **fails** (child recorded the shared original) | **fails** | **fails** |
| As designed | passes | passes | passes |

So it is red on unmodified code as `3-plan.md:203` claims, *and* red on the `_ready()`-time design it
exists to reject — which is exactly what round 1's version could not do. The `ConfigProbe` naming
note at `3-plan.md:230-231` is correct: GUT collects inner classes only when they extend `GutTest`,
so a `Node` subclass is ignored regardless, and the explicit name choice is good defence anyway.

The rest of the test table is now accurate too. Test 5 gained the "config is private" assertion
(`3-plan.md:224`), which is what makes it genuinely red-first — round 1's version passed on the
broken build. And build step 1 (`3-plan.md:139-146`) now pins the red run to a single-file `-gtest=`
process **and states why**: tests 4, 5 and 6 write into the shipped object every other file's
`preload()`ed `const` holds alive. That was D3 and it is fully answered.

### (c) Step 6's table — complete at file granularity, imprecise at line granularity (N2, non-blocking)

Every file my round-1 sweep found is present, and the "what must the new text say" column is a real
improvement: it correctly separates the rows whose *claim* is now false (`space_station.gd:54`
"Never write to `station.config`") from the rows whose *decision survives with a different reason*
(the four station children copy their tuning because their own fields are the tunable surface the
tests use and hold the conservative fallback defaults — `3-plan.md:166`). That distinction is the
part a careless implementer would have got wrong, and it is spelled out.

A re-sweep on wider phrasings (`shares ONE`, `same object preload`, `never write to`,
`property-init time`) turned up **no thirteenth file**. It did turn up line ranges that stop short of
the block they point at:

- `assault/scenes/enemies/space_station/ENEMY.md` — cited as `656`; the full stale paragraph is
  **662-670** ("every `SpaceStation` in the process shares one `SpaceStationConfig`… the same object
  `preload()` hands a test"). 656 is only the passing back-reference to it.
- The four station children are cited by their first line or two; the comment blocks actually run
  `station_gunnery.gd:56-63`, `station_laser_phase.gd:52-58`, `station_reinforcements.gd:73-79`,
  `station_death_sequence.gd:84-90`. (Round 1's table had the same imprecision — this is a shared
  correction, not a new complaint.)
- `3-plan.md:32,155,248` say "twelve files"; the table has **thirteen** rows.

Rewrite whole blocks rather than the cited lines, and the step lands correctly either way.

### D4 and D7 — accepted

`probes/probe_pack_serialisation.gd` and `probes/README.md` reproduce my result exactly
(`et_v in_tree=true sub_resource=true`) and identify the earlier clean row as the out-of-tree case.
The withdrawal is recorded in the plan (`3-plan.md:125-130`), in the research addendum, and in the
probe README, and the editor-placeholder argument is explicitly labelled "reasoning, not a
measurement". That is the right way to retire a bad measurement. D7's replacement risk row
(`3-plan.md:249`) now states plainly that `test_project_load_integrity.gd` cannot see this change,
which is correct — `:174-206` uses `can_instantiate()` and never adds a node to a tree.

D6 is done: one `ShipConfig.privatise()` at `3-plan.md:56-59`, called from four two-line hooks, with
the subtle `resource_path.is_empty()` reasoning stated once.

## Conditions

None blocking. Fold N1 (the two residual windows, with the grep evidence that neither is reachable)
and N2 (the `ENEMY.md` line range, the four block ranges, and twelve-vs-thirteen) into the plan as
you implement — they are edits to `3-plan.md` prose, not to the design. Implementation may start.
