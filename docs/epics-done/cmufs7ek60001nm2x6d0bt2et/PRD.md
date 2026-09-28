# Enemy rework, phase 2: Swarm Drone, Razor Drone and squad roles — PRD

## The ask

> Enemy rework, phase 2 of 20: the first roster epic on the phase-1 mode-neutral enemy AI
> architecture. It delivers the two contact-damage drones Tier 1 of the idea calls for and builds
> the smallest squad layer they need. The **Swarm Drone** replaces both the Kamikaze Drone and the
> Open Space `PatrolDrone`. It uses lightweight separation/alignment/cohesion steering with
> per-drone phase offsets, then a coordinated ram: wide orbit, a 0.4–0.8 s prediction, an
> unoccupied side, an acceleration burst, and an overshoot that allows one second pass instead of
> dying on a miss. A `SquadController` assigns lead attacker, left/right flank and rear-orbit roles
> and reassigns them when the lead dies, so groups of drones attack together without scripted
> paths. The **Razor Drone** evolves the Drone Interceptor phase 1 ported. It adds orbit reversal,
> a fake dash that brakes and attacks from the opposite side, a real dash with a stronger telegraph
> than the fake, a pulse shot after a missed dash, and an anchor-based idle orbit (drift, brake,
> reverse) that hands over smoothly to combat once it perceives the player. Contact damage becomes
> an explicit per-enemy profile (none, collision, ramming during a committed state only,
> explosive), so a drone only rams hard while it is attacking. In Open Space, `SectorHub`'s ambient
> `PatrolDrone` spawn becomes a Swarm Drone squad plus a Razor Drone around the same anchor, and
> `PatrolDrone` is deleted. In Assault, the level-1 spawns of the Kamikaze Drone and the Drone
> Interceptor switch to the new enemies: their spawn layouts are kept, they run under the phase-1
> corridor constraint instead of `.move()` paths, and wave timing is preserved. The Bonus Drone
> stays exactly as it is, as the Assault reward target. Both enemies get new strict top-down
> sprites (24–36 px and 40–56 px) that follow the readability rules: silhouette, faction accent and
> one gameplay light per state. Deterministic tests run the same behaviour spec in both harnesses:
> prediction, orbit radius, dash direction, fake-dash versus real-dash, overshoot and second pass,
> role reassignment and formation recovery. The existing invariant gates must cover the new scenes.
>
> **Scope of this phase** (from the idea's phase split): IDEAS §5.1 Swarm Drone in full (including
> group behaviour and the Assault adaptation); §5.2 Razor Drone in full; §3.2 the `spiral`/
> `corkscrew` primitives the swarm needs; §16 contact-damage profiles None/Collision/Ramming/
> Explosive (Armour is left to the Ram Corvette phase); §17 and §35 only as a `SquadController` with
> role assignment/reassignment for drones; §18.5 Razor idle plus the generic anchor-idle → combat
> handover it needs; §2 and §38 retiring the Kamikaze Drone and `PatrolDrone`, keeping the Bonus
> Drone; §21–23 readability rules and sprites for these two enemies only; §40 movement/behaviour
> tests in both modes; §41 Phase 2 items 1–2. Plus: `SectorHub`'s ambient spawn replaced by these
> enemies (not the `EncounterDirector`, which is Phase 13), and the level-1 Kamikaze/Interceptor
> spawns migrated to spawn layout + corridor constraint.

### Original idea

> Analyze the files with ideas, add improvements to it if you have any great ideas, research and
> create a plan to implement ALL those ideas. Be sure, to add in the review all changes you
> proposed at the top of the document, if you have any. `ENEMIES_OPEN_SPACE_REWORK_IDEAS.md` — file
> with all ideas proposed. `ENEMIES.md` — current implementation.

Attached documents, preserved verbatim in the repo:
`docs/ideas/cmufkkgmx0001o02y6bnf52bq/ENEMIES_OPEN_SPACE_REWORK_IDEAS.md` and
`docs/ideas/cmufkkgmx0001o02y6bnf52bq/ENEMIES.md`. The epic's approved plan
(`docs/plans/cmufs7ek60001nm2x6d0bt2et/3-plan.md`) already reflects them — see phase 1's PRD for how
the original idea was split into 20 phases in the first place.

