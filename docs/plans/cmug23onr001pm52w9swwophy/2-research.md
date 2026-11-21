# Research — Enemy rework, phase 9: electronic warfare (Jamming Structure, Hacker Frigate and EMP)

Epic `cmug23onr001pm52w9swwophy`, research task `cmug23onx001tm52wky2h8qj9`, 2026-11-06, against `agent/auto-dev` at `5fbc01f`
(Phase 8 closed). Read with `1-context.md` (requirements R9.1–R9.25, the files, reuse table, conventions, risks and open
questions Q1–Q16). This file has five parts:

1. **Scope check**: what changed against this phase's scope as written, from the code and the earlier phases' as-built notes.
2. **External findings**: how shipped games solve the same problems, with tradeoffs and typical values.
3. **Candidate approaches** per part, with tradeoffs and a recommendation.
4. **Starting values**, each labelled with where it comes from.
5. **Recommended answers to Q1–Q16**, the owner choices, and the test requirements.

Every recommendation here is a default for the plan stage. The ones the owner should confirm are listed in §5.2.

---

## 1. Scope check

The scope was written before Phases 5–8 ran. Checked against the code on `5fbc01f` and DECISIONS.md (Ph5 / Ph7 / Ph8 sections and
as-built notes). **S-numbers are referenced by the plan.**

