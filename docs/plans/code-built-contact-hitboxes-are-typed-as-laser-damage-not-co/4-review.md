# Review: contact hitboxes typed CONTACT, not LASER

VERDICT: APPROVED

## Findings

**Problem match.** The task body's claim is verified against live code, not just the plan's
paraphrase:
- `global/components/hitbox_component.gd:7` — `damage_type: DamageType = DamageType.LASER`.
- `global/components/hitbox_component.gd:20-29` — `matching_shape()` sets `collision_layer`,
  `collision_mask`, `damage`, but never `damage_type`.
- The 4 call sites confirmed by `grep -rn "matching_shape(" --include=*.gd .`: `base_enemy.gd:79`,
  `drone_interceptor.gd:146`, `kamikaze_drone.gd:58`, `ally_fighter.gd:95`. No 5th call site
  exists anywhere in the project.
- `asteroid_base.gd:41-42` sets `contact_hit_box.damage_type = HitBox.DamageType.CONTACT`
  explicitly on a scene-authored `$ContactHitBox`, confirming `CONTACT` is the intended type for
  ram damage elsewhere in the codebase — matches the plan's framing exactly.

**Design matches CLAUDE.md conventions.** The fix lives in the shared component
(`global/components/`), not duplicated across 4 call sites — consistent with "composition over
inheritance / shared component" and the project's stated preference (see the rejected-alternative
section, which is reasoned, not hand-waved). No signal involved, so signal-arity convention is
N/A. No enum member added or reordered, so the "`DamageType` ordinals are serialised, never
reorder" constraint is respected — `tests/unit/test_hitbox_hurtbox.gd:31-36`
(`test_damage_type_enum_is_stable`) is untouched and still pins `LASER=0, ROCKET=1, CONTACT=2`,
matching the enum at `hitbox_component.gd:4`.

**No reinvention.** `matching_shape()` is the single existing factory for code-built contact
hitboxes; the plan extends its signature rather than adding a parallel helper or a second
call-site pattern.

**Independently re-verified: nothing currently filters on LASER in a way this change would
break.**
- `grep -rn "accepted_damage_types" --include=*.gd --include=*.tscn .` — exactly 3 non-default
  sites: `big_asteroid.tscn:39`, `race_wall.tscn:26`, `race_asteroid.tscn:30`, all
  `Array[int]([1])` = ROCKET-only. These are hazard `HurtBox`es hit by player missiles, never by
  an enemy/ally ram `HitBox` — unaffected either way.
- `assault/scenes/player/player_fighter.tscn:334-336` — the player's `HurtBox` (`collision_layer
  = 128`, `collision_mask = 1281`) has no `accepted_damage_types` override in the scene file, so
  the script default `[]` (accept-all, `hurtbox_component.gd:7`) applies. This is the box every
  one of the 4 `matching_shape()` outputs is built to hit. Confirmed directly, not taken on the
  plan's word.
- No enemy or ally `HurtBox` in the project sets `accepted_damage_types` either (same grep, full
  results shown above — the only other hits are the component source itself and the unit test's
  own fixture helper).
- Conclusion holds: retyping the 4 call sites' output from LASER to CONTACT changes no
  currently-observable behaviour.

**Test plan can actually fail, and meaningfully.** All 4 call sites currently produce
`damage_type == LASER` (0); the new assertion checks for `CONTACT` (2), so it fails pre-fix and
passes post-fix — verified by reading the call sites directly rather than trusting the plan's
count. The roster reuse (`tests/integration/test_contact_hitbox_geometry.gd`'s existing `ROSTER`,
`_spawn()`, `_contact_hitbox()`) is exact — read the file in full and confirmed the 11-entry
roster with `bonus_drone` as the single `no_hitbox` exception, matching the plan's "10 entities"
count. The boundary case (kamikaze_drone/drone_interceptor pass a non-default `mask=128` before
the new trailing optional `dmg_type`) is real coverage of positional-argument ordering, not
padding. `test_hitbox_hurtbox.gd::test_hitbox_defaults()` (`hb.damage_type ==
HitBox.DamageType.LASER` for a bare `HitBox.new()`) is correctly left alone — it exercises the
constructor, not `matching_shape()`, and the plan does not touch the constructor default.

**No simpler alternative overlooked.** The plan considers and rejects the one real alternative
(explicit `damage_type = CONTACT` at all 4 call sites) with a concrete argument: a default on the
factory closes the hole for a 5th future caller, 4 repeated call-site edits don't. This is correct
and is the simpler design, not the more complex one — a single-line change to one function beats
four.

## Minor, non-blocking observation

`docs/architecture/modules/global.md:123` documents `matching_shape()`'s signature as
`(source: CollisionShape2D, layer, mask, dmg) -> HitBox` and line 143 shows a call-site example
with the comment `# layer, mask, damage`. The plan doesn't mention touching this doc. The
addition is a backward-compatible optional trailing parameter, so the doc isn't wrong, just
incomplete — worth a one-line addition when implementing, but this is a signature tweak to an
existing helper (not adding/renaming/moving/deleting an entity, component, module, or mechanic),
so it doesn't meet CLAUDE.md's mandatory-docs-update threshold and isn't grounds to request
changes.

## Summary

The plan solves exactly the bug described, reuses the existing factory and existing test harness
rather than inventing new mechanism, respects the enum-stability and shared-component
conventions, and its independent-verification claim (nothing filters on LASER today) checks out
against a from-scratch grep, not just the plan's own. The test can fail today and is tied to real
call sites. No missing edge case, no reinvention, no simpler alternative unexamined.
