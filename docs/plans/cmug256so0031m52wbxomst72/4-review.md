VERDICT: CHANGES_REQUESTED

Independent review of `3-plan.md` (revision 1) and `tasks.json`, against the code on `agent/auto-dev` @ `349c752`. Read: `CLAUDE.md`,
`DECISIONS.md` (Ph10 as-built, the planned Ph11 section), `docs/epics-done/cmug23oo90029m52wae4clve0/REPORT.md`, IDEAS §8, §8.1, §10, §21–26, §39–41,
ENEMIES.md, and the code each section cites.

## Summary

The plan is close. It covers every scope line of the epic: §8.1 size, batteries, shield nodes, core and four phases; Open Space and Assault movement; §10 as a reusable
mechanism; §24 geometry weapons; §25 as a gate; §26; wreckage; art; the station's retirement; the naming collision. It reuses Phase 10's framework instead of
rebuilding it: `EnemyModule`, `ModularHull.build_mounts`, `TurretMountBuilder`, `EnemyShield`, `EnemyBeam`, `EnergyRing`, `RadialAttackPattern`, `AnchorIdle`
and the Carrier's armoured-hull rule. Most of the §1.3 code facts check out, including the station scene and config, the `LevelDirector` poll, the ScoreTracker
orphan path, `EnemyShield`'s armoured-host rule, `EnemyMover.step()`'s capped face-point turn, the hub draw order and hard counts, the player numbers (360 /
420 px/s, 50 dmg / 0.18 s), and EMP Blast routing.

Three problems block approval:
- **t5 is missing a dependency on t2.**
- **t11's acceptance grep cannot pass.**
- **The Assault density ceiling, the plan's mitigation for its own top risk, is vacuous where it is measured and absent where it matters.**

The rest are minor corrections. Several of them would otherwise cost an unattended run time, most of all the `telegraph_gate` arity and the inherited-scene
export trap.

**EMP on structures (§2.12, t12) is not scope creep.** The Phase 10 as-built section explicitly defers it to Phase 11 (DECISIONS.md:3829-3831, :3896, :4347:
"EMP on structures (bonus drone, station, Ph8 turrets / fences) | Ph11"). Keeping the bonus drone's legacy freeze is a recorded decision put to the owner as
choice 7. One §1.3 fact behind t12 is wrong, though (finding 5).

**Owner choices.** "Owner choice N" refers to the plan's own summary list (3-plan.md:18-24). The planned Ph11 section of DECISIONS.md (:4360-4372, :4392-4393)
repeats choices 1, 4 and 5 as defaults and records 6 and 7 by content. The body uses the numbers consistently: 1 retire the station, 2 two batteries, 5 240 s,
6 `emp_factor`, 7 structure EMP. See finding 20 for the cross-phase numbering clash.

**Research.** There is no `1-context.md` / `2-research.md` and no external research (3-plan.md:107). That is acceptable here. The owner's spec is
prescriptive, Phase 10 used the same precedent, and §1.2 labels its judgement calls and gives a reason for each key structural choice (container node vs
director change, 360° bubble vs arc, no `ShieldGenerator` reuse, twin rig dropped). It is thin on tradeoffs, but that is not a reason to reject.

## Findings

### Blocking

1. **blocking — t5 uses t2's API without depending on it (t5, t2).**
   - What the plan says: §2.5.3's death order calls `reinforcements.scuttle_all()` and `_finish_death()` "free the escort container" (3-plan.md:325-326). t5
     row 7 asserts "escort container freed with it" (3-plan.md:383).
   - Where that API comes from: `BossReinforcements`, `EscortContainer.ensure/of` and the escort container are all built in t2 (§2.2).
   - The task graph: `tasks.json` gives t5 `dependsOn: ["t1","t4"]` and its `planSections` omit 2.2. §3 step 1–2 lets t5 run before t2.
   - Impact: a t5 agent that runs first has neither the class nor the spec. It would invent a container helper that t2 then duplicates, or stall.
   - Fix (either):
     - add `t2` to t5's `dependsOn` and `2.2` to its `planSections`; or
     - move the scuttle / escort-container clauses of §2.5.3 and row 7 into t8, which already depends on t2.

