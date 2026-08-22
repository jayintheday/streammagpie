#!/usr/bin/env bash
#
# build-ffmpeg.sh — build the static, LGPL-only ffmpeg + ffprobe that ship
# inside the StreamMagpie app bundle, WITH libmp3lame.
#
# WHY THIS EXISTS
#   A public clone of this repo has no access to the author's machine and no
#   sibling checkouts. An earlier version of this script copied a prebuilt
#   ffmpeg out of a private sibling repo; on any other machine that silently
#   produced an empty vendor/ directory, electron-builder logged one line
#   ("file source doesn't exist") and shipped a DMG with no ffmpeg in it.
#   This script builds from source instead, so a clone can produce the same
#   binaries the author does.
#
#   Homebrew's ffmpeg is not an option either: it links ~18 dylibs out of
#   /opt/homebrew, so copying it into an .app yields something that runs on the
#   build machine and nowhere else.
#
# WHY libmp3lame IS IN AN "LGPL-ONLY" BUILD — this is not a contradiction.
#   StreamMagpie sells MP3 output as a feature. MP3 encoding needs LAME, and
#   LAME is licensed LGPL v2, so linking it does NOT require --enable-gpl.
#   The GPL flag is for GPL-licensed dependencies (libx264, libx265, ...) and
#   for GPL-only ffmpeg components, none of which this app touches.
#
#   So: --enable-libmp3lame YES, --enable-gpl NO, --enable-nonfree NO.
#   Adding either of those is a licensing decision, not a build tweak. The
#   gate below refuses a binary that has them.
#
# WHY THE GATE IS THE POINT OF THIS SCRIPT
#   Every assertion in run_gate() exists because its absence presents to the
#   user as a broken app rather than a broken build:
#     - no libmp3lame     -> "Save as MP3" fails at conversion time, per file
#     - a Homebrew dylib  -> ffmpeg will not launch on any machine but this one
#     - wrong arch        -> the same, one layer down
#     - no licence text   -> we are redistributing LGPL binaries unlawfully
#     - a foreign build path in the configuration string -> the shipped binary
#       advertises somebody else's project and somebody's home directory
#   The last one is why STREAMMAGPIE_FFMPEG_DIR (see below) still runs the full
#   gate: importing a prebuilt binary must fail loudly, never vendor silently.
#
# WE REDISTRIBUTE THESE BINARIES, SO THE LICENCE TEXT SHIPS WITH THEM.
#   LGPL v2.1 section 1 requires a distributed binary to be accompanied by the
#   licence and by a route to the corresponding source. Alongside ffmpeg and
#   ffprobe this installs COPYING.LGPLv2.1 and LICENSE.md (both verbatim from
#   the source tree that was built) plus a generated README.StreamMagpie.txt
#   naming the exact upstream version, URL, checksum and configure line.
#   packages/app/electron-builder.yml copies this directory into the bundle
#   unfiltered, so those files reach the user automatically -- and, in the same
#   way, anything missing here is missing from every DMG we hand out.
#
# Properties:
#   - idempotent: a completed build is re-verified against the gate, not rebuilt
#   - no timestamps in any generated file, so re-runs are byte-identical
#   - all work happens OUTSIDE the repo (see WORK below); only the binaries and
#     their licence files land in the tree, under vendor/ (gitignored)
#   - the payload is assembled in a staging dir and only promoted into vendor/
#     after it passes the gate, so a failed run never leaves a bad ffmpeg behind
#
# Usage:
#   bash scripts/build-ffmpeg.sh              # build (or verify an existing build)
#   bash scripts/build-ffmpeg.sh --force      # discard and rebuild from scratch
#   bash scripts/build-ffmpeg.sh --verify     # run the gate only, build nothing
#
# Env overrides:
#   STREAMMAGPIE_FFMPEG_BUILD_DIR  work dir (default ~/.cache/streammagpie/ffmpeg-build)
#   STREAMMAGPIE_FFMPEG_JOBS       make -j value (default: all cores)
#   STREAMMAGPIE_FFMPEG_DIR        ESCAPE HATCH. Import ffmpeg/ffprobe from an
#                                  existing directory instead of building. The
#                                  full gate still runs, and only the four files
#                                  we manage are copied -- never a stray source
#                                  notice belonging to another application.

set -euo pipefail

# ---------------------------------------------------------------------------
# 0. Configuration
# ---------------------------------------------------------------------------

# Checksums here are NOT ones we computed from our own downloads -- that would
# be circular. Each is taken from an independent distribution channel with its
# own audit trail, cross-checking the bytes the upstream server hands us.
#
# ffmpeg: the sha256 Homebrew pins in its formula. To re-source it on a bump:
#   curl -sS https://formulae.brew.sh/api/formula/ffmpeg.json \
#     | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["versions"]["stable"], d["urls"]["stable"]["checksum"])'
FFMPEG_VERSION="9.0.1"
FFMPEG_SHA256="cf38e0e28c7e5605942c4a77755349b0145804a397af37eb1fb4c77cb237f635"
FFMPEG_URL="https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz"

