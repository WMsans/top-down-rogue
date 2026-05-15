#!/usr/bin/env python3
"""Generate set-piece room PNGs for boss arenas, elite chests, and secret chests.

PNG encoding:
- alpha=0           -> skip (do not modify terrain)
- (r, g, 0, 255)    -> write material id r, optional marker g
    r=255 -> biome.background_material
    r=254 -> biome.perimeter_material
    r=253 -> biome.cracked_material
    r=0   -> AIR (carve)
- markers (g channel): 1=enemy, 2=elite, 3=chest, 4=shop, 5=secret_chest,
    6=boss, 7=unused, 8=explosive_barrel, 9=oil_barrel, 10=gas_vent,
    11=lava_pool_seed, 12=oil_pool_seed, 13=water_pool_seed
"""
from __future__ import annotations
import os
import math
from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..")
ROOMS = os.path.join(ROOT, "assets", "rooms")

SKIP = (0, 0, 0, 0)
AIR = (0, 0, 0, 255)
BG = (255, 0, 0, 255)
PERIM = (254, 0, 0, 255)
CRACKED = (253, 0, 0, 255)

def mark(marker: int) -> tuple:
    # Place a marker on an AIR cell. Material id 0 (AIR) + marker in green.
    return (0, marker, 0, 255)

def new(size: int) -> Image.Image:
    return Image.new("RGBA", (size, size), SKIP)

def put(im: Image.Image, x: int, y: int, c: tuple) -> None:
    if 0 <= x < im.width and 0 <= y < im.height:
        im.putpixel((x, y), c)

def disk(im: Image.Image, cx: int, cy: int, r: int, c: tuple) -> None:
    r2 = r * r
    for y in range(max(0, cy - r), min(im.height, cy + r + 1)):
        dy = y - cy
        for x in range(max(0, cx - r), min(im.width, cx + r + 1)):
            dx = x - cx
            if dx * dx + dy * dy <= r2:
                im.putpixel((x, y), c)

def ring(im: Image.Image, cx: int, cy: int, r_outer: int, r_inner: int, c: tuple) -> None:
    ro2, ri2 = r_outer * r_outer, r_inner * r_inner
    for y in range(max(0, cy - r_outer), min(im.height, cy + r_outer + 1)):
        dy = y - cy
        for x in range(max(0, cx - r_outer), min(im.width, cx + r_outer + 1)):
            dx = x - cx
            d = dx * dx + dy * dy
            if ri2 < d <= ro2:
                im.putpixel((x, y), c)

def rect(im: Image.Image, x0: int, y0: int, x1: int, y1: int, c: tuple) -> None:
    for y in range(max(0, y0), min(im.height, y1)):
        for x in range(max(0, x0), min(im.width, x1)):
            im.putpixel((x, y), c)

def carve_interior(im: Image.Image, cx: int, cy: int, r: int) -> None:
    """Fill disk with AIR (carved out)."""
    disk(im, cx, cy, r, AIR)

def crenellated_ring(im: Image.Image, cx: int, cy: int, r_outer: int, thickness: int,
                     gap_arc: float, gap_count: int, c: tuple) -> None:
    """Solid ring with `gap_count` evenly-spaced angular gaps of width `gap_arc` (radians)."""
    r_inner = r_outer - thickness
    ro2, ri2 = r_outer * r_outer, r_inner * r_inner
    # precompute gap angle centers
    gap_centers = [2 * math.pi * i / gap_count for i in range(gap_count)]
    half_gap = gap_arc * 0.5
    for y in range(max(0, cy - r_outer), min(im.height, cy + r_outer + 1)):
        dy = y - cy
        for x in range(max(0, cx - r_outer), min(im.width, cx + r_outer + 1)):
            dx = x - cx
            d = dx * dx + dy * dy
            if not (ri2 < d <= ro2):
                continue
            a = math.atan2(dy, dx) % (2 * math.pi)
            in_gap = False
            for ga in gap_centers:
                da = abs(((a - ga + math.pi) % (2 * math.pi)) - math.pi)
                if da < half_gap:
                    in_gap = True
                    break
            if in_gap:
                im.putpixel((x, y), AIR)
            else:
                im.putpixel((x, y), c)

