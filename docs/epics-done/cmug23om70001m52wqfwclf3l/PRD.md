# Enemy rework, phase 6: hazard perception, gravity wells, anomalies and wreck fields — PRD

## The ask

> Enemy rework, phase 6 of 20. Every combat enemy gets a shared way to perceive hazards (a `HazardInfo` query: position, radius,
> pull force, damage per second, movement penalty, whether it disables abilities, whether it blocks line of sight) and a soft
> avoidance layer feeding the movement intent `EnemyMover` already consumes. Hazards apply their physics to enemies as well as the
> player, unless a movement profile resists. Each profile sets how strongly it avoids hazards; a rammer in its final run ignores
> them. First hazards: the Gravity Well (radial pull growing toward the centre, hull-stress damage), the Energy Anomaly (a readable
> distortion), and the Wreck / Debris Field (hard cover, a line-of-sight blocker for `can_see_player()`, drifting debris or an
> explosive wreck). Also the §11.4 Gravity Field weapon and the Debris Charge. Enemies use hazards as tools: the sniper hides
> behind wreckage, fighters take cover before a pass, ram ships try to push the player toward a well. Strict top-down art for each.
> Tests in both harnesses cover pull on enemies and the player, avoidance per profile, wreck spawning and line-of-sight blocking.

**Scope:** `ENEMIES_OPEN_SPACE_REWORK_IDEAS.md` §3.2.5, §18.6, the destructible/physical and energy/physics structure categories
except mines, jammers, turrets and laser emitters/barriers, §6.7, §6.8, §11.4, §28, §21-23 art, §40 tests.

## As finally understood

- Hazards are **sampled by the body** (a static registry), not detected by `Area2D`; collision bit 12 stays unallocated.
- Context steering is a stage inside `EnemyMover`; brains still make one request per tick; a committed attack is `boost()`.
- Mover-driven enemies only (the nine brains); rails, the Gunship and the station are untouched.
- Level 1 gets only what its enemies leave (wrecks); the hub gets one tactical space. Runtime hazards spawn deferred into a
  `HazardContainer`, never into the enemy container.
- Out: mines (Ph7), laser walls (Ph8), jammers / EMP (Ph9), capital and boss wrecks (Ph19), wingman cover (Ph14), the anomaly's
  shield / targeting variants and the Ram's deliberate plate throw (owner options), hazard audio.
- Gate budget: allowances summed to 35.5 s; GUT must stay <= 240 s.

## Acceptance for the closing task (t19)

Every new class, scene, group and gate is documented; this dossier and the DECISIONS as-built section exist and say what no human
has play-tested; the final gate time is recorded; `bash /agent/verify.sh` is green.
