# Enemy rework, phase 8: energy weapons, defense turrets and Twin-Laser Drones — PRD

## The ask

> Enemy rework, phase 8 of 20. Beams become a real, shared weapon family instead of a boss-only effect: Beam (immediate line with a telegraph), Sweeping Beam, Lance, Pulse Ring,
> Twin-Beam/Endpoint Laser and Moving Laser Wall. Every beam damages anything crossing its line, other enemies included. The Stationary Defense Turret is the first consumer: a non-moving
> enemy (48–96 px standard, 128–192 px heavy emplacement) with predictive aim and weapon variants (burst cannon, sweeping beam, rocket battery reusing phase 5's rockets, pulse ring, sniper
> lance), placed in groups of 2–4 with overlapping fire lanes, protectable by a shield generator, disabled as a group when its power-source structure dies. In Assault turrets are static
> corridor hazards. Stationary laser walls and temporary laser barriers are added as structures. Twin-Laser Drones are two small endpoint drones holding a beam between them: Attack A closes
> it through the player; in Attack B a controller ship launches them in a V toward predicted points, they align into a |---| wall and advance together. Killing one drone collapses the beam,
> and the drones can be baited into terrain or a gravity well. All own strict top-down art and telegraph effects and join Assault waves and the hub's ambient spawn. Tests in both harnesses
> cover beam activation and telegraph timing, beam damage to allies, power-source shutdown of a turret group, and the moving wall keeping its length.

**Scope:** `ENEMIES_OPEN_SPACE_REWORK_IDEAS.md` §6.5 Stationary Defense Turret (all of it except mounting on large ships, Ph10); §6.10 Twin-Laser Drones; §11.3 energy weapons; §18.6 defensive
structures and stationary laser walls / temporary barriers; §21–23 art; §40 beam-activation tests in both modes.

**Original idea:** "Analyze the files with ideas, add improvements to it if you have any great ideas, research and create a plan to implement ALL those ideas. Be sure, to add in the review all
changes you proposed at the top of the document, if you have any. ENEMIES_OPEN_SPACE_REWORK_IDEAS.md - file with all ideas proposed. ENEMIES.md - current implementation."

**The epic's tasks (titles):** gate room (t1); `EnemyBeam` core (t2); `EnergyRing` (t3); segment hazards (t4); endpoint beams, cover, laser-wall registration (t5); defense turret shell and burst
cannon (t6); beam turret mounts (t7); rocket battery and pulse ring mounts (t8); turret groups and the power source (t9); shield generator (t9s); laser fences (t10); heavy emplacement (t11);
Twin-Laser Drones and Attack A (t12); Laser Tender and Attack B (t13); hub idle and measured Assault exits (t14); structure art (t15); drone / tender art (t16); level-1 laser columns (t17);
hub placement (t18); level-1 placement (t19); docs, roster and phase record (t20).

**Owner's notes on the plan:** the plan was revised once (revision 2) to answer the round-1 review (B1–B4, N1–N10; plan §8). Owner choices recorded in the plan: the Laser Tender as Attack B's
launcher (choice 1) and static enemies never counting as escapes (choice 8); the other open owner questions were left at their defaults, which is what was built.

## Player-facing goal

Lasers are something the player reads and dodges, not a surprise: a 4 px warning line on the exact path, then the beam, and a beam hurts every enemy on its line too. Defended sites appear
in the hub and in level 1: turrets in groups whose fire lanes overlap, a power source whose death darkens the group, a generator whose bubbles must be broken first, laser fences that can be
shot down at a post. Twin-Laser Drones try to close a beam through the player; killing either drone collapses it. A Laser Tender launches a pair in a V into a moving wall the player must
slip round the end of.

## Scope

- **In:** the beam family (`EnemyBeam` BEAM / SWEEP / LANCE / TWIN, `EnergyRing`, `EnergyHitScan`); segment hazards; `DefenseTurret`, `TurretMount` (six variants), `HeavyEmplacement`, `PowerSource`,
  `ShieldGenerator`, `TurretGroup`, `LaserEmitter` + `LaserFence`, `TwinLaserDrone` + `TwinLaserPair` + `TwinLaserPairSpawn`, `LaserTender`; `AssaultDrift`; art for all of them; hub site and patrols;
  level-1 placement; gate-time recovery; docs.
- **Out (with owner phase):** turrets mounted on ships / bosses (Ph10 / Ph11); the station's lasers on `EnemyBeam` (Ph11); jammer-linked groups (Ph9 / Ph20); placed Assault corridor layouts (Ph15);
  encounter compositions (Ph13 / Ph14); difficulty tiers (Ph16); audio (Ph17); wreckage from destroyed turrets (Ph19); the endpoint-rig beam rotating about an anchor (Ph11).

## Constraints

- Strict top-down art from PixelLab only, saved with `scripts/pixellab.sh`, each image looked at.
- Composition over inheritance; config-driven enemies (`.tres` wins); one writer of motion (`EnemyMover`); a mount writes only its own `rotation`; beams are owner-ticked (no `Timer`, no `_process` clock).
- Design-unit coordinates (640×360 ×2); a wave-spawned group or fence is world-anchored in x.
- Gate time: GUT ≤ 240 s (Ph7 closed at 218.44 s); t1 had to free ≥ 15 s and every task has an allotment (33.1 s in total).
- Pass-through stays bit-identical: with no segment hazard, Ph6 / Ph7 avoidance is unchanged.

## Open questions at the time

- *Do energy weapons hurt other enemies?* Yes, everything but the owner set; direct emit, so shields and plates are bypassed (decided in the plan, recorded in DECISIONS).
- *Who launches Attack B?* A new Laser Tender (owner choice 1).
- *Who carries the plain Beam?* A sixth mount variant, `BEAM_CANNON`, on the heavy emplacement.
- *Do level 1's existing laser columns kill AI enemies?* Measured in t17: yes, so they register as `&"laser_wall"` hazards (`registers_hazard`).
- *How much gate time?* t1 freed 19.1 s; the phase ended at 212.4 s.