# LAME 3.100 is the long-settled release every distribution has built against
# for years; ffmpeg requires >= 3.98.3. LAME 4.0 exists and ffmpeg builds
# against it, but 3.100 is the conservative pin for a shipped binary -- bump it
# deliberately, with a fresh checksum, not casually.
#
# lame: the sha256 MacPorts pins in audio/lame/Portfile, whose recorded size
# (1524133 bytes) also matches the Gentoo Manifest entry for the same tarball.
#   curl -sS https://raw.githubusercontent.com/macports/macports-ports/master/audio/lame/Portfile | grep -A3 checksums
LAME_VERSION="3.100"
LAME_SHA256="ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e"
LAME_URL="https://downloads.sourceforge.net/project/lame/lame/${LAME_VERSION}/lame-${LAME_VERSION}.tar.gz"

# These mirror packages/engine/src/argv.ts, which is the only place that decides
# what ffmpeg is asked to do:
#   format 'mp3'  -> -x --audio-format mp3   (libmp3lame)
#   format 'alac' -> -x --audio-format alac  (ffmpeg-native alac encoder)
#   format 'm4a'  -> --remux-video m4a       (container copy, no encoder)
# Keep the two in lockstep. An encoder that vanishes from a future ffmpeg
# release must fail here, not at the user's first conversion.
REQUIRED_ENCODERS=(libmp3lame alac)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TARGET_ARCH="arm64"
OUT_DIR="$ROOT/vendor/ffmpeg/$TARGET_ARCH"

# Exactly the files this script owns in OUT_DIR. Used both to copy an imported
# directory (so nothing else rides along) and to clear the destination before
# promoting a new payload.
MANAGED_FILES=(ffmpeg ffprobe COPYING.LGPLv2.1 LICENSE.md README.StreamMagpie.txt)

# Work dir lives OUTSIDE the repo so a failed build can never dirty the tree,
# and so re-runs are cheap (the tarballs and object files survive).
WORK="${STREAMMAGPIE_FFMPEG_BUILD_DIR:-$HOME/.cache/streammagpie/ffmpeg-build}"
SRC="$WORK/ffmpeg-$FFMPEG_VERSION"
LAME_SRC="$WORK/lame-$LAME_VERSION"
FFMPEG_TARBALL="$WORK/ffmpeg-${FFMPEG_VERSION}.tar.xz"
LAME_TARBALL="$WORK/lame-${LAME_VERSION}.tar.gz"
STAGE="$WORK/stage"
BUILD_LOG="$WORK/build.log"
JOBS="${STREAMMAGPIE_FFMPEG_JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 4)}"

IMPORT_DIR="${STREAMMAGPIE_FFMPEG_DIR:-}"

# LAME is installed into a directory INSIDE the ffmpeg source tree and is
# referenced by a RELATIVE path. That is deliberate and load-bearing.
#
# ffmpeg records its configure arguments verbatim and prints them back from
# `ffmpeg -version`. An absolute --extra-cflags=-I/Users/<someone>/... would
# put a real person's home directory into a binary we hand to strangers. Since
# configure and make both run with the cwd set to $SRC, a relative -I/-L works
# identically and leaks nothing.
LAME_STAGE_REL="lame-root"
LAME_PREFIX="$SRC/$LAME_STAGE_REL"

# The configure flags live up here, in the config section, for one specific
# reason: README.StreamMagpie.txt records the exact configure line this build
# used, and write_build_notice() generates that line from THIS array. A
# hand-retyped copy in a string literal would drift from reality the first time
# someone edited the flags, and a corresponding-source notice that misstates how
# the binary was built is worse than no notice at all.
#
# --prefix is a relative, build-local string. We never run `make install` (the
# binaries are taken straight out of the build tree), so the prefix affects
# nothing except the configuration string -- and there it is neutral.
#
# --disable-lzma is NOT tidiness. macOS ships no system liblzma but Homebrew
# does, so ffmpeg's autodetection links it and the binary stops being portable.
# sdl2/xlib/libxcb are likewise Homebrew-only and serve ffplay, which is off.
#
# Network stays ENABLED on purpose: yt-dlp hands ffmpeg HTTP/HLS URLs directly
# for some formats, so --disable-network would break those downloads.
#
# No --enable-videotoolbox: this app never encodes video.
CONFIGURE_FLAGS=(
  --prefix=build-prefix
  --disable-shared
  --enable-static
  --disable-doc
  --disable-ffplay
  --disable-debug
  --disable-lzma
  --disable-sdl2
  --disable-xlib
  --disable-libxcb
  --enable-audiotoolbox
  --enable-libmp3lame
  "--extra-cflags=-I$LAME_STAGE_REL/include"
  "--extra-ldflags=-L$LAME_STAGE_REL/lib"
  --arch="$TARGET_ARCH"
)

# LAME's own configure. --disable-frontend drops the `lame` CLI, which is the
# only part of LAME that wants ncurses/termcap; we link the library only.
# CFLAGS is set explicitly rather than inherited so that (a) a Homebrew-flavoured
# shell profile cannot poison it and (b) autoconf's default "-g -O2" does not
# bake build-machine paths into the static archive's debug map.
LAME_CONFIGURE_FLAGS=(
  --prefix="$LAME_PREFIX"
  --disable-shared
  --enable-static
  --disable-frontend
  --disable-dependency-tracking
)
LAME_CFLAGS="-O2"

FORCE=0
VERIFY_ONLY=0

