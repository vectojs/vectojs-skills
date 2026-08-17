---
name: vectojs-knowledge-graph
description: Use when building or debugging a 2D node-link knowledge graph with @vectojs/knowledge-graph/model and @vectojs/core - paginated expansion, cancellation, snapshots, batch-painted graph layers, @vectojs/graph-layout physics, interaction, and idle scheduling.
---

# VectoJS Knowledge Graph (2D)

Patterns for canvas-native 2D knowledge-graph apps (node-link graphs with
search, drawers, hover tooltips, pan/zoom) on `@vectojs/core`. Read
`vectojs-graph-layout` for 2D physics, `vectojs-graph3d` for the 3D instanced
package, and `vectojs-performance` for profiling method.

## Renderer-neutral model and paging

Use `KnowledgeGraphModel` from `@vectojs/knowledge-graph/model` when the app
needs a bounded materialized cut of a large source graph. The subpath exposes
domain types, `MemoryDataSource`, and model state without importing the
session/rendering-facing package surface.

```ts
const model = new KnowledgeGraphModel({
  source,
  pageSize: 100,
  direction: "both",
  lang: "en",
});

await model.bootstrap(focusIds, false);
await model.expand(focusIds[0]);
draw(model.getGraphData());
```

- `KgDataSource.getNeighbors(id, { limit, cursor, direction, signal })` returns
  one page plus optional `total`, `nextCursor`, and `hasMore`. Treat cursors as
  opaque and propagate `signal` through backend I/O.
- `expand(id)` loads one page. Same-ID concurrent calls share one promise;
  different IDs may load concurrently. Call again from `partial` to resume.
- Expansion status is `idle`, `loading`, `partial`, `complete`, `failed`, or
  `cancelled`. `cancelExpand(id)` aborts active work; a later expand resumes at
  the last completed cursor. Failed calls reject and can be retried.
- Entities deduplicate by ID and merge labels. Facts deduplicate by the ordered
  `(source, predicate, target)` triple. Use model counts and list methods rather
  than maintaining a second materialized truth.
- `exportSnapshot()` / `importSnapshot()` persist versioned graph and pagination
  state. Import aborts requests and suppresses stale completions. Snapshots do
  not serialize in-flight work or error objects.
- Call `dispose()` to abort work and release state. Late completions cannot
  repopulate a disposed model.

The optional model `layout` is the XYZ `GraphLayout` contract from
`@vectojs/graph3d`, not the XY `ForceLayout2D`. For this skill's 2D architecture,
normally omit it and feed `model.getGraphData()` into your own `ForceLayout2D`
adapter. Keep model entity order aligned with the layout and rendering arrays.

## Architecture: one scene node batch-paints the graph

The graph itself is ONE `Entity` whose `render()` runs an immediate-mode loop
over your node/link arrays. Do **not** give each node its own `Entity` — the
engine's per-node transform/cull/`save()/restore()` scene walk was the dominant
cost at 5,000 items (~12fps) and is rebuilt every frame for nothing.

- `getBounds(): null` — the layer fills the viewport; opt out of engine culling.
- `isPointInside(): false` — the layer is never the pointer target; the App does
  hit-testing itself (it owns the badge rects the render pass computed anyway).
- UI panels (header, drawer, minimap) are sibling entities ABOVE the graph
  layer; the graph layer sits directly on the background.
- State lives in `KnowledgeGraphModel` or one equivalent application model; the
  entity reads it every frame. This is the inverse of DOM habits but keeps one
  copy of the truth and makes culling/hit-test loops trivial.

Reference implementation: `DanmakuLayer` in `vectojs-native/danmaku/bakudan`
(240Hz @ 5,000 danmaku, ~90Hz @ 20,000).

## The interaction contract (the #1 cause of "very laggy" graph apps)

The engine's idle management assumes state changes REACH it. When you draw
imperatively inside `render()` and mutate your model from window/canvas
listeners, nothing is marked dirty, so:

| Symptom                                                       | Mechanism                                                                                                                                                                                                                                                         | Correct fix                                                                                                                                                                                                                                              |
| ------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Everything runs at ~2 FPS even while hovering/panning/zooming | `autoThrottle` (default on) throttles an idle scene to its `idleFPS` floor — a hard 2 FPS before core 1.36.0, 60 FPS since — and `dirty`/`frameHadAnimation` never become true because you never called `markDirty()` and don't override `hasPendingAnimations()` | `renderMode: 'onDemand'` + `scene.markDirty()` on state mutations (hover, pan, zoom, expansion, active physics/camera/ripple steps) — but do not re-arm a cooled Scene-driven physics loop; or override `hasPendingAnimations()` only while work remains |
| "Fixed" with `autoThrottle: false` but CPU burns forever      | Always-mode renders the full canvas every frame, idle included                                                                                                                                                                                                    | That option exists for genuinely continuous content (danmaku). A settled graph must sleep                                                                                                                                                                |
| Hover tooltip lags one interaction behind                     | Hover state set but frame never scheduled                                                                                                                                                                                                                         | `markDirty()` inside the hover setter                                                                                                                                                                                                                    |

Measured on a real deployment (omm, 2026-08-15): a graph app whose hover/pan/
zoom never mark dirty rendered **16–17 frames per 8s (~2 FPS)** while the user
was actively interacting, with rAF itself at 240Hz and per-frame render cost
~1ms. One `markDirty()` renders exactly the frames needed; `onDemand` idles at
0 frames. Verify with `scene.dirty`, `scene._renderedFrames/_skippedFrames` and
`@vectojs/devtools/headless` `diagnoseDirty()`.

