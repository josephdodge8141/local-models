# Local Models Stack

Native multi-model LLM stack running Ollama on bare metal with Metal GPU acceleration on Apple Silicon.

## Architecture

```
┌──────────────────────────────────────────────────────┐
│  macOS (M5 Max, 128GB unified memory)                │
│                                                       │
│   curl / apps ──► http://127.0.0.1:11434             │
│                        │                              │
│   ┌────────────────────▼─────────────────────────┐   │
│   │  ollama serve (native arm64 process)         │   │
│   │  Metal GPU ◄──► unified memory (128 GB)      │   │
│   │                                              │   │
│   │  Models loaded on demand into GPU memory:    │   │
│   │   - qwen3.5:35b     (~22 GB)  worker        │   │
│   │   - llama3.3:70b    (~42 GB)  reviewer       │   │
│   │   - deepseek-r1:32b (~20 GB)  reasoning      │   │
│   │   - gemma4:e4b      (~3 GB)   router         │   │
│   └──────────────────────────────────────────────┘   │
│                        │                              │
│   ┌────────────────────▼─────────────────────────┐   │
│   │  ~/.ollama/models                            │   │
│   │  persistent on-disk model storage            │   │
│   └──────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────┘
```

**How it works:**

- **Ollama** runs as a native macOS process with direct Metal GPU access
- **Metal acceleration** uses the M5 Max GPU cores and full unified memory bandwidth — dramatically faster than CPU-only Docker
- **Models** are stored in `~/.ollama` and persist across restarts
- **The API** is served at `http://127.0.0.1:11434` — standard Ollama REST API, compatible with any client
- **Process management** via `up.sh`/`down.sh` scripts with PID tracking

**Why bare metal instead of Docker:**
Docker on Apple Silicon cannot pass through Metal GPU. Running Ollama in Docker means CPU-only inference — roughly 5-10x slower for large models. Native Ollama gets full GPU acceleration for free.

## Models

| Model | Tag | Approx Size | Role |
|---|---|---|---|
| Qwen 3.5 | `qwen3.5:35b` | ~22 GB | Primary large-context worker |
| Llama 3.3 | `llama3.3:70b` | ~42 GB | Reviewer / high-quality second pass |
| DeepSeek R1 | `deepseek-r1:32b` | ~20 GB | Reasoning fallback |
| Gemma 4 | `gemma4:e4b` | ~3 GB | Lightweight router / preprocessing |

With `OLLAMA_MAX_LOADED_MODELS=2`, Ollama keeps at most 2 models in GPU memory at once
(~64 GB worst case for 70b + 35b). Others load on demand and evict by LRU.

## Quick Start

```bash
# 0. Install Ollama (one time)
./scripts/install.sh

# 1. Start the server
./scripts/up.sh

# 2. Pull all models (first run downloads ~87 GB total)
./scripts/pull-models.sh

# 3. Test every model with a live inference
./scripts/test-models.sh

# 4. Check overall health
./scripts/health.sh
```

## Commands Reference

### Install Ollama
```bash
./scripts/install.sh
```
Installs (or upgrades) Ollama via Homebrew. One-time setup.

### Start the server
```bash
./scripts/up.sh
```
Sources `.env` for configuration, starts `ollama serve` in the background, waits for
the API to be healthy, and writes a PID file for clean shutdown.

### Pull models
```bash
./scripts/pull-models.sh
```
Pulls every model listed in `scripts/models.conf`. Idempotent — already-downloaded
models are verified and skipped.

### Test models
```bash
./scripts/test-models.sh
```
Sends a test inference to each model via `curl`. Reports token count, latency,
and tokens/second (shows Metal GPU throughput).

### Health check
```bash
./scripts/health.sh
```
Checks process status, API reachability, GPU/Metal state, model availability,
loaded models, and disk usage. Exit code = number of issues found.

### Stop the server
```bash
./scripts/down.sh
```
Stops the Ollama process tracked by the PID file. Clean shutdown.

### Manual commands
```bash
# View server log
tail -f .ollama.log

# List installed models
ollama list

# See currently loaded models (GPU memory)
curl -s http://127.0.0.1:11434/api/ps | jq '.models[]'

# Run a one-off prompt
curl http://127.0.0.1:11434/api/generate -d '{
  "model": "gemma4:e4b",
  "prompt": "Explain quicksort in two sentences.",
  "stream": false
}' | jq .response

# Interactive chat in terminal
ollama run gemma4:e4b

# Auto-start on boot (optional)
brew services start ollama
```

## Validation

After running the quick start, verify these three properties:

### 1. API reachable
```bash
curl -s http://127.0.0.1:11434/ && echo " OK"
# Expected: "Ollama is running OK"
```

### 2. Each model responds with Metal GPU
```bash
./scripts/test-models.sh
# Expected: PASS for every model, with tok/s showing GPU throughput
```

### 3. Persistence survives restart
```bash
./scripts/down.sh
./scripts/up.sh
ollama list
# Expected: all four models still listed (no re-download needed)
```

## Configuration

All tunable values are in `.env` (sourced by `up.sh`):

| Variable | Default | Description |
|---|---|---|
| `OLLAMA_HOST` | `127.0.0.1:11434` | Server bind address |
| `OLLAMA_MAX_LOADED_MODELS` | `2` | Max models in GPU memory at once |
| `OLLAMA_NUM_PARALLEL` | `4` | Concurrent requests per model |
| `OLLAMA_KEEP_ALIVE` | `10m` | Idle time before unloading a model |
| `OLLAMA_MODELS` | `~/.ollama` | Model storage path |

To change the model list, edit `scripts/models.conf`.

## Troubleshooting

### Ollama not found after install
**Symptom:** `command not found: ollama` after running `install.sh`.
**Fix:** Homebrew may not be in your PATH. Try:
```bash
eval "$(/opt/homebrew/bin/brew shellenv)"
ollama --version
```

### Model pull fails
**Symptom:** `pull-models.sh` reports failure for a specific model.
**Fix:** The model tag may not exist in the Ollama library. Check available tags at
https://ollama.com/library. Common issues:
- Tag renamed (e.g., `70b` vs `70b-instruct`)
- Model not yet published
- Network timeout — retry the pull

Edit `scripts/models.conf` to fix the tag, then re-run `pull-models.sh`.

### Port conflict
**Symptom:** `up.sh` reports Ollama is already running but you didn't start it.
**Fix:** Another process is using port 11434:
```bash
lsof -i :11434
```
If it's a stale Ollama process: `pkill -f 'ollama serve'` then retry.
If it's something else: change `OLLAMA_HOST` in `.env` to use a different port.

### Insufficient memory / system pressure
**Symptom:** macOS becomes sluggish when loading the 70B model, or model loading fails.
**Fix:** With 128 GB this should be rare. Check:
1. What else is consuming memory: `top -o mem`
2. Lower `OLLAMA_MAX_LOADED_MODELS` to 1 in `.env`
3. Restart: `./scripts/down.sh && ./scripts/up.sh`

The 70B model alone needs ~42 GB of unified memory. With 2 models loaded, worst case
is ~64 GB, leaving 64 GB for everything else.

### Slow first load
**Symptom:** First request to a model takes 10-30 seconds before tokens start.
**Expected behavior.** Ollama loads model weights from disk into GPU memory on first
request. The 70B model takes ~15-30s. Subsequent requests are fast while the model
stays loaded (controlled by `OLLAMA_KEEP_ALIVE`).

### Models disappear after reboot
**Symptom:** `ollama list` is empty after a reboot.
**Fix:** This shouldn't happen — models are stored in `~/.ollama` on disk. Check:
```bash
ls -la ~/.ollama/models/
```
If the directory is empty, models were deleted. Re-run `./scripts/pull-models.sh`.
If you moved `OLLAMA_MODELS` to another path, make sure that volume is mounted.

### Server won't start
**Symptom:** `up.sh` times out waiting for health.
**Fix:** Check the log:
```bash
cat .ollama.log
```
Common causes:
- Port already in use (see port conflict above)
- Corrupt installation: `brew reinstall ollama`
- macOS quarantine: `xattr -d com.apple.quarantine $(which ollama)`

### Stale PID file
**Symptom:** `down.sh` says "stale PID file" or `up.sh` thinks Ollama is running but it isn't.
**Fix:** The PID file (`.ollama.pid`) points to a process that exited. The scripts clean
this up automatically. If it persists:
```bash
rm .ollama.pid
./scripts/up.sh
```

## File Structure

```
.
├── .env                    # Ollama environment variables
├── .gitignore              # Ignores .ollama.pid and .ollama.log
├── README.md               # This file
└── scripts/
    ├── models.conf         # Model list (shared by all scripts)
    ├── install.sh          # Install Ollama via Homebrew
    ├── up.sh               # Start server + wait for health
    ├── down.sh             # Stop server
    ├── pull-models.sh      # Pull all models
    ├── test-models.sh      # Test inference on each model
    └── health.sh           # Comprehensive health check
```
