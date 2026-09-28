# Enemy Rework — Open Space + Assault

## Purpose

This document proposes a full enemy redesign for the current enemy roster.

The current implementation was originally shaped around Assault's vertical autoscroller: screen edges are meaningful, many enemies move on authored paths, several AIs assume the player is below them, and enemy projectiles use fixed arena bounds. Open Space removes those assumptions: the player can thrust, reverse, boost, turn, circle, retreat, and approach from any direction. The redesign should therefore make **enemy intent and movement behavior independent of the camera** and give every enemy a strong identity in both gameplay modes.

The goal is not to make every enemy more complicated for the sake of complexity. The goal is to make enemies feel like **different machines with different combat jobs** rather than the same ship using a different path and fire rate.

The existing audit confirms that the project already has useful building blocks to retain: health/hurtbox/hitbox plumbing, attack patterns, bullet pooling, config resources, damage-type filtering, the Drone Interceptor's full-2D orbit/dash behavior, and the Space Station's multi-part boss structure. fileciteturn0file0L199-L257 fileciteturn0file0L783-L858 fileciteturn0file0L1375-L1435

---

# 1. New enemy design pillars

## 1.1 Every enemy needs a readable combat verb

Each enemy should answer one question immediately:

- **Swarm:** "Can I break formation and survive?"
- **Flanker:** "Can I keep an angle on the player's blind side?"
- **Striker:** "Can I evade its attack run?"
- **Bomber:** "Where will the battlefield become dangerous next?"
- **Sniper:** "Where is it hiding, and can I punish its firing position?"
- **Missile ship:** "Can I survive the salvo and get behind it?"
- **Ram ship:** "How do I break its armor before it reaches me?"
- **Support ship:** "Can I kill the support unit before the formation becomes overwhelming?"
- **Carrier:** "Can I dismantle the machine while dealing with what it launches?"
- **Hacker:** "Can I stop it from turning my own weapons against me?"
- **Controller / Turret:** "Can I break the structure before it makes the space around it unsafe?"

A new enemy should not exist solely because it has a different HP/speed/damage number.

## 1.2 Movement is part of the weapon

In Open Space, an enemy's movement should be as recognizable as its gun.

Examples:

- A sniper does not simply move backward. It deliberately leaves the player's camera, creates distance, chooses a new offset firing position, and only then enters a stationary firing state. While aiming and taking the shot it should **not move**; this gives the player a real opportunity to close the distance and pressure it. After firing, it breaks the firing position and tries to create distance again rather than immediately returning to the player.
- A swarm drone does not fly in a sine wave. It uses a curved orbit, breaks formation, crosses behind the player, and recombines.
- A bomber does not cross left-to-right. It establishes a future danger zone, turns away, and lays ordnance along a predicted player path.
- A carrier does not chase the player. It controls space around itself while its escorts do the chasing.
- A Razor Drone can look almost idle when no combat is active: it drifts around an anchor point, makes asymmetric arcs, occasionally brakes or changes orbit direction, and only snaps into a combat pattern after acquiring the player.

## 1.3 Open Space is the source of truth for AI

The AI should be authored as a **2D world-space behavior** first.

Assault should then use the same AI but constrain or bias it through a movement envelope:

`Open Space AI → 2D movement intent → Assault movement constraint → actual movement`

Do not implement separate enemy logic for Open Space and Assault unless the attack fundamentally requires different rules.

---

# 2. Roster redesign

The current roster contains Bomber, Bonus Drone, Drone Interceptor, Kamikaze Drone, Interceptor, Light Assault Ship, Gunship, Ram Ship, Sniper Enemy, Space Station, and the much simpler Open Space Patrol Drone. Several of these currently overlap heavily or are built around Assault-only movement assumptions. fileciteturn0file0L13-L27

I would reduce the number of "basic" concepts while increasing the number of behaviors.

| New role | Current source | Size target | Primary behavior |
|---|---|---:|---|
| Swarm Drone | Kamikaze Drone + Patrol Drone | 24–36 px | Curved swarm, flank, coordinated ram |
| Razor Drone | Drone Interceptor | 40–56 px | Orbit, feint, predictive dash |
| Fighter | Light Assault Ship | 56–72 px | Strafing, turn-backs, aimed fire |
| Gatling Interceptor | Interceptor | 56–72 px | High-volume suppression, lateral passes |
| Bomber | Bomber | 88–120 px | Mine/bomb placement and escape arcs |
| Sniper | Sniper Enemy | 48–64 px | Relocate beyond visibility, lock, fire, relocate |
| Ram Corvette | Ram Ship | 72–96 px | Armor break → vulnerable charge |
| Missile Corvette | New | 80–112 px | Rocket volleys, wide repositioning |
| Support / Shield Ship | New | 72–104 px | Repairs, shields, targeting support |
| Mine Layer / Controller | New | 80–112 px | Area shaping, mine corridors |
| Heavy Gunship | Gunship | 112–160 px | Mobile fortress / broadside fire |
| Carrier | New / Space Station lineage | 192–320 px | Multi-part hull + launched drones |
| Dreadnought | New boss | 320–480 px | Multi-system boss, turrets + batteries |
| Space Fortress | Space Station rework | 320–512 px | Stationary/mobile objective boss |

**Bonus Drone** should remain a dedicated **Assault interaction**. It is still a fast, fragile, high-value target whose purpose is to reward rapid tracking and accurate destruction before it escapes. It can also be reused outside Assault as a **salvage drone / emergency cache carrier**, but that Open Space version should be treated as a world event/reward object rather than a normal combat enemy.

The existing Open Space Patrol Drone should also disappear as a special implementation. Its current behavior is just constant straight-line drift with minimal enemy integration, so it is better replaced by the same Swarm Drone architecture used everywhere else. fileciteturn0file0L364-L395

---

# 3. Enemy architecture rework

## 3.1 Replace camera-driven movement with behavior-driven movement

The current `EnemyPathMover` disables an enemy's own physics/AI and directly writes position. It also depends on `ArenaCamera.WORLD_SCALE`, screen-space paths, and camera-relative despawning. That works for Assault but is the wrong abstraction for Open Space. fileciteturn0file0L112-L150

Create a new shared layer:

```text
EnemyEntity
 ├── EnemyBrain
 │    ├── perception
 │    ├── intent
 │    └── behavior state
 ├── MovementController
 │    ├── max_speed
 │    ├── acceleration
 │    ├── turn_rate
 │    ├── braking
 │    └── movement constraints
 ├── AttackController
 │    └── AttackPattern
 ├── DefenseController
 │    ├── armor
 │    ├── shield
 │    └── weak points
 └── Presentation
      ├── sprite
      ├── thruster
      ├── telegraph
      └── damage state
```

The important separation is:

**Brain decides what the enemy wants to do.**

**MovementController decides how the ship reaches that intention.**

**AttackController decides how the ship weaponizes that intention.**

This eliminates the current situation where `.move()` can silently disable an enemy's actual AI. The audit explicitly identifies that behavior as a recurring source of contradictions for Bomber, Kamikaze Drone, Ram Ship, Gunship, and others. fileciteturn0file0L32-L49

## 3.2 Replace `EnemyPathMover` with movement primitives

Instead of authoring a complete position path, give the AI primitives such as:

- `seek(target_position)`
- `arrive(target_position)`
- `orbit(target, radius, angular_speed)`
- `intercept(target, prediction_time)`
- `evade(target_velocity)`
- `strafe(target, offset)`
- `lead_target(target)`
- `break_contact(direction)`
- `regroup(anchor)`
- `formation_slot(anchor, slot)`
- `hold_position(position, tolerance)`
- `retreat_from(target)`
- `spiral(target)`
- `corkscrew(target)`
- `drift(direction)`
- `boost(direction, duration)`

The exact implementation can still be deterministic/configurable. The important change is that the enemy is no longer told "move to this screen coordinate"; it is told "maintain a 400 px orbit around the player while drifting clockwise and keep firing when the player enters your attack cone."

