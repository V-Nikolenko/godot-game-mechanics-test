# t17 — Ram Corvette charge (Revision 2)

Task `cmuyk2qqb0091oa2xy7yn9sxa`. Builds the epic plan's §2.6.2 / §2.6.3 / §2.9.4 on the t16 shell. Context:
`1-context.md`. Where this plan fills a gap the epic plan leaves open, it says **[gap]**; numbers with no source are
**[judgement]** config defaults. Revision 2 applies review round 1 (`4-review.md`); each change is tagged R1-xx.

## Problem

Today the Corvette only flies at the player (a plain intercept) and leaves Assault when its budget runs out; it never
charges. After this task it: lines up on where the player *will be*, stops and glows while it winds up, rams in a
straight line through and 220 px past that point, swings round in a wide arc and tries again. Its plates' breaking
staggers a wind-up. With every plate gone it is faster, its charge hits harder and it jinks out of the player's aim.
In Assault it always charges diagonally, always gets its charge in before its time runs out, and leaves straight
along its charge.

## Design

### Phases

`Phase { APPROACH, LINE_UP, WIND_UP, CHARGE, WIDE_TURN, DISENGAGE, STAGGER }` — **STAGGER is appended** after
DISENGAGE so t16's values do not move [gap: the epic plan describes the stagger but names no phase]. t19 appends its
hub phases after STAGGER.

```
APPROACH → LINE_UP → WIND_UP → CHARGE → WIDE_TURN → LINE_UP (in range) | APPROACH (out of range)
LINE_UP / WIND_UP --plate breaks--> STAGGER → LINE_UP (gate) | APPROACH (gate fails) | DISENGAGE (budget expired)
```

The brain reads the player once per tick (`TargetInfo.player`).

