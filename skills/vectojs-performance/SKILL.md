---
name: vectojs-performance
description: Use when diagnosing or optimizing VectoJS performance, frame drops, layout/text cost, high entity counts, compute-heavy workloads, WebGL/WebGPU backend choices, virtualization, memory leaks, or benchmark methodology.
---

# VectoJS Performance

Use this skill when VectoJS feels slow or when designing workloads that may exceed DOM or Canvas 2D limits.

## Diagnosis workflow

1. Separate render cost, layout/text cost, application compute, event/hit-test cost, and DOM semantic-sync cost.
2. Reproduce with a fixed workload and record entity count, text length, backend, viewport, DPR, hardware, and browser.
3. Check whether CPU compute dominates before changing renderer backends.
4. Reduce unnecessary work: on-demand rendering, viewport culling, virtualization, prepared text, and dirty-region discipline.
5. Choose GPU paths only for matching workloads: WebGL point batching for large points/rects, WebGPU particles for compute-driven simulations.
6. Verify with the same benchmark after each change.

Read `references/performance-checklist.md` for concrete probes and fixes.
For token streams / chat / log tails, read `references/streaming-recipes.md` —
the per-frame batching pattern there is the single highest-leverage streaming
fix and is NOT optional for LLM-speed streams.

## Decision matrix

| Symptom                                                                                                               | Likely area               | First fix                                                                                                                                                                                                              |
| --------------------------------------------------------------------------------------------------------------------- | ------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Idle page uses CPU                                                                                                    | render loop               | `scene.renderMode = 'onDemand'`, auto-throttle, avoid timers. A canvas scrolled fully **off-screen already auto-pauses** the rAF loop (IntersectionObserver) — don't hand-roll that.                                   |
| Resize or stream stalls                                                                                               | layout/text               | hot width/content APIs, incremental append, debounce app compute                                                                                                                                                       |
| Streaming jank (chat/logs)                                                                                            | append cadence            | batch tokens per rAF, one `Markdown` per message, `VirtualList` history — see `references/streaming-recipes.md`                                                                                                        |
| Many rows/items slow                                                                                                  | entity count              | `VirtualList`, `Table` `viewportHeight` virtualization, culling, aggregate decorative shapes                                                                                                                           |
| Pointer feels delayed                                                                                                 | hit-test/event            | spatial hash boundaries, fewer overlapping interactive nodes                                                                                                                                                           |
| 100k points slow                                                                                                      | renderer                  | WebGL point backend if draw cost dominates                                                                                                                                                                             |
| Thousands of repeated short text runs/frame (danmaku, chat/log tails, particle labels) at low FPS while GPU sits idle | render (fillText shaping) | `TextRasterCache` (core ≥ 1.12.0): rasterize each `(font,color,text)` run once, blit with `drawImage`. Swapping fillText↔drawImage that doesn't move FPS means draw-count/overdraw, not shaping — batch to WebGL/MSDF. |
| Particle simulation slow                                                                                              | compute                   | WebGPU only if compute is parallel and supported                                                                                                                                                                       |
| Memory grows after navigation                                                                                         | lifecycle                 | `scene.destroy()`, remove observers/timers, dispose adapters/export jobs                                                                                                                                               |
| Animation steps/stutters only when the page is otherwise idle                                                         | throttle visibility       | The entity animates from `update()` without overriding `hasPendingAnimations()` — the idle throttle can't see it. Use `setTransition`/`springTo`, or override it.                                                      |

## Already handled by the engine (don't re-solve)

Measured on real hardware in both Chrome and Firefox. Reach for these facts
before optimizing:

| Area                      | What the engine does                                                                                       |
| ------------------------- | ---------------------------------------------------------------------------------------------------------- |
| Off-screen canvas         | rAF loop **pauses** via `IntersectionObserver`, resumes on re-entry                                        |
| Frame delta               | `dt` clamped to 100ms (`MAX_FRAME_DT`) — no substepping needed on your side                                |
| `VirtualList` scroll math | Fenwick (binary-indexed) row heights: `prefix()`/`indexAt()` are O(log n), no per-frame scan               |
| `Table`                   | Row virtualization (measured 149×/190× on large grids)                                                     |
| `measureText`             | LRU keyed on **raw** text, so a cache hit skips Arabic shaping — 4.14µs → 0.34µs (~12×)                    |
| `SpatialHashGrid`         | Large AABBs bypass cell enumeration (it is O(area/cellSize²)); one 6400² box went 1.2ms → <100µs to insert |
| devtools audit            | Sibling-overlap is broad-phased, not O(k²) — 4000 rows 1280ms → 7.4ms (173×)                               |
| `Graph3D`                 | Bounding sphere derived inline in `applyPositions` instead of a second full pass (2.3–3.2×)                |
| Compute-entity collection | Cached per structure version — a scene with no `ComputeParticleEntity` no longer walks the tree each frame |

**WASM acceleration** is opt-in and invisible: `enableWasmTransforms` /
`enableWasmParticles` with `coreWasmUrl`. JS is the permanent fallback and stays
bit-identical, so enabling it is never a behavior change. Measured 2–4× on the
transform/AABB and particle kernels; it is *not* a fix for draw-count or
overdraw problems.

**Measured and deliberately NOT optimized** — don't "fix" these without new
evidence: the `Entity.scene` getter's parent-chain walk (0.14µs per read at depth
50), `Tabs` per-frame visibility scan (2µs/frame at 60 tabs), `MSDFFont.layout`
(already 8–15M chars/s; its cost is JS result-object allocation, which a WASM
kernel cannot remove), and the `LayoutWorker` (off-thread + 50ms debounced, so it
never touches frame time).

## Compute greater than render

When calculation cost exceeds drawing cost, do not optimize the renderer first. Move expensive calculations out of per-frame paths, cache prepared results, split work across frames, use typed arrays, or move simulation to a Worker/WebGPU path when the data shape fits.

## Verification

Use production-like builds and record exact commands. In the VectoJS monorepo:

```bash
bun run benchmark
bun run compare:dom
bun run compare
```

Treat demo entity counts as workload examples, not universal promises.

**Measure on a real GPU.** Headless Chromium rasterizes in software — its FPS
numbers are a hard floor, not a measurement. Quote numbers captured in-page on
real hardware (the demos' "Export report" button), and record DPR: headless
defaults to DPR 1 while most dev machines are HiDPI, which also hides
hit-testing offsets that only appear at `deviceScaleFactor: 2`.
