# Enemy rework, phase 9: electronic warfare - Jamming Structure, Hacker Frigate and EMP — PRD

## The ask

> Enemy rework, phase 9 of 20. Enemies that attack the player's tools rather than the hull. Hook 1 is an ability / skill lock: the Jamming Structure suppresses special abilities (not movement or
> primary fire) inside a visible interference field, with a short stabilisation delay after the player leaves; local, sector and pulsed (on / off) variants; enemies fight around it. Hook 2 is
> retargeting of the player's seeking rockets: the Hacker Frigate (80–120 px) keeps medium to long range on asymmetric arcs and fires the Hijack Pulse, a non-damaging control projectile that claims
> eligible player rockets, newly launched and in flight, and turns them on the player, with a clear visual / audio / indicator tell and a short duration. The base Hacker affects only seeking ordnance;
> a variant that briefly disrupts abilities is decided by this phase's research. The EMP Pulse area weapon and phase 7's EMP mine use the same hooks where they fit. Counterplay: kill the source, hold
> rockets during the pulse, lure a hijacked rocket into another enemy. Both enemies are clamped to the corridor in Assault, own their art, and join Assault waves and the hub's ambient spawn. Tests in
> both harnesses cover lock / unlock timing, in-flight hijack and retargeting, and that primary fire is never affected.

**Scope:** `ENEMIES_OPEN_SPACE_REWORK_IDEAS.md` §6.4 Hacker Frigate, §11.2 Hijack Pulse, §6.6 Jamming Structure, §11.4 EMP Pulse, §18.6 jammer towers and EMP zones, §21–23 art, §40 tests.

**The epic's tasks:** ability lock (t1); lock tells (t2); homing-missile lifetime (t3); retarget hook and hijacked rocket (t4); EMP (t5); EMP Blast re-route (t6); Jamming Structure (t7); Hacker shell and
movement (t8); Hijack Pulse (t9); Disruptor (t10); EMP zone (t11); art (t12); hub placement (t13); level-1 placement (t14); docs, roster, dossier, phase record (t15).

**Owner's notes on the plan:** revised twice (revisions 2 and 3) to answer two review rounds (plan §8); the owner's seven choices kept their defaults (audio is a seam only, the EMP Blast routes by
`answers_emp()`, placed EMP mines reach enemies, the homing missile gets a `ProjectileLifetime`).

## Player-facing goal

The player's tools can be taken away, visibly and fairly. A jammer's ring crackles and a JAMMED chip with a refill bar says why H abilities and K rockets do nothing, while flying and shooting never
change. A Hacker charges a visible dish and turns up to three homing rockets back on the player: amber, slow, small blast, shot down with the main gun or lured into another ship. An EMP zone pulses
everyone inside, enemies included.

## Scope

- **In:** `PlayerBase` ability lock and its seams; `HazardField` jammer exports, `Hazards.jammer_at`; `SeekingOrdnance` retarget contract and the hijacked homing rocket; `EmpPulse` targets and the enemy EMP
  hook; `JammingStructure` (local / sector / pulsed); `HackerFrigate` + brain + `HijackPulse`; the Disruptor variant; `EmpZone`; art; hub and level-1 placement; docs.
- **Out (owner phase):** audio (Ph17); Hacker squad tactics (Ph14); Disruptor placement and difficulty numbers (Ph13 / Ph16); ship-mounted EMP (Ph10 / Ph18); jammer-linked turret groups (Ph20); enemy
  bodies blocking LOS (Ph19 / Ph14); jammer wreckage (Ph19); a module / cooldown HUD (Ph17).
