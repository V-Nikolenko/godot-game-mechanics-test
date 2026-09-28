# Enemy rework, phase 1 — sources

Merged and de-duplicated from `docs/plans/cmufklb100001p92xs1ey2fb1/2-research.md` §2. No
escalated task under this epic (only `t10-brain-mover`) ran its own separate research pass — its
`1-context.md` draws on the epic's own research instead.

| Source (URL) | What it contributed | Where it shows up in the build |
|---|---|---|
| https://www.red3d.com/cwr/steer/gdc99/ (Reynolds, "Steering Behaviors For Autonomous Characters") | Arrive's slowing-radius shape and pursuit's `T = D·c` lookahead scaling. | `Steering.arrive`/`hold_position` size their slowing radius from the mover's own deceleration; the Drone Interceptor's `dash_prediction_time` is a fixed instance of the same pursuit idea, kept unchanged in the port. |
| https://andrewfray.wordpress.com/2013/02/20/steering-behaviours-are-doing-it-wrong/ | Warning that weighted-sum blending of steering behaviours cancels and stalls with few, individually-visible agents (unlike large flocks). | `EnemyMover` takes **one** primary `request_velocity()` per step plus an *offered* additive `add_nudge()`, rather than a weighted blend — the design explicitly avoids the cancellation failure mode this source describes. |
| https://andrewfray.wordpress.com/2013/03/26/context-behaviours-know-how-to-share/ | Context-steering (interest/danger maps per heading slot) as the more robust alternative to weighted sums. | Explicitly deferred — noted in the research as "premature before hazards exist"; left on the roadmap for the phase that adds hazard perception. |
| https://www.gamedeveloper.com/programming/shooting-a-moving-target ; https://itch.io/devlog/34576/predictive-aim-for-assisted-and-ai-targeting.amp | Closed-form quadratic lead-target intercept, with an explicit no-solution branch. | `TargetInfo.intercept()`'s quadratic solve and its `{ok, point, time}` failure contract. |
| https://github.com/townofdon/predictive-aim ; https://www.tumblr.com/askagamedev/119049347621/how-exactly-do-developers-go-about-making-ai | "A 100% accurate AI is not fun" — blend intercept and direct aim on a 0–1 accuracy knob, or add a deliberate miss offset. | `TargetInfo.aim_direction(from, shot_speed, accuracy)`'s lerp between direct and intercept aim; `accuracy` on the aimed/gatling patterns, defaulted to `0.0` (today's exact behaviour) everywhere. |
| https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationagents.html | Godot's own intent/locomotion split: `NavigationAgent2D.set_velocity(intent)` → `velocity_computed(safe_velocity)` callback → `velocity = safe_velocity; move_and_slide()`. | Precedent for the exact slot `AssaultCorridorConstraint.filter(position, desired)` occupies between `EnemyMover`'s desired velocity and its one `move_and_slide()`. |
| https://saltmire.github.io/godot-4-object-pooling-vs-instantiate.html ; https://docs.godotengine.org/en/stable/classes/class_visibleonscreennotifier2d.html | Object pooling pays off above ~20 spawn/free per second and requires disciplined `reset()`; `VisibleOnScreenNotifier2D` reports `false` on its first frame and is camera-bound. | Confirms enemy bullets should stay pooled, and that screen-visibility is unfit as a projectile lifetime rule — `ProjectileLifetime` uses `max_time`/`max_distance`/`world_rect` instead, and arms lazily so an unpooled shot (the sniper's) still gets a correct lifetime without a mandatory `reset()`. |
| https://gut.readthedocs.io/en/v9.5.0/Simulate.html ; https://gut.readthedocs.io/en/latest/Awaiting.html ; https://docs.godotengine.org/en/stable/classes/class_randomnumbergenerator.html ; https://docs.godotengine.org/en/stable/tutorials/physics/physics_introduction.html | GUT's `simulate()` drives `_process`/`_physics_process` on a fixed delta but never fires `Timer` nodes; a seeded `RandomNumberGenerator` gives a reproducible draw sequence. | Brains tick via accumulated `delta` in `tick(delta)`, never a `Timer`; every brain owns a seedable `rng` (`rng_seed`, 0 = randomize) instead of drawing from the global RNG. |
| https://pixeljam.itch.io/nova-drift/devlog/432409/enemies-20-part-2 ; https://steamcommunity.com/app/858210/discussions/0/3193616250031397466/ ; https://blog.playstation.com/archive/2013/06/11/galak-z-reinvents-the-16-bit-space-shooter-on-ps4/ ; https://shmups.wiki/library/Boghog's_bullet_hell_shmup_101 | Free-roam enemies that pursue in world space tend to loiter or circle just off-screen without an explicit re-entry rule; shmups rely on a dead zone and learnable, deterministic patterns. | Motivated the Assault corridor's soft/hard-band velocity filter (rather than a bare position clamp) and the "no `randf()` for attack ordering" precedent the space-station family already set, which this phase's `AttackController` extension does not disturb. |

**Tried and unreachable or unusable** (recorded so a later phase doesn't re-attempt the same dead
end): *Game AI Pro 2* ch. 18 "Context Steering" and *Game AI Pro 3* ch. 33 "Using Your Combat AI
Accuracy to Balance Difficulty" — both binary/PDF fetches returned 0 bytes with no PDF tooling
available; the Fray blog posts above stand in for the first. The Galak-Z AI talk from
glenndoren.com — expired TLS certificate, proxy returned 422. GDC Vault Galak-Z talks — found, not
opened, and not about AI. No citable Everspace or Luftrausers developer statement on despawning
rules was found.

**Judgement calls with no citable source** (labelled as such in `2-research.md` and carried into
the plan unchanged):
- All Phase 1 starting numeric defaults not already present in a shipped config or resource: the
  corridor's `entry_speed` (60 px/s), `soft_band` (120 px), `hard_band` (450 px, the one number
  IDEAS §34 itself supplied) and `edge_pressure` (200 px/s); the Drone Interceptor's Open Space
  `dash_max_distance` (1600 px, "a little more than a 1280 px screen width plus the orbit radius").
- `ProjectileLifetime`'s derived `EnemyBullet` defaults (`max_time = 18 s`, `max_distance = 2400
  px`) are not judgement — they are computed from the shipped rect diagonal and the slowest
  shipped enemy-bullet speed found by source sweep (§2.9 of the plan), corrected during round-1
  review (F2) after the first derivation used a wrong minimum speed.
