#!/usr/bin/env bash
#
# vendor-ytdlp.sh — vendor the pinned yt-dlp wheel that ships inside the
# StreamMagpie app bundle.
#
# TWO FILENAMES, ONE WHEEL, AND BOTH ARE LOAD-BEARING.
#   yt_dlp-<version>-py3-none-any.whl   the pinned artifact, named as PyPI
#                                       publishes it, so the version that
#                                       shipped is legible from the filename
#   yt_dlp.whl                          the "floor copy": a byte-identical copy
#                                       under the fixed name the app resolves
#
#   packages/app/src/main/resolve-tools.ts and helper-paths.ts both look for
#   the literal name `yt_dlp.whl` (STREAMMAGPIE_FLOOR_WHEEL). It is the floor
#   the app falls back to when the self-updating copy in the user's support
#   directory is absent or broken, so it must exist under exactly that name.
#   Keeping the versioned name beside it is what makes the vendored floor
#   auditable after the fact.
#
# WHY NOT `pip download`
#   The previous version of this script shelled out to pip, which resolves
#   "latest" at run time. That makes the vendored wheel depend on the day the
#   build ran, requires a working pip on the build machine, and pins nothing.
#   A shipped app should contain the wheel we tested, not the wheel that
#   happened to be current. This fetches one pinned URL and verifies its
#   checksum.
#
# Properties:
#   - idempotent; a matching wheel already in place is verified, not re-fetched
#   - no timestamps anywhere, so re-runs are byte-identical
#
# Usage:
#   bash scripts/vendor-ytdlp.sh            # fetch (or verify what is there)
#   bash scripts/vendor-ytdlp.sh --force    # re-fetch even if the pin matches
#   bash scripts/vendor-ytdlp.sh --verify   # run the gate only, fetch nothing

set -euo pipefail

# ---------------------------------------------------------------------------
# 0. Configuration
#
# The checksum is the sha256 PyPI itself publishes for this exact file, which
# is also what pip verifies against. To re-source it on a version bump:
#
#   curl -sS https://pypi.org/pypi/yt-dlp/<version>/json \
#     | python3 -c 'import json,sys; d=json.load(sys.stdin); [print(u["filename"], u["digests"]["sha256"], u["url"]) for u in d["urls"]]'
#
# The URL contains a content-addressed path segment that changes with every
# release, so it has to be re-sourced the same way -- do not hand-edit the
# version into the old URL.
#
# ⚠ Bumping this pin is a behaviour change, not a chore: yt-dlp is the part of
# the app that breaks when YouTube changes. Run scripts/extractor-smoke.sh
# against the new wheel before you commit to it.
# ---------------------------------------------------------------------------
YTDLP_VERSION="2026.8.19"
YTDLP_SHA256="1d57897e94c6665a0a6f9bc54b34e584284e32c034ffab3a7df25d8f7b24eedf"
YTDLP_WHEEL="yt_dlp-${YTDLP_VERSION}-py3-none-any.whl"
YTDLP_URL="https://files.pythonhosted.org/packages/69/b2/8cd1613f56eed7ceb64fbd4df3f1c01246bfb098e6f398228bafda22b80b/${YTDLP_WHEEL}"

# The fixed name resolve-tools.ts opens. Do not rename without changing it too.
FLOOR_WHEEL="yt_dlp.whl"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="$ROOT/vendor/ytdlp"

MANAGED_FILES=("$YTDLP_WHEEL" "$FLOOR_WHEEL")

FORCE=0
VERIFY_ONLY=0

usage() {
  sed -n '3,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

for arg in "$@"; do
  case "$arg" in
    --force)   FORCE=1 ;;
    --verify)  VERIFY_ONLY=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $arg" >&2; exit 2 ;;
  esac
done

