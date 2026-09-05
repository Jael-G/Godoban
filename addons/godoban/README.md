# Godoban - Advanced Task Manager for Godot

A Godot editor plugin that adds a full Godoban board as a main editor tab (next to 2D / 3D / Script) for
tracking the project's own tasks. It runs entirely in the editor (`@tool`) — there is no runtime
dependency, so nothing ships in your exported game.

## Requirements

- **Godot 4.7** (tested on 4.7.2)
- GDScript only — no C# or GDExtension needed.

## Installation

1. Copy the `addons/godoban/` folder into your project's `addons/` directory.
2. In Godot, open **Project → Project Settings → Plugins**.
3. Enable **Godoban**.
4. A **Godoban** tab appears next to 2D / 3D / Script. Open it and click **"＋ New Task"** to
   add your first card.

> On first run the plugin creates a `res://godoban_data.json` file in your project root and saves
> your board there.

## Features

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

## Data

Tasks are stored in **`res://godoban_data.json`** in your project root:

- Created on first run, saved on every change (debounced ~0.5s), plus on editor save/exit.
- Pretty-printed and git-diffable — safe to hand-edit or move between machines.
- Deleting it resets the board.

## Notes

- The entire UI is built in GDScript at runtime — there are no scene files to edit. Visual changes
  are code changes.
- The bundled `Geist` font is licensed under the **SIL Open Font License**; see `fonts/OFL.txt`.

## 🤖 AI Disclosure

The development of this project was greatly assisted by AI.

## License

MIT — see [LICENSE](LICENSE).
