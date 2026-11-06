# Enemy rework, phase 7: mines, minefields and the Mine Layer — sources

**Internal precedents and measurements only; no external research.** The research stage of this epic left no `1-context.md` / `2-research.md`; the plan's §1.1 *Scope check* (S1–S11)
re-read the code and the decision log instead, and **every number's origin — an earlier phase, a measurement, a derivation, or a judgement-call starting value — is tabled in
`docs/plans/cmug23omu000lm52wu7rak0q5/3-plan.md` §2.18.** Nothing was reconstructed here. No URL was fetched, so there is no unreachable source to list. Values marked *starting value*
in §2.18 are **[judgement]**, not play-tested, and are tuning levers for Ph16/Ph17.

| Internal source | What it contributed | Where it shows up |
|---|---|---|
| `EnemyOrdnance` / Bomber mine (Ph4 t9–t10) | Eject-and-stop, proximity trigger, warning, `ContactBlast`, the 440 px/s mine band, 80 / 0.25 s / 48 / 30 / arm 0.5 | The PROXIMITY variant and every mine scene's shared numbers; the warning rule |
| `BulletPool.persist_after_owner_death` (Ph4) | Ordnance that outlives its owner with exactly one owner at each instant | The Mine Layer's per-variant pools |
| Ph4 Bomber wall rule and `BomberBrain._solve_arrival` | Intercept-point selection; earliest-feasible scan (0.1 s steps, 5 bisections, cap) | Lead plan form in `MineLayerBrain`; `ARRIVAL_SCAN_STEP`, `ARRIVAL_BISECTIONS` |
| `BomberBrain._enter_disengage()` | Release the Assault corridor on exit | `MineLayerBrain._enter_disengage()` |
| Ph5 rocket blast / `ContactBlast` | Explosion radius and `blast_radius` semantics | PLAYER-hostility mine blasts |
| Ph6 `Hazards` registry, `HazardInfo`, `Steering.context_avoid`, `Hazards.pulse_damage` | Perception, avoidance, environmental damage to both sides | Mine hazard footprint (measured, §2.3); ALL hostility |
| Ph6 wreck (60 px/s Assault drift, 40 s life) | Scrolling hazard precedent | `Minefield` Assault drift and its 40 s cap |
| Ph6 hub `_patrol_groups()` / `_element_radius()` clearance sweep | Placement rule (> 100 px) | Hub Mine Layer anchor and the placed field |
| `RailTrail` (Ph3) | Self-fading trail on its own clock | `MineWake` |
| `AnchorIdle` (Ph4 Bomber hub idle) | IDLE / NOTICING / RETURNING | Mine Layer hub idle |
| `SpecialistExitProbe`, `EXPECTED_PH5`, the frozen 2.5× gate (Ph4/Ph5) | Measured exits, density gate | `EXPECTED_PH7`, 7.53 s layer exit |
| `ENEMIES_OPEN_SPACE_REWORK_IDEAS.md` §6.3, §6.9, §11.4, §18.6, §21–23, §40 | The author's spec | Everything in the epic |
| Plan review rounds 1–4 (`docs/plans/cmug23omu000lm52wu7rak0q5/4-review.md`) | Independent measurements (avoidance table, run-in 150 px, simulation of the plan rules) | Revisions 2–4 of the plan |
