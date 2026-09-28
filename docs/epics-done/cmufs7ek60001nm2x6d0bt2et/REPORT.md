# Enemy rework, phase 2 — completion report

Epic `cmufs7ek60001nm2x6d0bt2et`. Plan directory: `docs/plans/cmufs7ek60001nm2x6d0bt2et/`
(`1-context.md`, `2-research.md`, `3-plan.md` revision 2, `4-review.md` — three rounds). Six tasks
ran their own escalated-track plan directories (`docs/plans/cmuj4y8r…`, `cmuj4y8s…`); each is named
under its task below. The idea's running decision log is
`docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md`, whose "Phase 2 - as built" section (appended
by this dossier's own task) is the fast-reference summary later phases should read first.

## What was built

Per build-sequence task (`3-plan.md` §3, `tasks.json`):

1. **t1-pin-drone-spawns** — characterization before anything moved:
   `tests/integration/test_level1_drone_spawns.gd` pins every level-1 Kamikaze/Interceptor spawn
   (trigger, offset, delay, formation, 14 drone formations counted from
   `Level1Director._build_sections()` data, not text) and the station's BOTTOM reinforcement
   squad; the legacy peak-concurrency numbers (14/6/5 per section) are computed, not hand-copied.
   Roster **completeness guards** added to `test_enemy_contact_damage.gd` and
   `test_contact_hitbox_geometry.gd`, matching `test_enemy_hurtbox_geometry.gd`'s existing pattern.
2. **t2-steering** — `global/enemy_ai/steering.gd` gains `spiral`, `corkscrew`, `formation_slot`,
   `separation`, `alignment`, `cohesion`, `clamped_lead_time` and `turn_toward` (the brain-side
   curve primitive, D7/B2 — see *Decisions* below), each pure and unit-tested with its boundary
   cases.
3. **t3-contact-profile** — `global/components/contact_profile.gd` (`ContactProfile`) and
   `contact_blast.gd` (`ContactBlast`): NONE/COLLISION/RAMMING/EXPLOSIVE contact modes,
   `BaseEnemy.suspend_ai()` arms the profile, and a blast that survives its owner's death (fixed
   from round-1 B1 — see *Decisions*). Proven against a real player `HurtBox` in
   `tests/integration/test_contact_blast_damage.gd`.
4. **t4-squad-controller** — `global/enemy_ai/squad_controller.gd` (`SquadController`): an
   event-driven, no-clock role board with full-recompute assignment, weak membership, side claims
   and shared engagement state. `tests/unit/test_squad_controller.gd`.
5. **t5-wave-squads** — `WaveBuilder.SpawnConfig.squad(id)` / `SpawnEntryResource.squad_id`;
   `WaveManager` resolves a squad key into a `WeakRef`-held board, set on the entity before
   `add_child()`. `tests/integration/test_wave_squads.gd`.
6. **t6-engagement-exit** — `global/enemy_ai/engagement_budget.gd` (`EngagementBudget`),
   `EnemyMover.release_constraint()`, `MovementConstraint.inner_rect()`; the §2.6 deadline formula,
   later repointed at real configs in t8b.
7. **t7-anchor-idle** — `global/enemy_ai/anchor_idle.gd` (`AnchorIdle`): the generic
   idle/notice/combat/return handover with hysteresis, `hold_combat` and `force_notice()`.
   `tests/unit/test_anchor_idle.gd`.
8. **t8a-state-light** — `global/components/state_light.gd` (`StateLight`): a code-built radial
   texture, OFF/ARMED/CHARGING/COMMIT, `blink_once()`. `tests/unit/test_state_light.gd`.
9. **t8b-swarm-solo** *(escalated, own plan `cmuj4y8rh0070p52xk6vzfvbe`, two review rounds)* — the
   Swarm Drone as a squad of one: `assault/scenes/enemies/swarm_drone/` scene, config, brain
   (APPROACH → CLOSE_IN → WINDUP → BURST → OVERSHOOT → one more pass → REJOIN, plus DISENGAGE in
   Assault). `tests/integration/test_swarm_drone.gd`.