### Human feedback (plan review, verbatim intent)

Three rounds, all preserved in `docs/plans/cmufs7ek60001nm2x6d0bt2et/4-review.md`:

- **Round 1 — `CHANGES_REQUESTED`.** Four blocking findings: the `EXPLOSIVE` blast as written could
  never actually hit the player (freed with its owner, parented to a plain `Node` at the canvas
  origin, armed for a frame that likely never steps — B1); `EnemyMover.max_turn_rate` does not bend
  a path, only the sprite, so both drones' "overshoot and curve away" specs described a straight
  line (B2); nothing owned the Swarm's hub idle — no task depended on the `AnchorIdle` primitive,
  no config fields, no tests (B3); and task t8 tried to be four tasks at once — a shared component,
  a new enemy, a ~10-state brain and full squad integration, too large to finish and verify in one
  session (B4). Twelve non-blocking notes (N1–N12) covered a missed deadline term, an
  under-specified C3 escalation threshold, `SquadController` API gaps, a phase-offset test that
  could not fail on its own, underspecified feint geometry, missing task ordering on shared files, a
  grep that would catch `.claude/`, an unspecified `StateLight` texture, an inner-rect test that
  could not fail mid-screen, an overstated Δv-bound guarantee, a hub patrol ring too close to the
  hub's own pickups, and a `PatrolDrone` sweep too broad for `docs/`.
- **Round 2 — `CHANGES_REQUESTED`.** All round-1 blocking findings and ten of twelve non-blocking
  ones were fixed; two new, purely numeric contradictions surfaced from independently re-derived
  arithmetic (a headless script over `Level1Director._build_sections()`, a step-for-step replay of
  `EnemyMover.step()`'s velocity math, and the real node positions in `sector_hub.tscn`): the
  Swarm's overshoot config could not reach the ≥ 60° turn its own acceptance test demanded (B5,
  the braking phase eats most of the turn window), and the Razor's hub anchor sat within
  `perceive_radius` of a row of weapon-unlocker pickups the plan's own manual check had missed
  (B6).
- **Round 3 — `APPROVED`.** Both numeric fixes (raised `braking`, raised `patrol_ring_radius`)
  verified against the same independently re-derived arithmetic.

## Player-facing goal

Today: Kamikaze Drones fly fixed straight/sine rails and lose to one sidestep; the Drone
Interceptor's only trick is orbit-then-dash, learned in one encounter; Open Space has three grey
squares that drift forever and never attack. After this phase: Swarm Drones fly and attack as a
*group* — a lead winds up (yellow light) and rams where the player is *going* (red light), two
flankers cut in from the sides when it commits, the rest circle and wait, and a new drone takes
the lead the instant the old one dies; a miss curves the drone round for one more pass. The Razor
Drone circles, sometimes reverses, sometimes fakes a dash (only the real dash shows the white
"commit" flash), survives a miss, fires one pulse shot and curves back. Touching either drone only
hurts while it is actively attacking; a Swarm Drone that hits you (or is shot while armed)
explodes. In Open Space, the hub has a Swarm squad and a Razor Drone idling on patrol, clear of the
spawn point, the planets and the pickups — fly close and the whole squad notices and turns to
fight together. In Assault level 1, the drones arrive at the same moments and places as before,
now fight as squads inside the corridor, and leave in time for the level to move on. The Bonus
Drone is unchanged.

## Scope

**In scope:** the Swarm Drone (new) and the Razor Drone (the Drone Interceptor renamed and
evolved), both flying in both modes; `ContactProfile`/`ContactBlast` (None/Collision/Ramming/
Explosive); `SquadController` (role board, reassignment, spawn-side squad wiring for Assault
waves and the Open Space hub); `AnchorIdle` (generic idle → combat handover) and its Razor and
Swarm-squad uses; `EngagementBudget` and the Assault world-rect exit rule; `StateLight`; the new
`Steering` primitives (`spiral`, `corkscrew`, `formation_slot`, `separation`, `alignment`,
`cohesion`, `clamped_lead_time`, `turn_toward`); dedicated top-down sprites for both drones;
retiring `KamikazeDrone` and `PatrolDrone`; migrating level 1's Kamikaze/Interceptor spawns and the
Open Space hub's ambient spawn onto the new enemies; deterministic dual-mode tests for both
drones' full behaviour specs; new invariant gates (roster completeness, the level-1 exit deadline
and concurrency ceiling, the hub clearance check).

