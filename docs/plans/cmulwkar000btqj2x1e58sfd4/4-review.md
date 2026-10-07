VERDICT: CHANGES_REQUESTED

# Review — t8b-fighter-run task plan (round 1)

Reviewed `3-plan.md` and `1-context.md` against the epic plan (`cmufs7ekv000lnm2x7nbswijy/3-plan.md` §2.4, §2.4.1,
§2.4.2, §2.5, §3 row 9, §4 t8b row), its `4-review.md` N1/N4/N8/N9, the `t8b-fighter-run` acceptance criteria,
CLAUDE.md and DECISIONS Phase 3. I read the code the plan cites and re-ran the prototype
(`/tmp/sim/sim4.gd`). I also wrote three checks of my own: `/tmp/rev/chk1.gd` (Dubins maths), `/tmp/rev/asim2.gd`
(the plan's Assault rules, which the prototype never ran) and `/tmp/rev/s4n.gd` (`sim4.gd` instrumented for
nose-on-player events).

Dubins is justified in principle. N8's diagnosis is right, and its own fix does not work. I checked the maths.
The Open Space holding-player numbers reproduce exactly. But the plan has three design problems that break
player-facing behaviour the epic promises, and its test plan would not catch any of them. Two of the three come
from the plan's own changes to the epic plan.

## Blocking

### B1. Assault: the first pass is never a lateral sweep, because the S clamp puts S inside the breach radius

- **Where:** `3-plan.md:136-141` (S clamp, "shrunk by `2r + hull_radius`") and `3-plan.md:99-103` (APPROACH:
  clearance = `standoff_radius`, breach "inside `standoff_radius` → RUN_IN at once as a FRONTAL-shaped pass").
- **Numbers:** the corridor is x −100..1380 (`assault_corridor_constraint.gd:84-89`, `arena_camera.gd:40-43`).
  Shrunk by 2 × 166.7 + 28.6 = 362 px, S.x is clamped into [262, 1018].
  - For any player near the corridor's centre line (x = 640), FLANK_LEFT's S = (160, y − 160) clamps to x = 262,
    and FLANK_RIGHT's to 1018.
  - Either way |S − P̂| = √(378² + 160²) = **411 px < 480**.
- **Consequences:**
  1. No Dubins path to S can pass APPROACH's clearance check, because its last sample, S itself, is inside 480.
     `asim2.gd` finds no clear candidate from any entry pose.
  2. Reaching S is impossible without crossing the standoff circle, so the breach rule always fires first.
- **Simulated with the plan's own Assault rules** (spawn above the screen, player at (640, 360) or (640, 600)):
  - APPROACH breaches at t = 2.3 s and 3.2 s.
  - The first pass is a FRONTAL-shaped dive with `u ≈ (0.92, 0.38)`, so it is not lateral.
  - The first lateral flank RUN_IN starts at **7.35 s / 8.35 s**. The shipped `engage_seconds` is 6.0, so it never
    happens.
- **What that means in play:** with the shipped config, a fighter against a centred Assault player never flies the
  "horizontal sweeps across the corridor" the plan's own Problem section promises (`3-plan.md:13-14`), and R3.5 asks
  for.
- **Why the tests miss it:** the planned lateral test (`3-plan.md:212`) filters by flank kind and would have to raise
  the budget to see a flank pass at all. It would stay green over this.
- **Cause:** the epic's bare-rect clamp left |S − P̂| = 506, so this problem comes from deviation 4 (the 2r shrink).
- The plan's worked example also has a small error. "S clamps to x = 234" (`3-plan.md:143`) leaves out the hull;
  the correct figure is 262.
- **Required:**
  - Make APPROACH's clearance and breach radius consistent with a clamped S. For example, breach at
    `min(standoff_radius, |S − P̂|) − margin` and plan to the same number, or clamp S so that it stays ≥
    `standoff_radius` from P̂ where the corridor allows.
  - Prototype Assault before implementing: centred player, player near the top (lane flip), player near a wall
    (bearing flip), entry from above, shipped `engage_seconds`.
  - Add an intent test: in Assault, with the **shipped** budget, a player at the corridor's centre and a fighter
    spawned above the screen, the **first** RUN_IN is a flank-shaped lateral pass.