## 3.2.5 Shared hazard perception

All combat-capable enemies should have optional access to a lightweight hazard field query:

```text
HazardInfo
 ├── position
 ├── radius
 ├── pull_force
 ├── damage_per_second
 ├── movement_penalty
 ├── disables_abilities
 └── line_of_sight_blocker
```

This lets the same AI reason about gravity wells, mines, jammers, wreckage, laser walls, and other encounter structures. The enemy does not need a bespoke script for every hazard.

A key rule: **hazards affect enemies according to their physical rules too**. If the player can be dragged into a gravity well, an enemy that enters the field should also be dragged unless its movement profile explicitly provides resistance.

## 3.3 Open Space persistence rules

Do not use screen visibility as an enemy lifetime rule in Open Space.

Instead use:

- encounter ownership
- maximum engagement distance from player
- maximum distance from encounter anchor
- leash distance
- mission/sector despawn rules
- tactical retreat and re-entry

For example:

```text
spawn
  ↓
engage player
  ↓
lose target / player boosts away
  ↓
search for player
  ↓
reacquire or return to encounter anchor
  ↓
despawn only after encounter cleanup
```

This directly avoids the current camera-relative culling problem identified for the existing path mover and enemy bullets. fileciteturn0file0L468-L531

---

# 4. Core AI system: behavior states + tactical intent

Every enemy should expose a small state machine, but the states should be **combat states**, not camera states.

Recommended shared states:

```text
SPAWN
SEARCH
APPROACH
POSITION
ATTACK
EVADE
REPOSITION
DISENGAGE
PANIC / CRITICAL
DESTROYED
```

A specific enemy can use only 3–5 of these.

For example, the sniper can use:

```text
APPROACH → HIDE → AIM → FIRE → REPOSITION → HIDE
```

while a swarm drone uses:

```text
APPROACH → FORMATION → FLANK → RAM → BREAKAWAY
```

and a carrier uses:

```text
ANCHOR → SCREEN → LAUNCH → BROADSIDE → REPAIR → ESCAPE
```

This makes behavior easier to reason about while still allowing complex movement.

---

# 5. Detailed enemy redesigns

## 5.1 Swarm Drone

### Replace

Kamikaze Drone + Open Space Patrol Drone.

The current Kamikaze Drone is a useful idea, but its actual heading is locked once at spawn and its Assault implementation is often overridden by path movement. In free flight, a single straight-line ram is too easy to sidestep. fileciteturn0file0L865-L926

### Identity

Small disposable autonomous craft that become dangerous through coordination.

### Size

24–36 px.

### Movement

Use lightweight swarm logic rather than expensive full boids:

- separation from nearby drones
- alignment toward squad velocity
- cohesion toward squad anchor
- player avoidance until attack commitment
- lateral offset from player's current velocity

Each drone selects a different phase offset so ten drones do not trace identical curves.

Example behavior:

```text
          drone A
             ↘
              ↘
player →       ●
              ↗
          drone B
```

Instead of both attacking head-on, one drone passes left and one passes right. A third stays behind and waits for the player's movement direction to become predictable.

### Attack

No gun.

Attack is a **coordinated ram**:

1. Drone enters a wide orbit.
2. It predicts player position 0.4–0.8 s ahead.
3. It chooses a side of the player that is not already occupied.
4. It performs a short acceleration burst.
5. On near miss, it does not immediately die. It overshoots and curves away.
6. It can perform one second attack pass.

This is much more interesting than "fly toward the player's current position once."

### Group behavior

If 3–6 drones are alive:

- one becomes the **lead attacker**
- two choose left/right flank slots
- remaining drones orbit the rear
- if the lead attacker dies, another takes its place

This also creates the desired "fly together if they can" behavior without requiring every individual drone to be scripted as a formation path.

### Assault adaptation

The same AI runs inside a vertical movement envelope. It cannot leave the allowed corridor, but it can still:

- curve left/right
- circle partially
- cross above/below the player inside the available space
- break formation
- re-enter from the side

The result should feel like a swarm inside a 2D lane rather than a row of sine-wave paths.

---

## 5.2 Razor Drone

### Source

Drone Interceptor.

The current Drone Interceptor is the strongest existing candidate for Open Space because its orbit and predictive dash are already genuinely 2D. fileciteturn0file0L783-L858

### Size

40–56 px.

### Movement

Keep the core idea but make it substantially richer:

```text
APPROACH
  ↓
ORBIT
  ↓
FEINT
 ↙  ↘
left  right
  ↓
DASH
  ↓
OVERSHOOT
  ↓
RETURN
```

The enemy should occasionally reverse its orbit direction before dashing. This prevents players from learning "it always attacks clockwise."

### New mechanic: fake dash

At the end of the orbit, it points directly at the player but does not fire its real dash. It brakes, slides past, then attacks from the opposite side.

The actual dash gets a stronger visual/audio cue than the fake.

### Attack

Contact damage plus a small **pulse weapon** fired immediately after a missed dash.

This gives the player a reason not to assume "I dodged it, so it is harmless now."

### Assault adaptation

Keep the orbit but constrain its center to a band around the player. In Assault, the drone can attack diagonally from a side lane rather than always moving directly toward the player.

---

## 5.3 Fighter

### Source

Light Assault Ship.

The current fighter is the baseline shooter and is heavily reused in formations. This is the right role, but the movement should stop being path-driven. fileciteturn0file0L1018-L1103

### Size

56–72 px.

### Movement identity: attack run

The fighter behaves like a pilot rather than a projectile:

```text
approach
   ↓
pass left of player
   ↓
fire burst
   ↓
wide turn
   ↓
reposition
   ↓
second pass
```

Give it acceleration and turn radius so the player can anticipate the curve but must decide whether to pursue it or stay focused on other enemies.

### Weapons

Two modes:

**Aimed burst:** 3–5 bullets toward predicted player position.

**Forward burst:** 5–7 fast bullets along its nose direction.

A fighter should switch between modes based on distance rather than being a static spawn property.

### Group behavior

Three fighters should naturally create a pincer:

```text
       F
      ↘
        PLAYER
      ↗
       F
```

while a fourth performs a frontal pass.

### Assault adaptation

The fighters remain in the vertical corridor but use lateral attack runs and curved exits. Formations should be a starting arrangement, not the complete behavior.

---

## 5.4 Gatling Interceptor

### Source

Current Interceptor.

The current Interceptor already has a reusable high-rate attack system, but the documentation and actual `GatlingAttackPattern` behavior disagree about whether it shoots forward or directly at the player. The redesign should remove that ambiguity. fileciteturn0file0L934-L1011

### Size

56–72 px.

### Identity

A suppression unit, not a chase unit.

### Movement

The interceptor wants to maintain **side-on range** from the player.

```text
player velocity →

          I → → →
          ↘
           ● PLAYER
          ↗
          I ← ← ←
```

It repeatedly moves through the player's flank, fires a stream, brakes, swings around, and attacks from the other side.

### Attack

Replace constant 11 shots/s with short **pressure windows**:

- spin-up 0.25 s
- 8–12 round stream
- 0.4 s cooldown
- reposition
- repeat

This gives visible attack rhythm and prevents the enemy from becoming background bullet noise.

### New weapon effect

Some variants use **convergence fire**: two nearby interceptors aim from slightly different angles so their streams overlap around the player's likely future position.

### Assault adaptation

The same flank logic works. The side of the arena becomes the temporary flank reference rather than the full world.

---

## 5.5 Bomber

### Source

Current Bomber.

Its existing identity is useful, but its current bomb falls downward and assumes a player's lane. The audit also found that its self-driven horizontal behavior is contradicted by the live wave setup. fileciteturn0file0L626-L704

### Size

88–120 px.

### Movement

A bomber should deliberately approach at an angle, establish a bombing line, then escape.

```text
                  escape
                     ↗
                    /
                   /
            B ----/ 
             \    \
              \    \   mine line
               \    \
                ● PLAYER
```