2. **blocking — t11's acceptance grep cannot return nothing (t11).**
   - §2.11 requires `grep -rn "space_station\|SpaceStation\|…" --include=*.gd --include=*.tscn --include=*.tres` outside `docs/` to return nothing
     (3-plan.md:565-566).
   - It matches files that have nothing to do with the boss, because Fortuna's Open Space mission data lives under directories named `space_stations/`:
     - `open_space/scenes/levels/sector_hub.tscn:10` (`res://open_space/scenes/mission_select_hubs/space_stations/fortuna_station.tres`)
     - `open_space/scenes/mission_select_hubs/space_stations/fortuna_station.tres:5`
     - `open_space/scenes/mission_data/space_stations/fortuna_station/fortuna_station_01_race_mission_first_cup.tres:3`
   - Impact: an unattended t11 either fails its own acceptance or "fixes" it by renaming Fortuna's mission directories. That is out of scope, churns UIDs, and
     pulls in exactly the "Fortuna Space Station" vocabulary the plan says to stay away from.
   - Fix: anchor the pattern, e.g. `enemies/space_station/\|space_station\.\(gd\|tscn\|tres\)\|SpaceStation\|Station\(Turret\|Gunnery\|LaserPhase\|Reinforcements\|DeathSequence\)`,
     or exclude `open_space/scenes/mission_*`. Add `StationDeathSequence` to the class list too; t4 renames it, so a leftover should fail.

3. **blocking — the measured density ceiling cannot fail where it is measured, and the frenzy is not measured at all (t7).**
   - What the plan measures: §2.7 measures density only in `batteries` with all five alive, against a ceiling of 2.0 × 6.67 = 13.3 rounds/s
     (3-plan.md:459-460). This is the mitigation for the plan's first-listed risk (§5, 3-plan.md:663-664).
   - Upper bound in `batteries`, from the §2.3 and mount-scene numbers (cycle = charge + (burst−1) × gap + cooldown), with no attack gate and every mount in arc:

     | Mount | Source | Cycle | Rate |
     |---|---|---|---|
     | spread | §2.3 | 10 rounds / 3.75 s | 2.67 /s |
     | rapid | §2.3 | 10 / 3.53 s | 2.83 /s |
     | heavy cannon | heavy_cannon_mount.tscn: 0.7 / 2 / 0.35 / 3.2 | 2 / 4.25 s | 0.47 /s |
     | rocket battery | rocket_battery_mount.tscn: 0.5 / 2 / 0.35 / 5.5 | 2 / 6.35 s | 0.31 /s |
     | sweep | no rounds | — | 0 |
     | **Total** | | | **≈ 6.3 /s** |

     That is under half the ceiling, so the row is green on any tuning t7 could plausibly pick.
   - The phase that can actually crowd the 1280 × 720 view is `critical`:
     - cooldowns × 0.6 put spread at ≈ 3.8 /s, rapid ≈ 4.0, artillery ≈ 0.67 and rockets ≈ 0.48;
     - the core ring adds 12 every 2.0 s = 6.0 /s;
     - total ≈ 15 /s upper bound, before spokes, the 3.5 s ring and the surge escorts.
   - Fix:
     - measure the ceiling in `critical` as well (and `core_exposed`), with the player stub at several positions, not only the view centre: (640, 360) sits
       4 px below the 176 px hull at y 180, where the north mounts are out of arc;
     - state each phase's ceiling;
     - keep the rule "tune, never widen".

### Minor

4. **minor — `attack_gate(mount)` does not match the `telegraph_gate` contract (t7).**
   - `TurretMount.telegraph_gate` is a zero-argument `call() -> bool` (turret_mount.gd:66-68, invoked as `telegraph_gate.call()` at :279).
   - `ModularHull.build_mounts` hands the same Callable to every mount, unbound (modular_hull.gd:78-93).
   - §2.7 specifies `attack_gate(mount) -> bool` (3-plan.md:430-433). Called with zero arguments, that is a runtime error on the first TRACK → TELEGRAPH.
   - Fix: declare it `attack_gate() -> bool` (count the battery mounts in TELEGRAPH / FIRE; the asking mount is still in TRACK), or bind per mount outside
     `build_mounts`.