10. **t8c-swarm-squad** *(escalated, own plan `cmuj4y8rj0074p52xqmin24gu`, two review rounds)* —
    squad behaviour: FORM roles, the flank pincer opened by the lead's `attack_window_open`, side
    claims, role reassignment mid-pass, `rear_engage_seconds`.
11. **t8d-swarm-idle** *(own task `cmuj4y8rm0078p52x5qa7v6fo`)* — the hub idle: `AnchorIdle` per
    member around a shared `patrol_anchor`, `SquadController.set_engaged`/`is_engaged` for
    squad-wide wake/return.
12. **t9-razor-rename** — `git mv drone_interceptor → razor_drone`, classes and
    `WaveBuilder.RAZOR_DRONE`/`razor_drone()` renamed, no behaviour change.
13. **t10-razor-combat** *(escalated, own plan `cmuj4y8rr007gp52xxs8dec5s`, two review rounds)* —
    the evolved brain: `ENTER → ORBIT ⇄ REVERSE → (FEINT | WINDUP) → DASH → OVERSHOOT → RETURN`,
    plus DISENGAGE in Assault; RAMMING `ContactProfile`; a post-miss pulse shot; the corridor turned
    **on** (`constraint_mode = AUTO`) for the first time since the phase-1 port.
14. **t11-razor-idle** *(own task, plan §2.8.4)* — `IDLE_ORBIT`/`IDLE_BRAKE`/`IDLE_REVERSE`/
    `IDLE_BOOST` legs on `AnchorIdle`, no `SquadController` (a lone drone).
15. **t12-art-swarm**, **t13-art-razor** — dedicated top-down sprites (32×32, 48×48) generated
    under the `pixel-art-generation` skill, wired into each scene with a matching `sprite_forward_
    angle` and a shared collision-shape scale.