# ---------- Boss arenas (512x512) ----------

def boss_arena_a(perim_color=PERIM) -> Image.Image:
    """Crenellated ring + 4 corner pillars + 2 lava + 4 melee + 2 barrels + boss."""
    im = new(512)
    cx, cy = 256, 256
    # Interior carve (radius 232 to leave room for 16px ring at 225-241)
    carve_interior(im, cx, cy, 232)
    # Crenellated perimeter
    crenellated_ring(im, cx, cy, 241, 16, gap_arc=0.18, gap_count=8, c=perim_color)
    # 4 corner pillars
    for (px, py) in [(176, 176), (336, 176), (176, 336), (336, 336)]:
        disk(im, px, py, 18, perim_color)
    # Lava pool seeds (markers)
    put(im, 200, 256, mark(11))
    put(im, 312, 256, mark(11))
    # Enemies (melee)
    for (px, py) in [(220, 220), (292, 220), (220, 292), (292, 292)]:
        put(im, px, py, mark(1))
    # Explosive barrels
    put(im, 256, 200, mark(8))
    put(im, 256, 312, mark(8))
    # Boss at center
    put(im, cx, cy, mark(6))
    return im

def boss_arena_b(perim_color=PERIM) -> Image.Image:
    """Diagonal pillar pairs + oil pool + oil barrel + elites + boss."""
    im = new(512)
    cx, cy = 256, 256
    carve_interior(im, cx, cy, 232)
    crenellated_ring(im, cx, cy, 241, 16, gap_arc=0.22, gap_count=6, c=perim_color)
    # Pillar cross
    for (px, py) in [(256, 160), (256, 352), (160, 256), (352, 256)]:
        disk(im, px, py, 14, perim_color)
    # Oil pool seeds
    put(im, 200, 200, mark(12))
    put(im, 312, 312, mark(12))
    # Oil barrel
    put(im, 220, 312, mark(9))
    put(im, 312, 220, mark(9))
    # Enemies + 1 elite
    for (px, py) in [(232, 256), (280, 256), (256, 232), (256, 280)]:
        put(im, px, py, mark(1))
    put(im, 200, 256, mark(2))
    # Boss
    put(im, cx, cy, mark(6))
    return im

def boss_arena_c(perim_color=PERIM) -> Image.Image:
    """Sparse interior + gas vent + 3 elites + boss."""
    im = new(512)
    cx, cy = 256, 256
    carve_interior(im, cx, cy, 232)
    crenellated_ring(im, cx, cy, 241, 16, gap_arc=0.14, gap_count=10, c=perim_color)
    # Single thick central pillar
    disk(im, cx, cy + 96, 24, perim_color)
    # Two flanking smaller pillars
    disk(im, cx - 96, cy - 64, 14, perim_color)
    disk(im, cx + 96, cy - 64, 14, perim_color)
    # Gas vent
    put(im, 256, 360, mark(10))
    # 3 elites
    put(im, 200, 200, mark(2))
    put(im, 312, 200, mark(2))
    put(im, 256, 320, mark(2))
    # Boss
    put(im, cx, cy, mark(6))
    return im

def boss_arena_d(perim_color=PERIM) -> Image.Image:
    """Concentric pillar rings + water pond + explosive barrels + boss."""
    im = new(512)
    cx, cy = 256, 256
    carve_interior(im, cx, cy, 232)
    crenellated_ring(im, cx, cy, 241, 16, gap_arc=0.20, gap_count=8, c=perim_color)
    # Inner pillar ring (8 small pillars at radius ~140)
    for i in range(8):
        ang = 2 * math.pi * i / 8 + math.pi / 8
        px = int(cx + math.cos(ang) * 140)
        py = int(cy + math.sin(ang) * 140)
        disk(im, px, py, 10, perim_color)
    # Water pond near top
    for (px, py) in [(256, 176), (252, 180), (260, 180), (256, 184)]:
        put(im, px, py, mark(13))
    # 2 explosive barrels
    put(im, 200, 320, mark(8))
    put(im, 312, 320, mark(8))
    # Enemies
    for (px, py) in [(224, 256), (288, 256)]:
        put(im, px, py, mark(1))
    put(im, cx, cy, mark(6))
    return im

