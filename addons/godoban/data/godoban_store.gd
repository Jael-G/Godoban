@tool
extends RefCounted

## godoban_store.gd — persistence layer. Owns the in-memory Board, loads/saves
## JSON, and emits `changed` whenever the model mutates. Also owns the board
## registry — the map of every known board (id → name → path) persisted to
## `res://godoban_boards/boards.json` — and the "current" board it points at.

const Model = preload("res://addons/godoban/data/godoban_model.gd")

signal changed
signal board_switched(board_id: String)
## A board was imported that's already on the list; `import_board` refused it.
signal board_import_rejected
## The target board's file is gone (deleted/removed) while switching to it; the
## dead entry was dropped from the registry. UI should inform the user.
signal board_missing(board_id: String, board_name: String)
## A board was renamed; `board_name` is the new name. Views that surface the name (e.g.
## the current-board chip) should refresh to the new value.
signal board_renamed(board_id: String, board_name: String)

const SAVE_DELAY := 0.5
## Folder of per-board files (one JSON each) + the registry that indexes them.
const BOARDS_DIR := "res://godoban_boards/"
const REGISTRY_PATH := BOARDS_DIR + "boards.json"

var board: Model.Board
var board_path := ""  # current board's file path ("" until a board is loaded)
var board_name := ""
## Known boards: [{"id": String, "name": String, "path": String}, …] — the in-memory
## mirror of REGISTRY_PATH. `path` may be a res://, user://, or absolute OS path (imports).
var registry: Array = []
var current_id := ""
var _timer: SceneTreeTimer = null


func _init() -> void:
	board = Model.Board.new()


## Load the registry, then the current board. The plugin NEVER fabricates a default
## board: a missing registry is the zero-board empty state. Pre-multi-board files are
## not picked up automatically — the user imports them by hand from the board switcher.
func load() -> void:
	registry = []
	current_id = ""
	if FileAccess.file_exists(REGISTRY_PATH):
		var data = _read_json(REGISTRY_PATH)
		if data is Dictionary:
			current_id = str(data.get("current", ""))
			for entry in data.get("boards", []):
				if entry is Dictionary:
					registry.append({
						"id": str(entry.get("id", "")),
						"name": str(entry.get("name", "")),
						"path": str(entry.get("path", "")),
					})
	_load_current()


## Point `board`/`board_path`/`board_name` at the registry's current entry.
func _load_current() -> void:
	var entry := _registry_entry(current_id)
	if entry.is_empty() and not registry.is_empty():
		entry = registry[0]
		current_id = String(entry["id"])
	if entry.is_empty():
		board = Model.Board.new()
		board_path = ""
		board_name = ""
		return
	board_path = String(entry["path"])
	board_name = String(entry["name"])
	var data = _read_json(board_path)
	board = Model.Board.from_dict(data) if data is Dictionary else Model.Board.new()
	# The registry is the source of truth for the name; a board file edited by hand
	# may predate the name field or carry a stale one.
	if board.name == "":
		board.name = board_name
	board_name = board.name


func save_now() -> void:
	if board_path == "":
		return
	_write_board_to_path(board, board_path)


func mark_dirty() -> void:
	if _timer and _timer.time_left > 0.0:
		return
	var tree := Engine.get_main_loop()
	if tree is SceneTree:
		_timer = tree.create_timer(SAVE_DELAY)
		_timer.timeout.connect(save_now)


func _now() -> int:
	return int(Time.get_unix_time_from_system())


# --- board registry ------------------------------------------------------------

func list_boards() -> Array:
	return registry


func current_board_id() -> String:
	return current_id


## True if a board whose underlying file is the same as `path` is already in the
## registry. Paths are canonicalized (`globalize` + `simplify`) so two spellings of
## the same file — a res:// path vs. its absolute OS path — compare equal.
func has_board(path: String) -> bool:
	var target := _normalize_path(path)
	for e in registry:
		if _normalize_path(String(e["path"])) == target:
			return true
	return false


## Switch the active board to `id`. Any debounced edit to the outgoing board is
## saved first, so nothing is lost and nothing is written to the new board's file.
## Returns true if the switch happened (or was a no-op on the already-current board);
## false if the target's file is missing — the dead entry is dropped from the registry
## and `board_missing` is emitted, so the UI can tell the user and stay put.
func switch_board(id: String) -> bool:
	if id == current_id or id == "":
		return true
	var entry := _registry_entry(id)
	if entry.is_empty():
		return false
	_flush_pending_save()
	var target_path := String(entry["path"])
	var data := _read_json(target_path)
	if data == null:
		# Imports reference a file on disk by path; a board whose file was deleted
		# can't be opened. Drop the dead entry, keep the current board, and let the
		# UI notify the user (a theme: the store decides, the views react).
		registry.erase(entry)
		save_registry()
		board_missing.emit(id, String(entry["name"]))
		return false
	current_id = id
	board_path = target_path
	board_name = String(entry["name"])
	board = Model.Board.from_dict(data) if data is Dictionary else Model.Board.new()
	if board.name == "":
		board.name = board_name
	board_name = board.name
	save_registry()
	board_switched.emit(current_id)
	changed.emit()
	return true


## Create a brand-new empty board, persist it under BOARDS_DIR, make it current.
## The folder (which only exists after a user action, never a default seed) is created
## here if needed.
func create_board(name: String) -> String:
	_flush_pending_save()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BOARDS_DIR))
	var b := Model.Board.new()
	b.name = name.strip_edges()
	if b.name == "":
		b.name = "My Board"
	var id := _gen_id(b.name)
	var path := BOARDS_DIR + "%s.json" % id
	_write_board_to_path(b, path)
	registry.append({"id": id, "name": b.name, "path": path})
	current_id = id
	save_registry()
	board = b
	board_path = path
	board_name = b.name
	board_switched.emit(current_id)
	changed.emit()
	return id


