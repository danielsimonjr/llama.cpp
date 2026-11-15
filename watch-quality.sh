#!/usr/bin/env bash
# Exit with a reason when the quality run ends, a row fails, or the runner dies.
LOG_DIR="${DORY_LOG_DIR:-$HOME/llama.cpp-dory/quality-logs}"
POLL="${DORY_WATCH_POLL:-60}"
# Count runner shells. A command line that ends in run-quality.sh is the runner itself;
# this check's own wrapper also contains the text, so it must not count.
alive() {
  powershell.exe -NoProfile -Command '@(Get-CimInstance Win32_Process | Where-Object { $_.Name -eq "bash.exe" -and $_.CommandLine -match "run-quality\.sh\s*$" }).Count' | tr -d '\r'
}
while true; do
  for f in "$LOG_DIR"/run-loops*.log; do
    bad=$(grep " r[0-9] " "$f" | grep -v " ok " | head -1)
    [ -n "$bad" ] && { echo "FAILED ROW in $(basename "$f"): $bad"; exit 1; }
  done
  n=$(alive)
  if [ "${n:-0}" -eq 0 ]; then
    for f in "$LOG_DIR"/run-loops*.log; do echo "$(basename "$f"): $(wc -l < "$f") rows"; done
    echo "RUNNER EXITED"; exit 0
  fi
  sleep "$POLL"
done
