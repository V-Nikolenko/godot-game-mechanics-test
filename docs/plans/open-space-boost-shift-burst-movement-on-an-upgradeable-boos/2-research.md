# Research — how shipped games solve a metered burst-movement verb

Epic: `open-space-boost-shift-burst-movement-on-an-upgradeable-boos`. Stage: **RESEARCH**,
2026-09-14. Companion to [`1-context.md`](./1-context.md), which covers what is already in this
codebase and is not repeated here.

**Sourcing note.** Three pages needed `scripts/fetch-page.sh` after WebFetch returned 403/402
(`noisypixel.net`, `ultrakill.fandom.com`, `ultrakill.wiki.gg`) — all three were recovered in full
through the reader proxy. Two sources were **not** recovered and are marked as such in the table:
the TV Tropes *Jet Lancer* page (403 direct **and** 403 through the proxy) and a Quod Soler article
on dash velocity (429 direct, empty body through the proxy) where only the search-index snippet is
available. Nothing has been invented, and no number below is attached to a page that was not read
except where the row says so explicitly.

Finding 5 of the sibling epic's
[`../open-space-mouse-aiming-inertial-turn-to-cursor-with-a-contr/2-research.md`](../open-space-mouse-aiming-inertial-turn-to-cursor-with-a-contr/2-research.md)
already establishes frame-rate-independent exponential damping (`1 - exp(-λ·dt)`, half-life
0.1–0.2 s for a player vehicle, Rory Driscoll / Freya Holmér). It is **not** repeated here; it
applies to this epic too and is cross-referenced where relevant.

---

## Findings

