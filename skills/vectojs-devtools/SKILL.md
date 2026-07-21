---
name: vectojs-devtools
description: Use when inspecting or debugging a live VectoJS scene with @vectojs/devtools — the VMT inspector panel, entity picking, tree/model queries, geometry readouts, layout audits (text overflow, overlap), scene snapshots/diffs, or when you need to locate which entity owns a pixel or why an entity is positioned/sized wrong.
---

# VectoJS Devtools (@vectojs/devtools, 0.4.1+)

An in-page Virtual Math Tree inspector plus a headless audit/capture layer.
The panel itself is a VectoJS Scene (dogfooding `@vectojs/ui`), docked to the
right edge of the page. Peer deps: `@vectojs/core >=1.0.0`, `@vectojs/ui >=1.0.0`.

## Attach / detach

```ts
import { attachDevtools } from "@vectojs/devtools";

const devtools = attachDevtools(scene, {
  width: 340, // panel width px (default 340)
  refreshInterval: 500, // auto-refresh ms while open; 0 disables (default 500)
  traceEvents: true, // opt-in pointer/wheel/keyboard routing trace
  dockSide: "right", // 'right' | 'left' (0.5.0; default 'right')
  showPerf: true, // live perf HUD strip reading Scene.frameStats (0.5.0)
  defaultTab: "tree", // 'tree' | 'inspect' | 'audit' | 'events' | 'settings' (0.5.0)
});
// …
devtools.detach(); // alias for panel.destroy(); always call on unmount
```

`attachDevtools` returns the `DevtoolsPanel`. One instance per inspected Scene.

## What the panel gives you

Since **0.5.0** the panel is a modern glass dock (rounded corners, shadow,
`Card`-grouped sections) organized into **tabs** (`Tree · Info · Audit · Log ·
⚙`), with a header of three ghost text-glyph icon buttons (`⌖` pick / `⟳`
refresh / `⚠` audit) and count badges (total / interactive⚡ / findings⚠).

- **Entity tree (`Tree` tab)** — live VMT view built from `scene.rootEntity` /
  `scene.overlayRootEntity`. Labels show `type (x,y) w×h` plus ⚡ (interactive)
  and ▶ (animating) markers. A **filter Input** (0.5.0) narrows by type/id
  substring; it's view-only — the id→entity index still resolves everything.
  Programmatic: `panel.setFilter(text)`.
- **Pick mode** — click any pixel on the host canvas; deepest entity wins.
- **Audit (`Audit` tab, 0.2.0)** — runs `auditScene` and lists findings; selecting
  one selects + highlights the offending entity. Since 0.5.0 findings live in
  their own tab (they no longer replace the tree). Programmatic: `panel.audit()`
  returns the findings, `panel.selectFinding(i)` selects one.
- **Selection highlight** — drawn through the host scene's overlay. Toggle it via
  the Settings tab or `panel.setHighlightEnabled(bool)` (0.5.0).
- **Detail readout + inline edit (`Info` tab)** — position/size/opacity/flags;
  arrow keys nudge `x/y` live, and 0.5.0 adds inline `x`/`y`/`opacity` `Input`
  editors plus **Copy path** / **Copy state JSON** buttons. (Careful: while a
  devtools selection exists, arrows are consumed — in apps with their own
  keyboard nav, deselect or detach first.)
- **Perf HUD (0.5.0)** — a bottom strip reading `scene.frameStats` (fps,
  ms/frame, entity count, render mode, rendered/skipped frames). The fps is the
  real _rendered-frame_ cadence, so an idle `onDemand`/auto-throttled scene
  honestly reads ~2fps, not a fake 60. Disable with `showPerf: false`.
- **Settings tab (0.5.0)** — highlight toggle, refresh-interval and dock-side
  (left/right) switches (`panel.setRefreshInterval(ms)`, `panel.setDockSide(side)`).
- **Event trace (`Log` tab; 0.3.0; content provenance in 0.4.0; pointer cancellation in 0.4.1)** — opt-in bounded recent-event view. It shows pointer,
  wheel, and keyboard type/source/target summaries after application handlers
  run, including whether the browser default was prevented.

## Headless / programmatic use (preferred for agents)

You rarely need the visual panel: the model layer works in tests and jsdom.
Query numbers instead of taking screenshots.

```ts
import {
  buildTreeModel,
  pickInScene, // 0.1.x
  inspectEntity,
  entityPath, // 0.2.0
  auditScene,
  captureSnapshot,
  diffSnapshots, // 0.2.0
  createEventTrace, // 0.3.0
} from "@vectojs/devtools/headless";

const hit = pickInScene(scene, x, y); // which entity owns this point?
if (hit) console.log(inspectEntity(hit)); // structured EntityInfo (JSON-safe)

const trace = createEventTrace(scene, { capacity: 50 });
trace.subscribe((entry) => console.log(entry.type, entry.targetPath));
// trace.entries is JSON-safe and oldest-to-newest; trace.destroy() removes listeners.
```

`inspectEntity` is the structured replacement for `describeEntity` (which still
exists, returning human-readable lines): world bounds + transform, flags,
`clipChildren`, child count, a duck-typed text preview (`.text` / `.value`),
and a11y projection attributes when present.

`createEventTrace` observes the document at capture phase but never installs VMT
listeners or changes dispatch. A projected a11y or selectable-content id resolves
first; canvas pointer input falls back to `pickInScene`; global keyboard routers
are reported as `source: "document"` when no entity owns the focused element.
Entries retain only scalar state, not DOM events or entity references.
`defaultPrevented` is read after browser dispatch completes, so it reports the
final application decision. Keep the trace opt-in and destroy it outside the
normal devtools panel life cycle.

