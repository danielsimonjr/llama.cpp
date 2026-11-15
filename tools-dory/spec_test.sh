#!/usr/bin/env bash
# spec_test.sh <tag> <server args...>: greedy 128-token completions of two prompts into $DORY_GATE_OUT/spec-<tag>-{short,long}.json
set -u
TAG="$1"; shift
OUT="${DORY_GATE_OUT:?set DORY_GATE_OUT}"; PORT="${DORY_GATE_PORT:-8092}"; SRV="${DORY_SRV:?set DORY_SRV}"
LONG=$(python -c "print(' '.join(['Paragraph %d: The committee reviewed the budget, the schedule and the staffing plan, then asked for a revised estimate.'%i for i in range(60)]) + ' Summarize the paragraphs above in two sentences.')")
"$SRV" -ngl 999 -c 4096 --port $PORT --host 127.0.0.1 "$@" > "$OUT/spec-$TAG.srv.log" 2>&1 & pid=$!
for i in $(seq 120); do curl -sf localhost:$PORT/health >/dev/null && break; sleep 2; done
for p in short long; do
  if [ $p = short ]; then P="Explain in three sentences why the sky is blue."; else P="$LONG"; fi
  python -c "import json,sys;print(json.dumps({'prompt':sys.argv[1],'n_predict':128,'temperature':0,'seed':42,'cache_prompt':False}))" "$P" | curl -s localhost:$PORT/completion -d @- > "$OUT/spec-$TAG-$p.json"
  python -c "import json,sys;d=json.load(open(sys.argv[1],encoding='utf-8'));t=d['timings'];print(sys.argv[2], sys.argv[3], 'tps', round(t['predicted_per_second'],2), 'draft', t.get('draft_n'), 'accepted', t.get('draft_n_accepted'))" "$OUT/spec-$TAG-$p.json" "$TAG" "$p"
done
kill $pid; wait $pid 2>/dev/null || true
