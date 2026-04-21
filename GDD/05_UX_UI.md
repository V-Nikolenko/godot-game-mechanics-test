# VOID BREACH — Game Design Document
## 05 · UX / UI

---

## Design Principles
1. **Minimal HUD:** Only show what the player needs right now.
2. **No pause-menu map:** Spatial knowledge is part of the skill expression.
3. **Contextual UI:** Information appears when relevant; disappears when not.
4. **Alerts over tutorials:** The game teaches through visual/audio feedback, not text pop-ups.

---

## HUD — Open Space

| Element | Position | Behavior |
|---|---|---|
| Ship Hull Bar | Top-left | Always visible |
| Ship Shield Bar | Top-left (below Hull) | Flashes when taking damage |
| Missile Count | Top-left (below Shield) | Icon × count |
| Charged Laser Cooldown | Top-center (when active) | Radial cooldown indicator |
| Mini-map / Sector View | Bottom-right | Shows known area, enemy indicators, objective markers |
| Beacon Status Indicator | Context — near beacon | Glows when approaching inactive beacon |
| Key Inventory | Bottom-left | Key icon × count; only visible when keys are held |

---

## HUD — Assault

| Element | Position | Behavior |
|---|---|---|
| Ship Hull Bar | Top-left | Simplified — bar only |
| Ship Shield Bar | Top-left | Below hull |
| Alert Indicator | Full-screen edge | Colored flash (Red/Yellow) on relevant screen edge |
| Alert Object | Incoming object | Arrow pointing from edge; color matches alert |
| Missile Count | Top-right | Icon count |
| Score / Progress | Top-center | Distance to target OR time remaining |

### Alert System — Visual Spec
- **Red Alert:** Screen edge pulses Red; icon of incoming threat appears 2+ seconds early
- **Yellow Alert:** Screen edge flashes Yellow; same early warning
- Alerts stack (multiple simultaneous alerts show multiple directional indicators)
- Sound design: distinct audio stings for Red vs Yellow — players learn the audio cue faster than the visual

---

## HUD — Land Mission

| Element | Position | Behavior |
|---|---|---|
| Health Bar | Top-left | Full bar; overflow section shown when temporary booster active |
| Equipped Weapon | Bottom-right | Icon of current weapon |
| Grenade / Mine Count | Bottom-right | Below weapon; icon × count |
| Active Modules (3 slots) | Bottom-center | Icon display; cooldown overlays per-module |
| Key Count | Bottom-left | Only shown when keys held |
| Objective Reminder | Top-right (subtle) | Faint text; appears when player is idle for 10+ seconds |
| Damage Numbers | On enemy | Optional (accessibility setting) |
| Grenade Arc Preview | Dynamic | Shown while Slot 2 held; trajectory line + landing marker |

---

## Menus

### Main Menu
- New Game / Continue
- Settings
- Exit
- No credits cluttering the main screen (credits in Settings or post-game)

### Pause Menu
| Option | Available In |
|---|---|
| Resume | All modes |
| Module Loadout | Open Space only |
| Settings | All modes |
| Return to Open Space | Land Mission / Assault |
| Quit to Main Menu | All modes |

**Module Loadout is not available during missions** — this is intentional. Loadout decisions are made between missions, creating meaningful commitment.

### Settings (key options)
- Controls remapping
- Damage numbers toggle (on/off)
- Alert sound volume (separate from SFX)
- Colorblind mode for Alert system (Red/Yellow → shapes/icons fallback)
- Camera shake intensity
- Text size

---

## Map System

### Open Space Map
- Revealed by exploration (fog of war)
- Beacons appear as nodes; inactive = dim, active = lit
- Sector boundaries shown; locked gates shown with icon
- Sub-mission locations marked after discovery
- Fast travel: select active beacon → confirm → instant travel

### Land Mission Map
- **No map** — intentional design choice
- Missions are compact enough that spatial memory suffices
- Objective compass (direction only, not distance) available as accessibility option

---

## Module Loadout Screen

Accessed from pause menu in Open Space.

### Layout
- 3 (or 4–5 if upgraded) active slots displayed prominently
- All discovered modules listed below in a grid
- Each module shows: Icon, Name, 2-line description, cooldown stat
- Drag-and-drop or directional-select to equip
- Currently equipped modules are highlighted in slot view

**Design rule:** Players should be able to swap a full loadout in under 30 seconds.

---

## Fragment Collection UI

When a fragment upgrade is picked up:

```
[Item Icon]  "Shield Upgrade Fragment"
             ██████░░  2 / 4
             "2 more to upgrade your maximum shield."
```

- Shown as a brief overlay (3 seconds)
- Fragment progress tracked in Upgrade Summary (accessible from pause in Open Space)
- Full upgrade earned when all fragments found — plays distinct audio and visual

---

## Narrative UI

- **No dialogue boxes during combat** — all voiced NPC communication happens in safe spaces or before combat starts
- **Companion relationship: no visible meter** — relationships are communicated through companion dialogue tone only
- **Point of No Return warning:** Full-screen overlay with clear text before entering final mission. Player must confirm twice.
- **Post-game summary:** After final mission, shows upgrade completion %, companion outcome, and hints about true ending if not achieved

---

## Accessibility Priorities
1. Colorblind mode for all color-coded systems (Alert, Health bars, Key colors)
2. All timed UI (alerts, HUD popups) have configurable durations
3. Grenade trajectory preview cannot be disabled — it's a core UI feature, not optional
4. Text contrast meets WCAG AA minimum in all UI contexts
