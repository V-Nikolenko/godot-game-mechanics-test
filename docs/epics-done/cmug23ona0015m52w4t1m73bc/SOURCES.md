# Enemy rework, phase 8: energy weapons, defense turrets and Twin-Laser Drones — sources

External research was gathered by a research subagent for `docs/plans/cmug23ona0015m52w4t1m73bc/2-research.md` (findings F1–F8; the plan's §2.21 tables where each number came from). Values
marked *judgement* in plan §2.21 are starting values, **not play-tested**. Nothing was re-fetched in the docs task; the list is the research's.

| Source | What it contributed | Where it shows up |
|---|---|---|
| Danmakufu laser tutorial (sparen.github.io/ph3tutorials/ph3u1l9.html) | A harmless warning line, then the beam; hit zone narrower than art (F1) | 0.9 s telegraph, hit half-width 12 vs drawn 16 |
| Terraria wiki — Moon Lord, Invincibility frames | Sweep rate (~40°/s), short lance, post-hit i-frames capping beam damage (F1–F3) | Sweep 100° over 2.0 s; `rehit_interval` 0.55 s above the player's 0.5 s i-frames |
| Enter the Gungeon wiki — Beholster, Blasphemy | Lasers cancelled at their origin (F6) | A beam ends when its emitter / a twin drone dies |
| Risk of Rain 2 wiki — Mithrix, Stone Titan | Telegraphed beams and rings passed through gaps (F1, F4) | Pulse Ring gaps, lance telegraph |
| Helldivers 2 wiki — Bunker Turret; Halo wiki — Banished shield generator; StarCraft / Protoss structures | Turret cadence; generators powering or shielding a group, single power point as a known weakness (F5) | Turret cadence, `lead_blend` 0.6, power source and shield generator |
| Returnal boss guide (powerpyx) | Beam and ring telegraph readability | Telegraph widths |
| Doom wiki — Monster infighting; gamedeveloper.com enemy-settlements article | Friendly fire needs rules (F8) | The owner-set rule |
| gdquest — laser_2d; Godot docs (Area2D, RayCast2D, ShapeCast2D, PhysicsDirectSpaceState2D, Line2D) | Physics-query behaviour, a `Line2D` telegraph (F7) | `EnergyHitScan` uses `Shape2D.collide`; cover rays only on the physics step |
| itch.io bullet-hell tips; kasoof "owww" | Telegraph and fairness heuristics (F1) | Fairness rows |
| Internal: Ph4 `Bomber` / Ph7 Mine Layer lead scan, Ph5 rockets and Support Ship shield path, Ph6 `Hazards` / wreck drift, Ph7 `SpecialistExitProbe`, `LaserRay`, the station laser phase | Everything the phase reused | See plan §1.1 (S1–S16, P1–P6) |
| `ENEMIES_OPEN_SPACE_REWORK_IDEAS.md` §6.5, §6.10, §11.3, §18.6, §21–23, §40 | The author's spec | Everything |
| Plan review round 1 (`docs/plans/cmug23ona0015m52w4t1m73bc/4-review.md`) | Independent checks: gate arithmetic, column clearance, alive curves, i-frame cadence | Revision 2 of the plan |
