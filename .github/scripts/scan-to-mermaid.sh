#!/usr/bin/env bash
# Convert Foglamp scan.json to Mermaid diagram

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCAN_JSON="$REPO_ROOT/.foglamp/scan.json"
OUTPUT_MD="$REPO_ROOT/docs/architecture.md"

if [ ! -f "$SCAN_JSON" ]; then
  echo "Error: scan.json not found at $SCAN_JSON"
  exit 1
fi

# Parse JSON and generate Mermaid
# Use jq to extract nodes and edges
echo '# Architecture Diagram' > "$OUTPUT_MD"
echo '' >> "$OUTPUT_MD"
echo '*This diagram is auto-generated from `.foglamp/scan.json`. Run `node scripts/generate-architecture.mjs` to regenerate.*' >> "$OUTPUT_MD"
echo '' >> "$OUTPUT_MD"
echo '```mermaid' >> "$OUTPUT_MD"
echo 'graph TD' >> "$OUTPUT_MD"
echo '' >> "$OUTPUT_MD"
echo '  %% Node styles by kind' >> "$OUTPUT_MD"
echo '  classDef entry fill:#e1f5fe,stroke:#01579b,stroke-width:2px;' >> "$OUTPUT_MD"
echo '  classDef cron fill:#fff3e0,stroke:#e65100,stroke-width:2px;' >> "$OUTPUT_MD"
echo '  classDef agent fill:#f3e5f5,stroke:#4a148c,stroke-width:2px;' >> "$OUTPUT_MD"
echo '  classDef model fill:#e8f5e9,stroke:#1b5e20,stroke-width:2px;' >> "$OUTPUT_MD"
echo '  classDef tool fill:#fff8e1,stroke:#f57f17,stroke-width:2px;' >> "$OUTPUT_MD"
echo '  classDef store fill:#fce4ec,stroke:#880e4f,stroke-width:2px;' >> "$OUTPUT_MD"
echo '  classDef external fill:#f5f5f5,stroke:#424242,stroke-width:2px;' >> "$OUTPUT_MD"
echo '' >> "$OUTPUT_MD"

# Extract nodes
jq -r '.graph.nodes[] |
  "  \(.id)[\"\(.label)\"]\n    %% \(.kind): \(.sub // .detail // "N/A")"' "$SCAN_JSON" >> "$OUTPUT_MD"

echo '' >> "$OUTPUT_MD"

# Extract edges
jq -r '.graph.edges[] |
  "  \(.from) -->|\"\(.label)\"| \(.to)"' "$SCAN_JSON" >> "$OUTPUT_MD"

echo '' >> "$OUTPUT_MD"

# Apply styles to nodes by kind
echo '  %% Apply styles' >> "$OUTPUT_MD"
jq -r '.graph.nodes[] | "  class \(.id) \(.kind)"' "$SCAN_JSON" | sort -u >> "$OUTPUT_MD"

echo '```' >> "$OUTPUT_MD"
echo '' >> "$OUTPUT_MD"

# Add stats section
echo '## Stats' >> "$OUTPUT_MD"
echo '' >> "$OUTPUT_MD"
jq -r '"- **Agents**: \(.stats.agents)\n- **Models**: \(.stats.models)\n- **Tools**: \(.stats.tools)\n- **Integrations**: \(.stats.integrations)"' "$SCAN_JSON" >> "$OUTPUT_MD"
echo '' >> "$OUTPUT_MD"

# Add top models
echo '## Top Models' >> "$OUTPUT_MD"
echo '' >> "$OUTPUT_MD"
jq -r '.topModels[] | "- **\(.label)** (\(.domain))"' "$SCAN_JSON" >> "$OUTPUT_MD"
echo '' >> "$OUTPUT_MD"

# Add top tools
echo '## Top Tools' >> "$OUTPUT_MD"
echo '' >> "$OUTPUT_MD"
jq -r '.topTools[] |
  if .domain then "- **\(.label)** (\(.domain))"
  else "- **\(.label)**"
  end' "$SCAN_JSON" >> "$OUTPUT_MD"
echo '' >> "$OUTPUT_MD"

# Add top integrations
echo '## Top Integrations' >> "$OUTPUT_MD"
echo '' >> "$OUTPUT_MD"
jq -r '.topIntegrations[] | "- **\(.label)** (\(.domain))"' "$SCAN_JSON" >> "$OUTPUT_MD"
echo '' >> "$OUTPUT_MD"

echo "Generated: $OUTPUT_MD"
echo "To regenerate, run: bash .github/scripts/scan-to-mermaid.sh"