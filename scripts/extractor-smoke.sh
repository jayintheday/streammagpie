#!/usr/bin/env bash
# Smoke-test a yt-dlp version against live YouTube. Exit 0 only if audio formats exist.
#
# ⚠ The checker is passed with `python3 -c`, NOT `python3 - <<EOF`. A heredoc
# would become python's stdin and displace the piped JSON, so json.load() would
# read an empty stream and the test would fail for a reason that has nothing to
# do with the extractor.
#
#   WHEEL=vendor/ytdlp/yt_dlp.whl bash scripts/extractor-smoke.sh
set -euo pipefail
VIDEO="${SMOKE_VIDEO:-https://www.youtube.com/watch?v=jNQXAC9IVRw}"
PY="${PYTHON:-python3}"
export PYTHONPATH="${WHEEL:-${PYTHONPATH:-}}"
"$PY" -m yt_dlp --no-update -J --skip-download \
  --extractor-args "youtube:player_client=visionos,tv,web_embedded,android_vr" \
  "$VIDEO" | python3 -c '
import json, sys
data = json.load(sys.stdin)
fmts = data.get("formats") or []
audio = [f for f in fmts if f.get("acodec") not in (None, "none") and f.get("vcodec") in (None, "none")]
if not audio:
    sys.stderr.write("SMOKE FAIL: no audio-only formats\n")
    sys.exit(1)
ids = {f.get("format_id") for f in audio}
if "140" not in ids and "251" not in ids:
    sys.stderr.write(f"SMOKE FAIL: no itag 140/251, got {sorted(ids)[:20]}\n")
    sys.exit(1)
print("SMOKE OK", sorted(ids)[:8])
'
