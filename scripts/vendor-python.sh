#!/usr/bin/env bash
#
# vendor-python.sh — vendor the relocatable CPython that ships inside the
# StreamMagpie app bundle.
#
# WHY A BUNDLED PYTHON AT ALL
#   yt-dlp is Python. A packaged .app cannot rely on the user's `python3`:
#   macOS's own is a stub that prompts to install the command line tools, and a
#   Homebrew python is absent on most machines and the wrong version on the
#   rest. packages/app/src/main/helper-paths.ts points STREAMMAGPIE_PYTHON at
#   Contents/Resources/python/bin/python3, which is this.
#
# WHY python-build-standalone AND NOT THE python.org INSTALLER
#   python.org ships macOS builds as a .pkg that installs a Framework into
#   /Library/Frameworks with absolute paths compiled in. It is built to be
#   installed, not to be relocated inside somebody else's app bundle, and
#   extracting one and moving it produces a Python that cannot find its own
#   stdlib. python-build-standalone exists specifically to be relocatable, is
#   the same upstream CPython source, and is what uv and a long list of
#   shipping apps use. The previous version of this script already chose it;
#   what it lacked was a checksum and a gate.
#
# WHAT CHANGED FROM THE PREVIOUS VERSION
#   It defaulted to an unpinned release tag with a comment saying "pin when you
#   vendor for a release", downloaded over plain curl with no checksum, and
#   verified nothing beyond `python3 --version`. A build machine that ran it on
#   the wrong day got a different interpreter, silently. Now: pinned tag,
#   pinned CPython version, published sha256, licence payload, and a gate that
#   imports the modules yt-dlp actually needs.
#
# Properties:
#   - idempotent; no timestamps in generated files, so re-runs are
#     byte-identical
#   - the payload is staged and gated before it is promoted into vendor/
#
# Usage:
#   bash scripts/vendor-python.sh            # download (or verify what is there)
#   bash scripts/vendor-python.sh --force    # discard and re-download
#   bash scripts/vendor-python.sh --verify   # run the gate only, download nothing
#
# Env overrides:
#   STREAMMAGPIE_PYTHON_BUILD_DIR   work dir (default ~/.cache/streammagpie/python-build)

set -euo pipefail

# ---------------------------------------------------------------------------
# 0. Configuration
#
# The checksum is the one the release itself publishes, in its SHA256SUMS
# asset. To re-source it on a bump:
#
#   curl -sSL https://github.com/astral-sh/python-build-standalone/releases/download/<TAG>/SHA256SUMS \
#     | grep 'aarch64-apple-darwin-install_only.tar.gz$'
#
# 3.12 is chosen over 3.13/3.14 deliberately: yt-dlp supports it, and it is the
# version with the longest track record against the C extensions in the
# stdlib that yt-dlp touches. Bump the CPython version and the release tag
# together -- the tag is what the URL is built from.
# ---------------------------------------------------------------------------
PYTHON_VERSION="3.12.14"
PBS_TAG="20260814"
PBS_FILE="cpython-${PYTHON_VERSION}+${PBS_TAG}-aarch64-apple-darwin-install_only.tar.gz"
PBS_SHA256="4572133a5542f306b9bdb155da5800f9e38950cd0a98d469b832ce256fe299ea"
PBS_URL="https://github.com/astral-sh/python-build-standalone/releases/download/${PBS_TAG}/${PBS_FILE}"

# The stdlib directory name, used to find the interpreter's own licence file.
PYTHON_XY="$(printf '%s' "$PYTHON_VERSION" | cut -d. -f1,2)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TARGET_ARCH="arm64"
OUT_DIR="$ROOT/vendor/python/$TARGET_ARCH"

WORK="${STREAMMAGPIE_PYTHON_BUILD_DIR:-$HOME/.cache/streammagpie/python-build}"
TARBALL="$WORK/$PBS_FILE"
STAGE="$WORK/stage"

# The modules yt-dlp cannot run without. _ssl is the one that matters most: a
# Python without it fails every single download, and fails it at network time
# with a message that looks like a network problem.
REQUIRED_MODULES=(ssl zlib ctypes sqlite3 hashlib bz2 lzma)

