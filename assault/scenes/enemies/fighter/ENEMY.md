# Fighter — gun-armed Tier 1 fighter (formerly the Light Assault Ship)

**Role:** The baseline shooter. Built as an AI enemy (`FighterBrain` decides, `EnemyMover` moves). While a level
rail (`EnemyPathMover`) owns its motion it falls back to the legacy weapon, so level 1 and the station's
reinforcements play as before.
**Fantasy / threat:** Bread-and-butter opposition. Manageable alone; dangerous in numbers.

> **Status (Phase 3, task t8b):** flies attack runs in both modes — a lead-in to the pass's start, a run past the
> player at a set lane with an aimed Pulse burst, a wide turn back in with a close Scatter spray when the nose comes
> on, a break-away and the next pass. Squad roles (t9), idle (t12) and level-1 migration (t16/t17) are still to come:
> level 1 keeps it on rails today. Task plan: `docs/plans/cmulwkar000btqj2x1e58sfd4/3-plan.md`.

---

## Stats

| Property | Value |
|---|---|
| HP | 60 (`fighter_config.tres`) |
| Damage | 20 contact / 8 per Pulse round on rails |
| Speed | `max_speed` 300, `acceleration` 700, `turn_rate` 1.8 rad/s (turn radius ≈ 167 px) |
| Sprite | `assault.png` placeholder `AnimatedSprite2D` (flipped 180° by `_rotate_sprite`); `sprite_forward_angle` PI/2 |
| Scene | `fighter.tscn` |
| Config | `fighter_config.tres` (flat, `@export_group`ed) |

---

## Scene

`Fighter` root, `Brain` (`FighterBrain`), `EnemyMover` (`constraint_mode = AUTO`), `StateLight`, the shared body /
`HurtBox` / `ContactHitBox` circle, and:

- `AimedAttack` + `ForwardAttack` — `AttackController`s, `driven_by_brain`, `enabled = false`;
- `AimedPool` (Pulse Round, 20) and `ForwardPool` (Scatter Round, 8) — **direct children of the root**:
  `BulletPool` resolves its container as `get_parent().get_parent()`, so a pool under a controller would carry its live
  bullets with the ship. Gated by `tests/integration/test_fighter.gd`.

There is no `AIStateMachine` and no `states/` folder.

Pool sizes are `max(AI need, rail need)` from `EnemyRounds.pool_size_for(...)`: the aimed burst (5 × ceil(4.67 s / 1.2 s))
is 20, the FORWARD rail cadence 12, the aimed rail cadence 7; the Scatter burst is 7, rounded to 8.

## Brain phases (`FighterBrain.Phase`)

`APPROACH, RUN_IN, EXTEND, TURN, REPOSITION, DISENGAGE` (t12 appends the idle phases). `phase_changed(new_phase: int)`
fires on every transition; `enter_phase()` is the one transition path.

**A pass** (epic §2.4.1) is a bearing `b` (the side it comes from), a run direction `u = −b` and a lane `l ⟂ u`. It
starts at `S = P̂ + b·standoff_radius + l`, on the pass line `P̂ + l + u·t`, so the closest approach equals `|l|`.
`P̂` is the player predicted 0.3–0.8 s ahead. `h` = the player's velocity direction above 40 px/s, else its facing;
in Assault always UP.

| `PassKind` | `b` | `l` |
|---|---|---|
| `FLANK_LEFT` | `left(h)` | `h·pass_offset` (160, ahead) |
| `FLANK_RIGHT` | `right(h)` | `h·pass_offset` solo; `h·(pass_offset + flank_lane_gap)` (260) role-shaped |
| `FRONTAL` | `h` | `right(h)·σ·pass_offset`, σ the fighter's own side, flipping each FRONTAL pass |

