---
name: vectojs-ui-animation
description: Use when creating polished VectoJS UI/UX with @vectojs/ui components, forms, overlays, hover/focus states, motion, transitions, microinteractions, or canvas-native interaction design.
---

# VectoJS UI Animation

Use this skill to turn VectoJS components into usable, accessible, and polished UI rather than just canvas drawings.

## Interaction workflow

1. Start with semantic components from `@vectojs/ui` before writing custom controls.
2. Model each interaction state: idle, hover, active, focus, loading, disabled, error, and success.
3. Use canvas motion for feedback, but preserve semantic state through the projected DOM.
4. Respect reduced motion. Suppress transform-heavy movement and keep essential opacity/state feedback.
5. Keep overlays in the Scene overlay root; dispose or hide transient UI when its target leaves the tree.
6. Test with keyboard and role-based automation, not only pointer clicks.

Read `references/ui-recipes.md` for patterns and snippets.

## Component guidance

- Use `Input` and `TextArea` for text entry so IME, selection, clipboard, and undo stay native.
- Use `Button`, `Toggle`, `Checkbox`, `Slider`, `Dropdown`, `RadioGroup`, and `Tabs` for controls with roles.
- Use `Tooltip`, `Popover`, `ContextMenu`, and `Modal` for transient UI; keep dismissal behavior explicit.
- On `@vectojs/ui@1.9.2+`, focused editor surfaces import `ContextMenu` from
  `@vectojs/ui/context-menu` to keep the application entry lean. Open it from
  VectoJS `pointerdown` when the native pointer button is `2`, using
  `sceneX`/`sceneY`; Core does not emit a `contextmenu` event and does not expose
  legacy `globalX`/`globalY` coordinates.
- As of `@vectojs/ui@2.0.0`, `Markdown` and `CodeBlock` are the standalone
  `@vectojs/markdown` package (import `from '@vectojs/markdown'`, not
  `@vectojs/ui`). `marked` + MathJax load only when you use it, so plain `ui`
  apps no longer pay for them.
- Use `RichText.appendSpans()` and `Markdown.appendMarkdown()` for streaming output.
- Text, RichText, and Table cell text (from `@vectojs/ui`) and `Markdown`/`CodeBlock` (from `@vectojs/markdown`) are natively selectable by default. Configure `selectable` or call `setSelectable()`; do not implement canvas clipboard or selection handles for static text.
- On `@vectojs/ui@1.9.0+` with `@vectojs/core@1.8.0+`, wrapped Text/RichText projections preserve logical
  source across soft spaces, hard breaks, space-less CJK wraps, and Arabic/RTL
  runs. Markdown lists and tables inherit the same behavior through their
  RichText cells, while each standalone Table cell remains one projection.
  `CodeBlock` shares Core's prepared source grid between per-grapheme Canvas
  paint and semantic projection. This is the required path for tabs, ZWJ,
  wide CJK/emoji, Arabic shaping, mixed bidi, Firefox font substitution, DPR,
  zoom, rotation, mirror transforms, and non-uniform scale; a monospace font
  name alone is not a geometry guarantee.
- Call `Table.layout()` after changing an external Entity cell. String cells are Text entities and each logical cell owns one content projection — plus a `role="gridcell"` a11y hotspot (see below), so a cell is now both a selectable text surface and a keyboard target.
- Prefer `Stack`/`Flow` composition over hand-positioning every child.
- On `@vectojs/ui@1.7.1+`, use `@vectojs/ui/input` for Input-only code,
  `@vectojs/ui/text` for selectable Text-only code, and `@vectojs/ui/measure`
  for measurement-only code. On UI 1.9.2+, use `@vectojs/ui/context-menu`
  for ContextMenu-only editor surfaces; retain the root import for
  multi-component surfaces.

## Keyboard & accessibility (ui 2.1.0)

Composite widgets project **one role per visible child** with a roving tabindex —
the whole widget is a single tab stop and arrow keys move within it. Don't
reimplement any of this:

| Component | Child role | Keys |
| --- | --- | --- |
| `TreeView` | `treeitem` (+ level/expanded/selected) | Up/Down · Right expands then enters · Left collapses then goes to parent · Home/End · Enter/Space |
| `Table` | `row` › `gridcell`/`columnheader` | 2D arrows (header is row −1) · Home/End row extremes · Ctrl+Home/Ctrl+End grid corners |
| `ContextMenu` | `menuitem` (+ haspopup/expanded) | Up/Down wrap and skip separators + disabled · Home/End · Right opens submenu · Left returns to parent · Enter/Space · Escape |
| `RadioGroup` | `radio` | Arrows move+select · Home/End · Space |
| `Tabs` | `tab` | Arrows · Home/End · Space/Enter |

Those hotspots carry `pointerEvents: 'none'` so the component underneath keeps
the mouse (selectable cell text, tap-to-toggle, drag-to-scroll). Keyboard focus
and AT-synthesized `click` still work through them.

**Touch**: `Table` and `TreeView` drag-to-scroll 1:1 with the finger, like
`ScrollView`/`VirtualList`. `TreeView` fires its toggle on `pointerup` and only
if the pointer moved less than ~6px, so a drag doesn't expand the row it started
on.

**Forced colors**: read `scene.forcedColors` and paint with CSS system colors
(`ButtonFace`/`ButtonText`/`Highlight`); canvas pixels are exempt from the
browser's High Contrast remapping. `Button` already does this.

**IME**: while a composition is active, `Input`/`TextArea` suppress the selection
highlight and underline the composing range instead. The native element keeps
reporting the pre-composition `selectionStart`/`End` until commit, so painting it
would show a stale highlight wider than the underline. Don't re-add it.

## Motion rules

| Scenario          | Recommended motion                                                         |
| ----------------- | -------------------------------------------------------------------------- |
| Hover/focus       | Small color/outline/opacity changes, no layout jump                        |
| Press/click       | 80-160 ms scale or opacity feedback                                        |
| Overlay enter     | short fade/scale, block underlying clicks only after visible target exists |
| Streaming content | append and reflow incrementally; avoid resetting scroll unless intended    |
| Loading           | show immediate state, then progress if operation exceeds short delay       |
| Error/success     | pair color with text/icon/state; do not rely only on color                 |

## Common mistakes

- Drawing a beautiful control without `getA11yAttributes()` or a native UI component.
- Animating layout so aggressively that hit boxes and projected DOM feel detached.
- Rebuilding a whole component tree for every state change.
- Importing `ContextMenu` from the UI root in an otherwise focused editor entry,
  which can retain rich-content dependencies and defeat the application's bundle budget.
- Hiding focus indicators on canvas controls.
- Ignoring IME and clipboard behavior by faking text entry.
- Intercepting Ctrl/Command+C while `window.getSelection()?.isCollapsed === false`, which overwrites native static-text copy; likewise, do not prevent Ctrl/Command+F without a replacement find UI.
- Hand-rolling per-frame motion in `update()` without telling the Scene —
  invisible to the idle throttle, so the animation steps at 2 FPS or stalls
  in onDemand mode. Prefer `setTransition`/`animateTo`/`springTo` or override
  `hasPendingAnimations()`; on core 0.2.6+ `markDirty()` inside `update()`
  also works. See vectojs-core-runtime's "Runtime gotchas".
- Relying on in-flight springs across tab switches on core ≤ 0.2.5 — the
  unclamped rAF `dt` made them diverge; core 0.2.6 substeps. If stuck on an
  old core, re-seed positions on `visibilitychange`.
- Creating a new `Tooltip` per hover event instead of one per target.
- **Reimplementing keyboard handling that already exists.** `Slider`,
  `RadioGroup`, `Tabs`, `TreeView`, `Table`, `ContextMenu`, `Dropdown` and
  `Modal` all handle `keydown` themselves — see the keyboard table below.
- **Adding a pointer handler that fights the component.** `TreeView`/`Table`
  own tap-vs-drag disambiguation and drag-to-scroll; their a11y hotspots
  deliberately don't capture the pointer so the component keeps it.