5. **minor — the §1.3 / §2.12 facts behind t12 are partly wrong (t12).**
   - Wrong: "turrets / fence posts / shield generators have brains but no mover" (3-plan.md:99). `LaserEmitter` has **no brain and no mover**
     (laser_emitter.gd:4; `laser_emitter.tscn` has no `Brain` node). For a post, "the brain gets `on_emp_started()`" does not apply.
   - Already true: "`BaseEnemy.apply_emp` must tolerate a null mover" (3-plan.md:570-571). It already guards `if _mover != null` (base_enemy.gd:185-188), and
     `_physics_process` already counts a brainless structure's window (base_enemy.gd:121-133).
   - Fix: say how a post's window reaches its fence. For example, `LaserFence.step()` (laser_fence.gd:93) reads `post.is_emp_disrupted()` and cancels / holds
     the beam while either post is disrupted. Drop the null-mover item, or turn it into a test row.

6. **minor — inherited mount and beam scenes and `export_of()` return the wrong values (t3, t7).**
   - Which scenes: §2.3 / §2.7 make `spread_cannon_mount.tscn` and `rapid_pulse_mount.tscn` inherit `burst_cannon_mount.tscn`, `fortress_spoke_beam.tscn`
     inherit `beam.tscn`, and `fortress_pulse_ring.tscn` inherit `energy_ring.tscn`.
   - The trap: `TurretMountScenes.export_of()` → `EnemyBeamScenes.export_of_scene()` reads only the scene's own `SceneState` (enemy_beam_scenes.gd:49-64).
     For an inherited scene, any property not re-authored comes back as the script default, not the base scene's value. The existing speed sweep uses
     `export_of` this way (test_enemy_bullet_lifetime.gd:69-80).
   - Precedent: `heavy_cannon_mount.tscn` is a standalone scene. Phase 10's one inherited ring was checked by instantiating it (test_carrier.gd:1074-1080).
   - Fix: make the two mounts standalone like the heavy cannon, or require every value a gate reads to be authored in the inherited scene, and have the
     fairness / lifetime rows read instantiated nodes.

7. **minor — the escort flag writes are overwritten, and are not needed (t2).**
   - The order problem: §2.2 sets `counts_toward_wave_clear = false`, `counts_as_escape = false` among the pre-`add_child` writes (3-plan.md:220-221).
     `BaseEnemy._ready()` then overwrites both from the config (base_enemy.gd:105-109), so they end up true.
   - Side effect if they did stick: `counts_toward_wave_clear` false makes the Support Ship treat escorts as non-combatants (support_ship_brain.gd:297).
   - Why they are not needed: the dedicated `_on_boss_escort_spawned` handler never reads them.
   - Also: "disconnects where the orphan signal is disconnected" points at nothing. ScoreTracker never disconnects the orphan signal (score_tracker.gd:76-79).
   - Fix: drop both writes (or make them after `add_child`, with the Support Ship consequence stated), and drop the disconnect clause.

8. **minor — the fortress breaks a recorded ENEMIES_CLEARED rule without recording an exception (t7, t10, t14).**
   - The rule: Ph10 as-built recorded that "every other persistent-ordnance enemy stays out of `ENEMIES_CLEARED` sections, the Carrier included", with the
     Heavy Gunship as the single bounded exception (DECISIONS.md:3822-3825).
   - The conflict: the fortress's `ROCKET_BATTERY` builds `persist: true` pools (rocket_battery_mount.gd:42-53) and lives in `station_assault`, an
     ENEMIES_CLEARED section.
   - What the plan does: t10 bounds the tail (`death_duration` + 6 s + 0.5 s), but the planned Ph11 "Changes to earlier decisions" (DECISIONS.md:4358-4373)
     does not list the exception, and no `test_engagement_deadline.gd` row names it.
   - Fix:
     - record the fortress as a second bounded exception, with its rocket term;
     - add a source / deadline row so a later persistent-ordnance boss mount in an ENEMIES_CLEARED section is a decision, not an accident.

9. **minor — retiring the station breaks two sanity pins in the lifetime test (t11).**
   - `test_enemy_bullet_lifetime.gd` pins the slowest shipped speed at exactly 150 px/s, `StationGunnery.new()`'s fallback (:84-90, :140-146). It pins the
     derived `max_time` at `ceil(2274 / 150) + 2 == 18.0` (:149-158).
   - §2.11 says only "drop station gunnery speeds" (3-plan.md:561). Deleting `StationGunnery` raises the minimum (the fortress core ring is 210, the radial
     default 220), so both sanity assertions fail.
   - Fix: state the new intent, e.g. "re-pin the slowest source to its new value; the shipped `enemy_bullet.tscn` 18 s / 2400 px stays ≥ the re-derived
     numbers", so the agent re-derives instead of deleting the check.

