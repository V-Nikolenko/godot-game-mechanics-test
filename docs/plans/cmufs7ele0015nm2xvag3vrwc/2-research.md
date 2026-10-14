# Research — Enemy rework, phase 4: Bomber, Sniper and Ram Corvette

Epic `cmufs7ele0015nm2xvag3vrwc`, research task `cmufs7ell0019nm2xnsxx8z94`, 2026-10-07.

`1-context.md` (next to this file) is the code inventory: requirements `R4.x`, files, reusable pieces, conventions and
risks `C1`–`C16`. This file holds what the plan decides from:
- §0 the scope check against the code and the earlier phases' as-built records;
- §1 outside findings, with their tradeoffs and typical values;
- §2 candidate approaches and behaviour sketches per enemy, each with a recommendation (§2.9 answers the open
  questions);
- §3 starting values and hub placement;
- §4 the `ENEMIES_CLEARED` deadline arithmetic;
- §5 the testing requirements, mapped to gates;
- §6 sizing and ordering notes for the plan stage.

Facts were read at `00aced5` on `agent/auto-dev`. Anything not read directly, or a judgement with no citable source,
is labelled **(judgement)**.

---

## 0. Scope check

The scope text was written before Phases 1–3 ran. Checked against `DECISIONS.md` (Phase 1/2/3 *as built*), the Phase 3
`REPORT.md` and the code, it changes as follows. Each item is an explicit adjustment the plan must carry.

| Id | Scope item | Finding | Adjustment |
|---|---|---|---|
| S1 | §3.2 `break_contact` | Not built in Ph1–Ph3 (DECISIONS Ph3 deviation 20: "`break_contact` stays with the Sniper (Ph4)"). `Steering.retreat_from` / `evade` exist; neither has a lateral component or a "until distance D" notion. | **In scope as planned.** Build `Steering.break_contact(pos, threat_pos, threat_vel, side, max_speed)` as a pure static, plus the mover one-liner, like every other primitive. |
| S2 | §12 `persist_after_owner_death` | DECISIONS Ph1 ("documented only … becomes a `BulletPool` policy in Ph5") and Ph2/Ph3 "handed to later phases" assign it to **Phase 5**. `projectile_lifetime.gd:26-28` documents it as a Ph5 flag. Nothing implements it. | **Pulled forward into Ph4**, because the epic text names it and the Bomber's mines need it (a mine that vanishes when its bomber dies is not area denial). Ph5 (rockets) then **builds on** it rather than creating it. This contradicts the recorded "Ph5" decision on purpose; the plan must log it in `DECISIONS.md`. Shape: see §2.3. |
| S3 | §28 real `can_see_player()` | `TargetInfo.line_of_sight(_from)` is still the stub returning `has_target` (`target_info.gd:117-118`). **It is pinned by `tests/unit/test_target_info.gd:130-132`** (`1-context.md` said "no caller"; the tests are its only callers). | In scope. The stub's two assertions change in the same task (they pin the stub, not an intent). The signature needs a world (§2.4). |
| S4 | §13.1 Armour, §16 Armour contact profile | `DefenseProfile.apply_alternate()` is one-way and documented "general multi-state armour is a later phase" (Ph1). `ContactProfile.Mode` has NONE/COLLISION/RAMMING/EXPLOSIVE; DECISIONS Ph2: "Armour collision is Ph4's new mode on the same enum". | In scope. **The armour does not need `DefenseProfile` to become multi-state**: the station's turret/core pattern (independent child hurtboxes + `is_armored()` on the core) already models it (§2.1, A3). `DefenseProfile` keeps its one-way switch; the Ram Corvette stops using it. The `ARMOR` contact mode is a fifth enum value. |
| S5 | Old Ram's layer immunity | The live `RamShip` excludes bit 64 from its hurtbox mask (`DefenseProfile` mask 33) and the player's sniper shot stops on group `ram_ships` (`bullet.gd:113`). The Ram is **not in group `enemies`**, so homing rockets, EMP, nova, dash and the beam never select it. | Retire both (epic: "not the old layer-based bullet immunity"). Joining `enemies` is a gameplay change for six player systems (C4); the plan must test at least homing rockets and the beam against the Corvette. `test_station_reinforcements.gd:410-433` rejects the ram class **by mask**; its reason changes. |
| S6 | §31 / §38 sniper `FLY_IN_TIME` and path retreat | Only **2** of 26 level-1 snipers use the `FLY_IN_TIME`-matched `sequence(...)` (deep_space 0.5 s pair, `b.sniper_enemy()`); the other 24 (`b.sniper()`, an alias of the same scene) aim while drifting on a straight rail, and some (`free_after(4.0)`) never fire (inferred from 2.5 + 2.0 + 0.5 = 5.0 s to the first shot). | In scope, and larger than the AUDIT implied: **26** sniper lines, not 2. Pin trigger/offset/delay only (Ph3 pin shape), not legacy fire timing (C14). |
| S7 | §5.6 Assault "tactical off-screen band" | `AssaultCorridorConstraint.inner_rect()` is the camera's whole pan range, **1480 × 1480** (x −100…1380, y −380…1100), while the camera shows 1280 × 720 of it. A sniper can stand **inside** the rect, off camera, with zero constraint pressure. Outside the rect the soft band pushes at up to 200 px/s, so nothing can be stationary there. | The "off-screen band" is the part of `inner_rect()` the camera is not currently showing, not a band outside the corridor. Firing points are chosen inside `inner_rect()` shrunk by a margin (C10). No change to the corridor constraint is needed. |
| S8 | §5.5 bomber "clamp bomb placement to the corridor" | Same rect. | Clamp drop/aim points to `inner_rect().grow(-margin)` in Assault; Open Space has no clamp. Done in the brain (a point clamp), not in the constraint (which filters velocity). |
| S9 | §28 "Sniper refuses to fire if a large asteroid blocks the shot" | Line-of-sight blockers today: asteroids (group `asteroids`, `asteroid_base.gd:34`) exist in level 1 **only in `asteroid_belt`**, which has no enemies. **The hub has no physics bodies** that could block a ray (Area2D triggers and pickups only). | The LOS refusal is real code exercised by **fixtures** in both harnesses; in shipped content it rarely triggers until Ph6 (wrecks) and Ph19 add blockers. Say so in the plan rather than inventing hub obstacles. |
| S10 | §23 / §21–22 sprites | Current art: `bomber.png` 92×42, `sniper.png` 64×64, `ram_ship.png` and `ram_ship_damaged.png` 32×32 (the Ram is far under its 72–96 px target). | In scope: three new ship sprites (Bomber ≈ 104–112 px wide, Sniper ≈ 56–64 px narrow, Corvette ≈ 80–88 px). The visual-state work is in §2.7 (S12). |
| S11 | Heavy Shell consumer | Ph3: "Heavy Shell's first consumer: Ph4 (Bomber/Ram) or Ph10". | **Not needed by this phase.** No Ph4 enemy's IDEAS text asks for a shell; giving one to the Bomber or Ram would be building ahead of the spec. It stays with Ph10 (Heavy Gunship) (§2.8). |
| S12 | §23 visual states | Sniper "weapon unfolds during charge"; Ram "armour plates glow during charge and physically disappear when destroyed". | Do this with **child sprites**, not frame animation: plates as their own `Sprite2D`s (hidden on break = "physically disappear"; modulate for the glow), the sniper's barrel as a second sprite that extends/scales during AIM (§2.7). |
| S13 | `SectorHub` ambient spawn | `_spawn_patrol()` already places Swarm (1300 @90°), Razor (1300 @270°), fighter pair (1500 @180°), Gatling pair (1500 @0°) from **one seeded rng**. | Append three groups at the free diagonals, drawing from the rng **after** the existing draws so the earlier groups' seeds do not move (§3.1). `test_sector_hub_patrol.gd` gains a clearance row per group. |
| S14 | §5.5 "all three ordnance types" in Assault level 1 | Level 1 has 2 bombers, both in `planet_approach` (DURATION). | Keep bombers out of `ENEMIES_CLEARED` sections and gate that with a boundary row (C5, §4). |
| S15 | Bonus Drone | §38 keeps it unchanged. | Out of scope; nothing in Ph4 touches it (R4.47). |
| S16 | Decoy telegraph "behind a difficulty flag" | No difficulty system exists (Ph16). | A `SniperConfig` bool (`decoy_telegraph`, default `false`) is the flag. Ph16 later maps a tier onto it. Default off means the shipped game never shows a decoy (§2.6). |