### Weapon redesign: ordnance dispenser

Give it 3 bomb types, selected by behavior:

**Gravity Bomb**

Slow projectile that keeps traveling in the current direction and detonates after a short proximity warning.

**Mine Cluster**

Drops 3–5 stationary mines in an arc behind the bomber.

**Pursuit Bomb**

Slowly rotates toward the player's future position before its final acceleration.

The player should be able to shoot bombs before detonation.

### Smart bombing

The bomber predicts where the player is heading, not where the player is.

If the player is boosting right, the bomber drops a mine chain ahead of the player's current trajectory.

### Assault adaptation

Keep the exact same prediction logic but clamp bomb placement to the assault corridor. The bomber can create temporary walls, diagonals, and pockets instead of repeatedly dropping bombs straight down.

---

## 5.6 Sniper

### Source

Current Sniper Enemy.

The existing AIM → LOCK → FIRE loop is already a good foundation. The important change is to make **relocation and distance management** the core behavior rather than an externally authored path exit. fileciteturn0file0L1285-L1374

### Size

48–64 px.

### Movement identity: disappear, establish distance, then commit to a firing position

The sniper should feel like a ship that is deliberately trying to maintain a safe firing geometry, not a ship that simply flies off-screen and comes back on a timer.

```text
PLAYER
  ●
   \
    \
     \\   sniper creates distance
      \\        ↗
       \\      S   hidden / repositioning
        \\          ↓
         \\     S = stationary firing point
                     │
                     │ aim / telegraph
                     │
                     ▼
                   FIRE
                     │
                     ▼
               disengage + distance
```

Cycle:

1. Enter encounter and choose a preferred engagement distance.
2. If the player is too close, **create distance first**; leaving the camera is a useful tactic, not a hard requirement.
3. Once enough distance is established, move laterally/diagonally to an unexpected firing offset.
4. Become **stationary** at the firing point. This stationary state is intentional: the player can use the telegraph window to close the distance and attack the sniper.
5. Telegraph the rail shot and lock the predicted player position.
6. Fire.
7. Immediately leave the firing point and attempt to **create distance from the player again**.
8. Choose a new firing position rather than returning to the same offset.

### Important rule

The sniper should never be forced into a "shoot → return to player" loop. Its post-shot behavior is to **break contact and re-establish a safe distance**, because a mobile Open Space player can punish a stationary sniper after the shot.

The player should be able to recognize a tactical window:

```text
MOVING / REPOSITIONING  = sniper is hard to hit
STATIONARY + TELEGRAPH   = sniper is vulnerable
POST-SHOT DISENGAGE       = sniper is escaping again
```

### Firing position selection

Prefer varied positions relative to the player's current velocity and facing:

- 60° left
- 90° right
- behind the player
- far above/below
- diagonal

Do not make it appear at the same relative offset repeatedly. Prefer a position that also creates a useful line of sight rather than blindly picking a random point.

### Weapon

Keep the high-speed sniper projectile, but redesign it as a **rail shot**:

- very low shot width
- very high speed
- high damage
- one clear charge line
- shot leaves a short residual trail

Optional advanced variant: the sniper emits a false/decoy telegraph before the real line, but only on higher difficulty.

### Assault adaptation

Assault can preserve the same state logic by replacing unlimited world-space distance with a tactical off-screen band. The sniper can leave the visible corridor, create a firing offset, become stationary for the telegraph/shot, then break away and re-enter from a different angle. It should **not** instantly pop back into the arena after firing.

## 5.7 Ram Corvette

### Source

Ram Ship.

The current armor gimmick is worth keeping, but its straight-down charge and Assault-specific bullet immunity should be replaced with a proper combat mechanic. The audit explicitly notes that its current hurtbox excludes the player's bullet layer until armor is stripped. fileciteturn0file0L1197-L1284

### Size

72–96 px.

### Defense

Three armor plates around the hull:

```text
     [armor]
        ↑
 [armor] ● [armor]
```

Each plate can be damaged independently by rockets or high-impact weapons.

After all plates break:

- main hull becomes vulnerable
- top speed increases
- contact damage increases slightly
- ship becomes more evasive

### Attack

**Charge telegraph:**

1. Ram ship rotates onto a predicted intercept course.
2. Engines charge for 0.5–0.8 s.
3. Armor glows.
4. Ship boosts through the player's projected position.
5. Overshoots.
6. Performs a wide turn.

It should not instantly die if it misses.

### Rocket interaction

This is the perfect enemy to introduce stronger enemy rockets because the player has to choose:

- use a rocket to strip an armor plate
- use primary fire to damage the exposed hull
- continue dodging the charge

### Assault adaptation

The charge becomes a diagonal corridor attack instead of an unconditional vertical dive.

---

# 6. New enemies and combat structures

## 6.1 Missile Corvette

### Role

Mid-weight ranged enemy that controls space with rockets.

### Size

80–112 px.

### Movement

Maintains medium distance and uses broad arcs instead of closing directly.

### Weapon: enemy rocket

A rocket should behave differently from a bullet:

- visible launch
- acceleration phase
- mild steering
- warning audio
- possible flare/decoy reaction
- explosion radius

Suggested pattern:

```text
       rocket
         ↘
          ↘
PLAYER ●   ← predicted intercept
```

The rocket should prefer the player's **future path**, not the current position.

### Counterplay

Player can:

- outrun it
- turn sharply
- destroy it
- cause it to collide with environment/other enemies
- bait it into a carrier escort

### Assault adaptation

Rockets remain fully functional but are limited by the corridor. This gives Assault a new threat that is not just another bullet stream.

---

## 6.2 Shield / Repair Ship

### Role

Support enemy that makes formations more dangerous without being a direct damage dealer.

### Size

72–104 px.

### Movement

Stays behind the highest-threat enemy.

Uses a soft formation anchor rather than direct player pursuit.

### Abilities

**Repair beam:** restores a small amount of HP to a nearby ally.

**Shield projector:** creates a directional shield arc around another enemy.

**Emergency escort:** if the supported target reaches low HP, the support ship pulls the target away and becomes the closer target itself.

### Destruction mechanic

Support ship should have low HP but high evasiveness.

Killing it first makes the rest of the formation much easier.

### Assault adaptation

Its support range is clamped so it cannot hide permanently above the camera.

---

## 6.3 Mine Layer

### Role

Battlefield-control enemy.

### Size

80–112 px.

### Movement

Flies sideways across the encounter, leaving mines in a curved or zig-zagging trail.

### Mines

Mines should have distinct behaviors:

- proximity mine
- slow homing mine
- chain mine that explodes near another mine
- pulse mine that briefly reduces boost efficiency

Do not fill the screen immediately. The enemy should gradually create unsafe regions.

### Open Space behavior

The player can leave the mine field entirely, but returning through the same area later is dangerous.

This creates genuine spatial memory in Open Space.

---

## 6.4 Hacker Frigate

### Role

A specialist ship that attacks the player's automated weapons rather than the hull directly. It is a high-priority disruption target.

### Size

80–120 px.

### Movement

The Hacker Frigate avoids direct confrontation. It maintains medium/long range, drifts through asymmetric arcs, and tries to keep line of sight while staying outside the player's easiest attack angle.

### Core ability: weapon hijack

The ship can temporarily take control of **automated player weapons**, especially rockets/missiles that normally acquire targets automatically. The effect can target both newly launched ordnance and eligible rockets already in flight, so a projectile can visibly rotate away from its original target and turn back toward the player.

```text
Player launches rocket
        ↓
Hacker pulse attaches
        ↓
Rocket target is replaced
        ↓
Rocket rotates / retargets
        ↓
Rocket attacks player instead
```

The hijack should be clearly telegraphed. A hacked rocket can change its visual accent, emit a warning sound, or receive a distinct targeting indicator so the player understands why their projectile turned around.

### Scope

