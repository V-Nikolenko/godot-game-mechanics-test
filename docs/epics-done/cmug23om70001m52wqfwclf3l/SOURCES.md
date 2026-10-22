# Enemy rework, phase 6 — sources

Findings F1-F14 and the scope check S1-S14 are in `docs/plans/cmug23om70001m52wqfwclf3l/2-research.md`; context in `1-context.md`.
Values with no citable source are **[judgement]** and are starting values for tuning.

| Source | What it contributed | Where it shows up |
|---|---|---|
| Context steering (Fray, Game AI Pro 2 ch. 18) and the Godot forum reports of snapping / sticking | Interest / danger maps over fixed slots; the failure modes | `Steering.context_avoid()`: 16 slots, interpolation, distance-scaled danger, previous-heading hysteresis, minimum speed ratio 0.35 |
| https://www.red3d.com/cwr/steer/gdc99/ | Obstacle avoidance and containment as steering behaviours | The avoidance stage's skirt and margin; the claimed-cover skip |
| The race `HazardSystem` in this repo | "What the AI dodges is what kills it": one object drives physics and perception | `HazardInfo` / `Hazards` registry |
| `ContactBlast.spawn` in this repo | A deferred attach for spawns inside a physics flush | `spawn_into()` on `HazardField`, `Wreck`, `DebrisFragment` |
| Phase 4's `LineOfSight` and `blocks_line_of_sight()` hand-over | A blocker contract nothing yet answered | `Wreck`, `EnemyBrain.can_see_player()` |
| `ENEMIES_OPEN_SPACE_REWORK_IDEAS.md` §6.7, §6.8, §11.4, §18.6, §28 | Well, anomaly, wreck, Gravity Field, Debris Charge, tactical use | Every hazard and enemy tactic |
| Well pull 520, reach 420 px, core 90; wreck radii 13 / 25 / 40; caps 8 (Open Space) and 4 (Assault); fragment 12 damage | Plan start values | [judgement]; pinned by the hazard test files |

Also read in research (URLs as cited in `2-research.md`):

- https://www.gameaipro.com/GameAIPro2/GameAIPro2_Chapter18_Context_Steering_Behavior-Driven_Steering_at_the_Macro_Scale.pdf — the context-steering source above.
- https://forum.godotengine.org/t/context-based-steering-enemy-direction-instantly-snapping-and-getting-stuck-problems/121923 — the snapping / sticking failure.
- https://starsector.wiki.gg/wiki/Terrain — terrain that pulls, slows and distorts; the model for field kinds.
- https://www.stardock.com/games/starcontrol/article/485927/planet-gravity-new and the UQM `gravity.c` — gravity wells as a physics hazard for ships of both sides.
- https://masswerk.at/spacewar/inside/insidespacewar-pt6-gravity.html — a central pull with a softened core.
- http://www.gameaipro.com/GameAIPro/GameAIPro_Chapter26_Tactical_Position_Selection.pdf — cover and firing-position scoring (Sniper cover candidates).