**Everything else in the scope stands as written.** Nothing an earlier phase built already delivers any of these three
enemies; the reusable machinery (brain/mover/steering, `DubinsPath`, `BurstClock`, `ContactProfile`/`ContactBlast`,
`ProjectileLifetime`, `EngagementBudget`, `AnchorIdle`, the dual harness) is listed in `1-context.md`.

---

## 1. Findings from shipped games and engine docs

A research subagent did the web searches; the URLs below were fetched and read unless marked *snippet only*. Pages
that 403'd were retried through `scripts/fetch-page.sh` (Valve wiki, ModDB, Killzone PDF via the reader proxy).
Sources that stayed unreachable are listed after the table. Ids `F1`–`F13` are used in §2–§3.

| # | Finding | Tradeoff for this phase | Typical values | Source |
|---|---|---|---|---|
| F1 | Half-Life 2's `npc_sniper` "keeps a target painted for [PaintInterval] seconds before shooting"; a *Faster Shooting* flag multiplies that by 0.75; it can be set to miss a number of initial shots on purpose, and it supports decoy targets. | A ready template for the Sniper: one config'd paint (AIM) time, difficulty as a **multiplier on it** (Ph16), and "warning misses" as an honest alternative to a decoy line. | ×0.75 paint time on the faster variant; `Initial Misses` count; no default `PaintInterval` given. | https://developer.valvesoftware.com/wiki/Npc_sniper (via reader proxy) |
| F2 | Halo 3 made sniper Jackals fairer with "slower targeting times" and a visor glow while sighting; the glow "functions both to warn the player and reveal the sniper's position". Halo Infinite's snipers aim "for a few seconds with a laser sight". | The telegraph also **gives the position away**, which is exactly why the Sniper must break contact after every shot (R4.15) and pick a new point (R4.12): a sniper that stays put after revealing itself is free kills. | "a few seconds" (no exact figure). | https://www.halopedia.org/Kig-Yar/Gameplay |
| F3 | Indie shipped examples: Operation: Havok's laser "flashes vividly between red and white before firing"; Counter Sniper uses an always-present glint plus a long inter-shot delay because a sniper "ha[s] a good chance to kill the player on their first shot". | A distinct **lock flash** marks the moment the aim stops tracking (our LOCK = `StateLight` COMMIT white). A tracking-until-fire laser is less fair than a frozen one. A long gap between shots lets the player recover — our relocation leg provides it. | No numbers. | https://empexori.itch.io/operation-havok/devlog/978848/devlog-3072025-update-5-sniper-rebalancing ; https://www.moddb.com/news/counter-sniper-designing-the-sniper (via fetch script) |
| F4 | Reaction-time data (fighting games): average simple reaction ≈ 265 ms (≈ 16 frames at 60 fps); 15 f "virtually unreactable", 27 f "quite easy to react", 45 f safe "even [for] absolute beginners". | Floors for every telegraph here: the Ram's 0.5–0.8 s wind-up (30–48 f) is comfortably reactable; the Sniper's **frozen LOCK must be ≥ ≈ 0.45 s** (27 f), because the rail round itself is near-instant and LOCK is the real dodge window (C8). Difficulty should shorten AIM, not LOCK. | 265 ms; 15 / 20 / 27 / 45 f at 60 fps. | https://ki.infil.net/reaction.html |
| F5 | An enemy that keeps turning toward the player during its wind-up shrinks the real reaction window; players ask for facing to freeze at wind-up (Path of Exile's change cited as making telegraphs "a lot easier to deal with"). Game Developer frames the pre-attack delay as the enemy saying "here I come… can you avoid my damage?" | The Ram **freezes its intercept line** at the end of WIND_UP at the latest (or tracks at a low capped rate during it), and never re-aims in CHARGE. The overshoot + wide turn is the dodge payoff. | No numbers. | https://forum.lastepoch.com/t/enemies-should-not-be-able-to-turn-while-theyre-winding-up-an-attack/19129 (player forum) ; https://gamedeveloper.com/design/enemy-attacks-and-telegraphing |
| F6 | A fake-out is fair only when it is readable and consistent, introduced gradually, and counterable: it "should punish expected reactions, not objectively correct ones"; "if players have no way to react … it feels like a cheap shot". | The decoy line must be **visibly different** from the real one (never the LOCK flash / COMMIT white), and it belongs behind the difficulty flag, after the real telegraph has been taught — which is what the scope asks (R4.18). | No numbers. | https://www.wayline.io/blog/the-art-of-the-fakeout-combat-design (blog) |
| F7 | Killzone's position picking (GDC Europe 2005): gather nearby waypoints, score each as a **weighted sum** of tactical annotations (proximity, line of fire to the threat, cover from others, inside preferred range), take the best; weights come from the AI's personality and are recomputed from current threats. | The Sniper's REPOSITION is this, with sampled candidate points instead of authored waypoints. Weights can be flat config fields. A "far from my last firing bearing" term is **our addition** (no source; it is what R4.12 asks). | Example weights: proximity 20; line of fire 40 (with partial cover) else 20; cover from secondary threats 20; in preferred range 10. | https://www.guerrilla-games.com/media/News/Files/gdce05_killzone_ai.pdf (via reader proxy) |
| F8 | Unreal's Environment Query System: a generator makes candidate points, tests score them, and **filter tests run before scoring** "so that fewer Items are returned and need to be scored". | Cheap filters first (inside `inner_rect()` in Assault, inside the distance band), the raycast LOS test only on the survivors: a handful of rays per relocation, not dozens. | No numbers. | https://dev.epicgames.com/documentation/en-us/unreal-engine/environment-query-system-overview-in-unreal-engine |
| F9 | Leading the player needs **damping** to stay fair: one developer predicts with velocity × projectile time × **0.64**, tuned so a full-speed sideways run escapes; a jam developer's 0.5 s full lead was "too strong" in their own words; Arco players complained when lead used dash velocity ("fires them where i dash to"). | The Bomber's predicted path uses a **lead factor < 1** on **smoothed** velocity, with a capped horizon, so a committed change of direction always escapes. The Open Space boost is the dash analogue: it should not be fully led. | Lead scalar ≈ 0.6; a 0.5 s undamped lead reported as too strong. | https://boardgamers2409.itch.io/plague-wardens/devlog/820382/enemy-balancing-antonio-roldan ; https://itch.io/post/12024854 ; https://steamcommunity.com/app/2366970/discussions/0/4434443557919428497 |
| F10 | Shmup conventions: a "bullet cancel" clears enemy shots on certain kills; "revenge bullets" fire when an enemy dies; enemy shots should be slower and brighter than the player's (halving enemy shot speed in one game changed play from "kill before they fire" to weaving). | Shootable ordnance needs a clear rule for what a shot does (defuse vs detonate small), and whether killing the Bomber cancels its mines is a **design decision**: cancelling rewards the kill; persisting (the scope's `persist_after_owner_death`) keeps the area denial. The scope chose persistence. Mines must be bright and readable. | Enemy shots ≈ ½ player shot speed in the cited case. | https://shmups.wiki/library/Glossary ; https://www.gamedeveloper.com/design/bright-slow-and-deadly ; "mine releases an aimed bullet when destroyed" is *snippet only* (shmups.system11.org) |
| F11 | Part-breaking: Monster Hunter World bounces/deflects hits on hard hitzones and breaking a part can soften it and remove attacks; Doom Eternal's weak points (Mancubus cannons, Arachnotron turret) are removed by specific hits and remove an attack; Horizon Zero Dawn's machines are "multi-layered animals with collectable components that could be shot off". | Supports the Corvette rule (bullets deflect, rockets break plates) as an established pattern. **Deflection needs its own feedback** (spark/flash, no damage), distinct from a damaging hit, and losing the plates must visibly change behaviour (faster, exposed). | MHW: hitzone 0–100; a hit bounces if hitzone × sharpness × adjustment ≤ 25; "weak" at 45+. | https://mhworld.kiranico.com/guide/understanding-monster ; https://blog.playstation.com/2017/02/24/the-making-of-horizon-zero-dawns-machines/ ; Doom Eternal *snippet only* (doomwiki.org 403) |
| F12 | Godot 4: `direct_space_state` is only safe inside `_physics_process()` ("accessing it from outside this function may result in an error due to space being locked"). `PhysicsRayQueryParameters2D` defaults: mask `4294967295`, `collide_with_bodies = true`, `collide_with_areas = false`, `hit_from_inside = false`; `exclude` is `Array[RID]`; masks are "much more efficient" than large exclude lists. | LOS runs on the brain's physics tick only; exclude the sniper's own body RID; set an **explicit mask** (bit 1, `environment`) instead of the all-bits default; leave `collide_with_areas` off, so hurtboxes, triggers and pickups never block — only bodies, then filtered by the opt-in rule (§2.4). | `create(from, to, mask, exclude)`; no published per-ray cost. | https://docs.godotengine.org/en/stable/tutorials/physics/ray-casting.html ; https://docs.godotengine.org/en/stable/classes/class_physicsrayqueryparameters2d.html |
| F13 | Projectiles parented under their shooter die with it; the usual fix is a level-owned container, or keeping the shooter alive (hidden) until its shots are gone. An Unreal pool plugin hit the same bug ("if I destroy one of these enemies the projectiles belonging to that enemy disappear!") and shipped an option to **orphan** active pooled actors so they outlive the pool (v1.4.5). | Our ordnance already lands in the level's container (`BulletPool` reparents to the grandparent); what dies with the Bomber is the **pool's ownership** (`_exit_tree → cancel_active`). The plugin's "orphan on destroy" is exactly P1 (§2.3): an explicit hand-over to self-ownership, each orphan with its own lifetime. | No numbers. | https://forum.godotengine.org/139658/bullets-destroying-with-enemy ; https://forums.unrealengine.com/t/plugin-object-pool-component/81338?page=9 |

