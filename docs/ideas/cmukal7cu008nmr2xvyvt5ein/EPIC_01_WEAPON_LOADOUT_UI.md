# Epic 1 — Weapon Loadout & Combat Selection UI

## Goal

Rework the weapon loadout menu and in-flight weapon selection so the player has a compact, understandable combat loadout:

- **3 Main Weapons**
- **3 Sub-Weapons**

This epic is intentionally focused on the **loadout UI, assignment, persistence, and combat cycling**.

Do not expand this epic into the implementation of individual weapon mechanics. The weapon epic will handle those separately.

Before implementation, inspect the current weapon menu, weapon lists, selection logic, weapon state machine, progression/unlocks, save/load, and input mappings.

---

# 1. Current menu → new layout

The current menu contains two large collections:

- Main Weapons
- Sub-Weapons

Keep those collections, but move them lower in the menu.

At the current prominent weapon-selection area, introduce six dedicated loadout frames:

```text
MAIN WEAPONS

[ Slot 1 ] [ Slot 2 ] [ Slot 3 ]


SUB WEAPONS

[ Slot 1 ] [ Slot 2 ] [ Slot 3 ]
```

These frames represent the weapons available for quick selection during combat.

---

# 2. Assignment workflow

The player selects one of the six loadout frames.

Then the player selects a compatible weapon from the appropriate collection below.

Example:

```text
MAIN LOADOUT

[ Pulse Cannon ] [ Scatter Cannon ] [ Empty ]


SUB LOADOUT

[ Harpoon ] [ Null Burst ] [ Empty ]


--------------------------------

MAIN WEAPONS
Pulse Cannon
Scatter Cannon
Mining Laser
Capacitor Gun
...

SUB WEAPONS
Harpoon
Rocket Launcher
Drones
Minecaster
...
```

Selecting a Main slot must only allow assigning Main Weapons.

Selecting a Sub slot must only allow assigning Sub-Weapons.

---

# 3. Empty slots

Empty loadout slots should always have a proper visible frame.

They should look like intentional UI elements, not missing content.

The empty frame should use the existing weapon/module frame language.

---

# 4. Current-loadout visual hierarchy

The top loadout frames should have stronger visual prominence than the complete weapon lists.

The player should immediately understand:

```text
CURRENT LOADOUT
↓
what I can quickly use during combat

FULL COLLECTION
↓
everything I have unlocked
```

---

# 5. In-flight weapon cycling

The equipped loadout feeds the combat weapon cycling system.

## Main Weapons

`E` cycles:

```text
Main Slot 1
↓
Main Slot 2
↓
Main Slot 3
↓
Main Slot 1
```

## Sub-Weapons

`Q` cycles:

```text
Sub Slot 1
↓
Sub Slot 2
↓
Sub Slot 3
↓
Sub Slot 1
```

Do not add mouse-wheel cycling.

Do not add extra direct weapon hotkeys.

Keep combat selection deliberately compact.

---

# 6. LoadoutManager

If there is no appropriate existing system, introduce a small reusable `LoadoutManager` or equivalent abstraction.

It should own:

- 3 Main slots;
- 3 Sub slots;
- current Main index;
- current Sub index;
- assignment validation;
- unlocked weapon references;
- persistence;
- Q/E cycling.

The manager should know **what is equipped**, not how weapons behave.

Weapon mechanics remain in the weapon system.

---

# 7. Duplicate weapon policy

Inspect the existing progression/inventory rules before deciding.

Preferred default:

> the same weapon cannot occupy multiple active slots.

For example:

```text
Main:
Pulse Cannon
Pulse Cannon
Scatter Cannon
```

should normally be rejected.

If the current game explicitly supports duplicates, preserve the existing rule instead.

---

# 8. Unlocked weapon collection

The lower lists remain the complete collection of discovered weapons.

They should:

- show unlocked weapons;
- allow assigning them to loadout slots;
- remain browseable;
- preserve the existing visual language.

Do not duplicate weapon definitions simply to support the loadout UI.

---

# 9. Persistence

The selected loadout must persist through the existing save/progression architecture.

Persist:

- Main Slot 1;
- Main Slot 2;
- Main Slot 3;
- Sub Slot 1;
- Sub Slot 2;
- Sub Slot 3.

If a weapon is no longer available because of an existing progression rule:

> invalidate that slot cleanly and show it as empty.

Do not silently assign another weapon.

---

# 10. UI interaction

The player should clearly see:

- which slot is selected;
- whether it is Main or Sub;
- which weapon is currently assigned;
- which list item is being assigned;
- which slots are empty.

Use the existing focus/selection animation and frame treatment wherever possible.

Do not redesign the entire UI language.

---

# 11. Pixel-art / UI assets

Inspect existing:

- weapon icons;
- module icons;
- selection frames;
- empty-slot frames;
- HUD weapon indicators.

Use **PixelLab MCP** for genuinely new pixel-art icons or frames.

New assets must match the existing style:

- pixel resolution;
- palette;
- silhouette language;
- lighting;
- outline treatment;
- frame conventions.

Do not generate unnecessary assets if existing ones can be reused.

---

# 12. Testing

Add/update tests for:

- exactly 3 Main slots;
- exactly 3 Sub slots;
- empty-slot rendering;
- selecting a slot;
- assigning a compatible weapon;
- rejecting incompatible weapon types;
- duplicate handling;
- Q cycling;
- E cycling;
- persistence;
- invalid saved weapon references;
- loadout changes not altering weapon behavior.

---

# 13. Implementation order

1. Inspect current weapon menu.
2. Add six loadout frames.
3. Move current weapon lists lower.
4. Add slot selection.
5. Add weapon assignment.
6. Add `LoadoutManager` or extend the current equivalent.
7. Connect Q/E cycling.
8. Add persistence.
9. Polish UI.
10. Generate only missing pixel-art assets through PixelLab MCP.

---

# 14. Expected result

The menu should make the player's combat loadout immediately obvious:

```text
MAIN
[1] [2] [3]

SUB
[1] [2] [3]

-----------------
Full Main List
Full Sub List
```

The player enters gameplay knowing exactly which six combat tools are available through quick cycling.
