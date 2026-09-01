# PixelLab API v2 — Additional Endpoints (not in MCP)

These endpoints are NOT available through the PixelLab MCP server.
Call them directly via `curl` using the `PIXELLAB_API_KEY` from `.env`.

**Base URL:** `https://api.pixellab.ai/v2`
**Auth:** `Authorization: Bearer $PIXELLAB_API_KEY`
**Content-Type:** `application/json`

---

## Quick Reference

| Endpoint | Sync/Async | Best For |
|----------|-----------|----------|
| `animate-with-text-v3` | Sync | Add animations to existing sprites |
| `generate-ui-v2` | Async | UI elements (buttons, bars, frames) |
| `generate-image-v2` | Async | General pixel art from text |
| `generate-with-style-v2` | Async | Style-matched generation |
| `edit-images-v2` | Async | Edit existing pixel art |
| `image-to-pixelart` | Sync | Convert photos to pixel art |
| `remove-background` | Sync | Remove sprite backgrounds |
| `inpaint-v3` | Async | Region-based AI editing |
| `resize` | Sync | Smart pixel-art resize |
| `rotate` | Sync | Rotate sprite direction/view |

---

## Async Job Polling

Async endpoints return 202 with `background_job_id`. Poll until complete:

```bash
curl -s https://api.pixellab.ai/v2/background-jobs/{JOB_ID} \
  -H "Authorization: Bearer $PIXELLAB_API_KEY" | jq '.status'
```

When `status === "completed"`, images are in `.last_response.images[]` (array of base64 PNGs).

---

## 1. animate-with-text-v3 (SYNC)

Generate animation frames from a first frame + action description.
Returns array of base64 PNG frames directly.

**Pixel budget:** width × height × frame_count ≤ 524,288
**Frame count:** 4 (simple loops), 8 (walk/run), 16 (complex) — must be even

```bash
# Read first frame, call API, save frames
FRAME_B64=$(base64 -i sprite-south.png)

curl -s -X POST https://api.pixellab.ai/v2/animate-with-text-v3 \
  -H "Authorization: Bearer $PIXELLAB_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"first_frame\": {\"type\":\"base64\", \"base64\":\"$FRAME_B64\", \"format\":\"png\"},
    \"action\": \"walking forward\",
    \"frame_count\": 8,
    \"no_background\": true,
    \"seed\": 42
  }" | jq -r '.images[].base64' | while read -r img; do
    echo "$img" | base64 -d > "frame_$((++i)).png"
  done
```

| Parameter | Type | Required | Default | Notes |
|-----------|------|----------|---------|-------|
| `first_frame` | Base64Image | YES | — | Max 256×256 |
| `last_frame` | Base64Image | no | null | Guide endpoint pose |
| `action` | string | YES | — | e.g. "walking", "attacking", "idle breathing" |
| `frame_count` | int | no | 8 | 4-16, must be even |
| `no_background` | bool | no | null | Transparent frames |
| `seed` | int | no | null | Reproducibility |

---

## 2. generate-ui-v2 (ASYNC)

Generate pixel art UI elements — buttons, health bars, inventory frames, dialogue boxes.

```bash
curl -s -X POST https://api.pixellab.ai/v2/generate-ui-v2 \
  -H "Authorization: Bearer $PIXELLAB_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "description": "medieval stone button with gold trim, pressed and unpressed states",
    "image_size": {"width": 128, "height": 64},
    "no_background": true,
    "color_palette": "brown and gold"
  }' | jq -r '.background_job_id'
```

| Parameter | Type | Required | Default | Notes |
|-----------|------|----------|---------|-------|
| `description` | string | YES | — | 1-2000 chars |
| `image_size` | {width, height} | no | 256×256 | 16-792 × 16-688 |
| `no_background` | bool | no | null | Transparent |
| `concept_image` | {image, size} | no | null | Design guidance reference |
| `color_palette` | string | no | null | e.g. "brown and gold" (max 200 chars) |
| `seed` | int | no | null | Reproducibility |

---

## 3. generate-image-v2 (ASYNC)

General text-to-pixel-art. Returns multiple images based on size:
- ≤42px max dim → 64 images
- 43-85px → 16 images
- 86-170px → 4 images
- >170px → 1 image

```bash
curl -s -X POST https://api.pixellab.ai/v2/generate-image-v2 \
  -H "Authorization: Bearer $PIXELLAB_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "description": "glowing health potion bottle",
    "image_size": {"width": 64, "height": 64},
    "no_background": true
  }' | jq -r '.background_job_id'
```

| Parameter | Type | Required | Default | Notes |
|-----------|------|----------|---------|-------|
| `description` | string | YES | — | 1-2000 chars |
| `image_size` | {width, height} | YES | — | 16-792 × 16-688 |
| `no_background` | bool | no | null | Transparent |
| `reference_images` | array | no | null | Max 4 items, each {image, size, usage_description?} |
| `style_image` | {image, size} | no | null | Style reference |
| `style_options` | object | no | all true | {color_palette, outline, detail, shading} |
| `seed` | int | no | null | Reproducibility |