The default version should affect **automated/seeking weapons**, not the player's direct-fire primary weapon. More advanced Hacker variants can briefly disrupt a skill/ability system, but the base enemy should have one clean, understandable trick.

### Counterplay

- Destroy the Hacker Frigate.
- Avoid launching automated weapons while the hacker is in its active pulse.
- Force the hacker behind cover or other enemies.
- Lure the hijacked projectile into another enemy or hazard where appropriate.

### Assault adaptation

The same logic works in a corridor. The hacker must remain inside a bounded lateral/vertical region, but the weapon hijack behavior remains unchanged.

---

## 6.5 Stationary Defense Turret

### Role

A persistent defensive structure placed around stations, wrecks, objectives, mining sites, or narrow routes. It is an enemy even though it does not move.

### Size

48–96 px for a standard turret; larger 128–192 px variants can act as heavy emplacements.

### Movement

None. The turret rotates its weapon mount and uses predictive targeting.

### Weapon variants

- burst cannon
- sweeping beam
- rocket battery
- short-range pulse ring
- sniper lance

### Defensive behavior

Turrets should often be positioned so that the player cannot simply park in one safe direction. Groups of 2–4 can create overlapping fire lanes.

### Destruction

Turrets can be:

- standalone enemies
- mounted on larger ships/stations
- protected by a shield generator
- connected to a jamming or power structure

Destroying the power source can disable the entire turret group.

### Assault adaptation

Turrets become static hazards in the scrolling corridor and can be mounted on large boss structures or encounter geometry.

---

## 6.6 Jamming Structure

### Role

A stationary battlefield structure that suppresses **special abilities / skills** in a radius. It should not normally disable basic movement or primary fire; its purpose is to temporarily change what tools the player can use.

### Behavior

The structure broadcasts a visible interference field. Enemies can deliberately fight around it because the structure is part of their tactical advantage.

### Interaction

Inside the field, affected abilities can be disabled or put into a locked/recharging state. Leaving the field restores access after a short stabilization delay.

### Counterplay

Destroy the structure or move the fight outside its field. Enemies should also respect the jammer when appropriate rather than treating it as a magical player-only effect.

### Variants

- local jammer: small radius
- sector jammer: large field around an objective
- pulsed jammer: periodically turns on/off, creating movement windows

---

## 6.7 Gravity Well / Energy Anomaly

These are environmental combat structures rather than conventional enemies, but they should participate in the same battlefield simulation.

### Gravity Well

Creates a radial pull that becomes stronger near the center. Ships and projectiles are affected according to mass/strength rules.

Enemy behavior should explicitly account for it:

- normal ships try to avoid entering the danger radius
- agile drones can deliberately skim the edge
- heavy enemies can partially resist the pull
- if an enemy is caught inside, it is **actually dragged inward** rather than ignoring the hazard
- staying too close causes damage or hull stress

This gives the player opportunities to bait enemies into the well rather than making it a player-only hazard.

### Energy Anomaly

A less predictable field that can distort movement, projectiles, shields, or targeting. Use it sparingly and keep its rules visually readable.

---

## 6.8 Wreck / Debris Field

Destroyed ships should sometimes leave physical battlefield remnants instead of always disappearing.

### Uses

- hard cover / line-of-sight blocker
- collision hazard
- drifting debris
- explosive wreck
- temporary obstacle around a destroyed capital ship

A wreck can also become a temporary hiding location for the sniper or cover that a fighter circles around.

---

## 6.9 Mine / Minefield

Mines can exist independently of a Mine Layer and be placed as part of the environment. They should be authored as encounters/structures rather than just invisible collision objects.

Recommended variants:

- proximity mine
- drifting mine
- chain mine
- EMP mine
- boost-disruption mine

---

## 6.10 Twin-Laser Drones

### Role

Two small drones act together as a large moving laser weapon. The drones are the weapon endpoints.

### Attack A: closing laser

Two drones move to opposite sides of the player, establish a beam between themselves, and then **fly the beam through the player's position**. The beam damages anything intersecting the line, including other enemies.

```text
Drone A ======= LASER ======= Drone B
             PLAYER
                ↓
       drones advance together
```

The beam length and relative spacing should remain stable during the attack so the player can understand where the danger actually is.

### Attack B: V-launch → moving laser wall

A controller ship launches two laser drones in a V-shaped spread toward two predicted points around the player's path. Once they reach those points, they align into a separated `|---|` beam segment and **fly that entire segment toward the player together**. The V is the launch pattern; the laser wall is the actual attack shape.

Conceptually:

```text
Drone A  \
          \\   PLAYER
           \\  /\
            \//
             X
            //\
           /   \
Drone B  /     \
```

The final attack should therefore read visually as two drones moving in from a V-shaped launch and then advancing together as a `|---|` wall.

### Counterplay

The player can:

- move around the beam endpoints
- destroy one drone to collapse the laser
- bait the drones into terrain or a gravity well
- use the beam to damage the enemy formation

### Assault adaptation

The same concept works extremely well as a scrolling attack because the endpoints can be constrained to the corridor while the beam sweeps upward/downward or across the player's lane.

---

## 6.11 Carrier

### Role

A large multi-part enemy that changes the encounter structure.

### Size

192–320 px, potentially 4–6× the player's visual area.

### Composition

Do **not** make it one giant HP bar.

Example:

```text
       [Engine]       [Engine]
          \             /
        [Hangar]---[Core]---[Hangar]
          /             \
       [Gun]             [Gun]
```

Each module has its own health.

Possible destructible components:

- left engine
- right engine
- left gun battery
- right gun battery
- hangar doors
- bridge/core

### Damage progression

Destroying parts changes behavior:

**Engines damaged** → carrier loses turning authority.

**Gun destroyed** → one side becomes safe.

**Hangar destroyed** → fewer drone launches.

**Core exposed** → carrier enters panic state.

### Attack

Carrier should have several independent systems:

- heavy cannon
- missile bank
- fighter launch
- anti-approach pulse
- emergency drone deployment

### Dynamic fight

This is a major opportunity to make large enemies feel like machines instead of HP containers.

The carrier's silhouette should physically change as components are destroyed.

### Assault adaptation

The carrier moves vertically through the corridor at a controlled speed, but the player can still maneuver around individual subsystems.

Its body becomes a moving arena rather than a simple sprite.

---

# 7. Heavy Gunship rework

The current Gunship is a good foundation for a heavy enemy because it already has a health-based phase change and dual-barrel attack. Its current major limitation is that entry, tracking, and retreat all assume the player is below the ship and that the screen has a meaningful top edge. fileciteturn0file0L1110-L1196

## New identity

A **mobile gun platform**, not a mini-boss by default.

### Size

112–160 px.

### Movement

Use slow tactical movement:

- maintain distance
- rotate to broadside the player
- strafe around a wide arc
- occasionally boost away
- turn the hull to bring weapon banks onto target

### Weapon layout

Give it visibly separate weapon systems:

- left gun battery
- right gun battery
- central cannon
- rear missiles

Destroying a side battery disables that attack permanently.

### Phase behavior

**100–60% HP:** controlled and defensive.

**60–30%:** weapons overheat and vent; attack windows become shorter.

**<30%:** emergency boost pattern, aggressive retreat, rear missile launches.

Unlike the current Gunship, do not make retreat equivalent to instant despawn. In Open Space it should remain in the encounter and attempt to escape the player.

---

# 8. Boss redesign

The existing Space Station already demonstrates a strong multi-part boss pattern: four independently destructible turrets, an armored core, a phase transition when all turrets die, rotating beams, bullet rings, reinforcements, and a multi-stage death sequence. This is the correct direction for future bosses. fileciteturn0file0L1375-L1435 fileciteturn0file0L1635-L1699

However, future bosses should be designed around **360° encounters from the beginning** rather than converting a vertical station fight afterward.

## 8.1 Space Fortress 2.0

### Size

320–512 px.

### Identity

A fortress that tries to keep the player moving around it.

### Suggested systems

**Outer batteries**

