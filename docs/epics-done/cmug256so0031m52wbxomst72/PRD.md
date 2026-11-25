# Enemy rework, phase 11: Space Fortress 2.0 and machine-driven boss reinforcements — PRD

## The ask

> Enemy rework, phase 11 of 20. Rebuild the Space Station mini-boss as Space Fortress 2.0 (320–512 px), a 360° boss on phase 10's module framework, fought by circling it. 4–6 outer batteries (spread cannon,
> laser sweep, missile launcher, rapid pulse, slow artillery), 2–3 shield nodes that protect sectors, a core hidden or armoured until enough outer systems die, four phases (batteries; shield generators exposed;
> core exposed and the fortress moves; critical frenzy), each changing at least two of movement, attacks, vulnerable areas, arena control, reinforcements and visuals. Open Space: slow rotation, repositioning
> inside a combat zone, shifting orbit centre. Assault: vertical movement only, still rotating. Geometry weapons (rotating hull beams, ring pulses, corner crossfire). Reinforcements launched from specific
> damaged or active parts, outside the generic Assault enemy container and scoring path, as a reusable boss mechanism. Multi-part art and wreckage states. Replaces the Assault station section, may appear in
> Open Space under a name that does not collide with "Fortuna Space Station".

**Scope:** `ENEMIES_OPEN_SPACE_REWORK_IDEAS.md` §8, §8.1, §10, §21–26, §39, §40, §41 Phase 5 item 1; the `ENEMIES.md` naming note.

**The epic's tasks:** phase ladder (t1); shared death sequence (t4); SPREAD_CANNON / RAPID_PULSE mounts (t3); shield sectors (t15); boss reinforcements (t2); EMP on structures (t12); fortress shell (t5), movement (t6),
batteries (t7), geometry weapons (t16), reinforcements (t8), art (t9); level 1 (t10); hub draw 21 (t13); station retirement (t11); docs and phase close (t14).

## Player-facing goal

A boss you walk around. Each side of the fortress is a different problem; shooting out a battery silences one diagonal lane, killing a generator drops one half's shield bubbles, the plated core opens only when
both are gone, and the hull spins its lasers and pulses rings as the reactor goes critical. Defenders launch from the part that was hurt, not from the sky.

## Scope

- **In:** `global/boss/` (`BossPhase`, `BossPhaseDriver`, `ShieldSector`, `ReinforcementBay`, `BossReinforcements`, `EscortContainer`, `BossDeathSequence`); `SpaceFortress` (+ brain, flat config, nine parts, five
  batteries, spokes, ring, core ring, three bays, 22 PNGs); two mount variants; EMP on structures; level 1's `station_assault`; hub draw 21; the station's retirement and test migration; docs.
- **Out (later phases):** Carrier / Heavy Gunship on the boss machinery (Ph18); beams vs parts, wreck LOS, capital wrecks (Ph18 / Ph19); Dreadnought (Ph12); encounter director (Ph13 / Ph14); boss HUD, per-part score,
  audio (Ph17); difficulty tiers (Ph16); EMP on boss shields (Ph18); level 2 (Ph15).
