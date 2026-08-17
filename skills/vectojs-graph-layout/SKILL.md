---
name: vectojs-graph-layout
description: Use when building, migrating, tuning, or profiling a renderer-agnostic 2D force-directed graph with @vectojs/graph-layout - ForceLayout2D, Barnes-Hut repulsion and cutoff, collision and force accessors, incremental node/link mutations, ID mappings, axis pins, reheating, and d3-force migration.
---

# VectoJS Graph Layout

Use `@vectojs/graph-layout@0.2.0` for dependency-free 2D graph physics. It owns
no renderer, canvas, scene, or timer: the host supplies graph data, calls
`step()`, and reads interleaved XY coordinates.

For a VectoJS 2D graph renderer, also read `vectojs-knowledge-graph`. For
instanced Three.js rendering and 3D physics, read `vectojs-graph3d` instead.

## Core contract

```ts
import { ForceLayout2D, type GraphData } from "@vectojs/graph-layout";

const graph: GraphData = {
  nodes: [
    { id: "a", radius: 8 },
    { id: "b", radius: 12 },
  ],
  links: [{ source: "a", target: "b", distance: 40 }],
};

const layout = new ForceLayout2D({
  seed: 7,
  repulsion: (node) => (node.id === "a" ? 180 : 240),
  collisionRadius: (node) => Number(node.radius),
  linkDistance: (link) => Number(link.distance),
  linkStrength: 0.3,
});

layout.setGraph(graph);

function frame(): void {
  const active = layout.step();
  draw(layout.positions); // [x0, y0, x1, y1, ...], in node order
  if (active) requestAnimationFrame(frame);
}

requestAnimationFrame(frame);
```

`step(iterations?)` returns **true while active** and `false` once cooled. This
is the opposite of a "settled" return value. It is synchronous, advances at
most 10,000 normalized iterations, and owns no scheduling.

`positions` is a live `Float32Array` view. Its identity is stable across
`step()` calls, but `setGraph()`, `appendGraph()`, and `removeNodes()` may
replace the view or backing buffer. Read `layout.positions` again after those
operations; copy it only when a historical snapshot is required. Use
`getNodeIndex(id)` and `getNodeId(index)` for current mappings, or
`getNodeIds()` for a position-order snapshot. Removal compacts survivors;
existing indices remain stable across append-only and link-only updates.

Call `dispose()` when finished. Disposal is idempotent; later API use throws.

## Forces and tuning

- Repulsion uses a true 2D Barnes-Hut quadtree. `theta` defaults to `0.9`;
  larger values trade accuracy for speed, while `0` requests exact O(N^2)
  repulsion.
- `repulsionDistanceMax` limits many-body work to nearby nodes. It defaults to
  `Infinity`; `0` disables repulsion. Tune it from graph-scale behavior and
  headed-browser tick measurements, not as an assumed optimization.
- `repulsion` and `collisionRadius` accept a number or `(node, index) => number`.
  `linkDistance` and `linkStrength` accept a number or
  `(link, globalIndex) => number`. Accessors run when items enter the layout,
  not on every tick.
- Collision is disabled by the default radius `0`. Set `collisionRadius` to the
  rendered node radius, plus desired padding; tune `collisionStrength` only
  after measuring overlap and tick cost.
- Defaults are `repulsion: 300`, `collisionRadius: 0`, `collisionStrength: 1`,
  `linkDistance: 30`, `linkStrength: 0.3`, `centerStrength: 0.02`,
  `velocityDecay: 0.6`, `theta: 0.9`, `repulsionDistanceMax: Infinity`,
  `alphaDecay: 0.0228`, `alphaMin: 0.001`, and `seed: 1`.
- The seed gives deterministic initial placement for identical ordered input.
  Preserve node order and seed when testing replay or migration behavior.

## Incremental graph updates

Use `setGraph()` for replacement, `appendGraph()` for pages or expansion,
`removeNodes(ids)` for node deletion, `removeLinks(items)` for edge deletion,
and `updateLinks(links)` to re-resolve distance/strength accessors. Node append
and removal preserve surviving positions, velocities, and pins, then reheat
automatically. Node removal also drops incident links and compacts survivors in
their previous relative order. Link-only mutation never changes node state or
indices.

`appendGraph()` is replay-safe:

- Existing and repeated node IDs are ignored, so replaying a node page is
  idempotent.
- A link identity is its directed `(source, target)` pair plus optional `id`.
  Replays are ignored; reverse links are distinct; parallel links need distinct
  IDs.
