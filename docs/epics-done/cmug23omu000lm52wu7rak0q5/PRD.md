# Enemy rework, phase 7: mines, minefields and the Mine Layer — PRD

## The ask

> Enemy rework, phase 7 of 20. This phase adds persistent area denial. The player has to remember where the unsafe regions are, and enemies avoid them through phase 6's hazard
> perception. Mines become one shared family: proximity, drifting, slow homing, chain (sets off nearby mines), pulse/boost-disruption (briefly cuts boost efficiency) and EMP. The EMP mine
> applies its disruption through the same hook the phase 9 EMP Pulse uses, and here it may be only an interface stub. Mines use phase 4's persist_after_owner_death lifetime rules and
> phase 5's explosion radius. Standalone mines and authored minefields can be placed as environment structures rather than invisible colliders. The Mine Layer enemy (80–112 px) flies
> sideways across an encounter, leaving curved or zig-zag trails. It builds unsafe regions gradually instead of filling the screen, and in Open Space an area the player comes back to
> stays dangerous. It reuses phase 4's intercept-point selection where that helps. In Assault the same logic is clamped to the corridor. The Mine Layer is added to existing Assault waves
> and to the hub's ambient spawn, and it owns its sprite, trail and mine art. Tests in both harnesses cover each mine type's trigger, chain propagation, boost-disruption application and
> trail placement.

**Scope:** `ENEMIES_OPEN_SPACE_REWORK_IDEAS.md` §6.3 Mine Layer (all of it, including the Open Space behaviour); §6.9 Mine/Minefield (all variants: proximity, drifting, chain, EMP,
boost-disruption); §11.4 Mine; §18.6 mines as structures; §21–23 readability and sprites for the Mine Layer and mines; §40 mine tests in both modes.

**Original idea:** "Analyze the files with ideas, add improvements to it if you have any great ideas, research and create a plan to implement ALL those ideas. Be sure, to add in the
review all changes you proposed at the top of the document, if you have any. ENEMIES_OPEN_SPACE_REWORK_IDEAS.md - file with all ideas proposed. ENEMIES.md - current implementation."

**The epic's tasks (titles):** gate room recovered (t1); the mine family and placed mines (t2); drifting and homing mines (t3); chain mines (t4); boost disruption on both players (t5);
the pulse mine (t6); the EMP mine and hook (t7); the Minefield (t8); mine art (t9); the Mine Layer shell (t10); the Mine Layer passes (t11); hub idle and persistence (t12); hull art,
hatch and wake (t13); the hub patrol and minefield (t14); level-1 placement (t15); docs, roster and phase record (t16).

**Owner's notes on the plan:** "CHANGES_REQUESTED: Fix those issues in your plan" — the owner's note carried no comments of its own, so the plan was revised three times (Revisions 2–4) to
answer the AI plan review's findings (rounds 1–3); round 4 approved it. The five owner questions in the plan (placed mines hurting enemies, how the EMP stand-in reads, etc.) were left open
with their defaults, which is what was built.

## Player-facing goal

Areas of space stay dangerous after a Mine Layer has crossed them: the player learns to read six mine kinds at a glance (proximity, drifting, homing, chain, pulse, EMP), steers round
them, lures enemies into placed minefields, and in Open Space finds the same lines waiting when they come back. Pulse and EMP mines briefly weaken the boost and dash. The Mine Layer
itself is a slow, easy-to-hit hull whose threat is what it leaves behind, and it punishes a player who tail-chases it.

## Scope

- **In:** `EnemyMine` family (6 variants) on the Bomber's ordnance base; hazard registration and the measured footprint; placed mines and `Minefield`; the player boost-disruption and EMP
  hooks (`EmpPulse`); the Mine Layer (shell, pass AI, hub idle, art, wake); hub patrol + placed hub minefield; level-1 placement in deep_space and planet_approach; gate-time recovery; docs.
- **Out (with owner phase):** EMP on enemies and the real EMP effect, jammers (Ph9); placed minefields in Assault levels (Ph15); encounter compositions (Ph13/14); mine numbers by
  difficulty (Ph16); mine/layer audio (Ph17); merging the race-track mine (not planned); a layer scattering mines on death (owner option); mines bending in gravity fields (decided no).
- **Already built earlier and not rebuilt:** §16 explosive collision profile (Ph2), §11.4 Gravity Field and Debris Charge (Ph6).

## Constraints

- Strict top-down art from PixelLab only, saved with `scripts/pixellab.sh`, each image looked at (CLAUDE.md).
- Composition over inheritance; config-driven enemies (`.tres` wins); one writer of motion (`EnemyMover`); one owner per projectile (`BulletPool.persist_after_owner_death`).
- Design-unit coordinates (640×360 ×2); brains tick on physics, no `Timer`/`create_timer`; randomness only from the brain's seeded rng.
- Gate time: GUT must stay ≤ 240 s (it started the phase at 216.3 s); every task has an allotment.
- Pass-through stays bit-identical: with no hazard in reach, enemy velocity and rotation equal Ph6's.

## Open questions at the time

- *Can avoidance keep ships outside a mine's trigger?* Measured (`Steering.context_avoid`): not at the trigger radius alone; resolved by `trigger_radius + hazard_pad 60` at weight 1.0 and the
  Mine Layer's own `hazard_avoidance` 0.8.
- *Where does the pulse/EMP effect live without Ph9?* On `PlayerBase` as duck-typed hooks; `EmpPulse.emit` is the one entry point and its player effect is a stand-in.
- *How does a layer lay a line "across" a player who stands still or is faster than it?* Lead form via the Bomber's earliest-feasible scan; fence form otherwise; a cruising player gets a fence line.
- *Do placed mines hurt enemies?* Yes, through `Hazards.pulse_damage` (Ph6's environmental rule) — owner question 1 default.
- *How much gate time?* t1 recovered 13.8 s first; allotments summed to 28.5 s; the phase finished at 218.44 s.
