#!/usr/bin/env bash
# gate.sh <server.exe> <gguf> <tag>: greedy completions on two prompts, fusion off and on, into $OUT/<tag>-{nf,f}-{short,long}.json
set -u
SRV="$1"; GGUF="$2"; TAG="$3"
OUT="${DORY_GATE_OUT:?set DORY_GATE_OUT}"; PORT="${DORY_GATE_PORT:-8092}"
LONG=$(python -c "print(' '.join(['Paragraph %d: The committee reviewed the budget, the schedule and the staffing plan, then asked for a revised estimate.'%i for i in range(60)]) + ' Summarize the paragraphs above in two sentences.')")
for mode in nf f; do
  if [ $mode = nf ]; then export GGML_VK_DISABLE_FUSION=1 GGML_VK_DISABLE_GRAPH_OPTIMIZE=1 GGML_VK_DISABLE_MULTI_ADD=1; else unset GGML_VK_DISABLE_FUSION GGML_VK_DISABLE_GRAPH_OPTIMIZE GGML_VK_DISABLE_MULTI_ADD; fi
  "$SRV" -m "$GGUF" -ngl "${DORY_GATE_NGL:-999}" -c 4096 --port $PORT --host 127.0.0.1 > "$OUT/$TAG-$mode.srv.log" 2>&1 & pid=$!
  for i in $(seq 90); do curl -sf localhost:$PORT/health >/dev/null && break; sleep 2; done
  for p in short long; do
    if [ $p = short ]; then P="Explain in three sentences why the sky is blue."; else P="$LONG"; fi
    python -c "import json,sys;print(json.dumps({'prompt':sys.argv[1],'n_predict':64,'temperature':0,'seed':42,'n_probs':5,'cache_prompt':False}))" "$P" | curl -s localhost:$PORT/completion -d @- > "$OUT/$TAG-$mode-$p.json"
  done
  kill $pid; wait $pid 2>/dev/null || true
done
