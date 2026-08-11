---
name: vectojs-core-runtime
description: Use when building or reviewing VectoJS apps with @vectojs/core, Scene/Entity, canvas rendering, semantic DOM projection, accessibility, automation, framework mounting, or lifecycle cleanup.
---

# VectoJS Core Runtime

Use this skill to build canvas-native VectoJS scenes that remain accessible, automatable, and cleanly disposable.

## Core workflow

1. Confirm installed package versions and inspect local source/docs when exact API behavior matters.
2. Start from `@vectojs/core` primitives: one `Scene` per canvas, `Entity` subclasses for custom drawing, and the built-in `Rect`/`Circle`/`Group` shape primitives (1.9.0+) for plain boxes, dots, and transform containers — no subclass needed.
3. **Develop with `@vectojs/devtools` attached.** Add the dep and gate `attachDevtools(scene, …)` behind a `?debug` query flag so it never ships; the headless layer (`pickInScene`, `inspectEntity`, `auditScene`, `auditSceneSelection`, `diagnoseDirty`, `inspectText`) is the fast path for verifying geometry/state in tests and agent loops without the panel. One devtools instance per inspected Scene; detach on unmount.
4. Use world/local coordinate conversion in hit tests. Do not subtract only `this.x` once nested transforms, scale, or rotation are possible.
5. Expose semantics for interactive entities with `getA11yAttributes()`.
6. Prefer `scene.renderMode = 'onDemand'` for static or event-driven UI; call `scene.markDirty()` after external mutations.
7. Always call `scene.destroy()` when the host framework unmounts.

For copyable examples, read `references/scene-recipes.md`.

## Package layout

`@vectojs/core` owns the `Scene`/`Entity` runtime, renderers (Canvas/SVG/WebGL/WebGPU), a11y projection, and the `Entity`-based text renderers (`MSDFTextEntity`, `SVGEntity`, `TextEntity`/`GridTextEntity`). The lower-level engines are now standalone packages: `@vectojs/text` (BiDi, Arabic shaping, typography, MSDF fonts, prepared content grids), `@vectojs/layout` (`LayoutEngine`, `LayoutWorkerManager`, measurement), `@vectojs/math` (`SpatialHashGrid`, `SpringPhysics`), and `@vectojs/animation` (`Easing`, `TweenDriver`, `SpringDriver`). `@vectojs/core` depends on and re-exports all four, so `import { LayoutEngine, SpringPhysics, … } from '@vectojs/core'` and the `@vectojs/core/{text,layout,renderer}` subpaths keep working unchanged — prefer importing from the standalone packages only when you want a smaller dependency surface.

Above `core` sit `@vectojs/ui` (components, zero runtime deps) and then
`@vectojs/markdown` (`Markdown`, `CodeBlock`), which composes `ui` and therefore
must be imported from `@vectojs/markdown` — `ui` cannot re-export it without a
cycle. Markdown's math comes from `@vectojs/tex`, a zero-DOM vendored KaTeX
parse/layout kernel with a self-contained SVG emit layer, loaded dynamically on
the first formula. It is **not** MathJax; `mathjax-full` is no longer a
dependency anywhere, though the public entry points keep their historical names
`preloadMathJax()` / `isMathJaxReady()`.

## Architecture rules

- Treat VectoJS as a retained scene runtime, not a DOM component library.
- Let canvas own pixels and let the semantic layer own role/name/state and native input.
- Use `getContentProjection()` for searchable/copyable static text; never hand-author a sibling DOM text layer.
- Keep application state outside the scene when possible; update entities from state and mark the scene dirty.
- Use `Scene.step(dt)` for deterministic tests, simulations, and video export.
- Keep custom entities small: render, hit-test, semantics, and lifecycle should stay understandable without reading the whole app.

## Common mistakes

