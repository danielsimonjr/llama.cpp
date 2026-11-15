#!/usr/bin/env bash
# Run the LLMBench chat tasks on Dory at each loop count, one llama-server per loop count.
# Settings come from the environment; each has one default here.
set -u
GGUF="${DORY_GGUF:-}"
[ -n "$GGUF" ] || [ -n "${DORY_GGUF_PER_LOOP:-}" ] || { echo "set DORY_GGUF or DORY_GGUF_PER_LOOP"; exit 2; }
SERVER="${DORY_SERVER:-$HOME/llama.cpp-dory/build-vk/bin/Release/llama-server.exe}"
REPO="${DORY_BENCH_REPO:-$HOME/Github/ollama-mcp-results}"
PORT="${DORY_PORT:-8091}"
CTX="${DORY_CTX:-49152}"
LOOPS="${DORY_LOOPS:-2 4 6 8}"
TASKS="${DORY_TASKS:-g1-free,g1-schema,g2a-claims,g2b-diffs,g3-free,g3-schema,g4-32k,g5-ste}"
RUNS="${DORY_RUNS:-2}"
# Empty = the runner defaults (temperature 0, seed 42), the workload of the other models.
OPTS="${DORY_OPTIONS:-}"
THINK="${DORY_THINK:-}"
OLLAMA="${OLLAMA_PS_URL:-http://127.0.0.1:11434/api/ps}"
# Optional: a GGUF per loop count, with %L for the count (for example dory-folded-L%L.gguf). The file then holds
# num_loops and no --override-kv is sent. Use it with a draft model: llama-server copies --override-kv to the draft.
GGUF_PER_LOOP="${DORY_GGUF_PER_LOOP:-}"
# Extra llama-server arguments, for example the speculative decoding flags.
EXTRA="${DORY_SERVER_ARGS:-}"
OUT="${DORY_LOG_DIR:-$HOME/llama.cpp-dory/quality-logs}"
mkdir -p "$OUT"

for L in $LOOPS; do
  name="dory-loops$L"
  curl -s "$OLLAMA" > "$OUT/ollama-ps-before-loops$L.json"
  if [ -n "$GGUF_PER_LOOP" ]; then
    model="${GGUF_PER_LOOP//%L/$L}"; kv=()
  else
    model="$GGUF"; kv=(--override-kv "dory.num_loops=int:$L,dory.recurrent_kv_cache_mode=str:per_loop")
  fi
  "$SERVER" -m "$model" --alias "$name" -ngl 999 --jinja "${kv[@]}" $EXTRA \
    --ctx-size "$CTX" --host 127.0.0.1 --port "$PORT" > "$OUT/server-loops$L.log" 2>&1 &
  spid=$!
  ok=0
  for i in $(seq 1 100); do
    if curl -sf "http://127.0.0.1:$PORT/health" > /dev/null; then ok=1; break; fi
    sleep 3
  done
  if [ "$ok" != 1 ]; then echo "loops=$L server did not become healthy"; kill "$spid"; exit 1; fi
  served=$(curl -s "http://127.0.0.1:$PORT/props" | python -c "import json,sys;print(json.load(sys.stdin)['default_generation_settings']['n_ctx'])")
  echo "loops=$L START $(date -Iseconds) served_ctx=$served"
  ( cd "$REPO" && OLLAMA_BENCH_BACKEND=openai OLLAMA_BENCH_HOST="http://127.0.0.1:$PORT" \
      bun benchmarks/src/run.ts --tasks "$TASKS" --models "$name" --runs "$RUNS" ${OPTS:+--options "$OPTS"} ${THINK:+--think} ) > "$OUT/run-loops$L.log" 2>&1
  rc=$?
  echo "loops=$L END $(date -Iseconds) exit=$rc rows=$(grep -c ' r[0-9]' "$OUT/run-loops$L.log") errors=$(grep -c ' ERR ' "$OUT/run-loops$L.log")"
  kill "$spid"; wait "$spid" 2>/dev/null
  curl -s "$OLLAMA" > "$OUT/ollama-ps-after-loops$L.json"
  [ "$rc" = 0 ] || exit "$rc"
done
echo "ALL DONE $(date -Iseconds)"
