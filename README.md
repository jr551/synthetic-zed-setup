# Synthetic + Zed Dynamic Setup

Automatically configure Zed Code Editor with Synthetic's AI models by querying the live `/v1/models` endpoint.

## Features

- 🔄 **Auto-discovery**: Fetches all available `hf:` models from Synthetic API
- 📝 **Dynamic config**: Updates Zed's `settings.json` with discovered models
- 🔑 **API key management**: Persists API key to shell profiles (`.zshenv` for zsh, `.bashrc` for bash)
- ✅ **Syntax validation**: Validates shell config files before modification
- 🛡️ **Backup protection**: Creates backups if existing configs have syntax errors

## Requirements

- `curl` - for API requests
- `jq` - for JSON parsing
- `gh` - for GitHub CLI (optional, for repo management)
- Zed Code Editor
- Synthetic API key

## Installation

```bash
# Clone or download setup_synthetic_dynamic.sh
chmod +x setup_synthetic_dynamic.sh
./setup_synthetic_dynamic.sh
```

## Usage

1. Run the script and provide your Synthetic API key when prompted
2. The script will:
   - Fetch all available models from Synthetic
   - Update `~/.config/zed/settings.json` with model configurations
   - Save your API key to `~/.zshenv` (zsh) or `~/.bashrc` (bash)
3. **Quit and restart Zed completely** (Cmd+Q on macOS)
4. Open the Agent Panel (Cmd/Ctrl+Shift+A)
5. Select a Synthetic model from the dropdown

## Supported Models

The script automatically discovers all `hf:` prefixed models from Synthetic, including:
- GLM 4.7, GLM 4.6
- MiniMax M2.1, M2
- Llama 3.3 70B Instruct
- DeepSeek V3 variants
- Qwen 3 models (Coder, VL, Thinking)
- Kimi K2 variants

## Configuration

The script updates `~/.config/zed/settings.json` with:

```json
{
  "language_models": {
    "openai_compatible": {
      "Synthetic": {
        "api_url": "https://api.synthetic.new/v1",
        "available_models": [
          {
            "name": "hf:zai-org/GLM-4.7",
            "display_name": "Synthetic: GLM 4.7",
            "max_tokens": 202752
          }
          // ... more models
        ]
      }
    }
  }
}
```

## Troubleshooting

### Models not showing in Zed

1. Ensure you've **completely quit and restarted** Zed (Cmd+Q)
2. Check that `SYNTHETIC_API_KEY` is set: `echo $SYNTHETIC_API_KEY`
3. Verify Zed logs: `tail -f ~/Library/Logs/Zed/Zed.log` (macOS)
4. Check settings.json syntax: `jq empty ~/.config/zed/settings.json`

### Shell syntax errors

The script validates shell configs before modification. If errors are found:
- A backup is created with timestamp: `.zshenv.backup.<timestamp>`
- Fix the original file or restore from backup
- Re-run the script

### API key not working

- Verify your API key at https://api.synthetic.new/v1/models
- Check your quota: `curl -s https://api.synthetic.new/v2/quotas | jq .`

## License

MIT

## Contributing

Feel free to submit issues and pull requests!