**Attack gate** `can_attack()`: `budget.remaining() >= config.line_up_cap + ATTACK_GATE_MARGIN` (0.05 s: three ticks of
float rounding, the Swarm Drone's `ATTACK_GATE_MARGIN` precedent, R1-N3); INF in Open Space. It still satisfies "LINE_UP
only if remaining() ≥ line_up_cap", and makes "a LINE_UP always reaches WIND_UP before expiry" hold despite the budget
being updated before the phase logic each tick. Every entry into LINE_UP goes through it (APPROACH in range, WIDE_TURN
end, STAGGER end). Gate closed → APPROACH continues.

**APPROACH.** `mover.max_speed = cruise`. Open Space: `mover.intercept(target, cruise, INTERCEPT_LOOKAHEAD)` as now.
Assault: `mover.seek(target.predicted_position(INTERCEPT_LOOKAHEAD) + Vector2(side, vside) · assault_side_offset, cruise)`.
With the offset at 0 this is exactly `Steering.intercept`, so the epic's "curved intercept" is kept and the dual-mode
identity case holds for any player velocity (R1-N5). `|offset| = 339 < engage_range`, so the ring is always crossed
before the point is reached. Within `engage_range` of the player and gate open → LINE_UP.
- `side` is chosen on the first Assault APPROACH tick after spawn and after every `enter_phase(APPROACH)` (`side = 0`
  marks "unchosen", which also covers the spawn's APPROACH that never goes through `enter_phase`, R1-N8). Tie-break
  (review N5): `sign(R.x − P.x)` when `|R.x − P.x| ≥ SIDE_TIE` (8 px); else the side with more corridor room beside the
  player (`sign(rect.center.x − P.x)` when that differs by ≥ 8 px); else an `rng` coin flip. If the chosen side's
  point lies outside `inner_rect().grow(−64)` on x and the other side's does not, flip. `vside = +1` when the Corvette
  is below the player, else −1 (above).
- Geometry check (top spawn at the level-1 distance, 800 px above the player): the 420 ring is crossed at
  ≈ (180, −379) from P → 25° off vertical. The angle depends on the spawn distance (≈ 11° from 500 px, R1-N4), so test
  10 spawns at the level-1 offset and the attack-in-budget runs assert ≥ 20° for every real spawn class.

**LINE_UP** (≤ `line_up_cap` 0.5 s). Lead `t = Steering.clamped_lead_time(d, charge_speed, lead_min 0.15, lead_max 0.6)`,
`P̂ = target.predicted_position(t)`, clamped to `inner_rect()` in Assault. `aim_dir` tracks P̂ freely (it is a
direction, not the nose). Requests zero velocity (brake) and `face_toward` along the aim (the mover's `max_turn_rate`
turns the nose). Ends when (`|nose − aim| ≤ 8°` **and** speed ≤ `crawl_speed`) or at `line_up_cap`.
- **[gap] braking**: WIND_UP must be ≤ 30 px/s from its first tick, but the mover brakes at `acceleration` (500). New
  config field `braking` 1600 px/s² [judgement] is written to the mover (`EnemyMover.braking` is a field, like
  `max_speed`) **only on entry to LINE_UP, WIND_UP and STAGGER**; every other phase's entry writes 0 (= `acceleration`),
  so the post-charge slow-down and the wide turn keep the mover's 500 (R1-N1). The fastest LINE_UP entry is a WIDE_TURN
  that ends on its first tick right after a charge: 700 px/s exposed (R1-N2, not 340 as Revision 1 said), which brakes
  to 30 in (700 − 30) / 1600 = 0.42 s < `line_up_cap`. Asserted as a config inequality read from the fields,
  `(max(charge_speed, exposed_charge_speed) − 30) / braking ≤ line_up_cap`, and by a dual case. The speed condition on
  the early exit makes "≤ 30 at WIND_UP entry" hold by construction; the cap still bounds LINE_UP.

**WIND_UP** (`wind_up_seconds` 0.65). Requests `aim_dir · crawl_speed` (20 px/s, a creep along the aim) and faces along
the aim. StateLight CHARGING. `glow = phase_time / wind_up_seconds` → every live plate's `set_glow` (through
`RamCorvette.set_plate_glow`). For the first `windup_track_fraction` (0.6) the aim turns toward the fresh P̂ at
≤ `windup_track_rate` (0.8 rad/s); at that moment it **freezes**: `charge_dir` and `charge_point`
(= pos + aim · |P̂ − pos|) are latched and never touched again.

**CHARGE.** `mover.boost(charge_dir, charge_speed, min((along + overshoot) / charge_speed, charge_max_time))`, `along` =
`(charge_point − pos)·charge_dir`, `overshoot` 220, `charge_max_time` 1.45. StateLight COMMIT. Glow held at 1. Exposed:
`contact.set_armed(true)` on entry. Ends when `mover.is_boosting()` is false → WIDE_TURN (exposed: disarm on leaving
CHARGE). Records `charge_origin`, `charge_duration`, `charge_started_at`, `charges` (count) for tests and the print.

**WIDE_TURN.** `turn_dir` starts at `charge_dir`, `Steering.turn_toward(turn_dir, P − pos, wide_turn_rate 1.4, dt)`,
requests `turn_dir · cruise`. Glow fades to 0 over `glow_fade_seconds` (0.3). Ends when `turn_dir` is within
`wide_turn_exit_angle_deg` (30°) of the player, or after `WIDE_TURN_CAP` (4 s) [gap: the epic plan has no cap; a player
orbiting could hold a 1.4 rad/s turn forever] → LINE_UP if within `engage_range` and gate open, else APPROACH [gap: the
epic plan says LINE_UP; a Corvette 700 px out would otherwise charge from out of range]. The per-tick rate assertion is
on the commanded `turn_dir`; the flown velocity heading is bounded on average once settled at cruise (test 6).

**STAGGER** (`stagger_seconds` 0.4). `on_plate_broken()` (called by `RamCorvette._on_plate_broken`) during LINE_UP or
WIND_UP enters it; in any other phase (STAGGER included), nothing. Requests zero velocity, glow 0, light OFF +
`blink_once()`. End: `disengage_pending` → DISENGAGE (nearest-edge); else in range and gate open → LINE_UP; else
APPROACH.

**Rails (R1-B1).** `on_suspended()` latches `suspended`; while it is set, `on_exposed()` and `on_plate_broken()` change no
phase, no contact arming and no speed — a railed ram's profile stays armed for life (epic §2.6.3). The exposed contact
60 / shove 0 still come from `_expose`. Tested.

**Exposed** (`on_exposed()`, called from `RamCorvette._expose`, i.e. on `armor_broken` per the t16 DECISIONS note):
`exposed = true`; cruise → `exposed_cruise_speed` 340 (and `mover.max_speed` in APPROACH / WIDE_TURN), charge →
`exposed_charge_speed` 700; contact disarmed unless in CHARGE (exposure mid-CHARGE disarms when the charge ends); light
`blink_once()`. Contact 60 and shove 0 are already set by `_expose` (t16). **Evasion**: in APPROACH and WIDE_TURN,
exposed, `d < evade_range` (600) and the player's facing within `evade_cone_deg` (20°) of the player→Corvette direction
→ `evade_nudge = Steering.strafe(pos, P, ±1, evade_speed 180)`, the sign chosen so the nudge points away from the
player's aim line (towards the side of it the Corvette is already on), added via `add_nudge` (`max_speed` caps the
sum). Otherwise `evade_nudge = 0`. Exposed field `evade_nudge` for tests.

