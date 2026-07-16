# VectoJS UI and animation recipes

## Lightweight single-purpose imports

On `@vectojs/ui@1.7.1+`, focused consumers can avoid loading the rich-content
graph:

```ts
import { Input, type InputOptions } from "@vectojs/ui/input";
import { Text } from "@vectojs/ui/text";
import { measureText, wrapLines } from "@vectojs/ui/measure";
import { ContextMenu } from "@vectojs/ui/context-menu"; // UI 1.9.2+
```

Keep the root `@vectojs/ui` import when a surface composes several components,
as the form example below does.

## Canvas-native context menu

Core routes secondary input as an ordinary VectoJS pointer event. Keep the
command surface in the Scene overlay root and suppress the browser-owned menu
at the application boundary when needed:

```ts
import { ContextMenu } from "@vectojs/ui/context-menu";

const menu = new ContextMenu({
  items: [{ label: "Delete", shortcut: "Delete", onClick: deleteSelection }],
});
scene.overlayRoot.add(menu);

target.on("pointerdown", (event) => {
  const pointer = event.nativeEvent as PointerEvent | undefined;
  if (
    pointer?.button !== 2 ||
    event.sceneX === undefined ||
    event.sceneY === undefined
  )
    return;
  menu.showAtPoint(event.sceneX, event.sceneY);
});
```

Do not register a VectoJS `contextmenu` listener or read `globalX/globalY`; those
are not Core APIs. Use one capture listener at the host boundary only to prevent
the browser's native menu, not to implement the editor command behavior.

## Accessible form card

```ts
import { Scene } from "@vectojs/core";
import { Button, Card, Input, Slider, Stack, Text, Toggle } from "@vectojs/ui";

const scene = new Scene(canvas);
scene.renderMode = "onDemand";

const state = { name: "", quality: 72, enabled: true };
const form = new Stack({ direction: "vertical", gap: 14 });
form.setPosition(24, 24);
form.add(new Text("Export settings", { font: "700 22px Inter" }));
form.add(
  new Input({
    width: 300,
    placeholder: "Project name",
    onChange: (v) => (state.name = v),
  }),
);
form.add(new Toggle({ checked: state.enabled, label: "Enabled" }));
form.add(new Slider({ min: 0, max: 100, value: state.quality, width: 300 }));
form.add(new Button("Export", { onClick: () => console.log(state) }));

const card = new Card({
  width: 360,
  height: 310,
  padding: 24,
  label: "Export settings",
});
card.add(form);
scene.add(card.setPosition(40, 40));
scene.start();
```

## Role-based Playwright check

```ts
await page.getByRole("textbox", { name: "Project name" }).fill("Launch");
await page.getByRole("switch", { name: "Enabled" }).click();
await page.getByRole("button", { name: "Export" }).click();
```

## Animation choices

- `entity.animate({ opacity: 0 }, 120)` is fine for simple one-off tweens.
- `setTransition(...)` is better for declarative properties that retarget often.
- `animateTo(...)` / `springTo(...)` are better when code must await completion.
- For reduced motion, rely on VectoJS reduced-motion behavior and avoid custom timers that force movement.

## Streaming content

For chat/LLM output, append incrementally:

```ts
markdown.appendMarkdown(delta);
markdown.setMaxWidth(contentWidth);
scrollView.scrollToBottom();
scene.markDirty();
```

Avoid `setContent(fullTranscript)` on every token unless the document is tiny.
