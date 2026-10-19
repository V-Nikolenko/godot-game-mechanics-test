# The Support Ship picks, follows and re-picks its ward (epic t11)

The design is the epic's approved plan (`docs/plans/cmufs7elw001pnm2xr3b6fteb/3-plan.md` §2.12, with §2.5 for the view
rect, §2.4 for `is_ai_driven()`, §4.1 / §4.3 for the tests). This file pins only the build choices §2.12 leaves open, the
build order and the test layout. Nothing below changes a name, number or rule of the epic plan.

## Problem

After t10 a Support Ship parks at `follow_distance` from whichever ally is nearest — a lone Swarm Drone, a legacy
Gunship, a Bonus Drone — on whatever side it happened to arrive, ignores the player entirely, and in Assault can sit
anywhere in the 1480 px corridor, including ~380 px above the visible screen. The player should meet a ship that
attaches itself to the most dangerous ally on screen, hangs back behind it (on the side away from the player), weaves
and slips away when the player comes for it, never chases the player, switches to another ally the tick its ward dies,
and in Assault is always where the player can see it — and supports nothing while it is not.

## Design

All in `assault/scenes/enemies/support_ship/support_ship_brain.gd` (requests only). No new config field, no scene change.

### Public surface added to `SupportShipBrain`

| Name | Meaning |
|---|---|
| `signal ward_changed(new_ward: Node)` | Emitted by `_set_ward()` on every change; `null` when the ward is lost/dropped. |
| `ward: BaseEnemy` | Kept (t10 name). Always read through `has_ward()` (`is_instance_valid`); written only by `_set_ward()` (a t10 test assigns it directly, which stays legal: `_set_ward(null)` tolerates a ward it never claimed). |
| `ward_score: float` | The current ward's threat score, refreshed every tick. |
| `ward_held_for: float` | Seconds since the current ward was selected (reset on every `_set_ward`). |
| `wards_selected: int` | Count of non-null selections. |
| `anchor: Vector2` | The FOLLOW target this tick (after the Assault clamp); `Vector2.INF` when there is none. |
| `follow_side: float` | ±1, drawn from `rng` at each selection (the `perp × side` of the anchor, and the evasion side). |
| `is_supporting() -> bool` | §2.12 verbatim: ward valid, within `beam_range`; with a view rect, the support inside `view.grow(view_band)` and the ward inside `view.grow(ward_view_band)`. |
| `threat_score(e: BaseEnemy) -> float` | `score_value × 1 / (1 + d_player / 600) × (1 + (1 − hp_fraction))`; `d_player` = 0 with no player; `hp_fraction` = current / max (1 if max ≤ 0). Public so tests compare scores directly. |
| `is_candidate(e: BaseEnemy) -> bool` | The §2.12 filter, in its order. |
| `best_candidate() -> BaseEnemy` | Highest `threat_score` among candidates, or null. Ties keep scan order. |
| `const CLAIM_META := &"support_claim"` | The claim meta key. |
| `const THREAT_DISTANCE_SCALE := 600.0` | The 600 of the score. |

### Ward lifecycle — one writer, `_set_ward(new_ward)`

1. If the old ward is valid: disconnect our handler **only if `ward.tree_exiting.is_connected(_ward_exit_cb)`** (the
   exact bound `Callable` is stored in `_ward_exit_cb` when connecting — a ward assigned directly, as a t10 test does,
   was never connected, and an unguarded disconnect logs an engine error that fails the test), and remove `CLAIM_META`
   **only if it holds our actor's instance id**.
2. Store the new ward; reset `ward_held_for`; if non-null: set its `CLAIM_META` to `actor.get_instance_id()`, connect
   `tree_exiting` to `_ward_exit_cb = _on_ward_tree_exiting.bind(new_ward)`, draw `follow_side` and the jink sign,
   `wards_selected += 1`, refresh `ward_score`.
3. Emit `ward_changed(new_ward)` if it changed. So a loss followed by a re-pick emits `null`, then the new ward.

Called with null from: `tree_exiting` handler, tick validation, `on_suspended()`, `_enter_disengage()`, and `_exit_tree()`.
A claim is "another live support's" when the meta is set, differs from our id, and `instance_from_id(id)` is non-null.

### Per tick (`tick`)

1. `_start()` on first tick; `_phase_time`; budget expiry → DISENGAGE (unchanged, t10). DISENGAGE ticks as in t10 and
   returns — no ward logic in DISENGAGE.
