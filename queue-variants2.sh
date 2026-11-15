#!/usr/bin/env bash
# Wait for queue-variants.sh to exit, then run the recommended-settings variants at loops 6 and 4.
set -u
BASE="${DORY_BASE:-$HOME/llama.cpp-dory}"
POLL="${DORY_WATCH_POLL:-60}"
VLOOPS="${DORY_VARIANT_LOOPS:-6 4}"
VOPTS="${DORY_VARIANT_OPTIONS:-temperature=1,top_p=0.95}"
export DORY_SERVER="${DORY_SERVER:-$BASE/build-vk-opt/bin/Release/llama-server.exe}"
export DORY_GGUF="${DORY_GGUF:-$HOME/.cache/dory-work/dory-q5km-folded.gguf}"
running() {
  powershell.exe -NoProfile -Command '@(Get-CimInstance Win32_Process | Where-Object { $_.Name -eq "bash.exe" -and $_.CommandLine -match "(queue-variants|run-quality2?)\.sh\s*$" }).Count' | tr -d '\r'
}
until [ "$(running)" -eq 0 ]; do sleep "$POLL"; done
echo "previous queue exited $(date +%FT%T)"
for variant in sampling think; do
  log="$BASE/quality-logs-$variant"
  mkdir -p "$log"
  if [ "$variant" = think ]; then think=1; else think=; fi
  echo "== $variant loops $VLOOPS start $(date +%FT%T)"
  DORY_LOOPS="$VLOOPS" DORY_OPTIONS="$VOPTS" DORY_THINK="$think" DORY_LOG_DIR="$log" bash "$BASE/run-quality2.sh"
  echo "== $variant end $(date +%FT%T) exit $?"
done
