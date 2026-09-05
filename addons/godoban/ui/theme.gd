@tool
extends RefCounted
## Central design tokens + StyleBox helpers. Near-black, flat and minimal —
## tuned after Linear's dark theme: layered surfaces, a single indigo accent
## for interactive/active emphasis, and semantic colors for status only. The
## whole palette lives here so it can't drift between screens.

const BG := Color("#0f1011")           # page canvas (darkest layer)
const BG_PANEL := Color("#14151a")     # columns, toolbars, panels
const BG_CARD := Color("#1a1c22")      # cards, inputs
const BG_HOVER := Color("#22252c")     # cards / controls on hover
const BG_INPUT := Color("#191b20")     # text fields / control surfaces
const BORDER := Color("#34363f")       # visible borders
const BORDER_SOFT := Color("#242632")  # subtle separators, card hairlines
const TEXT := Color("#eef0f3")
const TEXT_DIM := Color("#9aa1ad")
const TEXT_FAINT := Color("#5f646d")
const ACCENT := Color("#5e6ad2")       # signature indigo (actions, active, focus)
const ACCENT_HOVER := Color("#6b77e6") # accent surfaces on hover
const ACCENT_TEXT := Color("#f7f8fa")  # text sitting on accent surfaces
const OVERDUE := Color("#eb5757")

# Godoban status colors — the popular convention: neutral gray (not started),
# blue (up next), amber (active), purple (in review), green (done).
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
# by the Overview's by-priority bar comparison.
const PRIORITY_COLORS := {
	"low": Color("#3fae74"),
	"medium": Color("#4a9ff2"),
	"high": Color("#f0a832"),
	"critical": Color("#eb5757"),
}


static func priority_color(priority: String) -> Color:
	return PRIORITY_COLORS.get(priority, Color("#6b7280"))

const I = preload("res://addons/godoban/ui/icons.gd")
const FONT_PATH := "res://addons/godoban/fonts/geist_variable.ttf"
static var _theme: Theme


## The shared root theme. Applying this (via `Control.theme`) sets Geist as the
## default font + size for every control that inherits it, so individual
## font_size overrides elsewhere keep working on top. Built lazily + cached.
static func theme() -> Theme:
	if _theme == null:
		_theme = Theme.new()
		_theme.default_font_size = 13
		var f := load(FONT_PATH) as FontFile
		if f != null:
			_theme.default_font = f
	return _theme


static func panel(bg := BG_PANEL, border := BORDER_SOFT, radius := 8,
		ml := 10, mr := 10, mt := 8, mb := 8, border_w := 1) -> StyleBoxFlat:
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
		# Primary action: solid brand accent with near-white text. Reads as the
		# one intentional accent on the page rather than a dimmed float.
		b.add_theme_stylebox_override("normal", panel(ACCENT, ACCENT.lightened(0.08), 6, 12, 12, 5, 5, 1))
		b.add_theme_stylebox_override("hover", panel(ACCENT_HOVER, ACCENT.lightened(0.10), 6, 12, 12, 5, 5, 1))
		b.add_theme_stylebox_override("pressed", panel(ACCENT.darkened(0.12), ACCENT.darkened(0.04), 6, 12, 12, 5, 5, 1))
	else:
		b.add_theme_stylebox_override("normal", panel(BG_INPUT, BORDER, 6, 12, 12, 5, 5, 1))
		b.add_theme_stylebox_override("hover", panel(BG_HOVER, BORDER, 6, 12, 12, 5, 5, 1))
		b.add_theme_stylebox_override("pressed", panel(BG_INPUT.darkened(0.08), BORDER_SOFT, 6, 12, 12, 5, 5, 1))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var tc := ACCENT_TEXT if accent else TEXT
	for s in ["font_color", "font_hover_color", "font_pressed_color",
			"font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(s, tc)


static func flat_button(b) -> void:
	b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("hover", pill(Color(1, 1, 1, 0.06)))
	b.add_theme_stylebox_override("pressed", pill(Color(1, 1, 1, 0.10)))
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
			Color(1, 1, 1, 0.07), Color(1, 1, 1, 0), 8, 18, 18, 8, 8, 1))
	b.add_theme_stylebox_override("pressed", panel(
			ACCENT.darkened(0.5), ACCENT.darkened(0.05), 8, 18, 18, 8, 8, 1))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var font := ACCENT_TEXT if active else TEXT_DIM
	var hover_font := ACCENT_TEXT if active else TEXT
	b.add_theme_color_override("font_color", font)
	b.add_theme_color_override("font_hover_color", hover_font)
	b.add_theme_color_override("font_pressed_color", ACCENT_TEXT)
	b.add_theme_color_override("font_hover_pressed_color", ACCENT_TEXT)
	b.add_theme_color_override("font_focus_color", font)


static func field(control) -> void:
	control.add_theme_stylebox_override("normal", panel(BG_INPUT, BORDER, 6, 9, 9, 5, 5, 1))
	control.add_theme_stylebox_override("hover", panel(BG_INPUT, ACCENT.darkened(0.15), 6, 9, 9, 5, 5, 1))
	control.add_theme_stylebox_override("pressed", panel(BG_INPUT.darkened(0.08), BORDER_SOFT, 6, 9, 9, 5, 5, 1))
	control.add_theme_stylebox_override("focus", panel(BG_INPUT, ACCENT, 6, 9, 9, 5, 5, 1))
	control.add_theme_stylebox_override("focus_empty", panel(BG_INPUT, ACCENT, 6, 9, 9, 5, 5, 1))
