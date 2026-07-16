# Architecture Viewer

Interactive D3.js visualization of OpenClaw architecture based on `docs/scan.json`.

## Local Development

```bash
cd .github/architecture-viewer
npm install
npm run dev
```

Open http://localhost:5173 to view the interactive graph.

## Features

- Force-directed graph layout with zoom/pan
- Color-coded nodes by type (entry, agent, model, tool, store, external)
- Tooltips with node details (kind, sub path, description)
- Real-time statistics panel
- Interactive node dragging

## How It Works

1. Fetches `docs/scan.json` from repo root
2. Parses nodes and edges from graph data
3. Renders using D3.js force simulation
4. Updates dynamically when scan.json changes

## Rebuilding for Production

```bash
npm run build
npm run preview
```

## Integration with CI/CD

The architecture diagrams are auto-regenerated via `.github/workflows/regenerate-architecture.yml` when `docs/scan.json` changes.