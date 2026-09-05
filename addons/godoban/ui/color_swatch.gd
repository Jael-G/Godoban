@tool
extends Button

## A rounded color square that opens Godot's ColorPicker (color wheel + sliders)
## in a popup when clicked. The square always reflects the current color; picking
## a new color emits `color_changed`. Used as the accent square next to an epic's
## title in the epics dialog.

signal color_changed(color: Color)

const T = preload("res://addons/godoban/ui/theme.gd")

var _color := T.ACCENT
var _popup: PopupPanel
var _picker: ColorPicker


func _init() -> void:
	custom_minimum_size = Vector2(26, 26)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pressed.connect(_open_popup)


## Set the color without emitting color_changed (used on load).
func set_color(c: Color) -> void:
	_color = c
	_apply()


func get_color() -> Color:
	return _color


func _apply() -> void:
	add_theme_stylebox_override("normal", _style(_color))
	add_theme_stylebox_override("hover", _style(_color.lightened(0.07)))
	add_theme_stylebox_override("pressed", _style(_color.darkened(0.12)))
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if _picker != null:
		_picker.color = _color


func _style(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(6)
	s.set_border_width_all(1)
	s.border_color = Color(1, 1, 1, 0.14)
	return s


func _build_popup() -> void:
	_popup = PopupPanel.new()
	_popup.exclusive = true
	_popup.add_theme_stylebox_override("panel", T.panel(T.BG_PANEL, T.BORDER, 8, 8, 8, 8, 8, 1))
	_picker = ColorPicker.new()
	_picker.color = _color
	_picker.edit_alpha = false
	_picker.color_changed.connect(_on_picker)
	_popup.add_child(_picker)
	add_child(_popup)


func _open_popup() -> void:
	if _popup == null:
		_build_popup()
	_picker.color = _color
	_popup.popup()
	call_deferred("_position_popup")


func _position_popup() -> void:
	var global := get_global_rect()
	var size := _popup.size
	var win := get_window()
	var anchor: Vector2 = win.position if win != null else Vector2.ZERO
	var x: float = anchor.x + global.position.x + global.size.x * 0.5 - size.x * 0.5
	var y: float = anchor.y + global.position.y + global.size.y + 4
	_popup.position = Vector2i(maxi(0, int(x)), maxi(0, int(y)))


func _on_picker(c: Color) -> void:
	if c == _color:
		return
	_color = c
	_apply()
	color_changed.emit(c)
