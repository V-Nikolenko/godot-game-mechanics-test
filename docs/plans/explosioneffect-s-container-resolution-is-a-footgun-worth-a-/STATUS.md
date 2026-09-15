# STATUS — ExplosionEffect container resolution footgun

**Track:** Escalated (per routing: complexity medium, prepDir null) — resolved during context
gathering, no implementation stage needed.
**Task:** explosioneffect-s-container-resolution-is-a-footgun-worth-a- (epic: code-health-backlog)
**Started:** 2026-09-08

- [x] 1. Context gathered → `1-context.md`
- [x] 2. Finding: already resolved by commit `4126376`, part of the completed
      `explosioneffect-orphans-its-particles-onto-whatever-the-dying` task. Both remedies this
      backlog item proposed (explicit `container` override, loud warning on the remaining silent
      path) are shipped and covered by `tests/unit/test_explosion_effect.gd` and
      `tests/integration/test_explosion_effect_placement.gd`, both re-run green this cycle.
- [x] 3. No plan/review/implementation needed — see `1-context.md` for why a generic
      "ancestor-owned container" runtime check is not a meaningful check given the shipped design.

**Next action:** None — task closed as resolved by prior work.