A solo fighter alternates `FLANK_LEFT`/`FLANK_RIGHT`, the first matching the side it is on. `forced_pass_kind` (≥ 0) is
the test seam and t9's hook for squad roles. The pass is re-derived every tick until RUN_IN and **latched from RUN_IN
entry to EXTEND's end**, the lead time included. Read-only fields for tests and t9: `pass_kind`, `pass_bearing`,
`pass_dir`, `pass_lane`, `pass_anchor` (this tick's P̂), `pass_start`, `seek_target`, `passes_done`.

- **APPROACH** — a `DubinsPath` lead-in to S, arriving pointing along the run heading `g` (`u`, plus the lane's
  sideways velocity for a moving player). Each 16 px sample must stay clear of where the player will be then, by
  `min(standoff_radius, |S − P̂|) − 1`. Inside that radius less 24 px it **breaches**: RUN_IN at once as a
  FRONTAL-shaped pass from the current bearing (lane ⟂ the new `u`, on the side it is drifting to). With no clear path
  it falls back to the epic's ring routing (a point on the standoff ring at most 90° round toward S). Handover within
  `start_tolerance` of S with the heading within 30° of `g`.
- **RUN_IN** — path following: the seek target is always `lookahead` (220) ahead of the fighter's projection on the
  pass line, with the lane's sideways velocity fed forward. Ends at the closest approach (`(P̂ − X)·u < 0`) or after
  `run_in_max` (4 s).
- **EXTEND** — holds its heading until ≥ 350 px from the player after ≥ 0.6 s, or at 1.5 s. In Assault it also ends
  when the point 0.3 s ahead would leave the corridor. The pass is counted here.
- **TURN** — the visible wide turn: back in toward the player at full rate (radius ≈ 167 px) until the nose is within
  `nose_cone_deg` (the snapshot, burst opportunity (b)), capped at a full circle. Then a break-away: the first arc of
  the REPOSITION path, with a 120 px clearance on that arc only; with no such path it peels straight away.
- **REPOSITION** — the rest of that Dubins lead-in to the next S, clear of `reposition_min_radius` (288); ring
  routing with no clear path. After `passes` passes, Open Space loiters at S for `regroup_seconds` (1.5 s) first.
- **Liveness** — APPROACH and REPOSITION each have a deadline of (the first plan's remaining length / `max_speed`) +
  `reposition_max` (3 s). On it the fighter starts the FRONTAL breach pass from wherever it is.
- **DISENGAGE** — Assault only, when the `EngagementBudget` (`engage_seconds`) expires or `passes` passes are done:
  releases the corridor constraint, raises the mover to `exit_speed`, curves toward the nearest edge of the projectile
  world rect and frees itself once outside it. Open Space never disengages. **Deferred** while a telegraph or burst
  runs, to the burst's end (worst case 0.3 + 4 × 0.10 = 0.7 s).

**Assault rules.** The corridor is `mover.constraint.inner_rect()`. A flank lane that would sit within the hull of the
corridor top flips behind the player; a FRONTAL lane too close to a side wall flips σ. S is clamped along the run axis
into the corridor shrunk by `2 × 1.1 × turn radius + hull`, so the lead-in loop fits. If the clamped run is shorter
than `min_run_length`, the pass comes from the other side. Flank passes are therefore horizontal sweeps across the
corridor. At the shipped 6 s budget one lateral pass with one AIMED burst fits, and the fighter leaves during EXTEND,
so **Assault never reaches a TURN snapshot and never fires FORWARD** today (a t16 tuning input).

**Moving player.** Against a player cruising at 200 px/s the fighter closes at only ≈ 100 px/s along its course, and
REPOSITION usually cannot reach a moving S before its deadline. The steady state is therefore a **breach-shaped pass
about every 15 s**, none of which touches the player (`test_a_cruising_player_still_gets_attack_runs_that_never_touch_it`).
A holding player gets a flank pass about every 10 s.

## Weapons (epic §2.4.2)

Ticked every AI tick before the phase logic. **Legs:** leg A = RUN_IN (+ EXTEND), leg B = TURN; at most one burst per
leg, and at least `min_burst_period` (1.2 s) between two burst starts.

- **Opportunities:** (a) any RUN_IN tick within `fire_range` (520); (b) the TURN tick the nose comes on the player.
- **Mode** (`select_weapon_mode(d)`): below `forward_range` (325) → FORWARD; at `forward_range + mode_hysteresis`
  (385) or more → AIMED; in between the last burst's mode (initially AIMED). A FORWARD choice with the nose off
  `nose_cone_deg` (12°) is skipped and not spent. The mode is latched for the burst; `weapon_mode_changed(mode: int)`
  fires only when it differs from the last burst's.
- **Burst:** `StateLight` CHARGING for `burst_telegraph` (0.3 s), then ARMED while `BurstClock` fires the latched
  controller once per shot due. AIMED: 3–5 Pulse rounds 0.10 s apart at a point locked when the burst starts (the
  player's lead point, blended by `aimed_accuracy`). FORWARD: 5–7 Scatter rounds 0.05 s apart along the nose, the nose
  (not the path) held on the player through the burst. Light OFF and `aim_point` released at the end.
- A natural cycle against a holding player fires AIMED at ≈ 500 px on the run and FORWARD at ≈ 220–300 px in the TURN.

## Rail fallback

`BaseEnemy.suspend_ai()` calls `FighterBrain.on_suspended()`, which hands `AimedAttack` back to self-timed fire from config
fields: `aim_mode == "FORWARD"` → a Pulse round every `rail_forward_interval` (0.3 s) at `rail_forward_speed` (420);
otherwise an aimed round every `fire_interval` (0.8 s) at `rail_aimed_speed` (250). Damage is `bullet_damage` (8).
`aim_mode` (spawn props `shoot_forward()` / `shoot_at_player()`, else the config default) is read **only** there; an AI
fighter ignores it.

## Config

Read the real fields from `fighter_config.gd` (groups: Movement, Geometry, Attack, Tactics, Rail). t8b added
`run_in_max` (4.0) and `regroup_seconds` (1.5) and moved `forward_range` 300 → 325 (the epic's K5 lever: the TURN
snapshot comes nose-on inside it, so it can be FORWARD). The pin
`turn_rate × max_speed ≤ acceleration` is asserted in `tests/integration/test_fighter.gd`.

## Spawn notes

- WaveBuilder method: `b.fighter()` — see `docs/enemy-roster.md`. Level 1 still gives it `.move()` (a rail) until its
  migration task.
- `.shoot_forward()` / `.shoot_at_player()` are rail-only inputs.

## Files

```
fighter/
├── ENEMY.md            ← this file
├── fighter.tscn
├── fighter.gd
├── fighter_brain.gd   (uses global/enemy_ai/dubins_path.gd)
└── fighter_config.gd / .tres
```
