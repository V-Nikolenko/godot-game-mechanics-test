# Bomber — area-denial bomb-dropper

**Role:** Drops persistent ordnance (gravity bombs, proximity mines, a pursuit bomb) that forces the player to reposition.
**Fantasy / threat:** A wide, slow, easy-to-hit target — but ignore it and what it leaves behind catches you. Every piece of ordnance can be shot down.

> **Build state (Phase 4, t10).** The scene, config, pools, rail fallback, Assault exit (t9) and the AI bombing runs
> (t10) are built. Still to come: the hub idle (t19), its own sprite (t11), level-1 migration off rails (t21).
> Plans: `docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md` §2.4; `docs/plans/cmuyk2qpr0089oa2xlih7xvmg/3-plan.md` (t10, with "As built").

---

## Stats

| Property | Value |
|---|---|
| HP | 150 (`bomber_config.tres`; the `.tscn` Health node is overwritten in `_ready()`) |
| Damage | 35 contact (`ContactHitBox`); ordnance blasts come from the config |
| Speed | `max_speed` 240 transit, `run_speed` 170 for the bombing run |
| Body | one 96 × 44 `RectangleShape2D`, shared by the body, `HurtBox` and `ContactHitBox` (the wings are shootable) |
| Sprite | `bomber.png` (placeholder; nose-down) |
| Scene / config | `bomber.tscn` / `bomber_config.tres` (flat `BomberConfig`) |

---

## Behaviour

- **Brain:** `BomberBrain` (`Phase { APPROACH, RUN, ESCAPE, REPOSITION, DISENGAGE }`, `enter_phase()` seam).
  - **Prediction:** `v̄`, an EMA of the player's velocity (τ `velocity_smoothing` 0.3 s, seeded from the first sample).
    The mine wall uses an **undamped** lead on the bomber's own timeline, `P̂ = P + v̄ (t_approach_left + min(c, mine_horizon))`,
    `c = (run_length / 2) / run_speed + mine_arm_delay + wall_margin + (trigger_radius + arc_depth) / |v̄|`, so the middle
    mine is armed `wall_margin` before the player reaches its trigger edge. Gravity / pursuit aim with the damped lead
    `P + v̄ · lead_factor · min(horizon, d / run_speed)`. Below `min_lead_speed` the aim is P.
  - **Choice** (start of each APPROACH): `|v̄| > mine_speed_max` → PURSUIT; `≥ mine_speed_min` → MINE; else `d < gravity_range`
    → GRAVITY; else PURSUIT; `choice_jitter` takes the next in the cycle MINE → GRAVITY → PURSUIT. `approach_cap` (6 s) also
    moves to the next kind.
  - **Bombing line:** MINE — centred on P̂, perpendicular to `v̄`, starting on the bomber's side of the player's track.
    GRAVITY — the bearing to P̂ turned up to `approach_angle` (35°), over P̂ at run coordinate `L / 2 + gravity_release_lead`.
    PURSUIT — the same angled line, but P̂ is abeam its end, `pursuit_launch_range` (300) to the side. The angled line takes
    the side with the shorter lead-in and narrows its angle until the lead-in has no loop (close in, a near-direct pass).
    Assault: the anchor is clamped into `inner_rect().grow(-drop_margin)`, the line clipped and slid to fit, and every
    rest point clamped (`wall_clamped()`).
  - **APPROACH:** a Dubins lead-in (radius = what the mover can hold at `max_speed`, ≈ 244 px) arriving on the line,
    re-planned from a fresh prediction every `replan_interval`; the mine wall's arrival time is the earliest one the
    lead-in can be flown in. The last stretch pursues the line itself. RUN entry: ≤ 32 px off, ≤ 12° off, before the middle.
  - **RUN** (StateLight ARMED, `run_speed` 170, frozen line): MINE — 3–5 mines 70 px apart around where the line crosses
    the player's track, bowed toward the player, each released 24 px past its rest point and ejected so it stops on it;
    GRAVITY — one bomb when P̂ is `gravity_release_lead` (120) ahead, inheriting the heading; PURSUIT — one bomb at the
    midpoint, launched at P̂. Ends at the line's end (stall guard `L / run_speed + 0.25 s`); anything undropped goes then.
  - **ESCAPE:** turns away from the player at `min(escape_turn_rate, acceleration / escape_speed)` for `escape_time`.
  - **REPOSITION** (Open Space): orbits at `standoff` for 1.0–1.8 s, then APPROACH again.
  - **Assault:** one run per life (ESCAPE → DISENGAGE). Budget expiry mid-RUN finishes the run first, then DISENGAGE.
- **Mover:** `EnemyMover` AUTO (`max_speed` 240, `acceleration` 260, `max_turn_rate` 1.6).
- **Ordnance:** `Bomber.drop(kind, dir, speed, target_point)` takes it from `GravityBombPool` / `MinePool` / `PursuitBombPool`, root children with `persist_after_owner_death = true`, so a bomb or mine already dropped outlives the bomber. Pool sizes follow `EnemyOrdnanceScenes.pool_size_for()` (gated by `test_bomber.gd`).
- **Rail fallback:** while `is_ai_suspended()`, `Bomber._process` drops a gravity bomb `Vector2.DOWN` at `rail_bomb_speed` (120) every `rail_bomb_interval` (1.2 s), aimed `rail_bomb_range` below. Nothing writes motion.
- **Death / scoring:** `BaseEnemy` emits `died`, awards `score_value` 80.

---

## Spawn notes

- WaveBuilder method: `b.bomber()` — see `docs/enemy-roster.md`. Level 1 still spawns it on a rail (`.move(b.straight(...))`).

## Tests

`tests/integration/test_bomber.gd` (t9 structure and rails; t10 placement against P̂ and against the live player, line stand-still, choice rule, angled lines, escape, phase loop, light, edge clamp, budget deferral, the real-physics blast outcome and the WaveManager attack-in-budget row); the `Bomber` cases in `test_enemy_dual_mode.gd`; the ordnance itself in `test_enemy_ordnance.gd`.

---

## Files

```
bomber/
├── ENEMY.md            ← this file
├── bomber.tscn
├── bomber.gd
├── bomber_brain.gd
└── bomber_config.gd / .tres
```