**Assault expiry by state** (`_on_budget_expired`, the first tick `budget.update` is true):

| Phase | Result |
|---|---|
| APPROACH, LINE_UP, WIDE_TURN | DISENGAGE that tick, nearest-edge exit (no deferral) |
| WIND_UP, CHARGE, STAGGER | `disengage_pending`; CHARGE end → DISENGAGE **straight** along `charge_dir`; STAGGER end → nearest-edge DISENGAGE |

Deferral bound `wind_up_seconds + charge_max_time` = 2.1 s (STAGGER 0.4 < any WIND_UP + charge it cancels).
DISENGAGE after a charge: `_straight_exit = true`, requests `charge_dir · exit_speed` every tick, constraint released,
freed outside the world rect (same strict test as today). DISENGAGE from anywhere else: today's nearest-edge curve.

### Ram script changes

- `_ram_brain.contact = contact_profile` wiring in `_ready()`; `_on_plate_broken` → `_ram_brain.on_plate_broken()`;
  `_expose` → `_ram_brain.on_exposed()`; `set_plate_glow(amount)` over live plates.

### Config (`RamCorvetteConfig`, flat, appended under `Charge`)

`engage_range` 420, `assault_side_offset` 240, `line_up_cap` 0.5, `line_up_tolerance_deg` 8, `lead_min` 0.15,
`lead_max` 0.6, `braking` 1600, `crawl_speed` 20, `wind_up_seconds` 0.65, `windup_track_fraction` 0.6,
`windup_track_rate` 0.8, `charge_speed` 620, `overshoot` 220, `charge_max_time` 1.45, `wide_turn_rate` 1.4,
`wide_turn_exit_angle_deg` 30, `glow_fade_seconds` 0.3, `stagger_seconds` 0.4, `exposed_cruise_speed` 340,
`exposed_charge_speed` 700, `evade_cone_deg` 20, `evade_range` 600, `evade_speed` 180. Mirrored in the `.tres`.

### Alternatives rejected

- Raising the mover's `acceleration` for the brake, or a permanent `braking`: either would also sharpen the post-charge
  slow-down and the wide turn (R1-N1).
- A STAGGER implemented as a flag inside LINE_UP: the phase seam and `phase_changed` are what tests watch.
- Charge along the nose: the epic plan's "the charge follows the frozen aim, not the nose" keeps LINE_UP's cap safe.

## Build sequence

1. Config fields + `.tres`; ram script wiring (brain hooks, `set_plate_glow`). Gate-neutral.
2. Failing tests in `test_ram_corvette.gd` (t17 rows below).
3. Brain: APPROACH (offset + gate), LINE_UP, WIND_UP, CHARGE, WIDE_TURN, STAGGER, rails latch, exposed/evasion,
   per-phase braking, per-state expiry, straight exit.
4. Update `test_enemy_dual_mode.gd`'s approach case (zero the Assault side offset; the offset itself is tested in
   `test_ram_corvette.gd`) and t16's exposed-contact case (exposed contact lands only in CHARGE).
