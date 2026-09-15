VERDICT: APPROVED

## What was checked against the actual code (not just the plan's claims)

- `global/resources/ship_config.gd:40-43` — current `privatise(node: Object)` hard-codes
  `"config"` and `is ShipConfig`. The plan's widened signature
  `privatise(node: Object, property: String = "config")` with `is Resource` in place of
  `is ShipConfig` is a strict behavioural superset for both existing callers, confirmed below.

- `assault/scenes/enemies/base_enemy.gd:41,45` and
  `assault/scenes/allies/ally_fighter/ally_fighter.gd:22,26` both call `ShipConfig.privatise(self)`
  with no second argument — the new default parameter reproduces this exactly. No call site needs
  to change. The signature-widening risk the plan calls out is real but correctly mitigated.

- `assault/scenes/systems/score_tracker/score_tracker.gd:26,50-53` — matches the plan's
  description exactly: `@export var score_config: ScoreConfig = preload(...)`, and `_ready()`
  re-preloads only on `null`, so a scene override or the shared default both flow through
  untouched into the first real read (`_survival_remaining = score_config.survival_interval`,
  the exact insertion point the plan targets).

- `global/resources/score_config.gd` — nine `@export` fields, all `float`/`int`, none nested. The
  shallow-`duplicate()` precondition is genuinely met; the plan's claim is correct and its decision
  not to add a parallel flatness sweep for a single resource class is proportionate.

- `tests/integration/test_config_instance_isolation.gd` — read in full. `test_writing_to_one_entitys_config_cannot_reach_another`
  (`:229-262`) is the shape the plan proposes to mirror for `ScoreTracker`; the file's harness idiom
  (throwaway `Node2D` container, `add_child_autofree`) is compatible with `ScoreTracker`, which
  is a plain `Node`, not a `Node2D`-requiring entity — `test_score_tracker_escape_penalty.gd:20-23`
  already proves the simpler `ScoreTracker.new()` + `add_child_autofree` idiom works standalone, and
  the plan cites that file correctly as precedent.

- Traced the actual construction order for the proposed new test: both `ScoreTracker` instances'
  `@export` default evaluates to the SAME cached object at construction; `_ready()` fires on
  `add_child_autofree` and privatises each independently (first instance duplicates the shared
  original into a private copy with a blank `resource_path`; the second instance's default is still
  the untouched original, which still has a non-blank path, so it also privatises into a second,
  distinct copy). The proposed assertions (distinct objects, shipped `.tres` untouched, blank
  `resource_path`) will genuinely fail on today's code and genuinely pass after the fix — this is
  not a vacuous test.

- Exclusion claims for attack/movement/formation/wave/level resources, verified independently
  rather than trusted:
  - `grep -rn "@export.*= (pre)?load(" global/resources/` returns nothing outside
    `ship_config.gd`'s own doc-comment text (matched as a string, not code) — confirms no sibling
    `@export var x = preload(...)` pattern exists in `attack/`, `movement/`, `formation/`,
    `waves/`, `levels/`, or `skill_challenge_resource.gd`.
  - `global/resources/attack/attack_pattern_resource.gd:1-5` — doc comment states patterns are
    "pure data... Runtime state lives in AttackController, so multiple ships can safely share the
    same .tres asset," directly supporting the task body's `station_gunnery.gd:79` citation.
  - Confirmed `.new()` construction at `interceptor.gd:36`, `ally_fighter.gd:40`,
    `light_assault_ship.gd:39`, and `station_gunnery.gd:123-124` — every live attack-pattern
    instance is per-entity-constructed, never a shared preloaded default.
  - No existing `Privatiser`/`privatize` utility elsewhere in the codebase (`grep -rl` over
    `global/`, `assault/`, `tests/` finds only the six files already using `ShipConfig.privatise`
    plus this plan's own docs) — the plan is not reinventing something that already exists, and
    correctly rejects inventing a new `ResourcePrivatiser` class in favor of widening in place.

## Assessment against the review criteria

- Solves the stated problem: yes — closes the exact caching hazard described, using the same
  mechanism already proven for entity configs.
- No reinvention: confirmed, only one privatisation helper exists in the codebase.
- No CLAUDE.md convention violated: composition/config-driven patterns unaffected; no signal
  changes; attack-pattern "pure configuration" convention explicitly respected and left alone.
- Test plan can actually fail and isn't vacuous: verified by tracing construction/`_ready()` order
  above.
- No simpler unexamined alternative: the two alternatives considered (new util class, `_init()`
  hook) are reasonably dismissed with concrete evidence (no real pre-`add_child()` write window for
  `score_config`, unlike the entity case).
- Signature widening doesn't break existing callers: confirmed by reading both call sites.
- Exclusion claims for attack/movement/formation/wave/level resources hold up under independent
  grep and read, not just the plan's assertion.

No changes requested.
