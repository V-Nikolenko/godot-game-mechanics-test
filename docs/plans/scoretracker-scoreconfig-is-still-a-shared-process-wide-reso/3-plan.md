# ScoreTracker.score_config privatisation

## Problem

`ScoreTracker.score_config` (`assault/scenes/systems/score_tracker/score_tracker.gd:26`) is
declared `@export var score_config: ScoreConfig = preload("res://global/resources/score_config_default.tres")`,
and `_ready()` (`:52`) re-`preload()`s the same path as a null fallback. `ResourceLoader` caches by
path, so every `ScoreTracker` that never gets an explicit override in its scene, and every test
that `preload()`s `score_config_default.tres` directly, holds the exact same `ScoreConfig` object.

There is only one `ScoreTracker` per level, so this is not today's `test_config_instance_isolation.gd`
bug (many *simultaneous* entities sharing one config). It is the same defect in a smaller blast
radius: a test (or future code) that mutates `tracker.score_config.combo_step` to exercise a
specific scoring case silently rewrites the shipped balance data in memory for the rest of the test
run, and any other test that reads `score_config_default.tres` afterwards — in the same file or a
different one — sees the mutated value with no visible cause. This is exactly the failure mode
`ShipConfig.privatise()` already exists to close for entity configs; `ScoreConfig` was out of scope
for that fix only because it isn't a `ShipConfig` subclass and `ScoreTracker` isn't swept by
`test_config_instance_isolation.gd`'s entity-directory walk.

Player-facing impact: none directly. This is a correctness invariant for the test suite and any
future runtime code that tunes `score_config` per level — it prevents a class of flaky,
hard-to-diagnose test failure, the same class the entity-config fix already prevents.

## Design

**Widen `ShipConfig.privatise()` to take the property name, and genericize its type check from
`ShipConfig` to `Resource`.**

```gdscript
## global/resources/ship_config.gd

## Replace `node`'s `property`-named Resource property with a copy private to that node, if it
## still holds the shared, process-wide resource `ResourceLoader` caches.
## ... (existing doc comment, generalized: "Resource" instead of "ShipConfig", "the named
## property" instead of "config") ...
static func privatise(node: Object, property: String = "config") -> void:
	var res: Variant = node.get(property)
	if res is Resource and not (res as Resource).resource_path.is_empty():
		node.set(property, (res as Resource).duplicate())
```

Then in `score_tracker.gd`:

```gdscript
func _ready() -> void:
	if score_config == null:
		score_config = preload("res://global/resources/score_config_default.tres")
	ShipConfig.privatise(self, "score_config")
	_survival_remaining = score_config.survival_interval
```

### Alternatives considered

- **Move the helper off `ShipConfig` onto a new small util class** (e.g. `ResourcePrivatiser`),
  as the task body floats as an option. Rejected: `ShipConfig.privatise()` is referenced by name in
  ~15 comments across `base_enemy.gd`, `ally_fighter.gd`, the space-station family, and
  `test_config_instance_isolation.gd`'s own header. Renaming forces churn across all of them for no
  behavioural gain — the method's *logic* was never actually `ShipConfig`-specific (it only checked
  `is ShipConfig` because that was the only caller), and genericizing in place costs one line
  changed at each of the two call sites that matter (the type check, and the new default arg) with
  zero call-site changes for existing callers. If a third, unrelated resource type needs this
  later, moving it then — with two real callers motivating the new name — is cheaper than
  speculatively renaming now for one.
- **Call `privatise()` from a hypothetical `ScoreTracker._init()`** to mirror `BaseEnemy`'s
  `_init()` + `_enter_tree()` double-hook. Rejected: that double-hook exists because entities can
  have their `config` written between `instantiate()` and `add_child()` (`WaveManager`'s
  `initial_props`) or have `config` itself replaced by a scene override that only resolves at
  `_enter_tree()`, and because other nodes' `_ready()` (children) read `station.config` before the
  station's own `_ready()` runs. None of these windows exist for `score_config`: nothing constructs
  a `ScoreTracker` and writes `score_config` before `add_child()`, nothing overrides it via spawn
  props, and nothing reads another node's `score_config` from its own `_ready()`. A single call in
  `ScoreTracker._ready()`, after the null-fallback re-preload and before `score_config` is first
  read, closes every real window. Documented as a deliberate narrower fix, not an oversight.
- **Deep-copy instead of shallow `duplicate()`.** Unnecessary: `ScoreConfig` (`global/resources/score_config.gd`)
  has ten fields, all `int`/`float`, no nested `Object`/`Array`/`Dictionary` — a shallow copy is
  complete. No change needed to the copy mechanism itself.

### Resources deliberately left shared (per the task body's ask to check them)

Checked and confirmed no privatisation is needed:

- **Attack patterns** (`global/resources/attack/*.gd`) — `station_gunnery.gd:79-81` states runtime
  state must live off the pattern resource, "requires those to stay pure configuration." Every
  live construction site (`light_assault_ship.gd:37`, `interceptor.gd:37-40`, `ally_fighter.gd:41-43`,
  `station_gunnery.gd`) already builds its pattern with `SomePattern.new()` per entity — never a
  shared `preload()` default — so there is no sharing hazard to begin with.
