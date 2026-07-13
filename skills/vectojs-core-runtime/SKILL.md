---
name: vectojs-core-runtime
description: Use when building or reviewing VectoJS apps with @vectojs/core, Scene/Entity, canvas rendering, semantic DOM projection, accessibility, automation, framework mounting, or lifecycle cleanup.
---

# VectoJS Core Runtime

Use this skill to build canvas-native VectoJS scenes that remain accessible, automatable, and cleanly disposable.

## Core workflow

1. Confirm installed package versions and inspect local source/docs when exact API behavior matters.
2. Start from `@vectojs/core` primitives: one `Scene` per canvas and `Entity` subclasses for custom drawing.
3. Use world/local coordinate conversion in hit tests. Do not subtract only `this.x` once nested transforms, scale, or rotation are possible.
4. Expose semantics for interactive entities with `getA11yAttributes()`.
5. Prefer `scene.renderMode = 'onDemand'` for static or event-driven UI; call `scene.markDirty()` after external mutations.
6. Always call `scene.destroy()` when the host framework unmounts.

For copyable examples, read `references/scene-recipes.md`.

## Architecture rules

- Treat VectoJS as a retained scene runtime, not a DOM component library.
- Let canvas own pixels and let the semantic layer own role/name/state and native input.
- Use `getContentProjection()` for searchable/copyable static text; never hand-author a sibling DOM text layer.
- Keep application state outside the scene when possible; update entities from state and mark the scene dirty.
- Use `Scene.step(dt)` for deterministic tests, simulations, and video export.
- Keep custom entities small: render, hit-test, semantics, and lifecycle should stay understandable without reading the whole app.

## Common mistakes

| Mistake                                                 | Correction                                                                                            |
| ------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| Passing `renderMode` to `new Scene()`                   | Create the scene, then set `scene.renderMode = 'onDemand'`.                                           |
| Pixel-coordinate tests for controls                     | Use projected DOM roles for tests: `getByRole(...).click()`.                                          |
| Forgetting teardown                                     | Call `scene.destroy()` to release renderers, observers, workers, and projected DOM.                   |
| Custom canvas input for text                            | Use `@vectojs/ui` `Input`/`TextArea` so IME, selection, clipboard, and undo stay native.              |
| Rebuilding text every frame                             | Reuse entities and update width/content through the hot APIs where available.                         |
| Discarding dynamic interactive children without cleanup | Call `scene.detachA11y(child)` first — `syncA11y` creates/updates shadow nodes but never prunes them. |

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

### Exact Canvas-to-DOM text geometry

Do not assume an entity origin is a CSS text origin: Canvas `fillText()` takes
a baseline, while CSS positions line boxes. For simple text, return a local
`contentX`/`contentY` plus `baseline`. For text whose layout is already known,
project each visual row so the browser cannot re-wrap it differently:

```ts
override getContentProjection() {
  return {
    text: 'small large',
    selectable: true,
    lines: [{
      text: 'small large', x: 18, y: 12, baseline: 25,
      font: '28px sans-serif', lineHeight: 42,
      runs: [
        { text: 'small ', font: '16px sans-serif' },
        { text: 'large', font: 'bold 28px sans-serif' },
      ],
    }],
  };
}
```

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

## Runtime gotchas (source-verified)

- **Animating from `update()`**: prefer overriding `hasPendingAnimations()`
  to report "still moving", or drive motion through
  `setTransition`/`animateTo`/`springTo`. On core **0.2.6+**, `markDirty()`
  called _inside_ `update()` also works (the dirty flag is consumed before
  the update/render pass, so the mark survives to the next frame). On core
  **≤ 0.2.5** it was wiped by the loop's end-of-tick `dirty = false`, so an
  update()-integrating entity stepped at ~2 FPS once the throttle engaged —
  or stalled in onDemand mode. That exact bug shipped three separate times
  (ScrollView, VirtualList, TreeView).
- **onDemand + `autoThrottle: false`**: on core ≤ 0.2.5 this combination
  silently disables the onDemand frame skip (renders every rAF). Fixed in
  core 0.2.6; on older versions leave `autoThrottle` at its default.
- **Embedded (non-fullscreen) canvases**: pass `disableWindowResize: true`.
  On core ≤ 0.2.5 also call `scene.resize(w, h)` immediately after
  construction — the default renderer sized the canvas to the window anyway
  (fixed in core 0.2.6).
- **Custom `IRenderer` implementers**: `flush()` runs around _every_
  non-batched node each frame — it must only commit the pending primitive
  batch (near-zero cost when empty). Do end-of-frame work (a real GL render)
  in the optional `present()` hook, called exactly once per render pass.
- **Springs vs background tabs**: on core ≤ 0.2.5, `springTo` /
  `setTransition('spring')` integrated the raw rAF `dt`, so returning from a
  background tab (multi-second dt) made in-flight springs diverge violently.
  Core 0.2.6 substeps the integration.
- **`destroy()` and animation promises**: on core ≤ 0.2.5, promises from
  `animateTo`/`springTo` never settled if the entity was destroyed mid-flight
  (awaiting exit sequences hung). Core 0.2.6 resolves them on `destroy()`.

## Verification

Run the package or app’s normal checks. For the VectoJS monorepo, useful gates are:

```bash
bun run test
bun run build
oxlint packages/core/src packages/ui/src packages/three/src
prettier --check "**/*.{js,ts,json,md,html,yaml}"
```
