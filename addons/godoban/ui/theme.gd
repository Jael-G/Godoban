@tool
extends RefCounted
## Central design tokens + StyleBox helpers. Chroma resolves from Godot's own
## editor theme at runtime so the plugin reads as part of the editor — the editor
## registers its ThemeContext on the root, so any color we don't hard-code falls
## through to it. Only semantic colors (status, priority, overdue) and user-chosen
## epic colors stay custom — those are authored for intent, not for theming.

const I = preload("res://addons/godoban/ui/icons.gd")
const FONT_PATH := "res://addons/godoban/fonts/geist_variable.ttf"
static var _theme: Theme


## Read a color registered under the editor theme's "Editor" type. Guarded so the
## script never faults outside the editor (a hedge for any non-`@tool` path).
## Returns the editor's standard light text as a neutral fallback.
static func _editor_color(name: String) -> Color:
	var t := _editor_theme()
	return t.get_color(name, "Editor") if t != null else Color("#eef0f3")


## Dark/light detection from the editor's own constant (1 = dark, 0 = light),
## falling back to a luminance check outside the editor.
static func _editor_dark() -> bool:
	var t := _editor_theme()
	if t != null:
		return t.get_constant("dark_theme", "Editor") != 0
	return Color("#0f1011").get_luminance() < 0.5


static func _editor_theme() -> Theme:
	if Engine.is_editor_hint():
		return EditorInterface.get_editor_theme()
	return null


## A translucent overlay that reads on both surfaces: white on dark themes, black
## on light. Used for hover/pressed tints on flat + tab buttons.
static func _overlay(alpha: float) -> Color:
	return Color(1, 1, 1, alpha) if _editor_dark() else Color(0, 0, 0, alpha)


# --- Surface / chrome tokens ----------------------------------------------------
# These are runtime data, so each is a static func (not const — GDScript consts are
# compile-time and the editor palette can change with the theme). Elevation inverts
# with dark/light, so surfaces are never hard-coded to "near black".

# Page canvas (darkest editor layer) / the editor's dark panel surface.
static func BG() -> Color: return _editor_color("background")
static func BG_PANEL() -> Color: return _editor_color("dark_color_1")
# Cards and inputs sit a step lighter (the editor's base surface).
static func BG_CARD() -> Color: return _editor_color("base_color")
static func BG_INPUT() -> Color: return _editor_color("base_color")
static func BG_HOVER() -> Color:
	return BG_CARD().lerp(Color.WHITE if _editor_dark() else Color(0.1, 0.1, 0.1), 0.10)

static func BORDER() -> Color: return _editor_color("contrast_color_2")
static func BORDER_SOFT() -> Color: return _editor_color("separator_color")
# A border with real contrast against the surface, for places where the border IS the
# affordance (the clickable board chip). contrast_color_2 is meant to stay faint, so at
# 1px it vanishes into base_color; this lifts (dark) / drops (light) from the chip's own
# background so the outline reads clearly in both themes.
static func BORDER_STRONG() -> Color:
	return BG_INPUT().lerp(Color.WHITE if _editor_dark() else Color(0, 0, 0), 0.30)
static func TEXT() -> Color: return _editor_color("font_color")
static func TEXT_DIM() -> Color: return _editor_color("font_placeholder_color")
static func TEXT_FAINT() -> Color: return _editor_color("font_disabled_color")
static func ACCENT() -> Color: return _editor_color("accent_color")
static func ACCENT_HOVER() -> Color: return ACCENT().lerp(TEXT(), 0.12)
# Text sitting on the accent: white in the dark editor theme, near-black in the
# light one — mirroring how Godot renders its own accent-colored buttons.
static func ACCENT_TEXT() -> Color:
	return Color("#0f1011") if not _editor_dark() else Color.WHITE
# Display-only shortening for single-line surfaces whose width must not follow their text
# (the board chip, the switcher rows): anything past `max_chars` is dropped and an ellipsis
# appended. Character-based rather than width-based, so callers get a hard, predictable
# ceiling regardless of the glyphs involved; the full string stays in the data and in the
# caller's tooltip. Never write this back to the model — it's presentation only.
static func elide(text: String, max_chars: int) -> String:
	if max_chars < 2 or text.length() <= max_chars:
		return text
	return text.substr(0, max_chars - 1).strip_edges() + "…"


# Godoban status colors — the popular convention: neutral gray (not started),
# blue (up next), amber (active), purple (in review), green (done). Kept custom:
# these are semantic, not chrome.
const STATUS_COLORS := {
	"backlog": Color("#6b7280"),
	"todo": Color("#4a9ff2"),
	"in_progress": Color("#f0a832"),
	"review": Color("#8b5cf6"),
	"done": Color("#3fae74"),
}


static func status_color(status: String) -> Color:
	return STATUS_COLORS.get(status, Color("#6b7280"))

# Priority colors — a semantic severity scale (green → blue → amber → red) used
# by the Overview's by-priority bar comparison. Kept custom for intent.
const PRIORITY_COLORS := {
	"low": Color("#3fae74"),
	"medium": Color("#4a9ff2"),
	"high": Color("#f0a832"),
	"critical": Color("#eb5757"),
}


static func priority_color(priority: String) -> Color:
	return PRIORITY_COLORS.get(priority, Color("#6b7280"))

# Overdue marker — a semantic "error" red, kept literal like the status colors.
const OVERDUE := Color("#eb5757")