| Finding | Tradeoff | Typical values | Source |
|---|---|---|---|
| **1. ULTRAKILL — the closest shipped analogue to the whole ask — runs its Shift dash on discrete stamina, and the dash *always* resets momentum.** "Dashing is an action that performs a quick burst of speed in any given direction at the cost of 1 Stamina … performed using its corresponding key (**Left Shift by default**)". "The player has a maximum of **3 stamina**, indicated by the player HUD." "If the player attempts to perform any of these actions without the minimum stamina necessary, **they fail**." And, decisively for this epic: "**Dashing also completely resets player momentum when performed**, making it useful for recovering from knockback and stalling freefalls." | This is the *simple* rule — no angle threshold, no branch. Every dash kills what you had and re-aims you, so the 180° flip the idea asks for is just the interesting case of one uniform behaviour, and the player never has to work out which of two things they got. The cost is that boosting while already flying straight and fast can **slow you down** — exactly the surprise `_trigger_flip_boost`'s `boost_redirect_speed = 200` produces today against a 420 cap. The fix is to set the post-boost speed *above* cruise, not below it, so "reset" always reads as "re-aim at speed". | Max 3 stamina; 1 per dash; regen **0.7/s on Standard and higher** (1.05 Lenient, 1.4 Harmless) → one dash per ~1.43 s, empty→full in ~4.3 s. **Regen is paused entirely while sliding**, and a successful parry instantly refunds all stamina. | [ULTRAKILL Wiki — Movement](https://ultrakill.wiki.gg/wiki/Movement) (recovered via `fetch-page.sh`; direct 403) |
| **2. The same game keeps dash i-frames *shorter* than the dash.** "When dashing, V1 gets **0.2 s of invincibility (12 frames at 60 FPS)**", while the dash itself travels at 49.5 u/s for longer than that. Separately, taking a hit grants 0.5 s of "mercy invincibility" (30 frames). | Short i-frames make the dash a *dodge you have to time*, not a free pass through a bullet. Long ones make it a panic button and devalue every other defensive option. **This project already sits at the "mercy" end**: `PlayerBase.invincibility_sec = 0.5` matches ULTRAKILL's 0.5 s exactly, while `EngineBoostModule` grants **0.55 s of total immunity** (`damage_reduction = 1.0` for the whole boost) — i.e. today's module is at the generous extreme. A core Shift boost granting the same would make the module redundant on its strongest axis (`1-context.md`, open question 9). | Dash i-frames **0.2 s**; post-hit mercy i-frames **0.5 s**. | [ULTRAKILL Wiki — Invincibility Frames](https://ultrakill.fandom.com/wiki/Invincibility_Frames) (recovered via `fetch-page.sh`; direct 402/403) |
| **3. Jet Lancer — the idea's own stated reference — does *not* use a spend-a-pip meter. Its boost is a held thruster on an overheat gauge, and the gauge is what modules upgrade.** "While flying, you have complete control of your jet propulsion and can turn it on and off with ease." "You also have an **acceleration boost** … **if you use it too much, it can temporarily overheat**, leaving you potentially vulnerable without acceleration **or other moves tied to your boost**." Modules include "**additional coolant for your thrusters**" and extra shields. And on the UI: "you always need to pay attention to your **thruster and special weapon gauge**" — two gauges, read together. | **This contradicts the idea's framing in a way the plan must resolve deliberately.** The ask says "Pressing Shift activates the boost and consumes a dedicated boost meter", which is a discrete spend; the reference game's boost is a *held drain with a punishment state*, and its penalty is deliberately harsh — overheating removes movement **and** everything keyed off the boost. A held drain reproduces Jet Lancer's feel and its tension; a discrete spend is far easier to read, to test and to upgrade legibly. It also matters that the reference upgrades **cooling**, i.e. the *refill*, not the capacity — which is a third answer to `1-context.md`'s open question 4. Note also the corroboration for the UI ask: two combat gauges side by side is what the reference actually ships. | Not published. No durations, drain rates or capacities are stated anywhere reachable. | [Noisy Pixel — *Jet Lancer* review](https://noisypixel.net/jet-lancer-review-switch-pc/) (recovered via `fetch-page.sh`; direct 403) |
| **4. A depleting action meter should fail *soft*, and should pause its regeneration during and just after the action.** The recommendation is a "soft failure state" — on hitting zero the character enters exhaustion and cannot act again until recovery passes a threshold of "roughly **10%**" — rather than a hard per-action refusal, because that "discourages overspending without creating immediate loss conditions". Also: "Pausing stamina regeneration during and briefly after actions creates clearer decision boundaries. Even **millisecond-length pauses** influence perceived pacing." And on representation: integers are recommended over floats because they are "more stable, making it easier to determine precise amounts" across repeated calculation. | The exhaustion threshold buys a readable punish window and stops the meter being spammed at 1% — but it is a *second* state to implement, test and telegraph, and it is exactly where a boost meter starts feeling punitive on a traversal verb the player needs to cross the hub. The regen pause is nearly free and this project already has it: `Overheat._no_shoot_timer` / `_SHOOT_GRACE = 0.5 s` is the identical mechanism, already written and already unit-tested. | Exhaustion recovery threshold **≈10%** of max. Regen pause: any non-zero duration changes perceived pacing. | [Hedberg Games — *Design Thinking: Stamina in Action Games*](https://www.hedberggames.com/blog/design-thinking-stamina-in-action-games) |
| **5. Scope the i-frame window as a sub-range of one normalised dash timer, not as its own clock.** "Drive both the invincibility window and the dash movement from one normalized dash timer, and define the i-frame window as a sub-range of that timer" — the worked example runs i-frames from **0.05 to 0.85** of the dash, deliberately leaving startup and recovery vulnerable. Advance the timer by delta, not by counting frames, "to ensure consistency across different frame rates". The named failure it prevents is i-frames ending before the movement does, which "creates an unfair feel". | One timer means the two can never desync, and the sub-range is a designer dial rather than a second constant to keep in step. The cost is that the dash is genuinely killable at its edges, which reads as unfair if the startup fraction is too large. Directly applicable here: `EngineBoostModule` currently runs i-frames over the *entire* 0.55 s by stashing `damage_reduction`, so it has no startup or recovery vulnerability at all — a deliberate design position the plan can keep or narrow, but should at least name. | i-frames over **0.05 → 0.85** of a normalised dash duration. | [Bugnet — *How to Fix Dash I-Frames Ending Before the Dash Movement Finishes*](https://bugnet.io/blog/how-to-fix-dash-i-frames-ending-before-the-dash-movement-finishes) |
| **6. "Flip and burn" is Asteroids' signature *emergent* skill, not a button — and that is the depth this epic is proposing to spend.** Asteroids is credited as the arcade game that made inertia a mechanic: the ship "doesn't stop when you stop thrusting — it drifts", and "getting a feel for that momentum, learning when to thrust and when to let the ship coast … is the entire skill curve of the game compressed into a single mechanical truth". The emergency brake is described as "rapidly rotating 180 degrees and applying full thrust when moving fast in a dangerous direction". | The idea proposes to make that manoeuvre a single keypress. That is a real accessibility win — `1-context.md` measures the manual version at **~3.0 s** (0.82 s turn + 2.22 s thrust through zero) — but it converts the game's deepest movement skill into a resource you spend, and the meter is then the *only* thing left holding the skill ceiling up. That is a strong argument for the cost being visible and genuinely scarce rather than generous. | — | [RAM Retro Arcade Memories — Asteroids](https://retroarcadememories.wordpress.com/arcade-games-reviews/asteroids/); [Free To Play Puzzles — Asteroids strategies](https://www.freetoplaypuzzles.com/blog/asteroids-game-strategies). **Weakest sourcing in this table** — enthusiast retrospectives, not a postmortem. Cited for the *design observation*, not as authority for any number. |

### Two sources that could not be read

- **TV Tropes, *Jet Lancer*.** 403 direct **and** 403 through `scripts/fetch-page.sh`'s reader
  proxy. Genuinely unreachable from this container. It would likely have carried mechanical
  detail on the boost gauge that finding 3 had to take from a review instead.
- **Quod Soler, *Dashes and Knockbacks with Root Motion Sources*.** 429 direct on two attempts;
  the proxy returned HTTP 200 with an empty body. The search index shows two sentences —
  that a non-additive motion source "overrides movement for its duration, input, friction and
  braking stop mattering, which is what you want for a dash", and a recommendation to use
  "SetVelocity with a zero vector for knockbacks and ClampVelocity at your run speed for dashes,
  so the dash blends back into locomotion". **The page itself was never read, so this is recorded
  as an unverified snippet, not as a finding.** It is Unreal-specific in any case. The underlying
  idea — clamp the boost's speed back to cruise *on exit* rather than clamping it every frame — is
  the obvious answer to `1-context.md`'s risk 1, and the plan should treat it as **this project's
  own judgement call**, supported by the fact that `EngineBoostModule` already does exactly that
  (it eases 1500 → 500 and hands `velocity` back with `engine_boost_active = false`).

---

## What the findings imply for the plan

**1. The simple always-redirect rule has a shipped precedent, and it resolves the epic's hardest
open question.** Finding 1 says ULTRAKILL's dash resets momentum *unconditionally* — no angle
test, no second branch. `1-context.md`'s open question 2 asks whether the boost needs an angle
threshold to decide between "redirect" and "burst"; the evidence says no, and the project's own
`_trigger_flip_boost` already implements the unconditional form. The one change it needs is a
post-boost speed **above** cruise rather than below it, so that boosting while flying straight
accelerates instead of braking.

**2. Discrete charges are better supported than a continuous bar, on three separate grounds.**
Finding 1's shipped precedent is 3 discrete pips on the HUD; finding 4 recommends integers over
floats for stability; and this project's own upgrade precedent —
`ShipProgressionState.permanent_shield_count`, 1→5, with `ShieldIconStrip` drawing one icon per
charge — is already discrete, already persisted and already tested. A discrete meter also makes
the upgrade legible in a way a bar cannot ("+1 boost" vs "the bar is 12% longer"). The counter-
argument is finding 3: the *stated reference game* uses a continuous overheat gauge, and the idea
says "meter". A defensible middle is a continuous internal float rendered as segments.

**3. The regen-pause is free and should be in the first version.** Finding 4 recommends it;
`Overheat._no_shoot_timer` already implements the identical mechanism 30 lines away. Without it,
a held or mashed boost key trickle-charges the meter between activations.

**4. Do not give the core boost full-duration i-frames.** Findings 2 and 5 both point the other
way, and `1-context.md` shows `EngineBoostModule`'s entire value proposition as an *equippable*
ability rests on its 0.55 s of total immunity plus 45 contact damage. A metered, always-available
boost with the same immunity makes the module pointless. Either the core boost has **no** i-frames
(cleanest, and the differentiation writes itself), or a short window in the 0.05–0.85 sub-range
shape of finding 5 — never the module's blanket `damage_reduction = 1.0`.

**5. The epic's UI ask is corroborated by the reference game** (finding 3: "your thruster and
special weapon gauge"), but `1-context.md` shows the open-space overheat meter is a **world-space
bar under the ship**, not a HUD control. "Next to the overheat meter" means at roughly
`(0, 26)` below the hull, as a sibling of the existing `OverheatBar`.

---

## Starting numbers

Everything here marked *(judgement)* is derived from this project's own constants and the findings
above, **not** from a source that states it. None of it can be validated headlessly — a human has
to fly the hub. Every value should be an `@export` on a scene node so the fly-test is an inspector
change and not a code change.

| Parameter | Proposed start | Where it comes from |
|---|---|---|
| Boost charges at base | **2** *(judgement)* | Finding 1 ships 3 for a game with far more movement verbs. Two leaves the upgrade room the idea asks for and makes the first upgrade feel large. |
| Boost charges at cap | **5** *(judgement)* | Mirrors `ShipProgressionState.MAX_SHIELDS = 5` exactly, so the two upgrade tracks read as one system. |
| Recharge rate | **0.7 charges/s** | Finding 1's Standard-difficulty value, adopted directly. One boost per ~1.43 s; 2→full in ~2.9 s, 5→full in ~7.1 s. |
| Recharge delay after a boost | **0.5 s** | Finding 4's regen pause, at the value `Overheat._SHOOT_GRACE` already uses, so there is one such constant in the project rather than two. |
| Post-boost speed | **~600 px/s** *(judgement)* | Must exceed `max_speed = 420` or the redirect reads as a brake (finding 1's tradeoff, and today's `boost_redirect_speed = 200` bug). 600 is ~1.4× cruise and well under `EngineBoostModule`'s 1500, preserving the module's "heavier ability" identity. |
| Boost window | **0.25–0.35 s** *(judgement)* | Today's `boost_duration_sec = 0.3` sits in this band and is already the flip-boost's visual window. Kept so the cyan flame still reads as a discrete event. |
| Speed cap during the window | **raised to the post-boost speed, then decays back to `max_speed`** *(judgement)* | `1-context.md` risk 1. Clamp on exit, not per frame. |
| Core-boost i-frames | **none in v1** *(judgement, from findings 2 and 5)* | Keeps `EngineBoostModule` meaningfully different. `PlayerBase.invincibility_sec = 0.5` still covers the post-hit case. |
| Upgrade axis | **capacity (+1 charge)** *(judgement)* | The only axis a player can see on the meter, and the one the shield precedent supports. Finding 3 notes the reference game upgrades *cooling* instead; that is the fallback if capacity tests flat. |
| Pickup | **one `ShipBoostUpPickup` on the hub bench row `y = -212`** | Matches `ShipShieldUpPickup` at `x = 413`; `1-context.md` lists the free x positions. Required by the "unlockable content needs a source in the world" convention. |

---

## Questions research could not settle

- **Jet Lancer's actual boost numbers** — drain rate, overheat threshold, cooldown, and what the
  coolant modules change — are not published anywhere reachable, and the one page most likely to
  carry them (TV Tropes) is hard-403 from this container. Finding 3 establishes the *shape* of the
  mechanic and nothing more. No figure is offered.
- **Whether a continuous gauge or discrete charges is better for *this* game.** The evidence is
  genuinely split (finding 1 vs finding 3) and both map onto existing project components
  (`Shield` vs `Overheat`). This is a design call for the plan stage, not a research finding.
- **Whether the strict reading of "move the existing thrust/braking behavior into the boost
  system" is playable at all.** No source addresses removing continuous thrust from a free-flight
  hub the player must traverse to reach mission triggers. `1-context.md` risk 4 and risk 5 (the
  150 px/s planet-docking gate) are the concrete hazards; only a fly-test can answer it.
- **No number in the "Starting numbers" table above has been play-tested.** The gate can prove the
  meter clamps, persists, refills and gates the verb; it cannot say whether the ship feels like
  Jet Lancer.
