#!/bin/bash
# Synthetic + Zed Dynamic Setup Script
# Queries /v1/models endpoint, discovers all hf: models, updates Zed config
# Usage: chmod +x setup_synthetic_dynamic.sh && ./setup_synthetic_dynamic.sh

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Synthetic + Zed Dynamic Setup${NC}"
echo -e "${BLUE}  Auto-discovers live models from /v1/models${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo

# 1. Check dependencies
echo -e "${YELLOW}[1/5]${NC} Checking dependencies..."
for cmd in curl jq; do
    if ! command -v "$cmd" &> /dev/null; then
        echo -e "${RED}✗${NC} $cmd not found"
        if [ "$cmd" = "jq" ]; then
            echo "Install: sudo apt update && sudo apt install jq -y"
        fi
        exit 1
    fi
done
echo -e "${GREEN}✓${NC} curl and jq found"

# 2. Get API key
echo
echo -e "${YELLOW}[2/5]${NC} API Key Configuration"
if [ -n "${SYNTHETIC_API_KEY:-}" ]; then
    read -p "Use existing SYNTHETIC_API_KEY? (Y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]] || [ -z "$REPLY" ]; then
        API_KEY="$SYNTHETIC_API_KEY"
    else
        read -s -p "Enter Synthetic API key: " API_KEY
        echo
    fi
else
    read -s -p "Enter Synthetic API key: " API_KEY
    echo
fi

if [ -z "$API_KEY" ]; then
    echo -e "${RED}✗${NC} API key required"
    exit 1
fi
echo -e "${GREEN}✓${NC} API key set"

# 3. Fetch models from /v1/models endpoint
echo
echo -e "${YELLOW}[3/5]${NC} Fetching available models from Synthetic..."

