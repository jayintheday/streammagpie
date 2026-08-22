#!/usr/bin/env bash
#
# vendor-js.sh — build the QuickJS interpreter (qjs) that ships inside the
# StreamMagpie app bundle.
#
# WHAT IT IS FOR
#   yt-dlp needs a JavaScript runtime to solve YouTube's n-signature challenge.
#   packages/engine/src/argv.ts passes it as `--js-runtimes qjs:<path>`, and
#   packages/app/src/main/helper-paths.ts looks for the binary at
#   Contents/Resources/js/qjs. Without it, downloads fail on exactly the videos
#   that matter most.
#
# WHY qjs AND NOT deno — this is a packaging constraint, not a preference.
#   packages/app/electron-builder.yml lists the helpers that get code-signed:
#
#       mac:
#         binaries:
#           - Contents/Resources/js/qjs
#
#   `qjs` is on that list. `deno` is NOT. A deno binary dropped into vendor/js
#   would be copied into the bundle unsigned, and notarization would reject the
#   whole DMG -- after the build, at the last step, with an opaque message.
#   It is also roughly 100 MB against QuickJS's ~1 MB, on a DMG whose entire
#   appeal is that it is small.
#
#   The engine supports either runtime, so deno remains possible. But switching
#   to it means editing electron-builder.yml to sign it, which is a deliberate
#   configuration change made by a human. This script therefore has NO silent
#   fallback: if qjs cannot be produced it fails and says so.
#
# WHY BUILD RATHER THAN COPY A SYSTEM qjs
#   Homebrew's qjs links dylibs out of /opt/homebrew, so copying it produces a
#   bundle that works on the build machine and fails on every user's. QuickJS is
#   a handful of C files with no dependencies beyond libSystem; building it from
#   the pinned tarball takes well under a minute and links nothing but the OS.
#
# Properties:
#   - idempotent, and no timestamps in generated files, so re-runs are
#     byte-identical
#   - all work happens OUTSIDE the repo; only the binary and its licence files
#     land in vendor/js (gitignored)
#   - the payload is staged and gated before it is promoted into vendor/
#
# Usage:
#   bash scripts/vendor-js.sh             # build (or verify an existing build)
#   bash scripts/vendor-js.sh --force     # discard and rebuild from scratch
#   bash scripts/vendor-js.sh --verify    # run the gate only, build nothing
#
# Env overrides:
#   STREAMMAGPIE_QJS_BUILD_DIR   work dir (default ~/.cache/streammagpie/quickjs-build)
#   STREAMMAGPIE_QJS_JOBS        make -j value (default: all cores)

set -euo pipefail

# ---------------------------------------------------------------------------
# 0. Configuration
# ---------------------------------------------------------------------------

# QuickJS ships as a dated tarball from Bellard's own site; there is no
# "official binary release" to pin instead, so we pin the source.
#
# The checksum is NOT one we computed from our own download -- that would be
# circular. It is the sha256 Homebrew pins in its quickjs formula, i.e. an
# independent distribution channel cross-checking the bytes bellard.org serves.
# To re-source it on a bump:
#   curl -sS https://formulae.brew.sh/api/formula/quickjs.json \
#     | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["versions"]["stable"], d["urls"]["stable"]["checksum"])'
QUICKJS_VERSION="2026-06-04"
QUICKJS_SHA256="b376e839b322978313d929fd20663b11ba58b75df5a46c126dd19ea2fa70ad2a"
QUICKJS_URL="https://bellard.org/quickjs/quickjs-${QUICKJS_VERSION}.tar.xz"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

OUT_DIR="$ROOT/vendor/js"

# Exactly the files this script owns in OUT_DIR.
MANAGED_FILES=(qjs LICENSE.quickjs.txt README.StreamMagpie.txt)

WORK="${STREAMMAGPIE_QJS_BUILD_DIR:-$HOME/.cache/streammagpie/quickjs-build}"
SRC="$WORK/quickjs-$QUICKJS_VERSION"
TARBALL="$WORK/quickjs-${QUICKJS_VERSION}.tar.xz"
STAGE="$WORK/stage"
BUILD_LOG="$WORK/build.log"
JOBS="${STREAMMAGPIE_QJS_JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 4)}"

# CONFIG_M32= is how QuickJS's Makefile is told not to attempt a 32-bit build;
# it is the same override Homebrew's formula passes. `qjs` is a first-class
# target in PROGS, and it pulls in qjsc as a dependency because the REPL is
# compiled from repl.js.
MAKE_ARGS=(CONFIG_M32=)
MAKE_TARGET="qjs"

FORCE=0
VERIFY_ONLY=0