| Mistake                                                 | Correction                                                                                                                                                                                                                                                                         |
| ------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Passing `renderMode` to `new Scene()`                   | Create the scene, then set `scene.renderMode = 'onDemand'`.                                                                                                                                                                                                                        |
| Pixel-coordinate tests for controls                     | Use projected DOM roles for tests: `getByRole(...).click()`.                                                                                                                                                                                                                       |
| Forgetting teardown                                     | Call `scene.destroy()` to release renderers, observers, workers, and projected DOM.                                                                                                                                                                                                |
| Custom canvas input for text                            | Use `@vectojs/ui` `Input`/`TextArea` so IME, selection, clipboard, and undo stay native.                                                                                                                                                                                           |
| Rebuilding text every frame                             | Reuse entities and update width/content through the hot APIs where available.                                                                                                                                                                                                      |
| Subclassing `Entity` for a plain box/dot/group          | Use the built-in `Rect`/`Circle`/`Group` primitives (1.9.0+); reach for a subclass only when you need custom `render`/hit-test logic.                                                                                                                                              |
| Discarding dynamic interactive children without cleanup | Call `scene.detachA11y(child)` first — `syncA11y` creates/updates shadow nodes but never prunes them.                                                                                                                                                                              |
| `interactive = true` on thousands of ephemeral entities | Don't. Each one projects a real DOM element, and cost per entity **worsens** with count (measured: 1k → 6.4ms/frame, 20k → 715ms Chrome / 2737ms Firefox). Label the layer once and hit-test with `scene.findEntityAt(x, y)`, which resolves entities regardless of `interactive`. |
| Ignoring DPR² render cost on HiDPI screens              | Pass `maxDPR: 2` in `SceneOptions` to cap the backing-store pixel count. `maxDPR` is reapplied on every `resize()`. (Core 1.10.0+)                                                                                                                                                 |
| Custom motion in `update()` drops to ~2fps              | Drive motion through `setTransition`/`animateTo`/`springTo`, or override `hasPendingAnimations()` to return `true` while moving. Core 1.11.0+ warns in dev mode when this is missing.                                                                                              |

## Programmatic focus: `Entity.focus()` (Core 1.11.0+)

```ts
entity.focus();
```

Focuses the entity's projected a11y shadow element. If the element hasn't been
created yet (e.g., called synchronously after `scene.add()`), retries once on
the next rAF. Returns immediately; no promise. Prefer this over manual
`requestAnimationFrame` + `getElementById` patterns.

## Double-click: `'dblclick'` event (Core 1.11.0+)

```ts
entity.on("dblclick", (e) => handleDoubleClick(e));
```

Wired through the same dispatch as `click`. The existing a11yRoot-level
`dblclick` handler for text word-selection fires on the content-projection DOM
layer and is unaffected.

## Dev-mode runtime warnings (Core 1.11.0+)

Enable extra runtime guardrails:

```ts
Scene.devMode = true; // or set NODE_ENV=development or globalThis.__DEV__
```

Periodic checks (~every 2s at 60fps):

- **detachA11y leak**: warns when shadow-element count exceeds interactive entities
- **Content projection mismatch**: warns when projected text differs from DOM text
- **Missing `hasPendingAnimations`**: warns when `update()` is overridden but `hasPendingAnimations()` is not

These checks only run in dev mode and have negligible overhead.

## Static text selection (Core 1.5+)

```ts
override getContentProjection() {
  return { text: this.label, font: this.font, lineHeight: 24, selectable: true };
}
```

The transparent projection supplies browser find, selection, and copy; VMT state
still determines layout and pixels. Core keeps dynamic mirrors in tree order,
removes them recursively, and hides them when fully outside the viewport or a
`clipChildren` ancestor. Inspect a materialized mirror with
`scene.getContentElement(entity.id)`. Do not claim whole-document find for
virtualized or unmounted content.

Application shortcut routers must yield native copy when
`window.getSelection()?.isCollapsed === false` and must not suppress
Ctrl/Command+F unless they intentionally replace browser find.

