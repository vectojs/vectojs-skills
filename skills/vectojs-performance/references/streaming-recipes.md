# Streaming & real-time text recipes

Verified against core 1.32.7 / ui 2.15.1 / markdown 0.18.0. Full prose version:
https://vectojs.org/learn/streaming/

## Rule zero, the short version: use `Markdown.createStream()`

`@vectojs/markdown` ships the per-frame batching below as a supported writer.
Prefer it over hand-rolling the rAF loop — it also owns backpressure, pacing,
abort, and end-of-stream settlement, none of which the manual pattern gets right
by accident.

```ts
const stream = md.createStream({
  maxBufferedChars: 64 * 1024, // default; one write is backpressured past it
  incompleteMode: "optimistic", // default 'literal'
  signal: abortController.signal,
  onStable: (blocks) => bakeHighlightCache(blocks),
});

for await (const chunk of llmResponse) await stream.write(chunk);
await stream.close(); // resolves only once the document reflects every write
```

- `write()` resolves when the chunk enters the bounded buffer, so awaiting it is
  the backpressure signal. `bufferedChars` reads the current depth.
- `flush()` commits synchronously without closing. It never fires `onStable`.
- `close()` final-flushes, waits out the in-flight worker parse, then settles.
  This is why `await close()` means "the document reflects everything written" —
  `appendMarkdown()` alone gives no such guarantee, since the worker
  `postMessage` returns immediately.
- `abort(reason)` discards uncommitted text; `destroy()` also releases the
  controller's scheduler and listeners. Neither fires `onStable`.
- **One controller per instance.** A second `createStream()` while one is open
  throws.
- `pacing: { graphemesPerSecond: n }` is a fixed-rate typewriter reveal. Omit it
  for pure performance batching — the default is frame coalescing with no
  artificial delay.

`incompleteMode` decides how trailing unclosed syntax renders mid-stream.
`'literal'` (default, and what every prior release did) shows `**bo` as two
asterisks and `bo`. `'optimistic'` guesses the construct will close and formats
it immediately; the guess is display-only, never mutates token state, and is
unwound on `close()`, so both modes end at an identical document.

`onStable` fires exactly once, after `close()` has committed and settled, with a
snapshot of the top-level block entities. Calling `appendMarkdown()` or
`setContent()` from inside it throws synchronously; a throw from the callback
rejects the `close()` promise.

## Rule zero, the manual form: batch per frame, not per token

If you are streaming into `Text`/`RichText`, or into a `Markdown` you cannot
own the writer for, the same discipline applies by hand.

Every `append*` call pays a layout pass; layouts between two rendered frames
are invisible work. Buffer tokens, flush once per rAF. Self-regulating under
load (busier thread → bigger, rarer chunks) — better than a fixed debounce.

```ts
let pending = "";
let scheduled = false;
function pushToken(token: string) {
  pending += token;
  if (scheduled) return;
  scheduled = true;
  requestAnimationFrame(() => {
    scheduled = false;
    const chunk = pending;
    pending = "";
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

The lexer cost is the one to watch, and it is now measurable rather than
inferred. `@vectojs/devtools` 0.11.0 reports `lexerMs` and `sourceCharsLexed`
from `inspectMarkdownStream` / `formatMarkdownStream`; `sourceCharsLexed` grows
~O(n²) across a stream of n chunks. The reuse counters were renamed in the same
release because the old names implied the lexer was being skipped:
`tokensReused` → `tokensPrefixMatched`, `tokensRelexed` → `tokensReturned`,
`reuseRatio` → `tokenPrefixReuseRatio`. The old names are gone, not aliased.

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

| Symptom                           | Cause / probe                                                             |
| --------------------------------- | ------------------------------------------------------------------------- |
| Jank while streaming              | Appends ≫ frames → missing the rAF batch                                  |
| Jank grows with transcript length | One ever-growing entity → segment per message                             |
| Stall on long paragraphs          | No `\n` in stream → paragraph memo can't split                            |
| Scroll fights the user            | Unconditional `scrollToBottom()` → gate on `nearBottom` read pre-append   |
| CPU busy while stream idle        | `'always'` mode, or custom animation invisible to the throttle            |
| Producer outruns the renderer     | Not awaiting `write()` → the backpressure signal is the resolved promise  |
| Post-stream work sees stale boxes | Ran after `appendMarkdown()` or `flush()` instead of `onStable`/`close()` |
