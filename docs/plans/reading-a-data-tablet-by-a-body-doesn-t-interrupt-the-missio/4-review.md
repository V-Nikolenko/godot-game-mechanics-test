# Review: reading-a-data-tablet-by-a-body-doesn-t-interrupt-the-missio

VERDICT: CHANGES_REQUESTED

## Findings

### 1. Missing `updating-project-docs` skill step — real structural change, undocumented (Process / CLAUDE.md compliance)

The plan adds a brand-new top-level directory `global/interactables/` and a new shared class
`InfoLogInteractable` (`3-plan.md:21-31`) — exactly the class of change CLAUDE.md's "MANDATORY —
keep the docs current" section names ("adding... an entity, component, module, or mechanic"
requires invoking the `updating-project-docs` skill before finishing). The build sequence
(`3-plan.md:172-182`, steps 1-6) never mentions it, and neither does the "Out of scope" list. This
is not a cosmetic omission: `docs/architecture/modules/global.md`'s directory map (section 2,
`global.md:9-61`) and its "Pickups & resources" section explicitly enumerate `pickups/`,
`ship_modules/`, `components/` etc. as the same kind of flat top-level category this plan is
adding a new member of — leaving it unlisted is exactly the drift the skill exists to prevent, and
several sibling plans in this same repo (`docs/plans/*/3-plan.md`, e.g.
`no-pickup-or-menu-ever-calls-upgradestate-unlock-for-any-wea/3-plan.md`,
`move-code-built-contact-hitboxes-into-the-scenes-as-the-aste/3-plan.md`) do call the skill out
explicitly in their own build sequences for comparable changes. Add a doc-update step before
"Build sequence" step 6 (`bash /agent/verify.sh`).

## Things I checked and did not find a problem with

- **The sibling-task leak trap (the single most important thing to verify) — genuinely avoided.**
  Traced every test case in `3-plan.md:205-251` against `dialog_player.gd` and `pickup_base.gd`:
  - Cases 4 and 5 never reach `_read()`/`play()` at all — `_unhandled_input`'s own early returns
    (`_in_range.is_empty()` in case 4; `DialogPlayer.is_active` in case 5, pre-armed by the test)
    short-circuit before `_read()` is called.
  - Cases 6, 7, 8 call `_build_script()` directly, never `_read()` or `play()`.
  - Case 9 calls `_read()` with `message == ""`; `_read()`'s own guard
    (`if message.is_empty(): return`, `3-plan.md:83-84`) returns before `DialogPlayer.play()` is
    ever invoked — so unlike the sibling task's case 4, this doesn't even reach `play()`'s own
    empty-script guard (`dialog_player.gd:42-44`), it never calls `play()` at all. (The plan's own
    prose at `3-plan.md:245-251` slightly misdescribes this as "reaching `play()`'s call site... 
    which `play()` itself guards" — the guard that actually fires is `_read()`'s, one level up —
    but this is a narrative inaccuracy, not a functional one: no coroutine starts either way, and
    the actual behavior is *safer* than the plan's own description of it.)
  - No test case anywhere starts a real `play()` coroutine with a non-empty script. Confirmed this
    is the correct reading of the sibling review's trap by re-tracing `dialog_player.gd:36-92` and
    `dialog_box.gd`'s fade-in-tween-then-`line_finished` chain, and confirmed the precedent this
    plan leans on (`test_play_with_an_empty_script_is_ignored`,
    `tests/unit/test_dialog_player.gd:47-51`) really does exercise the exact same guard clause with
    an already-passing test.
- **`pickup_base.gd:36-49` (`_show_notification`) construction mirrored correctly** — `line.side`,
  `line.reveal`, `post_delay = 0.4`, `pause_gameplay = false` all match `_build_script()`
  (`3-plan.md:92-101`) field-for-field against the real enums in `dialog_line.gd:10-16` and
  `dialog_script.gd:11-15`.
- **`project.godot` claims verified**: `interact` bound to physical keycode 70 (F) at line 122;
  `2d_physics/layer_2="environment_interactable"` and
  `2d_physics/layer_3="environemnt_player"` (typo, not introduced by this plan) at lines 167-168;
  grep for `"interact"`/`'interact'` across `**/*.gd` returns nothing — the plan's "first user"
  claim holds.
- **Collision convention verified**: `open_space/scenes/entities/player/player_ship.tscn:215` and
  `assault/scenes/player/player_fighter.tscn:290` both set `collision_layer = 4` on the player
  body; all 9 `global/pickups/scenes/*.tscn` (checked `weapon_mode_unlocker_pickup.tscn`) set
  `collision_mask = 4`. The plan's choice of `collision_layer = 2` (`environment_interactable`,
  previously unused) / `collision_mask = 4` for the new scene is consistent with this and a
  reasonable, better-named alternative to reusing the pickups' anonymous layer 16.