4–6 independent turrets, each with a distinct attack:

- spread cannon
- laser sweep
- missile launcher
- rapid pulse
- slow artillery

**Shield nodes**

2–3 shield generators that protect different sectors.

**Core**

Hidden or armored until enough external systems are destroyed.

### Phase progression

```text
PHASE 1
outer batteries active
        ↓
PHASE 2
shield generators exposed
        ↓
PHASE 3
core exposed + fortress begins moving
        ↓
PHASE 4
critical reactor + attack frenzy
```

### Open Space movement

The fortress should not chase the player at high speed. Instead it can:

- slowly rotate
- reposition within a combat zone
- deploy thrusters to shift orbit center
- change orientation so its weak side changes

The player should be encouraged to **circle the boss**.

### Assault adaptation

The fortress can be constrained to move vertically while still rotating and exposing different sides.

---

# 9. New boss: Dreadnought

## Size

320–480 px.

## Role

The opposite of the Space Fortress: a large ship that actively hunts the player.

### Core idea

The Dreadnought consists of a central hull plus detachable weapon modules.

```text
  [turret]   [missile]
       \      /
       [ CORE HULL ]
       /      \
 [engine]    [engine]
```

### Movement

The Dreadnought uses long arcs around the player rather than tracking directly.

It should feel like two enormous bodies trying to change position relative to each other.

### Attacks

- broadside cannon sweep
- missile fan
- energy torpedo
- engine wake hazard
- heavy ram when critically damaged

### Destruction order

The player can choose what to disable first:

- weapons
- engines
- shields
- core

This introduces tactical freedom without requiring a menu or weak-point prompt.

### Phase shift

When one engine is destroyed, the Dreadnought becomes asymmetrical and its movement visibly changes.

When both engines are destroyed, it becomes stationary but enters an extreme weapons phase.

---

# 10. Boss reinforcement philosophy

Reinforcements should be part of the boss's machine behavior, not generic random waves.

Examples:

**Carrier boss:** launches drones from specific destroyed/active hangars.

**Fortress:** deploys defenders from damaged sectors.

**Dreadnought:** launches interceptors when a weapon module is destroyed.

This means destroying a module changes what the player has to fight next.

The existing Space Station already points toward this structure through its reinforcement subsystem, but those reinforcements currently use the normal Assault enemy container and scoring plumbing. fileciteturn0file0L1375-L1435

---

# 11. Weapons rework

Enemy weapons should become more diverse than "EnemyBullet with another speed/damage value."

The current enemy projectile architecture has only a basic bullet plus the specialized sniper projectile, while damage types currently distinguish LASER, ROCKET, and CONTACT. fileciteturn0file0L265-L302

## 11.1 Bullet family

### Pulse Round

Basic accurate projectile.

### Scatter Round

Short-range spread.

### Gatling Stream

Many low-damage projectiles with a visible stream rhythm.

### Heavy Shell

Slow, large projectile with high impact.

---

## 11.2 Rocket family

### Dumb Rocket

Fast and predictable.

### Pursuit Rocket

Mild steering for several seconds.

### Cluster Rocket

Splits into 3–5 small missiles.

### Delayed Warhead

Slower projectile that detonates after entering a proximity radius.

### Hijack Pulse

A non-damaging control projectile emitted by the Hacker Frigate. It temporarily claims ownership of eligible automated player projectiles and changes their target to the player. The effect should have a clear visual and short duration so the player understands the threat.


---

## 11.3 Energy weapons

### Beam

Immediate line with telegraph.

### Sweeping Beam

Rotates continuously for a short window.

### Lance

Narrow high-damage line with very short active duration.

### Pulse Ring

Expanding radial attack that forces movement around the enemy.

### Twin-Beam / Endpoint Laser

Two drones or emitters define the endpoints of a continuous laser. The weapon can:

- move the endpoints together, sweeping the beam through the player
- hold the endpoints while the host ship moves
- rotate the beam around an anchor point
- damage other enemies caught in the line

This should be treated as a real projectile/beam family, not as a boss-only special effect.

### Moving Laser Wall

Two endpoint drones form a beam segment and translate that segment toward the player, producing a readable `|---|` moving wall. A controller ship can fire the endpoints toward predicted positions so the wall cuts off escape routes rather than simply aiming at the current player location.


---

## 11.4 Area-control weapons

### Mine

Persistent obstacle.

### Gravity Field

Temporarily reduces movement/boost effectiveness.

### EMP Pulse

Disrupts enemy/player systems only if this fits the existing player mechanics.

### Debris Charge

Enemy breaks off an armor fragment that becomes a moving hazard.

---

# 12. Enemy projectiles need a world-space lifetime system

The current `EnemyBullet` uses fixed Assault arena bounds, which is explicitly identified as incompatible with Open Space. fileciteturn0file0L267-L297

Use a generic projectile lifetime controller:

```text
ProjectileLifetime
 ├── max_time
 ├── max_distance_from_owner
 ├── max_distance_from_player
 ├── world_bounds
 └── explicit_destroy()
```

A bullet should normally disappear because:

- it exceeded lifetime
- it exceeded useful travel distance
- it hit something
- its owner died and the weapon says the projectile should be recalled

For boss projectiles, allow a separate explicit rule such as:

`persist_after_owner_death = true`

This is useful for missiles, mines, and delayed beams.

---

# 13. Defense and damage system

The current project already has useful `Health`, `HurtBox`, `HitBox`, `Shield`, and damage-type infrastructure, but the enemy roster mostly uses only health and contact damage. fileciteturn0file0L199-L233

The redesign should introduce three generic defense concepts.

## 13.1 Armor

Armor modifies which attacks can hurt an area.

Examples:

- bullets bounce/deflect
- rockets damage armor plates
- heavy weapons stagger armor
- contact damage does not bypass armor unless explicitly designed

## 13.2 Shields

Shields should be a temporary combat resource rather than a second HP bar.

Examples:

- directional shield
- local module shield
- regenerating shield
- shield bubble projected by support ships

## 13.3 Weak points

Use small vulnerable components for large enemies.

The player should discover them visually, not by opening a menu.

---

# 14. Modular large-enemy damage

For large enemies, stop using one `Health` node for the entire object.

Recommended structure:

```text
Carrier
 ├── LeftEngine       100 HP
 ├── RightEngine      100 HP
 ├── LeftGun          80 HP
 ├── RightGun         80 HP
 ├── Hangar           140 HP
 └── Core             300 HP
```

Each module should expose:

- health
- armor
- damage types accepted
- disabled state
- visual state
- gameplay consequence

This creates the kind of "destroy the ship piece by piece" fight you requested without requiring a completely custom boss framework for every large enemy.

---

# 15. Collision layers cleanup

The current collision setup contains named layers plus unnamed numeric layers, and `BaseEnemy` currently overwrites every enemy's hurtbox mask with `97 | 1024`. The audit specifically calls out bits 6 and 11 as unnamed and worth cleaning up if Open Space gains richer enemy interactions. fileciteturn0file0L448-L463

## Proposed semantics

Keep the existing layers where practical to minimize migration risk, but give every used bit an explicit name.

Suggested conceptual model:

| Layer | Purpose |
|---:|---|
| 1 | World / environment |
| 2 | Interactables |
| 4 | Player body |
| 32 | Player / enemy rockets |
| 64 | Player weapons |
| 128 | Player hurtbox |
| 256 | Enemy offensive hitboxes |
| 512 | Enemy hurtboxes |
| 1024 | World hazards / asteroid contact |
| 2048 | Area-control / special hazards |
| 4096 | Boss/module interaction if needed |

The exact numeric allocation can remain unchanged for existing systems; the important part is that the project stops relying on unnamed magic numbers.

## Important architectural change

Do not let `BaseEnemy._ready()` blindly overwrite an enemy hurtbox mask anymore.

Instead expose a `DamageProfile` / `DefenseProfile` that sets accepted damage types and interaction rules.

