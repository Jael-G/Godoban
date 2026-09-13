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

## Every tag on the board, sorted case-insensitively by name. Shared by the task editor's tag
## picker and the board's tag filter.
##
## This is the board's *vocabulary* (`Board.tags`), not a scan of the tasks: it includes tags
## nothing carries yet — that is the whole point of the vocabulary — and includes a name only a
## task carries, because the board was loaded through `_merge_tag_names`. Always a fresh array:
## callers sort and filter what they get, and handing out the board's own array would let a
## display choice silently reorder the vocabulary that gets saved.
func all_tags() -> Array:
	var out: Array = board.tags.duplicate()
	out.sort_custom(func(a, b): return String(a).naturalnocasecmp_to(String(b)) < 0)
	return out


# --- tag operations ----------------------------------------------------------

## How many tasks carry `name`. Case-insensitive (see `Model.tag_key`), so a board edited by hand
## into holding both "AI" and "ai" counts as one tag, the same way every other tag rule sees it.
func tag_usage(name: String) -> int:
	var key := Model.tag_key(name)
	var n := 0
	for t in board.tasks:
		for tag in t.tags:
			if Model.tag_key(str(tag)) == key:
				n += 1
				break
	return n


## The stored spelling of the tag matching `name` case-insensitively, or "" if the board has no
## such tag. This is what stops a typed name from spawning a near-duplicate of one already in
## use: "Ai" resolves to the "AI" the board already has, and that spelling is what gets used.
func find_tag(name: String) -> String:
	var key := Model.tag_key(name)
	for tag in board.tags:
		if Model.tag_key(String(tag)) == key:
			return String(tag)
	return ""


## Add a name to the board's vocabulary and return the spelling now in use — the existing one
## when the board already has the tag in any case, otherwise the new name. "" means the name is
## unusable: blank, or carrying a comma.
##
## Commas are refused rather than split. The task editor's field splits a typed batch on commas,
## so no tag containing one can exist on a task; accepting one here would create a tag the picker
## can never type back.
func create_tag(name: String) -> String:
	var n := Model.clamp_tag(name)
	if n == "" or n.contains(","):
		return ""
	var existing := find_tag(n)
	if existing != "":
		return existing  # already known: nothing changed, so nothing to redraw or save
	board.tags.append(n)
	changed.emit()
	mark_dirty()
	return n


## Rename a tag everywhere it appears: the vocabulary entry, and every task carrying it. Returns
## true if anything changed; false when the old name isn't a tag, the new one is unusable, it is
## what the tag is already called, or a *different* tag already answers to it.
##
## Refusing the collision rather than merging is deliberate: a merge would have to pick which of
## the two names survives and silently fold one tag into the other, and the user asked to rename
## a tag, not to combine two. The dialog reports the clash so the name can be corrected.
##
## `updated_at` is left alone — renaming a tag is not an edit to the tasks that carry it, and
## bumping it would march every one of them to the top of the "Latest edited" sort. Deleting is
## the same; `Board.remove_epic` sets the precedent by clearing `epic_id` without touching stamps.
func rename_tag(old_name: String, new_name: String) -> bool:
	var from := find_tag(old_name)
	if from == "":
		return false
	# Compared before clamping: a name already on the board can predate the length cap, and
	# leaving the field alone must never truncate it just because the cap is shorter.
	var raw := new_name.strip_edges()
	if raw == "" or raw == from:
		return false
	var to := Model.clamp_tag(raw)
	if to == "" or to.contains(","):
		return false
	# A clash is only a clash if it belongs to *another* tag: renaming "ai" to "AI" resolves to
	# the very tag being renamed, which is a legal (case-only) rename.
	var clash := find_tag(to)
	if clash != "" and clash != from:
		return false
	var idx := board.tags.find(from)
	if idx == -1:
		return false  # unreachable while the vocabulary is a superset of the tasks; never write -1
	board.tags[idx] = to
	_sweep_tag(from, to)
	changed.emit()
	mark_dirty()
	return true


## Drop a tag from the board and strip it from every task carrying it. Returns how many tasks it
## was removed from, so the UI can say what it did (and confirm it first when that isn't zero).
func delete_tag(name: String) -> int:
	var from := find_tag(name)
	if from == "":
		return 0
	board.tags.erase(from)
	var touched := _sweep_tag(from, "")
	changed.emit()
	mark_dirty()
	return touched


## Rewrite every occurrence of `from` in the board's tasks to `to`, or drop it entirely when `to`
## is "". Matching is case-insensitive, so a board holding both spellings of a name is swept in
## one pass — and a task that ends up with the same name twice (it carried both spellings, or it
## already had the rename target) keeps a single entry. Returns how many tasks changed.
func _sweep_tag(from: String, to: String) -> int:
	var from_key := Model.tag_key(from)
	var touched := 0
	for t in board.tasks:
		var out: Array = []
		var seen := {}
		var hit := false  # named for the signal's sake: `changed` is the store's, not a task's
		for raw in t.tags:
			var name := str(raw)
			if Model.tag_key(name) == from_key:
				hit = true
				name = to
			var key := Model.tag_key(name)
			if key == "" or seen.has(key):
				continue
			seen[key] = true
			out.append(name)
		if hit:
			t.tags = out
			touched += 1
	return touched


func upsert_task(id: String, title: String, description: String, status: String,
		priority: String, epic_id: String, due_date: int, tags: Array) -> Model.Task:
	var t := board.get_task(id)
	var is_new := t == null
	var prev_status := ""
	if is_new:
		t = Model.Task.new(id)
		t.created_at = _now()
		board.add_task(t)
	else:
		prev_status = t.status
	t.title = title
	t.description = description
	t.status = status
	t.priority = priority
	t.epic_id = epic_id
	t.due_date = due_date
	t.tags = tags.duplicate()
	t.updated_at = _now()
	# A status change made here (the task editor) would otherwise leave the task at its
	# old array index, i.e. at an arbitrary spot in the new column. Send it to the end,
	# the same place a drag into empty space lands. Guarded on a real change: otherwise
	# every edit (title, tags, …) would shove the task to the bottom of its column.
	if not is_new and t.status != prev_status:
		board.reorder_before(t, "")
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


## Move `id` to `new_status`, landing immediately before `before_id` inside that column
## ("" = the end of the column). The board's task array *is* the manual order, so a
## reorder is an ordinary data change: it emits `changed` and saves.
##
## `updated_at` is bumped only when the status really changes: a drag within a column is
## an arrangement change, not an edit, and bumping it would make the reordered task jump
## to the top of the "Latest edited" sort.
func move_task(id: String, new_status: String, before_id := "") -> void:
	var t := board.get_task(id)
	if t == null:
		return
	var status_changed := t.status != new_status
	t.status = new_status
	if status_changed:
		t.updated_at = _now()
	var moved := board.reorder_before(t, before_id)
	if not status_changed and not moved:
		return  # dropped exactly where it already was: nothing to redraw or save
	changed.emit()
	mark_dirty()


# --- epic operations ---------------------------------------------------------

## How many tasks are assigned to `id`. The epics dialog's counterpart to `tag_usage`: it labels
## each row with what deleting it would cost, and it is what decides whether deleting needs a
## confirmation at all.
func epic_usage(id: String) -> int:
	var n := 0
	for t in board.tasks:
		if t.epic_id == id:
			n += 1
	return n


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
