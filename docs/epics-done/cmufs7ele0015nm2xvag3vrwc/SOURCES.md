# Enemy rework, phase 4 — sources

Merged from `docs/plans/cmufs7ele0015nm2xvag3vrwc/2-research.md` (§1 findings F1–F13) and `1-context.md`. A research subagent did the
web searches; pages that returned 403 were retried through `scripts/fetch-page.sh`. None of the six task-level plans
(`docs/plans/cmuyk2qq…/`) ran a separate web-research pass: they used this research and measurements from the live code. Values
marked **[judgement]** have no citable source.

| Source (URL) | What it contributed | Where it shows up in the build |
|---|---|---|
| https://developer.valvesoftware.com/wiki/Npc_sniper (read via the reader proxy) | HL2's `npc_sniper` keeps a target painted for a set time before firing; a faster flag multiplies it by 0.75; initial misses and decoys exist. | One configured AIM time and a difficulty lever that shortens *it* (`aim_seconds`, Ph16), never the lock; the decoy flag. |
| https://www.halopedia.org/Kig-Yar/Gameplay | Sniper Jackals were made fairer with slower targeting and a visor glow that warns and reveals position. | The telegraph gives the position away, so the Sniper breaks contact after every shot and picks a new point. |
| https://empexori.itch.io/operation-havok/devlog/978848/devlog-3072025-update-5-sniper-rebalancing ; https://www.moddb.com/news/counter-sniper-designing-the-sniper (via fetch script) | A laser that flashes before firing; a long inter-shot delay because a sniper can kill on the first shot. | The LOCK flash (`StateLight` COMMIT white) marks the moment tracking stops; the relocation leg is the recovery gap. |
| https://ki.infil.net/reaction.html | Reaction-time data: ~265 ms average, 27 frames "quite easy to react". | The Sniper's frozen LOCK stays **0.5 s** (30 frames); the ram's 0.65 s wind-up; difficulty shortens AIM, never LOCK. |
| https://forum.lastepoch.com/t/enemies-should-not-be-able-to-turn-while-theyre-winding-up-an-attack/19129 (player forum) ; https://gamedeveloper.com/design/enemy-attacks-and-telegraphing | Facing that keeps tracking through a wind-up shrinks the real window; the pre-attack delay is the fairness contract. | The Ram's aim tracks at ≤ 0.8 rad/s for the first 60 % of WIND_UP, then freezes; CHARGE never re-aims. |
| https://www.wayline.io/blog/the-art-of-the-fakeout-combat-design (blog) | A fake-out is fair only when readable and counterable. | The decoy line is dim orange, CHARGING-only, never COMMIT, behind `decoy_telegraph`. |
| https://www.guerrilla-games.com/media/News/Files/gdce05_killzone_ai.pdf (via reader proxy) | Position picking as a weighted sum of annotations over candidate waypoints. | `SniperBrain.choose_firing_point()`: sampled candidates scored `w_sep · Δ − w_travel · travel`. The "far from my last firing bearing" term is **ours** (no source). |
| https://dev.epicgames.com/documentation/en-us/unreal-engine/environment-query-system-overview-in-unreal-engine | Filter tests run before scoring, so fewer items need the expensive test. | Cheap filters (inset, path clearance, forward cone) first, the LOS ray only on survivors, capped at `max_los_rays` 6. |
| https://boardgamers2409.itch.io/plague-wardens/devlog/820382/enemy-balancing-antonio-roldan ; https://itch.io/post/12024854 ; https://steamcommunity.com/app/2366970/discussions/0/4434443557919428497 | Predictive aim needs damping (~0.6–0.64 on velocity) to stay fair; dash velocity should not be led fully. | The Bomber's gravity / pursuit lead (`lead_factor` 0.6, horizon ≤ 1.2 s) on smoothed velocity; the mine wall is the one **undamped** exception, only for 150 ≤ speed of v̄ ≤ 440 px/s. |
| https://shmups.wiki/library/Glossary ; https://www.gamedeveloper.com/design/bright-slow-and-deadly | Bullet-cancel and revenge-bullet conventions; enemy shots slower and brighter than the player's. | Shootable ordnance: any player hit defuses; killing the Bomber does **not** cancel its mines (the scope's choice). Mines blink for `warning_time`. |
| https://mhworld.kiranico.com/guide/understanding-monster ; https://blog.playstation.com/2017/02/24/the-making-of-horizon-zero-dawns-machines/ | Part-breaking: hard zones deflect, breaking a part removes an attack; machines with shoot-off components. | The Ram Corvette rule: bullets glance off, rockets break plates, losing them changes behaviour (faster, jinkier, vulnerable); deflection has its own flash. |
| https://docs.godotengine.org/en/stable/tutorials/physics/ray-casting.html ; https://docs.godotengine.org/en/stable/classes/class_physicsrayqueryparameters2d.html | `direct_space_state` is only safe in `_physics_process`; ray query defaults. | `LineOfSight.clear()` on the physics step only, an explicit mask (`ENVIRONMENT or HAZARD_CONTACT`), bodies only, own RID excluded. |
| https://forum.godotengine.org/139658/bullets-destroying-with-enemy ; https://forums.unrealengine.com/t/plugin-object-pool-component/81338?page=9 | Projectiles parented to their shooter die with it; an Unreal pool plugin added an option to orphan active actors. | `BulletPool.persist_after_owner_death`: on `_exit_tree` hand each projectile to its own `expired -> queue_free`. |

**Tried and unreachable, or not useful** (so a later phase does not repeat the dead end):
- Valve `Proto_sniper` — 403.
- doomwiki.org *Destructible demons* — 403 on WebFetch and on the fetch script; **snippet only** (Doom Eternal weak points).
- The 80.lv Horizon postmortem — announcement only, no content.
- Sparen's Danmaku Design Guide A2 — read, nothing on prediction or telegraphs.
- A bugnet.io telegraph article — read, no numbers.
- "Mine releases an aimed bullet when destroyed" (shmups.system11.org) — **snippet only**; not built.

**Judgement calls with no citable source** (starting values; tuned only where a gate forced it):
- the pursuit bomb's steering rate, every mine trigger radius, the decoy's exact shape (25–35°, 0.6 s), armour-plate HP (50), and the
  "different firing position" metric (≥ 45° in the player's frame);
- the three Assault budgets (sniper 9.0 s, bomber 8.0 s, ram 4.0 s) and the ram's `exit_speed` 560 — set by the Cloud Descent deadline
  arithmetic (`2-research.md` §4), not by a game reference;
- hub radii (perceive / lose) and the 1700 px ring with bearings 135° / 45° / 225°;
- the 2.5× density bound on the frozen specialist peaks (the plan's own choice);
- the Open Space ship's `apply_knockback` shove of 260 px/s for the ARMOR contact.
