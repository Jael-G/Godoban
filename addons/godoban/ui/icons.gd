@tool
extends RefCounted
## The single source for every plugin glyph. Icons are Lucide (`lucide-static`, ISC/MIT —
## free for commercial use, no attribution required) rendered as white line-glyphs on a
## transparent canvas. Each is built lazily from its embedded SVG via Godot's SVG loader and
## cached, so the wholesale board rebuilds never re-parse. A white base lets callers tint
## with `icon_normal_color` / `icon_hover_color` / … overrides, exactly like the old
## `ImageTexture` glyphs. Source paths pulled verbatim from
## `https://unpkg.com/lucide-static@latest/icons/<name>.svg`.

# Lucide icon glyphs, normalized to one line each. `currentColor` is replaced by an explicit
# white so the rasterizer draws a solid, tintable glyph. `fill-rule`/`clip-rule` are kept
# because a couple of icons (layers-2) rely on them to render their overlapping strokes.
const _SVG := {
	"grid-2x2": '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#ffffff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v18"/><path d="M3 12h18"/><rect x="3" y="3" width="18" height="18" rx="2"/></svg>',
	"layers-2": '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#ffffff" fill-rule="evenodd" clip-rule="evenodd" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M13 13.74a2 2 0 0 1-2 0L2.5 8.87a1 1 0 0 1 0-1.74L11 2.26a2 2 0 0 1 2 0l8.5 4.87a1 1 0 0 1 0 1.74z"/><path d="m20 14.285 1.5.845a1 1 0 0 1 0 1.74L13 21.74a2 2 0 0 1-2 0l-8.5-4.87a1 1 0 0 1 0-1.74l1.5-.845"/></svg>',
	"columns-2": '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#ffffff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2"/><path d="M12 3v18"/></svg>',
	"rows-2": '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#ffffff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2"/><path d="M3 12h18"/></svg>',
	"calendar": '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#ffffff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M8 2v3"/><path d="M16 2v3"/><rect x="3" y="3" width="18" height="18" rx="2"/><path d="M3 9h18"/><path d="M8 13h.01"/><path d="M12 13h.01"/><path d="M16 13h.01"/><path d="M8 17h.01"/><path d="M12 17h.01"/><path d="M16 17h.01"/></svg>',
	"chevron-down": '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#ffffff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m6 9 6 6 6-6"/></svg>',
	"chevron-right": '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#ffffff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m9 18 6-6-6-6"/></svg>',
	"x": '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#ffffff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 6 6 18"/><path d="m6 6 12 12"/></svg>',
	"kanban": '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#ffffff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 5v11"/><path d="M12 5v6"/><path d="M18 5v14"/></svg>',
	"plus": '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#ffffff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14"/><path d="M12 5v14"/></svg>',
	"pencil": '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#ffffff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21.174 6.812a1 1 0 0 0-3.986-3.987L3.842 16.174a2 2 0 0 0-.5.83l-1.321 4.352a.5.5 0 0 0 .623.622l4.353-1.32a2 2 0 0 0 .83-.497z"/><path d="m15 5 4 4"/></svg>',
	"folder-open": '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#ffffff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m6 14 1.5-2.9A2 2 0 0 1 9.24 10H20a2 2 0 0 1 1.94 2.5l-1.54 6a2 2 0 0 1-1.95 1.5H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h3.9a2 2 0 0 1 1.69.9l.81 1.2a2 2 0 0 0 1.67.9H18a2 2 0 0 1 2 2v2"/></svg>',
	"check": '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#ffffff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg>',
}

static var _cache: Dictionary = {}


## The icon glyph as a white texture. `size` is the rasterized edge length in pixels; the
## glyph scales proportionally within the 24×24 Lucide grid. Cached by (kind, size).
static func icon(kind: String, size := 24) -> ImageTexture:
	var key := "%s:%d" % [kind, size]
	if _cache.has(key):
		return _cache[key]
	var svg: String = _SVG.get(kind, _SVG["x"])
	if size != 24:
		# Rewrite the raster dimensions so the glyph is baked at the requested size.
		svg = svg.replace('width="24"', 'width="%d"' % size)
		svg = svg.replace('height="24"', 'height="%d"' % size)
	var img := Image.new()
	if img.load_svg_from_string(svg) != OK:
		push_warning("godoban: failed to render icon '%s'" % kind)
		return ImageTexture.create_from_image(Image.create(size, size, false, Image.FORMAT_RGBA8))
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func chevron_down(size := 16) -> ImageTexture:
	return icon("chevron-down", size)


static func chevron_right(size := 16) -> ImageTexture:
	return icon("chevron-right", size)