## Pointer transaction lifecycle (Core 1.6.1+)

Projected interactive entities receive `pointerdown`, `pointermove`,
`pointerup`, and `pointercancel` through the VMT event router. The semantic node
captures the pointer after `pointerdown`, so movement continues outside the
entity bounds. Treat `pointerup` as commit and `pointercancel` as rollback:

```ts
entity.on("pointerdown", beginPreview);
entity.on("pointermove", updatePreview);
entity.on("pointerup", commitPreview);
entity.on("pointercancel", discardPreview);
```

Do not install parallel `document` or canvas listeners for product interaction.
Keep the transient preview outside durable history, then append one command only
when the pointer stream commits.

### Focusable canvas workspaces (Core 1.6.2+)

A non-control interaction region does not become keyboard-focusable from
`interactive = true` alone. Declare focus order through the semantic projection:

```ts
override getA11yAttributes() {
  return { role: 'region', label: 'Design canvas', tabIndex: 0 };
}
```

Listen for `keydown` on that Entity or an ancestor so shortcuts remain in VMT
capture/bubble routing and DevTools tracing. Yield undo/redo, clipboard, and text
editing shortcuts when the native target is an input, textarea, or editable
content. Do not add a parallel document keyboard listener.

### The full `A11yAttributes` surface

`getA11yAttributes()` returns far more than `role`/`label`/`tabIndex`. Every
field below is projected to a real attribute each frame with dirty checking, and
returning `undefined` **removes** it — so state that stops applying disappears
instead of going stale. Note `false` is distinct from `undefined`
(`aria-invalid="false"` means "explicitly valid").

Beyond the element/native fields (`tag`, `href`, `target`, `src`, `alt`,
`inputType`, `placeholder`, `value`, `textInputStyle`):

| Group         | Fields                                                                                                |
| ------------- | ----------------------------------------------------------------------------------------------------- |
| Naming        | `label`, `labelledby`, `describedby`                                                                  |
| State         | `checked`, `disabled`, `selected`, `expanded`, `required`, `invalid`, `valuemin`, `valuemax`, `level` |
| Relationships | `controls`, `haspopup`, `activedescendant`, `ariaModal`                                               |
| Live regions  | `live` (`'off'\|'polite'\|'assertive'`), `atomic`, `relevant`                                         |
| Pointer       | `pointerEvents` (`'auto'\|'none'`)                                                                    |

`required`/`invalid` are the only way a canvas-drawn form is announceable —
without them a validation state is invisible to AT. `live`/`atomic`/`relevant`
are what make streaming text (chat, logs, async validation) announce without
moving focus.

### Composite widgets: pooled hotspots + roving tabindex

A tree, grid, menu, radio group, or tab list must expose **one role per child**,
not just a container role. The pattern the built-ins use (reuse it, don't invent
one):

1. a transparent, focusable child `UIComponent` per **visible** child —
   `interactive = true`, `getA11yAttributes()` returning the child's role +
   state + roving `tabIndex`, `render()` a no-op;
2. the **parent** owns the keyboard handler and moves the single `tabIndex: 0`;
3. if the parent or an underlying content projection owns the pointer
   (selectable text, drag-to-scroll, canvas hit handling), give the hotspot
   `pointerEvents: 'none'` — a real click/drag then passes through, while
   keyboard focus and AT-synthesized `click` still work.

Pool only visible children, so a virtualized list projects O(viewport) hotspots
rather than one per row. Scroll the target into view _before_ moving focus to it.

### Tab order follows visual reading order

The a11y shadow tree is ordered by **where things are drawn**, not the order you
added them — rows top-to-bottom, then inline within each row. Two entities added
in any order but drawn side by side Tab left→right. For an RTL UI set
`readingDirection: 'rtl'` (a `SceneOptions` field, also a live setter) so the
inline order within each row reverses too.

### Forced colors (High Contrast)

