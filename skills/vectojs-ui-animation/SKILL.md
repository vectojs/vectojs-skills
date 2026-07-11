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
- Use `RichText.appendSpans()` and `Markdown.appendMarkdown()` for streaming output.
- On `@vectojs/ui@1.7.0+`, Text, RichText, Markdown, CodeBlock, and Table cell text are natively selectable by default. Configure `selectable` or call `setSelectable()`; do not implement canvas clipboard or selection handles for static text.
- Call `Table.layout()` after changing an external Entity cell. Table rendering is draw-only; string cells are Text entities and each logical cell owns one content projection.
- Prefer `Stack`/`Flow` composition over hand-positioning every child.
- On `@vectojs/ui@1.7.1+`, use `@vectojs/ui/input` for Input-only code,
  `@vectojs/ui/text` for selectable Text-only code, and `@vectojs/ui/measure`
  for measurement-only code; retain the root import for multi-component
  surfaces.

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
- Creating a new `Tooltip` per hover event instead of one per target (and on
  ui ≤ 0.2.5, rapid re-hovers stacked show timers — fixed in ui 0.2.6).
- Reimplementing slider keyboard handling — ui 0.2.6's `Slider` handles
  Arrow/Home/End itself and takes a `step` option (integer-only before).