**Unreachable or unusable:** Valve `Proto_sniper` (403); doomwiki.org *Destructible demons* (403 on both WebFetch and the
fetch script, snippet only); the 80.lv Horizon postmortem (announcement only, no content); Sparen's Danmaku Design Guide
A2 (read, nothing on prediction or telegraphs); a bugnet.io telegraph article (read, no numbers).

**No source found** for: the pursuit bomb's steering rate, mine trigger radii, the decoy's exact shape, armour-plate
HP, or "different firing position" metrics. Those values in §3 are **judgement**, derived from the shipped code where
possible.

---

## 2. Candidate approaches

### 2.1 Ram Corvette armour (C1, C2, open question 2)

The constraints, all read in the code:
- A bullet's `HitBox` (layer 64, mask **513**) and a rocket's `HitBox` (layer 32, mask **513**) both detect **any** area
  on layer 512, whatever that area's own mask says. Area detection is one-directional: what decides whether the
  *projectile* sees the plate is the projectile's mask, not the plate's.
- On overlap, `bullet.gd::_hit_is_deflected(area)` and the identical copies in `homing_missile.gd:56` and
  `warhead_missile.gd:33` ask `area.get_parent().is_armored()`. True → the projectile keeps flying, no `expired`.
  False → it is spent.
- `HurtBox.received_damage(damage: int)` carries no damage type. Its `accepted_damage_types` filter acts only on
  `area_entered`. Direct emitters (beam, dash, nova, shield overload, engine boost, laser ray) call `received_damage.emit`
  on the root `HurtBox` and bypass every filter.