A `<canvas>` is opaque pixels, so the browser's `forced-colors` remapping never
touches what you draw — a themed control stays unreadable unless it repaints
itself. Read `scene.forcedColors` (a getter backed by `(forced-colors: active)`;
the scene repaints automatically when it toggles) and draw with CSS system
colors:

```ts
render(r: IRenderer) {
  const forced = this.scene?.forcedColors ?? false;
  r.fill(forced ? 'ButtonFace' : this.bg);
  if (forced) r.stroke('ButtonText', 1);        // give the shape an edge
  r.fillText(this.label, x, y, this.font, forced ? 'ButtonText' : this.color);
}
```

Use `Highlight` for selection/focus, `Canvas`/`CanvasText` for surfaces and body
text. `Button` already does this.

### Positioned Canvas-to-DOM text geometry (Core 1.7+)

Do not assume an entity origin is a CSS text origin: Canvas `fillText()` takes
a baseline, while CSS positions line boxes. For simple text, return a local
`contentX`/`contentY` plus `baseline`. For text whose layout is already known,
project each visual row so the browser cannot re-wrap it differently:

```ts
override getContentProjection() {
  return {
    // Always expose the logical Unicode source, never shaped visual glyph order.
    text: 'مرحبا VectoJS alpha\nbeta',
    selectable: true,
    lines: [
      {
        text: 'مرحبا VectoJS',
        separatorAfter: ' ', // consumed soft-wrap source
        x: 18, y: 12, baseline: 25,
        font: '28px sans-serif', lineHeight: 42,
      },
      {
        text: 'alpha',
        separatorAfter: '\n', // explicit hard break
        x: 18, y: 54, baseline: 25,
        font: '28px sans-serif', lineHeight: 42,
      },
      {
        text: 'beta', x: 18, y: 96, baseline: 25,
        font: '28px sans-serif', lineHeight: 42,
      },
    ],
  };
}
```

`text` is the authoritative logical source. Each visual line also uses logical
source order; `separatorAfter` is the exact source gap before the next row: a
space for a consumed soft wrap, `"\n"` for a hard break, or `""` for a
space-less CJK wrap. Omitting it retains the legacy newline fallback. Core keeps
the separator inside the preceding positioned line and applies automatic base
direction, so cross-row Range geometry has no projection-root fragment and
Arabic with embedded LTR text copies correctly. Do not project Arabic
presentation forms or other renderer-shaped visual glyph order.

`Scene` transforms those local offsets with the entity matrix and aligns CSS
line boxes using `cssLineBoxBaseline(font, lineHeight)`. Use explicit lines for
mixed-size `RichText`, code blocks with an inset, or any custom wrapping. Give
every run the same visual line height; a CSS `font` shorthand otherwise resets
its line height to `normal` and can reproduce Firefox overlap.

For canvas-native editors, expose `textInputStyle: { font, lineHeight, padding
}` from `getA11yAttributes()`. Scene applies it to the real `<input>` or
`<textarea>` with `box-sizing: border-box`; draw the canvas text from the same
`cssLineBoxBaseline()` and padding. Do not position the native editor with
browser defaults.