5. Attack-in-budget row + boundary.
6. Gate, leak check, `ENEMY.md`, DECISIONS t17 entry.

## Test plan (`tests/integration/test_ram_corvette.gd`, hand-ticked; "dual" = `use_parameters(MODES)`)

0. **Config:** the epic's numbers; `wind_up_seconds + charge_max_time == 2.1`; the designed worst case fits the boost
   cap; the braking inequality.
1. **Charge direction, dual:** player moving at (150, 0); CHARGE velocity within 5° of `predicted_position(clamped_lead)`
   computed by the test from the stub at the freeze tick (with a sanity check that this is > 5° off the player's current
   position, so the row cannot pass by aiming at the player); after the freeze the stub reverses → charge heading
   unchanged (≤ 0.5°) every CHARGE tick.
2. **WIND_UP, dual:** lasts 0.65 s ± one tick; speed ≤ 30 every tick; `glow` and every plate's modulate reach 1 (glow
   colour); light CHARGING during it, COMMIT in CHARGE. **Plus (R1-N2):** an exposed, boost-capped charge whose
   WIDE_TURN ends on its first tick still has speed ≤ 30 on every WIND_UP tick.
3. **Overshoot, dual:** stationary player; the position at CHARGE end is ≥ 200 px past `charge_point` along
   `charge_dir`; boost geometry inside the envelope (`along + overshoot ≤ charge_speed · charge_max_time`).
4. **Boundary — boost cap, dual:** seam LINE_UP with the player 1400 px away; `charge_duration` = 1.45; ticks with
   `is_boosting()` ≤ 1.45 s + one tick.
5. **Boundary — LINE_UP cap, dual:** the stub orbits the Corvette faster than the nose can turn; LINE_UP lasts ≤ 0.5 s +
   one tick (and ≥ 0.5 s − a tick: the cap ended it).
6. **Miss and wide turn, dual:** the player moves aside after the freeze; the Corvette is alive, enters WIDE_TURN,
   commanded heading change per tick ≤ 1.4 · dt + 1e-4, the flown velocity heading's average rate once settled at
   cruise ≤ 1.1 × 1.4 rad/s (R1-N8); then re-enters LINE_UP.
7. **Contact by phase, dual:** armoured → armed in every phase; exposed → armed only in CHARGE; exposure landing
   mid-CHARGE keeps it armed until the boost ends, then disarms (R1-N8). Armoured touch shoves (t16 test kept); exposed
   touch in CHARGE deals 60 and does not shove; exposed touch outside CHARGE deals 0.
8. **Stagger, dual:** a plate broken in WIND_UP → STAGGER, no CHARGE for 0.4 s, then LINE_UP; broken in CHARGE → still
   CHARGE; broken in LINE_UP → STAGGER; broken in STAGGER → no restart, no second `phase_changed` (R1-N8). Budget
   expired during the WIND_UP a stagger cancels → STAGGER ends in DISENGAGE. **Rails (R1-B1):** suspended and stripped →
   still armed, 60 on touch, no shove, no `phase_changed`.
9. **Exposed, dual:** charge velocity 700, cruise cap 340, contact 60. With the player facing it (8° off, inside the
   20° cone) inside 600 px, the nudge's component away from the aim line is positive (both modes) and the Corvette's
   perpendicular distance from the aim line grows over 0.5 s (Open Space, where the approach is the plain intercept)
   (R1-N6); no nudge with the player facing 90° away, and none while armoured.
10. **Assault diagonal (boundary on the side tie):** ram spawned exactly above a centred player **at the level-1 top
    distance (800 px, y = −440)** → charge ≥ 20° off vertical; a spawn at x = +100 px → it charges from the +x side.
    **Gate margin (R1-N3):** LINE_UP entered with `remaining()` just at `line_up_cap + ATTACK_GATE_MARGIN` reaches
    WIND_UP before expiry.
11. **Expiry by state (Assault):** expiry in WIND_UP → no DISENGAGE until CHARGE ends, then DISENGAGE heading equal to
    `charge_dir` and the Corvette freed outside the world rect, total deferral ≤ 2.1 s; `remaining() < line_up_cap`
    in range → never LINE_UP (DISENGAGE at expiry); forced on the first LINE_UP tick (seam) → DISENGAGE that tick, no
    WIND_UP; expiry in APPROACH / WIDE_TURN → DISENGAGE that tick.