FORCE=0
VERIFY_ONLY=0

usage() {
  sed -n '3,45p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
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

# ---------------------------------------------------------------------------
# Licence payload.
#
# CPython is distributed under the PSF License Agreement, which requires the
# notice to accompany a redistributed copy. The interpreter carries its own
# LICENSE.txt inside the stdlib directory; we copy that verbatim to the top of
# the payload so it is findable, rather than fetching a licence separately and
# risking it describing a different release.
# ---------------------------------------------------------------------------
find_python_licence() {
  local dir="$1" cand
  for cand in \
    "$dir/lib/python$PYTHON_XY/LICENSE.txt" \
    "$dir/lib/python$PYTHON_XY/LICENSE" \
    "$dir/LICENSE.txt" \
    "$dir/licenses/LICENSE.python.txt"
  do
    [[ -f "$cand" ]] && { printf '%s' "$cand"; return 0; }
  done
  # Last resort: any LICENSE.txt directly under a lib/python3.* directory.
  cand="$(ls -1 "$dir"/lib/python3.*/LICENSE.txt 2>/dev/null | head -1 || true)"
  [[ -n "$cand" ]] && { printf '%s' "$cand"; return 0; }
  return 1
}

write_source_notice() {
  local dir="$1"
  cat > "$dir/README.StreamMagpie.txt" <<EOF
CPython, as bundled with StreamMagpie
=====================================

WHAT THIS IS

  The Python interpreter in this directory is UNMODIFIED upstream CPython,
  redistributed as part of StreamMagpie under the Python Software Foundation
  License Agreement, a complete copy of which sits beside this file as
  LICENSE.python.txt.

  The specific build is a python-build-standalone distribution: the same
  CPython source, compiled to be relocatable so that it can live inside an
  application bundle rather than being installed system-wide.

WHAT IT DOES HERE

  It runs yt-dlp, which is a Python program. StreamMagpie never executes user
  code with it and never adds it to the user's PATH.

CORRESPONDING SOURCE

  CPython version:   $PYTHON_VERSION
  Distribution:      python-build-standalone $PBS_TAG
  File:              $PBS_FILE
  Source:            $PBS_URL
  SHA-256:           $PBS_SHA256

  Upstream CPython source for this version is published at
  https://www.python.org/downloads/source/ and tagged v$PYTHON_VERSION in the
  git repository at https://github.com/python/cpython. The build recipe used
  to produce the relocatable distribution is published at
  https://github.com/astral-sh/python-build-standalone.

REBUILDING

  scripts/vendor-python.sh in the StreamMagpie source tree re-fetches this
  distribution from the URL above, verifies the checksum, and verifies the
  result before accepting it.
EOF
  ok "licence: README.StreamMagpie.txt (source notice)"
}

install_licences() {
  local dir="$1" src
  if ! src="$(find_python_licence "$dir")"; then
    die "no PSF LICENSE text found anywhere in the python payload at $dir
     Refusing to ship a redistributed CPython with no licence text. If the
     distribution layout changed, fix find_python_licence() deliberately --
     do not skip the file."
  fi
  install -m 0644 "$src" "$dir/LICENSE.python.txt"
  ok "licence: LICENSE.python.txt (verbatim from the payload, ${src#"$dir"/})"
  write_source_notice "$dir"
}

# ---------------------------------------------------------------------------
# The gate.
# ---------------------------------------------------------------------------
run_gate() {
  local dir="${1:-$OUT_DIR}"
  local py="$dir/bin/python3"
  local fails=0

  say "HARD GATE ($dir)"

  # (a) the interpreter exists, runs, and is the version we pinned.
  if [[ ! -x "$py" ]]; then
    printf 'FAIL  not an executable file: %s\n' "$py"
    printf '\ngate FAILED\n' >&2
    return 1
  fi
  ok "executable: bin/python3"

  local reported
  reported="$("$py" --version 2>&1 || true)"
  if [[ "$reported" == "Python $PYTHON_VERSION" ]]; then
    ok "$reported"
  else
    printf 'FAIL  bin/python3 --version reports "%s", pin says "Python %s"\n' \
      "$reported" "$PYTHON_VERSION"; fails=1
  fi

  # (b) arch.
  local archs
  archs="$(lipo -archs "$py" 2>/dev/null | tr -s ' ' | sed 's/^ *//;s/ *$//')"
  if printf '%s' "$archs" | grep -qw arm64; then
    ok "lipo -archs = $archs (arm64 present)"
  else
    printf 'FAIL  lipo -archs = "%s", arm64 slice missing\n' "$archs"; fails=1
  fi

  # (c) no Homebrew linkage. @executable_path / @loader_path / @rpath are how a
  #     relocatable distribution finds its own libpython, so those are expected
  #     and fine; an absolute path outside the OS is not.
  local offenders
  offenders="$(otool -L "$py" | tail -n +2 | awk '{print $1}' \
    | grep -vE '^/usr/lib/|^/System/|^@executable_path/|^@loader_path/|^@rpath/' || true)"
  if [[ -n "$offenders" ]]; then
    printf 'FAIL  bin/python3 links libraries from outside the bundle and the OS:\n%s\n' "$offenders"; fails=1
  else
    ok "bin/python3: links only the OS and paths relative to itself"
  fi

  # (d) the modules yt-dlp needs actually import. A CPython built without
  #     _ssl still passes --version perfectly happily and then fails every
  #     download at run time with what looks like a network error.
  local mod
  for mod in "${REQUIRED_MODULES[@]}"; do
    if "$py" -c "import $mod" >/dev/null 2>&1; then
      ok "module imports: $mod"
    else
      printf 'FAIL  module does NOT import: %s\n' "$mod"; fails=1
    fi
  done

  # (e) it can reach a TLS endpoint's certificate store. Not a network call --
  #     just proof that the ssl module has a usable default context.
  if "$py" -c "import ssl; ssl.create_default_context()" >/dev/null 2>&1; then
    ok "ssl.create_default_context() works"
  else
    printf 'FAIL  ssl.create_default_context() failed -- downloads would fail at TLS setup\n'; fails=1
  fi

  # (f) the licence payload ships alongside the interpreter.
  local lf
  for lf in LICENSE.python.txt README.StreamMagpie.txt; do
    if [[ -s "$dir/$lf" ]]; then
      ok "licence file present: $lf"
    else
      printf 'FAIL  refusing to ship a redistributed CPython with no licence text: %s is missing\n' "$lf"; fails=1
    fi
  done

  # (g) no foreign source notice. electron-builder copies this directory into
  #     the bundle unfiltered.
  local entry base
  for entry in "$dir"/README.*.txt; do
    [[ -e "$entry" ]] || continue
    base="$(basename "$entry")"
    if [[ "$base" != "README.StreamMagpie.txt" ]]; then
      printf 'FAIL  foreign source notice would ship in the DMG: %s\n' "$base"; fails=1
    fi
  done

  if [[ "$fails" -ne 0 ]]; then
    printf '\ngate FAILED -- see FAIL lines above\n' >&2
    return 1
  fi
  printf '\ngate PASSED\n'
  return 0
}

# Clear OUT_DIR without disturbing the tracked .gitkeep that holds the
# directory in git (vendor/ contents are gitignored; the directory is not).
clear_out_dir() {
  local entry
  mkdir -p "$OUT_DIR"
  for entry in "$OUT_DIR"/* "$OUT_DIR"/.[!.]*; do
    [[ -e "$entry" ]] || continue
    [[ "$(basename "$entry")" == ".gitkeep" ]] && continue
    rm -rf "$entry"
  done
}

if [[ "$VERIFY_ONLY" -eq 1 ]]; then
  run_gate "$OUT_DIR"
  exit $?
fi

# ---------------------------------------------------------------------------
# 1. Preflight
# ---------------------------------------------------------------------------
say "preflight"

host_arch="$(uname -m)"
[[ "$host_arch" == "arm64" ]] || warn "host reports '$host_arch'; this vendors an arm64 interpreter regardless"

for tool in curl tar shasum otool lipo install; do
  command -v "$tool" >/dev/null 2>&1 || die "required tool not found on PATH: $tool"
done
ok "required tools present"

mkdir -p "$WORK" "$OUT_DIR"
ok "work dir: $WORK"
ok "output  : $OUT_DIR"

# Fast path: an existing payload that still passes the gate is left alone.
if [[ "$FORCE" -eq 0 && -x "$OUT_DIR/bin/python3" ]]; then
  skip "python already present -- verifying instead of re-downloading (--force to replace)"
  # Heal a payload vendored before the licence files existed, rather than
  # failing the gate forever with no way forward but --force.
  if [[ ! -s "$OUT_DIR/LICENSE.python.txt" || ! -s "$OUT_DIR/README.StreamMagpie.txt" ]]; then
    step "licence payload incomplete -- regenerating it in place"
    install_licences "$OUT_DIR"
  fi
  run_gate "$OUT_DIR"
  exit $?
fi

# ---------------------------------------------------------------------------
# 2. Fetch + verify
# ---------------------------------------------------------------------------
say "distribution"
verify_tarball() {
  [[ -f "$TARBALL" ]] || return 1
  [[ "$(sha256_of "$TARBALL")" == "$PBS_SHA256" ]]
}

if verify_tarball; then
  skip "$PBS_FILE already downloaded and checksum matches"
else
  [[ -f "$TARBALL" ]] && step "existing download failed checksum -- re-downloading"
  step "downloading $PBS_URL"
  curl -fSL --retry 3 --connect-timeout 20 -o "$TARBALL.part" "$PBS_URL"
  mv "$TARBALL.part" "$TARBALL"
  verify_tarball || {
    actual="$(sha256_of "$TARBALL")"
    rm -f "$TARBALL"
    die "sha256 mismatch for $PBS_FILE
       expected $PBS_SHA256
       got      $actual
     The download was discarded. Do NOT paper over this by updating the pin --
     re-source the checksum from the release's SHA256SUMS as shown in section 0."
  }
  ok "downloaded and checksum verified ($(du -h "$TARBALL" | awk '{print $1}'))"
fi

# ---------------------------------------------------------------------------
# 3. Extract into a staging dir
#
# The tarball unpacks to a single top-level `python/` directory; its contents
# are what become vendor/python/arm64.
# ---------------------------------------------------------------------------
say "extract"
rm -rf "$STAGE"
mkdir -p "$STAGE"
tar -xzf "$TARBALL" -C "$STAGE"
if [[ ! -x "$STAGE/python/bin/python3" ]]; then
  printf 'ERROR: unexpected tarball layout -- no python/bin/python3\n' >&2
  ls -la "$STAGE" >&2
  exit 1
fi
ok "extracted"

install_licences "$STAGE/python"

# ---------------------------------------------------------------------------
# 4. Gate the staged payload, then promote
# ---------------------------------------------------------------------------
run_gate "$STAGE/python" \
  || die "the downloaded interpreter did not pass the gate; vendor/ was left untouched"

say "promote"
clear_out_dir
# `tar` piped through itself preserves modes and symlinks exactly, which
# matters: the payload is full of bin/python3 -> python3.12 style links.
(cd "$STAGE/python" && tar -cf - .) | (cd "$OUT_DIR" && tar -xf -)
ok "promoted payload into $OUT_DIR"

run_gate "$OUT_DIR" || exit 1

# ---------------------------------------------------------------------------
# 5. Summary
# ---------------------------------------------------------------------------
say "summary"
printf '%-10s %s\n' "cpython" "$PYTHON_VERSION"
printf '%-10s %s\n' "build" "python-build-standalone $PBS_TAG"
printf '%-10s %s\n' "arch" "$TARGET_ARCH"
printf '%-10s %s\n' "licence" "PSF License Agreement (LICENSE.python.txt)"
printf '%-10s %s\n' "size" "$(du -sh "$OUT_DIR" | awk '{print $1}')"
printf '%-10s %s\n' "output" "$OUT_DIR"
echo
echo "vendor/ is gitignored -- these are build artifacts, not source."
exit 0
