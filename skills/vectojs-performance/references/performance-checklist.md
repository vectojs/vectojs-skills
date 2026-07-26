# VectoJS performance checklist

## Measurement notes

Record:

- browser and version;
- CPU/GPU and power mode;
- viewport CSS size and DPR;
- entity count and visible count;
- renderer/backend choices;
- text length, font path, and wrapping width;
- whether semantic projection is enabled and how often it syncs;
- the display's refresh rate, and whether the measurement was vsync-capped;
- whether GPU timings used `gl.finish()` (without it you measured queue
  insertion, not GPU work);
- the runtime: browser measurements only for quoted figures, never Node/Bun.

Report frame-time p50/p99 and the share of frames inside budget. Do not report
FPS: it saturates at the vsync cap and hides both regressions and wins.

## Fast probes

```ts
scene.renderMode = "onDemand";
scene.a11ySyncInterval = 100;
scene.markDirty();
```

If this lowers idle CPU but not interaction latency, the issue is not the idle
render loop.

## Layout/text

- Use `Text.setMaxWidth()` for reflow rather than replacing entities.
- Use rich/markdown append APIs for streams, batched per animation frame
  (`streaming-recipes.md` has the verified pattern).
- Cache expensive measurements and segmentation.
- `appendMarkdown` re-lexes the whole accumulated source per call (off-thread
  when `Worker` exists) — segment long transcripts into one `Markdown` entity
  per message so the live document stays small.
- When the same short strings are drawn thousands of times per frame
  (danmaku/barrage, chat/log tails, particle labels), `ctx.fillText` shaping +
  color-parse dominates and starves the GPU. Use `TextRasterCache` (core ≥
  1.12.0): rasterize each distinct `(font, color, text)` run once, then blit it
  with `drawImage` at the fillText baseline (`x - offsetX`, `baselineY -
  offsetY`). Bounded repeated content → ~100% hit rate; unbounded content is
  capped by `maxEntries`. Only helps _reused_ runs — draw-once text is pure
  overhead. Diagnostic: time the shaping phase directly; if swapping
  `fillText`↔`drawImage` doesn't move it, the wall is draw-count/overdraw (batch
  to WebGL/MSDF), not shaping. FPS is useless for this call — vsync-capped, it
  stays put whichever bottleneck is real.

## Large data

- Use `VirtualList`/`TreeView` for long collections.
- Render only visible rows and a small overscan.
- Aggregate static decorations into fewer entities.
- Prefer typed arrays for large numeric data.

## GPU path fit

- WebGL point batching helps when the bottleneck is many similar point/rect
  draws. `flush()` already issues at most one draw call per primitive type, so
  the scaling limit is uploaded bytes, not draw-call count; quad batches are
  indexed (4 verts + shared static 32-bit index buffer) since core 1.16.2.
- Crossover measured on an RTX 4060 Laptop: below ~35-50k quads/frame the JS
  vertex fill costs more than the GPU submit; above it the submit dominates and
  the lever becomes drawing less (culling, virtualization), not tuning the fill.
- WebGPU compute helps when simulation is parallel and large enough to pay setup
  costs.
- Neither helps much if app-side data preparation, text layout, or semantic sync
  dominates.
- Backing-store cost scales with `logical size × dpr²`, not linearly — a
  full-screen `pointBackend: 'webgl'` scene that's smooth at DPR 1 (most dev
  laptops) can jank badly on a DPR-3 display (measured: 116ms max-frame at DPR 3
  vs. inside-budget frames at DPR 1 for a 1200-particle full-screen field — the
  DPR-1 side read "60fps", which is the vsync cap, not headroom). Pass `new
  Scene(canvas, { maxDPR: 2 })` (>= `@vectojs/core@1.10.0`) instead of
  monkey-patching `window.devicePixelRatio` — it's re-applied correctly on every
  `resize()`, which a one-time patch is not. `maxDPR: 2` is retina-crisp; only
  go lower if 2 still isn't enough headroom.

## Leak checks

- Navigate away and force GC in dev tools.
- Confirm `scene.destroy()` runs.
- Confirm Three.js adapters call `adapter.dispose()`.
- Confirm video exports release Chromium, Vite, FFmpeg, progress output, and
  staged files on success, error, and abort.