| Approach | How | For | Against |
|---|---|---|---|
| **A1** Extend `DefenseProfile` to multi-state masks (the old design, generalised) | Plates are counted; the hull hurtbox mask excludes bit 64 until the last plate breaks. | Small diff; `DefenseProfile` already exists. | **Forbidden by the epic** ("not the old layer-based bullet immunity"). A bullet still *detects* the hull (its own mask has 512), sees `is_armored()` false, and is **silently consumed for 0**, which is what `test_enemy_hurtbox_geometry.gd`'s rationale and CLAUDE.md reject. Rejected. |
| **A2** One hull hurtbox, hit-direction sectors | Root `is_armored()` + a new hit-aware query; the brain maps the hit's bearing to a plate (front / left / right sector) and routes rocket damage to that plate's `Health`. | One hurtbox; no new child nodes. | Damage arrives as an int with no position or type, so the root has to read the overlapping `HitBox` itself in `area_entered`. Sectors are invisible to the player (a plate is a sprite, the sector a hidden angle). Direct emitters carry no position. More bespoke code. |
| **A3** Plates as child parts with their own `HurtBox` + `Health` (the station turret/core pattern), plus a **hit-aware deflect query** | Each plate node owns a small `HurtBox` (layer 512) with `accepted_damage_types = [ROCKET]` and its own `Health`. The hull `HurtBox` covers the body as the geometry gate requires; `RamCorvette.is_armored()` is `plates_alive > 0` and `_on_received_damage` deflects while armoured (the `SpaceStation` pattern, covering direct emitters, C2). Bullets/rockets gain one additive duck-typed check: if the target has `deflects_hit(hit_box: HitBox) -> bool`, use it; otherwise fall back to `is_armored()`. A plate answers `hit_box.damage_type != ROCKET`. | Reuses a pattern the gates already accept (the station's turrets are extra hurtboxes over an armoured core). Plates are visible sprites the player aims at. "Physically disappear" = free/hide the plate node. Station behaviour is byte-identical: it implements no `deflects_hit`, so the fallback path is today's code. No collision-layer change. | Three player-projectile scripts change (one line each plus a shared helper or three copies, as today). A homing rocket aims at the **root centre**, so it may cross the armoured hull first (deflected, keeps flying) before meeting a plate; from behind (no rear plate) a rocket crosses the hull and can exit through the front plate from inside. Needs real-rocket tests from front, side and rear (C4). |
| **A4** Plates on a new collision layer that only rockets mask | Plate hurtbox on unnamed bit 4 (value 8); rockets add 8 to their mask; bullets do not. | No script change in bullets. | Spends a free layer bit on one enemy; makes the player's rocket scene know about an enemy's armour; bullets crossing a plate meet the hull anyway (A3's hull rule still needed). Layer semantics churn the Ph1 naming work just cleaned up. Rejected. |

**Recommendation: A3.** The query extension is what CLAUDE.md already prescribes ("any future entity that needs to
deflect a bullet without consuming it must expose its own `is_armored()`-shaped query"); the hit-aware form is the
smallest change that lets "deflect a bullet, accept a rocket" be said at all.
- `test_player_bullet_lifetime.gd`'s invariant ("a player bullet is not consumed by a hurtbox it overlaps" when it
  deflects) extends naturally to a plate.
- `test_enemy_hurtbox_geometry.gd` already allows extra part hurtboxes beyond the root (the station's turrets). The
  root must still cover the body within 1 px.
- **Deflection feedback** (IDEAS §13.1 "bullets bounce/deflect"): the hull's `_on_received_damage` flashes on a deflect
  (station pattern). A plate gets no `received_damage` for a filtered bullet, so it flashes from its own
  `area_entered` when the overlapping `HitBox` is not a rocket. Whether the deflected bullet should visibly ricochet
  (change direction) rather than pass through is a design choice the plan should make explicitly; passing through is
  today's convention for the station and needs no new code **(judgement)**. F11: whatever the choice, a deflect must
  look different from a damaging hit (spark/flash, no damage), as part-breaking games do.
- **"Heavy weapons stagger armour"** (open question 5): the player's sniper shot (unlimited pierce, LASER) is stopped
  by the `ram_ships` group for 0 today. With the group retired it would pass through: the hull deflects it (armoured)
  until the plates are gone, then it damages the hull. Recommended: plates accept `ROCKET` only; the beam and the
  modules (direct emitters) hit the hull and are deflected while armoured. A "stagger" (a short charge interrupt when a
  plate breaks) is a cheap readable reaction **(judgement)**; anything more is Ph10's modular-damage work.

### 2.2 Ram Corvette charge and contact (R4.33, R4.37)

- **Charge:** brain states `APPROACH → LINE_UP (turn onto intercept, ≤ turn cap) → WIND_UP (0.5–0.8 s; velocity → 0 or
  a crawl; plates glow; `StateLight` CHARGING) → CHARGE (`mover.boost(dir, charge_speed, t)` along the intercept line
  frozen at the end of WIND_UP, never re-aimed after (F5); `StateLight` COMMIT; contact armed) → OVERSHOOT (keep the heading for an overshoot
  distance past the projected point) → WIDE_TURN (`Steering.turn_toward` at a low rate, the Ph2 rule: a curved path is a
  brain-side request, never the mover's turn cap) → APPROACH`.
- **Prediction:** `TargetInfo.intercept(from, charge_speed)` gives the point; IDEAS §27 "rammer predicts a shorter future
  position" means a **clamped** lead (`Steering.clamped_lead_time`, e.g. `t_max` 0.6 s) rather than a full intercept. The
  test asserts the charge direction points at `predicted_position(clamped_t)` within a tolerance, in both harnesses.
- **Contact profile:** two candidates for "Armour collision (deals high stagger/contact damage while partially
  protecting the enemy)":
  - (a) a new `ContactProfile.Mode.ARMOR` that is **always armed** (the plates hurt to touch even outside a charge)
    while plates remain, and switches to RAMMING semantics (armed only in CHARGE) once the plates are gone; "partially
    protecting" = the Corvette takes no contact-type self-damage while armoured;
  - (b) RAMMING only, with a damage multiplier during CHARGE.
  - **Recommended (a)**: it is what the enum was shaped for (DECISIONS Ph2), and it gives the profile a real difference
    from RAMMING. **Contact on the player never kills the Corvette** ("it should not instantly die if it misses", and it
    must survive a hit, unlike the Swarm's EXPLOSIVE).
- **After the plates break** (R4.32): config pairs `armoured_*` / `exposed_*` for `max_speed`, `charge_speed`,
  `collision_damage` (exposed slightly higher), plus an `evasive` behaviour — between charges, strafe/jink with
  `Steering.evade` when the player's aim line is on it. The contact-damage gate reads `config.collision_damage`; the
  exposed value must be a second field, and the gate's row asserts the armoured (spawn-time) value.

### 2.3 `persist_after_owner_death` (S2, C3, open question 3)

| Approach | How | For | Against |
|---|---|---|---|
| **P1** A `BulletPool` policy | `@export var persist_after_owner_death := false`. On `_exit_tree()` with the flag set, each in-flight bullet is **handed over**: disconnect the pool's recycle (store the per-bullet `Callable` in `_prewarm`, so it can be disconnected), connect `expired → queue_free`, drop it from `_active`. Its `ProjectileLifetime` (time / distance) remains the self-expiry rule. | The flag sits where ownership is decided, as Ph1 planned for Ph5. Explicit transfer: at any instant exactly one owner. Mines and pursuit bombs can be pooled like every other enemy round. | Touches a component every shooter uses (default off keeps them byte-identical). Edge cases: a bullet that expired in the frame the owner dies (deferred `_recycle` already queued: it must see the bullet is no longer the pool's), and the section-timeout sweep freeing persisted ordnance (harmless: it is in the container, and freeing it is the timeout's job). |
| **P2** Ordnance is never pooled | The bomber instantiates each bomb/mine into the container; ordnance frees itself on `expired` (the player-bullet ownership shape). `persist_after_owner_death` is then a constant `true` documented on the ordnance. | No pool change. Matches today's `bomb.gd` (unpooled, already outlives the bomber) and the enemy sniper bullet (unpooled). | The epic says "enemy projectiles gain" the flag; a constant is not a flag. Ph5 rockets would have to build P1 anyway. Instantiating a scene per drop is fine at this rate (≤ 5 per 2–3 s) **(judgement)**. |

**Recommendation: P1**, with ordnance pooled at `pool_size_for`-style sizing. It is the shape Ph1 already designed for
Ph5, so building it now rather than a throwaway P2 is cheaper over the chain; F13 is the same "orphan active pooled
objects on destroy" option a shipped Unreal pool plugin added for this exact bug. Killing the Bomber therefore does **not**
cancel its mines (F10: the scope chose persistence over a kill-cancel). Tests: owner freed → in-flight mine still in
the container, still dangerous, frees itself on its own `max_time`; owner freed with the flag off → today's behaviour
(the round vanishes); the double-expire frame; a persisted mine never returns to a dead pool.

### 2.4 Real line of sight (S3, C7)

- `TargetInfo` is a snapshot with no world. Options: (L1) `line_of_sight(from, space: PhysicsDirectSpaceState2D,
  exclude: Array[RID])`; (L2) a static `LineOfSight.clear(space, from, to, exclude) -> bool` helper, with
  `TargetInfo.line_of_sight(from, space)` delegating; (L3) a `RayCast2D` child on the sniper.
- **Recommended L2**: one pure-ish static, the same shape as the beam's ray (the project's only `intersect_ray`,
  `beam_behavior.gd:50-75`), reused by any later LOS user (Missile Corvette, turrets, Ph19). L3 needs a node per
  shooter and updates only once per physics frame (`force_raycast_update()` otherwise) **(judgement)**; F12 gives the query rules (physics tick only, explicit mask, own RID excluded, areas off).
- What blocks: **opt-in**, not "any body". Every enemy body sits on layer 1 (no authored layer) as do asteroids, so a
  plain mask-1 ray would let one fighter blind a sniper. Use the beam's excluded-and-recast loop: a collider blocks only
  if it is in group `asteroids` or answers `blocks_line_of_sight() == true`. Cap the recasts (e.g. 4).
- Call it only from the brain's tick (the physics step), never from `_process`. Tests place a blocker and **await a
  physics frame** before asserting, or the broadphase has not seen it.

### 2.5 Sniper firing-position selection (R4.11–R4.16, C15)

- **Candidate sampling + scoring** (Killzone's weighted-sum position picking, F7; filters before scoring, F8): each REPOSITION samples N (≈ 8–12)
  candidate bearings in the **player's frame** (relative to the player's velocity if moving, else facing), the IDEAS list
  as seeds: ±60°, ±90°, 180° (behind), plus diagonals, each at `preferred_range` ± jitter from `brain.rng`.
- Score: + distance from the last firing bearing (relative to the player frame), + LOS clear (L2), + inside
  `inner_rect().grow(−margin)` in Assault (else rejected), − travel time from the current position, − the player's
  forward cone (do not park in front of a boosting player). Pick the best; deterministic per seed.
- **"New firing position every cycle"** asserts an **angular separation** ≥ X° (e.g. 45°) between consecutive firing
  bearings in the player's frame, not float inequality. Boundary: the player hugging a corridor corner (few legal
  candidates) still yields a different bearing, or the documented fallback (the best legal one ≠ last).
- **Cycle:** `BREAK_CONTACT` (until `distance ≥ preferred_range` or a cap) → `RELOCATE` (arrive at the chosen point) →
  `SETTLE` (brake until `velocity < ε`) → `AIM` (track, the barrel unfolds, `StateLight` CHARGING) → `LOCK` (aim frozen on
  the predicted point; `StateLight` COMMIT) → `FIRE` (one rail round) → `BREAK_CONTACT` again. **LOS is re-checked at
  LOCK → FIRE**: blocked → no shot, straight to `BREAK_CONTACT` (or a short re-aim), no round spawned (the refusal test).
- **Stationary** = `velocity.length() < ε` and position drift `< 1 px` from SETTLE end to the shot (C10). The mover
  keeps facing the frozen lock point; rotation still settles during AIM.
- **Prediction** (§27 "sniper predicts further ahead"): lock on `predicted_position(t)` with `t` = the shot's travel time
  at lock, i.e. `TargetInfo.intercept(from, rail_speed)`; with a 2000+ px/s round over ≤ 900 px this is ≤ 0.45 s.
- **No `FLY_IN_TIME`** (R4.20): the approach is `BREAK_CONTACT/RELOCATE` arrival, whose duration is `distance / speed`
  by construction. Assault DISENGAGE uses the budget and the nearest-edge exit (the fighter's `_enter_disengage`).

### 2.6 Rail shot, residual trail and the decoy (R4.17, R4.18, C8, C9)

- **Round:** a new `rail_round.tscn` under `assault/scenes/projectiles/enemy_bullet/rounds/` (an inherited
  `enemy_bullet.tscn`, the Ph3 rounds shape), speed ≈ 2000–2400 px/s, damage 25–30, capsule width 2–3 px. It joins the
  round lifetime sweep through a `SniperConfig.rail_speed` field. The old `enemy_sniper_bullet.tscn` is deleted with
  the legacy enemy (`test_enemy_bullet_lifetime.gd:112-115,140,286` moves to the new round in the same task).
  Its own `WorldEnvironment` should **not** be copied (one per scene is the player bullet's legacy, and two
  environments in one viewport fight) **(judgement)**.
- **Residual trail:** a `Line2D` spawned at the shot, from the muzzle to where the round expired/hit, fading over ≈
  0.3–0.5 s, self-freeing on its own counter (no `create_timer`, the ContactBlast rule). It is a visual only: no hitbox.
- **Telegraph line:** `SniperAimVisualizer` is shared with the player weapon and draws a fixed 600 px line. An
  **additive** export (`line_length`, default 600) leaves the player byte-identical; the enemy sets it to the lock
  distance + overshoot so the line reaches past the player (C8). Alternatively the enemy owns its own small visual; the
  plan should pick one. Telegraph colours follow §21: dim red tracking (AIM), white/bright at LOCK (COMMIT exclusive to
  the real shot).
- **Decoy** (`decoy_telegraph`, default false): before the real AIM, a short CHARGING-only line at a bearing offset from
  the player, which **never** turns to the LOCK colour and is cancelled. COMMIT stays exclusive to the real shot (Ph2
  rule), so a decoy can never look like a lock (F6: a fair fake-out is distinguishable from the real thing). Tested only
  with the flag on. F1's "initial misses" is a simpler honest alternative the plan may weigh.

### 2.7 Visual states and art (S10, S12, C16)

- **Sniper:** hull sprite + a separate barrel `Sprite2D` that extends (scale/offset tween on the brain clock) during AIM,
  retracts after FIRE. Two PixelLab assets (hull, barrel), or one hull with folded/unfolded variants swapped by
  `texture`.
- **Ram Corvette:** hull sprite + three plate `Sprite2D`s, each a child of its plate node. Glow = `modulate` towards
  yellow during WIND_UP (StateLight CHARGING is the authoritative cue; the glow is the "armour glows" read). Break = the
  plate node is freed (its hurtbox goes with it) plus an `ExplosionEffect` burst.
- **Bomber:** wide hull; the ordnance is code-drawn or tiny sprites (the Ph3 rounds precedent was code-drawn `Line2D`s).
  A mine needs a readable "armed" blink (§21: red glow = armed).
- Every PNG passes `test_entity_sprite_transparency.gd` (< 90 % opaque); new sprites are drawn **nose-down** or set
  `sprite_forward_angle`; keep the node type/name convention (`AnimatedSprite2D` is flipped by `BaseEnemy`).

### 2.8 Bomber ordnance and behaviour (R4.1–R4.8, C5, C6)

- **Ordnance are `Area2D` projectiles**, not `BaseEnemy`s (C6): self-moving like `EnemyBullet`, outside the
  single-writer gate, each with a `ProjectileLifetime`, a small `HurtBox` + `Health` (1–2 hits) on `enemy_hurtbox` so
  player bullets/rockets destroy them (R4.4), and an EXPLOSIVE detonation through `ContactBlast` (never `create_timer`).
  - **Gravity Bomb:** keeps the bomber's velocity direction at a slow speed, proximity-arms (warning blink), detonates
    after a short fuse or on reaching its aim point.
  - **Mine Cluster:** 3–5 drops on a `BurstClock` along an arc behind the bomber, each mine stationary with a proximity
    trigger and a `max_time`.
  - **Pursuit Bomb:** turns toward `predicted_position(t)` at a low capped rate (`Steering.turn_toward`) for a window,
    then accelerates; it is the only one that steers.
- **Smart bombing:** the bombing line is placed across `predicted_position(lead)` along the player's velocity (R4.5),
  with a **damped** lead (F9: factor ≈ 0.6 on smoothed velocity, horizon capped, boost not fully led), so a committed
  change of direction escapes,
  not their current position; a stationary player falls back to the current position. Assault clamps every aim/drop point
  to `inner_rect().grow(−margin)` (S8).
- **Selection "by behaviour"** (R4.3): a simple rule, testable: player moving fast in a line → mine chain across the
  predicted path; player close and slow → gravity bomb; player far / evading → pursuit bomb. Weighted by `brain.rng` to
  avoid lock-step **(judgement)**.
- **Movement:** `APPROACH` on an angled lead-in (`DubinsPath` arriving along the bombing line, the Ph3 rule for any
  attack-run enemy) → `RUN` (straight along the line, dropping) → `ESCAPE` on an arc (`turn_toward` at a low rate) →
  re-position for another run (Open Space) or DISENGAGE (Assault budget).
- `bomb.gd` / `bomb.tscn` (legacy) are replaced; nothing else references them (grep in the plan task).

### 2.9 Recommended answers to `1-context.md`'s open questions

| # | Question | Recommendation | Where argued |
|---|---|---|---|
| 1 | Names | Keep `Bomber`. `git mv` `ram_ship/` → `ram_corvette/` (`RamCorvette`, `RamCorvetteConfig`) and `sniper_enemy/` → `sniper/` (`Sniper`, new `SniperConfig`), the Ph2/Ph3 rename precedent. Keep `WaveBuilder.ram()` / `sniper()`, and `sniper_enemy()` as an alias. Every roster test is edited in the rename task. | `1-context.md` blast radius |
| 2 | Armour query | A3: plate child parts + additive `deflects_hit(hit_box)` with an `is_armored()` fallback. | §2.1 |
| 3 | Ordnance pooling / the flag | P1: `BulletPool.persist_after_owner_death`, ordnance pooled. | §2.3 |
| 4 | Bombers in `ENEMIES_CLEARED` | Barred by a deadline boundary row; ordnance life stays out of the formula. | §4 |
| 5 | What breaks plates | Rockets only (`ROCKET`); the player's sniper shot, beam and modules hit the hull and are deflected while armoured. The `ram_ships` group rule is retired. | §2.1 |
| 6 | Assault Ram budget | One charge (`engage_seconds` ≈ 4.5 s), set by the 73.2 s entry's 0.5 s margin. | §4 |
| 7 | Sniper range per mode | Open Space 800–1000 px; Assault 600–800 px, firing point inside `inner_rect().grow(−margin)` and allowed off camera. | S7, §2.5 |
| 8 | Decoy flag | `SniperConfig.decoy_telegraph: bool = false`, a CHARGING-only line, never COMMIT. | §2.6 |
| 9 | Rail shot | New inherited `rail_round.tscn` in `rounds/`; pooled (`pool_size_for`, 1–2) or unpooled with self-free, as the plan prefers; the old scene is deleted. | §2.6 |
| 10 | Hub placement | Three groups at the free diagonals, appended to the seeded draw order. | §3.1 |

---

## 3. Starting values (judgement unless a finding is cited)

Speeds in world px/s (Assault design units × 2 already applied). Every value goes on a flat `ShipConfig` subclass field.

| Enemy | Field | Start | Reason |
|---|---|---|---|
| Bomber | size / HP / contact | ≈ 104×56 px, 150 HP, 35 | Today's `bomber_config.tres` HP and contact (keep the balance; only the shape changes). |
| Bomber | cruise / run speed | 140 / 170 | Slow specialist; the legacy rail ran 160–164 (80–82 design × 2). |
| Bomber | run length / drop gap | ≈ 360 px / 0.25 s for 3–5 mines | **Judgement.** At 170 px/s a 0.25 s gap spaces mines ≈ 43 px apart, so 4 mines span ≈ 130 px over 0.75 s, about two player hull widths (64 px). The "arc" comes from sideways ejection offsets on top of the travel. |
| Bomber | mine life / arm delay / trigger radius / blast radius / damage | 8 s / 0.5 s / 80 px / 48 px / 30 | Today's bomb: 80 px detector, 28 px blast, 40 dmg, 1 s countdown. A mine is longer-lived, so a smaller hit. |
| Bomber | gravity bomb speed / fuse | 120 / 1.0 s warning | Today's `fall_speed` 120, `trigger_time` 1.0. |
| Bomber | path lead factor / horizon / velocity smoothing | 0.6 / ≤ 1.2 s / ≈ 0.3 s average | F9 (0.64 shipped; an undamped 0.5 s lead was too strong). |
| Bomber | ordnance HP | 1 (any player hit defuses it; a defused mine detonates at a reduced radius or not at all, a plan choice) | R4.4; F10 (a clear "what a shot does" rule). |
| Bomber | pursuit bomb turn rate / steer window / final speed | 1.2 rad/s / 1.5 s / 380 | **Judgement** (no source): slow enough that a turning player out-turns it, the F9 "a committed change of direction escapes" rule. |
| Sniper | size / HP / contact | 56–64 px, 60 HP, 20 | Today's scene HP 60 and default contact. |
| Sniper | preferred range | Open Space 800–1000 px; Assault 600–800 px inside the rect | Beyond the half-view (≈ 640 px) in Open Space (S7, C8). |
| Sniper | AIM / LOCK | 1.2–1.5 s / 0.5 s | Today 2.0 / 0.5. F4: LOCK ≥ 0.45 s is the reactable floor, so LOCK stays 0.5 and difficulty shortens AIM only (F1's ×0.75 shape). F2: the AIM also reveals the sniper. |
| Sniper | rail speed / damage | 2200 px/s / 28 | Faster than today's 1400 to read as a rail shot; at 900 px it lands in ≈ 0.41 s after the lock. |
| Sniper | break-contact speed / relocate speed | 320 / 260 | **Judgement.** It cannot outrun the Open Space player (`max_speed` 420, boost exit 700), so break-contact relies on lateral motion and the distance it already has, not on speed. The plan should test "distance grows" against a stationary or slow player, and accept that a boosting player can catch it (that is the counterplay R4.16 wants). |
| Ram | size / HP hull / HP per plate / contact armoured→exposed | 80–88 px, 120, **50** each, 50→60 | Today contact 50, HP 999 (immune). The player's rockets deal `HitBox.damage` 50 (`warhead_missile.tscn:63`) and 100 (`homing_missile.tscn:57`), so 50 means **one rocket of either kind breaks one plate**: three rockets to expose the hull, the IDEAS "use a rocket to strip an armour plate" choice. |
| Ram | cruise / charge / exposed cruise / exposed charge | 160 / 620 / 220 / 700 | Legacy rail 520–700 px/s; a charge must land in that band to keep the shipped "ram" feel. |
| Ram | wind-up / overshoot / wide-turn rate | 0.65 s / 220 px / 1.4 rad/s | IDEAS 0.5–0.8 s; F4: 0.65 s ≈ 39 frames, comfortably reactable; F5: the line freezes at the end of WIND_UP. |
| All | Assault `engage_seconds` | Sniper 9–10 s (one or two shots), Ram ≈ 4.5 s (one charge), Bomber ≈ 8 s (one run) | §4. |

### 3.1 Hub placement (S13)

`sector_hub.gd` uses bearings with Godot's y-down convention: Swarm at 90° → (0, 1300), Razor at 270° → (0, −1300),
fighters at 180° → (−1500, 0), Gatlings at 0° → (1500, 0). The diagonals 45° / 135° / 225° / 315° are free. The scene's
clearance points read at `00aced5`:
- the planets' `MissionTrigger`s at (595, 342), (−530, −384) and (−635, 385);
- the pickup bench, a grid from about (−280, −515) to (730, −210), i.e. toward 270°–315°;
- the player spawn near the origin.

`test_sector_hub_patrol.gd` asserts `|point − anchor| − worst_idle_offset > perceive_radius` for every point, and that
anchors are more than 1000 px apart.

Worked example (**judgement**; the plan recomputes it on the real scene): a ring of 1700 px puts the 45° anchor at
(1202, 1202).
- Its nearest clearance point is the (595, 342) trigger, 1053 px away. With a 150 px idle offset, `perceive_radius` must
  stay under ≈ 900.
- The 315° anchor's nearest pickup, (730, −515), is ≈ 834 px away, the tightest diagonal. Give it the enemy with the
  smallest perceive radius, or push its ring out.
- Diagonal anchors at 1700 are ≥ 1140 px from the existing four anchors.

Suggested assignment:
- **Sniper at 135° or 45°**, the diagonals far from the bench. A perceive radius of ≈ 700 is separate from its firing
  range: it notices at 700, then breaks contact out to its 800–1000 px range.
- **Bomber and Ram** take the other two diagonals.
- Each new group draws its rng seed **after** the four existing groups, so their seeds stay put.

---

## 4. `ENEMIES_CLEARED` deadline arithmetic (cloud_descent, timeout 10.0 s, last trigger 76.0 s)

`test_engagement_deadline.gd` asserts per entry: `(entry − last_trigger) + engage + deferral + worst_exit + 0.5 < 10.0`,
with the **curved-exit bound** for an enemy that turns its velocity (Ph3 deviation 18: fighter 5.37 s).

| Entry | Enters at | Slack before 76.0 | Allowed `engage + deferral + exit` | Sketch |
|---|---|---|---|---|
| Sniper 11.0 | 11.0 | 65.0 | 74.5 | Trivially fits. |
| Snipers 32.0 (×4) | 32.0 | 44.0 | 53.5 | Fits. |
| Snipers 53.0 (×2) | 53.0 | 23.0 | 32.5 | Fits. |
| Snipers 62.0 + 1.2 (×2) | 63.2 | 12.8 | **22.3** | engage 10 + deferral 2.0 (AIM 1.5 + LOCK 0.5 of a shot already telegraphed) + curved exit ≤ 6 → 18 s. Fits with ≈ 4 s margin. |
| Rams 28.0 (×2, d 0 / 0.4) | 28.4 | 47.6 | 57.1 | Fits. |
| Ram 38.0 + 0.6 | 38.6 | 37.4 | 46.9 | Fits. |
| Rams 50.0 + 1.5 (×2) | 51.5 | 24.5 | 34.0 | Fits. |
| **Ram 72.0 + 1.2** | **73.2** | **2.8** | **12.3** | engage 4.5 + deferral (wind-up 0.65 + charge ≈ 0.9 + overshoot ≈ 0.35 ≈ 1.9) + curved exit ≈ 5.4 (fighter-like) → 11.8 s. **0.5 s margin: tight.** The plan must compute the real curved bound on the real scene (the Ph3 404-start probe), and the real replay `test_level1_fighter_exit.gd` (which already contains this ram) must still empty in time. Lever: engage 4.5 → 4.0, or a straight exit after the overshoot. |

**Bombers** appear only in `planet_approach` (DURATION). A mine laid at the end of a run outlives the bomber by up to its
`max_time` and holds an `ENEMIES_CLEARED` section open (C5); the gate gains a boundary row "no `ENEMIES_CLEARED` section
contains a Bomber" (the Gatling precedent), rather than putting ordnance life into the formula.

---

## 5. Testing requirements → gates

| Requirement (R4.40) | Test shape | Both harnesses |
|---|---|---|
| Mine/bomb placement against the predicted path | Player stub moving at v; assert each mine/aim point is within tolerance of the line through `predicted_position(lead)` and **not** within tolerance of the current position; Assault: every point inside `inner_rect().grow(−margin)` with a player near the edge (boundary). | yes |
| New firing position every cycle | Run 3+ cycles; consecutive firing bearings (player frame) differ by ≥ 45°; corner boundary. | yes |
| Stationarity during telegraph | From SETTLE end to the shot: `velocity.length() < ε`, drift < 1 px. | yes |
| Post-shot disengage | Distance to the player strictly increases over the 1.0 s after FIRE; no return toward the player before the next firing point is chosen. | yes |
| LOS refusal | Blocker (an `asteroids`-group StaticBody2D fixture) placed on the line, one physics frame awaited: no round spawned, state leaves LOCK; blocker removed → it fires next cycle. Plus: a fighter body on the line does **not** block (opt-in rule). | yes |
| Plate-by-plate vulnerability | Real bullets deflect off every plate and the hull (not consumed); a real rocket breaks the plate it hits; hull takes 0 until the third plate breaks, then takes bullet damage; front / side / rear rocket approaches (C4). | yes (Open Space spawns; Assault spawns) |
| Charge direction | Charge velocity points at `predicted_position(clamped_t)` within tolerance; it survives a miss; overshoot ≥ X px past the point. | yes |

Gates updated for renames and new scenes (from `1-context.md`): contact damage + contact geometry rosters (and their
completeness sweeps), hurtbox geometry, config isolation (new `SniperConfig`), sprite transparency, `test_base_enemy.gd`
flips and `_AUTHORED_CONTACT_MODES`, single writer, signal arity, round lifetime sweep (rail round; stationary mines are
time-bound only), UID and project-load integrity, `test_station_reinforcements.gd` ram guard, `test_player_bullet_lifetime.gd`
(plates), `test_target_info.gd` (stub → real), level-1 pin (50 rows), deadline rows (15 entries + bomber boundary), real
replay, density against frozen legacy constants, hub clearance rows.

---

## 6. Notes for the plan stage (sizing, ordering)

These are observations, not a plan. The plan stage decides.
- **Shared pieces first, each small and independently testable.** Each is a pure helper or a default-off flag with its
  own unit test, so none changes shipped behaviour on its own:
  - `Steering.break_contact`;
  - `LineOfSight` + `TargetInfo.line_of_sight` (S3);
  - `BulletPool.persist_after_owner_death` (P1);
  - the additive `deflects_hit` query in the three player projectiles (A3);
  - `ContactProfile.Mode.ARMOR`.
- **Renames are their own tasks.** Each `git mv` + roster-test edit is mechanical but touches about 10 test files (the
  `1-context.md` blast radius), and Ph3 did each rename as a separate step.
- **Each enemy is at least two tasks**, as the Fighter was in Ph3 (shell, then behaviour). The Ram's armour touches
  player-weapon code and the station's regression tests, so it is `large`. The Sniper's position selection plus LOS is
  `large`. The Bomber's three ordnance types plus smart bombing are probably two tasks: ordnance first, then the brain.
- **Art is its own task per enemy** (the `pixel-art-generation` skill, candidates, the visual check). The visual-state
  wiring (plate glow and removal, barrel unfold) belongs with the behaviour task that drives it.
- **Level-1 migration follows the Ph3 pattern**: freeze the legacy constants and pin the rows, then take the
  DURATION sections off rails, then cloud_descent (`ENEMIES_CLEARED`) with the deadline rows and the real replay.
  The 73.2 s Ram is the tight entry (§4).
- **Hub spawn last**, once all three enemies have hub idle.
- **Owner-visible gameplay changes** the plan should flag for approval:
  - the Ram joins `enemies`, so homing rockets, EMP, nova, dash and the beam now reach it;
  - the Ram is no longer bullet-immune once its plates are gone;
  - the player's sniper shot is no longer stopped by Rams;
  - mines outlive their Bomber;
  - level-1 snipers and rams live for a budget instead of a rail's few seconds, which changes density (C13);
  - `persist_after_owner_death` moves from Ph5 to Ph4 (S2).