# ---------- Elite chest rooms (256x256) ----------

def elite_chest_a() -> Image.Image:
    """Open round chamber: chest at center, 3 elites around, 2 explosive barrels."""
    im = new(256)
    cx, cy = 128, 128
    disk(im, cx, cy, 112, AIR)
    # Chest
    put(im, cx, cy, mark(3))
    # 3 elites in triangle
    for i in range(3):
        a = 2 * math.pi * i / 3 - math.pi / 2
        px = int(cx + math.cos(a) * 60)
        py = int(cy + math.sin(a) * 60)
        put(im, px, py, mark(2))
    # Explosive barrels
    put(im, cx - 40, cy + 40, mark(8))
    put(im, cx + 40, cy + 40, mark(8))
    return im

def elite_chest_b() -> Image.Image:
    """Oblong chamber: chest off-center, 2 elites, gas vent."""
    im = new(256)
    # Carve elongated area
    for y in range(40, 216):
        for x in range(24, 232):
            # Rounded rect
            dx = max(0, abs(x - 128) - 80)
            dy = max(0, abs(y - 128) - 60)
            if dx * dx + dy * dy <= 24 * 24:
                im.putpixel((x, y), AIR)
    put(im, 128, 128, mark(3))
    put(im, 80, 128, mark(2))
    put(im, 176, 128, mark(2))
    put(im, 128, 80, mark(10))  # gas vent
    return im

def elite_chest_c() -> Image.Image:
    """Diamond chamber: chest + 2 elites + oil pool."""
    im = new(256)
    cx, cy = 128, 128
    for y in range(256):
        for x in range(256):
            if abs(x - cx) + abs(y - cy) <= 100:
                im.putpixel((x, y), AIR)
    put(im, cx, cy, mark(3))
    put(im, cx - 50, cy, mark(2))
    put(im, cx + 50, cy, mark(2))
    # Oil pool seeds
    put(im, cx, cy + 60, mark(12))
    put(im, cx - 20, cy + 60, mark(12))
    put(im, cx + 20, cy + 60, mark(12))
    return im

# ---------- Secret chest (32x32) ----------

def secret_with_hint() -> Image.Image:
    """Tiny pocket: a chest in an air cavity, cracked hint patch on +X side.
    The stamp is placed inside solid terrain (validated by shader).
    """
    im = new(32)
    # Carve a small 6x6 air pocket on the left half
    for y in range(13, 19):
        for x in range(8, 14):
            im.putpixel((x, y), AIR)
    # Chest marker inside the pocket
    put(im, 11, 16, mark(5))
    # Cracked hint patch on the +X side (6x3 cells)
    for y in range(15, 18):
        for x in range(14, 20):
            im.putpixel((x, y), CRACKED)
    return im

# ---------- Driver ----------

BIOMES = ["caves", "mines", "magma", "frozen", "vault"]

def main() -> None:
    for biome in BIOMES:
        out = os.path.join(ROOMS, biome)
        os.makedirs(out, exist_ok=True)
        # Boss arenas
        boss_arena_a().save(os.path.join(out, "boss_arena_a.png"))
        boss_arena_b().save(os.path.join(out, "boss_arena_b.png"))
        boss_arena_c().save(os.path.join(out, "boss_arena_c.png"))
        boss_arena_d().save(os.path.join(out, "boss_arena_d.png"))
        # Elite chest rooms
        elite_chest_a().save(os.path.join(out, "elite_chest_a.png"))
        elite_chest_b().save(os.path.join(out, "elite_chest_b.png"))
        elite_chest_c().save(os.path.join(out, "elite_chest_c.png"))
        # Secret
        secret_with_hint().save(os.path.join(out, "secret_a.png"))
        print(f"  generated for {biome}")

if __name__ == "__main__":
    main()
