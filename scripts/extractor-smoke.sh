#!/usr/bin/env bash
# Smoke-test a yt-dlp version against live YouTube.
#
# Exit codes — the whole point of this script is that these are three different
# things, and the old version collapsed them into one:
#
#   0  OK            audio-only formats present, and itag 140 or 251 among them
#   1  FAIL          yt-dlp extracted the video, but the formats we ship against
#                    are gone. This is a real extractor regression. Act on it.
#   2  INCONCLUSIVE  yt-dlp could not extract at all — bot wall, network, geo.
#                    Says NOTHING about the extractor. Do not act on it.
#
# ⚠ The checker reads yt-dlp's JSON from a FILE, and is passed with `python3 -c`,
# NOT from a pipe and NOT via `python3 - <<EOF`. Three separate traps here:
#   - a heredoc becomes python's stdin and displaces the piped JSON, so
#     json.load() reads an empty stream and the test fails for a reason that has
#     nothing to do with the extractor;
#   - a pipe hides yt-dlp's own exit status behind python's, so a bot wall and a
#     genuine format regression become indistinguishable;
#   - when extraction fails, yt-dlp writes the error to stderr and the literal
#     `null` to stdout. json.load() then SUCCEEDS and returns None, and the first
#     .get() raises AttributeError — burying the real cause under a traceback.
#     That is exactly what the 2026-08-23 and 2026-08-24 CI runs reported.
#
#   bash scripts/extractor-smoke.sh                      # tests the shipped pin
#   WHEEL=/tmp/wheels/yt_dlp-9.9.9.whl bash scripts/...  # tests a candidate
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# WHEEL is the single knob, and it defaults to the wheel we actually ship. A bare
# run therefore tests the pin in vendor/ytdlp — not whatever PyPI published this
# morning, which is what the old CI job was doing and which told us nothing about
# the DMG. Setting PYTHONPATH directly does not work: this line overwrites it.
WHEEL="${WHEEL:-$REPO_ROOT/vendor/ytdlp/yt_dlp.whl}"
if [[ ! -e "$WHEEL" ]]; then
  printf 'SMOKE INCONCLUSIVE: wheel not found: %s\n' "$WHEEL" >&2
  printf '  Run scripts/vendor-ytdlp.sh first, or pass WHEEL=<path>.\n' >&2
  exit 2
fi
export PYTHONPATH="$WHEEL"

VIDEO="${SMOKE_VIDEO:-https://www.youtube.com/watch?v=jNQXAC9IVRw}"
PY="${PYTHON:-python3}"

# Mirrors buildProbeArgs() in packages/engine/src/probe.ts, whose chain comes from
# DEFAULT_CLIENT_CHAIN in packages/engine/src/clients.ts. Keep them in step: if
# they drift, CI is testing a configuration the product never uses.
CHAIN="${SMOKE_CLIENT_CHAIN:-visionos,tv,web_embedded,android_vr}"

# The bundled QuickJS is meant to solve YouTube's "n" challenge.
#
# ⚠ THE RUNTIME NAME IS `quickjs`, NOT `qjs`. yt-dlp 2026.8.19 accepts exactly
# deno, node, bun, quickjs. Anything else it discards with
# `WARNING: Ignoring unsupported JavaScript runtime(s): qjs` and then carries on
# succeeding - so the mistake silently means NO JS runtime at all, rather than an
# error. [verified: run 2026-08-24]
#
# ⚠ The app passes `qjs`: packages/app/src/main/extractor-host.ts:513 sets
# `name: 'qjs'`, typed at packages/engine/src/argv.ts:11 as `'qjs' | 'deno'`. So the
# shipped app bundles a 965 KB QuickJS binary that yt-dlp then ignores.
# [verified: source 2026-08-24]
#
# What that costs today: nothing measurable. Six alternating runs against the default
# video, same wheel and chain, gave an IDENTICAL 10 audio-only formats with itag 251
# present under both spellings. [verified: run 2026-08-24] The reason is that the name
# is not the only thing missing: yt-dlp also wants the EJS challenge-solver script,
# which it fetches with `--remote-components ejs:github`, and without it the n
# challenge fails even when the runtime IS recognised. Fixing the name is correct and
# removes a misleading warning; on its own it does not restore challenge solving, and
# shipping the solver script is a live-network question this repo has not answered.
#
# This script uses the spelling that works, so the gate stops blessing the typo.
#
# ${arr[@]+"${arr[@]}"} rather than "${arr[@]}": under `set -u`, bash 3.2 - still
# what /bin/bash is on macOS and on GitHub's runners - treats an empty array as unbound.
QJS="${STREAMMAGPIE_QJS:-$REPO_ROOT/vendor/js/qjs}"
JS_ARGS=()
if [[ -x "$QJS" ]]; then
  JS_ARGS=(--js-runtimes "quickjs:$QJS")
else
  printf 'NOTE: no QuickJS at %s; running without a JS runtime, so formats may be missing.\n' "$QJS" >&2
  printf '      Run scripts/vendor-js.sh to match what the app does.\n' >&2
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

set +e
"$PY" -m yt_dlp --no-update --no-playlist -J --skip-download \
  --extractor-args "youtube:player_client=$CHAIN" \
  ${JS_ARGS[@]+"${JS_ARGS[@]}"} \
  -- "$VIDEO" >"$tmp/out.json" 2>"$tmp/err.txt"
rc=$?
set -e

[[ -s "$tmp/err.txt" ]] && sed 's/^/      /' "$tmp/err.txt" >&2

if [[ $rc -ne 0 ]] || [[ ! -s "$tmp/out.json" ]] || [[ "$(tr -d '[:space:]' <"$tmp/out.json")" == "null" ]]; then
  if grep -qiE "sign in to confirm|not a bot|confirm you.re not a bot" "$tmp/err.txt"; then
    printf 'SMOKE INCONCLUSIVE: YouTube served a bot wall; the extractor was never exercised.\n' >&2
    printf '  Expected on a datacenter IP such as a GitHub Actions runner. StreamMagpie ships\n' >&2
    printf '  no cookie import, no sign-in and no PO-token provider by design (AGENTS.md), so\n' >&2
    printf '  there is nothing to fix here. Re-run from a residential connection.\n' >&2
    exit 2
  fi
  printf 'SMOKE INCONCLUSIVE: yt-dlp exited %s without usable JSON. See its stderr above.\n' "$rc" >&2
  exit 2
fi

"$PY" -c '
import json, sys
with open(sys.argv[1]) as fh:
    data = json.load(fh)
if not isinstance(data, dict):
    sys.stderr.write(f"SMOKE INCONCLUSIVE: expected a JSON object, got {type(data).__name__}\n")
    sys.exit(2)
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
' "$tmp/out.json"
