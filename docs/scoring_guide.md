# How Scoring Works

A guide for players (and designers) on how to rack up high scores in assault
missions. No code in here — this is the rules of the game.

---

## The basics

You earn points by destroying things. Every enemy is worth a base amount:

| Target            | Base value |
|-------------------|-----------:|
| Small asteroid    | 5          |
| Drone             | 10         |
| Big asteroid      | 15         |
| Fighter           | 25         |
| Ram ship          | 35         |
| Sniper            | 60         |
| Bomber            | 80         |
| Gunship           | 200        |
| **Bonus drone**   | **500**    |

But destroying things one at a time is just the floor. The real score comes
from the **combo multiplier** and **wave clear bonuses** stacked on top.

---

## The combo multiplier

Every kill grows your combo by **+0.1**, starting at **x1.0** and capping at
**x8.0**. Every kill awards `base value × current multiplier`, rounded down.

```
Kill #1:  combo x1.0 → fighter (25) × 1.0 = 25 pts
Kill #2:  combo x1.1 → fighter (25) × 1.1 = 27 pts
Kill #3:  combo x1.2 → fighter (25) × 1.2 = 30 pts
   ...
Kill #50: combo x6.0 → gunship (200) × 6.0 = 1,200 pts!
```

The combo is shown in the top-right of the HUD with a thin yellow bar
underneath it. **The bar is your combo timer.**

### What breaks your combo

Three things hurt your combo, each in a different way:

1. **Idle too long** — if you go more than **4 seconds without a kill**, the
   combo snaps all the way back to **x1.0**. Every kill resets that timer.

2. **You take damage** — your combo gets cut in **half**. Going from x6.0 to
   x3.0 in one hit is brutal. Stay clean.

3. **An enemy escapes off-screen alive** — your combo drops by **25%**
   (multiplied by 0.75). Less punishing than taking a hit, but it stacks. Let
   five enemies fly past and a fat x4 combo becomes barely x1.

### Why this matters

Keeping a high combo for the whole mission is the difference between a
1,000-point run and a 12,000-point run. Mastery rewards itself.

---

## Wave clear bonuses

Most enemies spawn in **waves** — groups of 3 to 5 ships arriving at the same
time. If you destroy **every single ship in a wave** before any of them escape,
you get a **wave clear bonus** on top of your normal kill points.

The bigger the wave, the bigger the bonus:

| Wave size | Bonus multiplier |
|----------:|------------------|
| 3 enemies | sum × 2.5        |
| 4 enemies | sum × 3.0        |
| 5 enemies | sum × 3.5        |

**Example:** a wave of 5 fighters (5 × 25 = 125 base) → wave clear bonus =
**437 pts**. That's almost double what the kills themselves were worth.

**Important:**
- Even one enemy escaping off-screen **cancels** the bonus for that wave —
  the kills still count, but the bonus is gone.
- Bonus drones (gold targets, see below) **do not** count as part of a wave.
  Letting one fly past doesn't ruin your wave clear.

---

## Bonus drones

Sometimes a **gold-tinted drone** streaks across the screen at high speed. It
doesn't shoot, doesn't ram you, and takes only **one bullet** to destroy.

Kill it for **500 points** × your current combo. That's potentially **4,000
pts** if your combo is maxed out.

They appear:
- Roughly once per non-asteroid section in Level 1.
- They cross horizontally, fast — you have about 3 seconds before they're gone.
- Missing one doesn't break your combo and doesn't ruin a wave clear. The
  reward is entirely upside.

---

## Skill challenges

Twice in Level 1, the game throws a short **skill challenge** at you — a
window where survival without damage is rewarded:

| Challenge          | When                              | Clean bonus | Survived (took damage) |
|--------------------|-----------------------------------|------------:|-----------------------:|
| Asteroid corridor  | Deep space, ~10s in               | 500         | 150                    |
| Bullet weave       | Planet approach, ~70s in          | 700         | 200                    |

The bonus is applied as long as you're alive at the end of the window. Coming
out **damage-free** gets the full payout AND nudges your combo up. Take a hit
and you still get the partial bonus, but no combo boost.

