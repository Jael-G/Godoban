@tool
extends PopupPanel

## Manage epics inline: each epic is a row with a color square (opens Godot's
## color picker) next to an editable title field. Edit in place, then Save to
## commit everything — new, renamed, recolored and deleted epics — or Cancel to
## discard it all. Uncommitted edits never touch the store, so Cancel reliably
## undoes them. Deletion is staged too (a removed row reappears on Cancel).

const T = preload("res://addons/godoban/ui/theme.gd")
const I = preload("res://addons/godoban/ui/icons.gd")
const ColorSwatch = preload("res://addons/godoban/ui/color_swatch.gd")

signal changed(epic_id: String)

var store: RefCounted
var _drafts: Array = []      # working copies: {"id", "title", "color"}
var _removed: Array = []     # ids deleted this session, staged until Save
var _focus_index := -1       # row whose title should grab focus after rebuild

var _head_count: Label
var _rows: VBoxContainer
var _add_btn: Button
var _focus_edit: LineEdit


func setup(p_store: RefCounted) -> void:
	store = p_store
	_build()


func _build() -> void:
	title = "Epics"
	add_theme_stylebox_override("panel", T.panel(T.BG_PANEL(), T.BORDER_SOFT(), 10, 16, 16, 14, 14, 1))

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.custom_minimum_size = Vector2(400, 0)
	add_child(v)

	v.add_child(_build_header())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 150)
	v.add_child(scroll)

	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 4)
	scroll.add_child(_rows)

	_add_btn = Button.new()
	_add_btn.text = "+  New epic"
	_add_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_btn.add_theme_font_size_override("font_size", 14)
	_add_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	T.button(_add_btn)
	_add_btn.pressed.connect(_add_epic)
	v.add_child(_add_btn)

	var sep := HSeparator.new()
	v.add_child(sep)

	v.add_child(_build_footer())


func _build_header() -> Control:
	var h := HBoxContainer.new()
	var t := Label.new()
	t.text = "Epics"
	t.add_theme_font_size_override("font_size", 15)
	h.add_child(t)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)
	_head_count = Label.new()
	_head_count.add_theme_color_override("font_color", T.TEXT_FAINT())
	h.add_child(_head_count)
	return h


func _build_footer() -> Control:
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)

	var cancel := Button.new()
	cancel.text = "Cancel"
	T.button(cancel)
	cancel.pressed.connect(_cancel)
	footer.add_child(cancel)

	var save := Button.new()
	save.text = "Save"
	T.button(save, true)
	save.pressed.connect(_save)
	footer.add_child(save)

	return footer


func open() -> void:
	_drafts = []
	_removed = []
	for e in store.board.epics:
		_drafts.append({"id": e.id, "title": e.title, "color": e.color})
	_focus_index = -1
	_rebuild_rows()
	popup_centered()


func _rebuild_rows() -> void:
	for c in _rows.get_children():
		c.free()
	var n: int = _drafts.size()
	_head_count.text = "%d %s" % [n, "epic" if n == 1 else "epics"]
	if _drafts.is_empty():
		var empty := Label.new()
		empty.text = "No epics yet — press New epic."
		empty.add_theme_color_override("font_color", T.TEXT_FAINT())
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_rows.add_child(empty)
		return
	for i in _drafts.size():
		_rows.add_child(_build_row(_drafts[i], i))
	_focus_target()


func _build_row(d: Dictionary, idx: int) -> Control:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("normal", T.row_surface())
	row.add_theme_stylebox_override("hover", T.row_surface())
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	row.add_child(h)

	var sw := ColorSwatch.new()
	sw.set_color(Color(String(d["color"])))
	sw.color_changed.connect(_on_color.bind(d))
	h.add_child(sw)

	var title := LineEdit.new()
	title.text = String(d["title"])
	title.placeholder_text = "Epic title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	T.field(title)
	title.text_changed.connect(_on_title.bind(d))
	title.text_submitted.connect(_save)
	if idx == _focus_index:
		_focus_edit = title
	h.add_child(title)

	var del := Button.new()
	del.icon = I.icon("x", 14)
	del.flat = true
	del.tooltip_text = "Delete"
	T.flat_button(del)
	del.add_theme_color_override("icon_normal_color", T.TEXT_FAINT())
	del.add_theme_color_override("icon_hover_color", T.OVERDUE)
	del.add_theme_color_override("icon_pressed_color", T.OVERDUE)
	del.pressed.connect(_remove_row.bind(d))
	h.add_child(del)

	return row


func _focus_target() -> void:
	if _focus_edit != null:
		_focus_edit.grab_focus()
		_focus_edit.select_all()
	_focus_edit = null
	_focus_index = -1


func _on_title(text: String, d: Dictionary) -> void:
	d["title"] = text


func _on_color(c: Color, d: Dictionary) -> void:
	d["color"] = c.to_html(false)


func _add_epic() -> void:
	_drafts.append({"id": "", "title": "", "color": T.ACCENT().to_html(false)})
	_focus_index = _drafts.size() - 1
	_rebuild_rows()


func _remove_row(d: Dictionary) -> void:
	var id := String(d["id"])
	if id != "" and not _removed.has(id):
		_removed.append(id)
	_drafts.erase(d)
	_focus_index = -1
	# Defer: this runs from the row's delete button, and _rebuild_rows free()s
	# every row — including the button whose `pressed` signal is still emitting.
	call_deferred("_rebuild_rows")


func _cancel() -> void:
	hide()


func _save() -> void:
	var first := ""
	for d in _drafts:
		var t := String(d["title"]).strip_edges()
		if t == "":
			continue
		var id := String(d["id"])
		if id == "":
			id = store.board.new_id("epic")
		if first == "":
			first = id
		store.upsert_epic(id, t, String(d["color"]))
	for id in _removed:
		store.delete_epic(id)
	changed.emit(first)
	hide()