12. **Open Space never disengages** and runs at least two charges in 12 s against a stationary player.
13. **Attack-in-budget (§2.9.4):** every distinct level-1 ram offset (from `Level1Director._build_sections()`) spawned
    through a real `WaveManager` / `ArenaCamera`, **one offset per run** (R1-N7: Corvette bodies collide), stub at the
    camera centre and 200 px past it away from the spawn; WIND_UP entered with budget left and (R1-N4) the first charge
    ≥ 20° off vertical; time to WIND_UP and charges per life printed. Classes top / top-wide / bottom / bottom-wide each
    present. **Boundary:** `cruise_speed` 160 on the top-wide class (stub away) never reaches WIND_UP.
14. Existing gates unchanged: contact damage (spawn-time 50), contact/hurtbox geometry, config isolation (flat),
    single writer, signal arity, sprite transparency, UID, project load. `scripts/check-test-leaks.sh` clean.

## Risks

- The approach curve under the corridor's entry rule may land the ring crossing at a smaller angle than the 25°
  estimate → measured in tests 10 and 13; tune `assault_side_offset`'s vertical share if needed (logged).
- Hand-ticked tests with `global_position = before + velocity · dt` skip collisions; contact tests use real physics
  frames as t16 does.
- t21/t22 depend on the deferral 2.1 s and the straight exit; both are as the epic plan states.

## Out of scope

Hub idle (t19), level-1 migration and the deadline rows (t21/t22), art (t18), project docs (t23).

## Review findings applied

Epic review: **N5** (side offset for centred rams): the tie-break above. **N9** (shared harness): the attack-in-budget
harness stays local to `test_ram_corvette.gd`. **N4** (lever 4's floor) is t21's; this task's printed times give it
"worst spawn-to-LINE_UP + line_up_cap". **B2** was built in t4 (plate `_resolve`); stagger hangs off `plate_broken`,
which fires once per plate.

Task review round 1 (Revision 2): **R1-B1** rails latch + test; **R1-N1** braking per phase; **R1-N2** worst case 700,
`braking` 1600, inequality + dual case; **R1-N3** `ATTACK_GATE_MARGIN` 0.05 + boundary; **R1-N4** test 10 pinned to the
level-1 distance, ≥ 20° asserted in the budget runs; **R1-N5** Assault APPROACH = intercept + offset; **R1-N6** evasion
direction asserted; **R1-N7** one offset per run; **R1-N8** side chosen lazily (covers spawn), mid-CHARGE exposure and
STAGGER plate-break rows, flown-heading rate bound.

## As built (notes against this revision)

- **Review round 2 (APPROVED) non-blocking notes, applied:** R2-N1 the Assault speed / arc tests keep the Corvette
  inside the visible rect (test 6 starts at y −200); R2-N2 the gate-margin case enters LINE_UP through the gate and runs
  it to its cap (orbiting stub), plus a 10 ms-short case that stays shut; R2-N3 the evasion run asserts APPROACH on every
  tick from rest; R2-N4 one glow fade rule (1 / `glow_fade_seconds` per second) through WIDE_TURN, APPROACH and LINE_UP,
  and WIND_UP ramps from whatever is left to 1, so it never snaps (asserted after a full-speed charge); R2-N5 braking
  and arming are written in `enter_phase`, braking by phase is tested.
- `test_enemy_dual_mode.gd`'s identity case zeroes the side offset on **both** Corvettes: the two harness worlds share
  one tree, so the "open" Corvette's AUTO mover also resolves the Assault world's corridor.
- LINE_UP cap test: the stub orbits at 4 rad/s (not "at the turn rate") starting under the resting nose, so the led aim
  stays out of the 8° window and only the cap ends it.
- Mutation checks (not committed): aiming at the player's current position fails test 1 (6.8° > 5°); dropping the rail
  latch fails the rails row; dropping the hard brake fails the braking-by-phase test and the crawl row after a
  full-speed charge (442 px/s in WIND_UP).
