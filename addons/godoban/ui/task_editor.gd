@tool
extends PanelContainer

## Create/edit sidebar. Validates a non-empty title, then store.upsert_task.

const Model = preload("res://addons/godoban/data/godoban_model.gd")
const Calendar = preload("res://addons/godoban/ui/calendar_popup.gd")
const T = preload("res://addons/godoban/ui/theme.gd")
const I = preload("res://addons/godoban/ui/icons.gd")

signal closed
signal new_epic_requested

var store: RefCounted
var editing_id := ""  # "" == new task
var _default_status := "backlog"
var _due_ts := 0
var _tags: Array = []

var _title: LineEdit
var _status_btn: OptionButton
var _priority_btn: OptionButton
var _epic_btn: OptionButton
var _epic_add: Button
var _due_btn: Button
var _tag_input: LineEdit
var _tags_box: HBoxContainer
var _desc: TextEdit
var _save_btn: Button
var _delete_btn: Button
var _calendar: Calendar
var _confirm: PopupPanel

func setup(p_store: RefCounted) -> void:
	store = p_store
	_build()

func _build() -> void:
	custom_minimum_size.x = 340
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	add_theme_stylebox_override("panel", T.panel(T.BG_PANEL, T.BORDER, 0, 16, 16, 14, 14, 1))

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)

	var head := HBoxContainer.new()
	var t := Label.new()
	t.text = "Task"
	t.add_theme_font_size_override("font_size", 16)
	head.add_child(t)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var close := Button.new()
	close.icon = I.icon("x", 14)
	close.flat = true
	T.flat_button(close)
	close.add_theme_color_override("icon_normal_color", T.TEXT_DIM)
	close.add_theme_color_override("icon_hover_color", T.TEXT)
	close.add_theme_color_override("icon_pressed_color", T.TEXT)
	close.pressed.connect(_cancel)
	head.add_child(close)
	v.add_child(head)

	v.add_child(_label("Title"))
	_title = LineEdit.new()
	_title.placeholder_text = "Task title"
	T.field(_title)
	v.add_child(_title)

	v.add_child(_label("Status"))
	_status_btn = OptionButton.new()
	T.field(_status_btn)
	for s in Model.STATUSES:
		_status_btn.add_item(Model.status_title(s))
	v.add_child(_status_btn)

	v.add_child(_label("Priority"))
	_priority_btn = OptionButton.new()
	T.field(_priority_btn)
	for p in Model.PRIORITIES:
		_priority_btn.add_item(Model.priority_title(p))
	_priority_btn.select(1)  # medium
	v.add_child(_priority_btn)

	v.add_child(_label("Epic"))
	var epic_row := HBoxContainer.new()
	epic_row.add_theme_constant_override("separation", 8)
	_epic_btn = OptionButton.new()
	T.field(_epic_btn)
	_epic_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	epic_row.add_child(_epic_btn)
	_epic_add = Button.new()
	_epic_add.text = "+"
	_epic_add.flat = true
	T.flat_button(_epic_add)
	_epic_add.add_theme_color_override("font_color", T.TEXT_DIM)
	_epic_add.tooltip_text = "New epic"
	_epic_add.pressed.connect(func(): new_epic_requested.emit())
	epic_row.add_child(_epic_add)
	v.add_child(epic_row)

	v.add_child(_label("Due date"))
	_due_btn = Button.new()
	_due_btn.text = "No due date"
	T.button(_due_btn)
	_due_btn.pressed.connect(func(): _calendar.open_for_date(_due_ts))
	v.add_child(_due_btn)

	v.add_child(_label("Tags"))
	_tags_box = HBoxContainer.new()
	_tags_box.add_theme_constant_override("separation", 4)
	v.add_child(_tags_box)
	var tag_row := HBoxContainer.new()
	tag_row.add_theme_constant_override("separation", 8)
	_tag_input = LineEdit.new()
	_tag_input.placeholder_text = "Add tag (Enter)"
	T.field(_tag_input)
	_tag_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tag_input.text_submitted.connect(func(_s): _add_tag())
	tag_row.add_child(_tag_input)
	var add_tag := Button.new()
	add_tag.text = "Add"
	T.button(add_tag)
	add_tag.pressed.connect(_add_tag)
	tag_row.add_child(add_tag)
	v.add_child(tag_row)

	v.add_child(_label("Description"))
	_desc = TextEdit.new()
	T.field(_desc)
	_desc.custom_minimum_size.y = 120
	_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_desc)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	_delete_btn = Button.new()
	_delete_btn.text = "Delete"
	_style_danger(_delete_btn)
	_delete_btn.pressed.connect(_delete)
	footer.add_child(_delete_btn)
	var tail := Control.new()
	tail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(tail)
	var cancel := Button.new()
	cancel.text = "Cancel"
	T.button(cancel)
	cancel.pressed.connect(_cancel)
	footer.add_child(cancel)
	_save_btn = Button.new()
	_save_btn.text = "Add"
	T.button(_save_btn, true)
	_save_btn.pressed.connect(_save)
	footer.add_child(_save_btn)
	v.add_child(footer)

	_calendar = Calendar.new()
	add_child(_calendar)
	_calendar.date_selected.connect(_on_date_selected)

	_confirm = PopupPanel.new()
	_confirm.add_theme_stylebox_override("panel", T.panel(T.BG_PANEL, T.BORDER, 0, 24, 24, 24, 24, 2))
	_confirm.min_size = Vector2i(440, 0)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 14)
	_confirm.add_child(cv)
	var title_msg := Label.new()
	title_msg.text = "Delete task"
	title_msg.add_theme_font_size_override("font_size", 18)
	cv.add_child(title_msg)
	var msg := Label.new()
	msg.text = "Delete this task? This cannot be undone."
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.add_theme_font_size_override("font_size", 14)
	msg.add_theme_color_override("font_color", T.TEXT_DIM)
	msg.custom_minimum_size.x = 380
	cv.add_child(msg)
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 8)
	var csc := Control.new()
	csc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	crow.add_child(csc)
	var c_cancel := Button.new()
	c_cancel.text = "Cancel"
	T.button(c_cancel)
	c_cancel.pressed.connect(func(): _confirm.hide())
	crow.add_child(c_cancel)
	var c_del := Button.new()
	c_del.text = "Delete"
	_style_danger(c_del)
	c_del.pressed.connect(_do_delete)
	crow.add_child(c_del)
	cv.add_child(crow)
	add_child(_confirm)


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", T.TEXT_DIM)
	l.add_theme_font_size_override("font_size", 11)
	return l