That is especially important for Ram Corvette-style armor and multi-part bosses.

---

# 16. Contact damage rework

Contact damage should become an explicit offensive system rather than something every `BaseEnemy` happens to have.

Recommended enemy contact profiles:

**None**

Support ships, salvage drones.

**Collision**

Normal ship body damage.

**Ramming**

High damage, only during a committed attack state.

**Explosive collision**

Deals contact damage plus an explosion on impact.

**Armor collision**

Deals high stagger/contact damage while partially protecting the enemy.

This prevents every ship from feeling equally dangerous when touching the player.

---

# 17. Formation behavior

Formations should become dynamic groups, not static geometry from `WaveBuilder`.

The current system has V, W, wedge, line, diagonal, and cluster formation helpers. These are useful as spawn arrangement tools, but they should not define how the enemies continue moving. fileciteturn0file0L311-L340

Use:

```text
FormationSpawn
      ↓
SquadController
      ↓
role assignment
      ↓
individual AI
      ↓
dynamic regrouping
```

Example:

```text
5 Fighters

      Leader
        ↓
   F1         F2
      \       /
        F3
        F4
```

If F1 dies:

- F3 can become left flank
- F2 remains right flank
- formation contracts
- one ship may switch to attack role

This is far more dynamic than keeping five ships on five scripted curves.

---

# 18. Squad communication

Give enemies a lightweight encounter-level communication system.

Messages might be:

- `TARGET_MARKED`
- `BEGIN_ATTACK`
- `PLAYER_BOOSTING`
- `ALLY_DAMAGED`
- `ALLY_DESTROYED`
- `RETREAT`
- `REPOSITION`
- `FORMATION_BROKEN`

This does not need a complex AI planner.

For example, if the sniper marks the player, two fighters could temporarily attempt a flank while the sniper relocates.

The player then experiences a small tactical scenario instead of ten independent projectiles.

---

# 18.5. Open Space idle behavior and ambient movement

Open Space enemies should not look frozen while waiting for the player to enter combat. Every enemy family should have a lightweight **idle movement profile** that is cheaper and calmer than combat AI.

This is especially important for distant enemies that the player can see before an encounter starts. They should feel like ships operating in the world, not objects waiting for a trigger.

## Idle movement rules

Idle behavior should be driven by an anchor and local motion rather than random teleportation:

```text
Idle Anchor
   ↓
soft orbit / drift / patrol
   ↓
small variation
   ↓
combat perception
   ↓
switch to combat AI
```

Useful idle patterns:

- slow orbit around a station
- asymmetric patrol loop
- figure-eight drift
- short braking bursts
- gentle formation drift
- escort circling a carrier
- docking/undocking movement
- turret scanning arcs
- Razor Drone repeatedly changing orbit direction around an anchor

### Razor Drone idle behavior

Razor Drone should be a signature example. Before detecting the player, it can make an irregular orbit around a patrol anchor, occasionally accelerate, brake, reverse orbit direction, or inspect nearby debris. Once the player enters its perception radius, it transitions naturally into the full combat sequence instead of instantly snapping to a combat position.

### Idle should not become busywork

Idle behavior should communicate faction identity and make encounters visually alive. It should not consume the same CPU budget as combat AI or attempt complex target reasoning when the player is far away.

---

# 18.6. Battlefield structures and environmental combat systems

Open Space should contain objects that change how ships fight, not just decorate the background.

## Structure categories

### Defensive structures

- stationary turrets
- shield generators
- jammer towers
- missile batteries
- laser emitters

### Destructible / physical structures

- ship wrecks
- drifting debris
- damaged satellites
- abandoned cargo platforms
- broken station modules

### Energy / physics structures

- gravity wells
- energy anomalies
- unstable reactor fields
- EMP zones
- temporary laser barriers
- stationary laser walls

### Placement principle

Structures should form tactical spaces:

```text
      Turret
        ↓
Wreck ======== Wreck
        \\    /
         \\  /   Gravity Well
          \\●
           \
        Player
```

Enemies should understand these objects through the same perception/steering system used for the player. That means enemies can use cover, avoid damage zones, accidentally hit hazards, or deliberately push the player toward dangerous geometry.

## Hazard avoidance should be intentional

Normal AI should have a soft avoidance layer:

```text
Desired combat velocity
        +
Hazard avoidance vector
        +
Collision / steering constraints
        ↓
Final movement intent
```

The avoidance strength depends on the hazard and enemy profile. A tiny drone strongly avoids a gravity well. A heavy dreadnought partially resists it. A suicidal ram drone may ignore it during the final committed attack.

## Hazards can be tactical tools

Do not make hazards universally bad for enemies. The interesting behavior comes from how enemies use them:

- sniper hides behind wreckage
- fighters use a wreck as cover before a pass
- ram ships avoid the gravity well until a charge can force the player toward it
- drones skim the edge of a danger field
- carriers position escorts between themselves and turrets
- hackers stay outside the player's preferred route while jamming from range

---

# 19. Open Space encounter patterns

Enemies should be spawned according to encounter roles, not only individual ship types.

## Example: scout encounter

```text
2 Swarm Drones
1 Razor Drone
```

Drones harass; Razor Drone attempts the actual intercept.

## Example: convoy

```text
1 Carrier
2 Fighters
1 Support Ship
2 Swarm Drones
```

The player has several meaningful priorities.

## Example: sniper ambush

```text
1 Sniper
2 Flank Fighters
1 Mine Layer
```

Mine Layer closes escape routes, Fighters force movement, Sniper attacks from outside view.

## Example: heavy patrol

```text
1 Heavy Gunship
1 Missile Corvette
2 Fighters
```

Gunship controls space, Corvette launches rockets, Fighters chase the player out of safe angles.

---

# 20. Assault encounter patterns

Assault should not become a separate arcade game with entirely separate enemies.

Instead, use the same encounters with an **arena constraint**.

Examples:

### Sniper + Fighters

Open Space:

- sniper leaves camera
- fighters flank from both sides
- sniper fires from a distant angle

Assault:

- sniper leaves visible play area temporarily
- fighters occupy the lower-left/lower-right corridor
- sniper returns from upper-left or upper-right

### Carrier

Open Space:

- player circles carrier
- hangars launch drones
- player can attack the rear

Assault:

- carrier enters vertically
- player can move laterally around it
- carrier remains partially inside the corridor rather than simply crossing the screen

### Ram Corvette

Open Space:

- predicts player velocity and charges

Assault:

- predicts player's horizontal/diagonal movement inside the corridor

The player should feel like they are fighting the same machine in both modes.

---

# 21. Visual redesign

The current enemy art is generally dark: navy/black hulls with red/crimson accents. That gives the faction a consistent identity, but many silhouettes risk disappearing against a dark Open Space background. The requested approach should preserve the faction while increasing readability rather than simply making everything brighter. The audit describes this dark shared palette repeatedly across the current drones, bomber, fighters, gunship, and station. fileciteturn0file0L639-L642 fileciteturn0file0L783-L800 fileciteturn0file0L1018-L1048

## 21.1 Readability rules

Every enemy should have three visual layers:

**Silhouette**

Visible at small distance.

**Faction accents**

Red/maroon/orange mechanical markings.

**Gameplay lights**

Small high-contrast elements indicating attack state.

Examples:

- red glow = armed
- yellow = charging
- white = locked shot
- cyan/blue = shield
- orange = overheating
- dark/off = destroyed module

Do not recolor the entire enemy according to state. Keep the faction palette intact and change only gameplay-critical indicators.

## 21.2 Bright edge separation

Use subtle cool edge highlights around dark silhouettes so they remain readable on dark backgrounds.

For example:

```text
black hull
+ dark blue edge light
+ red faction stripe
+ one bright weapon indicator
```

This is better than turning ships into bright red sprites.

## 21.3 Size language

Use size as part of gameplay communication:

- 24–36 px = swarm / disposable
- 40–72 px = fighter
- 80–120 px = specialist
- 112–160 px = heavy
- 192–320 px = carrier
- 320–512 px = boss

