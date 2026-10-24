#!/bin/zsh
# Start (or restart) the local model server for the demo with the settings we measured with.
# Restart it before the demo: the MLX runner's prompt cache grows (8.9 GB -> 16 GB seen after an hour of runs).
#   scripts/start-local-llm.sh            # restart ollama serve in the background, pull the model if missing, warm it
#   scripts/start-local-llm.sh --stop     # stop it (frees ~9-16 GB)
set -e
MODEL=${ARES_LOCAL_MODEL:-qwen3.5:9b}
LOG=${TMPDIR:-/tmp}/ollama-serve.log
pkill -x ollama 2>/dev/null || true
sleep 1
[ "$1" = "--stop" ] && { echo "ollama stopped"; exit 0; }
export OLLAMA_FLASH_ATTENTION=1 OLLAMA_KV_CACHE_TYPE=q8_0 OLLAMA_MAX_LOADED_MODELS=1 OLLAMA_KEEP_ALIVE=60m
nohup ollama serve > $LOG 2>&1 &
for i in $(seq 1 20); do curl -sf localhost:11434/api/version >/dev/null && break; sleep 0.5; done
ollama list | grep -q "^$MODEL" || ollama pull $MODEL
# Load the model now so the first decision isn't a cold start.
curl -s localhost:11434/api/chat -d "{\"model\":\"$MODEL\",\"messages\":[],\"keep_alive\":\"60m\"}" >/dev/null
echo "ollama $(curl -s localhost:11434/api/version | sed 's/.*"version":"\([^"]*\)".*/\1/') serving $MODEL (log $LOG)"
ollama ps | tail -n +2
