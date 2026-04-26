# Shop UI Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reskin the shop UI from a bare-bones centered dialog to a Balatro-style layout with header bar, horizontal card row, and bottom action bar.

**Architecture:** Single scene + script change. The scene gets a new node hierarchy (ShopPanel > VBoxContainer > [HeaderBar, BuyContainer, ActionBar]). The script restructures card creation (price/buy move outside card, card click = buy) and adds entrance animation. All styling uses existing UiTheme constants — no new assets.

**Tech Stack:** Godot 4.6, GDScript, UiTheme constants, UiAnimations utility

---

### Task 1: Rewrite shop_ui.tscn scene structure

**Files:**
- Modify: `scenes/economy/shop_ui.tscn`

Replace the current flat CenterContainer > VBoxContainer (Title, Gold, BuyContainer, RemoveButton, CloseButton) with the new Balatro-style hierarchy.

- [ ] **Step 1: Replace scene content**

Current structure:
```
CanvasLayer
├── Overlay (ColorRect)
└── CenterContainer
    └── VBoxContainer
        ├── TitleLabel
        ├── GoldLabel
        ├── BuyContainer (HBoxContainer)
        ├── RemoveButton
        └── CloseButton
```

New structure:
```
CanvasLayer
├── Overlay (ColorRect) — fullscreen dimmer, same as before
├── CenterContainer
    └── ShopPanel (PanelContainer) — %ShopPanel, outer container
        └── VBoxContainer
            ├── HeaderBar (PanelContainer) — %HeaderBar
            │   └── HBoxContainer
            │       ├── TitleLabel (Label) — text="SHOP"
            │       └── GoldLabel (Label) — %GoldLabel, text="GOLD: 0"
            ├── BuyContainer (HBoxContainer) — %BuyContainer, centered
            └── ActionBar (PanelContainer) — %ActionBar
                └── HBoxContainer
                    ├── RerollButton (Button) — %RerollButton, text="REROLL"
                    ├── RemoveButton (Button) — %RemoveButton, text="REMOVE MODIFIER"
                    └── CloseButton (Button) — %CloseButton, text="CLOSE"
```

Complete tscn content:

```
[gd_scene format=3 uid="uid://new_shop_ui"]

[ext_resource type="Script" path="res://src/economy/shop_ui.gd" id="1"]

[node name="ShopUI" type="CanvasLayer"]
layer = 16
script = ExtResource("1")
process_mode = 4

[node name="Overlay" type="ColorRect" parent="." unique_id=1]
unique_name_in_owner = true
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
color = Color(0.102, 0.059, 0.071, 0.87)

[node name="CenterContainer" type="CenterContainer" parent="."]
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
grow_horizontal = 2
grow_vertical = 2

[node name="ShopPanel" type="PanelContainer" parent="CenterContainer" unique_id=7]
unique_name_in_owner = true
layout_mode = 2

[node name="VBoxContainer" type="VBoxContainer" parent="CenterContainer/ShopPanel"]
layout_mode = 2
theme_override_constants/separation = 0

[node name="HeaderBar" type="PanelContainer" parent="CenterContainer/ShopPanel/VBoxContainer" unique_id=8]
unique_name_in_owner = true
layout_mode = 2
theme_override_constants/separation = 0

[node name="HeaderHBox" type="HBoxContainer" parent="CenterContainer/ShopPanel/VBoxContainer/HeaderBar"]
layout_mode = 2
theme_override_constants/separation = 0
size_flags_horizontal = 3

[node name="Spacer" type="Control" parent="CenterContainer/ShopPanel/VBoxContainer/HeaderBar/HeaderHBox"]
layout_mode = 2
size_flags_horizontal = 3
mouse_filter = 2

[node name="TitleLabel" type="Label" parent="CenterContainer/ShopPanel/VBoxContainer/HeaderBar/HeaderHBox"]
layout_mode = 2
text = "SHOP"
horizontal_alignment = 1
vertical_alignment = 1

[node name="GoldLabel" type="Label" parent="CenterContainer/ShopPanel/VBoxContainer/HeaderBar/HeaderHBox" unique_id=3]
unique_name_in_owner = true
layout_mode = 2
text = "GOLD: 0"
horizontal_alignment = 2
vertical_alignment = 1

[node name="BuyContainer" type="HBoxContainer" parent="CenterContainer/ShopPanel/VBoxContainer" unique_id=4]
unique_name_in_owner = true
layout_mode = 2
theme_override_constants/separation = 16
alignment = 1
size_flags_horizontal = 3

[node name="ActionBar" type="PanelContainer" parent="CenterContainer/ShopPanel/VBoxContainer" unique_id=9]
unique_name_in_owner = true
layout_mode = 2

[node name="ActionHBox" type="HBoxContainer" parent="CenterContainer/ShopPanel/VBoxContainer/ActionBar"]
layout_mode = 2
theme_override_constants/separation = 8

[node name="RerollButton" type="Button" parent="CenterContainer/ShopPanel/VBoxContainer/ActionBar/ActionHBox" unique_id=10]
unique_name_in_owner = true
layout_mode = 2
text = "REROLL"
size_flags_horizontal = 1

[node name="RemoveButton" type="Button" parent="CenterContainer/ShopPanel/VBoxContainer/ActionBar/ActionHBox" unique_id=5]
unique_name_in_owner = true
layout_mode = 2
text = "REMOVE MODIFIER"
size_flags_horizontal = 1

[node name="CloseButton" type="Button" parent="CenterContainer/ShopPanel/VBoxContainer/ActionBar/ActionHBox" unique_id=6]
unique_name_in_owner = true
layout_mode = 2
text = "CLOSE"
size_flags_horizontal = 1
```

