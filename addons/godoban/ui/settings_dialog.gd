@tool
extends "res://addons/godoban/ui/modal_overlay.gd"

## The plugin's settings, opened from the cog at the right end of the tab bar.
##
## One setting so far: the font size every other surface is drawn at. The dialog holds no state of
## its own — it reads and writes `godoban_settings.gd` and repaints from it — so a rebuild costs
## nothing but a re-read, and it can't disagree with the size the board is using.
##
## Chrome comes from `modal_overlay.gd`; `T`, `I` and the shared row helpers are inherited from it.

const Settings = preload("res://addons/godoban/data/godoban_settings.gd")

## Emitted after the stepper has written a new size. The main screen re-applies the type scale; the
## dialog leaves that to it, because the rebuild frees the button that is mid-`pressed` right now.
signal font_size_changed

## Kept as members so `_on_rebuilt` can repaint them after a rebuild.
var _value: Label
var _minus: Button
var _plus: Button


func setup() -> void:
	_build()
	_on_rebuilt()


func open() -> void:
	_sync()
	_show_modal()


## Everything that follows `_build()` — run once at setup and again by `rebuild_for_theme`.
func _on_rebuilt() -> void:
	_sync()


func _modal_icon() -> String:
	return "settings"


func _modal_title() -> String:
	return "Settings"


func _build_body(v: VBoxContainer) -> void:
	v.add_child(_caption("Font size"))
	v.add_child(_build_size_panel())

	var done := Button.new()
	done.text = "Done"
	done.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	T.button(done, true)
	done.pressed.connect(_cancel)
	v.add_child(done)


## A dim section caption, the same "small print above a block" the task editor uses.
func _caption(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", T.fs(11))
	l.add_theme_color_override("font_color", T.TEXT_DIM())
	return l


## The size control: a −/+ stepper. Each press applies straight away — the board behind the dialog
## re-renders on the click, which is what makes the board itself the preview.
func _build_size_panel() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",
		T.panel(T.BG_INPUT(), T.BORDER(), 8, 10, 10, 9, 9, 1))

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	v.add_child(row)

	var label := Label.new()
	label.text = "Size"
	label.add_theme_font_size_override("font_size", T.fs(12))
	label.add_theme_color_override("font_color", T.TEXT())
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	_minus = _stepper_button("minus", "Smaller")
	_minus.pressed.connect(_step.bind(-1))
	row.add_child(_minus)

	# Fixed width so the row doesn't twitch as the number gains a digit; scaled so it still fits.
	_value = Label.new()
	_value.custom_minimum_size.x = T.px(34)
	_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_value.add_theme_font_size_override("font_size", T.fs(14))
	_value.add_theme_font_override("font", T.title_font(0.7, 1.0))
	_value.add_theme_color_override("font_color", T.TEXT())
	row.add_child(_value)

	_plus = _stepper_button("plus", "Larger")
	_plus.pressed.connect(_step.bind(1))
	row.add_child(_plus)

	return panel


## A stepper glyph in the flat-button idiom: no chrome, hand cursor, tinted via the icon overrides.
func _stepper_button(kind: String, tooltip: String) -> Button:
	var b := Button.new()
	b.flat = true
	b.icon = I.icon(kind, 14)
	b.tooltip_text = tooltip
	b.custom_minimum_size = Vector2(24, 24)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.focus_mode = Control.FOCUS_NONE
	T.flat_button(b)
	_tint_button_icon(b, T.TEXT_DIM(), T.TEXT())
	# `_tint_button_icon` leaves the disabled state unset, which a stepper at the end of its range is.
	b.add_theme_color_override("icon_disabled_color", T.TEXT_FAINT())
	return b


## Repaint from the settings as they stand — the one place the dialog reads state.
func _sync() -> void:
	if _value == null:
		return
	var offset := Settings.font_offset()

	_value.text = str(Settings.font_size())
	_minus.disabled = offset <= -Settings.OFFSET_SPAN
	_plus.disabled = offset >= Settings.OFFSET_SPAN


func _step(delta: int) -> void:
	Settings.set_font_offset(Settings.font_offset() + delta)
	# Repaint before handing over: the rebuild is deferred, so the number would otherwise lag a frame.
	_sync()
	font_size_changed.emit()