### B2. Opportunity (b) never happens in natural play, so FORWARD (the close-range burst) is unreachable

- **Measured:** I instrumented `sim4.gd` to log every TURN or REPOSITION tick where the nose is within 12° of the
  player and d ≤ 520 (`/tmp/rev/s4n.gd`). Across all five prototype scenarios (solo, FRONTAL alternation, repeated
  FLANK_LEFT, and both moving-player cases) there are **zero** such ticks.
- **Why:** the clearance-aware Dubins loop always swings away from the player.
- **What else closes off FORWARD:**
  - TURN is the first arc of a path planned with REPOSITION's clearance, 288 (`3-plan.md:104-108`; `sim4.gd:95`).
    With `forward_range` at 300, (b) could only pick FORWARD in the band d ∈ [288, 300) even if the nose ever came
    on.
  - Opportunity (a) is always AIMED. From S the player is atan(160/480) = 18.4° off the nose (28° on FLANK_RIGHT's
    260 lane), which is more than `nose_cone_deg` 12°, and the angle only grows along the run.
- **Net effect:**
  - Every pass fires exactly one AIMED burst at about 506 px.
  - The fighter never uses the close-range spray that the task title and R3.3 describe.
  - The epic's §2.4.2 claim, "(b) … at the end of a turn, often at 200–350 px, so one fighter naturally uses both
    modes in a single run", no longer holds.
  - N8 listed "opportunity (b) never fires for a solo fighter" as one of the problems to fix. Under this plan it
    never fires for **any** pass kind.
- **How the plan presents it:** R4 (`3-plan.md:236`) describes this as FORWARD firing "rarely" and points to the
  epic's K5 lever (tuning `forward_range`). That lever cannot help while the nose never comes onto the player. The
  item is also missing from the "Deviations to log" list.
- **Required:** pick one of:
  - Restore a (b) that actually occurs. Options include: TURN not constrained by `reposition_min_radius` (the epic's
    TURN had no routing); preferring, among clear candidates, the one whose first arc sweeps the nose across the
    player; or an explicit nose-on leg before RUN_IN. Then report from the prototype how often (b) fires and in which
    mode, per cycle and per pass kind.
  - Or record it as a deviation that needs the owner's sign-off.

  Staged weapon tests alone cannot show either outcome.

### B3. When the pass is latched is unspecified, and REPOSITION/APPROACH have no upper time bound

**(i) Latching.**
- The epic latches `b, u, l` **on RUN_IN entry** (§2.4.1). §2.5 rules 1–2, the contract t9 builds on, let a role
  change take effect only through REPOSITION.
- The plan exposes "latched" `pass_bearing/dir/lane` (`3-plan.md:34-35`, `:203`) and latches the lead "when the pass
  is chosen" (`:30`). In practice that is TURN entry, because TURN needs the next S. It never says whether `h`, kind,
  `b` and `l` are re-derived during TURN/REPOSITION.
- If they are frozen at TURN entry:
  - an Open Space player who turns during a 3–5 s REPOSITION gets a pass shaped for a stale heading;
  - t9 cannot apply its "role change takes effect at the next REPOSITION" rule without rewriting this.
- **Required:** state that the pass is re-derived every tick during APPROACH/TURN/REPOSITION (from `h`, the solo
  alternation or `forced_pass_kind`, and later `role_of()`), with the 24 px replan trigger absorbing the changes, and
  latched on RUN_IN entry. The lead-latch argument (`:30-33`) holds equally if the lead is latched at RUN_IN entry.

**(ii) Liveness.**
- Deviation 2 (`3-plan.md:110-112`) makes `reposition_max` count only ticks flown on the fallback ring. The stated
  reason is that "a clear Dubins path is guaranteed progress", which is only true for a goal that does not move.
- In the plan's own prototype, the moving-player solo run spends **12.5 s in APPROACH (188 replans) and ≈ 11 s in
  REPOSITION (370 replans)** before a pass.
- Three cases get no bound at all:
  - a player faster than 300 px/s (Open Space cruises at 420);
  - a weaving player: in Open Space `h` follows the velocity direction, so S swings round a 506 px circle and
    replans every few ticks;
  - APPROACH, which never had a cap.