---

## Survival ticks

Quiet moments still pay. Every **15 seconds of damage-free play**, you earn
**+50 pts**. The timer resets the moment you take damage.

It's a small per-tick number, but it adds up over a 4-minute mission — and
it's pure reward for not being lazy with dodging.

---

## Asteroids split — and the shards score too

A big asteroid (15 pts) breaks into **2–4 small asteroid shards** when
destroyed. The shards:

- Travel in the **same direction** as the big asteroid was moving, just
  **slower** (about half speed), with a slight cone spread.
- Each shard is worth **5 pts** when destroyed, multiplied by your combo
  just like any other kill.
- The shards do **not** belong to the original asteroid wave, so missing one
  doesn't blow your wave-clear bonus.

So destroying a big asteroid is actually worth its 15 base points + 10–20
extra from the shards if you clean them up. Aggressive players go after every
shard for the combo growth.

---

## Star ratings

At the end of a mission, your total score becomes a **star rating** shown in
the mission select menu:

| Stars | Earned by                |
|:-----:|--------------------------|
| ★     | Completing the mission (any score) |
| ★★    | Hitting the 2★ score threshold     |
| ★★★   | Hitting the 3★ score threshold     |

**Level 1 thresholds:** 2★ = **6,000 pts**, 3★ = **11,000 pts**.

Your **highest score ever** on a mission is what counts — replaying for a
better star count keeps your best result. You never lose progress.

---

## Unlocking content with score

Some missions are locked behind **score requirements** on previous missions.
For example:

> **Edelia's Moon Base (Level 3)** requires
> - completing Level 1 (mission progression), **AND**
> - earning **11,000+** (3★) on Level 1

Both conditions must be met. So a high-score run on Level 1 is the only way
to crack open the moon mission. Other missions in the game work the same way
— check the mission info panel for any score requirements.

---

## Tips for hunting high scores

1. **Don't let anything escape.** It's not just about wave clears — every
   escape chips at your combo. A sloppy x6 becomes a wasted x2 fast.

2. **Group your kills tight.** The faster you string kills together, the
   longer the combo decay timer stays full. Aim for two-second clears.

3. **Always finish the wave, even after a mistake.** Took damage and your
   combo dropped? The wave clear bonus is still on the table — it's flat
   points, no multiplier needed.

4. **Bonus drones are non-negotiable.** A maxed-combo bonus drone kill is
   worth more than any other single action in the mission.

5. **Skill challenges = free combo growth.** Clean clears not only give a
   big chunk of points, they push your combo up — perfect for setting up the
   next wave clear.

6. **Big asteroids are score plays.** Hit them, clean up the shards, ride
   the combo into the next wave.

7. **Survival ticks are free.** If you're already not getting hit, you're
   already getting paid. Don't change anything — just keep doing it.

---

## What the HUD tells you

- **Top-right, big number** — your total score, tweens up smoothly so you
  see every chunk land.
- **Below it, "xN.N"** — your current combo. Hidden when it's x1.0.
- **Thin yellow bar under the combo** — the decay timer. Empty = combo about
  to reset. Full = you just got a kill, you have ~4 seconds.
- **Floating "+N" labels at kill sites** — every event has its own popup:
  - White `+N` — regular kill
  - Gold `WAVE! +N` — wave clear bonus
  - Gold `BONUS +N` — bonus drone
  - Green `SAFE +N` — survival tick
  - Cyan `PERFECT! +N` — clean skill challenge
  - Orange `SURVIVED +N` — partial skill challenge

---

## The end-of-mission debrief

When you finish a mission, after the briefing dialog, you see a **debrief
screen**:

1. Score counter ticks up dramatically from zero to your final total.
2. Breakdown panel fades in line by line:
   - Kills
   - Wave bonuses
   - Bonus targets (gold drones)
   - Skill bonuses
   - Survival ticks
3. Stars pop in from left to right — ★ if earned, ☆ if not.
4. Press any key to continue.

That's your scorecard. Beat it next time.