10. **minor — t10 row (b) cannot wait 240 s at 1× inside a 4.5 s allotment (t10).**
    - `_wait_enemies_cleared` is a wall-clock deadline (level_director.gd:159-190).
    - Row (b), "with the fortress never killed, the timeout frees the fortress and its escort container" (3-plan.md:535), needs the replay to override
      `enemies_cleared_timeout` on its built section. The 240 s stays pinned by `test_station_assault_section.gd`.
    - Fix: say so explicitly. Otherwise the gate-time allotment and the row contradict each other.

11. **minor — "killing the hangar stops the drones" is barely reachable while its generator lives (t8).**
    - The hangar is vulnerable only during OPENING, 0.8 s (`door_seconds`), then closes at once (§2.2, 3-plan.md:211-212). That happens once per 12–14 s.
    - The north bubble absorbs the first 120 points, about 3 default bullets (§2.5.4). With 4–5 default shots per window, about one 50-damage hit lands per
      window, so 300 HP takes ~6 windows (~75 s).
    - `CarrierHangars` holds the doors OPEN after launch for `door_hold_seconds` (carrier_hangars.gd:5-6). `ReinforcementBay` has no such hold.
    - Fix: add an `open_hold_seconds` export (Carrier parity) and a time-to-kill feasibility row, or state that the generator must die first and why.

12. **minor — the ring-gap fairness row checks the widest point, so it cannot fail (t7).**
    - "Gap angular width at `max_radius` ≥ 2 × the player hurtbox diameter" (3-plan.md:458) is measured where the gap is widest: 50° at 640 px is about
      558 px.
    - A gap is narrowest at the smallest radius a player can stand at, the hull edge (176 + player radius).
    - Fix: evaluate the inequality there. That is a row that can fail.

13. **minor — the spread cannon engages beyond its rounds' reach (t3).**
    - `fire_range` 520 (3-plan.md:264-265), but the Scatter round ends at `max_distance` 450 (scatter_round.tscn:13), about 478 from the mount with its muzzle
      offset.
    - Fix: set `fire_range` ≤ ~420, or add a row `fire_range ≤ round max_distance + muzzle offset`.

14. **minor — an EMP Blast during the death sequence freezes the wreck for 5 s (t5).**
    - Death calls `suspend_ai()` (3-plan.md:325), after which `answers_emp()` = `is_ai_driven()` is false (base_enemy.gd:170-171, 239-240).
    - `EMPBlastModule` then process-disables the still-`enemies` wreck (emp_blast_module.gd:39-46, 67-75). That pauses `_death_timer` and `BossDeathSequence`,
      and holds `station_assault` 5 s longer. The station had the same gap; the fortress should not inherit it.
    - Fix: `answers_emp()` true while `is_dying()`, with `apply_emp` a no-op then. Add one row.

15. **minor — movement row 3 asserts something the selection rule does not guarantee (t6).**
    - Row 3 says the new station point is "farther from the player's predicted position than the old one" (3-plan.md:419-420).
    - The rule picks the farthest of the 8 candidates that are ≥ 250 px from the current point. When the current point is already the farthest, the winner is
      nearer. Example: player predicted at anchor + (−400, 0) and current at (+360, 0) (760 px); the best eligible neighbour at 45° is ≈ 701 px.
    - Fix: assert the rule itself: the farthest eligible candidate, inside the zone, ≥ 250 px away.

16. **minor — the §25 row is path-dependent at `critical` (t5, t8).**
    - `critical` declares REINFORCEMENTS through the hangar surge (3-plan.md:352, 357, 482). The surge is a no-op when the hangar is already dead, so
      "changed keys ⊇ declared" fails on that path.
    - The ≥ 2 rule still holds (MOVEMENT, ATTACKS, VISUALS).
    - Fix: pin the §25 row's scripted path to a live hangar, and add a dead-hangar row asserting ≥ 2 observed changes. Or give `critical` a
      reinforcement change that does not depend on the hangar.

17. **minor — some tasks are missing sections they need (t6, t8, t5).**
    - t6's facing strength counts batteries "with a live shield" (§2.5.4), and its row 7 is the EMP rule (§2.5.6). It lists neither.
    - t8 scuttles in the death order of §2.5.3 and uses "engaged" from §2.6. It lists neither.
    - t5 needs §2.2 (finding 1).
    - Fix: add `2.5.4` and `2.5.6` to t6, `2.5.3` and `2.6` to t8, and `2.2` to t5.