With a 64×64 player ship as the reference, the scale differences will be immediately readable.

---

# 22. Sprite recommendations

## Small drones

Prefer 24×24 or 32×32 source sprites with exaggerated silhouettes and larger weapon/engine shapes.

## Fighters

64×64 or 72×72.

Keep the current angular top-down language, but increase contrast between cockpit, hull, engine, and weapon pods.

## Specialists

80×80 to 128×128.

Specialist ships should have clearly identifiable silhouettes. A sniper could be very narrow, while a bomber should be wide.

## Large ships

Do not simply scale up the fighter sprite.

Build carriers and bosses from multiple coherent modules so the damage state can change the silhouette.

The Space Station already establishes this philosophy visually through a 256×256 hull plus 64×64 independent turrets and destroyed turret states. fileciteturn0file0L1443-L1482

---

# 23. Enemy visual states

Every specialist should have at least one visually readable state change.

Examples:

**Sniper**

weapon unfolds during charge.

**Ram Corvette**

armor plates glow during charge and physically disappear when destroyed.

**Support Ship**

shield projector unfolds while supporting another unit.

**Carrier**

hangar doors open before drones launch.

**Gunship**

damaged weapon banks spark and stop rotating.

**Boss**

destroyed modules visibly remain as wreckage.

This makes the behavior discoverable without HUD text.

---

# 24. Boss weapons should come from the geometry

Large enemies should weaponize their body shape.

Examples:

A long carrier fires a long side beam.

A ring-shaped fortress creates radial pulses.

A Dreadnought uses broadside cannons.

A multi-engine boss leaves dangerous exhaust trails.

A station with corner turrets creates diagonal crossfire.

The current Space Station already uses hull rotation to sweep attached lasers. This is exactly the kind of geometry-driven behavior worth expanding. fileciteturn0file0L1538-L1635

---

# 25. Boss phase design rules

Avoid phases that simply mean "boss has less HP."

Every phase should change at least two of:

- movement
- attack pattern
- vulnerable areas
- arena control
- reinforcement behavior
- visual state

Example:

```text
PHASE 1
4 weapon pods
slow movement

PHASE 2
2 weapons destroyed
shield collapses
carrier starts moving

PHASE 3
core exposed
missiles become active
rear attack added

PHASE 4
critical
engines overload
boss attempts a final ram
```

This makes damage feel like progress rather than a number going down.

---

# 26. Destruction should change the battlefield

The best large enemies should physically transform the fight when pieces are destroyed.

Examples:

- destroying a carrier engine changes its movement arc
- destroying a turret removes one attack angle
- destroying a hangar reduces reinforcements
- destroying a shield generator exposes an entire sector
- destroying an armor plate reveals a new weapon
- destroying a missile rack causes missiles to stop

This gives the player a strategic reason to aim somewhere specific.

---

# 27. Open Space target selection

Enemies need a target-selection abstraction rather than blindly asking for `player.global_position` everywhere.

Use:

```text
TargetInfo
 ├── position
 ├── velocity
 ├── facing
 ├── distance
 ├── relative_angle
 ├── predicted_position
 └── line_of_sight
```

This allows enemies to make useful decisions:

- fighter leads the target
- sniper predicts further ahead
- rammer predicts a shorter future position
- rocket ship chooses a target point based on travel time
- mine layer chooses an intercept point

The current project already has direct player-group lookups that work mechanically in Open Space, but those lookups are scattered and mixed with Assault-specific movement logic. fileciteturn0file0L521-L526

---

# 28. Line of sight and occlusion

Introduce a simple optional perception rule:

```text
can_see_player()
```

Not every enemy needs it.

Useful for:

- sniper
- missile corvette
- support ship
- boss turrets

Potential behavior:

Sniper refuses to fire if a large asteroid blocks the shot.

Missile ship can still fire because its missiles can curve around obstacles.

This would make Open Space terrain relevant to combat instead of decorative.

---

# 29. Difficulty scaling

Do not make enemies simply faster and stronger at higher difficulty.

Scale:

**Easy**

slower decisions, larger telegraphs, fewer coordinated attacks.

**Normal**

intended behavior.

**Hard**

better prediction, tighter coordination, shorter attack cooldowns.

**Very Hard**

additional behavioral branches, not huge HP inflation.

For example, a hard sniper does not need 3× HP. It may instead relocate sooner and choose more varied firing angles.

---

# 30. Suggested enemy parameter groups

Instead of dozens of unrelated exports, organize config by behavior.

```text
MovementProfile
  max_speed
  acceleration
  braking
  turn_rate
  orbit_radius
  orbit_speed
  boost_speed

AttackProfile
  range
  fire_interval
  projectile_speed
  damage
  spread
  burst_count
  telegraph_time
  cooldown

DefenseProfile
  health
  armor
  shield
  collision_damage
  accepted_damage_types

TacticalProfile
  preferred_range
  aggression
  retreat_health_ratio
  target_prediction_time
  regroup_distance
  disengage_distance
```

Then an enemy config becomes understandable at a glance.

---

# 31. Remove current magic-number coupling

The current Sniper is a good example of a fragile script/config dependency: its `FLY_IN_TIME` must exactly match the wave-authored path duration. The audit also identifies hardcoded camera bounds, direct parent hierarchy assumptions in `BulletPool`, and camera-relative spawn math as recurring problems. fileciteturn0file0L468-L543

The redesign should eliminate this class of dependency.

For example:

Bad:

```text
SNIPER_FLY_IN_TIME = 2.5
wave path = 2.5
```

Better:

```text
sniper movement state owns its approach duration
```

or:

```text
approach_distance / movement_speed = approach_duration
```

The same principle should apply to spawn distance, projectile lifetime, retreat behavior, and phase transitions.

---

# 32. Open Space spawn system

Open Space needs a real encounter spawner rather than `SectorHub` spawning three ambient drones once at random positions. The current hub has no wave/director-equivalent system for enemies. fileciteturn0file0L391-L440

Recommended structure:

```text
EncounterDirector
 ├── encounter definitions
 ├── spawn budget
 ├── difficulty budget
 ├── world anchor
 ├── active enemy list
 └── cleanup
```

Spawn positions should be semantic:

- ahead of player
- behind player
- left flank
- right flank
- above
- below
- near encounter anchor
- outside camera view
- near objective

Example:

```text
spawn("sniper", RelativeTo.PLAYER_REAR, distance=1000)
spawn("fighters", RelativeTo.PLAYER_FLANK, distance=500)
spawn("carrier", RelativeTo.OBJECTIVE, distance=1200)
```

This is much more useful than camera coordinates.

---

# 33. Enemy persistence in Open Space

Enemies should be allowed to leave the camera without immediately dying.

A useful encounter lifecycle:

```text
VISIBLE
  ↓
FAR
  ↓
SEARCHING
  ↓
REENGAGE
```

However, avoid infinite enemy persistence.

Use a leash:

```text
if distance_from_encounter_anchor > leash:
    disengage
```

This keeps the world manageable while preserving the feeling that enemies inhabit physical space.

---

# 34. Assault compatibility layer

Instead of rewriting every existing wave immediately, add an Assault constraint wrapper.

```text
EnemyBrain
   ↓
DesiredVelocity
   ↓
AssaultMovementConstraint
   ├── corridor bounds
   ├── maximum vertical travel
   ├── maximum lateral travel
   └── optional edge pressure
   ↓
MovementController
```

This allows the same enemy logic to work in both modes.

Example:

A Sniper wants to move 900 px behind the player.

Open Space: allowed.

Assault: limited to a maximum of 450 px outside the visible combat region, then forced to re-enter.

---

# 35. Replace static formation paths with role formations

Existing formation helpers such as V/Wedge/Line should be kept only as **spawn layouts**. Their job ends when the enemies become active.

Example:

```text
spawn V formation
        ↓
assign Leader
        ↓
assign Flanker L/R
        ↓
assign Support
        ↓
formation becomes dynamic
```

