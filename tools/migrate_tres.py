#!/usr/bin/env python3
"""
One-shot rewrite of script-backed .tres files for step 3 of the godot-cpp port.

Before:
    [gd_resource type="Resource" script_class="BiomeDef" load_steps=2 format=3]
    [ext_resource type="Script" path="res://src/core/biome_def.gd" id="X"]
    [ext_resource type="Script" path="res://src/core/pool_def.gd" id="Y"]
    [sub_resource type="Resource" id="Z"]
    script = ExtResource("Y")
    material_id = 5

    [resource]
    script = ExtResource("X")
    display_name = "Caves"

After:
    [gd_resource type="BiomeDef" load_steps=1 format=3]
    [sub_resource type="PoolDef" id="Z"]
    material_id = 5

    [resource]
    display_name = "Caves"

The mapping from script path -> native class name is hardcoded below to the
five resources ported in step 3.
"""
import re
import sys
from pathlib import Path

SCRIPT_TO_NATIVE = {
    "res://src/core/biome_def.gd":     "BiomeDef",
    "res://src/core/pool_def.gd":      "PoolDef",
    "res://src/core/room_template.gd": "RoomTemplate",
    "res://src/core/terrain_cell.gd":  "TerrainCell",
    # template_pack.gd is RefCounted, never serialized to .tres -- not in this map.
}

EXT_RESOURCE_RE = re.compile(
    r'^\[ext_resource\s+type="Script"\s+path="([^"]+)"\s+id="([^"]+)"\]\s*$'
)
HEADER_RE = re.compile(
    r'^\[gd_resource\s+type="Resource"\s+script_class="([^"]+)"(.*)\]\s*$'
)
SUBRES_RE = re.compile(
    r'^\[sub_resource\s+type="Resource"\s+id="([^"]+)"\]\s*$'
)
SCRIPT_LINE_RE = re.compile(r'^\s*script\s*=\s*ExtResource\("([^"]+)"\)\s*$')

def migrate(path: Path) -> bool:
    """Rewrite `path` in place. Returns True if changed."""
    text = path.read_text()
    lines = text.splitlines(keepends=True)

    # Pass 1: collect script ext_resource id -> native class.
    id_to_native = {}
    for line in lines:
        m = EXT_RESOURCE_RE.match(line)
        if m:
            script_path, ext_id = m.group(1), m.group(2)
            native = SCRIPT_TO_NATIVE.get(script_path)
            if native:
                id_to_native[ext_id] = native

    if not id_to_native:
        return False  # already migrated, or no script-backed resources to rewrite

    # Pass 2: rewrite. We track which sub_resource id's native type we know,
    # by reading ahead one line for the `script = ExtResource("...")` after
    # the `[sub_resource type="Resource" id="..."]` line.
    out = []
    i = 0
    while i < len(lines):
        line = lines[i]

        # Drop script ext_resource lines (we replaced them with native types).
        m = EXT_RESOURCE_RE.match(line)
        if m and m.group(1) in SCRIPT_TO_NATIVE:
            i += 1
            continue

        # Rewrite the gd_resource header.
        m = HEADER_RE.match(line)
        if m:
            native = m.group(1)
            tail = m.group(2)
            # Drop load_steps; Godot recomputes it on save.
            tail = re.sub(r'\s*load_steps=\d+', '', tail)
            out.append(f'[gd_resource type="{native}"{tail}]\n')
            i += 1
            continue

        # Rewrite [sub_resource type="Resource" id="..."]: peek ahead for the
        # `script = ExtResource("...")` line to learn the native type.
        m = SUBRES_RE.match(line)
        if m:
            sub_id = m.group(1)
            native = None
            # Look at the next few lines for `script = ExtResource("X")`.
            for j in range(i + 1, min(i + 5, len(lines))):
                sm = SCRIPT_LINE_RE.match(lines[j])
                if sm and sm.group(1) in id_to_native:
                    native = id_to_native[sm.group(1)]
                    break
                if lines[j].startswith('['):  # next section, stop.
                    break
            if native:
                out.append(f'[sub_resource type="{native}" id="{sub_id}"]\n')
                i += 1
                continue

        # Drop `script = ExtResource("X")` lines that point to a migrated script.
        m = SCRIPT_LINE_RE.match(line)
        if m and m.group(1) in id_to_native:
            i += 1
            continue

        out.append(line)
        i += 1

    new = "".join(out)
    if new == text:
        return False
    path.write_text(new)
    return True

def main() -> int:
    if len(sys.argv) < 2:
        print("usage: migrate_tres.py FILE [FILE ...]", file=sys.stderr)
        return 2
    changed = 0
    for arg in sys.argv[1:]:
        p = Path(arg)
        if not p.is_file():
            print(f"skip (not a file): {p}", file=sys.stderr)
            continue
        if migrate(p):
            print(f"migrated: {p}")
            changed += 1
        else:
            print(f"unchanged: {p}")
    print(f"{changed} file(s) changed.")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
