# Level Preview Mode Design

## PurposeEnable level designers to preview generated terrain in the editor before playing the game. Supports iteration on world generation parameters.

## Architecture Overview

```
WorldManager (runtime + public API)
├── ChunkContainer
└── WorldPreview (@tool node)
        ↓ calls
    WorldManager.generate_chunks_at()
```

The preview functionality is encapsulated in a separate `WorldPreview` node that uses `@tool` to run in the editor. WorldManager exposes a public API for chunk generation that the preview node calls.

## Components

### WorldManager (Refactored)

**New Public API:**
- `generate_chunks_at(coords: Array[Vector2i], seed: int) -> void`- Generates chunks at specified coordinates with given seed
- Runs generation shader only (no simulation)
- `clear_all_chunks() -> void` - Removes all chunks and frees resources
- `get_chunk_container() -> Node2D` - Returns ChunkContainer node for preview meshes

**Changes:**
- Skip simulation in `_process()` when `Engine.is_editor_hint()` is true
- Skip chunk loading/unloading based on camera in editor mode
- Keep existing `@export` and `@onready` unchanged

### WorldPreview (New @tool Script)

**Exported Properties:**
```gdscript
@export var preview_size: int = 3  # generates (2n+1)×(2n+1) chunks
@export var world_seed: int = 0
```

**Inspector Buttons:**
- "Generate Preview" - calculates chunk coordinates, calls WorldManager API
- "Clear Preview" - calls WorldManager.clear_all_chunks()

**Logic:**
- Preview center is always world origin (0, 0)
- Generates (2n+1)×(2n+1) chunk grid centered on origin
- On generate: clears existing chunks first, then generates new ones

### EditorPlugin (New)

**Purpose:**
- Provides custom inspector for WorldPreview with buttons
- Auto-clears preview when WorldPreview is deselected**Implementation:**
- `EditorInspectorPlugin` subclass that adds buttons to WorldPreview inspector
- Tracks selection changes to detect deselection

## Data Flow

1. Editor loads scene, WorldPreview node exists as child of WorldManager
2. User selects WorldPreview node in scene tree
3. Inspector shows `preview_size`, `world_seed` fields and buttons
4. User sets parameters, clicks "Generate Preview"
5. WorldPreview clears existing chunks via `clear_all_chunks()`
6. WorldPreview calculates chunk coordinates (e.g., n=2 → coords from (-2,-2) to (2,2))
7. WorldPreview calls `generate_chunks_at(coords, world_seed)`
8. WorldManager creates GPU textures, runs generation shader
9. Generated chunks render in editor viewport
10. User clicks "Clear Preview" or deselects WorldPreview
11. Chunks cleared, viewport returns to normal

## Files Changed

| File | Change |
|------|--------|
| `scripts/world_manager.gd` | Add public API methods, skip sim in editor |
| `scripts/world_preview.gd` | New @tool script |
| `addons/level_preview/plugin.cfg` | Plugin configuration |
| `addons/level_preview/level_preview_plugin.gd` | EditorPlugin implementation |
| `addons/level_preview/world_preview_inspector.gd` | Inspector plugin |
| `project.godot` | Register editor plugin |

## Implementation Notes

- WorldPreview must find WorldManager sibling via `get_parent()` in `_ready()`
- WorldManager's existing `_create_chunk()` can be reused, just need to call from public API
- Generation shader already accepts seed in push constants (currently hardcoded to 0)
- No simulation runs in editor, so no performance concern with large previews