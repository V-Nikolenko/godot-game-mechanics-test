# Research — presenting a lock, and adding one to a shipped save format

Three questions from `1-context.md`: hide vs. grey out a locked item, what to do with saves that
predate the gate, and whether an empty starting loadout is acceptable.

| Finding | Tradeoff | Typical values / shape | Source |
|---|---|---|---|
| Both "hide" and "grey out" are standard; the usual split is **hide narrative/spoiler content, grey out stat- or progression-gated content**, because a greyed row tells the player their progression choices were meaningful and what to aim at. | Greying costs screen space and can read as nagging if the list is long; hiding reduces clutter but makes players believe the game has less content than it does. | Practitioners recommend the greyed row carry its requirement inline — e.g. `(Charm > 50%)` — otherwise it is a dead end with no call to action. | [Choice of Games forum — "Hidden or Greyed out?"](https://forum.choiceofgames.com/t/hidden-or-greyed-out/2182) |
| A greyed entry keeps items at a **fixed position in the menu**, which preserves muscle memory; a list that grows as you unlock reshuffles under the player's fingers. | Fixed positions mean the cursor can land on things you cannot pick, so confirm needs a defined no-op rather than a silent nothing. | Applies directly: `SLOT_MODULES` is already display-ordered, so a fixed 6-row weapons list beats one that grows 1→6. | **Weak citation — flagged in review.** The muscle-memory wording came from a developer comment surfaced in search ("a greyed-out menu option … lets items always be at the same place in the menu, aiding muscle memory") that I could not open to verify. [uichallenges.design](https://www.uichallenges.design/guides/game-ui-design) supports only the weaker claim that both hiding and heavy greying are accepted practice. Treat the fixed-position reasoning as a judgement call. |
| Visible-but-locked content is a standard motivator: locked entries act as concrete near-term goals, which is most of the value an unlock system has at all. | Only pays off if the player can see *how* to get it; a locked row with no stated source is worse than no row. | — | [gamedesignskills.com — Game progression systems](https://gamedesignskills.com/game-design/game-progression/), [Game Pill — designing progression and rewards](https://dev.to/gamepill/level-up-the-art-of-designing-game-progression-and-player-rewards-2603) |
| When a game adds a requirement to something that used to be free, the shipped pattern is **migrate on load**: detect the old shape and grandfather existing state rather than revoking it. The cited devlog ignored the old completion flag and wrote new flags that take precedence, specifically so returning players kept what they had earned. | Grandfathering repairs the invariant silently — later readers of the save cannot tell earned-by-pickup from migrated. Acceptable when the alternative is confiscating a loadout the player is currently flying with. | Migration runs once, on first load of the new build, off data already in the file — no version stamp needed when the old state is self-describing. | [Bugnet — QA testing for save-game backward compatibility](https://bugnet.io/blog/qa-testing-for-save-game-backward-compatibility), [Power Network Tycoon devlog — legacy save file challenge](https://davidmadethis.itch.io/power-network-tycoon/devlog/982888/massive-endgame-update-conquering-the-legacy-save-file-challenge) |

## Judgement calls (no citable source)

- **An empty starting loadout is fine here.** Every one of the 15 modules is a pure additive bonus
  (`ShootingModule` = +65% fire rate, `ArmorPlatingModule`, `WarpModule` = a flag `DashState`
  reads), so a player with four empty slots flies, shoots and dashes normally. Same shape as
  `UpgradeState`, which starts with only `default` — except that unlike weapons there is no
  "basic module" the ship needs, so seeding a starter module would be inventing content rather
  than preserving it.
- **Do not filter the list, grey it.** Filtering would leave a fresh profile staring at a one-row
  list containing only "None", which reads as a broken menu rather than a progression system.
  Greying keeps all 15 modules visible as goals from minute one.

## What this rules out
- Hiding locked modules from `ModuleList` (the clutter argument does not apply — the longest slot
  has 6 rows against a `MAX_ITEMS` of 8).
- Dropping equipped-but-not-unlocked modules on load (confiscates a loadout mid-playthrough).
- Deleting the unlock store as dead code — the pickup, the signal and the save keys all exist, and
  `docs/superpowers/plans/2026-05-26-pickup-system.md` states pickups are the intended unlock path.