Key differences from current:
- Overlay keeps the same color but process_mode moved to root node
- VBoxContainer separation = 0 (no gap between header/cards/action bar)
- HeaderBar has a Spacer control to push TitleLabel left and GoldLabel right
- All buttons have size_flags_horizontal = 1 for proportional sizing

---

### Task 2: Update shop_ui.gd for new layout

**Files:**
- Modify: `src/economy/shop_ui.gd`

- [ ] **Step 1: Update @onready references and _ready()**

Add new node references, remove _title_label (replaced by header label), add _reroll_button:

```gdscript
@onready var _shop_panel: PanelContainer = %ShopPanel
@onready var _header_bar: PanelContainer = %HeaderBar
@onready var _action_bar: PanelContainer = %ActionBar
@onready var _reroll_button: Button = %RerollButton
@onready var _overlay: ColorRect = %Overlay
@onready var _gold_label: Label = %GoldLabel
@onready var _buy_container: HBoxContainer = %BuyContainer
@onready var _remove_button: Button = %RemoveButton
@onready var _close_button: Button = %CloseButton
```

In `_ready()`, remove `_title_label.theme = theme`, add header/action bar styling, wire reroll button:

```gdscript
func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    _overlay.gui_input.connect(_on_overlay_input)
    _close_button.pressed.connect(close)
    _remove_button.pressed.connect(_on_remove_pressed)
    UiAnimations.setup_button_hover(_reroll_button)
    UiAnimations.setup_button_hover(_remove_button)
    UiAnimations.setup_button_hover(_close_button)
    _apply_bar_styles()
    visible = false
```

- [ ] **Step 2: Add bar styling method**

```gdscript
func _apply_bar_styles() -> void:
    var header_style := StyleBoxFlat.new()
    header_style.bg_color = UiTheme.SURFACE_BG
    header_style.set_corner_radius_all(0)
    header_style.set_corner_radius(CORNER_TOP_LEFT, 6)
    header_style.set_corner_radius(CORNER_TOP_RIGHT, 6)
    header_style.border_color = UiTheme.ACCENT
    header_style.set_border_width_all(0)
    header_style.set_border_width(MARGIN_BOTTOM, 2)
    header_style.shadow_color = Color(0, 0, 0, 0)
    _header_bar.add_theme_stylebox_override("panel", header_style)

    var action_style := StyleBoxFlat.new()
    action_style.bg_color = UiTheme.SURFACE_BG
    action_style.set_corner_radius_all(0)
    action_style.set_corner_radius(CORNER_BOTTOM_LEFT, 6)
    action_style.set_corner_radius(CORNER_BOTTOM_RIGHT, 6)
    action_style.border_color = UiTheme.PANEL_BORDER
    action_style.set_border_width_all(0)
    action_style.set_border_width(MARGIN_TOP, 1)
    action_style.shadow_color = Color(0, 0, 0, 0)
    _action_bar.add_theme_stylebox_override("panel", action_style)
```

- [ ] **Step 3: Update _create_offer_card() — remove price label and buy button, keep card clickable**

Remove internal price_label creation (lines 111-115) and buy_button creation (lines 117-123). Add gui_input for click-to-buy:

```gdscript
func _create_offer_card(offer: ShopOffer) -> PanelContainer:
    var card := PanelContainer.new()
    card.custom_minimum_size = CARD_MIN_SIZE
    card.theme = UiTheme.get_theme()

    var glow_mat := ShaderMaterial.new()
    glow_mat.shader = CARD_GLOW_SHADER
    glow_mat.set_shader_parameter("glow_enabled", false)
    card.material = glow_mat

    card.mouse_entered.connect(_on_card_mouse_entered.bind(card))
    card.mouse_exited.connect(_on_card_mouse_exited.bind(card))
    card.gui_input.connect(_on_card_gui_input.bind(offer, card))

    var vbox := VBoxContainer.new()
    vbox.add_theme_constant_override("separation", 6)
    vbox.alignment = BoxContainer.ALIGNMENT_CENTER
    card.add_child(vbox)

    if offer.modifier.icon_texture:
        var icon := TextureRect.new()
        icon.texture = offer.modifier.icon_texture
        icon.custom_minimum_size = MODIFIER_ICON_SIZE
        icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        vbox.add_child(icon)

    var name_label := Label.new()
    name_label.text = offer.modifier.name
    name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    name_label.add_theme_color_override("font_color", UiTheme.ACCENT_GOLD)
    vbox.add_child(name_label)

    var desc := offer.modifier.get_description()
    if desc != "":
        var desc_label := Label.new()
        desc_label.text = desc
        desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        desc_label.custom_minimum_size.x = CARD_MIN_SIZE.x - 16
        desc_label.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
        desc_label.add_theme_font_size_override("font_size", 13)
        vbox.add_child(desc_label)

    return card
```