# Call the models endpoint
MODELS_RESPONSE=$(curl -s -H "Authorization: Bearer $API_KEY" \
  https://api.synthetic.new/v1/models 2>/dev/null || echo "")

if [ -z "$MODELS_RESPONSE" ]; then
    echo -e "${RED}✗${NC} Failed to fetch models. Check API key and connectivity."
    exit 1
fi

# Parse models and build JSON array
# Filter for hf: models (HuggingFace hosted), extract id and context_length
MODELS_JSON=$(echo "$MODELS_RESPONSE" | jq -c '
[
  .data[]
  | select(.id | contains("hf:"))
  | {
      name: .id,
      display_name: ("Synthetic: " + (.id | split(":")[1] | split("/")[1] | gsub("_"; " ") | gsub("-"; " "))),
      max_tokens: (.context_length // 128000)
    }
]
' 2>/dev/null || echo "[]")

# Check if we got models
MODEL_COUNT=$(echo "$MODELS_JSON" | jq 'length')
if [ "$MODEL_COUNT" -eq 0 ]; then
    echo -e "${RED}✗${NC} No hf: models found in response"
    echo "Response sample:"
    echo "$MODELS_RESPONSE" | jq '.' | head -20
    exit 1
fi

echo -e "${GREEN}✓${NC} Discovered ${MODEL_COUNT} models"
echo
echo "Sample models:"
echo "$MODELS_JSON" | jq -r '.[:3] | .[] | "  • \(.display_name) (\(.max_tokens) tokens)"'

# 4. Build and merge Zed config
echo
echo -e "${YELLOW}[4/5]${NC} Updating Zed configuration..."

ZED_SETTINGS="$HOME/.config/zed/settings.json"

# Create settings dir if missing
if [ ! -d "$(dirname "$ZED_SETTINGS")" ]; then
    mkdir -p "$(dirname "$ZED_SETTINGS")"
fi

# Initialize if empty
if [ ! -f "$ZED_SETTINGS" ] || [ ! -s "$ZED_SETTINGS" ]; then
    echo '{}' > "$ZED_SETTINGS"
fi

# Build full config block
SYNTHETIC_CONFIG=$(cat <<EOF
{
  "language_models": {
    "openai_compatible": {
      "Synthetic": {
        "api_url": "https://api.synthetic.new/v1",
        "available_models": ${MODELS_JSON}
      }
    }
  }
}
EOF
)

# Merge with existing settings using jq
# Handles nested merge: if language_models.openai_compatible exists, merge Synthetic into it
jq '. + {
  "language_models": (
    (.language_models // {}) + {
      "openai_compatible": (
        (.language_models.openai_compatible // {}) + {
          "Synthetic": {
            "api_url": "https://api.synthetic.new/v1",
            "available_models": '"$(echo "$MODELS_JSON" | jq -c .)"'
          }
        }
      )
    }
  )
}' "$ZED_SETTINGS" > /tmp/zed_settings.json.tmp && \
mv /tmp/zed_settings.json.tmp "$ZED_SETTINGS"

# Validate JSON
if ! jq empty "$ZED_SETTINGS" 2>/dev/null; then
    echo -e "${RED}✗${NC} Invalid JSON in settings.json. Rollback."
    exit 1
fi

echo -e "${GREEN}✓${NC} Updated $ZED_SETTINGS"

# 5. Set environment variable
echo
echo -e "${YELLOW}[5/5]${NC} Persisting API key to shell profiles..."

# Detect shell and prefer .zshenv for zsh (loaded by all sessions, including GUI apps)
SHELL_RC=""
SHELL_NAME=$(basename "$SHELL")

if [ "$SHELL_NAME" = "zsh" ]; then
    # Prefer .zshenv for zsh (sourced by all sessions, including GUI apps like Zed)
    SHELL_RC="$HOME/.zshenv"
elif [ "$SHELL_NAME" = "bash" ]; then
    SHELL_RC="$HOME/.bashrc"
fi

# Fallback to common RC files if preferred file doesn't exist
if [ ! -f "$SHELL_RC" ]; then
    if [ -f "$HOME/.zshrc" ]; then
        SHELL_RC="$HOME/.zshrc"
    elif [ -f "$HOME/.bashrc" ]; then
        SHELL_RC="$HOME/.bashrc"
    fi
fi

if [ -n "$SHELL_RC" ]; then
    # Validate shell syntax before modifying (for zsh)
    if [ "$SHELL_NAME" = "zsh" ] && [ -f "$SHELL_RC" ]; then
        if ! zsh -n "$SHELL_RC" 2>/dev/null; then
            echo -e "${YELLOW}⚠${NC} Warning: $SHELL_RC has syntax errors. Creating backup."
            cp "$SHELL_RC" "${SHELL_RC}.backup.$(date +%s)"
        fi
    fi
    
    # Remove any existing SYNTHETIC_API_KEY line first
    grep -v "SYNTHETIC_API_KEY" "$SHELL_RC" > /tmp/shell_rc.tmp 2>/dev/null || true
    
    # Add the new line
    echo "export SYNTHETIC_API_KEY=\"$API_KEY\"" >> /tmp/shell_rc.tmp
    mv /tmp/shell_rc.tmp "$SHELL_RC"
    
    # Source it
    source "$SHELL_RC" 2>/dev/null || true
    echo -e "${GREEN}✓${NC} API key saved to $SHELL_RC"
else
    echo -e "${YELLOW}⚠${NC} Could not find shell RC file. Add manually:"
    echo "  export SYNTHETIC_API_KEY=\"$API_KEY\""
fi

# Summary
echo
echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ Setup Complete!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
echo
echo "Next steps:"
echo "  1. ${BLUE}IMPORTANT${NC}: Quit and restart Zed completely (Cmd+Q, then reopen)"
echo "  2. Open Agent Panel: ${BLUE}Cmd/Ctrl+Shift+A${NC}"
echo "  3. Click model dropdown - should see Synthetic models"
echo "  4. Select any model and test in chat"
echo
echo "Configuration saved to:"
echo "  ${BLUE}$ZED_SETTINGS${NC}"
echo
echo "All available models (${MODEL_COUNT} total):"
echo "$MODELS_JSON" | jq -r '.[] | "  \u2713 \(.display_name) - \(.max_tokens) tokens"' | head -15
if [ "$MODEL_COUNT" -gt 15 ]; then
    echo "  ... and $((MODEL_COUNT - 15)) more"
fi
echo
echo "To re-run (updates models list):"
echo "  ${BLUE}./setup_synthetic_dynamic.sh${NC}"
echo