The pointer trace includes `pointercancel`. For a transactional drag or range
selection, expect `pointerdown` followed by zero or more `pointermove` entries
and exactly one terminal `pointerup` (commit) or `pointercancel` (rollback).
Missing termination usually means the interactive entity was not projected or
the application bypassed VMT pointer capture.

`entry.source === "content"` means the native browser event started on a
`[data-vecto-content]` mirror. Use it with `defaultPrevented`, `targetPath`, and
local coordinates to diagnose why text drag-selection, copy, or wheel routing
was intercepted. Tests should dispatch from a descendant of the materialized
content node (`scene.getContentElement(id)`) and await one microtask before
asserting the finalized trace entry.

## Triage map: symptom → tool

Reach for numbers before screenshots:

| Symptom                                  | Workflow                                                                                                                              |
| ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| Which entity owns this pixel?            | `pickInScene(scene, x, y)` → `inspectEntity(hit)`                                                                                     |
| Entity positioned/sized wrong            | `inspectEntity` world bounds, then walk ancestors — first one with wrong bounds owns the bug (`entityPath` names the chain)           |
| Something overflows/overlaps somewhere   | `auditScene(scene)` — findings carry entityPath + per-edge overflow amounts                                                           |
| Interaction moved something it shouldn't | `captureSnapshot` → interact → `diffSnapshots`                                                                                        |
| Click/wheel/key goes to the wrong place  | `createEventTrace` — source/targetPath/coords + final `defaultPrevented`                                                              |
| Drag-selection or copy intercepted       | Trace entries with `source === "content"`; check `defaultPrevented` + targetPath                                                      |
| Drag stuck / never commits               | Pointer trace transaction: `pointerdown` → moves → exactly one `pointerup`/`pointercancel`; missing terminal = projection/capture bug |
| Selection drifts from pixels after zoom  | Not a devtools bug — the app owns sizing and never called `scene.resize()` (Firefox Range recalibration)                              |

`entityPath(entity)` returns the ancestry chain as `"Scene > Card#<id8> > Text#<id8>"`
(ids truncated to 8 chars) — note snapshot-diff paths use `type[index]` chains
instead, since ids are random per run.

## Scene auditing (0.2.0)

```ts
const findings = auditScene(scene, {
  tolerance: 0.5, // px slack before an escape/overlap counts
  includeOverlay: false, // overlay (modals/highlights) excluded by default
  ignore: (e) => e.id.startsWith("debug-"), // prune subtrees
  ignoreOverlap: (a, b) => a.id === "badge", // allow intentional stacking
});
// -> AuditFinding[]: { kind, entityId, entityPath, worldBounds, message,
//    containerBounds?, overflow?{left,right,top,bottom}, otherId?, intersection? }
```

Detects four kinds, deterministically sorted and JSON-safe:

- `text-overflow` — a text-bearing entity's measured box escapes its nearest
  sized ancestor. (ui `Text` self-sizes: its width/height ARE the measured
  content, so escaping the container means "the text doesn't fit".)
- `clip-overflow` — content escapes a `clipChildren` ancestor = pixels cut off.
- `overlap` — **siblings only** (parent-child containment is normal; cross-branch
  stacking belongs on the overlay, which is excluded by default).
- `viewport-overflow` — entity with no sized ancestor drawn outside the canvas.

Deliberate blind spots to know about: scrollable containers (`ScrollView`,
`VirtualList`, `TreeView`, `Tree` — override via `scrollableTypes`, matched by
`constructor.name`, so minified bundles need explicit names) exempt the
**vertical** axis; `opacity: 0` entities are skipped entirely.

**CI gate pattern**: `expect(auditScene(scene)).toEqual([])` — "audit clean".

## Snapshots & diffs (0.2.0)

```ts
const before = captureSnapshot(scene); // deterministic JSON tree of the whole scene
// … perform an interaction …
const diffs = diffSnapshots(before, captureSnapshot(scene));
// -> [{ path: "root > GridEntity[0]", kind: "changed", changes: { x: {from,to} } }]
```

Diffs are keyed by **structural path** (`type[index]` chains), never by entity
id — ids are random per run. Default-valued props (opacity 1, flags false) are
omitted from snapshots so JSON diffs stay quiet. Use snapshot-pairs as golden-
state assertions in smoke tests.

## Gotchas

- The panel adds its own canvas + Scene; never video-export or benchmark with the
  panel attached.
- `refreshInterval` polls; for deterministic tests set it to `0` and call the model
  functions yourself.
- Devtools is a dev dependency by nature — gate `attachDevtools` behind a dev flag
  (e.g. `location.search.includes("debug")`) so it never ships to production bundles.
- In audit tests under jsdom, use stub entities with explicit width/height — real
  ui `Text` measurement is unreliable without a canvas rasterizer.
- On `@vectojs/devtools@0.4.3+`, the dock no longer intercepts pointer input over
  the host page's right edge — the dock container and its canvas are
  `pointer-events: none`, so a real host app's own right-edge content (tab close
  buttons, toolbar buttons) sitting under the dock's 320px band stays clickable.
  Only the panel's own a11y-projected controls opt back in via `auto`. On older
  versions the dock ate every click in that band silently — if a headless
  interaction test with `?debug` on ever fails only near the right edge, rule out
  a stale devtools version before assuming the app has a real bug.
