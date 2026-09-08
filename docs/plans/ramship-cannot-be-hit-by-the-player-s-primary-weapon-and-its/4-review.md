VERDICT: APPROVED

## Verification performed

I independently checked every load-bearing claim in `1-context.md` / `3-plan.md` against the
actual code rather than trusting the plan's citations.

1. **The mask mechanics are correctly described.**
   `global/components/hurtbox_component.gd:9-10` shows `HurtBox` connects its *own*
   `area_entered` signal — i.e. `HurtBox` is the monitoring `Area2D`, so it is `HurtBox`'s
   `collision_mask` (not the `HitBox`'s) that gates whether a hit is even detected.
   `assault/scenes/enemies/base_enemy.gd:47` sets `hurt_box.collision_mask = 97 | 1024` in
   `_ready()`; `assault/scenes/enemies/ram_ship/ram_ship.gd:19` runs after `super._ready()` and
   overwrites it to `33` (32 missile bit + 1). `assault/scenes/projectiles/bullets/bullet.tscn:44`
   confirms the player bullet's `HitBox.collision_layer = 64`, which is not in `33`. The plan's
   central factual claim — bullets cannot reach an armoured ram ship — is correct, not just
   asserted.

2. **The "intentional design" conclusion is evidence-based, not assumed.**
   - `assault/scenes/enemies/ram_ship/ENEMY.md` was last touched in commit `613ad48`
     ("harness: backlog, feature-workflow skill, automation notes", 2026-08-31), which predates
     this task/cycle (2026-09-08) — confirmed via `git log`. It is not a same-cycle rationalization
     written to justify the "no fix" call.
   - `bullet.gd:104` (`if parent.is_in_group("asteroids") or parent.is_in_group("ram_ships"):`)
     is a real, independent code path (piercing-sniper handling, keyed off group membership, not
     the hurtbox mask) that treats `ram_ships` as a deliberate obstacle exactly as the plan
     describes. Line numbers in the plan (100-107) are off by ~2 from the actual span (100-111
     with the check at 104) — trivial, not a blocker.
   - `ram_ship.gd`'s own comments ("first missile hit triggers damaged state instead of dealing
     damage", "Now vulnerable to bullets too") read as an authored two-phase design, matching the
     plan's third leg.
   Three independent, pre-existing signals agreeing is real evidence for the design call, not a
   rubber stamp.

3. **The `max_health` fix matches genuine, existing convention.**
   Confirmed byte-for-byte in `assault/scenes/enemies/bomber/bomber.gd:19-20` and
   `assault/scenes/enemies/light_assault_ship/light_assault_ship.gd:19-20`:
   `health.max_health = config.max_health` / `health.current_health = config.max_health` inside
   `if config:`. `ram_config.tres:8` does set `max_health = 999`, and `ram_ship.gd:16-17`'s
   `if config:` block currently only reads `movement_speed` — the dead-code claim is accurate.

4. **The "no-op on gameplay" claim holds up under an independent search, not just the plan's own
   grep.** I searched for anything that reads an enemy's `Health` node before `_ready()` runs
   (health bars, minimap, spawn-override code in `wave_manager.gd`) and found nothing outside
   `BaseEnemy`/the entity itself. `assault/scenes/gui/health_shield_bar.gd`,
   `global/components/low_health_smoke.gd`, and the ship-module files that touch `.max_health` are
   all player-side, not enemy-side. Enemy `_ready()` order (`_enter_tree` privatises config →
   `_ready()` applies it) is unchanged by this plan. The claim is correct.

5. **No conflict with the existing roster-sweep tests.** Checked
   `tests/integration/test_enemy_contact_damage.gd`, `test_contact_hitbox_geometry.gd`, and
   `test_enemy_hurtbox_geometry.gd`'s `ram_ship` entries — none of them assert on
   `max_health`/`current_health` or the hurtbox mask value, so applying `config.max_health` cannot
   regress them, consistent with the plan's claim.

6. **`docs/enemy-roster.md:127`** does say `**HP:** Medium` today, confirmed, and is the only ram
   entry that omits the armour gimmick already documented in `ENEMY.md`. Fixing it is in scope and
   correctly targeted.

7. **No CLAUDE.md convention violation.** Config-driven-enemy convention is followed (`.tres` wins,
   applied in `_ready()`, private copy via `ShipConfig.privatise()` untouched). No new signal, no
   per-frame print, no bullet-lifetime interaction — the parts of CLAUDE.md that most often trip up
   changes in this area (composition-over-inheritance, projectile ownership, signal arity) are all
   unaffected by this diff.

## Test plan assessment

- `test_applies_config_max_health_on_ready` is the one test in the set that actually fails against
  current code (`health.max_health` reads 100, the `Health` node's scene default, not 999) —
  verified this is true by reading `ram_ship.tscn`'s `Health` node (uses component defaults,
  `global/components/health_component.gd:13-14` = 100/100) and confirming `ram_ship.gd` never
  overwrites it today.
- The other three (mask-excludes-bullets, first-hit-strips-armour, second-hit-deals-damage) are
  explicitly characterization/regression pins, not fix-driven — correctly labeled as such in the
  plan rather than oversold as failing-before-fix.
- `test_second_hit_after_armour_stripped_deals_damage` is a genuine boundary case: it is the one
  assertion that would catch a future regression where `_on_received_damage` stopped
  short-circuiting correctly (e.g. an off-by-one in the `_damaged` flag flip), which none of the
  other three tests would catch.

## Minor, non-blocking notes

- Plan's citation of `bullet.gd:100-107` for the `ram_ships` group check is slightly off (the
  actual `if` is at line 104, block runs to ~109); doesn't affect the finding's validity.
- The proposed `docs/enemy-roster.md` HP replacement is a full sentence, more verbose than
  neighboring entries' short qualitative labels (e.g. `**HP:** High (200)`) — a style nit, not a
  correctness problem, and arguably justified given this is the one enemy with a two-phase HP
  mechanic worth spelling out.
- Placing the new test at `tests/unit/test_ram_ship.gd` vs `tests/integration/` is a judgment call
  the plan itself leaves open; both directories have precedent for single-entity behavioural
  tests, so this isn't a defect either way.

## Conclusion

The plan resolves the filed design call with real, independently-verified evidence (not
assertion), correctly identifies the dead-code fix and matches it to a real, verified project
convention, correctly scopes out the mask change, and its test plan contains at least one real
failing-pre-fix test and one meaningful boundary case. No CLAUDE.md convention is violated. No
missing scope item was found — the "applied or deleted" choice is deliberated and justified rather
than defaulted. Approved as written.
