#!/usr/bin/env bash
# Convert Foglamp scan.json to SVG using Graphviz

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCAN_JSON="$REPO_ROOT/docs/scan.json"
OUTPUT_SVG="$REPO_ROOT/docs/architecture.svg"

if [ ! -f "$SCAN_JSON" ]; then
  echo "Error: scan.json not found at $SCAN_JSON"
  exit 1
fi

# Check for mmdc (Mermaid CLI) or fall back to Graphviz
if command -v mmdc &> /dev/null; then
  echo "Using mmdc (Mermaid CLI) to render SVG..."
  temp_mmd=$(mktemp)
  bash "$SCRIPT_DIR/scan-to-mermaid.sh" | sed 's/```mermaid//' | sed 's/```//' > "$temp_mmd"
  mmdc -i "$temp_mmd" -o "$OUTPUT_SVG" -t default -b transparent
  rm "$temp_mmd"
elif command -v dot &> /dev/null; then
  echo "Using Graphviz (dot) to render SVG..."

  # Generate Graphviz DOT format
  cat <<'EOF' > /tmp/temp.dot
digraph OpenClaw {
  rankdir=TB;
  splines=ortho;
  nodesep=0.8;
  ranksep=0.6;
  node [fontname="Arial", fontsize=12, shape=box, style="rounded,filled", penwidth=1.5];
  edge [fontname="Arial", fontsize=10];

  # Entry points (blue)
  cli [label="CLI Entry", fillcolor="#e1f5fe", color="#01579b"];
  gateway [label="Gateway", fillcolor="#e1f5fe", color="#01579b"];
  channels [label="Channel Router", fillcolor="#e1f5fe", color="#01579b"];

  # Cron (orange)
  cron [label="Cron Scheduler", fillcolor="#fff3e0", color="#e65100"];

  # Agents (purple)
  agent_loop [label="Agent Loop", fillcolor="#f3e5f5", color="#4a148c"];
  auto_reply [label="Auto-Reply", fillcolor="#f3e5f5", color="#4a148c"];
  coding_agent [label="Coding Agent", fillcolor="#f3e5f5", color="#4a148c"];

  # Models (green)
  claude [label="Claude", fillcolor="#e8f5e9", color="#1b5e20"];
  gpt [label="GPT", fillcolor="#e8f5e9", color="#1b5e20"];
  gemini [label="Gemini", fillcolor="#e8f5e9", color="#1b5e20"];
  deepseek [label="DeepSeek", fillcolor="#e8f5e9", color="#1b5e20"];
  openrouter [label="OpenRouter", fillcolor="#e8f5e9", color="#1b5e20"];

  # Tools (yellow)
  web_search [label="Web Search", fillcolor="#fff8e1", color="#f57f17"];
  memory [label="Memory", fillcolor="#fff8e1", color="#f57f17"];
  terminal [label="Terminal", fillcolor="#fff8e1", color="#f57f17"];
  browser [label="Browser", fillcolor="#fff8e1", color="#f57f17"];
  image_gen [label="Image Gen", fillcolor="#fff8e1", color="#f57f17"];
  vision [label="Vision", fillcolor="#fff8e1", color="#f57f17"];
  voice [label="Voice/TTS", fillcolor="#fff8e1", color="#f57f17"];

  # Store (red)
  sessions [label="Sessions", fillcolor="#fce4ec", color="#880e4f"];

  # External (gray)
  telegram [label="Telegram", fillcolor="#f5f5f5", color="#424242"];
  discord [label="Discord", fillcolor="#f5f5f5", color="#424242"];
  slack [label="Slack", fillcolor="#f5f5f5", color="#424242"];
  whatsapp [label="WhatsApp", fillcolor="#f5f5f5", color="#424242"];

  # Edges
  cli -> agent_loop [label="starts"];
  gateway -> agent_loop [label="routes"];
  channels -> gateway [label="delivers"];
  cron -> auto_reply [label="triggers"];
  agent_loop -> auto_reply [label="feeds"];
  agent_loop -> claude [label="calls"];
  agent_loop -> gpt [label="calls"];
  agent_loop -> gemini [label="calls"];
  agent_loop -> deepseek [label="calls"];
  agent_loop -> openrouter [label="routes"];
  auto_reply -> claude [label="uses"];
  coding_agent -> gpt [label="uses"];
  agent_loop -> web_search [label="queries"];
  agent_loop -> memory [label="reads/writes"];
  agent_loop -> terminal [label="executes"];
  agent_loop -> browser [label="drives"];
  agent_loop -> image_gen [label="generates"];
  agent_loop -> vision [label="analyzes"];
  agent_loop -> voice [label="speaks"];
  coding_agent -> terminal [label="runs"];
  coding_agent -> memory [label="stores"];
  auto_reply -> telegram [label="sends"];
  auto_reply -> discord [label="sends"];
  auto_reply -> slack [label="sends"];
  auto_reply -> whatsapp [label="sends"];
  agent_loop -> sessions [label="persists"];
  web_search -> sessions [label="caches"];
  memory -> sessions [label="syncs"];
  coding_agent -> sessions [label="logs"];
  image_gen -> sessions [label="stores"];
}
EOF

  dot -Tsvg /tmp/temp.dot -o "$OUTPUT_SVG"
  rm /tmp/temp.dot
else
  echo "Error: Neither mmdc nor dot found. Install Mermaid CLI or Graphviz."
  echo "  - Mermaid CLI: npm install -g @mermaid-js/mermaid-cli"
  echo "  - Graphviz: apt-get install graphviz"
  exit 1
fi

echo "Generated: $OUTPUT_SVG"