- **Movement / formation / wave / level resources** (`global/resources/{movement,formation,waves,levels}/*.gd`) —
  grepped every runtime write to a property on these types
  (`movement.speed =`, `w.trigger_time =`, `res.clean_bonus =`, etc.). Every write target is either
  a freshly `.new()`-constructed resource (`level_1_director.gd:133-134`, `wave_builder.gd:213`,
  `level_1_director.gd:177/185`) or authoring data built once at wave-build time and never shared
  across owners. None of them are declared `@export var x: T = preload(...)` the way `config` and
  `score_config` are, so none have the caching hazard this fix addresses.
- **`SkillChallengeResource`** (`global/resources/skill_challenge_resource.gd`) — designer-authored
  data placed in a `LevelSection.skill_challenges` array, read by `Level1Director`, never a shared
  `preload()`-default `@export` on a live node. Same reasoning as above — out of scope.

## Build sequence

1. **Failing test first.** Add `test_writing_to_one_trackers_score_config_cannot_reach_another` to
   `tests/integration/test_config_instance_isolation.gd` (new section, after the existing 6):
   spawn two `ScoreTracker` nodes (`ScoreTracker.new()`, `add_child_autofree`, matching the idiom
   `test_score_tracker_escape_penalty.gd` already uses), write to one's
   `score_config.combo_step`, assert the other tracker's `score_config.combo_step` and a fresh
   `load("res://global/resources/score_config_default.tres")` are both untouched, and assert
   `score_config.resource_path.is_empty()` (private-copy marker). Run it — confirm it fails against
   today's code (single shared object ⇒ the write IS visible everywhere).
2. Widen `ShipConfig.privatise()` in `global/resources/ship_config.gd` as designed above. Update
   its doc comment to describe the general `Resource`/named-property behaviour instead of hard-coding
   "`config`"/"`ShipConfig`" (the doc comment currently reads "every entity of a type" and similar —
   generalize the language, keep the entity-specific parts of the explanation since that's still
   the primary use, note `score_config` as the second use).
3. Call `ShipConfig.privatise(self, "score_config")` in `ScoreTracker._ready()`, after the
   null-fallback re-preload, before `_survival_remaining = score_config.survival_interval` reads it.
4. Run the new test — confirm it passes. Run the full `test_config_instance_isolation.gd` file —
   confirm the existing six entity-config tests are unaffected (the signature change is
   backward-compatible: `property` defaults to `"config"`).
5. Run `tests/integration/test_score_tracker_escape_penalty.gd` — confirm unaffected (it never
   reads/writes `score_config`).
6. Full gate: `bash /agent/verify.sh`.

## Test plan

- **New:** `test_writing_to_one_trackers_score_config_cannot_reach_another` in
  `test_config_instance_isolation.gd` — the defect stated directly, mirroring the file's existing
  `test_writing_to_one_entitys_config_cannot_reach_another` shape:
  - two live `ScoreTracker`s, write `a.score_config.combo_step = <sentinel>`
  - `b.score_config.combo_step` unchanged
  - `load("res://global/resources/score_config_default.tres").combo_step` unchanged (proves the
    shipped `.tres` wasn't rewritten in memory)
  - a third `ScoreTracker` spawned *after* the write does not inherit the poisoned value
  - **Boundary case:** `a.score_config.resource_path.is_empty()` is true (private-copy marker),
    proving it's actually a copy and not coincidentally-equal values.
- No new test needed for the `ShipConfig.privatise()` signature widening itself — the existing six
  tests in `test_config_instance_isolation.gd` exercise the default-argument path unchanged and
  will catch any regression there.

## Risks

- **Widening a heavily-referenced static method's signature.** Mitigated: new parameter has a
  default that reproduces the exact old behaviour (`property = "config"`, and `is Resource` is a
  strict superset of `is ShipConfig` for every existing caller, since every existing caller's
  `config` field is already typed as a `ShipConfig` subclass — the widened check accepts the same
  values it always did, for those call sites).
- **Doc-comment drift.** `ShipConfig.privatise()`'s doc comment is quoted/paraphrased by name in
  several other files' comments. Not rewriting those — the *behavior* they describe doesn't change
  for the entity-config case, so no comment referring to that case becomes inaccurate. Only
  `ship_config.gd`'s own doc comment needs an update, to stop implying `ShipConfig`-only scope.

## Out of scope

- Any privatisation for attack/movement/formation/wave/level resources — checked and confirmed
  correctly shared per `station_gunnery.gd:79-81`'s "pure configuration" convention (see Design).
- Adding a `test_configs_are_flat_so_a_shallow_copy_is_complete`-style sweep for `ScoreConfig`.
  There is exactly one such resource class and one such call site; a full directory-sweep-based
  flatness invariant (as exists for the ten `ShipConfig` subclasses) is disproportionate. The new
  isolation test itself would fail if `ScoreConfig` ever grew a nested `Object`/`Array`/`Dictionary`
  field and someone relied on the shallow copy carrying it — acceptable per the task's "cheapest
  fix" framing.