## Adopt an existing board file (anywhere on disk) into the registry by reference —
## it is *not* copied into BOARDS_DIR. The picked file is left untouched here; it
## only gets (re)written during a later save of the board's edits. Returns the new
## board id, or "" if the file is already on the list (refused, `board_import_rejected`
## emitted). Importing is idempotent: the same file can't be added twice.
func import_board(path: String) -> String:
	if has_board(path):
		board_import_rejected.emit()
		return ""
	_flush_pending_save()
	var data = _read_json(path)
	var b := Model.Board.from_dict(data) if data is Dictionary else Model.Board.new()
	if b.name == "":
		b.name = "My Board"
	var id := _gen_id(b.name)
	registry.append({"id": id, "name": b.name, "path": path})
	current_id = id
	save_registry()
	board = b
	board_path = path
	board_name = b.name
	board_switched.emit(current_id)
	changed.emit()
	return id


## Remove a board from the registry *only* — the underlying file is never touched, so the
## board can be re-imported later (the file stays where the user put it). If the removed
## board was the current one, fall back to the first remaining board, or seed a fresh empty
## default if none are left. Returns true if a board was removed.
func remove_board(id: String) -> bool:
	var entry := _registry_entry(id)
	if entry.is_empty():
		return false
	var was_current := id == current_id
	registry.erase(entry)
	if was_current:
		# Never leave the plugin on a stale board: point at the first remaining board, or —
		# if none are left — enter a deliberate zero-board state instead of auto-creating a
		# default (removing every board must not spawn a fresh one).
		current_id = ""
		if registry.is_empty():
			_load_current()  # board=blank, board_path="", board_name=""
			save_registry()  # persist current="" + an empty boards array so reload stays empty
		else:
			current_id = String(registry[0]["id"])
			_load_current()
		board_switched.emit(current_id)
	else:
		save_registry()
	changed.emit()
	return true


## Rename a board: updates the registry entry, the board's JSON `name` field, and (if
## it's the current board) the in-memory one + file. The file itself is never renamed or
## moved — only the `name` value *inside* it. Returns true if the name actually changed.
func rename_board(id: String, new_name: String) -> bool:
	new_name = new_name.strip_edges()
	if new_name == "":
		return false
	var entry := _registry_entry(id)
	if entry.is_empty():
		return false
	if String(entry["name"]) == new_name:
		return false
	entry["name"] = new_name
	if id == current_id:
		board.name = new_name
		board_name = new_name
		mark_dirty()
	else:
		_set_name_in_file(String(entry["path"]), new_name)
	save_registry()
	board_renamed.emit(id, new_name)
	changed.emit()
	return true


## Rewrite a board's JSON with a new `name` value, leaving everything else (and the
## filename) untouched. Used when renaming a board that isn't currently loaded.
func _set_name_in_file(path: String, name: String) -> void:
	var data = _read_json(path)
	if not data is Dictionary:
		return
	data["name"] = name
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("Godoban: cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return
	f.store_string(JSON.stringify(data, "  ", false))
	f.close()


func save_registry() -> void:
	var boards: Array = []
	for e in registry:
		boards.append({"id": e["id"], "name": e["name"], "path": e["path"]})
	var f := FileAccess.open(REGISTRY_PATH, FileAccess.WRITE)
	if f == null:
		push_error("Godoban: cannot write %s (%s)" % [REGISTRY_PATH, error_string(FileAccess.get_open_error())])
		return
	f.store_string(JSON.stringify({"current": current_id, "boards": boards}, "  ", false))
	f.close()


## Cancel any queued debounce and save the outgoing board immediately. Must run
## before a switch: a pending timer would otherwise fire after `board`/`board_path`
## changed, writing the NEW board to the NEW path (losing the old board's edits).
func _flush_pending_save() -> void:
	if _timer != null:
		if _timer.timeout.is_connected(save_now):
			_timer.timeout.disconnect(save_now)
		_timer = null
	save_now()


func _registry_entry(id: String) -> Dictionary:
	for e in registry:
		if String(e["id"]) == id:
			return e
	return {}


# --- helpers -------------------------------------------------------------------

func _write_board_to_path(b: Model.Board, path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("Godoban: cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return
	f.store_string(JSON.stringify(b.to_dict(), "  ", false))
	f.close()


## Canonical absolute path for a file ("res://"/"user://" → OS path, `..`/`.` folded),
## so the same file referenced two ways compares equal. Imports carry no inherent id —
## the path is the key for dedup and missing-file checks.
func _normalize_path(p: String) -> String:
	return ProjectSettings.globalize_path(p).simplify_path()


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text := f.get_as_text()
	f.close()
	return JSON.parse_string(text)


## Lowercase, collapse non-alphanumerics to single dashes ("Game Jam" → "game-jam").
func _slugify(s: String) -> String:
	var out := ""
	for i in s.length():
		var c := s[i].to_lower()
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
		elif out != "" and out[out.length() - 1] != "-":
			out += "-"
	while out.ends_with("-"):
		out = out.substr(0, out.length() - 1)
	return out


## A unique board id: human-readable slug + a short hash suffix, so the file name
## stays readable AND collisions with existing registry ids are avoided.
func _gen_id(name: String) -> String:
	var slug := _slugify(name)
	if slug == "":
		slug = "board"
	var short := "%04x" % (absi(hash(str(Time.get_ticks_usec()) + name)) & 0xffff)
	var id := "%s_%s" % [slug, short]
	var n := 0
	while not _registry_entry(id).is_empty():
		n += 1
		id = "%s_%s%x" % [slug, short, n]
	return id


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
