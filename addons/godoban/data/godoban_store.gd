@tool
extends RefCounted

## godoban_store.gd — persistence layer. Owns the in-memory Board, loads/saves
## JSON, and emits `changed` whenever the model mutates.

const Model = preload("res://addons/godoban/data/godoban_model.gd")

signal changed

const SAVE_DELAY := 0.5
const PATH := "res://godoban_data.json"

var board: Model.Board
var path := PATH
var _timer: SceneTreeTimer = null


func _init() -> void:
	board = Model.Board.new()


func load() -> void:
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f:
			var text := f.get_as_text()
			f.close()
			var data = JSON.parse_string(text)
			if data is Dictionary:
				board = Model.Board.from_dict(data)
			else:
				board = Model.Board.new()
	else:
		board = Model.Board.new()


func save_now() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("Godoban: cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return
	f.store_string(JSON.stringify(board.to_dict(), "  ", false))
	f.close()


func mark_dirty() -> void:
	if _timer and _timer.time_left > 0.0:
		return
	var tree := Engine.get_main_loop()
	if tree is SceneTree:
		_timer = tree.create_timer(SAVE_DELAY)
		_timer.timeout.connect(save_now)


func _now() -> int:
	return int(Time.get_unix_time_from_system())


# --- task operations ---------------------------------------------------------

func upsert_task(id: String, title: String, description: String, status: String,
		priority: String, epic_id: String, due_date: int, tags: Array) -> Model.Task:
	var t := board.get_task(id)
	if t == null:
		t = Model.Task.new(id)
		t.created_at = _now()
		board.add_task(t)
	t.title = title
	t.description = description
	t.status = status
	t.priority = priority
	t.epic_id = epic_id
	t.due_date = due_date
	t.tags = tags.duplicate()
	t.updated_at = _now()
	changed.emit()
	mark_dirty()
	return t


func delete_task(id: String) -> void:
	var t := board.get_task(id)
	if t == null:
		return
	board.remove_task(t)
	changed.emit()
	mark_dirty()


func move_task(id: String, new_status: String) -> void:
	var t := board.get_task(id)
	if t == null:
		return
	t.status = new_status
	t.updated_at = _now()
	changed.emit()
	mark_dirty()


# --- epic operations ---------------------------------------------------------

func upsert_epic(id: String, title: String, color: String) -> Model.Epic:
	var e := board.get_epic(id)
	if e == null:
		e = Model.Epic.new(id, title, color)
		board.add_epic(e)
	else:
		e.title = title
		e.color = color
	changed.emit()
	mark_dirty()
	return e


func delete_epic(id: String) -> void:
	var e := board.get_epic(id)
	if e == null:
		return
	board.remove_epic(e)
	changed.emit()
	mark_dirty()