usage() {
  sed -n '3,55p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
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

# The one message this script exists to print instead of quietly doing the
# wrong thing. Every failure path that leaves us without a qjs routes here.
die_no_qjs() {
  printf 'ERROR: %s\n' "$1" >&2
  cat >&2 <<'EOF'

     No JavaScript runtime was vendored, and this script will NOT substitute
     deno for it.

     Why there is no fallback:
       * packages/app/electron-builder.yml signs only
             Contents/Resources/js/qjs
         A deno binary placed in vendor/js would be copied into the bundle
         UNSIGNED, and notarization would then reject the entire DMG.
       * deno is roughly 100 MB. qjs is about 1 MB. That difference is most of
         the download.

     If you genuinely want deno, it is a configuration change, not a script
     fallback. You would have to:
       1. add `- Contents/Resources/js/deno` to mac.binaries in
          packages/app/electron-builder.yml, and
       2. accept the DMG size increase.
     The engine already supports either runtime (see packages/engine/src/argv.ts
     and packages/app/src/main/resolve-tools.ts), so nothing else changes.

     Otherwise: fix the build failure above and re-run this script.
EOF
  exit 1
}

sha256_of() { shasum -a 256 "$1" | awk '{print $1}'; }

# ---------------------------------------------------------------------------
# Licence payload.
#
# QuickJS is MIT licensed, and MIT requires the copyright notice and permission
# text to accompany the binary we distribute. electron-builder copies vendor/js
# into the bundle unfiltered, so putting the licence here is what makes it reach
# the user. No timestamps -- re-runs must be byte-identical.
# ---------------------------------------------------------------------------
write_source_notice() {
  local dir="$1"
  cat > "$dir/README.StreamMagpie.txt" <<EOF
QuickJS, as bundled with StreamMagpie
=====================================

WHAT THIS IS

  The \`qjs\` binary in this directory is UNMODIFIED upstream QuickJS, compiled
  from the official source release identified below. No patches of any kind
  were applied. It is redistributed as part of StreamMagpie under the MIT
  license, a complete copy of which sits beside this file as
  LICENSE.quickjs.txt.

WHAT IT DOES HERE

  yt-dlp uses it to evaluate the JavaScript that YouTube requires in order to
  derive playback URLs. StreamMagpie passes it to yt-dlp as
  \`--js-runtimes qjs:<path to this binary>\`. It is never used to run code that
  StreamMagpie itself supplies.

CORRESPONDING SOURCE

  Version:   QuickJS $QUICKJS_VERSION
  Source:    $QUICKJS_URL
  SHA-256:   $QUICKJS_SHA256

HOW THIS BINARY WAS BUILT

  make ${MAKE_ARGS[*]} $MAKE_TARGET
  strip -S -x qjs

  The build links nothing but the macOS system libraries; run \`otool -L qjs\`
  to confirm.

REBUILDING

  scripts/vendor-js.sh in the StreamMagpie source tree reproduces this build
  from the tarball above, and verifies the result before accepting it.
EOF
  ok "licence: README.StreamMagpie.txt (source notice)"
}

install_licences_from_source() {
  local dir="$1"
  [[ -f "$SRC/LICENSE" ]] || die "no LICENSE in $SRC
     QuickJS is MIT licensed and the notice must travel with the binary.
     If upstream renamed the file, fix this script deliberately."
  install -m 0644 "$SRC/LICENSE" "$dir/LICENSE.quickjs.txt"
  ok "licence: LICENSE.quickjs.txt (verbatim from the built source tree)"
  write_source_notice "$dir"
}

# ---------------------------------------------------------------------------
# The gate. Takes the directory to inspect so the same code can vet a staging
# dir before promotion and vendor/js afterwards.
# ---------------------------------------------------------------------------
run_gate() {
  local dir="${1:-$OUT_DIR}"
  local qjs_bin="$dir/qjs"
  local fails=0

  say "HARD GATE ($dir)"

  # (a) present and executable.
  if [[ ! -x "$qjs_bin" ]]; then
    printf 'FAIL  not an executable file: %s\n' "$qjs_bin"
    printf '\ngate FAILED\n' >&2
    return 1
  fi
  ok "executable: qjs"

  # (b) arch. arm64 is what the app ships; a universal binary is acceptable
  #     because it still runs natively, it is just larger than it needs to be.
  local archs
  archs="$(lipo -archs "$qjs_bin" 2>/dev/null | tr -s ' ' | sed 's/^ *//;s/ *$//')"
  if printf '%s' "$archs" | grep -qw arm64; then
    ok "lipo -archs = $archs (arm64 present)"
    [[ "$archs" == "arm64" ]] || warn "universal binary -- fine, but larger than the DMG needs"
  else
    printf 'FAIL  lipo -archs = "%s", arm64 slice missing\n' "$archs"; fails=1
  fi

  # (c) no non-system dynamic links. QuickJS needs nothing but libSystem, so
  #     anything else here means a Homebrew binary got copied in by mistake and
  #     the bundle would fail to launch on a user's machine.
  local offenders
  offenders="$(otool -L "$qjs_bin" | tail -n +2 | awk '{print $1}' \
    | grep -vE '^/usr/lib/|^/System/' || true)"
  if [[ -n "$offenders" ]]; then
    printf 'FAIL  qjs links non-system libraries:\n%s\n' "$offenders"; fails=1
  else
    ok "qjs: links only /usr/lib and /System"
  fi

  # (d) it actually evaluates JavaScript. An executable that cannot run a
  #     one-liner cannot solve an n-signature either.
  local smoke
  smoke="$("$qjs_bin" -e 'console.log(1)' 2>/dev/null || true)"
  if [[ "$smoke" == "1" ]]; then
    ok "smoke: qjs -e \"console.log(1)\" printed 1"
  else
    printf 'FAIL  smoke: qjs -e "console.log(1)" printed "%s", expected "1"\n' "$smoke"; fails=1
  fi

  # (e) the licence payload ships alongside the binary.
  local lf
  for lf in LICENSE.quickjs.txt README.StreamMagpie.txt; do
    if [[ -s "$dir/$lf" ]]; then
      ok "licence file present: $lf"
    else
      printf 'FAIL  refusing to ship an MIT-licensed binary with no licence text: %s is missing\n' "$lf"; fails=1
    fi
  done

  # (f) nothing else executable rides along. This is the deno trap: electron-
  #     builder signs only Contents/Resources/js/qjs, so any OTHER binary in
  #     this directory reaches the bundle unsigned and sinks notarization.
  local entry base kind
  for entry in "$dir"/*; do
    [[ -f "$entry" ]] || continue
    base="$(basename "$entry")"
    case " ${MANAGED_FILES[*]} " in
      *" $base "*) continue ;;
    esac
    [[ "$base" == ".gitkeep" ]] && continue
    kind="$(file -b "$entry" 2>/dev/null || echo unknown)"
    if printf '%s' "$kind" | grep -q 'Mach-O'; then
      printf 'FAIL  a second binary is present and would ship UNSIGNED: %s\n' "$base"
      printf '      electron-builder.yml mac.binaries lists only Contents/Resources/js/qjs.\n'
      printf '      Notarization will reject the DMG. Remove it, or sign it deliberately.\n'
      fails=1
    else
      warn "unexpected file in vendor/js (it WILL ship in the DMG): $base"
    fi
  done

  say "otool -L qjs"
  otool -L "$qjs_bin"

  if [[ "$fails" -ne 0 ]]; then
    printf '\ngate FAILED -- see FAIL lines above\n' >&2
    return 1
  fi
  printf '\ngate PASSED\n'
  return 0
}

promote() {
  local from="$1" f
  mkdir -p "$OUT_DIR"
  for f in "${MANAGED_FILES[@]}"; do
    rm -f "$OUT_DIR/$f"
    [[ -e "$from/$f" ]] || continue
    if [[ "$f" == "qjs" ]]; then
      install -m 0755 "$from/$f" "$OUT_DIR/$f"
    else
      install -m 0644 "$from/$f" "$OUT_DIR/$f"
    fi
  done
  ok "promoted payload into $OUT_DIR"
}

# --verify short-circuits everything else.
if [[ "$VERIFY_ONLY" -eq 1 ]]; then
  run_gate "$OUT_DIR"
  exit $?
fi

# ---------------------------------------------------------------------------
# 1. Preflight
# ---------------------------------------------------------------------------
say "preflight"

xcode-select -p >/dev/null 2>&1 \
  || die_no_qjs "no Xcode command line tools -- QuickJS is C source and needs a compiler (xcode-select --install)"

for tool in curl tar make cc shasum otool lipo strip install; do
  command -v "$tool" >/dev/null 2>&1 \
    || die_no_qjs "required tool not found on PATH: $tool"
done
ok "toolchain: $(cc --version | head -1)"

mkdir -p "$WORK" "$OUT_DIR"
ok "work dir: $WORK"
ok "output  : $OUT_DIR"

# Fast path: an existing binary that still passes the gate is left alone.
if [[ "$FORCE" -eq 0 && -x "$OUT_DIR/qjs" ]]; then
  skip "qjs already present -- verifying instead of rebuilding (--force to rebuild)"
  # Heal a vendor dir populated before the licence files existed, rather than
  # failing the gate forever with no way forward but --force.
  if [[ -f "$SRC/LICENSE" ]]; then install_licences_from_source "$OUT_DIR"; fi
  run_gate "$OUT_DIR"
  exit $?
fi

if [[ "$FORCE" -eq 1 ]]; then
  step "--force: discarding previous source tree and outputs"
  rm -rf "$SRC" "$STAGE"
  for f in "${MANAGED_FILES[@]}"; do rm -f "$OUT_DIR/$f"; done
fi

# ---------------------------------------------------------------------------
# 2. Fetch + verify the release tarball
# ---------------------------------------------------------------------------
say "source tarball"
verify_tarball() {
  [[ -f "$TARBALL" ]] || return 1
  [[ "$(sha256_of "$TARBALL")" == "$QUICKJS_SHA256" ]]
}

if verify_tarball; then
  skip "quickjs-${QUICKJS_VERSION}.tar.xz already downloaded and checksum matches"
else
  [[ -f "$TARBALL" ]] && step "existing tarball failed checksum -- re-downloading"
  step "downloading $QUICKJS_URL"
  curl -fSL --retry 3 --connect-timeout 20 -o "$TARBALL.part" "$QUICKJS_URL" \
    || die_no_qjs "download failed: $QUICKJS_URL"
  mv "$TARBALL.part" "$TARBALL"
  verify_tarball || {
    actual="$(sha256_of "$TARBALL")"
    rm -f "$TARBALL"
    die "sha256 mismatch for quickjs-${QUICKJS_VERSION}.tar.xz
       expected $QUICKJS_SHA256
       got      $actual
     The download was discarded. Do NOT paper over this by updating the pin --
     re-source the checksum from the Homebrew formula named in section 0."
  }
  ok "downloaded and checksum verified ($(du -h "$TARBALL" | awk '{print $1}'))"
fi

# ---------------------------------------------------------------------------
# 3. Extract
# ---------------------------------------------------------------------------
say "extract"
if [[ -f "$SRC/Makefile" ]]; then
  skip "source tree already extracted at $SRC"
else
  step "extracting into $WORK"
  rm -rf "$SRC"
  tar -xJf "$TARBALL" -C "$WORK"
  [[ -f "$SRC/Makefile" ]] || die "extract produced no Makefile at $SRC"
  ok "extracted"
fi

# ---------------------------------------------------------------------------
# 4. Build
#
# The environment is scrubbed for the same reason ffmpeg's is: a shell profile
# exporting -I/opt/homebrew/include or -L/opt/homebrew/lib is enough to make
# the result link a Homebrew dylib and fail gate (c) -- or, worse, pass here
# and fail on a user's machine.
# ---------------------------------------------------------------------------
say "build quickjs $QUICKJS_VERSION"
step "make ${MAKE_ARGS[*]} -j$JOBS $MAKE_TARGET  (output -> $BUILD_LOG)"
(
  cd "$SRC"
  env -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS -u PKG_CONFIG_PATH \
      make "${MAKE_ARGS[@]}" -j"$JOBS" "$MAKE_TARGET"
) > "$BUILD_LOG" 2>&1 || {
  printf '\n--- last 40 lines of %s ---\n' "$BUILD_LOG" >&2
  tail -40 "$BUILD_LOG" >&2
  die_no_qjs "quickjs build failed"
}
[[ -f "$SRC/qjs" ]] || die_no_qjs "the build reported success but produced no qjs in $SRC"
ok "make completed"

# ---------------------------------------------------------------------------
# 5. Stage, gate, promote
#
# QuickJS's Makefile compiles with -g. Stripping the debug map keeps the build
# machine's directory layout out of a binary handed to strangers, and takes the
# binary from ~1.2 MB to ~0.9 MB.
# ---------------------------------------------------------------------------
say "stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
install -m 0755 "$SRC/qjs" "$STAGE/qjs"
strip -S -x "$STAGE/qjs"
ok "staged qjs ($(du -h "$STAGE/qjs" | awk '{print $1}'), stripped)"

install_licences_from_source "$STAGE"

run_gate "$STAGE" || die "the freshly built qjs did not pass the gate; vendor/js was left untouched"
promote "$STAGE"

# ---------------------------------------------------------------------------
# 6. Summary
# ---------------------------------------------------------------------------
say "summary"
printf '%-10s %s\n' "quickjs" "$QUICKJS_VERSION"
printf '%-10s %s\n' "licence" "MIT"
printf '%-10s %s\n' "output" "$OUT_DIR"
echo
printf '  %-26s %8s  %s\n' "FILE" "SIZE" "ROLE"
printf '  %-26s %8s  %s\n' "qjs" "$(du -h "$OUT_DIR/qjs" | awk '{print $1}')" "binary (signed by electron-builder)"
for lf in LICENSE.quickjs.txt README.StreamMagpie.txt; do
  [[ -f "$OUT_DIR/$lf" ]] || continue
  printf '  %-26s %8s  %s\n' "$lf" "$(du -h "$OUT_DIR/$lf" | awk '{print $1}')" "licence"
done
echo
echo "vendor/ is gitignored -- these are build artifacts, not source."
exit 0