When selection, copy, or a caret appears displaced, inspect the materialized
node with `scene.getContentElement(id)` / `scene.getA11yElement(id)`. Compare
the Canvas baseline to the DOM line span's `getBoundingClientRect().top +
cssLineBoxBaseline(computed.font, computed.lineHeight)` before changing fonts
or adding ad-hoc CSS offsets.

For multiline regressions, select the materialized root in Chromium and Firefox
and verify `Selection.toString()` plus real Ctrl/Command+C. Range fragments must
map to the projected row bands; Firefox may report both a line-box and glyph-box
fragment for one row, so compare the per-row union and reject only root-origin
or out-of-band fragments.

### Prepared code-like text (Core 1.8+)

For terminals, code blocks, and other fixed-grid text, compile the logical
source once with `prepareContentGrid()` and return that exact object as
`ContentProjection.grid`. Canvas paint and the semantic projection must consume
the same cells. Paint `cell.glyph` at `cell.x`; retain `grid.source` and each
cell's UTF-16 `sourceStart`/`sourceEnd` for copy, find, and syntax colors.

The prepared grid owns grapheme carets, tabs, wide CJK/emoji advances, ZWJ
clusters, CR/LF/CRLF separators, Arabic shaping, and UAX #9 bidi positions. Do
not create a second DOM overlay, project shaped glyph order as source, or infer
carets from viewport X. Core calibrates fonts in a cold batch and routes legal
carets in transformed two-dimensional geometry for ordinary, line-less, and
grid projections under DPR, browser zoom, rotation, reflection, and non-uniform
scale.

`Markdown` and `CodeBlock` live in **`@vectojs/markdown`** (they moved out of
`@vectojs/ui` in ui 2.0.0), which peers on `core >=1.25.0 <2` and `ui >=2.6.0 <3`.
Read the selectable grid recipe in `references/scene-recipes.md` before building
a custom implementation.

## Runtime gotchas (source-verified)

- **Animating from `update()`**: prefer overriding `hasPendingAnimations()` to
  report "still moving", or drive motion through
  `setTransition`/`animateTo`/`springTo`. `markDirty()` called _inside_
  `update()` also works — the dirty flag is consumed before the update/render
  pass, so the mark survives to the next frame.
- **`dt` is clamped to 100ms** (`MAX_FRAME_DT`). After a backgrounded tab, a
  breakpoint, or a long GC the real elapsed time can be seconds; feeding that
  raw into integration makes physics and tweens teleport. If you integrate `dt`
  yourself in `update(dt)`, it never exceeds 100ms — do not add your own
  substepping on top.
- **Off-screen scenes stop rendering.** An `IntersectionObserver` on the canvas
  pauses the rAF loop when the canvas scrolls fully out of view and resumes on
  re-entry. Nothing to opt into; where `IntersectionObserver` is unavailable
  (SSR/jsdom) the scene is treated as always on-screen. Don't hand-roll a
  visibility pause on top of it.
- **Embedded (non-fullscreen) canvases**: pass `disableWindowResize: true` and
  drive size with `scene.resize(w, h)`.
- **Custom `IRenderer` implementers**: `flush()` runs around _every_
  non-batched node each frame — it must only commit the pending primitive batch
  (near-zero cost when empty). Do end-of-frame work (a real GL render) in the
  optional `present()` hook, called exactly once per render pass. If you own a
  GPU context, also implement the two optional context-loss hooks — see below.
- **GPU context loss**: a GPU reset or memory-pressure eviction takes the
  context away and leaves the surface permanently blank unless handled. A
  renderer should (1) `preventDefault()` the loss event — otherwise the browser
  never fires the restore event, (2) report `isContextLost(): boolean` so
  `Scene.render` skips the pass instead of drawing against a dead context, and
  (3) on restore re-acquire the context, re-apply DPR/size, and fire the
  `onContextRestored(cb)` callback so the Scene repaints the cleared surface.
  `CanvasRenderer` does this for Canvas2D and `ThreeRenderer` for WebGL.

## Verification

Run the package or app’s normal checks. The VectoJS monorepo drives everything
through `just` (thin wrappers over the pinned toolchain, so local and CI match):

```bash
just verify          # = just check + just test, the pre-push gate
just check           # oxfmt --check, oxlint, markdownlint, shellcheck/shfmt, actionlint
just test            # unit tests, every package
just test-pkg core   # one package
just e2e             # real-browser e2e (HiDPI + text projection)
```

`oxfmt` is the only formatting authority — do **not** run `prettier` as a check.
A `.prettierrc.yaml` exists solely so editor tooling that resolves Prettier
without config does not reformat whole files with Prettier's defaults.