## The shared root theme. Applying this (via `Control.theme`) sets Geist as the
## default font + size for every control that inherits it, so individual
## font_size overrides elsewhere keep working on top. Font-only on purpose: no
## colors are set here, so every color still resolves through to the editor theme.
## Built lazily + cached.
static func theme() -> Theme:
	if _theme == null:
		_theme = Theme.new()
		_theme.default_font_size = 13
		var f := load(FONT_PATH) as FontFile
		if f != null:
			_theme.default_font = f
	return _theme


## A bold, gently letter-spaced FontVariation for prominent labels (the board chip,
## dialog titles). Uses the theme's Geist face so the embolden matches the same
## family, plus a small tracking (spacing_glyph) to help it read as a heading
## rather than body text. Callers set `font_size` separately via a size override.
static func title_font(embolden := 0.7, spacing := 1.0) -> FontVariation:
	var fv := FontVariation.new()
	var base := load(FONT_PATH) as FontFile
	if base != null:
		fv.base_font = base
	fv.variation_embolden = embolden
	fv.spacing_glyph = spacing
	return fv


## A flat panel. `bg` and `border` are required so the palette always comes from
## the caller (which reads the editor theme); the numeric args carry the spacing
## geometry.
static func panel(bg: Color, border: Color, radius := 8, ml := 10, mr := 10,
		mt := 8, mb := 8, border_w := 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(0)
	s.content_margin_left = ml
	s.content_margin_right = mr
	s.content_margin_top = mt
	s.content_margin_bottom = mb
	return s


static func pill(bg: Color, radius := 4) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_border_width_all(0)
	s.content_margin_left = 7
	s.content_margin_right = 7
	s.content_margin_top = 1
	s.content_margin_bottom = 1
	return s


static func button(b, accent := false) -> void:
	if accent:
		# Primary action: solid brand accent with contrasting text.
		b.add_theme_stylebox_override("normal", panel(ACCENT(), ACCENT().lightened(0.08), 6, 12, 12, 5, 5, 1))
		b.add_theme_stylebox_override("hover", panel(ACCENT_HOVER(), ACCENT().lightened(0.10), 6, 12, 12, 5, 5, 1))
		b.add_theme_stylebox_override("pressed", panel(ACCENT().darkened(0.12), ACCENT().darkened(0.04), 6, 12, 12, 5, 5, 1))
	else:
		b.add_theme_stylebox_override("normal", panel(BG_INPUT(), BORDER(), 6, 12, 12, 5, 5, 1))
		b.add_theme_stylebox_override("hover", panel(BG_HOVER(), BORDER(), 6, 12, 12, 5, 5, 1))
		b.add_theme_stylebox_override("pressed", panel(BG_INPUT().darkened(0.08), BORDER_SOFT(), 6, 12, 12, 5, 5, 1))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var tc := ACCENT_TEXT() if accent else TEXT()
	for s in ["font_color", "font_hover_color", "font_pressed_color",
			"font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(s, tc)


static func flat_button(b) -> void:
	b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("hover", pill(_overlay(0.06)))
	b.add_theme_stylebox_override("pressed", pill(_overlay(0.10)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


## A white chevron used by the collapse/expand toggles. `down` true draws "⌄"
## (collapse action); false draws "›" (expand action). A Lucide glyph (see icons.gd),
## tintable via the caller's icon color override.
static func arrow_icon(down := true, size := 16) -> ImageTexture:
	return I.chevron_down(size) if down else I.chevron_right(size)


## A rounded hoverable row surface, used for list rows (epics, options). Full
## width, with comfortable padding; a faint fill appears on hover only.
static func row_surface() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(1, 1, 1, 0)
	s.set_corner_radius_all(6)
	s.set_border_width_all(0)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


## Top-level tab button, styled like a website top bar. Unselected tabs are
## transparent; hovering shows a faint rounded "dim" square; the selected tab is
## a solid accent surface. All three states share identical content margins +
## 1px border widths, so switching tabs never shifts the bar's geometry.
static func tab_button(b, active := false) -> void:
	b.add_theme_stylebox_override("normal", panel(
			Color(1, 1, 1, 0), Color(1, 1, 1, 0), 8, 18, 18, 8, 8, 1))
	b.add_theme_stylebox_override("hover", panel(
			_overlay(0.07), Color(1, 1, 1, 0), 8, 18, 18, 8, 8, 1))
	b.add_theme_stylebox_override("pressed", panel(
			ACCENT().darkened(0.5), ACCENT().darkened(0.05), 8, 18, 18, 8, 8, 1))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var font := ACCENT_TEXT() if active else TEXT_DIM()
	var hover_font := ACCENT_TEXT() if active else TEXT()
	b.add_theme_color_override("font_color", font)
	b.add_theme_color_override("font_hover_color", hover_font)
	b.add_theme_color_override("font_pressed_color", ACCENT_TEXT())
	b.add_theme_color_override("font_hover_pressed_color", ACCENT_TEXT())
	b.add_theme_color_override("font_focus_color", font)


static func field(control) -> void:
	control.add_theme_stylebox_override("normal", panel(BG_INPUT(), BORDER(), 6, 9, 9, 5, 5, 1))
	control.add_theme_stylebox_override("hover", panel(BG_INPUT(), ACCENT().darkened(0.15), 6, 9, 9, 5, 5, 1))
	control.add_theme_stylebox_override("pressed", panel(BG_INPUT().darkened(0.08), BORDER_SOFT(), 6, 9, 9, 5, 5, 1))
	control.add_theme_stylebox_override("focus", panel(BG_INPUT(), ACCENT(), 6, 9, 9, 5, 5, 1))
	control.add_theme_stylebox_override("focus_empty", panel(BG_INPUT(), ACCENT(), 6, 9, 9, 5, 5, 1))