say()  { printf '\n==== %s ====\n' "$*"; }
step() { printf '....  %s\n' "$*"; }
ok()   { printf 'OK    %s\n' "$*"; }
skip() { printf 'SKIP  %s\n' "$*"; }
warn() { printf 'WARN  %s\n' "$*"; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

sha256_of() { shasum -a 256 "$1" | awk '{print $1}'; }

# Strip leading zeros from every dot-separated component, so that yt-dlp's
# padded "2026.08.19" and PyPI's normalised "2026.8.19" compare equal.
normalise_version() {
  printf '%s' "$1" | awk -F. '{ for (i=1;i<=NF;i++) { printf "%s%s", $i+0, (i<NF ? "." : "") } }'
}

# ---------------------------------------------------------------------------
# The gate.
# ---------------------------------------------------------------------------
run_gate() {
  local dir="${1:-$OUT_DIR}"
  local pinned="$dir/$YTDLP_WHEEL"
  local floor="$dir/$FLOOR_WHEEL"
  local fails=0
  local f actual

  say "HARD GATE ($dir)"

  # (a) both names exist and both match the pin. The floor copy matching the
  #     pin is the whole point: a stale yt_dlp.whl beside a fresh versioned
  #     wheel would ship the old extractor while the filename claims the new
  #     one, and that failure only shows up as "this video won't download".
  for f in "$pinned" "$floor"; do
    if [[ ! -s "$f" ]]; then
      printf 'FAIL  missing or empty: %s\n' "$f"; fails=1; continue
    fi
    actual="$(sha256_of "$f")"
    if [[ "$actual" == "$YTDLP_SHA256" ]]; then
      ok "sha256 matches the pin: $(basename "$f")"
    else
      printf 'FAIL  sha256 mismatch: %s\n      expected %s\n      got      %s\n' \
        "$(basename "$f")" "$YTDLP_SHA256" "$actual"; fails=1
    fi
  done
  [[ "$fails" -eq 0 ]] || { printf '\ngate FAILED\n' >&2; return 1; }

  # (b) it is a readable zip with the module layout the app expects. A wheel
  #     that unzips but has no yt_dlp/ package is not going to import.
  local listing
  if ! listing="$(unzip -l "$floor" 2>/dev/null)"; then
    printf 'FAIL  unzip cannot read %s -- it is not a valid wheel\n' "$FLOOR_WHEEL"; fails=1
  else
    local entry
    for entry in "yt_dlp/__init__.py" "yt_dlp/version.py" "yt_dlp/extractor/youtube/"; do
      # ⚠ NOT `printf ... | grep -qF`. `grep -q` exits the instant it matches,
      # which closes the pipe and kills printf with SIGPIPE; under `set -o
      # pipefail` that makes the pipeline non-zero and the check reports a FALSE
      # FAIL. It is buffer-timing dependent, so it passes locally on an already
      # vendored wheel and fails on a fast CI runner — observed 2026-08-24, where
      # yt_dlp/__init__.py and yt_dlp/version.py "failed" while the later-matching
      # yt_dlp/extractor/youtube/ passed. A herestring has no pipe and no writer.
      if grep -qF -- "$entry" <<<"$listing"; then
        ok "wheel contains $entry"
      else
        printf 'FAIL  wheel does not contain %s\n' "$entry"; fails=1
      fi
    done
    ok "wheel holds $(printf '%s\n' "$listing" | tail -1 | awk '{print $2}') files"
  fi

  # (c) the version baked into the wheel agrees with the pin. Catches a wheel
  #     renamed by hand, which is otherwise undetectable until someone tries to
  #     work out which extractor version actually shipped.
  #
  #     ⚠ The two spellings differ legitimately. yt-dlp writes a zero-padded
  #     calendar version into yt_dlp/version.py ("2026.08.19") while PyPI names
  #     the file with the PEP 440 normalised form ("2026.8.19"). Compare the
  #     normalised form of both rather than the literal strings.
  local inner_version
  inner_version="$(unzip -p "$floor" yt_dlp/version.py 2>/dev/null \
    | sed -nE "s/^__version__[[:space:]]*=[[:space:]]*['\"]([^'\"]+)['\"].*/\1/p" | head -1)"
  if [[ "$(normalise_version "$inner_version")" == "$(normalise_version "$YTDLP_VERSION")" ]]; then
    ok "yt_dlp/version.py reports $inner_version, matching the pin ($YTDLP_VERSION)"
  else
    printf 'FAIL  yt_dlp/version.py reports "%s", pin says "%s"\n' "$inner_version" "$YTDLP_VERSION"; fails=1
  fi

  # (d) nothing else rides along. electron-builder copies this directory into
  #     the bundle unfiltered, so a leftover wheel from an older pin is dead
  #     weight in the DMG and an ambiguity in any later audit.
  local base
  for entry in "$dir"/*; do
    [[ -f "$entry" ]] || continue
    base="$(basename "$entry")"
    case " ${MANAGED_FILES[*]} " in
      *" $base "*) continue ;;
    esac
    [[ "$base" == ".gitkeep" ]] && continue
    case "$base" in
      yt_dlp-*.whl)
        printf 'FAIL  a wheel from another version would also ship: %s\n' "$base"
        printf '      Remove it, or re-run this script without --verify to clean up.\n'
        fails=1 ;;
      *)
        warn "unexpected file in vendor/ytdlp (it WILL ship in the DMG): $base" ;;
    esac
  done

  if [[ "$fails" -ne 0 ]]; then
    printf '\ngate FAILED -- see FAIL lines above\n' >&2
    return 1
  fi
  printf '\ngate PASSED\n'
  return 0
}

if [[ "$VERIFY_ONLY" -eq 1 ]]; then
  run_gate "$OUT_DIR"
  exit $?
fi

# ---------------------------------------------------------------------------
# 1. Preflight
# ---------------------------------------------------------------------------
say "preflight"
for tool in curl shasum unzip; do
  command -v "$tool" >/dev/null 2>&1 || die "required tool not found on PATH: $tool"
done
ok "required tools present"

mkdir -p "$OUT_DIR"
ok "output: $OUT_DIR"

# ---------------------------------------------------------------------------
# 2. Fetch + verify
# ---------------------------------------------------------------------------
say "wheel"
PINNED="$OUT_DIR/$YTDLP_WHEEL"

if [[ "$FORCE" -eq 0 && -s "$PINNED" ]] && [[ "$(sha256_of "$PINNED")" == "$YTDLP_SHA256" ]]; then
  skip "$YTDLP_WHEEL already present and checksum matches"
else
  [[ -s "$PINNED" ]] && step "existing wheel failed checksum or --force given -- re-downloading"
  step "downloading $YTDLP_URL"
  curl -fSL --retry 3 --connect-timeout 20 -o "$PINNED.part" "$YTDLP_URL"
  mv "$PINNED.part" "$PINNED"
  actual="$(sha256_of "$PINNED")"
  if [[ "$actual" != "$YTDLP_SHA256" ]]; then
    rm -f "$PINNED"
    die "sha256 mismatch for $YTDLP_WHEEL
       expected $YTDLP_SHA256
       got      $actual
     The download was discarded. Do NOT paper over this by updating the pin --
     re-source the checksum from PyPI as shown in section 0."
  fi
  chmod 0644 "$PINNED"
  ok "downloaded and checksum verified ($(du -h "$PINNED" | awk '{print $1}'))"
fi

# ---------------------------------------------------------------------------
# 3. Floor copy
#
# A plain copy, not a symlink: electron-builder would either follow it and
# duplicate the payload or preserve it and ship a dangling link into the .app.
# ---------------------------------------------------------------------------
say "floor copy"
FLOOR="$OUT_DIR/$FLOOR_WHEEL"
if [[ -s "$FLOOR" ]] && [[ "$(sha256_of "$FLOOR")" == "$YTDLP_SHA256" ]]; then
  skip "$FLOOR_WHEEL already matches the pinned wheel"
else
  install -m 0644 "$PINNED" "$FLOOR"
  ok "$YTDLP_WHEEL -> $FLOOR_WHEEL (the name resolve-tools.ts opens)"
fi

# ---------------------------------------------------------------------------
# 4. Remove wheels from superseded pins
#
# Left alone these ship in the DMG: dead weight, and a later audit cannot tell
# which one the app actually loaded.
# ---------------------------------------------------------------------------
for stale in "$OUT_DIR"/yt_dlp-*.whl; do
  [[ -e "$stale" ]] || continue
  [[ "$(basename "$stale")" == "$YTDLP_WHEEL" ]] && continue
  step "removing wheel from a superseded pin: $(basename "$stale")"
  rm -f "$stale"
done

# ---------------------------------------------------------------------------
# 5. Gate + summary
# ---------------------------------------------------------------------------
run_gate "$OUT_DIR" || exit 1

say "summary"
printf '%-10s %s\n' "yt-dlp" "$YTDLP_VERSION"
printf '%-10s %s\n' "output" "$OUT_DIR"
echo
printf '  %-40s %8s  %s\n' "FILE" "SIZE" "ROLE"
printf '  %-40s %8s  %s\n' "$YTDLP_WHEEL" "$(du -h "$PINNED" | awk '{print $1}')" "pinned artifact"
printf '  %-40s %8s  %s\n' "$FLOOR_WHEEL" "$(du -h "$FLOOR"  | awk '{print $1}')" "floor copy (loaded by the app)"
echo
echo "Smoke-test this wheel against live YouTube before shipping it:"
echo "  WHEEL=$FLOOR bash scripts/extractor-smoke.sh"
exit 0
