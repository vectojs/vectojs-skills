# Cross-environment consistency (OS / browser / zoom / DPR)

Distilled from https://vectojs.org/learn/cross-environment/ — read that page
for the full rationale. Verified against core 1.9.2 / ui 1.9.5.

## What the engine already guarantees

- All coordinates are logical CSS px; the renderer sizes the backing store to
  `logical × DPR` and every `scene.resize()` re-reads the current DPR.
  Rendering, hit-testing, and layout share one coordinate space at any density
  including fractional DPR (Windows 125/150 %).
- Text layout is self-measured (`measureText` with the exact font string), so
  layout and pixels always agree WITH EACH OTHER on any machine. Absolute
  geometry (wrap points, widths) still differs per OS font.

## What the application must do

1. **Size ownership.** Fullscreen scenes recalibrate automatically on window
   resize (zoom fires it). Embedded scenes (`disableWindowResize: true`) must
   bridge their container:

   ```ts
   const ro = new ResizeObserver(([e]) =>
     scene.resize(e.contentRect.width, e.contentRect.height),
   );
   ro.observe(container); // disconnect alongside scene.destroy()
   ```

   `scene.resize()` is also the **selection recalibration hook**: Firefox
   computes native Range selection metrics from state that zoom/container
   changes invalidate. Canvas looks fine but selection drifts after zoom in
   Firefox ⇒ a missing `resize()` call, first suspect.

2. **Fonts.** Construct `Text`/`RichText`/`Markdown` only after
   `await document.fonts.ready`, or measurement uses the fallback font while a
   later repaint draws the loaded one — the ONE way layout and pixels can
   disagree. Lazy fonts: re-run `setText`/`setMaxWidth` from
   `document.fonts.onloadingdone`. Never hard-code text-derived pixel
   expectations in tests unless CI installs the exact font (upstream installs
   Noto); prefer relational assertions — `auditScene(scene)` automates them.

3. **Selection alignment contracts.** Selectable text projects the logical
   source with geometry from the same layout the painter uses; it breaks only
   when (a) the scene wasn't told about size/zoom, (b) fonts raced, or
   (c) a custom component paints text without projecting through the shared
   prepared layout (`prepareContentGrid` / `LayoutEngine.prepare`) — never two
   independent measurements for paint vs projection.

## Test matrix (the minimum that catches the real bug classes)

- DPR **1 and 2** (`deviceScaleFactor` per context). Headless defaults to 1;
  most real machines are 2. An offset proportional to distance-from-origin ⇒
  suspect DPR.
- **Chrome and Firefox** for anything involving native selection/Range.
- One **non-default zoom** level (125 %).
- OS **reduced-motion on** (engine caps FPS by default — don't fight it).
- Numeric gates over screenshots: `auditScene` clean + `captureSnapshot`/
  `diffSnapshots` on key interactions.