---

## 4. generate-with-style-v2 (ASYNC)

Generate pixel art matching the style of 1-4 reference images.

```bash
STYLE_B64=$(base64 -i existing-sprite.png)

curl -s -X POST https://api.pixellab.ai/v2/generate-with-style-v2 \
  -H "Authorization: Bearer $PIXELLAB_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"style_images\": [{\"image\":{\"type\":\"base64\",\"base64\":\"$STYLE_B64\",\"format\":\"png\"}, \"width\":64, \"height\":64}],
    \"description\": \"a warrior with a sword\",
    \"image_size\": {\"width\":64, \"height\":64},
    \"no_background\": true
  }" | jq -r '.background_job_id'
```

| Parameter | Type | Required | Default | Notes |
|-----------|------|----------|---------|-------|
| `style_images` | array | YES | — | 1-4 items, each {image, width, height} |
| `description` | string | YES | — | 1-2000 chars |
| `image_size` | {width, height} | YES | — | 16-512 × 16-512 |
| `style_description` | string | no | null | Text style hint (max 500) |
| `no_background` | bool | no | null | Transparent |
| `seed` | int | no | null | Reproducibility |

---

## 5. edit-images-v2 (ASYNC)

Edit existing pixel art with text instructions or a reference image.

**Frame limits by output size:**
- 32-64px → up to 16 frames (15 with reference)
- 65-80px → up to 9 (8 with reference)
- 81-128px → up to 4 (3 with reference)
- 129-512px → 1 (text only)

```bash
SPRITE_B64=$(base64 -i character.png)

curl -s -X POST https://api.pixellab.ai/v2/edit-images-v2 \
  -H "Authorization: Bearer $PIXELLAB_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"method\": \"edit_with_text\",
    \"edit_images\": [{\"image\":{\"base64\":\"$SPRITE_B64\"}, \"width\":64, \"height\":64}],
    \"image_size\": {\"width\":64, \"height\":64},
    \"description\": \"add a red cape\",
    \"no_background\": true
  }" | jq -r '.background_job_id'
```

| Parameter | Type | Required | Default | Notes |
|-----------|------|----------|---------|-------|
| `method` | enum | no | "edit_with_text" | "edit_with_text" \| "edit_with_reference" |
| `edit_images` | array | YES | — | 1-16 items, each {image, width, height} |
| `image_size` | {width, height} | YES | — | 32-512 × 32-512 |
| `description` | string | no | null | Required for edit_with_text |
| `reference_image` | {image, width, height} | no | null | Required for edit_with_reference |
| `no_background` | bool | no | null | Transparent |
| `seed` | int | no | null | Reproducibility |

---

## 6. image-to-pixelart (SYNC)

Convert regular images to pixel art. Output should be ~1/4 of input size.

```bash
PHOTO_B64=$(base64 -i photo.png)

curl -s -X POST https://api.pixellab.ai/v2/image-to-pixelart \
  -H "Authorization: Bearer $PIXELLAB_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"image\": {\"type\":\"base64\", \"base64\":\"$PHOTO_B64\", \"format\":\"png\"},
    \"image_size\": {\"width\":256, \"height\":256},
    \"output_size\": {\"width\":64, \"height\":64}
  }" | jq -r '.image.base64' | base64 -d > output.png
```

| Parameter | Type | Required | Default | Notes |
|-----------|------|----------|---------|-------|
| `image` | Base64Image | YES | — | Source image |
| `image_size` | {width, height} | YES | — | 16-1280 × 16-1280 |
| `output_size` | {width, height} | YES | — | 16-320 × 16-320 |
| `text_guidance_scale` | float | no | null | 1.0-20.0 |
| `seed` | int | no | null | Reproducibility |

---

## 7. remove-background (SYNC)

```bash
SPRITE_B64=$(base64 -i sprite.png)

curl -s -X POST https://api.pixellab.ai/v2/remove-background \
  -H "Authorization: Bearer $PIXELLAB_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"image\": {\"base64\":\"$SPRITE_B64\"},
    \"image_size\": {\"width\":64, \"height\":64},
    \"background_removal_task\": \"remove_simple_background\"
  }" | jq -r '.image.base64' | base64 -d > no-bg.png
```

| Parameter | Type | Required | Default | Notes |
|-----------|------|----------|---------|-------|
| `image` | Base64Image | YES | — | Source |
| `image_size` | {width, height} | YES | — | 1-400 × 1-400 |
| `background_removal_task` | enum | no | "remove_simple_background" | "remove_simple_background" \| "remove_complex_background" |
| `text` | string | no | null | Foreground hint (max 500) |
| `seed` | int | no | null | Reproducibility |

