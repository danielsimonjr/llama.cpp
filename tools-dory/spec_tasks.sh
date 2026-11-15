#!/usr/bin/env bash
# spec_tasks.sh <tag> <server args...>: LLMBench items on one server setting, rows into $DORY_GATE_OUT/tasks-<tag>
set -u
TAG="$1"; shift
OUT="${DORY_GATE_OUT:?set DORY_GATE_OUT}"; PORT="${DORY_GATE_PORT:-8092}"; SRV="${DORY_SRV:?set DORY_SRV}"
REPO="${DORY_BENCH_REPO:-$HOME/Github/ollama-mcp}"; TASKS="${DORY_SPEC_TASKS:-g2a-claims,g2b-diffs,g3-schema,g4-32k}"
LIMIT="${DORY_SPEC_LIMIT:-2}"; CTX="${DORY_CTX:-49152}"
RES="$OUT/tasks-$TAG"; mkdir -p "$RES"
"$SRV" -ngl 999 -c "$CTX" --jinja --alias dory-spec --port $PORT --host 127.0.0.1 "$@" > "$RES/server.log" 2>&1 & pid=$!
for i in $(seq 120); do curl -sf localhost:$PORT/health >/dev/null && break; sleep 2; done
( cd "$REPO" && BENCH_RESULTS_DIR="$RES" OLLAMA_BENCH_BACKEND=openai OLLAMA_BENCH_HOST="http://127.0.0.1:$PORT" \
    bun benchmarks/src/run.ts --tasks "$TASKS" --models dory-spec --runs 1 --limit "$LIMIT" ) > "$RES/run.log" 2>&1
kill $pid; wait $pid 2>/dev/null || true