func open_new(status: String) -> void:
	editing_id = ""
	_default_status = status
	_due_ts = 0
	_tags = []
	_title.text = ""
	_desc.text = ""
	_refresh_epics()
	_status_btn.select(Model.STATUSES.find(status))
	_priority_btn.select(1)
	_refresh_due()
	_refresh_tags()
	_save_btn.text = "Add"
	_delete_btn.visible = false
	visible = true
	_title.grab_focus()


func open_edit(task_id: String) -> void:
	var task = store.board.get_task(task_id)
	if task == null:
		return
	editing_id = task_id
	_default_status = task.status
	_due_ts = task.due_date
	_tags = task.tags.duplicate()
	_title.text = task.title
	_desc.text = task.description
	_refresh_epics()
	_status_btn.select(Model.STATUSES.find(task.status))
	_priority_btn.select(Model.PRIORITIES.find(task.priority))
	if task.epic_id != "":
		_select_epic(task.epic_id)
	_refresh_due()
	_refresh_tags()
	_save_btn.text = "Save"
	_delete_btn.visible = true
	visible = true
	_title.grab_focus()


func _refresh_epics() -> void:
	_epic_btn.clear()
	_epic_btn.add_item("None")
	for e in store.board.epics:
		_epic_btn.add_item(e.title)
		_epic_btn.set_item_metadata(_epic_btn.item_count - 1, e.id)


func _select_epic(epic_id: String) -> void:
	for i in _epic_btn.item_count:
		if str(_epic_btn.get_item_metadata(i)) == epic_id:
			_epic_btn.select(i)
			return


func refresh_epics(select_id := "") -> void:
	_refresh_epics()
	if select_id != "":
		_select_epic(select_id)


func _on_date_selected(ts: int) -> void:
	_due_ts = ts
	_refresh_due()


func _refresh_due() -> void:
	if _due_ts == 0:
		_due_btn.text = "No due date"
	else:
		_due_btn.text = Model.format_date(_due_ts)


func _add_tag() -> void:
	var raw := _tag_input.text.strip_edges()
	_tag_input.text = ""
	if raw == "":
		return
	for part in raw.split(","):
		var p := part.strip_edges()
		if p != "" and p not in _tags:
			_tags.append(p)
	_refresh_tags()


func _refresh_tags() -> void:
	for c in _tags_box.get_children():
		c.free()
	for tag in _tags:
		var chip := Button.new()
		chip.text = tag + " ✕"
		chip.flat = true
		T.flat_button(chip)
		chip.add_theme_color_override("font_color", T.TEXT_DIM)
		chip.pressed.connect(func(): _tags.erase(tag); call_deferred("_refresh_tags"))
		_tags_box.add_child(chip)


func _save() -> void:
	var title := _title.text.strip_edges()
	if title == "":
		_title.grab_focus()
		return
	var status: String = Model.STATUSES[_status_btn.selected]
	var priority: String = Model.PRIORITIES[_priority_btn.selected]
	var epic_id := ""
	if _epic_btn.selected > 0:
		epic_id = str(_epic_btn.get_item_metadata(_epic_btn.selected))
	var id: String = editing_id if editing_id != "" else store.board.new_id("task")
	store.upsert_task(id, title, _desc.text, status, priority, epic_id, _due_ts, _tags)
	hide()
	closed.emit()


func _delete() -> void:
	if editing_id == "":
		return
	_confirm.popup_centered()


func _do_delete() -> void:
	_confirm.hide()
	store.delete_task(editing_id)
	hide()
	closed.emit()


func _style_danger(b: Button) -> void:
	b.add_theme_stylebox_override("normal", T.panel(T.OVERDUE, T.OVERDUE.lightened(0.08), 6, 12, 12, 5, 5, 1))
	b.add_theme_stylebox_override("hover", T.panel(T.OVERDUE.lightened(0.10), T.OVERDUE.lightened(0.12), 6, 12, 12, 5, 5, 1))
	b.add_theme_stylebox_override("pressed", T.panel(T.OVERDUE.darkened(0.12), T.OVERDUE.darkened(0.04), 6, 12, 12, 5, 5, 1))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for s in ["font_color", "font_hover_color", "font_pressed_color",
			"font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(s, T.ACCENT_TEXT)


func _cancel() -> void:
	hide()
	closed.emit()
