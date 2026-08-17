---
name: vectojs-graph3d
description: Use when building or debugging a 3D force-directed graph with @vectojs/graph3d — Graph3D instanced rendering, the GraphLayout contract, VectoForceLayout (in-house Barnes-Hut) vs D3ForceLayout, GraphInteraction hover/select/drag-to-pin, or when a graph layout is slow, unstable, or non-deterministic.
---

# VectoJS Graph3D

`@vectojs/graph3d` renders a force-directed graph as **instanced** Three.js
geometry and keeps layout strictly separate from rendering. Its only peer is
`three`; it does **not** depend on `@vectojs/three` or `@vectojs/core`, so a
graph can be dropped into a plain Three.js app. (`@vectojs/three` becomes
relevant only if you also want VectoJS UI panels in the same 3D scene.)
For renderer-agnostic true 2D physics, use `@vectojs/graph-layout` and read
`vectojs-graph-layout`. Both packages use host-driven `step()` calls that return
true while the simulation remains active and false once cooled; their XY and
XYZ buffers are not interchangeable.

## Architecture: layout and renderer are decoupled

The renderer is deliberately ignorant of how positions were produced.

```ts
import { Graph3D, VectoForceLayout, GraphInteraction } from "@vectojs/graph3d";

const graph = new Graph3D({ nodeRadius: 4 });
graph.setGraphData({ nodes, links }); // rebuilds instanced buffers

const layout = new VectoForceLayout();
layout.setGraph({ nodes, links });

function frame() {
  const active = layout.step(); // advance the simulation
  graph.applyPositions(layout.positions); // xyz triplets in node order
  if (active) requestAnimationFrame(frame);
}
```

- `setGraphData()` rebuilds GPU resources — instanced buffers are fixed-size, so
  a changed node/link **count** means fresh meshes. Styling-only changes to the
  same topology don't need it.
- `applyPositions(Float32Array)` takes xyz triplets in node order. Call it after
  every layout step that moved something.
- Unknown link endpoints **throw** rather than silently drawing a line to the
  origin — a wrong id is a bug, not a visual glitch.

## Choosing a layout

Both implement the same `GraphLayout` contract (`setGraph`, `step(iterations?)`
returning true while active, `positions`, and optional
`pinNode`/`unpinNode`/`reheat`),
so they are drop-in swappable.

|              | `VectoForceLayout`                                                                                | `D3ForceLayout`       |
| ------------ | ------------------------------------------------------------------------------------------------- | --------------------- |
| Dependencies | **none** (in-house)                                                                               | `d3-force-3d`         |
| Algorithm    | Barnes-Hut octree N-body, O(N log N)/tick                                                         | d3's force simulation |
| Determinism  | seeded PRNG, f32 throughout                                                                       | depends on d3         |
| Measured     | **4.2–7.2× faster (Chrome), 5.0–8.3× (Firefox)** per tick at 500–5000 nodes; margin widens with N | baseline              |

**Default to `VectoForceLayout`.** It removes a dependency and is several times
faster; `D3ForceLayout` remains for parity with an existing d3 tuning.

### Tuning `VectoForceLayout`

Defaults are chosen so linked nodes settle closer than unlinked ones:

- `linkDistance` (30) — spring resting length.
- `linkStrength` (0.3) — fraction of overshoot corrected per tick, scaled by alpha.
- `repulsion` (300) — positive magnitude (d3 expresses this as negative charge).
- `centerStrength` (0.02) — pull toward the origin.
- `velocityDecay` (0.6) — per-tick velocity retention, i.e. `1 - friction`.
- `theta` (0.9) — Barnes-Hut opening angle. `0` = exact O(N²); larger = faster
  and looser. Raise it before lowering node count.
- `alphaDecay` (0.0228) — d3's default, ~300 ticks to cool.

`step()` returns `true` while active and `false` once cooled. Call `reheat()`
after a topology or pin change instead of rebuilding the layout.

## Interaction

`GraphInteraction` wires hover, select, and drag-to-pin against the renderer's
`pickNode(raycaster)`. Drag-to-pin routes through `pinNode`/`unpinNode`, which is
why those are part of the layout contract — a pinned node is held by the
simulation, not by the renderer.

`graph.getNodePosition(index, target)` reads a node's current world position into
a `THREE.Vector3` you own (returns `null` for an out-of-range index).

## Common mistakes

- **Rebuilding `Graph3D` every frame.** `setGraphData()` is a GPU rebuild; only
  call it when the node/link count changes.
- **Stepping the layout inside `render()`.** Step it in your frame loop, then
  hand positions to the renderer. Mixing them makes the simulation frame-rate
  dependent.
- **Not calling `dispose()`.** Both `Graph3D` and `GraphInteraction` own GPU
  resources and listeners.
- **Assuming `positions` is a copy.** It's the live buffer; copy it if you need a
  snapshot.
- **Assuming the WASM kernel is always worth enabling.** It is an opt-in
  accelerator with an identical-output JS fallback (see "WASM force kernel");
  for small graphs the JS tick already fits the frame budget, and the WASM win
  is bounded (~1.4–1.5× on the force phase).

## Performance notes (measured)

- `applyPositions` derives the instanced mesh's **bounding sphere inline** from
  the positions it already has, rather than calling
  `InstancedMesh.computeBoundingSphere()` (which re-reads every instance matrix —
  it measured at 60–78% of the whole method). Frustum culling stays correct
  because the sphere expands by each instance's true world radius
  (`nodeRadius × cbrt(val)`). Net 2.3–3.2× faster.
- `linkLines` sets `frustumCulled = false` (a line set spanning the whole graph
  is never meaningfully cullable); `nodeMesh` keeps culling **on**.

## WASM force kernel (opt-in)

`VectoForceLayout` ships an optional Rust/WASM force kernel
(`crates/vectojs-force-rs`, published as a co-located `vectojs_force.wasm` in
`@vectojs/graph3d` — **no `@vectojs/core` dependency**, `three` stays the only
peer). It accelerates the Barnes-Hut octree build + repulsion accumulation; the
f32 integration, springs, and centering stay in JS.

```ts
import { forceWasmUrl } from "@vectojs/graph3d/wasm";
await layout.enableWasmForce(forceWasmUrl); // streaming (browser): URL | Response
// or, from raw bytes (Node/tests, no fetch):
layout.enableWasmForceSync(bytes);
```

- `enableWasmForce(url | Response)` is async and fetches; `enableWasmForceSync(bytes)`
  compiles bytes directly and never fetches. Both return `false` on any failure
  (CSP, 404, corrupt module) and silently keep the identical-output JS Barnes-Hut.
- The kernel is **bit-for-bit identical** to the JS path (both accumulate in
  f64); the JS path is the permanent fallback and the differential oracle.
- It is not automatically faster — it only matters once the JS tick misses the
  frame budget (measured ~2000 nodes on a 240 Hz panel). The force-accumulate
  phase is 78–90% of the tick, so the ceiling is ~1.4–1.5×, not an order of
  magnitude.

## Verification

- Layout is deterministic: same input + same seed ⇒ same positions. Assert that
  rather than a screenshot.
- `step()` eventually returns `true`; a layout that never settles is a tuning bug
  (usually `velocityDecay` too high or `repulsion` fighting `centerStrength`).
- For frame-time claims use the real-browser harness (see the
  `hyprland-browser-bench` skill) and quote both engines — V8 and SpiderMonkey
  diverge noticeably on this workload.
