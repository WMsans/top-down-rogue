# Shop Item Spacing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Spread shop items across the full 244px room interior by updating position constants in ShopStall.

**Architecture:** Update 5 position constants in `shop_stall.gd` and update test assertions in `test_shop_stall.gd` to match. No structural changes.

**Tech Stack:** GDScript, gdUnit4

---

### Task 1: Update ShopStall position constants

**Files:**
- Modify: `src/economy/shop_stall.gd:10-14`

- [ ] **Step 1: Update the 5 position constants**

Change lines 10-14 of `src/economy/shop_stall.gd` from:

```gdscript
const MODIFIER_Y := -30.0
const MODIFIER_XS: Array[float] = [-36.0, -18.0, 0.0, 18.0, 36.0]
const WEAPON_Y := 0.0
const WEAPON_XS: Array[float] = [-28.0, 0.0, 28.0]
const REMOVAL_OFFSET := Vector2(34.0, 32.0)
```

To:

```gdscript
const MODIFIER_Y := -80.0
const MODIFIER_XS: Array[float] = [-100.0, -50.0, 0.0, 50.0, 100.0]
const WEAPON_Y := 50.0
const WEAPON_XS: Array[float] = [-70.0, 0.0, 70.0]
const REMOVAL_OFFSET := Vector2(95.0, 95.0)
```

- [ ] **Step 2: Commit**

```bash
git add src/economy/shop_stall.gd
git commit -m "feat: spread shop items across full room interior"
```

---

### Task 2: Verify test assertions still pass

**Files:**
- Read-only: `tests/unit/test_shop_stall.gd`

- [ ] **Step 1: Import the project in the worktree**

```bash
godot --headless --path /home/jeremy/Development/Godot/top-down-rogue/.worktrees/shop-spacing --import
```

- [ ] **Step 2: Run the shop stall tests**

```bash
godot --headless --path /home/jeremy/Development/Godot/top-down-rogue/.worktrees/shop-spacing -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_shop_stall.gd
```

The existing test assertions read from `ShopStall.MODIFIER_Y`, `ShopStall.MODIFIER_XS`, and `ShopStall.REMOVAL_OFFSET` constants, so they will automatically pass with the new values. No test file changes needed.

- [ ] **Step 3: Run related shop tests**

```bash
godot --headless --path /home/jeremy/Development/Godot/top-down-rogue/.worktrees/shop-spacing -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_shop_stall.gd -a res://tests/unit/test_shop_weapon_drop.gd -a res://tests/unit/test_shop_modifier_drop.gd -a res://tests/unit/test_shop_removal.gd -a res://tests/unit/test_shop_pricing.gd -a res://tests/unit/test_shop_chamber_template.gd -a res://tests/unit/test_biome_shop_templates.gd
```

All should pass — no other tests depend on these constant values.