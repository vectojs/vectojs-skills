---
name: vectojs-styles
description: Use when styling VectoJS UI with @vectojs/styles — CSS-property-name style objects, var() token themes with setTheme switching, css() merging, font composition, per-axis padding, or migrating CSS/web styling habits onto the numeric Virtual Math Tree.
---

# VectoJS Styles

Use this skill to write VectoJS component styling that reads like CSS without
a parser, cascade, or selector. `@vectojs/styles` maps typed style objects
onto numeric entity fields; `var(--key)` token references resolve against a
flat theme and re-apply on `setTheme`.

## Core workflow

1. Confirm the installed `@vectojs/styles` version; the API below is 0.2.0+.
2. Define a theme once: `setTheme(tokens({ accent: '#2563eb', 'radius-md': 8 }))` — flat keys, no `--` prefix; `PRESET_THEMES` ships `light` (default) / `dark` / `github` / `dracula`.
3. Write styles with `style({...})` (typed identity) and merge variants with `css(base, override, ...)` — later sources win, `null`/`false` skipped.
4. Reference tokens in values: `backgroundColor: 'var(--accent)'` — styles containing `var()` are tracked and re-applied automatically when `setTheme(next)` runs, recolouring the scene.
5. Apply: `applyStyle(entity, style)` writes mapped fields and returns `{ applied }`; it marks the scene dirty once when anything was written.
6. Verify with `@vectojs/devtools` headless: `inspectEntity`/`pickInScene` read the same fields `applyStyle` wrote.

## Key mapping (CSS name → entity field)

| CSS key                                 | Field / behaviour                                                      |
| --------------------------------------- | ---------------------------------------------------------------------- |
| `x`/`y`/`width`/`height`                | same; bare number or `px` string                                       |
| `opacity`/`scaleX`/`scaleY`/`rotation`  | same; rotation in **radians**                                          |
| `backgroundColor`/`color`/`borderColor` | `bg`/`color`/`borderColor`; strings pass through                       |
| `borderRadius`                          | `radius`                                                               |
| `padding`                               | single value, or `{ x, y }` → `paddingX`/`paddingY`                    |
| `font`                                  | full shorthand string                                                  |
| `fontFamily`/`fontSize`/`fontWeight`    | composed into the entity's `font` shorthand, preserving other segments |
| `lineHeight`/`gap`                      | same                                                                   |
| `textAlign`                             | `'left' \| 'justify'` ONLY                                             |
| `display`                               | `'flex'` only — validates the entity is a container                    |
| `flexDirection`                         | `'row'`→`'horizontal'`, `'column'`→`'vertical'`                        |
| `alignItems`                            | `'flex-start'`→`'start'`, `'flex-end'`→`'end'`, `'center'`             |
| `flexWrap`                              | `'wrap'`→`true`, `'nowrap'`→`false`                                    |

## Rules of the road

- **Cross-component reuse**: keys whose field the entity lacks are skipped
  silently — one style object works on `Button`, `Text`, and `Stack`.
- **Loud failures**: layout keys on non-containers, unknown keys, unknown
  tokens, and invalid values (`'50%'`, `'8em'`, `textAlign: 'center'`,
  `alignItems: 'stretch'`) throw `TypeError` with the property name. A
  migration must not fail silently.
- **Values are px**: bare numbers or `px` strings only; `%`/`em`/`rem`
  rejected.
- **`setTheme` re-applies only `var()`-tracked styles**; literals are left
  alone. `setTheme` throws if a new theme drops a referenced token or a token
  value fails validation.
- **Button sizing is fixed at construction**: `padding: {x,y}` applied later
  is read by consumers of `paddingX`/`paddingY` (e.g. Card layouts), not by
  intrinsic sizing.
- **No strings, no cascade**: never parse CSS text, never implement
  selectors/pseudo-states/media queries — the numeric VMT is the single
  source of truth.

## Migration checklist (web → VectoJS)

1. Replace `#hex` literals with tokens (`var(--surface)` etc.) or keep them —
   literals are fine, they just don't theme-switch.
2. `display: flex` + `flexDirection/gap/alignItems` → the entity must be a
   `Stack`/`Flow` (VectoJS has no auto-container conversion).
3. `center`/`right` text-align has no backing field — re-layout with
   `Stack({ align: 'center' })` instead.
4. `transform: rotate(30deg)` → `rotation: Math.PI / 6` (radians).
5. Pseudo-states (`:hover`) → entity events (`entity.on('hover')`).

## Cross-references

Component fields and constructor sizing → **vectojs-core-runtime** ·
layout containers → **vectojs-responsive-layout** · theme-switching
performance → **vectojs-performance** · verifying applied fields →
**vectojs-devtools**.

Base directory for this skill: /mnt/data/Workspace/Projects/vectojs/.agents/skills/vectojs-styles
