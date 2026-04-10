# Weapon System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a weapon system where the player can trigger weapons in slots via Z/X/C keys. First weapon spawns gas around the player.

**Architecture:** Script-based weapons extending a base `Weapon` class. Player controller holds weapon array and routes key input to weapon `use()` calls. Each weapon manages its own cooldown internally.

**Tech Stack:** GDScript, Godot 4.6

---

## File Structure

### New Files
- `src/weapons/weapon.gd` - Abstract base class for all weapons
- `src/weapons/test_weapon.gd` - First weapon implementation (spawns gas)

### Modified Files
- `src/player/player_controller.gd` - Add weapon slots, key handling, and `get_world_manager()`

---

### Task 1: Create Weapon Base Class

**Files:**
- Create: `src/weapons/weapon.gd`

- [ ] **Step 1: Create weapons directory**

```bash
mkdir -p src/weapons
```

- [ ] **Step 2: Write Weapon base class**

Create `src/weapons/weapon.gd`:

```gdscript
class_name Weapon
extends RefCounted

var name: String = "Weapon"


func use(_user: Node) -> void:
	push_error("Weapon.use() must be overridden")


func tick(_delta: float) -> void:
	pass


func is_ready() -> bool:
	return true
```

- [ ] **Step 3: Verify file created**

Run: `ls src/weapons/`
Expected: `weapon.gd`

- [ ] **Step 4: Commit**

```bash
git add src/weapons/weapon.gd
git commit -m "feat: add Weapon base class"
```

---

### Task 2: Create Test Weapon

**Files:**
- Create: `src/weapons/test_weapon.gd`

- [ ] **Step 1: Write TestWeapon implementation**

Create `src/weapons/test_weapon.gd`:

```gdscript
class_name TestWeapon
extends Weapon

const COOLDOWN: float = 0.5
const GAS_RADIUS: float = 6.0
const GAS_DENSITY: int = 200

var _cooldown_timer: float = 0.0


func _init() -> void:
	name = "Test Weapon"


func use(user: Node) -> void:
	if _cooldown_timer > 0.0:
		return
	
	var world_manager := _get_world_manager(user)
	if world_manager == null:
		return
	
	var pos: Vector2 = user.global_position
	world_manager.place_gas(pos, GAS_RADIUS, GAS_DENSITY)
	_cooldown_timer = COOLDOWN


func tick(delta: float) -> void:
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta


func is_ready() -> bool:
	return _cooldown_timer <= 0.0


func _get_world_manager(user: Node) -> Node:
	if user.has_method("get_world_manager"):
		return user.get_world_manager()
	var parent := user.get_parent()
	if parent:
		return parent.get_node_or_null("WorldManager")
	return null
```

- [ ] **Step 2: Verify file created**

Run: `ls src/weapons/`
Expected: `test_weapon.gd  weapon.gd`

- [ ] **Step 3: Commit**

```bash
git add src/weapons/test_weapon.gd
git commit -m "feat: add TestWeapon that spawns gas"
```

---

### Task 3: Integrate Weapons into Player Controller

**Files:**
- Modify: `src/player/player_controller.gd`

- [ ] **Step 1: Add preload constants at top of file**

At line 8 (after `ShadowGridScript` constant), add:

```gdscript
const TestWeaponScript := preload("res://src/weapons/test_weapon.gd")
```

- [ ] **Step 2: Add weapons array property**

After line 11 (after `max_speed`), add:

```gdscript
var weapons: Array[Weapon] = []
```

- [ ] **Step 3: Initialize weapons in _ready()**

After line 27 (after `add_to_group("gas_interactors")`), add:

```gdscript
	weapons.resize(3)
	weapons[0] = TestWeaponScript.new()
	# slots 1 and 2 remain null (empty)
```

- [ ] **Step 4: Add _input function after _physics_process**

After line 45 (after `_apply_movement` function), add:

```gdscript

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var slot := -1
		match event.keycode:
			KEY_Z: slot = 0
			KEY_X: slot = 1
			KEY_C: slot = 2
		if slot >= 0 and slot < weapons.size() and weapons[slot] != null:
			weapons[slot].use(self)
```

- [ ] **Step 5: Add tick_weapons function**

After `_input` function, add:

```gdscript


func _tick_weapons(delta: float) -> void:
	for weapon in weapons:
		if weapon != null and weapon.has_method("tick"):
			weapon.tick(delta)
```

- [ ] **Step 6: Call _tick_weapons in _physics_process**

After line 42 (after `shadow_grid.update_sync`), add:

```gdscript
	_tick_weapons(delta)
```

- [ ] **Step 7: Add get_world_manager function**

After `_tick_weapons`, add:

```gdscript


func get_world_manager() -> Node:
	return _world_manager
```

- [ ] **Step 8: Commit**

```bash
git add src/player/player_controller.gd
git commit -m "feat: integrate weapon system into player controller"
```

---

### Task 4: Manual Testing

- [ ] **Step 1: Open project in Godot editor**

Launch Godot and open the project.

- [ ] **Step 2: Run the game**

Press F5 or click Play.

- [ ] **Step 3: Test weapon firing**

- Press Z to fire weapon in slot 1
- Expected: Gas spawns around player (visible as particles/density change)
- Press Z again immediately - should do nothing (cooldown)
- Wait 0.5s, press Z again - should spawn gas again

- [ ] **Step 4: Test empty slots**

- Press X (slot 2, empty) - should do nothing
- Press C (slot 3, empty) - should do nothing

- [ ] **Step 5: Test movement still works**

- WASD movement should work normally while weapon cooldowns tick

---

## Verification Commands

After all tasks complete:

```bash
# Check all files exist
ls src/weapons/weapon.gd src/weapons/test_weapon.gd src/player/player_controller.gd

# Verify no GDScript errors (if you have a linting setup)
# godot --headless --script-check res://src/player/player_controller.gd
```