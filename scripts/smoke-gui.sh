#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="$root/build/artifacts/MochiDrop.app"
binary="$app/Contents/MacOS/MochiDrop"
test -x "$binary"

marker="$(mktemp "${TMPDIR:-/tmp}/mochidrop-gui.XXXXXXXX")"
log="$root/build/gui-smoke-$(uname -m).log"
MOCHIDROP_GUI_SMOKE_MARKER="$marker" "$binary" >"$log" 2>&1 &
pid=$!
cleanup() {
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  rm -f "$marker"
}
trap cleanup EXIT

for _ in {1..60}; do
  if [[ -s "$marker" ]]; then break; fi
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "MochiDrop exited before showing a window" >&2
    cat "$log" >&2
    exit 1
  fi
  sleep 0.5
done

if [[ ! -s "$marker" ]]; then
  echo "MochiDrop did not report a visible window within 30 seconds" >&2
  cat "$log" >&2
  exit 1
fi
cat "$marker"
sleep 3
if ! kill -0 "$pid" 2>/dev/null; then
  echo "MochiDrop exited immediately after opening its window" >&2
  cat "$log" >&2
  exit 1
fi

screenshot="$root/build/gui-smoke-$(uname -m).png"
if screencapture -x "$screenshot" 2>>"$log" && [[ -s "$screenshot" ]]; then
  sips -g pixelWidth -g pixelHeight "$screenshot"
else
  echo "Screenshot unavailable on this runner; visible-window check passed"
fi
