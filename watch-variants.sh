#!/usr/bin/env bash
# Exit with a reason when a variant row fails, a queue stage starts or ends, or every queue has exited.
BASE="${DORY_BASE:-$HOME/llama.cpp-dory}"
POLL="${DORY_WATCH_POLL:-60}"
OUTS="$BASE/quality-logs/queue-variants.out $BASE/quality-logs/queue-variants2.out"
stages() { cat $OUTS 2>/dev/null | grep -c "^=="; }
alive() {
  powershell.exe -NoProfile -Command '@(Get-CimInstance Win32_Process | Where-Object { $_.Name -eq "bash.exe" -and $_.CommandLine -match "(queue-variants2?|run-quality2?)\.sh\s*$" }).Count' | tr -d '\r'
}
start=$(stages)
while true; do
  for f in "$BASE"/quality-logs-sampling/run-loops*.log "$BASE"/quality-logs-think/run-loops*.log; do
    [ -f "$f" ] || continue
    bad=$(grep " r[0-9] " "$f" | grep -v " ok " | head -1)
    [ -n "$bad" ] && { echo "FAILED ROW in $f: $bad"; exit 1; }
  done
  now=$(stages)
  if [ "$now" != "$start" ]; then echo "STAGE CHANGE:"; cat $OUTS | grep "^=="; exit 0; fi
  if [ "$(alive)" -eq 0 ]; then echo "ALL QUEUES EXITED"; cat $OUTS | grep "^=="; exit 0; fi
  sleep "$POLL"
done