18. **minor — t9 and t6–t8 edit the same scene with no ordering between them (t9).**
    - t9 depends only on t5, and §3 says it "may run beside t6–t8" (3-plan.md:642). It wires exports into `space_fortress.tscn`, which t6–t8 also edit
      (HullBeams, PulseRing, Bays, Thrusters).
    - On one branch this is ordering, not concurrency, but scene merges are fragile.
    - Fix: make t9 depend on t8, or limit it to PNGs plus the texture-export lines, and say which.

19. **minor — t4 understates what the move involves (t4).**
    - The `.uid` sidecar: `git mv` must move `station_death_sequence.gd.uid` as well, and the station scene's `ext_resource` path (space_station.tscn:13) must
      follow. Otherwise the UID-integrity gate trips.
    - "Byte-identical" cannot survive t11 as written: the script holds `var _station: SpaceStation` and casts `get_parent() as SpaceStation`
      (station_death_sequence.gd). The duck-typed host contract §2.4 describes needs those to change (and the "not a SpaceStation" warning).
    - Fix: say "behaviour-identical" and list these edits.

20. **minor — inconsistencies in labels and wording (t2, t14).**
    - Squad sharing: t2's description says "one shared SquadController per launch", while §2.2 says "per payload scene (the CarrierHangars rule)".
      `CarrierHangars` caches one per payload across all launches (`_squad(path)`). Pick one.
    - Owner-choice numbers collide across phases: Ph10's "owner choice 4" (hangar hittable) and "owner choice 7" (Support Ship ward) already sit in
      DECISIONS.md. t14 should write "Ph11 owner choice N".
    - Choice 6 reads "the player's EMP Blast", but the `apply_emp` override scales every EMP source. Say "every EMP".

## Task-level summary

| Task | Complexity | Verdict |
|---|---|---|
| t1 | medium | OK |
| t2 | large | OK (finding 7, squad wording 20) |
| t3 | medium | OK (findings 6, 13) |
| t4 | small | OK (finding 19) |
| t5 | large | needs `t2` dependency + §2.2 (finding 1); findings 14, 16 |
| t6 | large | sections (finding 17); row 3 (finding 15) |
| t7 | large | density row (finding 3), gate arity (finding 4), fairness (findings 6, 12), ENEMIES_CLEARED exception (finding 8) |
| t8 | medium | sections (finding 17), hangar feasibility (finding 11) |
| t9 | large (art) | ordering (finding 18) |
| t10 | medium | timeout override (finding 10) |
| t11 | large | acceptance grep (finding 2), lifetime pins (finding 9) |
| t12 | medium | in scope (recorded Ph9 / Ph10 debt); fence-post path (finding 5) |
| t13 | medium | OK; hard counts and sites match `test_sector_hub_patrol.gd`:614, :1070, :1275, :1417, :1953 |
| t14 | medium | OK; headings "6. Out of scope" / "7. Requirements coverage" exist |

Complexities are otherwise right. t5, t7 and t11 are each at the top of a one-session task; the Phase 10 Carrier shell and weapons tasks were the same size
and landed.

## Spot-check by the dispatching run

The dispatching run (not the reviewer) re-checked the blocking claims and two minor ones against the code before recording the verdict:
- Finding 1: `tasks.json` t5 `dependsOn` is `["t1","t4"]` and its `planSections` omit `2.2`, while §2.5.3 calls `reinforcements.scuttle_all()` and frees the escort container. Confirmed.
- Finding 2: the §2.11 grep matches `open_space/scenes/levels/sector_hub.tscn`, `open_space/scenes/mission_select_hubs/space_stations/fortuna_station.tres` and `open_space/scenes/mission_data/space_stations/fortuna_station/…`. Confirmed.
- Finding 3: §2.7 measures density only over 20 s of `batteries` with the stub at the view centre. Confirmed.
- Finding 4: `turret_mount.gd:279` calls `telegraph_gate.call()` with no arguments. Confirmed.
- Finding 7: `base_enemy.gd` `_ready()` copies `counts_toward_wave_clear` / `counts_as_escape` from the config. Confirmed.

Verdict recorded in `review.json`: CHANGES_REQUESTED.
