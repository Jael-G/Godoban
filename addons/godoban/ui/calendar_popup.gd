@tool
extends PopupPanel

## Minimal date picker (Godot has no built-in one). Emits a Unix timestamp
## (midnight of the chosen day) or 0 when cleared.

const T = preload("res://addons/godoban/ui/theme.gd")

signal date_selected(ts: int)

var _year: int
var _month: int  # 1..12
var _header_label: Label
var _grid: GridContainer

func _init() -> void:
	var now := Time.get_datetime_dict_from_system()
	_year = now["year"]
	_month = now["month"]
	_build()

func _build() -> void:
	title = "Due date"
	add_theme_stylebox_override("panel", T.panel(T.BG_PANEL, T.BORDER_SOFT, 10, 12, 12, 12, 12, 1))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)

	var header := HBoxContainer.new()
	var prev := Button.new()
	prev.text = "‹"
	prev.flat = true
	T.flat_button(prev)
	prev.add_theme_color_override("font_color", T.TEXT_DIM)
	prev.pressed.connect(_shift_month.bind(-1))
	header.add_child(prev)

	_header_label = Label.new()
	_header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(_header_label)

	var next := Button.new()
	next.text = "›"
	next.flat = true
	T.flat_button(next)
	next.add_theme_color_override("font_color", T.TEXT_DIM)
	next.pressed.connect(_shift_month.bind(1))
	header.add_child(next)
	v.add_child(header)

	var dow := GridContainer.new()
	dow.columns = 7
	for d in ["S", "M", "T", "W", "T", "F", "S"]:
		var l := Label.new()
		l.text = d
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size = Vector2(24, 0)
		l.add_theme_color_override("font_color", T.TEXT_DIM)
		dow.add_child(l)
	v.add_child(dow)

	_grid = GridContainer.new()
	_grid.columns = 7
	v.add_child(_grid)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	var clear := Button.new()
	clear.text = "Clear date"
	T.button(clear)
	clear.pressed.connect(func(): date_selected.emit(0); hide())
	footer.add_child(clear)
	var today := Button.new()
	today.text = "Today"
	T.button(today)
	today.pressed.connect(func(): date_selected.emit(_today_ts()); hide())
	footer.add_child(today)
	v.add_child(footer)

	_rebuild()


func open_for_date(ts: int) -> void:
	if ts != 0:
		var d := Time.get_datetime_dict_from_unix_time(ts)
		_year = d["year"]
		_month = d["month"]
	_rebuild()
	popup_centered()


func _rebuild() -> void:
	for c in _grid.get_children():
		c.free()
	_header_label.text = _month_name(_month) + " " + str(_year)
	var first_wd: int = Time.get_datetime_dict_from_unix_time(_make_ts(_year, _month, 1))["weekday"]
	for i in first_wd:
		var blank := Label.new()
		blank.custom_minimum_size = Vector2(24, 22)
		_grid.add_child(blank)
	var dim := _days_in_month(_year, _month)
	for day in range(1, dim + 1):
		var b := Button.new()
		b.text = str(day)
		b.flat = true
		b.custom_minimum_size = Vector2(24, 22)
		T.flat_button(b)
		b.add_theme_color_override("font_color", T.TEXT)
		var ts := _make_ts(_year, _month, day)
		b.pressed.connect(func(): date_selected.emit(ts); hide())
		_grid.add_child(b)


func _shift_month(delta: int) -> void:
	_month += delta
	if _month > 12:
		_month = 1
		_year += 1
	elif _month < 1:
		_month = 12
		_year -= 1
	_rebuild()


func _month_name(m: int) -> String:
	return ["January", "February", "March", "April", "May", "June", "July",
			"August", "September", "October", "November", "December"][m - 1]


func _days_in_month(y: int, m: int) -> int:
	match m:
		1, 3, 5, 7, 8, 10, 12:
			return 31
		4, 6, 9, 11:
			return 30
		2:
			return 29 if (y % 4 == 0 and (y % 100 != 0 or y % 400 == 0)) else 28
	return 30


func _make_ts(y: int, m: int, d: int) -> int:
	var dt := {"year": y, "month": m, "day": d, "hour": 0, "minute": 0, "second": 0}
	return int(Time.get_unix_time_from_datetime_dict(dt))


func _today_ts() -> int:
	var now := Time.get_datetime_dict_from_system()
	return _make_ts(now["year"], now["month"], now["day"])
