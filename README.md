# VectoJS Skills

Agent skills for building, reviewing, optimizing, and exporting VectoJS projects.

[![MIT](https://img.shields.io/badge/license-MIT-6366f1.svg)](./LICENSE)
[![skills.sh](https://skills.sh/b/vectojs/vectojs-skills)](https://skills.sh/vectojs/vectojs-skills)

This repository is a skills catalog for AI coding agents such as Codex, Claude Code, Cursor, GitHub Copilot, and other agents supported by the [Vercel Labs Skills CLI](https://github.com/vercel-labs/skills).

## Skills

| Skill                       | Use it for                                                                                                                                 |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `vectojs-paradigm`          | Read FIRST: replaces HTML/CSS instincts with scene-graph thinking and the state-space debugging ladder                                     |
| `vectojs-core-runtime`      | Core `Scene`/`Entity` architecture, semantic projection, lifecycle, and framework integration                                              |
| `vectojs-responsive-layout` | Adaptive canvas layouts, resize/zoom handling, `Stack`/`Flow`, scroll regions, and layout boundaries                                       |
| `vectojs-ui-animation`      | Polished `@vectojs/ui` components, forms, overlays, UX states, and animation/microinteraction patterns                                     |
| `vectojs-performance`       | Profiling, compute-vs-render tradeoffs, text/layout cost, large scenes, batching, and backend selection                                    |
| `vectojs-three`             | `@vectojs/three`, Three.js/WebXR panels, raycast input routing, texture sync, and disposal                                                 |
| `vectojs-video-exporter`    | Deterministic MP4 export, CLI/API usage, fixed-step scene contracts, Chromium/FFmpeg, and cancellation                                     |
| `vectojs-devtools`          | `@vectojs/devtools` VMT inspector: entity tree, click-to-pick, geometry readouts, headless model APIs                                      |
| `vectojs-graph-layout`      | `@vectojs/graph-layout` renderer-agnostic 2D Barnes-Hut physics, incremental updates, collision, pinning, and d3 migration                 |
| `vectojs-graph3d`           | `@vectojs/graph3d` force-directed graphs: Graph3D instancing, layout contract, Barnes-Hut vs d3, picking                                   |
| `vectojs-knowledge-graph`   | 2D node-link knowledge graphs: batch-painted layers, graph-layout physics, pan/zoom, hit-testing, dirty/onDemand, Canvas2D to WebGL/WebGPU |

## Install with `skills`

List available skills:

```bash
npx skills add vectojs/vectojs-skills --list
```

Install all skills for all detected agents:

```bash
npx skills add vectojs/vectojs-skills --all
```

Install selected skills for specific agents:

```bash
npx skills add vectojs/vectojs-skills \
  --skill vectojs-core-runtime \
  --skill vectojs-responsive-layout \
  --agent codex \
  --agent claude-code \
  --agent cursor \
  --agent github-copilot
```

Use one skill without installing it:

```bash
npx skills use vectojs/vectojs-skills --skill vectojs-video-exporter
```

The Skills CLI supports GitHub shorthand (`owner/repo`), full GitHub URLs, direct skill paths, local paths, and agent-specific installs. See the upstream CLI README for current options and supported agents: <https://github.com/vercel-labs/skills>.

## Local development

Each skill is a standalone folder under `skills/<name>/` with:

- `SKILL.md` — required frontmatter and instructions.
- `references/` — optional detailed recipes loaded only when needed.
- `agents/openai.yaml` — UI metadata for OpenAI/Codex surfaces.

Validate formatting:

```bash
prettier --check README.md "skills/**/*.md" "skills/**/agents/openai.yaml"
```

Check discovery through the Skills CLI:

```bash
skills add . --list
```

## License

[MIT](./LICENSE) © 2026 VectoJS
