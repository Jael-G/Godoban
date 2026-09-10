# Godoban - Advanced Task Manager for Godot

A Godot editor plugin that adds a full Godoban board as a main editor tab (next to 2D / 3D / Script) for
tracking the project's own tasks. It runs entirely in the editor (`@tool`) — there is no runtime
dependency, so nothing ships in your exported game.

> [!IMPORTANT]
> **Migrating from a version that predates multiple boards?** 1.1.0 stores one JSON file per board and
> no longer reads the old single-file layout, so older boards must be brought in by hand:
>
> - **Import your old board.** Godoban won't find it on its own — click the board chip in the toolbar
>   → **Import board** and point at your previous JSON (wherever you kept it, including a
>   `res://godoban_data.json` at the project root).
> - **Add a `"name"` to the JSON first** (recommended), otherwise the board imports as **"My Board"**.
>   It's a display name only — no task, epic, or date is touched — and you can rename it anytime with
>   the **pencil** on the board's row in the switcher.

## Requirements

- **Godot 4.7** (tested on 4.7.2)
- GDScript only — no C# or GDExtension needed.

## Installation

1. Copy the `addons/godoban/` folder into your project's `addons/` directory.
2. In Godot, open **Project → Project Settings → Plugins**.
3. Enable **Godoban**.
4. A **Godoban** tab appears next to 2D / 3D / Script. Open it and click **"＋ New Task"** to
   add your first card.

> Godoban never creates a board for you. On first run it shows a friendly **"No board yet"** empty
> state; use the board chip in the top bar to **New board** or **Import board**. The
> `res://godoban_boards/` folder (one JSON per board + a `boards.json` registry) is created the first
> time you make a board.

## Features

**Multiple boards**
- Keep any number of boards and switch between them from the board chip in the top bar.
- Each board is its own named JSON file under `res://godoban_boards/`.
- Removing every board leaves the plugin in a **"No board yet"** empty state (chip row only); it never
  auto-creates a default — use **New board** or **Import** to start again.
- One popup gives you the list of known boards (click to switch), **New board**, and
  **Import board** (pick any JSON on disk). Each row has a **pencil** to *rename* the
  board (renames the list entry + its JSON `name` field in place — the file itself is
  never renamed or moved) and an **"×"** to *remove from the list* — take a board out
  of the list without deleting its file.

**Board & tasks**
- **Five status columns** — Backlog, To Do, In Progress, Review, Done.
- **Drag & drop** — move cards between columns to change status, or reorder within a column.
- **Priorities** — Low, Medium, High, Critical, color-coded on every card.
- **Tags / labels** — free-form, with a searchable picker; filter by any label.
- **Due dates** — set a date via a built-in calendar popup (Godot has no native date picker).
- **Descriptions** — multi-line notes on each task.
- **Click to edit** — any card opens in the slide-in editor; each column has its own "＋".

**Epics**
- Lightweight, color-coded groups of related tasks (a name and a color).
- **Per-epic view** — one compact board per epic, plus a "No Epic" board.
- Cards show a colored epic chip in the all-tasks view; deleting an epic reassigns instead of
  orphaning its tasks.

**Search & filters**
- Live, case-insensitive search across title, description, and tags.
- 6 sort modes (created, latest edited, priority, due date, alphabetical).
- Filter by priority, epic, or label; date bounds (overdue, due today, due this week, none).
- All filters combine; empty results show a friendly hint.

**View modes**
- **All Tasks** — one board with everything. **Per Epic** — one board per group.
- **Vertical / Horizontal** — stack cards down each column, or flow them across a row per status.
- Collapsible columns; state survives rebuilds.

**Overview dashboard**
- Summary cards (total / completed / in progress / overdue) with ring progress.
- By-status donut, priority bars, per-epic progress, and actionable lists
  (overdue, no-epic, upcoming).

**Editor-native theme**
- Matches your current editor theme — dark or light — so the board reads as native to the editor.
- The palette auto-syncs on every theme change.

## Data

Boards live under **`res://godoban_boards/`**:

- Each board is its own pretty-printed JSON file (recording the board's `name`), and a
  `boards.json` **registry** indexes them as id → name → path and marks which is current.
- **Imported** boards stay wherever you pick and are referenced by path — they're *not* moved into
  the folder.
- Saved on every change (debounced ~0.5s), plus on editor save/exit.
- Pretty-printed and git-diffable — safe to hand-edit or move between machines.
- **Removing a board from the list only unregisters it — Godoban never deletes the file.**
  To permanently delete a board, delete its JSON file yourself; the board then stops showing
  on the list. Deleting a board's JSON keeps the rest of the registry intact.

> A board imported from a pre-multi-board file takes its name from that file's `"name"` field,
> falling back to **"My Board"** when there isn't one.

## Notes

- The entire UI is built in GDScript at runtime — there are no scene files to edit. Visual changes
  are code changes.
- The bundled `Geist` font is licensed under the **SIL Open Font License**; see `fonts/OFL.txt`.

## 🤖 AI Disclosure

The development of this project was greatly assisted by AI.

## License

MIT — see [LICENSE](LICENSE).
