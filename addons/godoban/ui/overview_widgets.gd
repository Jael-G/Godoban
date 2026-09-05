@tool
extends Control

## Small self-drawn widgets used only by the Overview tab: a ring progress
## indicator, a donut/ring chart, and a vertical-bar comparison. Each is a plain
## Control that renders in `_draw()`, so they stay resolution-independent and
## pick up the theme's font for their text. They never touch the store — the
## overview feeds them data.

const T = preload("res://addons/godoban/ui/theme.gd")


# --- Ring progress -----------------------------------------------------------
# A thin circular arc that fills clockwise from the top. Used inside the summary
# stat cards to show a percentage at a glance without a big chart.
class RingProgress:
	extends Control

	var value := 0.0        # 0.0..1.0
	var ring_color := T.ACCENT
	var track_color := T.BORDER

	func _init() -> void:
		custom_minimum_size = Vector2(46, 46)

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 4.0
		var w := 4.0
		draw_arc(c, r, 0.0, TAU, 64, track_color, w, true)
		var v := clampf(value, 0.0, 1.0)
		if v > 0.001:
			draw_arc(c, r, -PI / 2.0, -PI / 2.0 + TAU * v, 64, ring_color, w, true)


# --- Donut chart -------------------------------------------------------------
# A donut/ring breakdown of the board by status, with the total in the center.
class Donut:
	extends Control

	var segments: Array = []   # [{ "color": Color, "value": float }]
	var total: int = 0
	var center_title := "Total"
	var font: Font

	func _init() -> void:
		custom_minimum_size = Vector2(156, 156)

	func _draw() -> void:
		var c := size * 0.5
		var w := 16.0
		var r := minf(size.x, size.y) * 0.5 - w * 0.5 - 1.0
		var f: Font = font if font != null else get_theme_default_font()

		# A faint full track behind the slices reads as an empty ring and shows up
		# as the thin separator between slices.
		draw_arc(c, r, 0.0, TAU, 96, T.BORDER, w, true)

		var totalv := 0.0
		for s in segments:
			totalv += float(s.value)
		if totalv > 0.0:
			var gap := 0.022
			var acc := -PI / 2.0
			for s in segments:
				var frac := float(s.value) / totalv
				if frac <= 0.0:
					continue
				var span := TAU * frac
				var a0 := acc
				var a1 := acc + span
				if span > gap * 2.0:
					a0 += gap
					a1 -= gap
				draw_arc(c, r, a0, a1, 96, s.color, w, true)
				acc += span

		# Center: the big total, with a dim label underneath.
		_center_string(f, c + Vector2(0, 8), str(total), 24, T.TEXT)
		_center_string(f, c + Vector2(0, 30), center_title, 12, T.TEXT_DIM)

	func _center_string(f: Font, pos: Vector2, text: String, fs: int, color: Color) -> void:
		var wt := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, pos + Vector2(-wt * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


# --- Vertical bars -----------------------------------------------------------
# A compact vertical-bar comparison, one bar per priority, each labelled below
# with its task count above. Bar height is scaled against the tallest category.
class VBars:
	extends Control

	var bars: Array = []    # [{ "color": Color, "value": int, "label": String }]
	var font: Font

	func _init() -> void:
		custom_minimum_size = Vector2(0, 128)

	func _draw() -> void:
		var f: Font = font if font != null else get_theme_default_font()
		if bars.is_empty():
			return
		var maxv := 1
		for b in bars:
			maxv = maxi(maxv, int(b.value))
		var pad_top := 20.0
		var pad_bottom := 22.0
		var area_h := size.y - pad_top - pad_bottom
		var n := bars.size()
		var sep := 8.0
		var slot := (size.x - sep * float(n + 1)) / float(n)
		var bar_w := slot * 0.4
		var x := sep
		for b in bars:
			var h := area_h * float(b.value) / float(maxv)
			if b.value > 0 and h < 2.0:
				h = 2.0
			var by := pad_top + (area_h - h)
			draw_rect(Rect2(x + (slot - bar_w) * 0.5, by, bar_w, h), b.color, true)
			var cs := str(b.value)
			draw_string(f, Vector2(x + slot * 0.5 - f.get_string_size(cs, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x * 0.5, by - 4),
					cs, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, T.TEXT)
			var lbl := str(b.label)
			draw_string(f, Vector2(x + slot * 0.5 - f.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x * 0.5, size.y - 6),
					lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, T.TEXT_DIM)
			x += slot + sep
