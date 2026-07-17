# VectoJS performance checklist

## Measurement notes

Record:

- browser and version;
- CPU/GPU and power mode;
- viewport CSS size and DPR;
- entity count and visible count;
- renderer/backend choices;
- text length, font path, and wrapping width;
- whether semantic projection is enabled and how often it syncs.

## Fast probes

```ts
scene.renderMode = 'onDemand';
scene.a11ySyncInterval = 100;
scene.markDirty();
```

If this lowers idle CPU but not interaction latency, the issue is not the idle render loop.

## Layout/text

- Use `Text.setMaxWidth()` for reflow rather than replacing entities.
- Use rich/markdown append APIs for streams, batched per animation frame
  (`streaming-recipes.md` has the verified pattern).
- Cache expensive measurements and segmentation.
- `appendMarkdown` re-lexes the whole accumulated source per call (off-thread
  when `Worker` exists) — segment long transcripts into one `Markdown` entity
  per message so the live document stays small.

## Large data

- Use `VirtualList`/`TreeView` for long collections.
- Render only visible rows and a small overscan.
- Aggregate static decorations into fewer entities.
- Prefer typed arrays for large numeric data.

## GPU path fit

- WebGL point batching helps when the bottleneck is many similar point/rect draws.
- WebGPU compute helps when simulation is parallel and large enough to pay setup costs.
- Neither helps much if app-side data preparation, text layout, or semantic sync dominates.

## Leak checks

- Navigate away and force GC in dev tools.
- Confirm `scene.destroy()` runs.
- Confirm Three.js adapters call `adapter.dispose()`.
- Confirm video exports release Chromium, Vite, FFmpeg, progress output, and staged files on success, error, and abort.