## Camera (pan/zoom)

- Keep `panX/panY/zoom` as plain numbers; `worldToScreen = x*zoom + pan`.
- `zoomAt(factor, cx, cy)`: anchor the point under the cursor —
  `pan = cursor - (cursor - pan) * (newZoom/zoom)`.
- Hit radius is in WORLD units: divide the screen-pixel radius by `zoom`.
- Clamp zoom (e.g. 0.15–3.5); snapping to a target with a per-frame eased
  interpolation in `update()` (or `render()`) is a camera animation and counts
  as `hasPendingAnimations()`.
- Wheel must be `preventDefault()` + `{ passive: false }`; canvas needs
  `touch-action: none` or mobile drag breaks.

## Physics (force layout)

Default to `ForceLayout2D` from `@vectojs/graph-layout` for 2D. It is
renderer-agnostic, dependency-free, uses a true 2D Barnes-Hut quadtree, supports
collision/accessor forces, and preserves simulation state across
`appendGraph()` and `removeNodes()`. Read `vectojs-graph-layout` for the full API,
input rules, d3 migration, complexity, and measurement guidance.

- Step once per host frame. `step()` returns `true` **while active**. When a
  Scene `update()` drives physics, call `scene.markDirty()` only while true;
  marking dirty from every cooled update prevents `renderMode: 'onDemand'` from
  sleeping. An external scheduler may render the final false-returning mutation
  once, but it must then stop invoking the physics callback.
- Use `appendGraph()` for expansion, `removeNodes()` for node deletion,
  `removeLinks()` for edge deletion, and `updateLinks()` for force-property
  changes. Reacquire the live `positions` view after node topology methods. Use
  `getNodeIndex()` for current mappings; append and link-only mutation preserve
  existing indices, while node removal compacts them.
- Drag with `setNodePin(index, { x, y })` / `clearNodePin(index)`, call
  `reheat()`, and `markDirty()` on every move or pin-state change.
- Existing d3-force apps can migrate incrementally: stop d3's timer, retain
  host-controlled ticks, convert negative charge to positive `repulsion`, use
  primitive endpoint IDs, and map `fx`/`fy` to pins. d3's `velocityDecay` is
  loss while graph-layout's is retention, so start with `1 - d3VelocityDecay`.
- If d3 remains temporarily, keep its quadtree `forceManyBody`/`forceCollide`,
  rebuild only on topology changes, and preserve this same VectoJS
  `markDirty()`/`onDemand` contract. Do not use `@vectojs/graph3d` physics as a
  2D substitute.

## Rendering ladder (pick by measured draw cost, not by guess)

Draw cost with the Canvas2D immediate-mode loop, color-batched, with per-node
text pills: **~2.5ms p50 / 5.4ms p95 per frame at 448 nodes / 437 links**
(60fps, DPR 1.6, 240Hz panel, measured 2026-08-15). So Canvas2D is NOT your
first suspect at this scale — measure before migrating backends.

1. **Canvas2D + batching**: group primitives by color to kill state changes;
   cull off-screen with a margin; reuse scratch arrays with `length = 0`;
   never allocate per frame (no per-node `{x,y}` objects, no per-frame Maps,
   no per-link template/string keys). Text pills are the first wall:
   `fillText` re-shapes CJK/emoji per frame.
2. **`TextRasterCache`** (core ≥ 1.12): pre-rasterize each `(font, color, text)`
   once and blit with `drawImage` — removes per-frame shaping; perfect for
   node labels. Font-size buckets (integer px) reduce `ctx.font` churn.
3. **WebGL point layer**: `pointBackend: 'webgl'` stacks a WebGL2 layer whose
   `pointRenderer` batches `addCircle`/`addRect`/`addSprite`/MSDF `addGlyph`
   into ~1 draw call. **There is no line primitive — edges stay Canvas2D.**
   MSDF glyphs need an atlas (`setMSDFTexture` + `MSDFFont.layout`); emoji /
   out-of-atlas glyphs fall back to `TextRasterCache`. Auto-falls back to
   Canvas2D when WebGL2 is unavailable. This is how danmaku holds 240Hz at
   5,000 labels. For omm-style graphs, the win starts at thousands of labeled
   nodes, not hundreds.
4. **WebGPU**: `particleBackend: 'auto'` only accelerates
   `ComputeParticleEntity` simulation (WebGPU → CPU fallback). It is NOT a
   scene renderer — there is no whole-scene WebGPU→WebGL→Canvas2D cascade.
   Canvas2D is the scene renderer; GL/WebGPU are optional stacked layers for
   specific primitive classes.

Cap `maxDPR` (e.g. 1–2): backing-store cost scales with `logical × dpr²`, and a
DPR-3 machine silently quadruples your fill rate vs the dev box.

## Hit-testing

- Reuse the geometry the render pass computed (pill rects, node screen
  positions) instead of recomputing — draw and hit-test must read the same
  numbers.
- Test pills topmost-first, then a world-space radius check via
  `screenToWorld` (divide the radius by `zoom`); a linear scan is fine to ~10k
  nodes, a spatial hash beyond.
- Rebuild hit rects only when positions/pills change; hover changes must
  `markDirty()` (see the contract above).

## Frame budget

Never quote FPS — vsync saturates it. Report frame-time p50/p99 and the share
of frames inside budget, and check `scene._lastFrameMs` per frame. A 2 FPS
scene can show "60fps" rAF on a 240Hz panel; the scene's rendered/skipped
counters tell the truth.
