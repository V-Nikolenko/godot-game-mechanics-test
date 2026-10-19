# Research — Enemy rework, phase 6: hazard perception, gravity wells, anomalies and wreck fields

Epic `cmug23om70001m52wqfwclf3l`, research task `cmug23omg0005m52w238jt91z`, 2026-10-19.

`1-context.md` (next to this file) is the code inventory: requirements `R6.1`–`R6.19`, files, reusable pieces,
conventions, blast radius and the open questions. This file holds what the plan decides from:
- §0 the scope check against the code and the earlier phases' as-built records;
- §1 outside findings, with their tradeoffs and typical values;
- §2 candidate approaches per part, each with a recommendation (§2.13 answers `1-context.md`'s open questions);
- §3 starting values;
- §4 placement (Open Space hub, Assault);
- §5 the testing requirements, mapped to gates;
- §6 sizing and ordering notes for the plan stage.

Facts were read at `4126091` on `agent/auto-dev`. Anything not read directly, or a judgement with no citable source, is
labelled **(judgement)**.

---

## 0. Scope check

The scope text was written before Phases 1–5 ran. Checked against `DECISIONS.md` (Phase 1 plan and roadmap, Phase 1–5
*as built*), the Phase 4 and 5 reports and the code, it changes as follows. Each item is an explicit adjustment the
plan must carry.

| Id | Scope item | Finding | Adjustment |
|---|---|---|---|
| S1 | "Research decides whether to use context steering" (EPIC; R6.7) | Ph1 §2.4 **rejected weighted blending** ("cancellation shows as stalls") and named context steering "the planned upgrade in Phase 6, with hazards". `EnemyMover` today has one primary request plus additive nudges (`enemy_mover.gd:75-80`); nothing avoids anything. Nine brains request velocities directly. | **Use context steering, but as a mover stage, not a rewrite of the nine brains** (§2.2): the brain's request becomes the interest map, hazards write a danger map, the mover picks. Repulsion nudges (a weighted sum by another name) are rejected for the same reason Ph1 gave. This *keeps* the Ph1 decision and implements its named upgrade. |
| S2 | §3.2.5 `HazardInfo` query | Nothing exists: no `HazardInfo`, no `hazards` group, no field query. The closest precedent is the race mode's `HazardSystem` + `Sensors` (group `race_hazards`, duck-typed `danger_rect()` / `is_lethal_now()`), where "what the AI dodges is exactly what kills it". | Build `HazardInfo` (all seven IDEAS fields, plus the few the maths needs, §2.1) and a static `Hazards` registry. The **same** objects drive both the physics applied to ships and the AI's perception (R6.6). |
| S3 | Bit 12 `area_control` (Ph1: "Ph6 allocates `area_control` (bit 12, 2048)") | Bit 12 is unused everywhere. Ph1 also decided "no new layer is allocated until something uses it". A **sampled** field (§2.1: every body asks the registry for the field at its position) needs no physics layer; an `Area2D` design would, but it cannot be hand-ticked (overlaps need real physics frames) and `Area2D` projectiles are not `PhysicsBody2D`s, so Godot's built-in area gravity does not reach them (F6). | **Recommend not allocating bit 12 in this phase** unless the plan picks an `Area2D` design. The one place a layer question genuinely arises is "does a wreck stop enemy rounds?" (§2.8, C-question Q9), which can use the existing `hazard_contact` (1024). Either way the plan records the decision in `DECISIONS.md`, since it revisits a planned Ph1 item. |
| S4 | §11.4 Gravity Field | Ph1 roadmap put §11.4's gravity field in **Ph7** (with the mine); this board's scope moves it here. Nothing else in Ph7's scope depends on it. | In scope here. Ph7 keeps the mine and minefields. Log the move in `DECISIONS.md`. |
| S5 | §11.4 Debris Charge | Not in the Ph1 roadmap at all (§11.4 there listed mine / gravity field → Ph7, EMP → Ph9). The only armoured enemy with breakable parts is the Ram Corvette (`ArmorPlate` × 3, `ram_corvette.gd:138` `_on_plate_broken`); `ArmorPlate._break()` spawns nothing. | In scope here, on the Ram Corvette (§2.10). Heavy-ship / boss armour fragments are Ph19 (with Ph10's modules). |
| S6 | §28 LOS "feeding `can_see_player()`" | **Ph4 built LOS**: `LineOfSight.clear()` and `TargetInfo.line_of_sight()`, opt-in blockers (group `asteroids` or `blocks_line_of_sight() == true`), used by the Sniper (`sniper_brain.gd:454, :589, :598`) and the Support Ship (`support_ship_brain.gd:597`). No `can_see_player()` name exists. The hub has **no physics bodies**, so the Sniper's refusal is "proven by fixtures only" (DECISIONS Ph4 open items). The Missile Corvette never checks LOS — already §28's "missile ship can still fire". | Nothing to build in `LineOfSight`. This phase adds (a) wrecks and structures that answer `blocks_line_of_sight()` (the Ph4 hand-over), (b) a thin `EnemyBrain.can_see_player()` wrapper over `TargetInfo.line_of_sight` for new code (existing callers may migrate, not required), and (c) the first shipped blockers in the hub (§4.1). |
| S7 | §18.6 destructible / physical structures: "ship wrecks, drifting debris, damaged satellites, abandoned cargo platforms, broken station modules" | Only wrecks and drifting debris have behaviour of their own. Satellites, cargo platforms and station modules differ only in silhouette. Six unused grey debris sprites exist (`assault/assets/sprites/environment/debris_1..6.png`, 64×64, transparent). | One `Wreck` family with size / blocker / explosive / drift fields; **satellite, cargo platform and station module are art variants of a placed (non-spawned) wreck**, used in the hub's tactical space (§4.1). Drifting debris reuses `debris_1..6.png`. |
| S8 | §18.6 energy / physics structures: "gravity wells, energy anomalies, unstable reactor fields, EMP zones, temporary laser barriers, stationary laser walls" | Laser barriers / walls are excluded by the scope line (Ph8). EMP is Ph9 in the roadmap (§11.4 EMP pulse) and its natural consumer — `disables_abilities` — is the Ph9 jammer's. An "unstable reactor field" is a pure damage zone. | Gravity well and anomaly in scope. **Unstable reactor field = a `HazardField` with `damage_per_second` and no pull**, the lingering field an explosive wreck leaves (§2.9); cheap once the field exists. **EMP zones → Ph9**, with the jammer: building an ability-disabling zone with no jammer is the same consumer built twice. `HazardInfo.disables_abilities` ships as a field with no producer or consumer this phase (R6.1 asks for the shape; Ph9 gives it meaning). |
| S9 | §6.8 "temporary obstacle around a destroyed capital ship"; §23 "destroyed modules visibly remain as wreckage" | No capital ships exist; the station is Ph11, heavies Ph10, all of their hazard / wreck behaviour is Ph19 by the roadmap. | Out → Ph19. The `Wreck` family is the thing Ph19 reuses. |
| S10 | §18.6 tactical-tool examples: carriers positioning escorts, hackers staying outside the route | Carrier Ph10/Ph18, Hacker Ph9. | Out. In scope: sniper cover, fighter cover before a pass, ram pushing toward a well, drones skimming (EPIC names these). |
| S11 | R6.3 "hazards affect enemies" — *which* enemies | Mover-driven: the nine brains. Rail-driven spawns: `EnemyPathMover` owns position (only the station's reinforcements and `level_2_waves.gd` still use rails, DECISIONS Ph4/Ph5). Legacy: Gunship (own `_physics_process`, Ph10), Bonus Drone (rail; a reward target), Space Station (root layer 0, stationary, Ph11). | **Mover-driven enemies only.** Rails stay position-authoritative until Ph15; the Gunship gets it with its Ph10 rework; the station is "fully resistant" by being immovable (Ph19 decides heavy-ship mass). State it in the coverage table. |
| S12 | §6.7 "Ships **and projectiles** are affected" (R6.10) | Every projectile moves itself by `global_position +=` (no shared velocity); round lifetimes are gated by straight-line arithmetic (`test_enemy_bullet_lifetime.gd`); player bullets are gated by `test_player_bullet_lifetime.gd`. A 900 px/s player bullet crossing a 420 px well deflects ~85 px at the recommended strengths (½·a·t², a ≈ 200 px/s², t ≈ 0.93 s — arithmetic, §3.1), a 300 px/s round several hundred — not negligible. | In scope with an **opt-in per family** (§2.6). Recommendation: rockets, bombs and player missiles feel the well; bullets and rounds do not (owner question Q4). |
| S13 | Shipped content | The Open Space hub has no asteroids, hazards or bodies; level 1's density, deadline and attack-in-budget gates are calibrated with no hazards (the 73.2 s ram row has 0.40 s of margin). | Hub: one placed tactical space (§4.1). Assault: hazards that arrive *with enemies already in level 1* (wrecks from deaths, the Bomber's Gravity Field, the Ram's Debris Charge); **no placed gravity well or anomaly in level 1** this phase (§4.2, owner question Q10). |
| S14 | Gate time | GUT ≈ 200 s of the 240 s ceiling at the end of Ph5; `test_fighter_squad.gd` alone ~63 s, and it ticks every fighter's mover ~186k times. | Any per-step cost added to `EnemyMover.step()` multiplies across that sweep. The avoidance stage must be **O(1) when no hazard exists** (static registry count, never a group scan per step, §2.1). Prefer hand-ticked rows; budget per task (§6). |

**Everything else in the scope stands as written.** No earlier phase built hazard perception, avoidance, any pull or
slow, wrecks or fragments.

---

## 1. Findings from shipped games, papers and engine docs

A research subagent did most of the searches; URLs were fetched and read unless marked *snippet only*. Pages that
403'd were retried through `scripts/fetch-page.sh` (gamedev.net) or read through a reader proxy (gameaipro.com PDFs).
Ids `F1`–`F12` are used in §2–§3.

| # | Finding | Tradeoff for this phase | Typical values | Source |
|---|---|---|---|---|
| F1 | **Context steering (Fray, F1 2011).** Each behaviour writes an *interest* map and a *danger* map, one slot per heading, instead of returning a vector. Maps merge per slot by **max, not sum** ("we're not going to avoid a particular obstacle any more just because there's another obstacle behind it"). The final step finds the lowest danger, **masks every slot with more danger than that**, and picks the highest remaining interest; speed is proportional to that interest; the chosen heading is interpolated between neighbouring slots so motion is not locked to slot directions. Blending in the previous frame's map gives hysteresis without behaviours holding state; danger can carry a decreasing "skirt", made wider for cautious drivers. Replacing classic steering cut ~4000 lines. | Avoidance is guaranteed and behaviours stay small and stateless — but it is purely local (no path planning), and the final step is game-specific. The **skirt width is the per-profile knob** we need (narrow = skim, wide = cautious). Cost is linear in slots. | No slot count given; emergency brake when danger on the path exceeds a threshold. | https://www.gameaipro.com/GameAIPro2/GameAIPro2_Chapter18_Context_Steering_Behavior-Driven_Steering_at_the_Macro_Scale.pdf (read via proxy) |
| F2 | **Slot count and a simpler variant**: "For most purposes 8 slots is about perfect, but 32 is another good choice … better, smoother results"; usable range 4 to hundreds. Scores normalised to [0, 1] and **multiplied** per slot, so a single 0 vetoes a heading. | Multiplying is a hard veto; Fray's masking keeps "less dangerous" as an option when every heading has some danger (inside a well's skirt, every slot does). 8 slots is coarse without interpolation. | 8 or 32 slots, scores [0, 1] | https://gamedev.net/tutorials/programming/artificial-intelligence/smarter-steering-using-context-for-direction-r3149 (403 direct; read via `fetch-page.sh`) |
| F3 | **Reynolds' combining options**: weighted sum "often works well" but components "may cancel each other out at inopportune times"; strict priority (avoidance if non-zero, else the next behaviour) never cancels but is single-minded; prioritised dithering; prioritised acceleration allocation. Force and velocity truncated to `max_force` / `max_speed`. | The repulsion-nudge option (§2.2 B) is a weighted sum: cheapest, and it is the cancellation Ph1 already rejected. Priority arbitration (§2.2 C) makes ships ignore their target while near a hazard — no edge-skimming, no fighting near a well. | `steering = truncate(dir, max_force)` | https://www.red3d.com/cwr/steer/gdc99/ |
| F4 | **Star Control II melee planet** (UQM source): a **constant** pull of 1 world unit/frame toward the centre, only inside a hard radius (`GRAVITY_THRESHOLD = RES_SCALE(255)`); an inverse-square version with softening and `MAX_MAGNITUDE 6` exists but is compiled out (`#ifdef NEVER`). The slingshot is designed, not emergent: inside the well the ship's speed cap is lifted to `MAX_ALLOWED_SPEED` 18 px/frame, then it decelerates ("deceleration after gravity whip"). | Constant pull is predictable and readable but has a hard edge and does not grow toward the centre, which R6.10 asks for. A designed slingshot is an option, not a side effect. | radius 255 px, constant pull, cap lift to 18 px/frame | https://raw.githubusercontent.com/Serosis/UQM-MegaMod/master/src/uqm/gravity.c (+ `element.h`, `ship.c`) |
| F5 | **Spacewar! (1962)**: true inverse square (r̂ / r²) everywhere, with a capture radius (explode or warp); "near to immediate plunge into the Star" within ~34 units unless already moving away fast. MIT GAMBIT's remake: 1/r gave **no slingshot**, 1/r² did, but also "bounced off in a completely different direction or pass right through the star at a very high speed". | 1/r² is dramatic and chaotic near the centre; 1/r is calmer and readable but has no slingshot. An escape threshold (the distance past which a ship cannot get out) exists in every model and must be designed, not discovered. | 1/r², capture ~20 units | https://masswerk.at/spacewar/inside/insidespacewar-pt6-gravity.html ; https://gambit.mit.edu/updates/2012/02/the_peculiar_spacewar.php |
| F6 | **Softening and the engine option.** Phaser's `GravityWell`: inverse square with distance clamped to at least `epsilon` (default **100 px**), so force is constant inside it — no singularity. Godot's `Area2D.gravity_point_unit_distance` gives inverse-square falloff (0 = constant); `PhysicsBody2D.get_gravity()` returns gravity including area overrides, so a `CharacterBody2D` can read it — but only after real physics overlap, and `Area2D` projectiles are not physics bodies (judgement from the docs). | A core clamp removes the singularity cheaply. Godot's built-in area gravity has no clamp, needs physics frames (not hand-tickable) and misses every projectile in this project. | epsilon 100 px; Godot exponent 2 | https://raw.githubusercontent.com/phaserjs/phaser/master/src/gameobjects/particles/GravityWell.js ; https://docs.godotengine.org/en/stable/classes/class_area2d.html ; https://docs.godotengine.org/en/stable/classes/class_physicsbody2d.html |
| F7 | **Star Control: Origins playtest**: planet gravity "too strong because it is too far reaching, so ships … get stuck at the planet … works more like a magnet than a slingshot", while also too weak for a noticeable slingshot. | Reach and strength are separate knobs: a long reach with modest strength produces a magnet. Keep the reach short and the strength concentrated near the core. | — | https://www.stardock.com/games/starcontrol/article/485927/planet-gravity-new |
| F8 | **Killzone position scoring**: candidate positions scored by a weighted sum ("outside danger zone", partial cover, line of fire, preferred range); example weights proximity 20, line of fire to the primary threat **40 with partial cover, 20 without**, cover from secondary threats 20, inside preferred range 10. LOS precomputed per waypoint and sector: "Inaccurate, but consistent", "pessimistic about cover". | Weighted sums are fine for choosing a **position** (one score per candidate) even though they fail for choosing a direction (F3) — so the Sniper's existing weighted firing-point score is the right place for a cover term. Precomputed LOS goes stale with moving wrecks. | weights 10–40; partial cover doubles the LOF weight | https://www.guerrilla-games.com/media/News/Files/gdce05_killzone_ai.pdf |
| F9 | **Tactical position selection (Crysis / Far Cry)**: for round obstacles (trees ≈ our wrecks), cover points are generated **on the side opposite the threat and regenerated on every request**, so agents circle the obstacle as the threat moves; reject points the enemy can reach first (`canReachBefore_the_target`, mandatory in Crysis 1); never pick a point another agent claimed; run cheap filters before raycasts, which are "often the dominant cost of position selection". | Generated-on-demand points suit drifting wrecks (no stale table) but cost raycasts; claiming prevents two agents racing for one wreck. The "opposite the threat" rule is exactly "hide behind wreckage" and "fighter circles the wreck". | 15 m collection radius, 10 m grid fallback | http://www.gameaipro.com/GameAIPro/GameAIPro_Chapter26_Tactical_Position_Selection.pdf |
| F10 | **Taming spatial queries (Johnson)**: symmetric scores make the destination oscillate — break ties with a small side bias; switch only when the new best beats the current by a threshold (hysteresis); **erosion** builds a buffer outside a damage volume so an overshooting agent does not land in it; **blur** stops agents holding at a boundary. | Hysteresis trades stability for responsiveness. Erosion vs blur is the "skim vs avoid" knob from the position side, matching F1's skirt from the steering side. | side bias 5 %; hysteresis 10–20 % | http://www.gameaipro.com/GameAIProOnlineEdition2021/GameAIProOnlineEdition2021_Chapter05_Taming_Spatial_Queries_Tips_for_Natural_Position_Selection.pdf |
| F11 | **Environment as a tool reads as intelligence, unseen tactics read as cheating**: a flanking AI the player never saw was "accused … of cheating"; opportunistic use of the environment reads as smart; **tickets** ration tactics (1 left-flank ticket, 1 grenade ticket, 3 frontal attackers). | Using a hazard against the player is only fair if telegraphed and visible, and only one enemy at a time should try it. | one ticket per tactic | https://gdkeys.com/ai-keys-to-believable-enemies/ |
| F12 | **Slows**: League of Legends applies only the strongest slow (others ignored), refreshes rather than stacks, and floors speed (110). Overwatch (June 2023) cut Mei's sustained primary slow **50 % → 40 %** and her peak slow **75 % → 65 %**, because slows traded away too much. Starsector's abyssal hyperspace: top ship speed and missile speed / range **−20 %**. | No-stack plus a floor keeps a slow from pinning the player; sustained slows above ~40–50 % were walked back in a shipped game. | 20–40 % sustained, ≤ 65 % peak; strongest-only | https://wiki.leagueoflegends.com/en-us/Slow ; https://us.forums.blizzard.com/en/overwatch/t/overwatch-2-retail-patch-notes-%E2%80%93-june-28-2023/852239 ; https://starsector.wiki.gg/wiki/Terrain |

**Known failure modes** (each one is a test or a design rule in §2 / §5):
1. **Weighted sums cancel to zero** — averaging chase and avoid gives "very close to 0, and the entity hardly moves";
   adding weights "only succeeded in moving the problem" (F1, F3). → No repulsion nudges (§2.2).
2. **Context steering snaps or sticks** — a Godot 4.3 user with 8 rays and a hard −3 danger penalty saw the heading
   "snap about sixty degrees" near walls and the actor "gets stuck if the destination … is directly behind a huge
   obstacle" (https://forum.godotengine.org/t/context-based-steering-enemy-direction-instantly-snapping-and-getting-stuck-problems/121923).
   → 16 slots, interpolation, distance-scaled danger, previous-map blend, and a "target behind obstacle" row (§5).
3. **Magnet, not slingshot** — far-reaching gravity traps ships (F7); 1/r² plunges (F5). → Short reach, softened core,
   a designed escape threshold per body (§2.3, §3.1).
4. **Destination / cover thrash** — symmetric scores weave; agents racing for one cover point leave one stranded
   (F9, F10). → Hysteresis and a cover claim (§2.11).
5. **Holding at, or overshooting into, a hazard edge** (F10). → Erosion margin = the profile's skim margin (§2.2).

**Energy-anomaly readability: no citable source found.** The subagent did not research it; my own searches reached
only snippets — FTL's environmental beacons (asteroid fields, solar flares, pulsars, nebulae, ion storms) **affect both
sides** and are announced by a persistent hazard state (*snippet only*, ftl.fandom.com "Plasma Storm" search result);
original Everspace's black hole plays "a repeating warning beep that speeds up as you approach" and rewards luring
enemies in (*snippet only*; everspace.fandom.com 402 to WebFetch, `fetch-page.sh` failed). §2.5's anomaly rules are
therefore **(judgement)**, built on two things those snippets agree with: one rule per hazard, and a telegraph that
escalates with proximity / time.

**Sources tried and unreachable:** everspace.fandom.com "Natural hazard" (402 WebFetch; `fetch-page.sh` failed — direct
403, proxy returned nothing usable); ftl.fandom.com hazard pages (not fetched; snippet only); Fray's blog / GDC 2013
talk (not found / not read); the kidscancode Godot 4 context-map recipe (404); newdocs.phaser.io (DNS failure — GitHub
source used instead). Not researched, so no claims: Geometry Wars black holes, Nova Drift, Gravitar, Solar Jetman,
Everspace 2 / Rebel Galaxy anomalies, Enter the Gungeon cover numbers.

---

## 2. Candidate approaches

### 2.1 `HazardInfo` and the registry (R6.1, R6.2, R6.6, S2, S3, S14)

**Shape.** `HazardInfo` (`global/hazards/hazard_info.gd`, `RefCounted`), a snapshot like `TargetInfo`:

| Field | IDEAS name | Meaning |
|---|---|---|
| `position: Vector2` | position | centre, world px |
| `radius: float` | radius | outer edge of every effect (pull reach, slow area, cover footprint) |
| `pull_force: float` | pull_force | acceleration at the core, px/s² (0 = none); the falloff is the field's (§2.3) |
| `damage_per_second: float` | damage_per_second | inside `damage_radius` |
| `movement_penalty: float` | movement_penalty | 0..1 speed / thrust / boost reduction inside `radius` |
| `disables_abilities: bool` | disables_abilities | carried; no producer or consumer until Ph9 (S8) |
| `line_of_sight_blocker: bool` | line_of_sight_blocker | mirrors the body's `blocks_line_of_sight()` so the AI's cover maths and the ray agree |
| `kind: StringName` | — | `&"gravity_well"`, `&"anomaly"`, `&"gravity_field"`, `&"wreck"`, `&"debris"`, `&"reactor_field"`; later `&"mine"` (Ph7), `&"laser_wall"` (Ph8), `&"jammer"` (Ph9) |
| `core_radius`, `damage_radius: float` | — | the pull's softening radius (F6) and the hull-stress radius |
| `avoid_weight: float` | — | the hazard's own "how bad is it to enter" (well 1.0, reactor field 1.0, gravity field 0.6, wreck 0.5, anomaly 0.7) — R6.8's "depends on the hazard" half; the profile is the other half |
| `velocity: Vector2` | — | drifting hazards (wrecks, fragments), so avoidance can lead them |

Plus pure methods: `pull_at(pos) -> Vector2` (the acceleration field), `tangential_at(pos)` (the anomaly's swirl),
`contains(pos, margin)`, `penalty_at(pos)`. Every hazard node answers `hazard_info() -> HazardInfo` (duck-typed, the
`blocks_line_of_sight()` precedent), so Ph7 mines, Ph8 walls and Ph9 jammers join without touching the AI (R6.2).

**Registry — three options:**

| Option | How | For | Against |
|---|---|---|---|
| A. Group scan | `get_tree().get_nodes_in_group(&"hazards")` per query | Zero state; the race `HazardSystem` does it | Allocates an `Array` per call; per enemy per step that is ~750k calls in `test_fighter_squad.gd` alone (S14) |
| **B. Static registry (recommended)** | `Hazards` (static class, `global/hazards/hazards.gd`): a hazard calls `Hazards.register(self)` in `_enter_tree()` and `unregister` in `_exit_tree()`; `Hazards.count()`, `around(pos, reach)`, `pull_at(pos, scale)`, `penalty_at(pos)` | `count() == 0` is O(1), so every existing gate pays nothing; mirrors `EnemyWorld`'s "one static lookup" rule | Static state across tests: a hazard freed without `_exit_tree` would linger — not possible for a freed node; a test leak check (§5) pins it |
| C. `Area2D` overlap | Each hazard's area tracks bodies inside it and pushes onto them | Engine-native; scales to many bodies | Needs real physics frames (not hand-tickable — breaks the dual-mode `_tick()` convention); needs a layer (bit 12); misses `Area2D` projectiles (F6); hazards would write ship velocity (single-writer) |

**Recommend B.** The physics is **sampled by the body** (mover, player ship, opted-in projectile) and the hull-stress
damage is **delivered by the hazard** to the ships it finds by distance (iterating `enemies` + `player`, the race
`HazardSystem` shape) as a direct `HurtBox.received_damage.emit()` pulse (the laser-ray / beam precedent). No physics
area, so bit 12 stays unallocated (S3).

### 2.2 Soft avoidance: context steering as a mover stage (R6.7, R6.8, S1)

| Option | How | For | Against |
|---|---|---|---|
| A. Full context steering in every brain | Each brain writes interest maps instead of `request_velocity` | Fray's full model | Rewrites nine tested brains; every Ph2–Ph5 behaviour spec, budget row and density gate moves; far beyond scope |
| B. Repulsion nudge | Each hazard adds `away · strength` via `add_nudge` | Smallest change | A weighted sum: cancels to zero against a brain seeking a point behind the hazard (F1, F3, failure mode 1); Ph1 rejected it |
| C. Priority arbitration | Inside a hazard's skirt, avoidance replaces the brain's request | Never cancels | Single-minded (F3): a ship near a well stops fighting; no skimming |
| **D. Context stage in the mover (recommended)** | In `EnemyMover.step()`, after the desired velocity is formed and before the accel limit: if `Hazards.count() > 0` and the ship is not boosting, build a 16-slot **interest** map from the brain's desired velocity (`max(0, cos(slot − desired))`) and a **danger** map from the hazards within `reach = radius + margin + speed · lookahead`, merged by max (F1); mask slots above the minimum danger; pick the highest remaining interest; interpolate between neighbours; speed = `|desired| · interest(chosen)` | Brains are untouched; every brain gets avoidance; boost = committed = no avoidance, which is R6.8's rammer rule for free (Swarm BURST, Razor dash, Ram CHARGE all use `mover.boost`); exact pass-through when nothing is near | The mover gains state (previous map for hysteresis) and a stage; local only (no paths around big obstacles) |

**Recommend D**, with these rules:
- **Pass-through identity**: no hazard in reach (or `count() == 0`) → the desired velocity is returned unchanged
  (bit-identical). Pinned per mover configuration (§5).
- **Per-profile strength (R6.8)** — three flat fields, set from config like `max_speed` is today:
  - `hazard_avoidance` 0..1: scales danger (0 = ignores hazards entirely, e.g. a committed state that is not a boost);
  - `hazard_margin` px: the danger skirt beyond the hazard's radius — **narrow = skims the edge**, wide = cautious
    (F1's skirt, F10's erosion);
  - `hazard_resistance` 0..1: how much of a pull / slow the ship feels (§2.3) — the "heavy ships partly resist" half.
  Danger for a slot = `avoid_weight · hazard_avoidance · skirt(d)` where `skirt` falls from 1 at the radius to 0 at
  `radius + margin + lookahead`, scaled by how squarely the slot points into the hazard (angular half-width
  `asin((r + margin) / d)`). A hazard the ship is already inside writes danger on every inward slot and none on the
  outward ones, so it always steers out.
- **Snapping / sticking (failure mode 2)**: 16 slots (between F2's 8 and 32 — **judgement**), parabolic interpolation
  between the best slot and its neighbours, distance-scaled danger (never a hard penalty), and a 0.5 blend with the
  previous step's chosen direction (F1's hysteresis). A target directly behind a hazard makes the ship circle the edge
  — that *is* the skim the IDEAS want; a test row pins that it does not stall (speed > 0) and does not enter.
- **Wrecks are hazards too** (`avoid_weight` 0.5, no pull): ships steer round them instead of grinding along them
  with `move_and_slide` (enemy roots are layer 1 / mask 1, so they physically collide with a layer-1 wreck).
- **A brain can opt out for a step** (`mover.ignore_hazards()` — a request, cleared each step) for the deliberate uses
  in §2.11 (a ram lining up with the player between it and a well). Boost already bypasses.
- **The Assault corridor stays last** (constraint after the context stage, as today), so the corridor can never be
  avoided out of.

### 2.3 The pull (R6.3, R6.10, R6.11)

**Field.** Softened inverse-distance with a short reach (F4–F7):
`a(r) = pull_force` for `r ≤ core_radius`; `pull_force · core_radius / r` out to `radius`; a linear taper to 0 over the
last 15 % of `radius` so there is no hard edge (F4's weakness). **1/r rather than 1/r²** (F5: 1/r² is chaotic near the
core and our ships are damped anyway), **a core clamp** (F6, Phaser's epsilon), **a short reach** (F7). A designed
slingshot (F4) is out of scope (judgement: nothing in the IDEAS asks for one).

**How a body integrates it — three options:**

| Option | How | Against |
|---|---|---|
| A. Add `a·dt` to `velocity` | True physics | Every mover with `acceleration = 0` reassigns `velocity` each step, so the pull never accumulates; boosts overwrite it; orbit capture (F5, F7) |
| B. Flow field | `v = v_self + k · a(r)` with no memory | Snaps the instant a ship leaves the well; not "dragged" |
| **C. Mover-held drift (recommended)** | The mover keeps `_drift: Vector2`: each step `_drift += a(pos) · (1 − hazard_resistance) · dt`, then decays exponentially (half-life `drift_half_life`, 0.35 s, frame-rate independent); final `v = v_self + _drift`, **after** the accel limit and the boost, **before** `constraint.filter()` | One more piece of mover state; capture is a property to design (below) |

**Recommend C for enemies.** Consequences that make it testable:
- **Terminal drift** in a constant field is `a · (1 − res) / k` with `k = ln 2 / half_life` (1.98 /s at 0.35 s). A ship
  is **captured** where its own speed is below the terminal drift — a designed threshold, not an accident (§3.1 table).
- **It applies while boosting** (physics; R6.3) but avoidance does not (R6.8). A committed ram still curves slightly
  through a well — readable, and what "really pulled in" means.
- **Before the corridor**, so the Assault corridor still bounds an enemy (a well near the edge cannot drag it past the
  hard band). `halt()` and `suspend_ai()` zero `_drift`.
- The mover is still the single writer: the hazard never touches the enemy.

**Players** integrate the same field with their own physics ("according to their physical rules", R6.3):
- **Open Space ship** (`player_ship.gd`): `velocity += a · dt` inside `_handle_thrust` / `_step_boost`, before the speed
  ceiling clamp. The ship's thrust is 380 px/s²: where `a > 380` it cannot thrust out and must **boost** (700 px/s,
  re-asserted while sustained). That makes the core "boost or be dragged" — a readable rule. Its rotation is untouched
  (`ShipTurnController` stays the only writer).
- **Assault fighter** (`move_state.gd` sets `velocity = direction · move_speed` every tick): the same drift state as
  the mover (option C) on `PlayerBase`, added before `move_and_slide()` and the bounds clamp, decayed the same way.
  Dash and knockback paths keep their own rules (the drift persists across them).

### 2.4 Gravity Well (R6.10, R6.11)

A scene in `assault/scenes/hazards/gravity_well/` (beside the asteroids, so the transparency sweep covers it):
`Node2D` root answering `hazard_info()`, registered with `Hazards`, an animated top-down sprite (swirl rings), and a
hull-stress pulse: every `stress_period` (0.5 s) each ship (`enemies` + `player`) within `damage_radius` gets
`stress_damage` through a direct `received_damage.emit()`. **Decide whether shields absorb stress**: a direct emit
bypasses `EnemyShield` (it hooks `area_entered`, Ph5) — recommendation: they do not (the stress is hull stress, IDEAS'
own word), stated in `HAZARD.md`. No physics body (ships and shots pass through; it is a field, not a rock), so it is
**not** a LOS blocker. Telegraph: the sprite's inner glow brightens with the pull felt (`StateLight` colours; a ship
in the stress radius flashes as damage lands). "Bait enemies into the well" (R6.11) falls out of drift + capture: a
Swarm Drone chasing a player across the core is captured (§3.1).

### 2.5 Energy Anomaly (R6.12) — (judgement; no citable source)

The IDEAS ask for one of "movement, projectiles, shields, or targeting", used sparingly and readably.

| Option | Effect | For | Against |
|---|---|---|---|
| **A. Swirl (recommended)** | A **tangential** drift (`tangential_at(pos)`, same integrator as the pull, rotated 90°, clockwise or counter-clockwise per instance) on ships *and* opted-in projectiles; **pulsed**: 1.0 s telegraph (rings brighten), 2.5 s active, 3.0 s quiet | Reuses §2.3's machinery entirely; distorts movement and projectiles together with one visible rule ("the swirl turns everything clockwise while lit"); the pulse is the "less predictable" part, and it is readable because it is telegraphed | A second field kind in `HazardInfo` (`tangential_force`) |
| B. Shield suppression | Shields neither absorb nor regenerate inside | Simple | Touches `EnemyShield` and the player `Shield`; overlaps Ph9's disruption theme; invisible unless shields are up |
| C. Target scramble | Enemy `TargetInfo.aim_direction` accuracy degraded inside; player homing missiles lose lock | Interesting with the Sniper | Invisible effect (fails "readable"); touches player weapons that Ph9 also retargets |

**Recommend A**, one anomaly variant shipped. B and C are owner options (Q5), not built. Avoidance reads the anomaly
as danger only while active or telegraphing (`avoid_weight` 0.7), so ships visibly route round a lit anomaly and cut
through a quiet one — a pattern the player can learn.

### 2.6 Projectiles in fields (R6.10, S12)

A projectile opts in by answering `hazard_pull_scale() -> float` and sampling `Hazards.pull_at()` /
`tangential_at()` in its own `_physics_process`, bending its heading (rockets: `_heading`; missiles: `rotation`;
ordnance: its velocity).

| Option | Bent | Lifetime gates |
|---|---|---|
| **A (recommended)** | Enemy rockets (all five kinds), the Bomber's gravity and pursuit bombs, player homing and warhead missiles. **Not** bullets, enemy rounds or mines | Rounds' and player bullets' straight-line rows untouched; rockets / bombs already have time caps that bound them regardless of path (their distance cap is from the origin, so a curved path only shortens reach) |
| B | Everything, with a per-family scale (bullets 0.25) | Every round and bullet lifetime row must be re-derived; a pooled bullet's `reset()` must clear its bend |
| C | Nothing | Contradicts §6.7 |

**Recommend A** (owner question Q4): heavy, guided ordnance "feels" gravity — the IDEAS' "mass/strength rules"
inverted into a readable game rule ("rockets bend, bullets fly true"). Mines are excluded so Ph4's mine-wall
arithmetic stays valid.

### 2.7 Gravity Field weapon (R6.15, S4)

**What it is:** a temporary `HazardField` (`kind = &"gravity_field"`): `movement_penalty` inside `radius` for
`duration`, no pull, no damage. The penalty scales the enemy mover's `max_speed`, the Open Space ship's thrust, speed
ceiling and `boost_exit_speed`, and the Assault fighter's `move_speed` and dash speed — "movement/boost
effectiveness". **Strongest only, no stacking, a floor** (F12): `Hazards.penalty_at()` returns the max of the fields
covering a point, capped at 0.5; enemies feel `penalty · (1 − hazard_resistance)`.

**Who fires it:**

| Option | For | Against |
|---|---|---|
| **A. The Bomber's gravity bomb leaves one where it detonates (recommended)** | The Bomber is the battlefield-shaping enemy (IDEAS §5.5) and its bomb is already *named* "gravity bomb" but has no gravity (sweep: "a name only"); no new enemy, launcher or pool; the field is where the blast was, so it is telegraphed by the bomb's own warning | Changes `test_enemy_ordnance.gd` / `test_bomber.gd` rows that assert a gravity bomb's detonation; the Bomber is in level 1 (2 spawns, DURATION sections only) |
| B. A new ordnance kind / rocket kind | Separate from existing balance | A fourth bomber kind needs a choice rule and its own tests; a rocket kind changes the corvette's salvo table |
| C. Support Ship ability | Fits "support" | The Support Ship is a protector, not a controller; overloads its brain |

**Recommend A.** Starting values in §3.3.

### 2.8 Wrecks and debris (R6.13, R6.14, R6.17, S6, S7)

**Family** `assault/scenes/hazards/wreck/` (one script, `Wreck`, with exports; scenes per size / art variant):
- **Body**: `CharacterBody2D` on layer 1 (`ENVIRONMENT`), moved by its own position writes (the `SmallAsteroid`
  drift precedent) — hard cover that ships physically collide with, and the ray in `LineOfSight` hits it.
  `blocks_line_of_sight()` returns `blocks_los` (true for medium and large wrecks and placed structures, false for small
  debris) and `HazardInfo.line_of_sight_blocker` mirrors it.
- **Shot stopping**: a `HurtBox` (512, mask 96) with `Health` so player shots and rockets are consumed (player bullets
  react only to areas — `bullet.gd:113`). Inert wrecks have high HP (destructible over time); explosive wrecks low.
  **Enemy rounds currently pass through everything except the player hurtbox** (`enemy_bullet.tscn` mask 128). For
  cover to be two-sided, the wreck needs a shot-blocking area that rounds and rockets see. Options: put it on
  `hazard_contact` (1024) and add 1024 to round / rocket masks — which also makes rounds stop on **asteroids**
  (rockets already hit asteroids, Ph5) — or allocate a dedicated named layer. Recommendation: 1024, accepting the
  asteroid consequence as consistent ("terrain relevant to combat", §28); owner question Q9.
- **Contact**: a low-damage contact `HitBox` on 1024 (the asteroid precedent: "collision hazard").
- **Not an enemy**: never in `enemies`, never scored, never a homing target.

**Where wrecks live — the `ENEMIES_CLEARED` trap** (`level_director.gd:170` waits on the enemy container's child
count): a wreck in the enemy container would hold a section open. **Recommend a `HazardContainer`** found through
`Hazards.container(tree)` (group `hazard_container`), added to the level-1 scene and the hub; **no container → no
wreck** (never a fallback into the enemy container). Tests inject one.

**Spawning on death:** `BaseEnemy` death flow gets one hook (beside `explode()`): if the config's `wreck_chance > 0`,
the brain's seeded `rng` rolls, and the alive cap is not reached, spawn the enemy's wreck scene at its position and
rotation, inheriting 25 % of its velocity (judgement). Deterministic (seeded) for tests. Config fields are flat
(`wreck_chance`, `explosive_wreck_chance`) on `ShipConfig` (default 0), so the isolation gate stays green.

**Lifetime (one owner):** a wreck frees itself: Open Space after `wreck_lifetime` (fade the last 2 s) or when the
alive cap evicts the oldest; Assault when it leaves `EnemyWorld.projectile_world_rect()` or its time cap
(`ProjectileLifetime`, which emits and never frees — the wreck connects `expired → queue_free`). In Assault it drifts
downward so it reads as left behind by the scroll (judgement: the asteroids' drift precedent).

**Explosive wreck** (from ordnance carriers — Bomber, Missile Corvette — the readable reason): low HP, glows
(`StateLight` CHARGING-orange) and detonates when shot or after a fuse once a ship touches it; the blast should hurt
**everyone** — it is the environment, not an enemy weapon (Ph5 kept *enemy* blasts player-only; Ph8 owns enemy friendly
fire). Mechanically: the Ph5 rocket-impact precedent, a HitBox on 32 | 256 reaches enemies, plates, asteroids and the
player. It leaves a short **unstable reactor field** (§0 S8; a damage-only `HazardField`). Owner question Q8.

**Pre-placed structures** (satellite, cargo platform, station module) are the same `Wreck` with `drift = 0`, no
lifetime, high HP, art variants — the hub's tactical space (§4.1).

### 2.9 Line of sight and `can_see_player()` (R6.17, S6)

`LineOfSight` needs no change. Add `EnemyBrain.can_see_player() -> bool` (from the actor's position to
`TargetInfo.player(tree)`, excluding the actor's own RID; physics-step only, which the brain tick is). The Sniper
and Support Ship keep their direct calls (optional migration). A test row: a wreck between a sniper and the player
makes `can_see_player()` false and the sniper refuses to fire; small debris (`blocks_los = false`) does not; the
Missile Corvette still fires (§28).

### 2.10 Debris Charge (R6.16, S5)

| Option | How | For | Against |
|---|---|---|---|
| **A. Broken plates fly off (recommended base)** | When an `ArmorPlate` breaks, the Ram spawns a `DebrisFragment` (`Wreck` family, small, `blocks_los` false, contact damage, tumbling) from the plate's texture and transform, thrown outward along the breaking hit's direction at ~200 px/s, lifetime ~3 s | The player's own rocket turns armour into a moving hazard — readable cause and effect; no brain change | Passive: "enemy breaks off" is weaker |
| B. The Ram jettisons a plate as an attack | Once per life, after a missed charge, a cracked plate (≤ 50 % HP) is thrown at the player's predicted path; the Ram loses that plate | A real enemy weapon ("area-control weapon", §11.4), a risk/reward the player can read | A new brain branch; trades the Ram's armour, changing its plate tests and the 0.40 s-margin deadline row if it alters timing |

**Recommend A, with B as the owner's option (Q7)**: A delivers "an armour fragment that becomes a moving hazard" with
the least risk to the Ram's thin-margin rows; B is the more literal reading of "enemy breaks off" and can be added in
one task on top of A's fragment. The fragment is born after the plate is gone (Ph4: a part resolves each hit once).

### 2.11 Hazards as tools (R6.9, R6.14)

- **Sniper hides behind wreckage.** `choose_firing_point()` already scores candidates with weights (`w_sep`,
  `w_travel`) — a position choice, where weighted sums are fine (F8). Add **cover candidates**: for each LOS-blocking
  wreck within `cover_search_radius`, the point on its far side from the player (F9's "opposite the threat",
  regenerated each pick), stepped sideways to the nearest point with a clear line to the player ("peek"), plus a
  `w_cover` bonus for any candidate within `cover_radius` of a blocker whose silhouette sits near the player→point line
  (partial cover — Killzone doubles the LOF weight with partial cover, F8). Keep the existing LOS filter (it must see to
  fire). Hysteresis 15 % on re-picks (F10). The Sniper's tiers and path filters stay; with no wreck near, the pick is
  unchanged (a pass-through row).
- **Fighter uses a wreck as cover before a pass.** `_derive_pass()` picks the start point S and `_hold_station` holds
  there. If a blocker lies within `cover_shift_max` of S, move S to the blocker's far side from the player and hold
  there occluded (`can_see_player()` false) until the pass opens; F9's claim rule — one fighter per wreck — via a
  `claimed_by` field on the wreck (F11's ticket idea).
- **Ram pushes the player toward a well.** While a well is within `well_use_range` of the player, `_choose_side()`
  prefers the side that puts the player between the Ram and the well (charge direction within ~30° of player→well),
  so both the charge and the ARMOR shove (`contact_profile.gd` `_shove`, owner → target) send the player toward it;
  the Ram avoids the well while approaching (normal avoidance) and ignores it during CHARGE (boost). One Ram at a time
  (a ticket on the well, F11). Only if its LINE_UP still fits the budget gate (the 0.40 s margin row must stay green).
- **Drones skim the edge**: profile only — Swarm / Razor `hazard_margin` small (§3.2), so their context stage lets them
  run along a hazard's radius.

### 2.12 Art (R6.18)

New, under `pixel-art-generation` (strict top-down, `high top-down`, `isometric: false`, `scripts/pixellab.sh`, look
at every image, transparency sweep): gravity well (animated rings / accretion swirl, ~128–192 px visual, the field
radius drawn as a faint ring), energy anomaly (animated, distinct colour from the well — the IDEAS' "cyan/blue =
shield" is taken, so violet / magenta for the anomaly, **judgement**), gravity field (a translucent ring for the
duration), faction wrecks (one per size class: small 32–48, medium 64–80, large 96–120 — dark hull, **lights off**,
broken silhouette, IDEAS §21.1 "dark/off = destroyed"), three placed structures (satellite, cargo platform, station
module), the explosive-wreck glow. Drifting debris reuses `debris_1..6.png` (grey, generic — acceptable for scrap;
faction wrecks need the navy / crimson palette). Each hazard gets a `HAZARD.md`.

### 2.13 Recommended answers to `1-context.md`'s open questions

| # | Question | Recommendation |
|---|---|---|
| 1 | Context steering, nudge, or both? | Context steering as a mover stage (§2.2 D); no repulsion nudges. |
| 2 | Pull model | Mover-held drift with exponential decay, after the accel limit and boost, before the corridor; applies while boosting; players integrate with their own physics (§2.3). |
| 3 | Mass / resistance | One flat `hazard_resistance` per config (0..1), set on the mover; not derived from speed (judgement: speed is already a tuned feel number). |
| 4 | Which projectiles bend | Rockets, bombs, player missiles; not bullets, rounds or mines (§2.6). **Owner question.** |
| 5 | Anomaly rule | One variant: pulsed tangential swirl on ships and opted-in projectiles (§2.5). **Owner question** (B / C variants). |
| 6 | Who fires the Gravity Field | The Bomber's gravity bomb leaves it (§2.7). |
| 7 | Debris Charge passive or active | Passive fragments from broken plates; active jettison as an option (§2.10). **Owner question.** |
| 8 | Wreck rules | Config chance + seeded rng + alive cap; `HazardContainer`, never the enemy container; explosive variant from ordnance carriers, blast hurts everyone (§2.8). **Owner question** on the everyone-blast. |
| 9 | Explosive / cover vs enemy fire | Wrecks stop enemy rounds via 1024, which also makes rounds stop on asteroids (§2.8). **Owner question.** |
| 10 | Shipped placement | Hub tactical space; level 1 only gets what its enemies bring; no placed well / anomaly in level 1 (§4). **Owner question.** |
| 11 | Bit 12 | Not allocated (sampled design) unless the plan picks an area design (§0 S3). |
| 12 | Rail / legacy enemies | Mover-driven only (§0 S11). |

---

## 3. Starting values (judgement unless a finding is cited)

### 3.1 Gravity well and the drift integrator

`radius` 420 px, `core_radius` 90 px, `pull_force` 520 px/s², taper over the last 15 % (357–420 px), `damage_radius`
150 px, `stress_damage` 5 per `stress_period` 0.5 s (10 /s; the player ship has 50 HP), drift `half_life` 0.35 s
(k = 1.98 /s). Reach is short and the strength concentrated (F7); the core is clamped (F6).

Field strength: 520 px/s² at ≤ 90 px; 334 at 140; 234 at 200; 131 at 357 (taper starts); 0 at 420.

Terminal inward drift `a · (1 − res) / k` against each ship's own speed (speeds from the shipped configs; resistance
from §3.2):

| Ship | Own speed (px/s) | Resistance | Drift at the core | Escapes the core? | Captured inside |
|---|---|---|---|---|---|
| Swarm Drone | 220 (`max_speed`) | 0.0 | 263 | **no** | ~107 px |
| Razor Drone | 200 approach / 480 dash | 0.0 | 263 | only by dashing | ~118 px at approach speed |
| Fighter | 300 | 0.1 | 236 | yes (64 px/s net) | — |
| Gatling Interceptor | 260 | 0.15 | 223 | yes (37 net) | — |
| Support Ship | 270 | 0.1 | 236 | yes (34 net) | — |
| Missile Corvette | 210 | 0.4 | 158 | yes | — |
| Ram Corvette | 280 cruise | 0.5 | 131 | yes | — |
| Assault player | 360 `move_speed` | 0 | 263 | yes (97 net) | — |
| Open Space player | thrust 380 px/s² vs field | 0 | — | thrust out only beyond **123 px** (where a < 380); boost 700 escapes anywhere | inside 123 px without boost |

So: drones that wander into the core are dragged in and stressed (R6.11's bait); fighters and heavier ships escape
slowly; the player must boost out of the core in Open Space. The plan should confirm each row with a test, since the
drift approaches terminal with a 0.5 s time constant (rows assert the asymptote's sign, not the exact value).

### 3.2 Hazard profile per enemy

| Enemy | `hazard_avoidance` | `hazard_margin` (px) | `hazard_resistance` | Note |
|---|---|---|---|---|
| Swarm Drone | 1.0 | 12 | 0.0 | skims (IDEAS "agile drones skim") |
| Razor Drone | 1.0 | 16 | 0.0 | skims; dashes ignore (boost) |
| Fighter | 0.8 | 60 | 0.1 | |
| Gatling Interceptor | 0.8 | 60 | 0.15 | |
| Sniper | 1.0 | 90 | 0.1 | cautious; uses wrecks as cover (§2.11) |
| Support Ship | 1.0 | 80 | 0.1 | |
| Bomber | 0.6 | 70 | 0.4 | heavy |
| Missile Corvette | 0.7 | 80 | 0.4 | heavy |
| Ram Corvette | 0.5 | 60 | 0.5 | heavy; CHARGE ignores (boost) |

Avoidance lookahead 0.6 s; 16 slots; previous-direction blend 0.5.

### 3.3 Gravity Field, anomaly, wrecks, fragments

- **Gravity Field** (from a gravity-bomb detonation): `radius` 150 px (≥ the bomb's blast, judgement), `duration` 3.5 s,
  `movement_penalty` 0.4 (F12: 40 % sustained), floor / cap 0.5, strongest-only.
- **Anomaly**: `radius` 300 px, `tangential_force` 260 px/s² at the core with the well's falloff, cycle 1.0 s telegraph /
  2.5 s active / 3.0 s quiet, `avoid_weight` 0.7 while telegraphing or active, 0 when quiet.
- **Wrecks**: `wreck_chance` — Swarm 0, Razor 0, Fighter 0.2, Gatling 0.2, Sniper 0.3, Support 0.3, Missile Corvette
  0.5, Bomber 0.6, Ram 0.5; `explosive_wreck_chance` (of those wrecks) Bomber 0.5, Missile Corvette 0.5, else 0. Alive
  cap 8 (Open Space), 4 (Assault). Open Space life 40 s (fade 2 s). Assault: drift down 60 px/s plus 25 % of the death
  velocity, `ProjectileLifetime` world rect + 20 s cap. Inert HP 200, explosive HP 20; explosive blast radius 110 px,
  25 damage; reactor field 2.0 s at 8 /s within 90 px. Contact damage 10.
- **Debris fragment**: ~200 px/s outward, slows at 120 px/s², life 3.0 s, contact damage 12, `blocks_los` false.
- **Cover**: `cover_search_radius` 700 px (Sniper), `cover_radius` 140 px, `w_cover` = the existing separation weight
  (F8's 2:1 partial-cover ratio as a starting relation), re-pick hysteresis 15 % (F10); Fighter `cover_shift_max`
  220 px; Ram `well_use_range` 600 px, approach cone 30°.

---

## 4. Placement

### 4.1 Open Space hub — one tactical space (R6.5, S6, S13)

The hub has no physics bodies, which is why LOS is "fixture-proven only". One placed tactical space, IDEAS §18.6's
sketch: a gravity well, two or three placed structures / wrecks forming cover, an anomaly nearby — **outside every
patrol group's idle ring plus its `perceive_radius`, and outside every interactable's reach**, so it never ambushes a
mission dwell (the `test_sector_hub_patrol.gd` clearance rule; patrol rings sit at 1300 / 1500 / 1700 / 1900 px around
the origin). Candidate: a bearing in a free arc on a ~2600–3000 px ring, where enemies arrive only by chasing the player
(the place the player chooses to fight). The plan must compute the clearance numbers and **append** any new seeded
draws after the existing fourteen (`sector_hub.gd:75-79`). A `HazardContainer` node joins the hub scene so wrecks from hub
kills persist. **Placed hazards are scene nodes, not rng draws** — they do not disturb patrol seeds.

### 4.2 Assault (level 1)

- **Come with existing enemies:** wrecks from deaths (all three sections: their chance and cap must not move the
  density gates, which count enemies in `enemies` / the container, not wrecks — wrecks live in the `HazardContainer`),
  the Bomber's Gravity Field (its two spawns are in DURATION sections), the Ram's fragments.
- **Placed wells / anomalies: none this phase** (owner question Q10). The corridor makes a static field strange in an
  autoscroller unless it drifts, every level-1 gate is calibrated without one, and the cloud_descent ram row has
  0.40 s of margin. Ph15 (Assault migration to spawn layouts) is the natural owner; the mechanics are proven in both
  harnesses here.
- **Risk to watch:** a wreck that drifts into the player's lane is a physical obstacle against the Assault position
  clamp (the asteroids already behave this way; no squeeze bug is recorded). A test row: a wreck pushed against the
  player at the clamp edge never pins the player for more than a frame (or the wreck yields).

---

## 5. Testing requirements → gates

All behaviour rows are **hand-ticked and dual-mode** (`open_space` / `assault` labels, harness built in the body,
`_tick()`), because the design samples the field rather than relying on physics overlaps. Only rows that need real
collision (wreck blocks a body, a shot hits a wreck, LOS rays) use real physics on the 8× clock.

| Requirement | Test (new unless named) | Key rows (boundary cases in bold) |
|---|---|---|
| R6.1, R6.2 registry | `tests/unit/test_hazards.gd` | register / unregister on tree enter / exit; `count()` 0 after free; `around()` reach; `pull_at` field values (core clamp, 1/r, taper, **0 at radius**, **finite at r = 0**); `penalty_at` strongest-only and **capped at 0.5**; a duck-typed fixture hazard joins with no AI change |
| R6.7 pass-through | `tests/unit/test_enemy_mover.gd` (extend) | **no hazard → bit-identical velocity and rotation** for instant, accel-limited, boosting and constrained movers |
| R6.7, R6.8 avoidance | `tests/unit/test_hazard_avoidance.gd` (pure function) + `test_enemy_dual_mode.gd` rows | heads round a hazard toward a target behind it **without stalling (speed > 0) or entering**; inside a hazard → steers out; margin 12 skims closer than margin 90; avoidance 0 → straight through; **boosting ignores**; corridor still applied last in Assault; 16-slot heading interpolated (no 22.5° quantisation) |
| R6.3, R6.11 pull on enemies | `test_enemy_dual_mode.gd` rows | an idle enemy beside a well drifts inward in both modes; resistance 0.5 drifts half as far; **a Swarm Drone in the core cannot leave, a Fighter can** (§3.1 table); drift persists through a boost; `halt()` zeroes it; Assault: never past the hard band |
| R6.3 pull on players | `test_open_space_*` (new file) + an Assault player row | Open Space ship drifts inward with no input; **thrust escapes outside 123 px, not inside; boost escapes inside**; rotation unchanged; Assault fighter drifts and stays inside its clamp |
| R6.11 hull stress | `test_gravity_well.gd` | damage pulses inside `damage_radius` only; **just outside: none**; enemies and player both; shields do not absorb (or do, per the plan's decision) |
| R6.12 anomaly | `test_energy_anomaly.gd` | tangential (not radial) drift, direction per instance; quiet phase → no effect; telegraph precedes active; avoidance reads it only while lit |
| R6.10 projectiles | `test_hazard_projectiles.gd` | a rocket / bomb / player missile bends toward a well; **a round and a player bullet do not**; lifetime still ends them (time cap) |
| R6.15 Gravity Field | `test_gravity_field.gd`, `test_enemy_ordnance.gd` / `test_bomber.gd` (extend) | a gravity bomb's detonation leaves a field; Open Space ship's thrust / ceiling / boost scaled by 0.6; Assault move / dash scaled; enemy `max_speed` scaled by `(1 − 0.4 · (1 − res))`; **two overlapping fields = strongest only**; expires at `duration` |
| R6.13, R6.19 wreck spawning | `test_wreck.gd` | seeded chance (same seed → same wrecks); **cap evicts the oldest**; spawns into `HazardContainer`, **never the enemy container** (an `ENEMIES_CLEARED` replay ends on time with wrecks alive); never in `enemies`; frees itself (Open Space life, Assault world rect) — one owner; explosive wreck: shot → blast hurts player **and** enemies (if Q8 = yes) → reactor field |
| R6.17, R6.19 LOS | `test_line_of_sight.gd` (extend), `test_sniper.gd` (extend) | a wreck blocks `LineOfSight.clear` and `can_see_player()`; **small debris does not**; the sniper refuses to fire through a wreck; the missile corvette still fires |
| R6.14, R6.9 cover / tools | `test_sniper.gd`, `test_fighter.gd`, `test_ram_corvette.gd` (extend) | sniper picks a cover candidate when a wreck is near, **the same pick as today when none is**; fighter holds occluded behind a wreck before its pass; **two fighters do not claim one wreck**; ram's charge direction within 30° of player→well when a well is near, unchanged when none; existing attack-in-budget / deadline rows still green |
| R6.16 Debris Charge | `test_ram_corvette.gd` (extend) | a breaking rocket spawns one fragment moving away from the hit; the plate still resolves once; fragment hurts on contact and frees itself |
| R6.18 art | `test_entity_sprite_transparency.gd` (existing sweep) | every new sprite passes (no painted background) |
| Hub placement | `test_sector_hub_patrol.gd` (extend) | the tactical space clears every patrol ring + perceive radius and every interactable; patrol seeds unchanged |
| Single writer | `test_enemy_mover_single_writer.gd` (existing) | still green: hazards never write enemy motion |
| Registry leak | `scripts/check-test-leaks.sh` | clean after the hazard suites |

---

## 6. Notes for the plan stage (sizing, ordering)

- **Order:** registry + `HazardInfo` + container → mover drift (pull) and players' pull → context stage → gravity well
  (+ art) → anomaly → wrecks (+ death hook, LOS, art) → `can_see_player` + sniper / fighter cover → ram well use and
  Debris Charge → Gravity Field (bomber) → projectile opt-in → hub tactical space → docs / as-built. The context stage
  depends only on the registry and can run beside the pull.
- **Large items** (own plan + review): the context stage in `EnemyMover` (every enemy's hot path), and wrecks (death
  flow + new family + two modes + container). Medium: pull + players, gravity well, anomaly, Gravity Field, sniper cover,
  fighter cover, ram tools + Debris Charge, hub placement. Small: `can_see_player()`, projectile opt-in (if A), docs.
- **Gate time:** ~40 s of headroom (≈ 200 / 240 s). The avoidance stage must early-out on `Hazards.count() == 0`, or
  `test_fighter_squad.gd`'s 186k mover ticks pay for it. Hand-ticked dual-mode rows ≈ 0.02–0.06 s each; real-physics
  rows on the 8× clock ≈ 0.25–0.4 s. Give each task an allotment (Ph5 precedent) and run `scripts/gate-time.sh` before
  and after; a gate-room task first is only needed if the plan's sum exceeds ~35 s.
- **Docs:** each hazard gets `HAZARD.md`; `global.md` gains `global/hazards/`; `PROJECT.md` conventions gain "hazards
  are sampled by the body; the mover owns enemy drift"; `CLAUDE.md` gains the new gates. `DECISIONS.md` must log: the
  context-steering stage (keeps Ph1's rejection of weighted blending), bit 12 not allocated (revisits Ph1), §11.4
  Gravity Field moved here from Ph7, EMP zones to Ph9, capital wrecks to Ph19, the `HazardContainer` rule.
- **Owner questions to surface in the plan summary:** Q4 projectiles, Q5 anomaly variant, Q7 active jettison, Q8
  explosive-wreck blast hurts enemies, Q9 wrecks stop enemy rounds (and therefore asteroids do too), Q10 no placed
  well / anomaly in level 1.