- The epic's 3.0 s `reposition_max` existed precisely to guarantee an attack cadence.
- **Required:**
  - Keep an absolute cap on REPOSITION: for example the path length at first plan / `max_speed` + `reposition_max`,
    or a fixed ceiling. The ring-only counter can stay underneath it.
  - Say what bounds APPROACH.
  - Test the cap with a weaving or fast player.

### B4. Test-plan gaps for rules that can regress

- **N9 (binding on this task) is untested.** There is no case for the APPROACH breach fallback. Add one: fighter
  spawned inside `standoff_radius` (and one with the player closing on it). Assert:
  - `b = dir(X − P̂)` and `l ⟂ u`;
  - σ taken from the drift side;
  - the closest approach against its tolerance.

  This is also the only situation where hurtbox overlap is plausible. The planned no-overlap case (25 s of solo passes
  against a holding player, `3-plan.md:210`) has a minimum distance of 159 px against a 42 px limit, so it cannot
  fail.
- **The passes-done rule is untested:** Assault → DISENGAGE (including the deferral when a burst is running), and
  Open Space → the 1.5 s REGROUP loiter.
  - At the shipped `engage_seconds` 6.0, an Assault fighter never reaches a second pass anyway: the second RUN_IN
    starts at ≥ 6.4 s in both the prototype and `asim2.gd`, even when APPROACH is skipped.
  - So these cases, and the dual phase-sequence case (`:200`), must raise `engage_seconds` on the private config. Say
    so, and note for t16 that the pre-approved lever "`assault_passes` 2 → 1" currently changes nothing.
- **`min_burst_period` needs a staged boundary.** Natural gaps between legs are ≥ 3 s, so "≥ `min_burst_period`
  between two burst starts" (`:222`) can never fail. Stage a TURN with the nose on the player 0.5 s after a RUN_IN
  burst, and assert no burst before 1.2 s. Also define "burst start": telegraph start or first shot.

## Non-blocking

1. **APPROACH clearance equals the breach radius (both 480), with no margin.** The kinematic prototype never
   breaches, but it tracks perfectly. The real mover follows `_heading()` from velocity through `move_toward`, and a
   few px of tracking error on a path that grazes 480 flips a flank pass into a FRONTAL one. Plan to the breach
   radius plus a margin (e.g. 24 px).
2. **RUN_IN feed-forward (`3-plan.md:45`):** say what happens when |v⊥| ≥ `max_speed`. The √ goes negative, and
   the Open Space player cruises at 420. The prototype clamps it to 0; the plan should too. `RUN_IN_MAX_SECONDS` is
   then the only exit, and it is untested.
3. **The path radius equals `max_speed / turn_rate` exactly,** so the tracker has zero turn authority to spare on an
   arc and can only recover by replanning. Planning at about 1.05–1.1 r costs nothing against the 15 % TURN-radius
   tolerance.
4. **Dubins unit test (`3-plan.md:194-195`):** "sampled heading at the end within 1°" fails on any arc-ending
   candidate at 8 px sampling. The last chord is off by step/(2r) = 1.37°: I measured 1.375° over 200 random pose
   pairs, and it is 2.75° at 16 px. Expose the end heading analytically, or use a tolerance of step/(2r) + ε.
5. **CPU (R5):** evaluate candidates in length order and stop at the first clear one, as `sim4.gd:24` already does.
   The moving-player prototype replans about 15 times a second, not 8, and plans twice per replan for the goal
   prediction.
6. **REGROUP loiter (`3-plan.md:118`):** capping the whole of `v_P + (S − X)` at 60 px/s means the fighter cannot
   hold S against a moving player. Cap only the correction term.
7. **Config convention:** `REGROUP_SECONDS` and `RUN_IN_MAX_SECONDS` are tuning values. Either make them
   `FighterConfig` fields (`test_config_instance_isolation.gd` keeps the class flat, which these would not break), or
   say why they are structural.
8. **Locked `aim_point`:** `AimedAttackPattern.fire` measures a finite `aim_point` from
   `ship.global_position + spawn_offset` (`aimed_attack_pattern.gd:34-35`), and the fighter's AI patterns keep the
   default unrotated (0, 10) offset. The burst-direction tests should allow for it, or the brain should set
   `spawn_offset` to zero.