2. **Validate:** if the ward is set but `not _ward_still_valid()` (invalid instance, queued, health ≤ 0, not
   `is_ai_driven()`, beyond `ward_keep_radius`, or with a view rect outside `view.grow(ward_view_band)`) → `_set_ward(null)`.
3. **Select:** no ward → `_set_ward(best_candidate())`. Ward held ≥ `min_ward_seconds` → if `best_candidate()` is another
   enemy scoring ≥ `ward_switch_margin × ward_score`, switch. (`ward_score` refreshed before the comparison.)
   A ward lost through `tree_exiting` is therefore replaced on the next tick; one lost through validation is replaced on
   the same tick that sees the loss, which is the first tick after it happened — both are "the next tick" of §2.12.
4. **Phase:** ward → FOLLOW (enter if not already); none → SEEK_WARD. `ward_held_for += delta` while a ward is held.
5. **Grace (Assault only, `budget.active`):** `_no_ward_time` accumulates while there is no ward **and the support itself
   is inside `view.grow(view_band)`**; it resets to 0 whenever a ward is held. At ≥ `no_ward_grace` → DISENGAGE. Open
   Space: no grace. (Review finding 5: supports and their allies spawn above the screen, and allies are no candidates
   until inside `view.grow(ward_view_band)`; a clock from spawn would send a support home before its allies arrive. The
   SEEK_WARD hold point is clamped into the view, so a support with no ward always comes into view and the clock always
   starts; the budget stays the backstop. Logged in DECISIONS.md for t17.)
6. Run the phase's motion.

### FOLLOW motion

Request = **one** `mover.request_velocity(seek + jink + evade)`; the mover caps the sum at `max_speed`. Computed in the
brain with `Steering` so the three terms can be weighed (review finding 1-2: a full-speed `arrive` cancels a 60 px/s
jink and a 240 px/s evasion nudge to a few px, so neither would be visible or testable).

- **Anchor:** `away = (ward − player).normalized()`, `anchor = ward + away × follow_distance + away.orthogonal() ×
  follow_lateral × follow_side`. No player (or player on the ward): `away` = the ward→support direction, else
  `Vector2.UP`. With a view rect: clamped component-wise into `view.grow(−view_margin)`. Stored in `anchor`.
- **Soft seek:** `seek = Steering.arrive(pos, vel, anchor, min(max_speed, d_anchor × FOLLOW_GAIN), decel)` with
  `const FOLLOW_GAIN := 2.0` (1/s; judgement) and `decel` = the mover's `braking`, else `acceleration`. Far from the
  anchor this is the full-speed `arrive` §2.12 names; near it, a spring, so the anchor is *soft* (R5.19).