usage() {
  sed -n '3,80p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
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

# Fetch a tarball and refuse to proceed unless it matches the pin. A mismatch
# discards the download rather than keeping it -- the next run must re-fetch,
# not inherit a half-trusted file.
fetch_verified() {
  local url="$1" want="$2" dest="$3" label="$4"
  local actual
  if [[ -f "$dest" ]]; then
    actual="$(sha256_of "$dest")"
    if [[ "$actual" == "$want" ]]; then
      skip "$label already downloaded and checksum matches"
      return 0
    fi
    step "existing $label failed checksum -- re-downloading"
  fi
  step "downloading $url"
  curl -fSL --retry 3 --connect-timeout 20 -o "$dest.part" "$url"
  mv "$dest.part" "$dest"
  actual="$(sha256_of "$dest")"
  if [[ "$actual" != "$want" ]]; then
    rm -f "$dest"
    die "sha256 mismatch for $label
       expected $want
       got      $actual
     The download was discarded. Do NOT paper over this by updating the pin --
     re-source the checksum from the distribution channel named in section 0."
  fi
  ok "$label downloaded and checksum verified ($(du -h "$dest" | awk '{print $1}'))"
}

# ---------------------------------------------------------------------------
# Licence payload -- shipped NEXT TO the binaries, not optional.
#
# COPYING.LGPLv2.1 and LICENSE.md are taken verbatim from the source tree we
# actually built, never fetched separately, so they cannot end up describing a
# different release than the binaries came from.
# ---------------------------------------------------------------------------

# Notice for the normal path: we built these binaries, so we can name the exact
# corresponding source. The configure line is reconstructed from the same array
# the build ran, so it cannot drift from what was actually built.
#
# No timestamp anywhere in here: re-runs must produce byte-identical output or
# "idempotent" stops meaning anything.
write_build_notice() {
  local dir="$1"
  local cfg="./configure" lcfg="./configure" f
  for f in "${CONFIGURE_FLAGS[@]}"; do cfg="$cfg $f"; done
  for f in "${LAME_CONFIGURE_FLAGS[@]}"; do lcfg="$lcfg $f"; done
  # LAME's --prefix is the one absolute path in play; it is build-local and has
  # no business in a file we hand to users.
  lcfg="${lcfg//$SRC/<ffmpeg-source-dir>}"

  cat > "$dir/README.StreamMagpie.txt" <<EOF
FFmpeg, as bundled with StreamMagpie
====================================

WHAT THIS IS

  The ffmpeg and ffprobe binaries in this directory are UNMODIFIED upstream
  FFmpeg, compiled from the official source release identified below, linked
  against an unmodified upstream LAME. No patches of any kind were applied to
  either project. They are redistributed as part of StreamMagpie under the GNU
  Lesser General Public License, version 2.1, a complete copy of which sits
  beside this file as COPYING.LGPLv2.1.

CORRESPONDING SOURCE

  FFmpeg
    Version:   $FFMPEG_VERSION
    Source:    $FFMPEG_URL
    SHA-256:   $FFMPEG_SHA256

  LAME (libmp3lame, statically linked into ffmpeg)
    Version:   $LAME_VERSION
    Source:    $LAME_URL
    SHA-256:   $LAME_SHA256

  Those two tarballs are the complete corresponding source for these binaries.
  Both are published by their respective projects and remain available for
  download. The FFmpeg release is additionally tagged n$FFMPEG_VERSION in the
  upstream git repository at https://git.ffmpeg.org/ffmpeg.git, should the
  tarball itself ever be withdrawn.

HOW THESE BINARIES WERE CONFIGURED

  LAME, installed into a directory inside the FFmpeg source tree:

    CFLAGS="$LAME_CFLAGS" $lcfg
    make && make install

  FFmpeg, built against that LAME:

    $cfg
    make

  (--prefix above is a build-local string. It does not affect the binaries,
  which are taken directly from the build tree rather than installed, and the
  paths passed to --extra-cflags / --extra-ldflags are relative to the FFmpeg
  source directory.)

LICENSING POSITION

  This is an LGPL build. It is configured WITHOUT --enable-gpl and WITHOUT
  --enable-nonfree.

  libmp3lame is present because StreamMagpie offers MP3 output. LAME is
  licensed under the GNU Lesser General Public License, version 2, so linking
  it does not make this build GPL. No GPL-licensed library is linked: there is
  no libx264, libx265, libvpx, libsvtav1 or libdav1d in it.

  You do not have to take this file's word for any of that -- ask the binary:

      ./ffmpeg -L            the licence FFmpeg reports it was built under
      ./ffmpeg -buildconf    the exact configure flags compiled into it
      otool -L ./ffmpeg      the libraries it actually links against

  See LICENSE.md for the FFmpeg project's own statement of how its individual
  components are licensed. LAME's own licence text ships inside the LAME
  tarball named above, in COPYING and LICENSE.

REBUILDING

  scripts/build-ffmpeg.sh in the StreamMagpie source tree reproduces this build
  from the tarballs above, and verifies the result before accepting it.
EOF
  ok "licence: README.StreamMagpie.txt (corresponding-source notice)"
}

# Notice for the escape hatch: we did NOT build these binaries, so we must not
# claim a source tarball we never fetched. Everything below is read back out of
# the binary itself, which keeps the file both honest and deterministic.
write_import_notice() {
  local dir="$1"
  local ver_line buildconf
  ver_line="$("$dir/ffmpeg" -hide_banner -version 2>/dev/null | head -1)"
  buildconf="$("$dir/ffmpeg" -hide_banner -buildconf 2>/dev/null | sed -n '2,$p' | sed 's/^[[:space:]]*/    /')"

  cat > "$dir/README.StreamMagpie.txt" <<EOF
FFmpeg, as bundled with StreamMagpie
====================================

WHAT THIS IS

  The ffmpeg and ffprobe binaries in this directory are FFmpeg, redistributed
  as part of StreamMagpie under the GNU Lesser General Public License, version
  2.1, a complete copy of which sits beside this file as COPYING.LGPLv2.1.

  They were supplied to the packaging step as prebuilt binaries (via the
  STREAMMAGPIE_FFMPEG_DIR escape hatch) rather than compiled by
  scripts/build-ffmpeg.sh. Everything recorded below was therefore read back
  out of the binaries themselves.

CORRESPONDING SOURCE

  The binaries report themselves as:

    $ver_line

  The matching source release is published by the FFmpeg project at
  https://ffmpeg.org/releases/ and tagged in the upstream git repository at
  https://git.ffmpeg.org/ffmpeg.git.

  If you are the packager: confirm that the corresponding source for THIS
  build is genuinely published and reachable before you distribute the result.
  Running scripts/build-ffmpeg.sh without STREAMMAGPIE_FFMPEG_DIR builds from a
  pinned, checksummed tarball and removes that question entirely.

HOW THESE BINARIES WERE CONFIGURED

$buildconf

LICENSING POSITION

  This is an LGPL build. scripts/build-ffmpeg.sh refuses to vendor a binary
  whose configuration contains --enable-gpl or --enable-nonfree, or one that
  lacks --enable-libmp3lame, so the configuration above has been checked for
  all three.

  Verify it yourself:

      ./ffmpeg -L            the licence FFmpeg reports it was built under
      ./ffmpeg -buildconf    the exact configure flags compiled into it
      otool -L ./ffmpeg      the libraries it actually links against

  See LICENSE.md for the FFmpeg project's own statement of how its individual
  components are licensed.
EOF
  ok "licence: README.StreamMagpie.txt (imported-binary notice)"
}

install_licences_from_source() {
  local dir="$1"
  [[ -f "$SRC/COPYING.LGPLv2.1" ]] || die "no COPYING.LGPLv2.1 in $SRC
     Refusing to ship an LGPL binary with no licence text. If upstream really
     renamed or moved it, fix this script deliberately -- do not skip the file."
  install -m 0644 "$SRC/COPYING.LGPLv2.1" "$dir/COPYING.LGPLv2.1"
  ok "licence: COPYING.LGPLv2.1 (verbatim from the built source tree)"

  # LICENSE.md carries FFmpeg's per-component licence position. Expected, but
  # not worth blocking a release over if a future tarball drops it.
  if [[ -f "$SRC/LICENSE.md" ]]; then
    install -m 0644 "$SRC/LICENSE.md" "$dir/LICENSE.md"
    ok "licence: LICENSE.md (verbatim from the built source tree)"
  else
    warn "no LICENSE.md in $SRC -- shipping without it"
  fi

  write_build_notice "$dir"
}

# ---------------------------------------------------------------------------
# The gate. Defined early so --verify can reach it without building anything.
#
# Takes the directory to inspect, so the same code can vet a staging dir before
# it is promoted and vet vendor/ afterwards. Accumulates failures so one run
# reports everything wrong, not just the first thing.
# ---------------------------------------------------------------------------
run_gate() {
  local dir="${1:-$OUT_DIR}"
  local ffmpeg_bin="$dir/ffmpeg"
  local ffprobe_bin="$dir/ffprobe"
  local fails=0
  local bin

  say "HARD GATE ($dir)"

  # (a) both binaries exist, are executable, and actually run. ffprobe is easy
  #     to forget: the engine probes with it before it ever converts.
  for bin in "$ffmpeg_bin" "$ffprobe_bin"; do
    if [[ ! -x "$bin" ]]; then
      printf 'FAIL  not an executable file: %s\n' "$bin"; fails=1; continue
    fi
    if ! "$bin" -hide_banner -version >/dev/null 2>&1; then
      printf 'FAIL  will not run: %s -version\n' "$bin"; fails=1; continue
    fi
    ok "executable and runs: $(basename "$bin")"
  done
  # Nothing below can work if the binaries do not run.
  [[ "$fails" -eq 0 ]] || { printf '\ngate FAILED\n' >&2; return 1; }

  # (b) arch. A universal binary is not acceptable here: the app ships arm64
  #     only, and an x86_64 slice is dead weight in the DMG.
  for bin in "$ffmpeg_bin" "$ffprobe_bin"; do
    local archs
    archs="$(lipo -archs "$bin" 2>/dev/null | tr -s ' ' | sed 's/^ *//;s/ *$//')"
    if [[ "$archs" == "$TARGET_ARCH" ]]; then
      ok "$(basename "$bin"): lipo -archs = $archs"
    else
      printf 'FAIL  %s: lipo -archs = "%s", want exactly "%s"\n' \
        "$(basename "$bin")" "$archs" "$TARGET_ARCH"; fails=1
    fi
  done

  # (c) no non-system dynamic links. "Static" here does NOT mean zero dynamic
  #     links -- linking the macOS system libs and frameworks is correct and
  #     unavoidable. It means nothing outside the OS. A single /opt/homebrew
  #     reference makes the bundle work on this machine and fail on every
  #     user's, and that failure surfaces after the DMG has shipped.
  for bin in "$ffmpeg_bin" "$ffprobe_bin"; do
    local offenders
    offenders="$(otool -L "$bin" | tail -n +2 | awk '{print $1}' \
      | grep -vE '^/usr/lib/|^/System/' || true)"
    if [[ -n "$offenders" ]]; then
      printf 'FAIL  %s links non-system libraries:\n%s\n' "$(basename "$bin")" "$offenders"; fails=1
    else
      ok "$(basename "$bin"): links only /usr/lib and /System"
    fi
  done

  # (d) + (e) the configuration string: the licensing posture and the MP3
  #     capability are both recorded in it, and so is any build path the
  #     builder leaked. This is what catches a foreign binary imported through
  #     STREAMMAGPIE_FFMPEG_DIR.
  local cfg_line
  cfg_line="$("$ffmpeg_bin" -hide_banner -version | sed -n 's/^ *configuration: *//p')"
  if [[ -z "$cfg_line" ]]; then
    printf 'FAIL  ffmpeg -version printed no configuration line\n'; fails=1
  else
    if printf '%s' "$cfg_line" | grep -qF -- '--enable-libmp3lame'; then
      ok "configuration has --enable-libmp3lame (MP3 output is a shipped feature)"
    else
      printf 'FAIL  configuration lacks --enable-libmp3lame -- "Save as MP3" would fail at runtime\n'; fails=1
    fi
    local badflag
    for badflag in --enable-gpl --enable-nonfree; do
      if printf '%s' "$cfg_line" | grep -qF -- "$badflag"; then
        printf 'FAIL  configuration has %s -- StreamMagpie ships an LGPL build only\n' "$badflag"; fails=1
      else
        ok "configuration has no $badflag"
      fi
    done

    # A home directory in the configuration string means the shipped binary
    # prints somebody's machine layout to anyone who runs `ffmpeg -version`.
    # It is also the tell-tale of a binary borrowed from another project.
    local leak=""
    printf '%s' "$cfg_line" | grep -qE '/Users/|/home/' && leak="/Users/ or /home/"
    if [[ -n "${HOME:-}" && "${#HOME}" -gt 1 ]] && printf '%s' "$cfg_line" | grep -qF -- "$HOME"; then
      leak="\$HOME"
    fi
    if [[ -n "$leak" ]]; then
      printf 'FAIL  configuration string contains a build-machine home path (%s):\n      %s\n' "$leak" "$cfg_line"; fails=1
    else
      ok "configuration string contains no build-machine home path"
    fi
  fi

  # (f) the encoders packages/engine/src/argv.ts actually asks for. Matched
  #     against ffmpeg's own -encoders shape: a 6-char capability flag block,
  #     whitespace, then the encoder name.
  local encoders enc
  encoders="$("$ffmpeg_bin" -hide_banner -encoders 2>/dev/null || true)"
  for enc in "${REQUIRED_ENCODERS[@]}"; do
    if printf '%s\n' "$encoders" | grep -qE "^[[:space:]]*[A-Z.]{6}[[:space:]]+${enc}([[:space:]]|\$)"; then
      ok "encoder present: $enc"
    else
      printf 'FAIL  encoder MISSING: %s\n' "$enc"; fails=1
    fi
  done

  # (g) an encoder can be listed and still be broken. Actually encode a fifth
  #     of a second of silence to MP3 and probe the result. This is the single
  #     property the app is sold on, so prove it rather than infer it.
  local smoke_dir smoke_codec
  smoke_dir="$(mktemp -d)"
  if "$ffmpeg_bin" -hide_banner -nostdin -loglevel error \
       -f lavfi -i anullsrc=r=44100:cl=stereo -t 0.2 \
       -c:a libmp3lame -q:a 0 -f mp3 -y "$smoke_dir/smoke.mp3" >/dev/null 2>&1 \
     && [[ -s "$smoke_dir/smoke.mp3" ]]; then
    smoke_codec="$("$ffprobe_bin" -hide_banner -loglevel error \
      -select_streams a:0 -show_entries stream=codec_name \
      -of default=nw=1:nk=1 "$smoke_dir/smoke.mp3" 2>/dev/null || true)"
    if [[ "$smoke_codec" == "mp3" ]]; then
      ok "MP3 round-trip smoke: encoded and probed back as mp3"
    else
      printf 'FAIL  MP3 smoke produced a file ffprobe reads as "%s", not mp3\n' "$smoke_codec"; fails=1
    fi
  else
    printf 'FAIL  MP3 smoke: libmp3lame could not encode 0.2s of silence\n'; fails=1
  fi
  rm -rf "$smoke_dir"

  # (h) the licence payload ships alongside the binaries. electron-builder
  #     copies this directory into the .app unfiltered, so a file absent here
  #     is absent from every DMG we hand out -- and a silently missing licence
  #     is exactly the kind of thing nobody notices until it matters.
  local lf
  for lf in COPYING.LGPLv2.1 README.StreamMagpie.txt; do
    if [[ -s "$dir/$lf" ]]; then
      ok "licence file present: $lf"
    else
      printf 'FAIL  refusing to ship an LGPL binary with no licence text: %s is missing\n' "$lf"; fails=1
    fi
  done
  if [[ -s "$dir/LICENSE.md" ]]; then
    ok "licence file present: LICENSE.md"
  else
    warn "LICENSE.md absent (expected, but not fatal)"
  fi

  # (i) nothing else rides along. A README belonging to another application is
  #     a hard failure, not a cosmetic one: it would ship in the DMG and tell
  #     users this app is something it is not.
  local entry base
  for entry in "$dir"/README.*.txt; do
    [[ -e "$entry" ]] || continue
    base="$(basename "$entry")"
    if [[ "$base" != "README.StreamMagpie.txt" ]]; then
      printf 'FAIL  foreign source notice would ship in the DMG: %s\n' "$base"; fails=1
    fi
  done
  for entry in "$dir"/*; do
    [[ -e "$entry" ]] || continue
    base="$(basename "$entry")"
    case " ${MANAGED_FILES[*]} " in
      *" $base "*) continue ;;
    esac
    [[ "$base" == ".gitkeep" ]] && continue
    warn "unexpected file in the vendor directory (it WILL ship in the DMG): $base"
  done

  # Advisory only: a home path anywhere in the binary is worth knowing about,
  # but unlike the configuration string it can come from upstream sources and
  # is not grounds for blocking a release on its own.
  if command -v strings >/dev/null 2>&1 && [[ -n "${HOME:-}" && "${#HOME}" -gt 1 ]]; then
    if strings -a "$ffmpeg_bin" 2>/dev/null | grep -qF -- "$HOME"; then
      warn "the ffmpeg binary contains the string \"$HOME\" somewhere -- inspect before release"
    else
      ok "no build-machine home path anywhere in the ffmpeg binary"
    fi
  fi

  say "otool -L ffmpeg"
  otool -L "$ffmpeg_bin"

  if [[ "$fails" -ne 0 ]]; then
    printf '\ngate FAILED -- see FAIL lines above\n' >&2
    return 1
  fi
  printf '\ngate PASSED\n'
  return 0
}

# Replace the managed files in OUT_DIR with the ones in the staging dir. Only
# runs after the staging dir has passed the gate, so vendor/ never holds a
# payload we would refuse to ship.
promote() {
  local from="$1" f
  mkdir -p "$OUT_DIR"
  for f in "${MANAGED_FILES[@]}"; do
    rm -f "$OUT_DIR/$f"
    [[ -e "$from/$f" ]] || continue
    if [[ "$f" == "ffmpeg" || "$f" == "ffprobe" ]]; then
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
# 1. Escape hatch: import prebuilt binaries instead of building.
#
# This exists for the packager who already has a known-good LGPL+lame ffmpeg.
# It does NOT relax anything: the imported payload goes through the identical
# gate, and only the files we manage are copied, so a source notice belonging
# to some other application cannot follow the binaries into the DMG.
# ---------------------------------------------------------------------------
if [[ -n "$IMPORT_DIR" ]]; then
  say "import (STREAMMAGPIE_FFMPEG_DIR)"
  [[ -d "$IMPORT_DIR" ]] || die "STREAMMAGPIE_FFMPEG_DIR is not a directory: $IMPORT_DIR"
  for f in ffmpeg ffprobe; do
    [[ -x "$IMPORT_DIR/$f" ]] || die "no executable $f in $IMPORT_DIR"
  done

  mkdir -p "$WORK"
  rm -rf "$STAGE"
  mkdir -p "$STAGE"

  install -m 0755 "$IMPORT_DIR/ffmpeg"  "$STAGE/ffmpeg"
  install -m 0755 "$IMPORT_DIR/ffprobe" "$STAGE/ffprobe"
  ok "copied ffmpeg and ffprobe"

  if [[ -f "$IMPORT_DIR/COPYING.LGPLv2.1" ]]; then
    install -m 0644 "$IMPORT_DIR/COPYING.LGPLv2.1" "$STAGE/COPYING.LGPLv2.1"
    ok "copied COPYING.LGPLv2.1"
  else
    die "no COPYING.LGPLv2.1 in $IMPORT_DIR
     Refusing to ship an LGPL binary with no licence text. Put the licence next
     to the binaries in the source directory, verbatim from the FFmpeg tree
     they were built from."
  fi
  if [[ -f "$IMPORT_DIR/LICENSE.md" ]]; then
    install -m 0644 "$IMPORT_DIR/LICENSE.md" "$STAGE/LICENSE.md"
    ok "copied LICENSE.md"
  else
    warn "no LICENSE.md in $IMPORT_DIR -- importing without it"
  fi
  # Deliberately nothing else. Any README.<otherapp>.txt, dylib, config or
  # stray build artefact in the source directory stays where it is.
  step "not copying anything else from $IMPORT_DIR (by design)"

  write_import_notice "$STAGE"

  run_gate "$STAGE" || die "the imported binaries did not pass the gate; vendor/ was left untouched.
     This is the escape hatch working as intended. A build lacking libmp3lame,
     or one whose configuration string names another machine or project, must
     not be vendored -- rerun without STREAMMAGPIE_FFMPEG_DIR to build from
     the pinned sources instead."

  promote "$STAGE"
  say "summary"
  printf '%-10s %s\n' "source" "imported from $IMPORT_DIR"
  printf '%-10s %s\n' "output" "$OUT_DIR"
  exit 0
fi

# ---------------------------------------------------------------------------
# 2. Preflight
# ---------------------------------------------------------------------------
say "preflight"

host_arch="$(uname -m)"
[[ "$host_arch" == "arm64" ]] || die "this script builds an arm64 binary natively; host reports '$host_arch'"
ok "host arch: $host_arch"

xcode-select -p >/dev/null 2>&1 || die "no Xcode command line tools (xcode-select --install)"
ok "toolchain: $(clang --version | head -1)"

for tool in curl tar make clang shasum otool lipo install; do
  command -v "$tool" >/dev/null 2>&1 || die "required tool not found on PATH: $tool"
done
ok "required tools present"

# nasm only matters for x86 assembly; an arm64 build assembles NEON with clang.
# pkg-config is deliberately blinded in section 5 and is not needed for
# libmp3lame, which ffmpeg detects with a plain link test. Both are noted, not
# installed -- this script never runs `brew install` on someone else's machine.
for optional in nasm pkg-config; do
  command -v "$optional" >/dev/null 2>&1 \
    || warn "$optional not found -- not needed for this arm64, libmp3lame-only build"
done

# The ffmpeg build tree with static libs runs ~1.5-2 GB. Fail early rather than
# 30 minutes in with a confusing linker error.
avail_kb="$(df -k "$HOME" | tail -1 | awk '{print $4}')"
avail_gb=$(( avail_kb / 1024 / 1024 ))
if (( avail_gb < 3 )); then
  die "only ${avail_gb} GiB free on the home volume; an ffmpeg build tree needs ~2 GB"
fi
(( avail_gb >= 6 )) || warn "only ${avail_gb} GiB free -- this build wants ~2 GB of it"
ok "free space: ${avail_gb} GiB"

mkdir -p "$WORK" "$OUT_DIR"
ok "work dir: $WORK"
ok "output  : $OUT_DIR"

# Fast path: an existing build that still passes the gate is left alone.
if [[ "$FORCE" -eq 0 && -x "$OUT_DIR/ffmpeg" && -x "$OUT_DIR/ffprobe" ]]; then
  skip "binaries already present -- verifying instead of rebuilding (--force to rebuild)"
  # Refresh the licence payload when the source tree is still around, so a
  # vendor dir populated before these files existed heals on the next run
  # instead of failing the gate forever with no way forward but --force.
  if [[ -f "$SRC/COPYING.LGPLv2.1" ]]; then install_licences_from_source "$OUT_DIR"; fi
  run_gate "$OUT_DIR"
  exit $?
fi

if [[ "$FORCE" -eq 1 ]]; then
  step "--force: discarding previous source trees and outputs"
  rm -rf "$SRC" "$LAME_SRC" "$STAGE"
  for f in "${MANAGED_FILES[@]}"; do rm -f "$OUT_DIR/$f"; done
fi

# ---------------------------------------------------------------------------
# 3. Fetch + verify both release tarballs
# ---------------------------------------------------------------------------
say "source tarballs"
fetch_verified "$LAME_URL"   "$LAME_SHA256"   "$LAME_TARBALL"   "lame-${LAME_VERSION}.tar.gz"
fetch_verified "$FFMPEG_URL" "$FFMPEG_SHA256" "$FFMPEG_TARBALL" "ffmpeg-${FFMPEG_VERSION}.tar.xz"

# ---------------------------------------------------------------------------
# 4. Extract
# ---------------------------------------------------------------------------
say "extract"
if [[ -f "$LAME_SRC/configure" ]]; then
  skip "lame source tree already extracted at $LAME_SRC"
else
  step "extracting lame into $WORK"
  rm -rf "$LAME_SRC"
  tar -xzf "$LAME_TARBALL" -C "$WORK"
  [[ -f "$LAME_SRC/configure" ]] || die "extract produced no configure script at $LAME_SRC"
  ok "lame extracted"
fi

if [[ -f "$SRC/configure" ]]; then
  skip "ffmpeg source tree already extracted at $SRC"
else
  step "extracting ffmpeg into $WORK"
  rm -rf "$SRC"
  tar -xJf "$FFMPEG_TARBALL" -C "$WORK"
  [[ -f "$SRC/configure" ]] || die "extract produced no configure script at $SRC"
  ok "ffmpeg extracted"
fi

# ---------------------------------------------------------------------------
# 5. Build LAME into a staging prefix inside the ffmpeg source tree
#
# Static only, library only. The environment is scrubbed for the same reason it
# is scrubbed for ffmpeg: a Homebrew-flavoured shell profile exporting
# -I/opt/homebrew/include is enough to make the result unshippable.
# ---------------------------------------------------------------------------
say "build lame $LAME_VERSION"
if [[ -f "$LAME_PREFIX/lib/libmp3lame.a" ]]; then
  skip "libmp3lame.a already staged at $LAME_PREFIX/lib"
else
  step "configure + make lame (output -> $BUILD_LOG)"
  (
    cd "$LAME_SRC"
    env -u CXXFLAGS -u CPPFLAGS -u LDFLAGS -u PKG_CONFIG_PATH \
        CFLAGS="$LAME_CFLAGS" \
        ./configure "${LAME_CONFIGURE_FLAGS[@]}"
    make -j"$JOBS"
    make install
  ) > "$BUILD_LOG" 2>&1 || {
    printf '\n--- last 40 lines of %s ---\n' "$BUILD_LOG" >&2
    tail -40 "$BUILD_LOG" >&2
    die "lame build failed"
  }
  [[ -f "$LAME_PREFIX/lib/libmp3lame.a" ]] \
    || die "lame installed but produced no static libmp3lame.a in $LAME_PREFIX/lib"
  ok "libmp3lame.a staged at $LAME_STAGE_REL/lib (relative to the ffmpeg source tree)"
fi

# ---------------------------------------------------------------------------
# 6. Configure ffmpeg
#
# Two hostile things are neutralised here, both of which would otherwise show
# up as a gate (c) failure after a long build:
#
#   * pkg-config is pointed at an empty directory. Left alone it happily finds
#     Homebrew .pc files and ffmpeg links whatever it discovers.
#   * CFLAGS/LDFLAGS/etc are cleared, since a Homebrew-ish shell profile
#     exporting -I/opt/homebrew/include is enough to poison the build.
#
# The flag list itself is CONFIGURE_FLAGS, defined in section 0 and explained
# there.
# ---------------------------------------------------------------------------
say "configure ffmpeg $FFMPEG_VERSION"

# A stamp lets a re-run skip a configure that already ran with these exact
# flags, while still reconfiguring if anyone edits the list above.
STAMP="$SRC/.streammagpie-configure-stamp"
STAMP_WANT="$FFMPEG_VERSION $LAME_VERSION ${CONFIGURE_FLAGS[*]}"

mkdir -p "$WORK/pkgconfig-empty"

if [[ -f "$SRC/ffbuild/config.mak" && -f "$STAMP" ]] && [[ "$(cat "$STAMP")" == "$STAMP_WANT" ]]; then
  skip "already configured with these exact flags"
else
  step "running configure (${#CONFIGURE_FLAGS[@]} flags)"
  (
    cd "$SRC"
    env -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS -u PKG_CONFIG_PATH \
        PKG_CONFIG_LIBDIR="$WORK/pkgconfig-empty" \
        ./configure "${CONFIGURE_FLAGS[@]}"
  ) || die "configure failed -- see $SRC/ffbuild/config.log
     If it reports 'libmp3lame >= 3.98.3 not found', the LAME staging prefix in
     section 5 did not produce $LAME_STAGE_REL/lib/libmp3lame.a."
  printf '%s' "$STAMP_WANT" > "$STAMP"
  ok "configured"
fi

# Cheap, load-bearing pre-build check: if configure did not turn libmp3lame on,
# MP3 output cannot possibly work and there is no reason to spend half an hour
# finding that out. config.mak marks a disabled feature by prefixing the key
# with '!', so an anchored match on the bare key is the positive signal.
grep -qE "^CONFIG_LIBMP3LAME=yes\$" "$SRC/ffbuild/config.mak" \
  || die "configure did NOT enable libmp3lame -- MP3 output would fail at runtime.
     Inspect $SRC/ffbuild/config.log"
ok "configure enabled libmp3lame"

# The same check from the other direction: refuse to spend the build time on a
# tree that has somehow been configured GPL.
if grep -qE "^CONFIG_GPL=yes\$" "$SRC/ffbuild/config.mak"; then
  die "configure enabled GPL -- StreamMagpie ships an LGPL build only.
     Something added --enable-gpl to CONFIGURE_FLAGS; that is a licensing
     decision, not a build tweak."
fi
ok "configure did not enable GPL"

# ---------------------------------------------------------------------------
# 7. Build, then take only the two binaries.
#
# Deliberately no `make install`: that would also deposit ~200 MB of static
# libs, headers and .pc files we never ship. We want exactly two files.
# ---------------------------------------------------------------------------
say "build ffmpeg"
step "make -j$JOBS  (this takes a while; full output -> $BUILD_LOG)"
(
  cd "$SRC"
  make -j"$JOBS"
) > "$BUILD_LOG" 2>&1 || {
  printf '\n--- last 40 lines of %s ---\n' "$BUILD_LOG" >&2
  tail -40 "$BUILD_LOG" >&2
  die "make failed"
}
ok "make completed"

# ---------------------------------------------------------------------------
# 8. Stage, gate, promote
# ---------------------------------------------------------------------------
say "stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
for bin in ffmpeg ffprobe; do
  [[ -f "$SRC/$bin" ]] || die "build produced no $bin in $SRC"
  install -m 0755 "$SRC/$bin" "$STAGE/$bin"
  ok "staged $bin ($(du -h "$STAGE/$bin" | awk '{print $1}'))"
done

# The binaries never ship alone: LGPL v2.1 requires the licence text and a
# corresponding-source notice travel with them.
install_licences_from_source "$STAGE"

run_gate "$STAGE" || die "the freshly built binaries did not pass the gate; vendor/ was left untouched"
promote "$STAGE"

# ---------------------------------------------------------------------------
# 9. Summary
# ---------------------------------------------------------------------------
say "summary"
printf '%-10s %s\n' "ffmpeg" "$FFMPEG_VERSION"
printf '%-10s %s\n' "lame" "$LAME_VERSION (static libmp3lame)"
printf '%-10s %s\n' "arch" "$TARGET_ARCH"
printf '%-10s %s\n' "licence" "LGPL (libmp3lame is LGPL v2; no --enable-gpl)"
printf '%-10s %s\n' "output" "$OUT_DIR"
echo
printf '  %-26s %8s  %s\n' "FILE" "SIZE" "ROLE"
printf '  %-26s %8s  %s\n' "ffmpeg"  "$(du -h "$OUT_DIR/ffmpeg"  | awk '{print $1}')" "binary"
printf '  %-26s %8s  %s\n' "ffprobe" "$(du -h "$OUT_DIR/ffprobe" | awk '{print $1}')" "binary"
for lf in COPYING.LGPLv2.1 LICENSE.md README.StreamMagpie.txt; do
  [[ -f "$OUT_DIR/$lf" ]] || continue
  printf '  %-26s %8s  %s\n' "$lf" "$(du -h "$OUT_DIR/$lf" | awk '{print $1}')" "licence"
done
echo
echo "vendor/ is gitignored -- these are build artifacts, not source."
echo "All files above ship in the app bundle; the licence files are required."
exit 0