## Checked and fine

- **Dubins maths** (`/tmp/sim/dubins_path.gd`, via `/tmp/rev/chk1.gd`), over 200 random pose pairs:
  - every candidate ends within 1.2e-4 px of the goal;
  - analytic length matches the 8 px polyline within 0.01 %.
- **Solo reversal (450, −160)/0 → (480, −160)/π:** the shortest candidate is RLR/LRL at 1220 px, CCC and ≤ 1250,
  as claimed. It is also the shortest candidate that stays clear of the player at 288.
- **N8 analysis:** after FLANK_LEFT → FLANK_RIGHT, the next S is dead ahead on the same line. N8's `S − u·lookahead`
  point is also dead ahead, so seek-based fixes cannot produce the arrival heading. A pose-to-pose planner is a
  reasonable answer. Nothing like it exists in `global/`: there is no Dubins or arc-path code outside `/tmp`.
- **Prototype table (`3-plan.md:123-129`)** reproduces exactly:
  - closest approach 159.3–160.6 px;
  - TURN radius 166.7–170.1 px;
  - cycle ≈ 6.6 s solo, ≈ 9 s frontal, ≈ 8.8 s repeated flank.

  Open Space approach from five entry poses (`/tmp/rev/osim.gd`) never breaches spuriously.
- **Lead-latch arithmetic:** the lead goes 0.8 → 0.53 s, and 0.27 × 200 = 54 px of drift.
- **Feed-forward arithmetic:** the pure-pursuit steady state is e = 200 × 220 / √(300² − 200²) = 196.8 px.
- **FORWARD-hold collision arithmetic:** 250 − 0.6 × 300 = 70 px.
- **Deferral bound:** 0.3 + 4 × 0.10 = 0.7 s ≤ 0.8 s.
- **Mover:** a full-rate turn needs 540 px/s² against 700 px/s² available (`fighter_config.tres`,
  `enemy_mover.gd:365-372`, `max_turn_rate` = `turn_rate` from `fighter.gd:53`), so the real mover can follow a
  full-rate arc.
- **Single writer:** `DubinsPath` as a pure `RefCounted` in `global/enemy_ai/` passes
  `test_enemy_mover_single_writer.gd`'s receiver matcher. The brain bends its path only through `turn_toward`
  (Phase 2 D7).
- **Weapons layer (§4):** matches §2.4.2 and N4:
  - hysteresis 300/360;
  - FORWARD skipped and not spent;
  - one burst per leg;
  - `weapon_mode_changed(mode: int)`;
  - `BurstClock` + `fire_now()` on the latched controller;
  - `aim_point` lock and reset;
  - `on_suspended()` stopping the burst.

  "Any RUN_IN tick" for (a) is a sensible reading once `min_burst_period` can block the first tick.
- **Scope:** no squad roles, idle or level migration. `forced_pass_kind` and the exposed pass fields are the right
  seams for t9, subject to B3(i).

## Round 2

VERDICT: APPROVED

Re-reviewed Revision 2 of `3-plan.md` against the same sources as round 1, plus the code it cites. I ran the new
prototype, `/tmp/sim/sim9.gd`, and wrote five variants of my own in `/tmp/rev/`:

- `sim9m.gd`: the moving-player trace;
- `sim9s.gd`: staged moving-player spawns, one per pass kind;
- `sim9br.gd`: breach cases;
- `sim9b.gd`: bearing rate while a FORWARD burst is held.

Every round-1 blocking point is answered in the design, and I checked each answer numerically. No redesign is
needed. What remains are errors in claimed numbers and gaps in the spec that an implementer would otherwise trip
on. Each one is written below as a **binding implementer note (I1–I8)**, and each must be applied during t8b.

### Round-1 points, verified

- **B1: fixed.**
  - The APPROACH clearance is `min(standoff, |S − P̂|) − 1` and the breach radius is 24 px less
    (`3-plan.md:112-118`).
  - With the 1.1 r plan radius, S clamps to x = 295 = −100 + 2·183.3 + 28.6, giving |S − P̂| = 380, consistent with
    `:114` and `:151`.
  - `sim9.gd` "Assault centre, from above" with the shipped 6 s budget: the first RUN_IN is at 3.77 s, FLANK,
    `u = (−1, 0)`, closest approach 160.5. No non-lateral tick and no exit from the soft band in any Assault row.
    The table rows at `:156-165` reproduce exactly.
