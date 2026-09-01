# Sidescroller Tilesets — PixelLab Reference

Generate platform tiles for 2D platformer/sidescroller games with side-view perspective.

---

## Tool: `create_sidescroller_tileset`

Creates 16 Wang tiles (4×4 grid, 128×128px spritesheet) optimized for side-view platformers.

### Key Parameters

| Parameter | Default | Range | Purpose |
|---|---|---|---|
| `lower_description` | required | string | Platform material ("stone brick", "wooden planks", etc.) |
| `transition_description` | required | string | Surface decoration ("moss", "grass", "snow", "cracked edge") |
| `transition_size` | 0.0 | 0.0–0.5 | How much surface layer appears. 0=none, 0.25=light, 0.5=heavy |
| `tile_size` | {w:16,h:16} | 16 or 32 | Tile dimensions. **Use 32×32 for our games** |
| `outline` | null | lineless/selective/single color | **Always use "lineless"** (project preference) |
| `shading` | null | flat/basic/medium/detailed/highly detailed | "medium shading" recommended |
| `detail` | null | low/medium/highly detailed | "medium detail" recommended |
| `base_tile_id` | null | UUID | Reference tile from previous tileset for visual consistency |
| `tileset_adherence` | 100 | 0–500 | Structure strictness to reference. Higher = closer match |
| `tileset_adherence_freedom` | 500 | 0–900 | How much AI can deviate. Lower = more rigid |
| `tile_strength` | 1.0 | 0.1–2.0 | Pattern consistency within tileset |
| `text_guidance_scale` | 8 | 1–20 | How strongly text description influences output |
| `seed` | null | integer | Reproducible generation (single tileset only, not cross-tileset) |

### Output

- **PNG**: 128×128px spritesheet (4×4 grid of 32×32 tiles)
- **JSON**: Metadata with bounding boxes, corner data, connection rules
- **Transparent background** — suitable for layering over game background
- **Flat surfaces** — no slopes, optimized for platformer collision

---

## Creating Connected/Matching Tilesets

### The `base_tile_id` System

Only mechanism for cross-tileset visual consistency. Workflow:

1. Create first tileset → get `base_tile_ids.base` from response
2. Pass that ID as `base_tile_id` in next tileset creation
3. New tileset inherits visual DNA from reference

### Adherence Settings for Matching

Tested combinations (from our experiments):

| Setting | adherence | freedom | Result |
|---|---|---|---|
| Default | 100 | 500 | Very loose — tilesets look quite different |
| Medium | 300 | 200 | Closer match, still noticeable differences |
| Tight | 400 | 100 | Very close to original, minimal variation |

**For complementary tilesets** (same material, different surface):
- Use `base_tile_id` from first tileset
- Keep `lower_description` identical
- Change only `transition_description`
- Use adherence 300–400 / freedom 100–200

**For contrasting tilesets** (different look, same game):
- Use `base_tile_id` for some consistency
- Different `lower_description` + `transition_description`
- Use adherence 100–200 / freedom 300–500
- Keep same `outline`, `shading`, `detail` settings

### Tips for Better Consistency

- **Same descriptions help**: Shared vocabulary ("ancient", "weathered") maintains tonal consistency
- **Generate multiple variants**: Use different seeds, cherry-pick best match
- **transition_size matters**: 0.25 vs 0.5 dramatically changes the look even with same description
- **Cannot upload custom style image** — `base_tile_id` is the only reference mechanism
- Aseprite plugin recommended for manual fine-tuning after generation

---

## Wang Tile Corner System — CRITICAL

Each tile has 4 corners: NW, NE, SW, SE.

### IMPORTANT: Terrain encoding

From PixelLab docs:
```json
"lower": "rock"                    // = SOLID platform material
"upper": "transparent background"  // = AIR / transparent
```

**"lower" = SOLID, "upper" = AIR.** This is counterintuitive! Don't confuse with visual top/bottom.

The `transition_description` controls the decorative edge that appears at the boundary between solid and air.

### Frame index formula

Spritesheet is 4×4 grid. Frame = `(bounding_box.y / tileSize) * 4 + (bounding_box.x / tileSize)`

### Verified Platformer Role Mapping (tested in Relic Rush)

| Platformer Role | Wang Tile | Frame | Corners (NW,NE,SW,SE) | Visual |
|-----------------|-----------|-------|------------------------|--------|
| **TOP_LEFT** | wang_14 | 13 | up,up,up,low | Only SE solid → outer top-left corner |
| **TOP** | wang_12 | 3 | up,up,low,low | Air above, solid below → top surface |
| **TOP_RIGHT** | wang_13 | 0 | up,up,low,up | Only SW solid → outer top-right corner |
| **LEFT** | wang_10 | 1 | up,low,up,low | Air left, solid right → left edge |
| **CENTER** | wang_0 | 6 | low,low,low,low | All solid → interior fill |
| **RIGHT** | wang_5 | 11 | low,up,low,up | Solid left, air right → right edge |
| **BOTTOM_LEFT** | wang_11 | 8 | up,low,up,up | Only NE solid → outer bottom-left |
| **BOTTOM** | wang_3 | 9 | low,low,up,up | Solid above, air below → bottom edge |
| **BOTTOM_RIGHT** | wang_7 | 15 | low,up,up,up | Only NW solid → outer bottom-right |

