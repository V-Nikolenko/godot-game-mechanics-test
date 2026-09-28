# Enemy rework, phase 2 — sources

Merged from `docs/plans/cmufs7ek60001nm2x6d0bt2et/2-research.md` §1/§6/Sources. No escalated task
under this epic ran its own separate research pass; every task task-plan (`cmuj4y8r…`,
`cmuj4y8s…` directories under `docs/plans/`) draws on this research and on the round-2 plan
review's independently re-derived arithmetic instead.

| Source (URL) | What it contributed | Where it shows up in the build |
|---|---|---|
| https://www.red3d.com/cwr/steer/gdc99/ (Reynolds) | Neighbourhood definition for flocking; pursuit prediction time T ∝ distance; wander as a smoothed random walk. | `Steering.separation`/`alignment`/`cohesion` (squad-only neighbours, O(k²), k ≤ 7); `Steering.clamped_lead_time`'s distance-scaled prediction window (the Swarm's 0.4–0.8 s ram lead). |
| https://www.jdxdev.com/blog/2021/03/19/boids-for-rts/ | Spatial-grid flocking at scale; a **side latch** to stop avoidance flicker between two neighbours. | Confirms brute-force O(k²) is fine at squad size (no grid needed); the side-latch idea is `SquadController.claim_side()`/`release_side()`, latched until a pass ends. |
| https://arnauld-alex.com/scaling-boids-for-multiplayer-games-fast-flocking-with-spatial-grids-and-zero-copy-optimization | Grid scaling only pays off at dozens of agents. | Confirms the squad-only neighbour search needs no spatial structure at this phase's scale (max 7 loose drones in one level-1 wave). |
| http://www.gameaipro.com/…Chapter28…Kung-Fu_Circle… (read via r.jina.ai; the raw PDF was undecodable) | *Kingdoms of Amalur*: an attack-slot grid, a per-creature weight, an attack capacity, inner/outer circles. | Confirms the owner's own lead/flank/rear role split (IDEAS §5.1) is a known-good pattern rather than a novel design; `SquadController`'s `LEAD`/`FLANK_LEFT`/`FLANK_RIGHT`/`REAR` roles. |
| https://www.gamedeveloper.com/design/cyber-demons-the-ai-of-doom-2016- (summary) | *DOOM* (2016): an attack **token** a demon requests and releases, stealable by a closer demon. | `SquadController`'s "closest steals the token" LEAD assignment, recomputed on every join/leave rather than elected once. |
| https://www.gameaipro.com/GameAIPro2/…Human_Enemy_AI_in_The_Last_of_Us.pdf (read via r.jina.ai) | *The Last of Us*: one active shooter at a time, the rest given roles; perception delay ≈ 1–2 s; combat persists ≥ 10 s after losing the player. | The "one lead attacks, others hold roles" shape; `AnchorIdle.notice_time` (0.35 s, shorter — this is a wind-up beat, not TLoU's full perception build-up) and `hold_combat`'s squad-wide persistence. |
| https://gdkeys.com/keys-to-combat-design-1-anatomy-of-an-attack/ | Telegraph length ≈ reaction time (≈ 0.25 s) + ability trigger + a difficulty buffer. | The 0.34 s telegraph floor behind `windup_seconds` (Swarm 0.4 s, Razor real dash 0.5 s). |
| https://www.gamedeveloper.com/game-platforms/anatomy-of-an-enemy-attack-in-dark-souls-3 (summary) | Signal + attack together need ≥ 340 ms. | Cross-checks the telegraph floor above. |
| https://note.com/darkangels_417/n/nb520b22d60f7?hl=en (summary) | A feint is "telegraph A looped for longer", with one cue exclusive to the real attack. | The Razor's fake dash: the same yellow CHARGING light held `fake_windup_scale` (1.5×) longer than a real wind-up, with the white COMMIT flash reserved for the real dash only. |
| https://www.gamedeveloper.com/design/enemy-attacks-and-telegraphing (summary) | Fairness = damage the player could have responded to; combine animation/SFX/VFX cues. | Motivates `StateLight` as the one shared telegraph channel (SFX explicitly out of scope — no enemy audio pipeline exists). |
| https://www.gamedeveloper.com/programming/predictive-aim-mathematics-for-ai-targeting (summary) | Imperfect prediction; intercepts can have no solution. | `TargetInfo.intercept()`'s existing `{ok, point, time}` contract (phase 1) is reused unchanged as the Swarm's ram-aim fallback. |
| https://discussions.unity.com/t/enemy-ai-orbit-strafe-around-player/575271 | Tangent orbit = "direction to target + 90°" plus a radial correction. | Confirms `Steering.orbit`'s existing (phase-1) shape; no change needed for either drone's orbit. |
| https://code.tutsplus.com/understanding-steering-behaviors-wander--gamedev-1624t | Wander-angle smoothing to avoid jitter. | Background for the Razor's idle-leg design (`IDLE_ORBIT`/`IDLE_BRAKE`/`IDLE_REVERSE`/`IDLE_BOOST`), not a direct numeric source. |
| https://github.com/Saitamadupauvre/brotatomato/pull/33 | Leash/aggro hysteresis ≈ 300/450 px, marked a guess in the source itself. | Confirms the *shape* of `AnchorIdle`'s two-radius hysteresis (`perceive_radius` < `lose_radius`); the actual values are this phase's own judgement, sized to the hub's real geometry. |
| https://enterthegungeon.wiki.gg/wiki/Dodge_Roll_(Move) | *Enter the Gungeon*: contact damage is always on; fairness comes from dodge-roll i-frame timing, not from the hitbox switching off. | Cross-checked against `PlayerBase.invincibility_sec` (0.5 s) and rejected as the model here — IDEAS §16 picks "hurts only while attacking" instead, which `ContactProfile`'s RAMMING/EXPLOSIVE modes implement. |
| https://www.slynyrd.com/blog/2020/12/14/pixelblog-31-shmup-sprite-design | Small-sprite readability: shape first, then colour; projectiles should stay the most vivid thing on screen; a size spread across the roster. | The Swarm/Razor size split (32×32 / 48×48, inside IDEAS §21–23's 24–36 / 40–56 px bands) and `StateLight.MAX_ALPHA = 0.85`, capped below `EnemyBullet`'s brightness. |

**Tried and unreachable** (so a later phase does not re-attempt the same dead end):
`tvtropes.org/pmwiki/pmwiki.php/Main/CollisionDamage` and
`neogaf.com/threads/damage-on-touch-good-or-bad.1149018` — both 403 direct and through the proxy;
the Gungeon wiki page above stands in for the contact-damage rationale.

**Judgement calls with no citable source**, carried from the research into the shipped values (each
also individually flagged `[judgement]` in `docs/plans/cmufs7ek60001nm2x6d0bt2et/3-plan.md`):
orbit-reversal frequency (`reverse_chance` 0.35), the feint's lunge geometry (`feint_clearance_px`
70, worked out live during t10 against the drone's *measured* orbit radius rather than the plan's
assumed one — see DECISIONS "Phase 2 - as built"), per-agent phase offsets (`phase_offset`, ±0.35
rad), the hub's two patrol-ring radii (1300 px, corrected once more than the plan's own round-2 fix
during t16 after a full interactable sweep), and every numeric config default not already pinned by
existing code, a shipped resource, or the round-2 review's independently re-derived arithmetic
(`braking` 900, `overshoot_turn_rate`/`overshoot_speed` per drone, `engage_seconds`, `exit_speed`).