- **B2: fixed.**
  - The turn-in snapshot comes nose-on at 304–308 px in every holding-player scenario and in the centred and low
    Assault scenarios.
  - With `forward_range` at 325 that is FORWARD, while the RUN_IN burst at ≈ 506 px stays AIMED.
  - The acceptance numbers 250/400/330 still hold: 330 lies in [325, 385).
  - `forward_range` has no reader outside `fighter_config.gd` and `.tres`.
  - K5 is the epic's pre-approved lever, so this is a legitimate, logged deviation (`:301`).
- **B3-i: fixed.** Passes are re-derived until RUN_IN and latched on RUN_IN entry (`:33-42`), which matches epic
  §2.4.1 and the t9 contract in §2.5. A latching test was added (`:248-249`).
- **B3-ii: fixed in principle.** A deadline now falls back to the FRONTAL breach pass (`:131-136`), and the test at
  `:258` covers a 420 px/s player. See I1 for a gap in how the deadline is defined.
- **B4: fixed.**
  - Breach cases (`:254-256`). In `sim9br.gd`, breaches at 380 px and at 300 px give closest approaches of
    122.5 px and 110.6 px, both inside the planned ±60 tolerance (37.5 and 49.4 px under 160).
  - Passes-done and regroup (`:260-262`).
  - The `min_burst_period` boundary (`:276`); see I2.
  - The natural-play weapon intent case (`:268-269`).
- **Non-blocking 1–8:** all addressed (`:321-328`).
- **Other figures checked:**
  - pass-to-pass times: 10.05 / 13.05 / 9.7 / 9.35 s;
  - closest approaches: 159.4–160.5 px.

### Binding implementer notes

**I1. The REPOSITION deadline needs a defined basis when REPOSITION inherits TURN's path.**
- Where: `3-plan.md:131-133`.
- The problem: the break-away plans the REPOSITION path inside TURN. REPOSITION then flies that same path and does
  not re-plan for a holding player, so it has no "first successful plan in that phase". Read literally, its deadline
  falls back to `reposition_max` alone, 3.0 s.
- In `sim9.gd`, REPOSITION after the break-away arc takes ≈ 4–5 s: solo nose-on at 6.03 s, RUN_IN at 11.22 s.
- A literal build would therefore cut every solo and repeated-flank cycle into a FRONTAL breach pass.
- **Required:** the deadline is `(remaining length of the path being flown at REPOSITION entry) / max_speed +
  reposition_max`. The same rule applies to APPROACH, using its first plan.

**I2. The `min_burst_period` staged test contradicts the definition of (b).**
- Where: `:176-177` against `:276-277`.
- (b) is "the TURN tick on which the nose comes within the cone", and the turn-in ends on that same tick. A nose-on
  blocked by the period is therefore lost. So "no burst before 1.2 s, **and one after**" cannot happen, because after
  that tick the fighter is breaking away with its nose off.
- **Required:** keep (b) as a single tick. Change the test to assert that the blocked nose-on gives **no** leg-B
  burst in that TURN, and that leg B is still unspent until TURN ends. Put the "one after" half on opportunity (a):
  a RUN_IN staged 0.5 s after a burst start fires at 1.2 s, not before.

**I3. The FORWARD-hold numbers are wrong, and "never closes to spray" is false.**
- Where: `:195-198`.
- Measured in `sim9b.gd` over the 0.6 s of telegraph + burst after nose-on:
  - bearing rate **1.48 rad/s** (solo and Assault), **1.75 rad/s** (FRONTAL);
  - distance falls from ≈ 305 px to **202 px** (solo) and **152 px** (FRONTAL).
- It still sits under the mover's 1.8 rad/s rotation cap (`enemy_mover.gd:385-387`), so the mechanism stands.
- **Required:**
  - correct the text and the DECISIONS line;
  - in the FORWARD test, assert each shot is along the **nose** (as planned), not at the player, because on a
    FRONTAL break-away the nose can lag the bearing by a tick;
  - the no-overlap case must include one full natural FRONTAL cycle (minimum 142.5 px in the prototype).

