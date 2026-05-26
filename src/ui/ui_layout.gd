class_name UILayout
extends RefCounted

## Single source of truth for UI layout magic numbers. Referenced by
## ModalPanel, HUD, and theme variations in UiTheme. No .tscn file
## should hardcode layout integers that exist here.

# Spacing scale (px). XS only for inline gaps inside rows.
const XS := 4
const S  := 8
const M  := 16
const L  := 24
const XL := 32

# Modal widths.
const MODAL_SM := 320
const MODAL_MD := 480
const MODAL_LG := 640
enum ModalWidth { SM, MD, LG }

static func modal_width_for(w: ModalWidth) -> int:
	match w:
		ModalWidth.SM: return MODAL_SM
		ModalWidth.MD: return MODAL_MD
		ModalWidth.LG: return MODAL_LG
	return MODAL_MD

# Inner padding for every ModalPanel.
const PANEL_PAD_X := 24
const PANEL_PAD_Y := 24

# HUD gutter from screen edge.
const HUD_GUTTER := 16

# Buttons.
const BUTTON_MIN_HEIGHT        := 40
const BUTTON_COMPACT_MIN_WIDTH := 96
const BUTTON_ICON_SIZE         := 32

# Title bar + separators.
const TITLE_BAR_HEIGHT := 48
const SEPARATOR_PAD    := 8
