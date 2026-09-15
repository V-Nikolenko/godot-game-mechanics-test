# Review

## Round 1 — VERDICT: CHANGES_REQUESTED

1. **Coroutine leak, test case 4 of `test_lore_log_pickup.gd`**: called `_on_body_entered()` with
   the fixture catalogue non-empty, which reaches `_show_notification()` → `DialogPlayer.play()`
   — a leaked, permanently-suspended coroutine, the exact defect that blocked the sibling task
   twice. The plan's own claim of applying "option (b)" was inaccurate; it needed either dropping
   the `_on_body_entered()` call or pre-arming the `_show_notification()` guard.
2. **Same ambiguity in `test_hub_log_placement.gd` §5**: "exercise via `_on_body_entered`/
   `_collect`" implied the two were interchangeable for `LoreLogPickup`; they are not.
3. **`LoreLogBeaconStatic` at `(420, -212)`** would overlap `ShipShieldUpPickup` at
   `(413, -212)`'s collision circle almost completely.

Full reasoning: see the round-1 subagent transcript (not persisted verbatim; summarized here and
in the fixes below, which quote the relevant trace).

## Fixes applied

1. Case 4 now pre-sets `DialogPlayer.is_active = true` before calling `_on_body_entered()`, so
   `_show_notification()`'s guard (`if DialogPlayer.is_active: return`, first statement) skips
   before `play()` is ever referenced. Resets `DialogPlayer.is_active = false` in `after_each`.
2. §5 now states explicitly: the real-collect proof calls `_collect()` only, never
   `_on_body_entered()`.
3. `LoreLogBeaconStatic` moved to `(620, -212)`, clear of the row's actual rightmost occupant
   (`TemporaryDamageUpPickup` at `(519, -210)`) by a 101px gap against a ~50px combined-radius
   overlap threshold.

## Round 2 — VERDICT: APPROVED

Confirmed by tracing `pickup_base.gd::_show_notification()` directly: `DialogPlayer.is_active`
is checked as the very first statement, before any reference to `play()` — pre-arming it
guarantees `play()` is never called, not just made a no-op. Independently also confirmed
`DialogPlayer.play()` itself guards `is_active` before touching any coroutine-relevant state, so
the fix holds even if the guard were reached differently. The `after_each` reset was confirmed
sufficient since `DialogPlayer` is a single shared autoload with no other state this guard
touches. The `(620, -212)` placement was confirmed clear by measuring the actual `CircleShape2D`
scale in `weapon_mode_unlocker_pickup.tscn` (~24.9px effective radius) against the 101px gap to
the row's rightmost item. All other node placements (near `edelia`/`voeter_k05m`/
`fortuna_station`) were independently re-checked and found clear of every existing scene node.

No new issues found. Plan approved for implementation.
