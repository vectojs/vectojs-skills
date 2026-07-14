# VectoJS core scene recipes

## Minimal accessible entity

```ts
import { Entity, type IRenderer, Scene } from "@vectojs/core";

class Dot extends Entity {
  constructor() {
    super();
    this.width = 48;
    this.height = 48;
    this.interactive = true;
    this.on("click", () => this.animate({ scaleX: 1.2, scaleY: 1.2 }, 120));
  }

  isPointInside(globalX: number, globalY: number): boolean {
    const local = this.worldToLocal(globalX, globalY);
    return !!local && Math.hypot(local.x - 24, local.y - 24) <= 24;
  }

  getA11yAttributes() {
    return { tag: "button" as const, role: "button", label: "Animated dot" };
  }

  render(renderer: IRenderer): void {
    renderer.beginPath();
    renderer.arc(24, 24, 24, 0, Math.PI * 2);
    renderer.fill("#22d3ee");
  }
}

const canvas = document.querySelector<HTMLCanvasElement>("canvas")!;
const scene = new Scene(canvas, { maxFPS: 60 });
scene.renderMode = "onDemand";
scene.add(new Dot().setPosition(80, 80));
scene.start();
```

## Host framework mounting pattern

```ts
const scene = new Scene(canvas, {
  maxFPS: 60,
  pointBackend: "canvas",
  particleBackend: "cpu",
});
scene.renderMode = "onDemand";

const resize = () =>
  scene.resize(container.clientWidth, container.clientHeight);
resize();
window.addEventListener("resize", resize);
scene.start();

return () => {
  window.removeEventListener("resize", resize);
  scene.destroy();
};
```

## Testing through semantics

```ts
await page.getByRole("button", { name: "Animated dot" }).click();
await page.getByRole("textbox", { name: "Project name" }).fill("Launch");
```

Prefer role-based tests over coordinate clicks unless testing hit-testing itself.

## Selectable code-like grid

```ts
import {
  Entity,
  prepareContentGrid,
  type ContentProjection,
  type IRenderer,
  type PreparedContentGrid,
} from "@vectojs/core";

class CodeSurface extends Entity {
  private grid: PreparedContentGrid | null = null;
  private gridKey = "";
  private fontRevision = 0;
  source = "A\t你👩‍💻\r\nabc مرحبا 123";
  font = "15px ui-monospace, monospace";
  cellWidth = 0;
  lineHeight = 24;
  baseline = 18;
  tabSize = 4;

  /** Measure through Canvas with the same browser-resolved font used to paint. */
  refreshFontMetrics(context: CanvasRenderingContext2D): void {
    context.font = this.font;
    const nextCellWidth = Math.max(1, context.measureText("M").width);
    this.cellWidth = nextCellWidth;
    this.fontRevision++;
    this.grid = null;
    this.scene?.markDirty();
  }

  private prepare(): PreparedContentGrid {
    if (this.cellWidth <= 0) {
      throw new Error("Call refreshFontMetrics() before preparing the grid");
    }
    const key = JSON.stringify([
      this.source,
      this.font,
      this.cellWidth,
      this.lineHeight,
      this.baseline,
      this.tabSize,
      this.fontRevision,
    ]);
    if (!this.grid || this.gridKey !== key) {
      this.grid = prepareContentGrid(this.source, {
        font: this.font,
        cellWidth: this.cellWidth,
        lineHeight: this.lineHeight,
        baseline: this.baseline,
        tabSize: this.tabSize,
      });
      this.gridKey = key;
    }
    return this.grid;
  }

  override getContentProjection(): ContentProjection {
    const grid = this.prepare();
    return { text: grid.source, selectable: true, ligatures: "none", grid };
  }

  override render(renderer: IRenderer): void {
    for (const [row, line] of this.prepare().lines.entries()) {
      for (const cell of line.cells) {
        const source = this.source.slice(cell.sourceStart, cell.sourceEnd);
        if (cell.advance <= 0 || source === " " || source === "\t") continue;
        renderer.fillText(
          cell.glyph,
          cell.x,
          row * this.lineHeight + this.baseline,
          this.font,
          "#e2e8f0",
        );
      }
    }
  }
}
```

Invalidate the cached grid when source, font, cell width, line height, baseline,
or tab size changes, then call `scene.markDirty()`. Await `document.fonts.ready`,
measure through the same browser Canvas font used by `render()`, and remeasure on
`document.fonts` `loadingdone`; a hard-coded width or monospace family name does
not survive Firefox font substitution reliably.

Verify real forward/reverse pointer drag, Shift extension, word/line selection,
Ctrl/Command+C, ZWJ and Lam-Alef caret boundaries, mixed bidi copy order, and no
root-origin Range fragment in Chromium and Firefox at fractional DPR/zoom.
Include rotation, `scaleX = -1`, non-uniform scale, and a Firefox case with
document fonts disabled or substituted. Assert every projected cell start and
width against the Canvas grid geometry, not only the copied string. Also require
`scene.getContentElement(id)?.textContent === source`, exercise a real
Ctrl/Command+F smoke test, then change both source and font metrics and prove the
grid revision rebuilds without stale carriers, calibration probes, or pending
frames. Do not replace these with programmatic `Range.selectNodeContents()`
checks.