- [ ] **Step 4: Add card gui_input handler**

```gdscript
func _on_card_gui_input(event: InputEvent, offer: ShopOffer, card: PanelContainer) -> void:
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        _on_buy_pressed(offer, card)
```

- [ ] **Step 5: Update _build_buy_grid() — wrap cards in slot VBoxContainer with price label**

Each slot becomes: VBoxContainer > [card PanelContainer, price Label]

```gdscript
func _build_buy_grid() -> void:
    _clear_buy_grid()
    for offer in _offerings:
        var slot := VBoxContainer.new()
        slot.alignment = BoxContainer.ALIGNMENT_CENTER
        slot.add_theme_constant_override("separation", 4)
        slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

        var card := _create_offer_card(offer)
        slot.add_child(card)

        var price_label := Label.new()
        price_label.text = "%d gold" % offer.price
        price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        price_label.add_theme_color_override("font_color", UiTheme.ACCENT)
        price_label.add_theme_font_size_override("font_size", 18)
        slot.add_child(price_label)

        _buy_container.add_child(slot)
```

- [ ] **Step 6: Update _refresh_gold() — show "GOLD: X" format**

```gdscript
func _refresh_gold() -> void:
    var player := get_tree().get_first_node_in_group("player")
    if player:
        var wallet := player.get_node_or_null("WalletComponent")
        if wallet:
            _gold_label.text = "GOLD: %d" % wallet.gold
```

- [ ] **Step 7: Add entrance animation**

In `open()`, add stagger slide-in for cards and fade for header/action:

```gdscript
func open(offerings: Array[ShopOffer]) -> void:
    _offerings = offerings
    _remove_count = 0
    _refresh_gold()
    _build_buy_grid()
    _build_remove_section()
    SceneManager.set_paused(true)
    visible = true
    _play_entrance_animation()

func _play_entrance_animation() -> void:
    var cards: Array[Control] = []
    for child in _buy_container.get_children():
        var slot := child as Control
        if slot:
            slot.position.y += 20
            slot.modulate.a = 0.0
            cards.append(slot)
    for i in cards.size():
        var tween := cards[i].create_tween()
        tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
        tween.tween_interval(0.08 * i)
        tween.parallel().tween_property(cards[i], "position:y", cards[i].position.y - 20, 0.3).set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_OUT)
        tween.parallel().tween_property(cards[i], "modulate:a", 1.0, 0.3)
```

- [ ] **Step 8: Remove _title_label from _ready() and verify no stale references**

The _title_label variable is no longer needed. In the new scene, the TitleLabel is a child of HeaderBar but doesn't need a script reference since its text never changes.

- [ ] **Step 9: Add reroll signal (stub)**

For future wiring, add a signal and connect the reroll button:

```gdscript
signal reroll_requested

func _ready() -> void:
    ...
    _reroll_button.pressed.connect(_on_reroll_pressed)
    ...

func _on_reroll_pressed() -> void:
    reroll_requested.emit()
```

---

### Task 3: Verify everything works

- [ ] **Step 1: Verify scene loads without errors**

Run: `godot --headless --check-only scenes/economy/shop_ui.tscn`
Expected: No errors (exit code 0)

Or open the project in the editor and open the shop scene.

- [ ] **Step 2: Check the shop opens in-game**

Run the game, trigger the shop (check input_handler.gd for dev key, likely U), verify:
- The new layout appears centered
- Header shows "SHOP" and "GOLD: X"
- 3 offer cards in a row with price labels below
- Action bar with REROLL, REMOVE MODIFIER, CLOSE buttons
- Cards glow/scale on hover
- Clicking a card buys it

- [ ] **Step 3: Test edge cases**

- Buy all offers → empty buy container
- Remove modifier → verify button state updates
- Open with 0, 1, 2, 3 offers → verify layout adapts
- Close via overlay click, pause key, close button

---

### Task 4: Commit

- [ ] **Step 1: Stage and commit**

```bash
git add scenes/economy/shop_ui.tscn src/economy/shop_ui.gd
git commit -m "feat: redesign shop UI with Balatro-style layout

- New scene hierarchy: HeaderBar, card row, ActionBar
- Cards show icon/name/desc, price label below card
- Click card to buy (no separate buy button)
- Reroll button with signal (stub)
- Entrance animation with stagger slide-in
- Custom StyleBoxFlat for header/action bars
```