- Link accessor indices are global and stable across pages.
- Links with unknown endpoints and self-links are ignored. Send a page's nodes
  and links together, or append links again after their endpoints exist.

`removeLinks()` accepts full links matched by directed endpoints plus optional
ID, or bare IDs that remove all identified links carrying that ID. It is
idempotent and preserves survivor order and cached accessor values.
`updateLinks()` validates the whole batch before mutation, ignores unmatched
identities, and re-runs link accessors for matches. Endpoints define identity,
so reroute with remove plus append rather than update.

Validation is intentionally asymmetric. `setGraph()` throws on a malformed
node ID or duplicate node ID without replacing the current graph.
`appendGraph()` skips malformed, existing, and repeated nodes. Invalid links
are ignored. Non-finite positions, pins, options, and accessor results are
clamped or replaced with safe defaults; validate application data separately
when silent omission would hide a backend defect.

## Pinning and host scheduling

`setNodePin(index, { x?, y? })` pins supplied axes, immediately updates those
live coordinates, and clears their velocity. `clearNodePin(index, { x?, y? })`
releases selected axes; omit the axes object to release both. `pinNode()` and
`unpinNode()` remain both-axis conveniences. Invalid indices are no-ops.
Initial finite `fx` and `fy` values can independently pin one axis.

Pinning does not itself raise alpha. Call `reheat()` after a pin or unpin;
`reheat(alpha = 0.3)` never lowers the current alpha. **Reheat once at drag
start, never on every pointer move** — reheating per move keeps alpha pinned
near max, so the dragged node's neighbors keep overshooting their springs and
the whole neighborhood keeps vibrating for several seconds after release (alpha
decays at ~`alphaDecay` per tick ≈ 5 s at 60 fps), which reads as jitter and
text-label ghosting. Update the pin position each move; `reheat()` only for
topology changes, explicit wake-ups, and drag start. If a gentle follow during
the drag is wanted, raise `velocityDecay` (damping) instead of reheating. In an
on-demand
VectoJS scene whose `update()` drives physics, call `scene.markDirty()` only
while `step()` returns true; marking dirty again from every cooled update creates
an infinite render loop. If an external scheduler drives physics, render the
final false-returning mutation once, then stop invoking the physics callback so
the scene can sleep.

## Migrating from d3-force

- Stop d3's internal timer. Replace `simulation.nodes()`, `force("link")`, and
  `simulation.tick()` with `setGraph()`, primitive-ID links, and host-controlled
  `step()`.
- Convert negative d3 charge strength to positive `repulsion` magnitude.
  Map link distance/strength and collision radius accessors directly.
- d3's `velocityDecay` is velocity loss; this package's value is retention.
  Start with `1 - d3VelocityDecay`, then retune from measurements.
- Map d3 `fx`/`fy` data to initial pins, or use node indices with
  `setNodePin()`/`clearNodePin()` during drag. Reheat explicitly instead of setting
  d3 alpha targets.
- Do not expect exact trajectories. Centering and integration details differ;
  test invariants such as finite positions, pins, separation, determinism, and
  eventual cooling rather than coordinate parity.

## Complexity and measurement

For N nodes and M links, typical sparse-graph tick cost is O(N log N + M) for
Barnes-Hut repulsion, springs, and quadtree collision traversal. Collision also
depends on the number of nearby pairs; pathological overlap can approach
O(N^2). Topology mutation is amortized by geometric typed-array growth;
`removeNodes()` is O(N + M). `removeLinks()` is O(M + R) for full-link
requests, or O(M + RM) in the worst case for R bare IDs; `updateLinks()` is
O(M + U) for U updates. Space is O(N + M).

Measure in real headed Chrome and Firefox with production-like graph shapes,
degree distributions, collision radii, and page sizes. Report per-tick median
and tail latency, maximum synchronous step time, topology mutation time, first
post-append tick, total settling time/ticks, long tasks, and memory deltas.
Warm each arm, rotate comparison order, isolate mutations from payload creation,
and compare equivalent dimensions and force models. Do not use FPS as the
physics metric.

There is no WASM backend in `@vectojs/graph-layout@0.2.0`. Keep WASM deferred
until headed Chrome and Firefox evidence shows this JS layout is the bottleneck
and a representative WASM prototype wins end to end, including boundary and
memory costs. Existing cross-dimensional comparisons against 3D layouts are
directional implementation evidence, not a 2D d3 baseline or evidence that
WASM would help.
