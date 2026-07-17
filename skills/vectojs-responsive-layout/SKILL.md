---
name: vectojs-responsive-layout
description: Use when designing adaptive VectoJS canvas layouts with browser resize or zoom, Stack, Flow, Card, ScrollView, VirtualList, responsive panels, dashboards, forms, or layout reflow.
---

# VectoJS Responsive Layout

Use this skill when a VectoJS UI must adapt to viewport size, browser zoom, density, content length, or resizable panels.

## Layout workflow

1. Define layout state in logical CSS pixels, not backing-store pixels.
2. Resize the `Scene` from the containing element, not blindly from `window`, when embedding in an app shell.
3. Compose with `Stack`, `Flow`, `Card`, `ScrollView`, `VirtualList`, `TreeView`, and resizable panels.
4. After direct child size changes, call the parent layout method and mark the scene dirty.
5. Keep one scroll owner per region; avoid nested wheel handlers without clear boundaries.
6. Use role labels and semantic regions even for canvas-rendered layout containers.

Read `references/layout-recipes.md` for copyable patterns.
For OS/browser/zoom/DPR consistency and text-selection alignment (embedded
`scene.resize()` bridge, Firefox Range recalibration, web-font race, the
DPR-1-vs-2 test matrix), read `references/cross-environment.md`.

## Design rules

- Use `scene.resize(width, height)` for logical layout dimensions.
- Let VectoJS/Canvas handle high-DPI backing stores; do not multiply layout coordinates by DPR.
- Make breakpoint decisions from available logical width/height.
- Prefer reflowing existing entities to destroying and recreating the full tree.
- Reserve virtualization for long lists/tables/trees; do not render thousands of offscreen rows as regular children.
- Treat browser zoom as a layout-input multiplier only when product requirements explicitly need density changes beyond normal CSS pixel behavior.

## Common mistakes

| Mistake                                                           | Correction                                                                                                                                                                                                 |
| ----------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Reading `canvas.width` for layout                                 | Use container CSS size or `scene.width` / `scene.height`.                                                                                                                                                  |
| Recreating every component on resize                              | Reposition/reconfigure existing entities, then `scene.markDirty()`.                                                                                                                                        |
| ScrollView inside another wheel-capturing region                  | Give each wheel gesture one owner or define escape behavior.                                                                                                                                               |
| Fixed desktop-only coordinates                                    | Add breakpoint functions and test narrow, wide, and zoomed layouts.                                                                                                                                        |
| Changing child size without relayout                              | Call `stack.layout()` / equivalent and mark dirty.                                                                                                                                                         |
| Growing ScrollView content without re-measuring                   | `scrollView.add()` measures automatically, but mutating an existing child's size needs `scrollView.updateContentSize()` or the max-scroll clamp goes stale.                                                |
| Guessing `estimatedRowHeight` for fixed-height `VirtualList` rows | Set it to the exact row height — the estimate only exists for variable rows (measured heights are cached per index); `setItems()` resets scroll and that cache.                                            |
| Passing `canvas.width`/`canvas.height` into a layout function     | Those are the DPR-scaled backing store (2× at retina). Pass `window.innerWidth`/`scene.width` — the logical size — or panels double in width.                                                              |
| Expecting `Tabs` to stay legible with many tabs                   | `Tabs` (>= `@vectojs/ui@1.1.3`) keeps a fixed `tabWidth` (floor `minTabWidth`) and scrolls horizontally; pass `closable: true` + `onClose` for per-tab × close. Since 1.9.4 surplus bar width stays empty (never stretches past `tabWidth`). |
| Wanting no tab bar while only one tab exists (Vim `showtabline=1`) | `Tabs` (>= `@vectojs/ui@1.9.5`) `autoHideTabBar: true` — bar + hit region vanish below two tabs, content takes full height; read the live `effectiveTabBarHeight` getter (not `tabHeight`) when laying out siblings around the bar. |
| Drag handler reading `localX` deltas from the dragged handle      | `PanelResizeHandle` (>= `1.1.3`) uses `sceneX`/`sceneY` — a coordinate space that does not move with the handle. Any custom drag must do the same or it lags the cursor.                                   |
| Selection highlights drift after zoom (Firefox), canvas looks fine | The app owns sizing but never calls `scene.resize()` — it is the Range-metric recalibration hook. Bridge the container via ResizeObserver (`references/cross-environment.md`).                             |
| Hit/selection tests pass headless, fail on real laptops           | Headless runs DPR 1; real machines are DPR 2 — run pointer/selection tests at `deviceScaleFactor: 2` too. Offset proportional to distance from origin ⇒ DPR bug.                                            |
| Text renders in a different font than it was measured with        | Web-font race: construct text after `await document.fonts.ready`, re-measure from `document.fonts.onloadingdone` for lazy fonts.                                                                            |

## Verification

Check at least:

- narrow mobile width;
- desktop width;
- browser zoom 125% and 150%;
- keyboard navigation/focus order;
- role-based automation for interactive controls.