---

## 8. inpaint-v3 (ASYNC)

Region-based AI editing. White mask pixels = generate, black = keep.

```bash
IMG_B64=$(base64 -i sprite.png)
MASK_B64=$(base64 -i mask.png)

curl -s -X POST https://api.pixellab.ai/v2/inpaint-v3 \
  -H "Authorization: Bearer $PIXELLAB_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"description\": \"add a glowing sword in hand\",
    \"inpainting_image\": {\"image\":{\"base64\":\"$IMG_B64\"}, \"size\":{\"width\":64,\"height\":64}},
    \"mask_image\": {\"image\":{\"base64\":\"$MASK_B64\"}, \"size\":{\"width\":64,\"height\":64}},
    \"no_background\": false
  }" | jq -r '.background_job_id'
```

| Parameter | Type | Required | Default | Notes |
|-----------|------|----------|---------|-------|
| `description` | string | YES | — | What to generate in masked area |
| `inpainting_image` | {image, size} | YES | — | Image to edit (32-512px) |
| `mask_image` | {image, size} | YES | — | Mask (white=generate, black=keep) |
| `no_background` | bool | no | null | Remove bg from generated content |
| `crop_to_mask` | bool | no | null | Crop output to mask boundary |
| `seed` | int | no | null | Reproducibility |

---

## 9. resize (SYNC)

Smart pixel-art-aware resize. Max 2× increase or 50% decrease per call.

```bash
SPRITE_B64=$(base64 -i small-sprite.png)

curl -s -X POST https://api.pixellab.ai/v2/resize \
  -H "Authorization: Bearer $PIXELLAB_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"description\": \"cute wizard with blue robe\",
    \"reference_image\": {\"base64\":\"$SPRITE_B64\"},
    \"reference_image_size\": {\"width\":32, \"height\":32},
    \"target_size\": {\"width\":64, \"height\":64},
    \"no_background\": true
  }" | jq -r '.image.base64' | base64 -d > resized.png
```

| Parameter | Type | Required | Default | Notes |
|-----------|------|----------|---------|-------|
| `description` | string | YES | — | What the sprite depicts |
| `reference_image` | Base64Image | YES | — | Source |
| `reference_image_size` | {width, height} | YES | — | 16-200 × 16-200 |
| `target_size` | {width, height} | YES | — | 16-200 × 16-200 |
| `view` | enum | no | null | "side" \| "low top-down" \| "high top-down" |
| `direction` | enum | no | null | 8 compass directions |
| `no_background` | bool | no | null | Transparent |
| `color_image` | Base64Image | no | null | Color palette reference |
| `seed` | int | no | null | Reproducibility |

---

## 10. rotate (SYNC)

Rotate a sprite to show from different direction/view angle.

```bash
SPRITE_B64=$(base64 -i character-south.png)

curl -s -X POST https://api.pixellab.ai/v2/rotate \
  -H "Authorization: Bearer $PIXELLAB_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"image_size\": {\"width\":64, \"height\":64},
    \"from_image\": {\"base64\":\"$SPRITE_B64\"},
    \"from_direction\": \"south\",
    \"to_direction\": \"east\",
    \"image_guidance_scale\": 3.0
  }" | jq -r '.image.base64' | base64 -d > character-east.png
```

| Parameter | Type | Required | Default | Notes |
|-----------|------|----------|---------|-------|
| `image_size` | {width, height} | YES | — | 16-200 × 16-200 |
| `from_image` | Base64Image | YES | — | Source sprite |
| `image_guidance_scale` | float | no | 3.0 | 1.0-20.0 |
| `from_view` / `to_view` | enum | no | null | "side" \| "low top-down" \| "high top-down" |
| `from_direction` / `to_direction` | enum | no | null | 8 compass directions |
| `view_change` | int | no | null | -90 to 90 degrees tilt |
| `direction_change` | int | no | null | -180 to 180 degrees rotation |
| `isometric` | bool | no | false | Isometric view |
| `no_background` | bool | no | null | Transparent |
| `color_image` | Base64Image | no | null | Palette reference |
| `seed` | int | no | null | Reproducibility |

---

## Base64Image Format

All image parameters accept:
```json
{
  "type": "base64",
  "base64": "<base64-encoded-data>",
  "format": "png"
}
```

Short form (type/format optional): `{"base64": "..."}`

## Helper: Encode image to base64

```bash
# macOS
base64 -i sprite.png

# Linux
base64 -w0 sprite.png
```

## Helper: Save base64 response to file

```bash
# From sync response
curl ... | jq -r '.image.base64' | base64 -d > output.png

# From async job (after polling)
curl -s https://api.pixellab.ai/v2/background-jobs/$JOB_ID \
  -H "Authorization: Bearer $PIXELLAB_API_KEY" \
  | jq -r '.last_response.images[0].base64' | base64 -d > output.png
```