**Explicitly out of scope (deferred to named later phases):** the Armour contact-collision profile
and real line-of-sight (Phase 4); squad messages beyond shared engagement and idle profiles for
any family besides these two drones (Phase 14); the Open Space `EncounterDirector`, leash/search
and hub-patrol respawn (Phase 13); taking any other level-1 enemy off rails, or retiring
`SineMovement` and friends (Phase 15); `BulletPool`'s injectable grandparent container (deferred a
second time — Phase 5); difficulty tiers (Phase 16); enemy audio (no SFX pipeline exists; Phase
17's readability pass, if the owner wants it); the Fighter and Gatling Interceptor (Phase 3); every
non-drone family's readability/checklist audit (Phase 17).

## Constraints

- **View rule:** `assault/` and `open_space/` are strict top-down orthographic — both drones'
  sprites were generated under the `pixel-art-generation` skill (`view: "high top-down"`,
  `isometric: false`).
- **Coordinate space:** level-1 waves stay authored in 640×360 design units; nothing in this phase
  pre-multiplies `ArenaCamera.WORLD_SCALE`.
- **Single-writer rule:** an `EnemyMover`-carrying enemy's `velocity`/`rotation`/`move_and_slide()`
  stays the mover's alone; `SquadController` and `AnchorIdle` are read-only role/state boards a
  brain queries, never a second writer.
- **Reuse requirements:** `DefenseProfile`'s shape, `AttackController.fire_now()`, `BulletPool`,
  `TargetInfo`, and the phase-1 dual-mode test harness all carry over unchanged in mechanism.
- **Gate:** every existing invariant test stays green, `bash /agent/verify.sh` must pass, and
  `scripts/check-test-leaks.sh` must report no leaks after every task that adds an `await`-based
  test.
- **Process:** implementation of a large task starts only on `VERDICT: APPROVED`; this epic's plan
  needed three rounds before that verdict.

## Open questions at the time, and how each was resolved

| Question | Resolution |
|---|---|
| Does an armed drone's blast actually reach the player? | No, as first designed (B1) — the blast is now a separate node (`ContactBlast`) parented into the owner's *parent*, at the owner's position, staying alive on its own physics-frame counter, proven against a real player `HurtBox`. |
| Does a capped turn rate bend an AI enemy's path? | No (B2, D7) — `EnemyMover.max_turn_rate` only turns the sprite. Any curved path is a brain-side `Steering.turn_toward()` request built from the actor's current velocity every tick, now the standing rule for every future curving enemy. |
| Who owns the Swarm squad's Open Space idle? | Split into its own task (t8d, B3), with its own config fields, its own spawn-geometry proof and its own squad-wide engagement tests. |
| Was task t8 the right size? | No — split into t8a (`StateLight`), t8b (solo ram cycle), t8c (squad behaviour) and t8d (hub idle), each independently reviewable (B4). |
| Can the Swarm's overshoot actually turn ≥ 60°? | Not at the round-1 numbers (B5) — `braking` raised from 500 to 900 so the curve clears the deceleration phase the original config test ignored. |
| Is the Razor's hub anchor really clear of every hub interactable? | Not at 1000 px (B6) — a full sweep (not a hand-picked pickup row) found a closer weapon-unlocker pickup; `patrol_ring_radius` raised to 1300. |
| Should level 1's difficulty spike (drones now live ~8.3 s instead of ~3.5 s) trigger a lever? | Computed in advance (§5 C3): three pre-approved levers, in order, with fixed escalation thresholds. Measured against the shipped build, no lever was needed — see the DECISIONS "Phase 2 - as built" section. |
| Evolve the Drone Interceptor in place, or a new directory? | Evolve in place, renamed via `git mv` in its own task (t9) with no behaviour change, so a failure there is attributable before any real combat change lands. |