- **Jink:** `jink = away.orthogonal() × jink_sign × jink_strength`; `jink_sign` (±1) is redrawn from `rng` every
  `jink_period` of accumulated delta (the config's "sideways dodge ... and the period of its reversal"). Against the
  spring this sways the ship ≈ ±20–30 px across the ward line — inside the 60 px anchor row.
- **Evasion (player within `evade_radius`, distance `d_p`):** `w = clamp((d_p − 0.8 × evade_radius) / (0.2 ×
  evade_radius), 0, 1)`; `seek` and `jink` are scaled by `w`; any component of `seek + jink` pointing at the player is
  removed (never pursue); `evade = Steering.break_contact(pos, player, player_vel, follow_side, evade_speed, EVADE_LATERAL_WEIGHT)` added in full,
  with `const EVADE_LATERAL_WEIGHT := 0.3` (round 2: the default 0.6, doubled for a closing threat, leaves ≈ 154 px/s of
  radial escape — slower than a 200 px/s player; 0.3 doubled to 0.6 leaves ≈ 206 px/s). Logged in DECISIONS.md.
  So from `evade_radius` inward the anchor gives way, and from 0.8 × `evade_radius` only the escape steers.
- `mover.face_toward(ward)`.

### SEEK_WARD motion

t10's hold near `nearest_ally()` (or stand still), with these changes: the nearest ally is held in a **local**, never
assigned to `ward` (t10's `ward = nearest_ally()`, `support_ship_brain.gd:99`, goes — `ward` is written only by
`_set_ward()`); with a view rect the hold point is clamped into `view.grow(−view_margin)`, and with no ally at all the
hold point is the support's own position clamped the same way (so a support above the screen comes into view). Open
Space with no ally: stand still, as t10.

### `on_suspended()` / `_exit_tree()` / DISENGAGE

`_set_ward(null)` (releases the claim) in all three; `on_suspended()` still folds the projector.

## Build sequence

0. `scripts/gate-time.sh` before (done on a clean copy of HEAD: GUT 184.7 s, 1731 tests).
1. Tests (new rows below) in `tests/integration/test_support_ship.gd`; re-point the t10 rows the grace changes; watch them fail.
2. Ward lifecycle, filter, score, selection, validation, `ward_changed`, claims.
3. FOLLOW motion, jink, evasion, facing; SEEK_WARD clamp; grace; `is_supporting()`.
4. Re-point `test_enemy_dual_mode.gd`'s support case; ENEMY.md / docs; a "t11 as built" entry in
   `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md` (`_set_ward` as the one writer, `ward_changed` order null → new,
   `ward_held_for`, `anchor == Vector2.INF` with no ward, the claim meta, the grace start, `FOLLOW_GAIN` and the evasion
   blend); gate-time after; leak check; verify.

## Test plan (`tests/integration/test_support_ship.gd`, hand-ticked; candidates are still — physics off)

Candidates are the real scenes where §2.12 names them (fighter, bomber, swarm drone, gunship, bonus drone); otherwise a
`fixture_enemy.tscn` with `score_value` set by the test (AI-driven, 10 HP).

Selection (dual-mode unless marked):
- `test_picks_the_bomber_over_the_fighter` — real fighter and bomber at equal distance from support and player.
- `test_a_badly_damaged_fighter_near_the_player_beats_a_healthy_one_far_away` — 20 % HP at 100 px from the player vs
  full HP at 800 px; asserts its `threat_score` is higher too.
- `test_never_another_support` — another `SupportShip` (score 60) as the only enemy → no ward.
- `test_never_a_rail_suspended_enemy` — a bomber after `suspend_ai()` beside a fighter → the fighter.
- `test_skips_a_ward_claimed_by_another_live_support` — two supports, one bomber + one fighter: the first takes the
  bomber, the second the fighter; a stale claim (an id whose object was freed) counts as free (boundary).
- `test_a_lone_swarm_drone_is_no_ward` — real swarm drone (10) → no ward (SEEK_WARD holds near it).
- `test_gunship_and_bonus_drone_beside_a_fighter_choose_the_fighter` — real `gunship.tscn` + `bonus_drone.tscn` + fighter
  → fighter; plus asserts both have the higher raw `score_value`, so it fails if the filter falls back to it.
- `test_a_non_combatant_is_never_a_ward` — an AI-driven fixture with `score_value = 500` and
  `counts_toward_wave_clear = false` beside a fighter → the fighter (the Bonus Drone has no brain, so the row above
  cannot fail on this clause alone; review finding 3).
- `test_ward_search_radius_boundary` (Open Space) — a lone fixture (25) at 890 px is selected, at 910 px it is not.

Stability (Open Space and Assault):
- `test_a_1_2x_challenger_does_not_take_over` — ward fixture 50, challenger 60 added after selection, 4 s → no switch.
- `test_a_1_4x_challenger_takes_over_only_after_min_ward_seconds` — challenger 70 added at once: no switch before
  `ward_held_for` reaches 2.0 s, switch within one tick after.

Retarget (dual-mode):
- `test_freeing_the_ward_selects_a_new_one_on_the_next_tick` — `free()`: `ward_changed(null)` at once, then the next tick
  `ward_changed(other)`.
- `test_killing_the_ward_through_health_selects_a_new_one_on_the_next_tick` — `health.decrease(max)`.
- `test_suspending_the_ward_selects_a_new_one_on_the_next_tick`.
- `test_with_no_other_candidate_open_space_seeks` (Open Space: `ward == null`, SEEK_WARD after 3 s) /
  `test_with_no_other_candidate_assault_disengages_after_the_grace` (Assault, support spawned in view: SEEK_WARD at
  1.4 s, DISENGAGE by 1.6 s).
- `test_assault_grace_starts_only_once_the_support_is_in_view` — spawned at y −200 with no candidate: it comes into view
  (clamped hold point), and DISENGAGE comes no earlier than `no_ward_grace` after the first tick it was inside
  `view.grow(view_band)`, and no later than one tick past that.
- `test_a_ward_beyond_keep_radius_is_dropped` (Open Space, boundary 1090 kept / 1110 dropped).
- `test_claim_is_released_on_switch_and_on_exit` — meta present while held, gone after a switch and after the support is
  freed.
- `test_suspending_a_support_whose_ward_was_assigned_directly_logs_no_error` is already the t10 suspend row
  (`brain.ward = ally; ship.suspend_ai()`); it stays and guards finding 4.

Follow (dual-mode; fixed `rng_seed` on the brain):
- `test_sits_within_60_px_of_the_anchor_behind_the_ward` — ward (640, 360), player still at (640, 760); after 4 s,
  within 60 px of `anchor`, and the anchor is on the far side of the ward from the player (`(anchor − ward)·(ward −
  player) > 0`).
- `test_it_jinks` — same set-up, after settling: the support's offset across the ward line spans > 15 px over 4
  `jink_period`s; control with `jink_strength = 0` (private config) spans < 3 px.
- `test_evades_an_approaching_player` — same set-up, settled 3 s; then the stub flies a **straight line** at 200 px/s for
  3 s from (640, 760) toward the support's settled position (so it crosses the ward), **setting `player.velocity`
  every tick** (so `break_contact` sees a closing threat). Min distance ≥ 0.8 × `evade_radius` every tick, **for each of
  seeds 1, 2, 3, 7** (not one lucky seed). **Control:** the same run with `evade_speed = 0` comes within 0.8 × `evade_radius`.
- `test_never_moves_toward_the_player_by_more_than_50_px` — support spawned at (500, 400), ward (640, 300), still player
  at (640, 700); over 5 s the distance to the player never drops more than 50 px below its start.
- `test_faces_the_ward` — after settling, the nose (rotation + `sprite_forward_angle`) points at the ward within 0.2 rad.

Assault view clamp:
- `test_assault_anchor_behind_a_ward_above_the_view_is_clamped_into_view` — ward at (640, −80) (inside `ward_view_band`),
  player (640, 600) → raw anchor at y ≈ −230; the support stays inside `view.grow(view_band)` every tick for 4 s,
  `anchor.y ≥ view_margin`, and `is_supporting()` becomes true.
- `test_assault_ward_300_px_above_the_view_top_no_support_until_the_view_pans` — the ward at (640, −300), support spawned
  at (640, 120): the ward is no candidate (outside `ward_view_band`), so the support has no ward, stays inside
  `view.grow(view_band)` every tick for 1.2 s (< the grace) and `is_supporting()` is false; then camera
  `offset = (0, −300)` in the same frame, one tick → that ward selected and `is_supporting()` true.
- `test_assault_a_ward_that_leaves_the_view_is_dropped` — while supporting, the `offset` pans so the ward is outside
  `view.grow(ward_view_band)`: `is_supporting()` false **in the same frame, before any tick**; after one tick the ward is
  dropped (`ward_changed(null)`).
- `test_assault_support_pushed_out_of_view_does_not_support` — the `offset` pans so the support (not the ward) is outside
  `view.grow(view_band)` → `is_supporting()` false in the same frame; a pan that leaves it 1 px inside the band → true
  (boundary).

Re-pointed t10 rows (the §2.12 grace and filter change what they could assume):
- `test_it_holds_near_an_ally_at_follow_distance` and `test_it_closes_on_a_far_ally_and_picks_the_nearest_of_two`:
  Open Space only (the SEEK_WARD fallback with a non-candidate ally); Assault's no-ward case is the grace rows above.
- `test_with_no_ally_it_drifts_in_place`: Open Space only, same reason.
- `test_enemy_dual_mode.gd::test_support_ship_holds_near_an_ally_in_both_modes` → the ally gets `score_value = 25` (a
  ward); assertions: within 60 px of `anchor`, and `assert_almost_eq(distance to ward, Vector2(150, 40).length(), 60)`.

Gates: `test_enemy_mover_single_writer.gd` (sweeps the brain), signal arity, project load, all automatic.

## Risks

- Follow rows depend on rng (side, jink): they use a fixed `rng_seed` so a failure reproduces.
- Hand-ticked tests: still candidates, so `ward_keep_radius`/view drops are only from the support's or camera's motion.
- `FOLLOW_GAIN` and the 0.8–1.0 × `evade_radius` blend are judgement; recorded in DECISIONS.md.

## Out of scope

Repair, shield projection, projector unfold, tether drawing (t12); ESCORT (t13); IDLE / NOTICING / RETURNING (t15).