**I4. The turn-in timeout has about 10° of margin.**
- Where: `:124`.
- Every prototype turn-in takes 1.95 s, about 200°. The cap `π / turn_rate + 0.3` = 2.05 s is 6 ticks longer.
- The geometry is deterministic today, but any retune of EXTEND, `pass_offset` or `turn_rate` would time the turn
  out silently, and (b) would stop firing.
- **Required:** make the cap `2π / turn_rate`, a full circle. The natural-play weapon test then guards the snapshot.

**I5. The break-away must not re-plan at REPOSITION's clearance mid-arc.**
- Where: `:124-126`.
- With a moving player, S moves more than 24 px about every 0.12 s (`sim9s.gd`: re-plans every 0.13 s in
  REPOSITION).
- A break-away re-plan made with the 288 px clearance from a pose inside 288 finds no path. The fighter then drops
  to the ring mid-arc.
- **Required:** while in the break-away, re-plan only with the break-away clearance profile, or not at all (fly the
  arc, as `sim9.gd` does).
- A REPOSITION re-plan that starts inside `reposition_min_radius` treats the start samples as exempt until the path
  first leaves the radius. Without that, "REPOSITION entirely outside `reposition_min_radius`" (`:81-83`) cannot be
  planned from where the break-away ends.

**I6. The moving-player row omitted from the table.**
- Where: `:167-169`.
- `sim9.gd`'s own "OS moving solo (spawn ahead)" row makes **no pass in 40 s**: minimum distance 481.7 px, and
  `sim9m.gd` shows the fighter overflying S along `h`.
- The table leaves this row out and cites round-1 numbers instead. Staged spawns do work (`sim9s.gd`): closest
  approach is 160.4 px (flank) and 160.0 px (FRONTAL) on the first pass, so the N1 acceptance holds as planned.
  After that pass, though, REPOSITION never converges in 12 s, and every later pass comes from the liveness
  deadline as a FRONTAL breach pass.
- Moving-player snapshots come nose-on at 474 px (flank) and 686 px (FRONTAL): AIMED or no burst, never FORWARD.
- **Required:**
  - Add a natural-play test: Open Space, player at 200 px/s, natural spawn. Assert at least 2 RUN_IN entries within
    20 s, every one with closest approach ≥ the hull limit.
  - State the steady state (breach-shaped passes against a cruising player) in `ENEMY.md` and DECISIONS.

**I7. The Assault EXTEND rule differs from the prototyped one.**
- Where: `:119-120`.
- The plan says `X + heading·(r + hull)` (≈ 195 px) leaves `inner_rect()`. `sim9.gd:144-145` uses 0.3 s ahead
  (90 px) inside `inner_rect().grow(−hull)`.
- The Assault ring clamp also differs: the plan shrinks by `r`, `sim9.gd:125` by 200 px.
- **Required:** implement the prototyped rule, or re-run the near-wall scenario with the plan's rule before
  committing. The near-wall row today has EXTEND ending after 0.12 s and nose-on at 157 px.

**I8. Log that shipped Assault never uses FORWARD.**
- Where: deviation 8 at `:309-310`.
- At `engage_seconds` 6.0 an Assault fighter flies one lateral pass with one AIMED burst and leaves during EXTEND
  (`sim9.gd`: DISENGAGE at 6.02 s from EXTEND). So it never reaches the turn-in and **never fires FORWARD in
  Assault**.
- The epic's line "in Assault … FORWARD is more common" (§2.4.2) no longer holds.
- **Required:** record this beside deviation 8 as a t16 tuning input. It is a known consequence, not a defect of
  this task.

### Non-blocking
- `DubinsPath` is justified, is not a reinvention (nothing similar exists in `global/`), and passes the single-writer
  sweep as a pure `RefCounted`.
- The new config fields `run_in_max` and `regroup_seconds` keep `FighterConfig` flat.
- `face_toward` is a mover request, so the brain still never writes rotation.
- The loiter (`:137-140`) and `forced_pass_kind` leave t9 a clean seam. Nothing from t9, t12 or t16/t17 is built
  here.