16. **t14-swap-kamikaze** — `WaveBuilder.DRONE` points at `swarm_drone.tscn`; every existing
    `.move()` drone line (including the station's BOTTOM squad) now spawns a rail-driven, armed
    Swarm Drone; `kamikaze_drone/` deleted.
17. **t15-level1-ai** *(escalated, own plan `cmuj4y8s30080p52xxk0ioy1n`, two review rounds)* —
    `.move()` removed from every level-1 `b.drone()` line; formations and tagged loose waves become
    squads (`squad(&"w<n>")`); the C3 concurrency check and a real-`WaveManager` exit integration
    case.
18. **t16-hub-patrol** *(own task `cmuj4y8s70084p52x8g2hl0tm`)* — `SectorHub._spawn_patrol()`: a
    Swarm squad and a Razor Drone on fixed bearings, `patrol_drone.{gd,tscn}` deleted.
19. **t17-docs** *(this task)* — module docs, `PROJECT.md` conventions, `CLAUDE.md`'s test-gate
    paragraph, both `ENEMY.md` files (verified current, one stale sentence fixed — see *Decisions*),
    the idea's "Phase 2 - as built" section, and this dossier.

Every task's commit is on `agent/auto-dev`; `git log` is the authoritative commit list.

## How it was verified

- `bash /agent/verify.sh` (import, headless boot, full GUT suite) was green after every task,
  including this one; `scripts/check-test-leaks.sh` was run after every task that added an
  `await`-based test.
- **New unit coverage:** `test_steering.gd` (extended), `test_contact_profile.gd`,
  `test_squad_controller.gd`, `test_engagement_budget.gd`, `test_anchor_idle.gd`,
  `test_state_light.gd`.
- **New integration coverage:** `test_contact_blast_damage.gd`, `test_wave_squads.gd`,
  `test_engagement_deadline.gd`, `test_swarm_drone.gd`, `test_razor_drone.gd` (renamed from
  `test_drone_interceptor.gd`), `test_enemy_dual_mode.gd` (extended), `test_level1_drone_spawns.gd`
  (extended with the C3 ceiling), `test_level1_drone_exit.gd`, `test_sector_hub_patrol.gd`,
  `test_station_reinforcements.gd` (extended for the rail Swarm Drone).
- **New invariant gates** (all documented in `CLAUDE.md`'s test-gate paragraph): the roster
  completeness guards in `test_enemy_contact_damage.gd`/`test_contact_hitbox_geometry.gd`; the
  level-1 exit deadline in `test_engagement_deadline.gd`; the level-1 concurrency ceiling inside
  `test_level1_drone_spawns.gd`; the hub clearance check in `test_sector_hub_patrol.gd`.
- **The pre-existing invariant gates all stayed green throughout:** config isolation (roster floor
  10 held — a net 0 change, `-kamikaze_drone +swarm_drone`), contact-damage, contact-hitbox and
  hurtbox geometry, sprite transparency (floor 12 held), player-bullet lifetime, signal arity
  (`contact_made`, `detonated`, `role_changed`), the single-writer gate (both new brains and the
  squad board), project load integrity, UID integrity, the space-station family and the Bonus
  Drone's own pins.
- **What the gate cannot verify:** see *Known gaps*.

## Decisions and course changes

- **Plan review, round 1 (`CHANGES_REQUESTED`).** B1: the `EXPLOSIVE` blast as first designed could
  never land (freed with its owner, positioned at the canvas origin, armed for a frame that likely
  never steps) — fixed with `ContactBlast`, a separate node parented into the owner's *parent* at
  the owner's position, alive on its own physics-frame counter, proven against a real player
  `HurtBox`. B2: `EnemyMover.max_turn_rate` only turns the sprite, never the path — fixed by adding
  `Steering.turn_toward()` and making every curving enemy build its own bounded brain-side request
  from its *current* velocity each tick (D7). B3: nobody owned the Swarm's hub idle — split into
  its own task, t8d. B4: task t8 was really three-to-four tasks — split into t8a/t8b/t8c/t8d.
  Twelve non-blocking notes (N1–N12) were folded into the revision: the deadline formula gained the
  last wave's spawn delay and the acceleration ramp; the C3 escalation thresholds and levers were
  computed and fixed in advance rather than decided later; `SquadController` gained `leave()` and
  `update_target()`; the phase-offset test was rewritten with a same-seed control; the Razor's feint
  geometry was fully specified; task ordering was added for two same-file collisions; the
  `PatrolDrone`-sweep grep excluded `.claude/`; `StateLight`'s texture was specified as a code-built
  gradient; the inner-rect test case was moved off dead centre; the Δv-bound guard was reworded from
  a guarantee to a guard; the hub patrol ring moved to fixed bearings with a per-group clearance
  test; the `PatrolDrone` sweep was scoped to `.gd`/`.tscn`/`.tres`.
- **Plan review, round 2 (`CHANGES_REQUESTED`).** Every round-1 finding held under independent
  re-derivation (a headless script over `Level1Director._build_sections()`, a step-for-step replay
  of `EnemyMover.step()`'s velocity math, a real `GradientTexture2D.get_image()` probe, and the real
  node positions in `sector_hub.tscn`) — except two new numeric contradictions the same re-derivation
  surfaced: B5, the Swarm's round-1 overshoot config could not reach its own ≥ 60° turn requirement,
  because the config test's steady-state inequality ignored the deceleration phase that eats most of
  the turn window (fixed by raising `braking` to 900, verified to turn ~76°); B6, the Razor's hub
  anchor at 1000 px sat within `perceive_radius` of a weapon-unlocker pickup row the plan's manual
  check had missed (fixed by raising `patrol_ring_radius` to 1300, and re-deriving the clearance
  table from every interactable in the scene rather than one hand-picked row).
- **Plan review, round 3 (`APPROVED`).** Both fixes verified against the same independently
  re-derived arithmetic; no further findings.
- **Deviations found live during implementation**, each recorded in full in the idea's `DECISIONS.md`
  "Built in tX" notes and indexed in its "Phase 2 - as built" section — summarized here:
  - `ContactBlast` parents itself via a deferred call on the blast, not on the container, so an
    already-freed container fails safely (t3).
  - `SquadController` assignment is a **full recompute** on every join/leave/release, not an
    incremental fill — the only shape where "LEAD is whoever is closest" is a standing property
    rather than a one-time election, superseding round-1 N14's literal suggestion (t4).
  - Three Swarm-solo config numbers differ from the plan's own §2.7 table (`braking` 900,
    `max_turn_rate` 10, `corkscrew_amplitude` 120 px/s @ 0.6 Hz), all found by measuring the actual
    curve/swing rather than trusting the table (t8b).
  - Two Swarm-squad config numbers and two board-API additions differ from the plan (`rear_orbit_
    speed` 0.55 not 1.4, `phase_offset` bounded ±0.35 rad, the board-owned `rear_ring_angle`, the
    generalized attack-window-close rule) (t8c).
  - The Razor's feint geometry, orbit-hold speed, reversal cooldown, side-lane check point, and
    idle-light state all differ from the plan's literal wording, each found by measuring the
    drone's *actual* orbit radius and dash geometry rather than the plan's assumed numbers (t10).
  - The Razor idle's `home_radius` equals `idle_radius` itself, not `idle_radius + jitter` as the
    round-2 review's own estimate assumed (t11).
  - Level 1's C3 concurrency check needed **no lever** — every section landed inside the
    pre-approved ceiling on the shipped configs (t15).
  - The hub's `patrol_ring_radius` needed a second correction, from 1000 (plan) to 1300 (this
    phase, not the plan's already-corrected 1000 from round 2 — a full interactable sweep found a
    closer pickup the manual round-2 check had also missed) (t16).
  - `swarm_drone/ENEMY.md`'s opening line still claimed the swap and hub replacement were "later
    tasks" and that "nothing spawns it in a level yet" — stale since t14/t15/t16 landed; corrected
    in this task (t17).
