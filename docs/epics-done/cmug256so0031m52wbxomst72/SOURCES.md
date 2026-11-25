# Enemy rework, phase 11: Space Fortress 2.0 — sources

The research stage left no file; the findings are in plan §1.2 (`docs/plans/cmug256so0031m52wbxomst72/3-plan.md`). No new web research was done: the design questions were answered by the owner's spec and by
Phases 1–10. Numbers marked *judgement* in the plan are starting values, **not play-tested**.

| Source | What it contributed | Where it shows up |
|---|---|---|
| `ENEMIES_OPEN_SPACE_REWORK_IDEAS.md` §8, §8.1, §10, §21–26, §39–41 | The author's spec | Everything |
| `ENEMIES.md` (naming note) | "Fortuna Space Station" collides with "station" | The boss is the Space Fortress; the section keeps `station_assault`; `docs/enemy-roster.md` |
| Phase 10 (`EnemyModule`, `ModularHull`, `TurretMountBuilder`, armoured-hull rule, Carrier) | Part framework and the armoured hull | Fortress parts, mounts, hull rule |
| The retired space station (`StationTurret`, gunnery, laser phase, reinforcements, death sequence) | What already worked | `BossDeathSequence`, mounts, spokes, `BossReinforcements`; migrated test family |
| Ph8 `EnemyBeam` / `EnergyRing`, Ph9 `answers_emp()`, Ph5 `EnemyShield`, `SquadController` | Weapons, EMP routing, shields, escort squads | Spokes, ring, structures' EMP, `ShieldSector`, escorts |
| Plan review (`docs/plans/cmug256so0031m52wbxomst72/4-review.md`) and the owner's send-back | Revisions 2 and 3 of the plan | Plan §8; Ph11 owner choices |
