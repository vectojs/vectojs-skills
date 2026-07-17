# Streaming & real-time text recipes

Verified against published core 1.9.2 / ui 1.9.5. Full prose version:
https://vectojs.org/learn/streaming/

## Rule zero: batch per frame, not per token

Every `append*` call pays a layout pass; layouts between two rendered frames
are invisible work. Buffer tokens, flush once per rAF. Self-regulating under
load (busier thread → bigger, rarer chunks) — better than a fixed debounce.

```ts
let pending = '';
let scheduled = false;
function pushToken(token: string) {
  pending += token;
  if (scheduled) return;
  scheduled = true;
  requestAnimationFrame(() => {
    scheduled = false;
    const chunk = pending;
    pending = '';
    markdown.appendMarkdown(chunk); // ONE layout for the frame's tokens
    transcript.scrollToBottom();
  });
}
```

## API costs (what actually happens per call)

- `Text.append(chunk)` — cold pass, but the engine's paragraph memo reuses
  every finished `\n`-terminated paragraph. One endless run-on line (no `\n`)
  defeats the memo → O(document) re-measure per flush. Don't strip newlines.
- `Markdown.appendMarkdown(chunk)` — re-lexes the WHOLE accumulated source
  (O(document), off-thread via embedded-blob Worker when `Worker` exists;
  sync fallback otherwise), then prefix-diffs tokens by raw source: finished
  block entities are reused by instance, a growing last paragraph updates its
  spans in place.
- `RichText.appendSpans(spans)` — appends; prior spans' measurements reused.
- `setText` / `setContent` with the full accumulated document — anti-pattern,
  rebuilds everything, reuses nothing.

## Bottom-follow (chat)

`scrollToBottom()` SNAPS (deliberately bypasses the scroll spring — retargeting
a spring many times/sec jitters). `scrollTo(y)` SPRINGS — position-derived
state read immediately after it sees the old position. Stickiness via public
API, read-append-scroll order inside one flush:

```ts
function nearBottom(sv: ScrollView, slack = 24): boolean {
  const maxScroll = Math.max(0, sv.content.height - sv.height);
  return -sv.content.y >= maxScroll - slack; // content.y = negative translation
}
const stick = nearBottom(transcript); // BEFORE append
markdown.appendMarkdown(chunk);
if (stick) transcript.scrollToBottom(); // AFTER
```

## Long transcripts: segment, then virtualize

Lex/append cost grows with document size — cap the live document:

1. One `Markdown` entity **per message**; stream only into the in-flight one.
   Finished messages never re-lex.
2. Put messages in a `VirtualList` so a 1000-message transcript costs what the
   viewport shows.

## Render mode

Streaming UIs: `renderMode: 'onDemand'`. Appends mark dirty; scroll containers
report `hasPendingAnimations()`; frames run exactly while content flows. Any
custom per-frame motion during the stream (typing indicator) must override
`hasPendingAnimations()` or use `animate()`/`springTo()` — the idle-throttle
contract applies as usual.

## Symptom map

| Symptom                            | Cause / probe                                                        |
| ---------------------------------- | --------------------------------------------------------------------- |
| Jank while streaming               | Appends ≫ frames → missing the rAF batch                              |
| Jank grows with transcript length  | One ever-growing entity → segment per message                         |
| Stall on long paragraphs           | No `\n` in stream → paragraph memo can't split                        |
| Scroll fights the user             | Unconditional `scrollToBottom()` → gate on `nearBottom` read pre-append |
| CPU busy while stream idle         | `'always'` mode, or custom animation invisible to the throttle        |