- **`PlayerBase`/`PlayerStub` group membership**: `player_base.gd:56` (`_ready()` →
  `add_to_group("player")`) confirms `PlayerStub` (which `extends PlayerBase` and never overrides
  `_ready`, `tests/helpers/player_stub.gd:16`) really is in the "player" group, matching the
  plan's `_on_body_entered`/`_on_body_exited` test cases' premise.
- **`DialogTrigger` rejection is accurate**: `dialog_trigger.gd:19,31-32` confirms `play_once`
  defaults `true` and consumes on first `fire()`, and `script_resource` is a pre-built
  `@export`, not a runtime string — the plan's stated reasons for not reusing it both check out.
- **Epic/task scope verified against `BACKLOG.json:1360-1372`**: the task body matches the plan's
  "Done when" criteria word for word (prompt on approach, replay on every interaction, no
  `LogState` coupling, `DialogPlayer.is_active` guard, enter/exit/re-read test). The two "out of
  scope" deferrals — infiltration player wiring and any real placement — are correctly assigned
  to `log-records-can-be-placed-in-assault-and-infiltration-missio` and
  `test-logs-on-the-open-space-map-prove-both-log-types-work-en` respectively per
  `BACKLOG.json:1388-1405`.
- **Directory placement**: `global/interactables/` as a new flat top-level category is consistent
  with the existing convention shown in `docs/architecture/modules/global.md`'s directory map
  (`pickups/`, `ship_modules/`, `components/` are siblings, not nested under each other) — sound,
  modulo finding 1's doc-sync gap.
- **Art skip is justified, not dodged**: the task brief's own wording names three different
  physical dressings for one contract; baking in a sprite now would be thrown away by whichever
  later placement task (`log-records-can-be-placed-in-assault-and-infiltration-missio` /
  `test-logs-on-the-open-space-map-prove-both-log-types-work-en`) actually places an instance.
  Consistent with how `pickup_base.gd`/its subclasses separate base behavior from per-pickup
  dressing.
- **No CLAUDE.md convention violations found** beyond finding 1: no new signal is declared (arity
  rule N/A per the plan's own note, `1-context.md:65-69`, and confirmed — the script declares
  none); no per-frame logging added; no hand-typed/copied `uid://` anywhere in the plan; composition
  is respected (`Area2D` sibling of `PickupBase`, not a subclass of it, per the brief's own
  instruction).
- Test cases 1-3 assert real, falsifiable, non-tautological behavior (prompt visibility transitions,
  non-player filtering) directly against the shown `_on_body_entered`/`_on_body_exited` code, and
  case 9 is a genuine boundary case (empty message) that can actually fail if `_read()`'s guard
  were removed or reordered.

## Round 2

VERDICT: APPROVED

Round 1's sole finding is resolved: `3-plan.md:183-189` adds build-sequence step 7, invoking the
`updating-project-docs` skill and naming concrete targets — a row in
`docs/architecture/modules/global.md`'s directory map (alongside `pickups/`, `components/`,
`ship_modules/`) plus checking `docs/architecture/PROJECT.md` for a matching mention. This is
correctly placed after verification (step 6, `verify.sh`) and matches the precedent the round-1
finding cited from sibling plans.

Diffed the remainder of the file against every line-anchored quote in this review's round-1
"checked and did not find a problem with" section — design/rationale prose, rejected alternatives,
scene layout, all 9 test cases, risks, and out-of-scope list are unchanged apart from line-number
shifts caused by the step-7 insertion. No regression introduced by the edit.