### 2-Row Platform Rendering (recommended for visual depth)

For a platform W tiles wide, render 2 rows:
- **Row 0** (top surface, where player walks): TOP_LEFT → TOP (repeat) → TOP_RIGHT
- **Row 1** (body extending down): BOTTOM_LEFT → BOTTOM (repeat) → BOTTOM_RIGHT

Physics body covers only row 0 (the collision surface). Row 1 is purely visual.

Special cases:
- **1 tile wide**: Row 0 = TOP, Row 1 = BOTTOM
- **2 tiles wide**: Row 0 = TOP_LEFT + TOP_RIGHT, Row 1 = BOTTOM_LEFT + BOTTOM_RIGHT

---

## Integration in Phaser (Sidescroller)

### Loading

```typescript
// boot.ts — load as spritesheet (4×4 grid)
this.load.spritesheet("tileset-stone", `${ASSET_BASE}/tileset-stone.png`, {
  frameWidth: 32, frameHeight: 32
});
```

### Platform Rendering with Wang Tiles

```typescript
// Frame constants (verified correct mapping)
const TF = {
  TOP_LEFT: 13, TOP: 3, TOP_RIGHT: 0,
  LEFT: 1, CENTER: 6, RIGHT: 11,
  BOTTOM_LEFT: 8, BOTTOM: 9, BOTTOM_RIGHT: 15,
} as const;

// Spawn platform with 2-row visual + invisible physics zone
private spawnPlatform(x: number, y: number, widthTiles: number) {
  const w = widthTiles * TILE;

  // Invisible physics zone (collision only)
  const zone = this.add.zone(x + w/2, y + TILE/2, w, TILE);
  this.platforms.add(zone);
  (zone.body as Phaser.Physics.Arcade.StaticBody).setSize(w, TILE);
  (zone.body as Phaser.Physics.Arcade.StaticBody).updateFromGameObject();

  // Visual tiles — 2 rows for depth
  for (let row = 0; row < 2; row++) {
    for (let col = 0; col < widthTiles; col++) {
      let frame: number;
      if (row === 0) { // Top surface row
        if (widthTiles === 1) frame = TF.TOP;
        else if (col === 0) frame = TF.TOP_LEFT;
        else if (col === widthTiles - 1) frame = TF.TOP_RIGHT;
        else frame = TF.TOP;
      } else { // Bottom body row
        if (widthTiles === 1) frame = TF.BOTTOM;
        else if (col === 0) frame = TF.BOTTOM_LEFT;
        else if (col === widthTiles - 1) frame = TF.BOTTOM_RIGHT;
        else frame = TF.BOTTOM;
      }
      this.add.image(
        x + col * TILE + TILE/2,
        y + row * TILE + TILE/2,
        "tileset-stone", frame
      );
    }
  }
}
```

---

## Chaining Example (Our Relic Rush Game)

```typescript
// Tileset 1: Main platform (dark temple stone + light moss)
create_sidescroller_tileset({
  lower_description: "ancient greek temple stone blocks, dark brown weathered marble bricks",
  transition_description: "cracked stone edge with small moss patches",
  transition_size: 0.25,
  tile_size: { width: 32, height: 32 },
  outline: "lineless",
  detail: "medium detail",
  shading: "medium shading"
})
// → base_tile_id: "c5ae1d1b-..."

// Tileset 2: Overgrown variant (same stone + heavy green moss)
create_sidescroller_tileset({
  lower_description: "ancient greek temple stone blocks, dark brown weathered marble bricks",
  transition_description: "thick green moss and small ferns growing on cracked stone surface",
  transition_size: 0.5,
  tile_size: { width: 32, height: 32 },
  outline: "lineless",
  detail: "medium detail",
  shading: "medium shading",
  base_tile_id: "c5ae1d1b-..."
})
```

---

## Common Pitfalls

- **transition_size: 0** = no visible surface layer at all, even with good description
- **Low adherence + high freedom** with `base_tile_id` = tilesets look completely different
- **Different outline/shading/detail** between tilesets = guaranteed style mismatch
- **Seed does NOT help cross-tileset** — only reproduces same single tileset
- **No style image upload** — cannot reference arbitrary PNG, only `base_tile_id` from PixelLab
