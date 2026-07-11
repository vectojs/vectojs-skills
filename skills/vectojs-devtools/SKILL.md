---
name: vectojs-devtools
description: Use when inspecting or debugging a live VectoJS scene with @vectojs/devtools — the VMT inspector panel, entity picking, tree/model queries, geometry readouts, layout audits (text overflow, overlap), scene snapshots/diffs, or when you need to locate which entity owns a pixel or why an entity is positioned/sized wrong.
---

# VectoJS Devtools (@vectojs/devtools, 0.4.0+)

An in-page Virtual Math Tree inspector plus a headless audit/capture layer.
The panel itself is a VectoJS Scene (dogfooding `@vectojs/ui`), docked to the
right edge of the page. Peer deps: `@vectojs/core >=1.0.0`, `@vectojs/ui >=1.0.0`.

## Attach / detach

```ts
import { attachDevtools } from "@vectojs/devtools";

const devtools = attachDevtools(scene, {
  width: 320, // panel width px (default 320)
  refreshInterval: 500, // auto-refresh ms while open; 0 disables (default 500)
  traceEvents: true, // opt-in pointer/wheel/keyboard routing trace
});
// …
devtools.detach(); // alias for panel.destroy(); always call on unmount
```

`attachDevtools` returns the `DevtoolsPanel`. One instance per inspected Scene.

## What the panel gives you

- **Entity tree** — live VMT view built from `scene.rootEntity` / `scene.overlayRootEntity`.
  Labels show `type (x,y) w×h` plus ⚡ (interactive) and ▶ (animating) markers.
- **Pick mode** — click any pixel on the host canvas; deepest entity wins.
- **Audit button (0.2.0)** — runs `auditScene` and lists findings in place of the
  tree; selecting a finding selects + highlights the offending entity. `Refresh`
  restores the normal tree. Programmatic: `panel.audit()` returns the findings,
  `panel.selectFinding(i)` selects one.
- **Selection highlight** — drawn through the host scene's overlay.
- **Detail readout + nudging** — position/size/opacity/flags; arrow keys nudge
  `x/y` live (careful: while a devtools selection exists, arrows are consumed —
  in apps with their own keyboard nav, deselect or detach first).
- **Event trace (0.3.0; content provenance in 0.4.0)** — opt-in bounded recent-event view. It shows pointer,
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

`entry.source === "content"` means the native browser event started on a
`[data-vecto-content]` mirror. Use it with `defaultPrevented`, `targetPath`, and
local coordinates to diagnose why text drag-selection, copy, or wheel routing
was intercepted. Tests should dispatch from a descendant of the materialized
content node (`scene.getContentElement(id)`) and await one microtask before
asserting the finalized trace entry.

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
