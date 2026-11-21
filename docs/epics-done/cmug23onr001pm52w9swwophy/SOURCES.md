# Enemy rework, phase 9: electronic warfare — sources

External research: `docs/plans/cmug23onr001pm52w9swwophy/2-research.md` (findings F1–F12). Values marked *judgement* in plan §2.19 are starting values, **not play-tested**. Nothing was re-fetched in the docs task.

| Source | What it contributed | Where it shows up |
|---|---|---|
| Dota 2 Silence / Mute (F1) | Silence blocks active abilities, not items, passives or movement | The lock covers H and K only |
| Overwatch, Sombra's Hack (F2, F3) | Hacked heroes move and shoot; short 1.5 s band; warning only while the lock holds | Disruptor 1.5 s; the JAMMED chip |
| Warframe Nullifier bubble (F4) | Visible sphere that stops abilities | Jammer field ring (`JammerFieldArt`) |
| EVE Online ECM (F5) | Jam source is a ship that can be killed | Kill the Hacker / tower to end it |
| Elite Dangerous chaff / ECM (F6), FreeSpace 2 decoys (F8), Battlefield flares (F9) | Seekers fail where aim is assisted; fixed fire unaffected; counters are scarce and cued | Seekers fly straight in a field; primary fire never affected |
| Overwatch Genji Deflect (F7) | A reflected homing projectile loses homing | The hijacked rocket's turn limit |
| Halo 3 Power Drain (F10) | 0.5 s arm, visible field, then the effect | EMP zone's 1.0 s arming ring |
| FTL hacking pulse (F11) | Disruption leaves the system's own cooldown alone | A locked press spends nothing; module `tick()` keeps counting |
| Riot loss-of-control indicators (F12) | Group indicators by the lost verb | JAMMED chip + rocket lock glyph |
| Internal: Ph5 rockets and Support Ship, Ph6 `Hazards` / `HazardField`, Ph7 EMP mine and boost disruption, Ph8 static structures, `AssaultDrift`, `AnchorIdle` | Everything reused | Plan §1.1 (S1–S18, P1–P7) |
| `ENEMIES_OPEN_SPACE_REWORK_IDEAS.md` §6.4, §6.6, §11.2, §11.4, §18.6, §21–23, §40 | The author's spec | Everything |
| Plan review rounds 1 and 2 (`docs/plans/cmug23onr001pm52w9swwophy/4-review.md`) | Gate arithmetic, cone-escape simulation, self-hit guard, EMP routing | Plan revisions 2 and 3 |