- **No plan was rejected outright.** All three rounds ended in a path forward.

## Numbers

| Value | Where used | Origin |
|---|---|---|
| Swarm `max_health`/`collision_damage`/`score_value` | 30/30/10 | Kamikaze parity (existing balance, carried over). |
| Swarm `braking` | 900 px/s² | Round-2 review B5: the config's own ≥ 60° overshoot-turn acceptance case fails below this once the deceleration phase is accounted for; verified to turn ~76° at this value. |
| Swarm `max_turn_rate` / `corkscrew_amplitude` | 10 rad/s (sprite only) / 120 px/s @ 0.6 Hz | Measured against the actual 0.4 s wind-up swing and a 32 px hull (t8b) — the plan's 5 rad/s and 60 px/s @ 1.5 Hz produced an invisible ~6 px swing. |
| Swarm `windup_seconds` | 0.4 s | Research finding 3's 0.34 s telegraph floor, rounded up. |
| Swarm `lead_time_min`/`max` | 0.4 s / 0.8 s | IDEAS §5.1, confirmed by research finding 5 (distance-scaled prediction). |
| Swarm `engage_seconds` / `exit_speed` | 5.5 s / 320 px/s | §2.6: legacy on-screen time (~3.5 s) + one ram cycle (1.65 s), rounded up; `exit_speed` raised from round-1's 260 to clear the deadline. |
| Swarm `rear_orbit_speed` | 0.55 rad/s | t8c (D1): the plan's 1.4 rad/s × 260 px ring exceeds `max_speed` (220), so a REAR could never hold the ring. |
| Swarm blast `blast_radius`/`blast_damage` | 48 px / 15 | Judgement — under 2 hull widths, half the contact damage, tunable in `.tres` if it plays unfair (open question 1). |
| Razor `acceleration`/`braking`/`max_turn_rate` | 900 / 700 / 6 rad/s | The re-pin (D5) turning the corridor on for the first live combat use since the phase-1 port. |
| Razor `orbit_correct_speed` | 260 px/s | t10: raised from the plan's value so the orbit actually holds ≈ 119 px (measured 82–110 px at the lower value, which broke the feint's clearance geometry). |
| Razor `feint_clearance_px` | 70 px | t10: replaces the plan's 25° offset once the *measured* orbit radius showed a 25° lunge would pass through the player's hull. |
| Razor `overshoot_turn_rate`/`overshoot_speed` | 3.0 rad/s / 200 px/s | 3.0 × 200 = 600 ≤ `acceleration` 900 (the config test's steady-state pin). |
| Razor `engage_seconds` | 9.0 s [judgement] | One full combat cycle plus a second; Razors ship only in `deep_space` (a `DURATION` section), so the `ENEMIES_CLEARED` deadline never applies to one in practice — pinned as a boundary case regardless. |
| Level-1 C3 escalation ceiling | ≤ 2.0× attack-capable, ≤ 2.5× all-drones, per section | Pre-approved in the plan before implementation (round-1 N2); measured result 1.21–1.40× / 1.50–2.00×, no lever pulled. |
| Hub `patrol_ring_radius` | 1300 px | t16: raised twice from the plan's original 900 (round-1) → 1000 (round-2 B6) → 1300 (this phase, full interactable sweep). |
| Sprite sizes | Swarm 32×32, Razor 48×48 | IDEAS §21–23's 24–36 / 40–56 px bands; research finding 9 (size spread + shape-first readability). |

## Known gaps

- **Nobody has played either drone's finished behaviour by hand.** The gate proves the state
  machines, the squad reassignment, the deadline arithmetic and the sprite geometry — it cannot say
  whether the ram telegraph, the feint, or the squad pincer *feel* right at real Assault speed.
  t8b/t8c/t10/t15/t16 each ended their runs with a written hand-playtest checklist; none has been
  run by a human yet.
- **Level-1 density is a gated floor, not a felt result.** Drones now live ~8.3 s under AI instead
  of ~3.5 s on a rail, and the C3 ceiling (≤ 2.0×/2.5× the legacy peak) is a safety net against a
  spike, not a claim that the new density plays well. The DECISIONS "Phase 2 - as built" section
  records the exact measured ratios per section for a human reviewing feel to start from.
- **`StateLight` readability at speed is unverified.** The red/yellow/white cues are asserted by
  state and by alpha cap in isolation; nothing headless can say whether they read in the middle of
  a fast Assault section with other bullets and effects on screen.
- **The hub patrol's clearance is geometric, not experiential.** `test_sector_hub_patrol.gd` proves
  every planet, pickup and the player's spawn point clears each group's perception radius on the
  *current* scene layout — it says nothing about whether a player dwelling at a mission trigger or
  browsing the pickup bench feels safe, which is exactly what t16's playtest checklist item asks a
  human to confirm (the pickups sit closer to the Razor's ring than the planets do).
  `EncounterDirector` (Phase 13) will need an equivalent live check once patrols are no longer a
  static scene layout.
- **No enemy audio exists anywhere in the project.** Both drones' telegraphs are visual-only by
  design (out of scope, §8/§7 of the plan) — the readability pass in Phase 17 is where an SFX
  pipeline, if the owner wants one, would land.
- **The Explosive blast's fairness is an open question the owner may want to weigh in on** (plan
  §8, open question 1): an armed Swarm Drone shot at point-blank range detonates, which is by
  design (it is the blast's real gameplay value against a committed drone) but has not been played.
  `blast_damage` is a `.tres` field if it needs tuning to zero.

## Links

- Plan directory: `docs/plans/cmufs7ek60001nm2x6d0bt2et/` (`1-context.md`, `2-research.md`,
  `3-plan.md` revision 2, `4-review.md` — three rounds, `tasks.json`).
- Escalated task plan directories: `docs/plans/cmuj4y8rh0070p52xk6vzfvbe/` (t8b),
  `docs/plans/cmuj4y8rj0074p52xqmin24gu/` (t8c), `docs/plans/cmuj4y8rr007gp52xxs8dec5s/` (t10),
  `docs/plans/cmuj4y8s30080p52xxk0ioy1n/` (t15).
- Idea folder and decision log: `docs/ideas/cmufkkgmx0001o02y6bnf52bq/`
  (`ENEMIES_OPEN_SPACE_REWORK_IDEAS.md`, `ENEMIES.md`, `DECISIONS.md` — see its
  "Phase 2 - as built" section, which indexes every deviation above by task).
- Per-entity docs: `assault/scenes/enemies/swarm_drone/ENEMY.md`,
  `assault/scenes/enemies/razor_drone/ENEMY.md`.
- Epic id: `cmufs7ek60001nm2x6d0bt2et`. Phase 1's dossier: `docs/epics-done/cmufklb100001p92xs1ey2fb1/`.
  Phase 3's epic (Fighter, Gatling Interceptor and the bullet family) is next in the chain.