This preserves the existing level-authoring convenience while removing the feeling that every enemy is following a rail.

---

# 36. Recommended first-pass roster

For the initial rewrite, I would implement these ten combat types:

### Tier 1

**Swarm Drone**

Disposable coordinated rammer.

**Fighter**

Balanced ranged attacker with attack runs.

**Razor Drone**

Orbit + dash striker.

### Tier 2

**Gatling Interceptor**

Suppression and side passes.

**Bomber**

Bombs/mines and battlefield shaping.

**Sniper**

Hidden relocation + precision shot.

**Ram Corvette**

Armor + charge.

**Missile Corvette**

Rockets + medium-range control.

**Support Ship**

Repair/shield support.

### Tier 3

**Heavy Gunship**

Multi-weapon heavy.

**Carrier**

Multi-part spawning platform.

Then build two bosses:

**Space Fortress**

Multi-part stationary/slow-moving fortress.

**Dreadnought**

Large mobile boss.

This is enough to create many encounter combinations without having a huge number of one-off classes.

---

# 37. Enemy combinations to build around

The strongest part of this redesign is not individual enemy count. It is combinations.

## Swarm + Sniper

Drones force movement while the sniper punishes predictable escape paths.

## Bomber + Fighter

Bomber restricts space; fighters exploit the remaining space.

## Support + Ram

Support keeps the ram ship alive long enough to make multiple attack attempts.

## Carrier + Sniper

Carrier controls the local area while the sniper relocates outside the battle.

## Gunship + Swarm

Gunship creates suppressive fire while drones make the player's path unpredictable.

## Missile Corvette + Fighter

Rockets force turns; fighters attack the new direction.

## Carrier + Support + Drones

Destroying the support ship first reduces the carrier's ability to regenerate its escort force.

---

# 38. What I would scrap completely

## Keep: Bonus Drone as an Assault reward enemy

The Bonus Drone remains in Assault specifically because its current interaction is valuable: it is a fast, fragile target that forces the player to track it quickly and destroy it before it escapes, paying out a large score reward.

For Open Space, the same visual family can become a **Salvage Drone / Emergency Cache Drone** encountered as an optional world event. That version is not a normal combat enemy and does not need to count toward combat clearance.

## Scrap: fixed-screen Bomber movement

Keep bomber's role, completely rewrite movement and ordnance.

## Scrap: straight-line Kamikaze Drone

Replace with coordinated swarm behavior.

## Scrap: Gunship's screen-top parking behavior

Keep the heavy gunship concept but make it a mobile tactical unit.

## Scrap: path-authored Sniper retreat

Make relocation a native AI behavior. The sniper should create distance, choose a new firing position, become stationary while telegraphing/aiming/firing, and then disengage again after the shot. It should not automatically return to the player after firing.

## Scrap: camera-edge enemy despawning

Use encounter/world persistence in Open Space and a constraint system in Assault.

These changes directly address the architectural issues identified by the current audit rather than layering new behavior on top of the old assumptions. fileciteturn0file0L594-L618

---

# 39. What I would keep

## Keep the Drone Interceptor idea

Its orbit → predictive dash behavior is already close to the desired Open Space philosophy.

## Keep the Space Station's modular boss structure

The four independent turrets, armored core, phase transition, beams, rings, reinforcement logic, and death spectacle are strong foundations. fileciteturn0file0L1590-L1635

## Keep config resources

The existing `ShipConfig` + privatization mechanism is useful and already tested for per-instance isolation. fileciteturn0file0L154-L185

## Keep shared attack infrastructure

`AttackController`, attack patterns, and bullet pools are useful, but their container/lifetime assumptions should be removed from specific scene hierarchies. fileciteturn0file0L244-L257

---

# 40. Testing strategy for the rework

The existing test suite is strong on collision/config invariants but comparatively weak on enemy behavior. The audit explicitly notes that there are no direct tests for `BaseEnemy`, `EnemyPathMover`, or most enemy-specific behaviors, and the Open Space Patrol Drone has no dedicated behavior characterization. fileciteturn0file0L547-L587

The rework should add deterministic AI tests for:

## Movement

- target prediction
- orbit radius maintenance
- dash direction
- retreat direction
- formation recovery
- leash behavior

## Combat

- fire cadence
- telegraph duration
- weapon selection
- rockets
- mines
- beam activation

## Behavior

- sniper chooses new firing location
- support ship changes target when ally dies
- carrier stops launching from destroyed hangar
- ram ship changes vulnerability after armor destruction
- squad reassigns leader

## Large enemies

- module death disables attack
- module death changes movement
- core becomes vulnerable only when intended
- destroyed components remain as wreckage

## Mode compatibility

Every enemy should have at least one automated test in both:

```text
Open Space
Assault
```

The same behavior specification should be used in both tests, with only the movement constraint changed.

---

# 41. Recommended implementation order

## Phase 1 — architecture

1. Refactor `BaseEnemy` into a mode-neutral entity base.
2. Introduce `EnemyBrain`, `MovementController`, `AttackController`, and `DefenseProfile` contracts.
3. Replace camera-specific projectile lifetime with world-aware lifetime.
4. Name every collision layer currently used numerically.
5. Add `TargetInfo` / prediction helpers.

## Phase 2 — foundational enemies

1. Swarm Drone
2. Razor Drone
3. Fighter
4. Gatling Interceptor

This establishes swarm, orbit, attack-run, and suppression behavior.

## Phase 3 — specialists

1. Bomber
2. Sniper
3. Ram Corvette
4. Missile Corvette
5. Support Ship

This adds battlefield control, precision attacks, armor, rockets, and support mechanics.

## Phase 4 — heavy enemies

1. Heavy Gunship
2. Carrier

These introduce multi-weapon and multi-module design.

## Phase 5 — bosses

1. Space Fortress rework
2. Dreadnought

Use the new module architecture for both.

## Phase 6 — encounter director

Once individual AI feels good, rebuild Open Space spawning around encounter compositions rather than ambient random drones.

## Phase 7 — Assault migration

Replace old wave movement with spawn layouts + AI constraints, allowing existing level timing to remain mostly intact while the enemy behavior becomes dynamic.

---

# 42. Final design target

The finished enemy roster should make the following situations possible without bespoke level scripts:

```text
Player boosts away
        ↓
Swarm predicts the new path
        ↓
Fighters turn for a flank
        ↓
Bomber drops mines across the retreat route
        ↓
Sniper disappears off-screen
        ↓
Missile Corvette launches a predicted rocket salvo
        ↓
Player turns back
        ↓
Razor Drone attacks from the previous blind side
        ↓
Support Ship repairs the wounded Fighter
        ↓
Player kills Support Ship
        ↓
Formation collapses
        ↓
Carrier arrives and launches another squad
```

None of those events should require a special level script saying "now move this enemy to x=-300, then spawn the next thing at t=4.5".

The encounter should emerge from the enemies' roles.

That is the main opportunity of moving the roster into Open Space: **stop treating enemies as objects moving through a scrolling level and start treating them as autonomous combat machines operating in a shared 2D space.**

---

# 43. Compact design checklist

Before an enemy is considered finished, it should answer all of these:

- What makes its silhouette unique?
- What is its preferred combat distance?
- What is its movement signature?
- How does it attack?
- What does it do when the player approaches from behind?
- What does it do when the player boosts away?
- Can it fight effectively while off-screen?
- Does it have a retreat or reposition behavior?
- Does it have a distinct telegraph?
- Does destroying it change the encounter?
- Can it work in Open Space without camera coordinates?
- Can the same behavior run in Assault with movement constrained?
- Does its sprite communicate attack/defense state?
- Does it need armor, shields, or weak points?
- Does it work alone?
- Does it become more interesting when combined with another enemy?
- Can its behavior be tested deterministically?

If the answer to most of these is yes, the enemy is probably contributing a real gameplay role rather than filling a roster slot.

