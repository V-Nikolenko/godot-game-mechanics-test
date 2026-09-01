# Research — destructible-turret ("cores and turrets") bosses

**Method note / honesty caveat:** four of the most relevant pages (`shmups.system11.org`
forum thread, `tvtropes.org` ShieldedCoreBoss and CoresAndTurretsBoss, the Construct
destructible-parts tutorial) returned **HTTP 403** to the fetcher, and the Gradius wiki
returned **402**. The findings below are drawn from search-result excerpts of those pages plus
one page that did fetch (`shmups.wiki` Boghog). Where a number could not be confirmed from a
page body it is marked *(excerpt only)*. **No numbers here are invented** — the parameter
choices the plan makes are labelled as this project's own decisions, not as industry standards.

| Finding | Tradeoff | Typical values | Source |
|---|---|---|---|
| **"Cores and Turrets" is a named, codified boss pattern**: the boss decomposes into *cores* (the weak points that must be destroyed to win) and *turrets* (the weapons that threaten you meanwhile). Codified by Gradius ("Destroy the Core!") and a Compile trademark. | Splitting a boss into parts turns a single HP bar into a target-priority decision — but every extra part is more HP between the player and the win, which is exactly how a fight becomes a damage sponge. | Gradius Big Core line: **1 core** (original), **3 cores** (MK III), **4 cores** (MK IV) *(excerpt only)* | [Cores-and-Turrets Boss (TV Tropes)](https://tvtropes.org/pmwiki/pmwiki.php/Main/CoresAndTurretsBoss), [Big Core MK III](https://gradius.fandom.com/wiki/Big_Core_MK_III), [Big Core MK IV](https://gradius.fandom.com/wiki/Big_Core_MK_IV) |
| **The core is *guarded*, not merely low-priority.** In Gradius the core sits behind "small walls or force fields the player must break through before they can attack the cores themselves" — destructible walls that physically impede shots and act as "the boss' shielding gauge until its core is finally vulnerable to attack." | A *physical* blocker teaches the rule with zero UI: the shot visibly stops. A pure invulnerability flag (shot passes through, nothing happens) reads to a player as a bug. The cost of the physical version is collision authoring per blocker. | Shield gauge must be "whittled away by repeated well-placed shots" *(excerpt only)* | [Gradius (TV Tropes)](https://tvtropes.org/pmwiki/pmwiki.php/VideoGame/Gradius), [Shoot The Core](https://gradius.fandom.com/wiki/Shoot_The_Core_(phrase)) |
| **Remaining parts escalate as parts die**: "the more cores and turrets you have destroyed, the fiercer the rate of fire of the remaining ones." | Compensates for the fight getting mechanically easier as guns are removed, so tension holds to the end — but stacked naively it produces a difficulty *spike* on the last turret, which is where a player who has already invested two minutes will resent dying. | — | [Cores and Turrets Boss (Tropedia)](https://tropedia.fandom.com/wiki/Cores_and_Turrets_Boss) |
| **Many small part-hitboxes demand precision and can force unfair risk.** Star Fox's Great Commander has "six extremely small hitboxes/turrets that must all be hit", escalates its attacks as they die, and "eventually forc[es] players to risk collision damage to hit the last turret." | High part counts + small hitboxes = a precision test rather than a pattern-dodging test, and the *last* part is the one most likely to be badly placed. Argues for **few, generously-sized** turrets over many small ones. | **6** turrets is already described as a pain point *(excerpt only)* | [Cores and Turrets Boss (Tropedia)](https://tropedia.fandom.com/wiki/Cores_and_Turrets_Boss) |
| **Constant intensity fatigues players; vary it.** Boghog's shmup guide: enemies should be designed against three outcomes — *optimal kill* (killed immediately), *average kill* (intended), *slow kill* (the safety net for a struggling player) — and unusual/hard-to-read trajectories "may need extra effects like trails" to stay fair. | Designing only the average case leaves a fast player with a boss that does nothing interesting and a slow player with an unbounded fight. The cost is authoring three behaviours per part instead of one. | — | [Boghog's bullet hell shmup 101](https://shmups.wiki/library/Boghog's_bullet_hell_shmup_101) |
| **Damage-sponge is the named failure mode** for bosses whose difficulty is HP rather than pattern; multi-part bosses are explicitly cited (Battle Garegga's Nose Laughin "consists of many destructible parts" and is trivial to rush but fiddly to optimise). | HP tuning is the cheapest knob and the worst one. Part count and HP must be set together, not independently. | — | [Damage-Sponge Boss (TV Tropes)](https://tvtropes.org/pmwiki/pmwiki.php/Main/DamageSpongeBoss), [Battle Garegga/Bosses](https://shmups.wiki/library/Battle_Garegga/Bosses) |

## Answers to the open questions from `1-context.md`

1. **How many turrets?** The shipped range is **1–4 guarded cores** (Gradius) and **6 turrets is
   already cited as excessive** (Star Fox). → **4 turrets**, this project's decision, sitting at
   the top of the Gradius range and below the cited pain point. Four also places symmetrically on
   a square top-down station (one per face), which matters because placement is authored by hand.
2. **Invulnerable vs unhittable core?** Research favours a **visible block**: the Gradius shield
   walls *stop the shot*. The cheapest faithful version here is to keep the core's `HurtBox`
   **active** (so the hit registers and the core flashes/sparks) but **reject the damage** while
   any turret lives. A disabled hurtbox — shots sailing through the core — is the option research
   argues against, and it is also the one that reads as a bug. This is directly testable:
   `received_damage` fires, `Health.current_health` does not move.
3. **PixelLab maximum sprite size?** Answered from the tool schemas, not the web:
   `create_image_pixflux` accepts **16–400 px per side** (total area ≥ 32×32) at **1 generation**;
   `create_image_pro` goes to **512×512 square** but costs **20–40 generations**. A 256×256
   station and 64×64 turrets fit comfortably in the 1-generation tool. Budget is not a constraint
   (1980 generations remaining this cycle), but there is no reason to spend 40 on a first pass.
4. **Wreckage on destroyed turrets?** No source found either way in the reachable pages. Treated
   as an open aesthetic choice; the plan takes the cheap option (swap to a destroyed sprite if one
   is generated, otherwise hide) and does not claim research backing.

## What this rules out

- A single-HP-bar station with cosmetic turrets — that is the damage-sponge failure mode named above.
- 6+ turrets, or turrets with small hitboxes.
- Disabling the core's hurtbox during the armoured phase.
