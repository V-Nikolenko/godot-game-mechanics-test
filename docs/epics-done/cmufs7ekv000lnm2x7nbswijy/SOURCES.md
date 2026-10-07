# Enemy rework, phase 3 — sources

Merged from `docs/plans/cmufs7ekv000lnm2x7nbswijy/2-research.md` (§1, §3 and its Sources list) and `1-context.md`. None of
the five escalated build tasks (t8b, t9, t10, t16, t17; `docs/plans/cmulwkar…/`) ran a separate web-research pass: they drew
on this research and on measurements from the live code (their `prototype/` directories, kept as patches and harness text).
Values marked **[judgement]** have no citable source.

| Source (URL) | What it contributed | Where it shows up in the build |
|---|---|---|
| https://wiki.hard-light.net/index.php/Ai_profiles.tbl (FreeSpace 2; 403 to WebFetch, read through `scripts/fetch-page.sh`) | `$Max Player Attackers` caps the ships attacking at once and scales by difficulty (2, 3, 4, 5, 99); AI turn-time scale, in-range wait and fire-delay scale per difficulty; native burst fire. | The **three-attacker cap**: only LEAD + two flank lanes fire, REARs fly dry passes (deviation from IDEAS §5.3's "fourth frontal"). The `accuracy` and attacker-cap hooks Ph16's difficulty tiers will use. The 0.25 s Gatling spin-up kept as the owner's number despite FS2's longer waits. |
| https://www.gamedeveloper.com/design/cyber-demons-the-ai-of-doom-2016- | DOOM 2016's attack tokens: a limited number per attack type, stealable by a better-suited demon; waiters keep pressure without attacking. | `SquadController`'s full recompute on every join/leave is "stealing" (the closest takes LEAD); a REAR's **dry pass** is what a token-waiter does. Token *categories* were rejected as more arbitration than this phase needs (Ph14). |
| https://www.red3d.com/cwr/steer/gdc99/ (Reynolds) | A fly-by or strafing run is *offset pursuit*: aim at a point offset by R from the predicted position, T ∝ distance; leader-following arrives "offset slightly behind". | The Fighter's pass geometry (§2.4.1: `S = P̂ + b·standoff + l`, closest approach = `|l|`) and the signed lane per role, so the pincer emerges from two lanes of opposite sign. Also the clamped 0.3–0.8 s lead time. |
| https://www.gamedeveloper.com/programming/predictive-aim-mathematics-for-ai-targeting | First-order lead is enough; deliberate imperfection reads as skill; an intercept can have no solution. | Aimed burst `accuracy` 0.7 plus seeded jitter; convergence = one shared predicted point with an independent ±3° error per shooter; `TargetInfo.aim_direction()` / `intercept()` instead of a new `Steering.lead_target`. |
| https://shmups.wiki/library/Boghog's_bullet_hell_shmup_101 | Aimed patterns pressure and force movement; static patterns create obstacles; never block whole screen chunks; readability rules for bullets (glow cores, reds/pinks over yellow/orange, chunky, elongate fast bullets, small hitboxes). | Convergence pairs stay on the **same half-plane** so one side is left open; Pulse + Gatling are the "aimed" layer, Scatter + Heavy Shell the "static" layer; the round visuals (elongated red-pink Pulse, thin Gatling streak drawn on top, Heavy Shell with a dark rim drawn below). |
| https://www.slynyrd.com/blog/2026/7/26/pixelblog-63-horizontal-shmup | Background/foreground separation for shmup sprites (S −20, C −15, B +15). | Sprite readability brief for t14/t15; the 64×64 size inside IDEAS' 56–72 px band. |
| https://sparen.github.io/ph3tutorials/ddsga2.html | Danmaku bullet-design guidance. | Reachable, but contributed nothing that changed a number (the research's "Sparen guide A3: nothing on readability"). |
| https://www.gamedevs.org/uploads/three-states-plan-ai-of-fear.pdf (F.E.A.R.; read via reader proxy) | Squad behaviours fill slots from simple rules; coordination must be *apparent* to the player. | "Formations are spawn layouts, then roles"; the pincer emerges from each flanker's own lane; the convergence pair must be **visible** — both `StateLight`s go CHARGING together. |
| http://www.gameaipro.com/GameAIPro2/GameAIPro2_Chapter20_Hierarchical_Architecture_for_Group_Navigation_Behaviors.pdf (read via reader proxy) | Greedy nearest-slot assignment fails when members cross paths; the cheap fix is to sort members and slots spatially the same way. | `SquadController._reassign()` already re-sorts on every change; the plan added no assignment code. (The post-death station swap in the report is exactly this failure mode, found by the t9 sweep.) |
| https://forum.godotengine.org/t/object-pooling-with-bullets-of-different-hitboxes/81553 | One scene per bullet type in a keyed pool beats reshaping one scene at runtime; a hidden node still collides unless its shape is disabled. | **One scene per round, one `BulletPool` per round per shooter** (`EnemyRounds`); `EnemyBullet.reset()` restoring the scene's own authored speed and damage. |
| https://www.gamedeveloper.com/design/enemy-attacks-and-telegraphing | A projectile telegraph is charge cue → sound → flash; "it becomes fair" because the player saw it coming. | The Gatling spin-up (yellow `StateLight` from SWING_IN) and the fighter's 0.3 s yellow telegraph as *the* cues; SFX stays out of scope. |

**Tried and unreachable, or not useful** (so a later phase does not repeat the dead end):
- https://www.gamedev.net/forums/topic/677818-advice-on-spaceship-combat-ai-3d/ — 403, and `fetch-page.sh` failed too. Not used.
- The *Squadron: Mercenaries* devlog (itch.io) — reachable, no numbers. Not used.
- **No primary source** was found for Gatling/minigun spin-up timing (Gungeon, Returnal, DOOM) or for dogfight AI in *Star Wars:
  Squadrons*, *Ace Combat* or *Descent*. The 0.25 s spin-up and every burst size are the owner's (IDEAS §5.3–5.4), not sourced.
- The `Dubins 1957` / LaValle *Planning Algorithms* §15.3.1 shortest-path-with-turn-radius result cited in `dubins_path.gd` and
  `global.md` was **not in the research**; it came in with t8b to satisfy the pass-geometry fix (review B1/N8) and is cited
  from the maths, not a fetched page.

**Judgement calls with no citable source** (all were starting defaults, tuned only where a gate forced it):
- the 4-attackers → 3-shooters cap (a reading of FS2's Medium value, plus the level-1 density gates);
- every burst gap, speed, range and pool size in plan §3;
- convergence as "shared point + independent error + same half-plane";
- one pool per round being lower risk than variant data (a reading of the forum thread and our `BulletPool` contract);
- starting the Gatling's CHARGING light at SWING_IN, not SPIN_UP;
- `forward_range` 325 (the epic's own K5 lever), `reposition_cap` 5 s, `swing_in_reach` 300 px, `min_burst_period` 1.2 s;
- the hub ring (1500 px) and bearings (180° / 0°) — the generic clearance sweep accepted them unchanged.