| # | What the scope assumed | What is actually there | Effect on this phase |
|---|---|---|---|
| S1 | "The player-side ability-lock … hooks these need" | **No lock exists anywhere.** `HazardInfo.disables_abilities` (`global/hazards/hazard_info.gd`) is a reserved field with no producer and no consumer ("Carried for Phase 9"). The H abilities are fired from two loops, `OpenSpacePlayerShip._input` and `PlayerFighter._input`, each calling `ShipModuleBase.try_activate()` in turn; the K special weapon is `RocketState._on_action()`. | Build the lock from scratch, on `PlayerBase`, with **one refusal check in each of those three places, run before anything is spent**. There are 3 seams. It is not a per-module job. |
| S2 | "the player's automated, seeking rockets" (plural, generic) | **The player has one seeking weapon**: `homing_missile` (K with Q set to homing; 3 rockets per launch, targets picked once at launch from group `enemies` by distance, 5 s `CooldownTimer`). The warhead rockets fly straight (`WarheadMissile`). The mining laser and beam are not seeking. `AITargetingModule` is "automated" but it is an H ability that snaps the nose, not ordnance. | The retarget hook is a small contract (§3.2) with one implementer today. Warheads are explicitly **not eligible** (R9.16). `AITargetingModule` is covered by the jammer's lock, not by the Hacker. |
| S3 | In-flight hijack works in both modes | **The homing missile frees itself outside a hard-coded Assault arena box** (`homing_missile.gd` `_ARENA_*` consts, x −164…1444, y −444…1164 in world coordinates). In Open Space that box sits around the world origin, so anywhere else in the hub a launched homing rocket dies on its first tick. It also points straight at its target every tick (no turn rate) at 500 px/s, has no `ProjectileLifetime`, no `expired` signal and no HurtBox. | **A prerequisite fix belongs to this phase:** give the homing missile a `ProjectileLifetime` (the Ph1 component: `max_time`, `max_distance`, `use_world_rect`), which keeps the Assault world rect where a provider exists and is a no-op in Open Space, plus an `expired` signal → `queue_free`. Without it the "in-flight hijack in both harnesses" test rows cannot exist. It changes a shipped player weapon in Open Space (rockets start working there); the Assault path stays inside the same rect. |
| S4 | A hijacked rocket "attacks the player" | **No player rocket can hurt the player**: the missile's HitBox is layer 32 / mask 513, and the player HurtBox mask is 1281, which does not include 32. | The hijacked rocket hurts the player only through the **Ph5 `EnemyRocket` rule**: a detonation spawns a `ContactBlast` on layer 256. No new collision bit, and the player's own fresh rocket can never touch the player at launch (`test_collision_layer_names.gd` is unaffected). |
| S5 | "EMP Pulse … and phase 7's EMP mine disrupt systems through the same hooks" | Ph7 built `EmpPulse.emit(tree, at, radius, seconds, source) -> int` (player group only) and the stand-in `PlayerBase.apply_emp()` → `apply_boost_disruption(1.0, seconds)`. Nothing reads `is_emp_disrupted()` or `emp_changed`. **A second, older EMP exists**: the player's own `EMPBlastModule` (H, cockpit slot) sets `PROCESS_MODE_DISABLED` on every enemy for 5 s. Disabling a `CollisionObject2D` removes it from physics by default, so **a stunned enemy cannot be shot for 5 s** (a live bug, pinned only by `test_ram_corvette.gd::test_emp_still_skips_the_corvette`). Enemies have no EMP hook at all. | Build an **enemy EMP hook** (`apply_emp(seconds, source)` duck-typed on `BaseEnemy`: weapons and special systems held, still tangible, Assault budget still running). Extend `EmpPulse` without breaking its signature (§3.4). Re-routing `EMPBlastModule` through the new hook fixes the intangibility bug, but it changes a shipped player ability, so it is an **owner choice** (Q11, default: re-route and keep 5 s / 15 s / immune list). |
| S6 | "Jamming Structure", a new kind of thing | Ph8 built the template: static `BaseEnemy` structures with no mover (`PowerSource`, `ShieldGenerator`): `AssaultDrift`, `ContactProfile` NONE, `is_laser_blocking()` false, `counts_as_escape` false in `.tres`, an owner group, a `_draw()` off-state. Ph6's `HazardField` already has the **TELEGRAPH → ACTIVE → QUIET** cycle on accumulated delta (`cycle_telegraph` / `cycle_active` / `cycle_quiet`, `phase_changed(phase: int)`). | The jammer is a `ShieldGenerator`-shaped structure that **owns** a hazard registration (`kind = &"jammer"`, `disables_abilities = true`, the Ph6 decision). The pulsed variant reuses the cycle's phase function rather than a new clock. No new structure framework. |
| S7 | Hacker movement: "medium/long range, asymmetric arcs" | Ph5's `MissileCorvetteBrain` HOLD_ARC is exactly this: an orbit at `held_range()` ± `range_drift`, reversals every 4–7 s, a `min_range` break-off, the nose on the player, attacks only inside `launch_cone_deg`, TELEGRAPH → action, Assault `EngagementBudget` + DISENGAGE, hub `AnchorIdle`. Ph5's `SupportShipBrain._clamp_into_view()` is the Assault view clamp. Ph4's `SniperBrain` scores positions by bearing against the player's velocity and facing. | The Hacker brain **composes these**, it does not invent a new movement model: HOLD_ARC with asymmetric arc speeds, plus a bearing penalty for the player's nose cone and velocity line (the §18.6 "outside the player's preferred route" rule), plus the view clamp in Assault. |
| S8 | "§18.6 jammer towers and EMP zones" | Nothing produces either. | Jammer towers = the jammer structure (S6). **EMP zones** = a placed area that pulses `EmpPulse` on a cycle and affects everything inside it (§3.4.3). It is a small addition on the same pieces. |
| S9 | Jammers as part of defended sites | `TurretGroup.add_power_provider()` is documented as "the Ph20 jammer seam", and the roadmap gives "jammer-linked turret groups" to **Phase 20**. | **Out of scope:** Ph9 does not link a jammer to a turret group's power. A jammer may be *placed beside* a turret group (that is placement, not linkage). |
| S10 | "a clear visual, audio and indicator tell" | **The project has no audio at all.** There is no `AudioStreamPlayer` in any `.gd` or `.tscn` outside `addons/`. Every earlier phase deferred SFX to Ph17. | The visual and HUD tells are built here. For audio, the recommendation is a **seam only**: an `EventBus` signal fired when a rocket is hijacked and when the lock engages, which Ph17's audio pass listens to. The epic text names audio explicitly, so this is an **owner choice** (Q16). |
| S11 | "locked/recharging state" shown to the player | There is no module or cooldown HUD. `AbilityChip` exists in the Assault HUD only, hidden. `MissionHud` binds the special-weapon `WeaponIcon` + `CooldownOverlay` to `RocketState` in both modes. `BoostBar` has a violet "disrupted" state. | A small shared HUD addition (a "JAMMED" chip with a stabilisation fill, a lock glyph over the special-weapon icon) plus a tell on the ship itself, like the Ph7 `BoostDisruptionRing`. No module HUD (that is Ph17's readability pass). |
| S12 | Both enemies "join Assault waves" | Level-1 specialist density is nearly full: `test_level1_specialist_spawns.gd`'s frozen 2.5× gate has deep_space at 12 of 12.5 and planet_approach at 7 of 7.5 (Ph8 end). asteroid_belt has no specialists and **no frozen legacy constant** (a 2.5× of nothing). Ph8 counted structures per ship in the same gate. | Placement must be **off-peak and measured**, not at a peak, or the asteroid_belt section needs a new frozen constant, which is an owner-visible gate change. The default is off-peak measured placement in deep_space / planet_approach (§3.6), with none in an `ENEMIES_CLEARED` section (guard rows). |
| S13 | Both enemies join "the hub's ambient spawn" | 17 seeded draws, appended only. The 2600 ring has bearings −22.5 / 112.5 / −157.5 taken. `test_sector_hub_patrol.gd` sweeps every patrol ring and site footprint. | Draws 18+ are appended. The jammer goes to a site that the clearance sweeps cover (sweep A's reach rule applies to its field radius). |
| S14 | "A variant that briefly disrupts abilities is decided by this phase's research" | `Shield.set_hacked()` / `ShieldIcon.play_hacked()` exist with no caller, but `set_hacked` drains every charge in one call, which is not a brief disruption. | **Decided (§3.3.4):** the variant exists, and its pulse also applies a **timed ability lock** to the player through the same lock hook. It is built as a config flag on the same scene (a second `.tres` / inherited scene), tested, and **not placed** in Ph9 (placement: Ph13 encounters / Ph16 tiers). The shield "hacked" drain is rejected for it. |
| S15 | Ph7 hand-over: "Pulse / EMP mines affecting enemies (Ph9, if wanted)" | The EMP mine calls `EmpPulse.emit`. Enemy-laid mines are `Hostility.PLAYER`; placed hub mines (`Minefield`) are `ALL`. | Recommended: an `ALL` (placed) EMP mine also reaches enemies through the extended `EmpPulse`, while an enemy-laid mine stays player-only (the Ph7 rule "enemy-laid mines never trigger on enemies" stands). This changes the hub minefield slightly (EMP weight 0.15). **Owner choice**, default yes. |
| S16 | "Enemies should also respect the jammer" | No enemy has "abilities". The closest equivalents are seeker guidance (enemy Pursuit / Cluster rockets), the Support Ship's ward and the Hacker's own pulse. | Recommended reading (§3.1.5): the jammer **jams seeker guidance of everything inside it**, both sides. The Missile Corvette respects this through its existing kind choice. The Hacker does not pulse a rocket inside a field. The faction's shields and wards are unaffected (it is their jammer). |
| S17 | Tests "in both harnesses" | `tests/helpers/enemy_ai_harness.gd` (`open_space()` / `assault()`), label-parameterised dual-mode rows, and `test_player_boost_disruption.gd` already hand-tick **both real player scenes**. | No new harness. The lock rows copy the boost-disruption file's shape. |
| S18 | — | Gate time: Ph8 closed at **212.4 s** of the 240 s ceiling (2634 tests). Headroom is about 27.6 s. | The plan needs a gate-time allotment (≤ ~20 s for the phase) and the Ph8 rule that a task passing 238 s escalates. |

**Net scope change:** add S3 (the homing-missile lifetime fix) and the enemy EMP hook (S5) as in-scope prerequisites. Move
jammer-linked turret power to Ph20 (S9). Audio becomes a seam (S10, owner choice). The Hacker variant is decided but left unplaced
(S14). Nothing in the phase's scope was already built by an earlier phase except the `EmpPulse` / `apply_emp` shell and the reserved
`disables_abilities` field, which this phase fills.

---

## 2. External findings

Gathered by a web-research pass on 2026-11-06. Most wiki pages returned 403 to a direct fetch and were read through
`scripts/fetch-page.sh`'s reader proxy (marked "proxy"). **No shipped game was found in which enemies hijack the player's own
missiles**: the nearest analogues are deflection (Genji) and lock-breaking (flares, ECM, decoys). **No source gave telegraph times in
seconds, and none described a grace delay after leaving a jamming field.** Those two numbers are judgement (§4).

| # | Finding | Tradeoff for this phase | Typical values (as read) | Source |
|---|---|---|---|---|
| F1 | **Dota 2 Silence** blocks active abilities and cancels channels. It does **not** block items (a separate status, Mute), passives, already-cast effects, movement or attacks (attacks are Disarm). The HUD puts a grid over the locked ability icons, and pressing one shows a red "Silenced" message. | This is the model for §3.1.1 A: lock the *use* of H modules and K, and leave passives, running effects, movement and primary fire alone. A refused press needs visible feedback (the chip flash), not silence. | No durations on the page | https://dota2.fandom.com/wiki/Silence (403 direct; read fully via proxy) |
| F2 | **Overwatch, Sombra's Hack:** a hacked hero cannot use abilities but moves and shoots. The lock was tuned 1.5 → 3 → 1.5 → 1.0 → 1.75 → 1.5 s across patches, with Blizzard noting that shorter feels "less oppressive" and that the lockout "often goes unnoticed, unless it's being used as an active interrupt". Damage interrupts the cast. | A timed lock longer than ~2 s is oppressive, and one shorter than ~1 s is barely felt. That bounds the Disruptor variant's lock (1.5 s) and the EMP lock (2.0 s). The damage interrupt supports cancelling the Hacker's pulse when it is shot during TELEGRAPH (§3.3.2). | Lock 1.0–3.0 s over its history; cast 0.65–0.85 s; cooldown 4–8 s | https://overwatch.fandom.com/wiki/Sombra (402 direct; abilities and patch history via proxy) |
| F3 | One Hack patch made the "Hacked" warning show **only while the lock holds**, not for the rest of the debuff. | The "JAMMED" chip must mean exactly "you cannot use H / K now". The stabilisation fill is part of the lock, so it is shown. Nothing cosmetic may linger after the unlock. Test row: the chip hides on the unlock tick. | — | same Sombra page (proxy) |
| F4 | **Warframe Nullifier bubble:** a visible sphere inside which abilities cannot be cast. Shooting it shrinks it (6 % per hit, with per-hit damage clamped so every weapon shrinks it at the same rate), and killing the projector removes it for good. | The jammer field must be **visible and destroyable from outside** (primary fire is never locked, so the player can shoot the tower from inside or out). Shrinking the field under fire was considered and **rejected**: it would add a second health model. The tower's HP is the counter. | 6 % per hit; damage per hit clamped 100–400 | https://warframe.fandom.com/wiki/Nullifier_Crewman (403 direct; via proxy) |
| F5 | **EVE Online ECM:** a jammed ship loses every target lock and can lock nothing **except the ship jamming it**, for a 20 s cycle, landing on a strength ratio roll. | "Fight back at the source" should stay open. Primary fire and the player's aim stay free, so the jammer and the Hacker can always be shot. **A random lock chance is rejected**: in an action game a dice-roll lock reads as unfair (judgement). | 20 s cycle; chance = ECM ÷ sensor strength | https://wiki.eveuniversity.org/Electronic_warfare (read fully) |
| F6 | **Elite Dangerous:** chaff breaks only **gimballed / turreted** (assisted) aim; fixed weapons are unaffected. ECM makes seeker missiles lose lock and expire, and torpedoes stall "for a few seconds" and then re-acquire. | Electronic warfare targets **assisted aim, not manual fire**. That is exactly R9.16 (seekers, not the primary gun) and the seeker-jamming rule of §3.1.5 / §3.4.2. Losing lock means flying straight, which is readable. | ECM cooldown 10 s | https://elite-dangerous.fandom.com/wiki/Chaff_Launcher, https://elite-dangerous.fandom.com/wiki/Electronic_Countermeasure (403 direct; via proxy) |
| F7 | **Overwatch, Genji's Deflect:** a reflected projectile becomes Genji's at full damage, but **homing projectiles lose homing and fly straight** along his aim. | The fairness lever for a turned rocket is its **guidance**, not only its damage. §3.2 keeps a short, turn-limited guidance window (R9.13 asks for a rocket that visibly turns back toward the player) and cuts the player damage to a blast, because three arrive at once. The plan's alternative is "claim, then fly straight at the player's position at the claim" (Genji rule): simpler and fairer, but a straight rocket is a weaker threat. | — | https://overwatch.fandom.com/wiki/Deflect (403 direct; relevant section via proxy) |
| F8 | **FreeSpace 2 Open tables:** homing turn rate is a **period** (`+Turn Time`, seconds per 360°). A decoy's pull = decoy effectiveness ÷ seeker strength, applied only inside its effective radius. | A capped turn rate with a radius gate is the standard model. It confirms §3.2's `hijack_turn_rate` cap and `hijack_range` gate. A strength ratio would suit a later "hardened seeker" tier (Ph16), not the base Hacker. | Seeker strength: heat 3.0, aspect 2.0; decoy effectiveness 1.0; radius 300 m | https://wiki.hard-light.net/index.php/Weapons.tbl (403 direct; homing / countermeasure sections via proxy) |
| F9 | **Flares are scarce and not guaranteed:** Battlefield 3/4 has an 11 s re-use with an audio cue and a HUD "ready" indicator. Ace Combat: Assault Horizon gives 5 / 6 / 9 flares per class. | Retargeting has to be **gated and visible**, or it removes the need to dodge. For us the gate is the Hacker's cooldown (6–8 s), its visible PULSE window and the claim cap (3). | 11–15 s re-use; 5 / 6 / 9 charges | https://battlefield.fandom.com/wiki/IR_flares (proxy), https://acecombat.wiki.gg/wiki/Flares (proxy, read fully) |
| F10 | **Halo 3 Power Drain** (an EMP): 0.5 s arm, then a visible blue field for 6.5 s that strips shields and disables light vehicles of **everyone** inside, through walls. | An EMP area that hits all factions is a positional hazard both sides respect, and a tool the player can turn on enemies. That supports the neutral **EMP zone** (§3.4.3), placed EMP mines reaching enemies (S15), and the arm time as its telegraph. | 0.5 s arm + 6.5 s field | https://www.halopedia.org/Power_drain (read fully) |
| F11 | **FTL hacking pulse** disrupts a system for 4 / 7 / 10 s with a 20 s cooldown and **does not change the system's own cooldown**. Sombra's EMP cast was raised 0.2 → 0.35 s specifically "to react" and for "more counterplay". | A lock must neither spend nor reset cooldowns. §3.1.2 goes one step kinder: **module cooldowns keep ticking while locked** (`tick()` is not gated), so a lock never costs time after it ends. The wind-up exists for counterplay, which backs the Hacker's TELEGRAPH and the EMP zone's arm time. FTL's 4–10 s windows suit a pausable game, not ours. | 4 / 7 / 10 s, 20 s cooldown; EMP cast 0.35 s | https://ftl.fandom.com/wiki/Hacking (proxy), Sombra page (proxy) |
| F12 | **Readability of loss of control:** Riot groups loss-of-control indicators by the lost verb ("Can't Cast: Silence", "Can't Move: Rooted", "Can't Attack: Disarmed"). Blizzard cut most crowd control in Overwatch 2 because the game "felt like … a pinball machine", and capped Mei's slow at 1.5 s. Mike Stout: "the player must first know the damage is coming". | One label naming the lost verb ("JAMMED: abilities"), on the ship and on the HUD. **Do not stack EW effects on the player**: §3.1.2's "longest wins, nothing stacks" rule, and the placement rule that keeps Hacker and jammer apart. | Mei slow 1.5 s; no telegraph timings on any page read | https://www.surrenderat20.net/2013/01/future-feature-discussion-loss-of.html (read), https://www.pcgamesn.com/overwatch-2/crowd-control (403; proxy), https://www.gamedeveloper.com/design/enemy-attacks-and-telegraphing (read through a summarising fetch, not verbatim) |

**Unreachable or empty:** Liquipedia (Dota 2 Silence, StarCraft 2 EMP Round): 403, and the proxy failed as well. starcraft.fandom.com
EMP Round, callofduty.fandom.com EMP Grenade, deusex.fandom.com EMP grenade: the proxy returned navigation only. overwatch.fandom.com Genji
(not retrievable). overwatch.wiki.gg Genji (empty stub). ftl.fandom.com Ion damage / Ion Weapons (no body). Destinypedia "Suppression"
(404). hard-light.net Countermeasure (stub). Nothing was found for Everspace 2 flares, Star Citizen decoys, Hawken, or Ratchet & Clank.

**Judgement calls with no source:** the stabilisation delay (0.75 / 1.25 s), every telegraph length (0.8–1.0 s), the hijacked rocket's
numbers (they come from the project's own Ph5 fairness rows, not from an external source), and rejecting a random lock chance (F5).

---

## 3. Candidate approaches

### 3.1 The ability lock (R9.1, R9.3–R9.10)

#### 3.1.1 What is locked (Q1–Q3)

| Option | Locks | For | Against |
|---|---|---|---|
| **A. H abilities + K special weapon** (recommended) | Every `try_activate()` from the H loop, and the K launch in `RocketState._on_action()` (both rocket types). Never movement (thrust, turn, Shift boost, dash, warp), never primary fire (`WeaponState`), never weapon switching. | Matches "special abilities / skills", "not movement or primary fire" (IDEAS §6.6). It is the MOBA "silence" split (finding F1): the basic attack and movement stay, so the player is never helpless. K is the tool that most changes "what tools the player can use". | A jammer next to a Hacker makes the hijack moot (the player cannot launch). Place them apart (placement rule, §3.6). |
| B. H abilities only | H loop only | The smallest change | K (homing rockets) is the obvious "special" tool, and leaving it open makes the jammer barely noticeable when no H module is equipped (H slots start empty for a new save). |
| C. A + dash / warp / Shift boost | Also the movement verbs | The strongest effect | Contradicts "should not normally disable basic movement". Boost verbs already have a debuff channel (`apply_boost_disruption`, the Ph7 excess rule) for EMP / pulse mines. |

**Passive modules** (Pierce, Overclock, Shooting, Armor Plating, Warp flag) are **not** locked. They are stat changes, not "use" actions,
and locking them would mean per-module edits and would change primary-fire numbers, which R9.3 forbids. An ability that is
**already running** when the lock engages (a Shield Overload window, an Engine Boost burst) finishes its own duration. The lock
refuses new activations; it does not cancel effects. This is the Dota 2 silence rule (F1) and avoids a cancellation path through
15 modules. Module cooldowns **keep ticking** while locked (`tick()` is not gated), so a lock never costs time after it ends (F11: a disruption must not spend or reset cooldowns).

#### 3.1.2 Lock model (Q4)

| Option | How | For | Against |
|---|---|---|---|
| **A. Sampled + timed, on `PlayerBase`** (recommended) | Each physics tick, `_step_disruption()` (already first in both ships' ticks) samples `Hazards.around(global_position, 0)` for an info with `disables_abilities` that is *lit*. Timed sources (EMP, the Hacker variant) call `apply_ability_lock(seconds, source)`, where the longest wins and nothing stacks (the `apply_boost_disruption` rule). `abilities_locked()` is true while any source holds or the stabilisation clock runs. `ability_lock_changed(locked: bool)` fires on change only. | Follows the Ph6 convention that **hazards are sampled by the body**. There is no enter/exit signal to lose when a structure dies or a pulsed field goes QUIET: the next tick simply finds no field. It is hand-steppable for tests, and the existing pattern makes the unlocked path a cheap early return. | One `Hazards.around` call per tick while any hazard exists. The registry is small (it is already called per tick for `penalty_at`). |
| B. Area2D overlap on the jammer (`body_entered` → lock) | Signals | Familiar Godot idiom | Breaks the sampled-hazard convention, needs a collision bit (Ph6 left bit 12 unallocated on purpose), and loses the exit when a jammer is freed while overlapping. |
| C. Per-module `locked` flag | Each module checks | Fine-grained | 15 edits, and a forgotten module is a silent hole. |

**Stabilisation delay** (R9.6): leaving every field starts `stabilise_seconds`. Re-entering cancels it, and the full delay restarts on the next exit. A
pulsed field's QUIET phase counts as "outside", so the delay also applies when a pulsed field turns off. Timed locks (EMP) end
**without** a stabilisation delay: their duration already is the debuff. The delay is a property of a field (it lives in the field's
`HazardInfo`/structure export), read at the moment of exit. That way a sector jammer can have a longer one.

**A refused press spends nothing.** The check runs before `try_activate()` (so no module cooldown starts) and before
`cooldown_timer.start()` in `RocketState`. A refused press gives feedback: the HUD chip and ship tell flash (F1).
It is consumed (`set_input_as_handled()`), so H does not fall through to another listener.

#### 3.1.3 Where the check goes

There are three seams, all existing: `OpenSpacePlayerShip._input` (before the module loop), `PlayerFighter._input` (same),
`RocketState._on_action` (`special_weapon` branch only; `switch_weapon` stays free). `RocketState` reaches the lock through its existing
`actor` export (`actor.has_method(&"abilities_locked")`, duck-typed, so a test actor without it is never locked). `WeaponState` is not
edited: the "primary fire never affected" rows assert this by firing inside a lit field in both real ships, at a cadence bit-identical
to a run with no field.

#### 3.1.4 Tells (R9.5, R9.15, Q14)

- **Field:** a code-drawn ring at the radius with a crawling interference band (short dashed arcs, a few px wide, low alpha) and a
  slow rotation, so it reads as "zone" rather than "wall". It is distinct from the mine / gravity-well rings: amber-white static, not
  cyan (cyan = shield in IDEAS §21) and not violet (the boost-disruption colour). The pulsed variant's TELEGRAPH flickers the ring
  for its telegraph time before ACTIVE (the HazardField anomaly precedent).
- **Ship:** a small "static" overlay on the player while locked, code-built like `BoostDisruptionRing`, with a distinct shape.
- **HUD:** a shared chip in `MissionHud` ("JAMMED") whose fill shows the stabilisation countdown, plus a lock glyph over the
  special-weapon icon. Both modes, since `MissionHud` is shared.

#### 3.1.5 Enemies and the jammer (R9.7, R9.8, Q13)

| Option | For | Against |
|---|---|---|
| **A. Zero avoidance for enemies, placement around it, seeker jamming both ways** (recommended) | The jammer's `HazardInfo.avoid_weight` is 0 (`Steering.context_avoid` skips it), so enemy ships **fight through it freely**: the field is their terrain, unlike a gravity well. It is placed with shooters around it (a hub site with the jammer, the Ph8 hub site idea). Inside the field, **seeker guidance is jammed for everything**: player homing rockets and enemy Pursuit / Cluster rockets fly straight (dumb rockets unaffected). That is the "respect" half: the Missile Corvette's `MissileCorvetteBrain.choose_kind()` chooses Dumb when its target is inside a field, and the Hacker does not pulse a rocket inside a field. | It uses existing seams only (`avoid_weight`, `choose_kind()`, `EnemyRocket.is_guiding()`). It is symmetrical and readable ("seekers don't work in the static"), and it adds a counterplay: pull a corvette's rockets through a field. | Squad-level "pin the player in the field" tactics wait for Ph14 squad communication. |
| B. Brains bias their held position to keep the player inside the field | Stronger "fight around" | A per-brain change in five brains, which is Ph14 territory |
| C. The jammer also suppresses enemy wards / shields | Pure symmetry | Contradicts "the structure is part of their tactical advantage" |

### 3.2 The seeking-rocket retarget hook (R9.2, R9.13, Q6–Q9)

**Contract** (duck-typed, like `is_armored()` / `deflects_hit()`): every eligible player seeking projectile joins group
`&"player_seeking_ordnance"` in `_ready()` and answers

- `can_be_retargeted() -> bool`: false once hijacked, fizzling, or inside a jammer field.
- `retarget(target: Node2D, seconds: float, source: Node) -> bool`: the claim. It returns false if refused.
- `is_retargeted() -> bool`, and `signal retargeted(source: Node)` / `signal retarget_ended()`.

Only `homing_missile` implements it in Ph9 (S2). `WarheadMissile` does not join the group, so it is not eligible (R9.16). The group gives the
Hacker both **in-flight** and **newly launched** rockets with no launch signal: a rocket launched this frame is in the group on the
Hacker's next physics tick.

**What a retargeted homing missile does** (Q7). This is a mode switch inside the missile, not a new scene:

| Rule | Recommended | Why |
|---|---|---|
| Steering | Turn-rate limited (`Steering.turn_toward`, `hijack_turn_rate` ≈ 1.6 rad/s, the Pursuit rocket's), toward `target.global_position` | Today's missile has **no turn rate** at 500 px/s. Retargeted as is, it would be unescapable (the fighter's cruise is 360 and the Open Space ship's 420). A visible turn-around is also the tell R9.13 asks for ("visibly rotate away … and turn back"). |
| Speed | Drops to `hijack_speed` ≈ 380 px/s over the turn | Faster than the Assault fighter's 360 but slower than the Open Space cruise 420 and every boost. It is dodgeable by a turn plus a short boost, which is the Ph5 Pursuit-rocket fairness band (440 cruise / 1.6 rad/s, 3 s guidance, gated by its dodge rows). |
| Duration | `hijack_seconds` ≈ 2.5 s of guidance, then it **fizzles** (pops harmlessly, `expired`) | "Short duration" (§11.2). Fizzling, rather than handing it back to the player, avoids a yo-yo rocket and a second retarget pass. |
| Player damage | Blast only: a `ContactBlast` (layer 256) on proximity / contact with the player, ≈ 18 damage, r 40 (the Pursuit rocket's) | Player HP is 50, so three hijacked rockets at the missile's own 100 would be an instant kill. The blast rule is Ph5's, and it needs no new layer (S4). |
| Enemy damage | Keeps its HitBox (mask 513) and **full** damage against enemies | The "lure it into another enemy" counterplay (R9.17) has to pay off. |
| Shoot-down | A HurtBox (layer 512, mask 64) enabled only while hijacked, 1 hit | A primary-fire counter that the jammer and the Hacker never touch (R9.3). It is the Ph5 `EnemyRocket` precedent. |
| Arming | The blast never arms within 0.25 s of the claim, or within 60 px of the player at the claim | Prevents a rocket claimed at launch from detonating on the launcher before the player sees it turn. This is the `EnemyRocket` arming rule. |
| Visual | Accent swap on the sprite (amber "hacked" tint on the exhaust and a target-bracket ring), a tether flash from the Hacker at the claim | IDEAS §21: change a light, not the hull. |
| Jammer | No retarget inside a jammer field. Guidance is jammed there anyway (§3.1.5) | Consistent with S16 |

**Delivery of the Hijack Pulse** (Q6):

| Option | For | Against |
|---|---|---|
| **A. A PULSE window on the Hacker plus a visible control dart per claim** (recommended) | TELEGRAPH (the yellow `StateLight`, the antenna dish lights) → PULSE for `pulse_seconds`. During PULSE, each tick the Hacker claims every eligible rocket within `hijack_range` with LOS by firing a fast non-damaging **Hijack Pulse dart** at it (≈ 900 px/s, pooled `BulletPool` round with a `ProjectileLifetime`). The rocket is retargeted when the dart touches it. Rockets launched during the window are claimed the same way ("newly launched"). | Every claim is visible (dart, tether flash, the rocket turning), so R9.14's "non-damaging control projectile" is literal. Holding K during the visible PULSE window is the counterplay R9.17 names. LOS lets cover block it. The dart can be dodged by the *rocket*, which is rare but readable. | A pooled projectile kind (small). |
| B. An expanding ring from the Hacker claiming what its band crosses (the `EnergyRing` swept-interval code) | Reuses Ph8 code | A rocket launched just behind the band is never claimed, so "newly launched" needs a second rule anyway. One ring covering the whole range also reads as a damaging weapon. |
| C. Hitscan claim, no projectile | The simplest | No "control projectile" (§11.2), and the claim cannot be seen |

**Cap:** at most `max_claims_per_pulse` (≈ 3, the homing salvo size) claims per PULSE, one dart per rocket.

#### 3.2.1 The lifetime prerequisite (S3, Q9)

Replace the missile's `_ARENA_*` box with a `ProjectileLifetime` child (`max_time` ≈ 6 s, `max_distance` ≈ 2400, `use_world_rect` true). In
Assault this is the same rect from `EnemyWorld.projectile_world_rect()`, so Assault homing behaviour is unchanged apart from the new
time and distance caps (a rocket circling a dead target already flies forward and leaves the rect well inside 6 s at 500 px/s). In Open
Space the rockets start working anywhere in the hub. The rockets keep their one owner (`RocketState`'s child, `expired → queue_free`). The
`test_player_bullet_lifetime.gd` ownership sweep should gain a row for the missile (it currently enumerates `WeaponBehavior`s only).

### 3.3 The Hacker Frigate (R9.11–R9.18)

#### 3.3.1 Shape

A `BaseEnemy` + `EnemyBrain` + `EnemyMover` ship (the Ph1 stack), 96×96 art (inside the 80–120 px brief and IDEAS §22's 80–128 specialist
band). Narrow hull with a large forward antenna / dish (a distinct silhouette from the corvette's tubes and the support's projector), a
`StateLight` (yellow = charging, white = pulsing). Weak hull: HP ≈ 120, below the corvette's 160, because it is a "high-priority
disruption target" (R9.11). `ContactProfile` COLLISION, low.

#### 3.3.2 Movement (R9.12)

HOLD_ARC composed from `MissileCorvetteBrain`. Held range ≈ 720 (Open Space) / 520 (Assault), above the corvette's 620 / 460, so the two
read as different jobs. Arcs are **asymmetric**: the angular speed differs per direction (for example 0.18 rad/s one way and 0.30 the
other), and reversals come at random 3–6 s. A **bearing penalty** keeps it out of the player's nose cone (± 30°) and off the player's
velocity line (the §18.6 "outside the preferred route" rule; SniperBrain scoring precedent). When the player closes inside `min_range`,
it breaks contact (`Steering.break_contact`) and **does not pulse while breaking**. It pulses only with LOS (`can_see_player()`), so "force
it behind cover" works. **Damage during TELEGRAPH cancels that pulse** and starts the cooldown (F2: Sombra's hack is interrupted by damage). It is the "destroy / pressure the Hacker" counter made immediate, and it is testable with one hit.

#### 3.3.3 Assault (R9.18)

`SupportShipBrain._clamp_into_view()` keeps the hull inside `EnemyWorld.view_rect()` minus a margin. An `EngagementBudget` gives one life
in the corridor, with up to 2 pulses per life, then DISENGAGE with a measured exit (`specialist_exit_probe.gd`). Hijack behaviour is
unchanged in Assault.

#### 3.3.4 The variant (S14, Q5)

| Option | For | Against |
|---|---|---|
| **A. "Disruptor" config flag: the pulse also locks abilities for `pulse_lock_seconds` ≈ 1.5 s if the player is within `hijack_range`** (recommended) | It uses the lock hook (`apply_ability_lock`), so it costs almost nothing. "Briefly disrupt a skill/ability system" is literal. The base Hacker keeps its single trick (the flag is 0 in the base `.tres`). | Two EW effects on one ship. That is why it is not placed in Ph9. |
| B. Shield hack (`Shield.set_hacked`) | Art exists | It drains every charge in one call: a heavy, permanent loss, not "brief". Rejected. |
| C. No variant | Cheapest | The epic asks this phase to decide |

Built and tested in Ph9 (one row in each harness), **placed in Ph13 / Ph16**.

### 3.4 EMP (R9.19–R9.21, Q10–Q12)

#### 3.4.1 The real player effect (replacing the Ph7 stand-in)

| Option | Effect | For | Against |
|---|---|---|---|
| **A. Ability lock + keep the boost disruption** (recommended) | `apply_emp()` calls `apply_ability_lock(seconds, source)` as well as the existing `apply_boost_disruption(1.0, seconds)`. Player seeking rockets within the EMP radius lose guidance (fly straight) | "Disrupts systems": the lock and the boost are the two existing player systems that fit (§11.4 "only if this fits the existing player mechanics"). Every Ph7 EMP row (`test_enemy_mines.gd`, `test_player_boost_disruption.gd`) stays green. `is_emp_disrupted()` / `emp_changed` keep their meaning. | It is stronger than the stand-in. EMP windows are short (2.0 s for the mine). |
| B. Replace the boost disruption with the lock | The Ph7 comment's literal reading | It rewrites pinned Ph7 rows, and boost is the most "systems" thing the ship has |
| C. Shield drain | Fits the "EMP strips shields" convention (F10) | The shield component has no partial drain. `set_hacked` empties all charges. That is too strong for an area weapon. |

#### 3.4.2 Enemies and seekers (`EmpPulse` extension)

Keep `emit(tree, at, radius, seconds, source) -> int` and add a **defaulted trailing** `targets: int = TARGET_PLAYER` bitmask
(`TARGET_PLAYER | TARGET_ENEMIES | TARGET_SEEKERS`). Existing callers are bit-identical (the Ph8 precedent: `SpecialistExitProbe` gained a
trailing defaulted `prepare`). `TARGET_ENEMIES` calls a duck-typed `apply_emp(seconds, source)` on `BaseEnemy`: the brain's weapons and
special systems are held (`EnemyBrain.is_emp_disrupted()`), the mover coasts at a reduced speed, the `StateLight` goes dark, and the ship
**stays tangible**. An Assault `EngagementBudget` keeps running, so an EMP can never stall a section. `TARGET_SEEKERS` ends the guidance of
player homing rockets and enemy Pursuit / Cluster rockets in range. The `test_emp_pulse.gd` row "never touches group enemies" stays true
for the default target set, and a new row covers `TARGET_ENEMIES`.

Callers: the enemy-laid EMP mine stays `TARGET_PLAYER | TARGET_SEEKERS`. A placed (`ALL`) EMP mine adds `TARGET_ENEMIES` (S15, owner
choice). The EMP zone uses all three. `EMPBlastModule` (re-routed, Q11) uses `TARGET_ENEMIES | TARGET_SEEKERS` around the player, with
its 5 s / 15 s / immune list kept.

#### 3.4.3 The EMP Pulse area weapon and EMP zones (Q12)

| Option | For | Against |
|---|---|---|
| **A. An EMP zone: a placed, neutral pulsing area** (recommended) | A `HazardField`-cycled node (TELEGRAPH ≈ 1.0 s, a visible contracting ring → PULSE: an expanding `EmpRing`-style ring, `EmpPulse.emit(…, all targets)` once → QUIET). It registers as `&"emp_zone"` with `avoid_weight` ≈ 0.6, so enemies avoid it and can be baited through it (the Ph6 rule: hazards affect enemies by their physical rules). It covers §11.4 and §18.6 in one piece. | — |
| B. The pulsed jammer emits an EMP at each ACTIVE start | One fewer structure | It merges two readable effects into one confusing one |
| C. An enemy-mounted EMP weapon | §11.4 lists it as a weapon | No Ph9 enemy needs one. The Carrier's "anti-approach pulse" (Ph10/18) is the natural first user, and the same `EmpPulse` call serves it |

### 3.5 The Jamming Structure (R9.4–R9.10)

`JammingStructure` (`assault/scenes/structures/jamming_structure/` or under `enemies/` beside `shield_generator`, for the plan to decide by
the roster sweeps' directory rules). A static `BaseEnemy`, no mover, `AssaultDrift`, `ContactProfile` NONE, `is_laser_blocking()` false,
`counts_as_escape` false, joins `enemies`. It owns one `HazardInfo` (`kind = &"jammer"`, `disables_abilities = true`, `avoid_weight = 0`,
`radius` per variant), registered in `_enter_tree()` (scene-placed) and unregistered on death. Dying turns the field off on the same tick
(the lock then starts its stabilisation delay). **Variants as `.tres` + inherited scenes**, not code paths:

| Variant | Radius | Cycle | Stabilise | Where |
|---|---|---|---|---|
| Local | ≈ 240 px | always on | 0.75 s | both modes |
| Sector | ≈ 640 px (Open Space); not in Assault (it would cover most of the 1280 px view) | always on | 1.25 s | hub objective / site |
| Pulsed | ≈ 300 px | TELEGRAPH 0.8 / ACTIVE 3.0 / QUIET 2.5 s | 0.75 s | both modes |

HP: local ≈ 140, sector ≈ 260 (a priority target that takes a commitment), pulsed ≈ 160. Art: a top-down tower with emitter vanes,
≈ 64×64 (local and pulsed) and ≈ 96×96 (sector), with an emitter light that pulses with the field and goes dark when off (IDEAS §23).

### 3.6 Placement (R9.22, Q15)

- **Hub:** draws 18+ appended: a Hacker on a free bearing of the 2600 ring (for example 67.5°) with `AnchorIdle`, plus a jammer site.
  The recommendation is one **local jammer** with a fighter pair patrolling it, at a new site that clears the spawn, triggers and pickups
  by its field radius plus the Ph8 sweep margin, and one **EMP zone** somewhere away from the spawn. The sector jammer is used in the hub
  only if a site's clearance allows it (sweep A).
- **Level 1:** one Hacker and one local or pulsed jammer, each in a DURATION section **off its measured peak** (deep_space after its 29 s
  twin pair, or planet_approach away from 98.0 s). Never in `ENEMIES_CLEARED` (guard rows in `test_engagement_deadline.gd`, like Ph8's).
  The jammer is world-anchored and must clear every lit laser column and the level-start `LaserWallWave` (x 0–672), the Ph8 t19 lesson.
  **Do not place the Hacker inside or next to a jammer** (§3.1.1 A).

---

## 4. Starting values

| Value | Start | Source |
|---|---|---|
| Lock stabilisation (local / pulsed / sector) | 0.75 / 0.75 / 1.25 s | **Judgement**: no source covers a grace delay (§2). It must exceed one physics tick and stay well below a module cooldown |
| Timed lock: EMP mine | = EMP seconds (2.0 s) | Ph7 `emp_mine.tscn` |
| Timed lock: Disruptor variant | 1.5 s | F2 (the Hack lock was tuned within 1.0–1.75 s; under ~1 s it goes unnoticed) |
| Local / pulsed / sector jammer radius | 240 / 300 / 640 px | Judgement: the player crosses 480 px in ~1.1 s at 420 px/s; sector ≈ half the 1280 px view |
| Pulsed cycle | 0.8 / 3.0 / 2.5 s | Ph6 anomaly cycle shape; judgement |
| Hacker held range OS / Assault | 720 / 520 px | Above corvette 620 / 460 (`missile_corvette_config.tres`) |
| Hacker telegraph / pulse window / cooldown | 0.9 s / 1.6 s / 6–8 s | **Judgement** (no source gave telegraph seconds, F12), next to the corvette's 0.7 s salvo telegraph; F11 backs a wind-up for counterplay; cooldown per F9's "gated" rule |
| Hijack range | 650 px, LOS required | Judgement: inside the held range, so a rocket fired at the Hacker itself is claimable |
| Hijack dart speed | 900 px/s | Judgement: arrives in ≤ 0.75 s at range, visible but reliable |
| Hijacked rocket speed / turn / guidance | 380 px/s / 1.6 rad/s / 2.5 s | Ph5 Pursuit rocket fairness band (440 / 1.6 / 3.0), lowered because three arrive together |
| Hijacked rocket blast | 18 dmg, r 40, arm 0.25 s / 60 px | Ph5 `pursuit_rocket.tscn` |
| Max claims per pulse | 3 | Homing salvo size (`homing_count` 3) |
| Hacker HP | 120 | Below corvette 160 (priority target) |
| Homing missile lifetime | 6 s / 2400 px | The Ph5 shared caps (`test_enemy_bullet_lifetime.gd` uses 18 s / 2400 px synthetic) |
| EMP zone cycle / radius / seconds | 1.0 telegraph, pulse every 6 s, r 260, 2.0 s | EMP mine 190 px / 2.0 s, scaled up for an area structure |

---

## 5. Recommendations

### 5.1 Answers to the open questions

| Q | Recommended answer |
|---|---|
| Q1 | H abilities + the K special weapon (both rocket types). §3.1.1 A |
| Q2 | Dash, warp and Shift boost are movement: never locked by the jammer. EMP still disrupts them through the Ph7 boost rule |
| Q3 | Passive modules are not locked. Running effects finish |
| Q4 | Sampled hazard + timed sources on `PlayerBase`: `apply_ability_lock(seconds, source)`, `abilities_locked()`, `ability_lock_changed(locked: bool)`. §3.1.2 A |
| Q5 | The variant is the "Disruptor" config flag (a 1.5 s lock on pulse). Built and tested, not placed. §3.3.4 |
| Q6 | A PULSE window plus a non-damaging dart per claim. Covers in-flight and newly launched rockets. §3.2 A |
| Q7 | Turn-limited (1.6 rad/s), 380 px/s, 2.5 s, then it fizzles. Blast-only player damage (18 / r 40), full damage to enemies, shootable while hijacked. Alternative for the plan: the Genji rule (F7), where a claimed rocket flies straight at the player's position at the claim: simpler and fairer, but a weaker threat |
| Q8 | Homing missiles only (group `player_seeking_ordnance`). Warheads excluded |
| Q9 | Yes: `ProjectileLifetime` on the homing missile, as a prerequisite task (S3) |
| Q10 | EMP = ability lock + the kept boost disruption + seeker guidance loss. Enemies get a tangible `apply_emp`. Placed EMP mines reach enemies; enemy-laid ones do not |
| Q11 | Re-route `EMPBlastModule` through the enemy hook (it fixes the intangible-stun bug), keeping 5 s / 15 s / the immune list. Owner choice |
| Q12 | An EMP zone structure (neutral, cycled). Ship-mounted EMP waits for its first user (Ph10/18) |
| Q13 | Zero avoidance for enemies, placement with shooters, seeker jamming both ways, the Corvette picks Dumb rockets, the Hacker never claims inside a field |
| Q14 | Ship-local static overlay + a shared `MissionHud` "JAMMED" chip with the stabilisation fill + a lock glyph on the special-weapon icon |
| Q15 | Hub draws 18+ (Hacker on the 2600 ring, a jammer site, an EMP zone). Level 1: one Hacker and one jammer, off the measured peaks, DURATION sections only |
| Q16 | An `EventBus` seam (`player_ordnance_hijacked(rocket: Node2D, source: Node)`, `player_abilities_locked(locked: bool)`), with audio in Ph17. Owner choice, because the epic names audio |

### 5.2 Choices for the owner (defaults taken in brackets)

1. Does the jammer also lock the K rockets, or only H abilities? [H + K]
2. Should the player's own EMP Blast ability be re-routed (fixing that stunned enemies cannot be shot), which changes a shipped ability? [yes, same numbers]
3. Should placed hub EMP mines also hit enemies? [yes; enemy-laid mines never]
4. Is the audio tell built now (a first audio pipeline) or a seam for Ph17? [seam]
5. Is the Disruptor variant placed now or later? [later: built and tested, placed in Ph13 / Ph16]
6. Should the homing missile start working across the whole Open Space hub (today it dies away from the origin)? [yes; required for in-flight hijack there]

### 5.3 Test requirements (for the plan's test plan)

Both harnesses (`enemy_ai_harness.gd` label-parameterised, never `use_parameters([HARNESS…])`), and the real player scenes for the lock
rows (the `test_player_boost_disruption.gd` shape).

- **Lock timing:** locked on the first tick inside a lit field. Still locked one tick before `stabilise_seconds` after exit, unlocked on
  the tick at it. Re-entry inside the delay restarts it. A pulsed field's QUIET counts as outside. Two overlapping fields and an EMP do not
  stack and never unlock early. A timed lock ends with no stabilisation. The jammer's death starts the delay. The HUD chip and the ship tell show on the lock tick and hide on the unlock tick, with nothing lingering (F3). `ability_lock_changed` fires once per edge. Module cooldowns keep ticking while locked (F11).
- **Refusals spend nothing:** an H press while locked starts no module cooldown (every H module in the pool), and a K press starts no
  `CooldownTimer` and launches nothing. The boundary rows press one tick before and one tick after the unlock.
- **Never affected:** primary fire cadence and damage inside a lit field and during a hijack, bit-identical in both ships for all five
  weapon modes. Thrust, turn, Shift boost, dash and warp are unchanged inside a field (no EMP). `switch_weapon` works while locked.
- **Retarget hook:** the contract on a fixture target (refusals: already hijacked, inside a field, warhead not in the group). In-flight
  claim: the rocket's heading turns at ≤ `hijack_turn_rate` per second toward the player. A newly launched rocket is claimed during PULSE.
  None are claimed outside PULSE or without LOS. At most 3 claims per pulse. A hijacked rocket damages the player only by blast (18) and an
  enemy at full damage (the lure). It is shot down by one player bullet. It fizzles at 2.5 s. A claim at launch never blasts the player
  inside the arming rule. Dodge rows: a straight run at cruise plus a late turn escapes (Ph5 dodge-row shape).
- **Homing lifetime:** an Open Space rocket far from the origin lives and is guided. An Assault rocket still expires on the world rect,
  and on `max_time`. Ownership sweep row.
- **EMP:** `EmpPulse` default target set unchanged (the Ph7 rows). `TARGET_ENEMIES` reaches enemies in radius (`<=` rule), holds their
  weapons, and keeps them shootable (a real bullet kills an EMP'd enemy; the EMP Blast boundary row). The Assault budget still expires
  under EMP. Seekers lose guidance. The player gets lock + boost refusal for the EMP window.
- **Hacker:** held range and asymmetric arcs, staying out of the nose cone, break-off inside `min_range` with no pulse while breaking, no
  pulse without LOS, a hit during TELEGRAPH cancels the pulse (control: no hit → PULSE), the Assault view clamp, one life and its pulses per Assault life, a measured exit, hub idle → notice.
- **Jammer:** each variant's radius and cycle. `avoid_weight` 0 (an enemy's path through it is unchanged). Seeker guidance off inside.
  The corvette picks Dumb against a player inside a field. It joins `enemies` and every roster sweep (contact damage, hitbox and hurtbox
  geometry, config isolation, sprite transparency, load integrity).
- **Placement gates:** the hub clearance sweeps for the new draws and the site. Level 1: the frozen 2.5× count gate stays green, the
  `ENEMIES_CLEARED` guard rows, and the jammer clears every lit column.
- **Gate time:** report before / after per task (`scripts/gate-time.sh`). Stay ≤ 240 s, with an allotment of about 20 s for the phase.
