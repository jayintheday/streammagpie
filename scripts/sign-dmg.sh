#!/usr/bin/env bash
#
# sign-dmg.sh — sign, notarize and staple a StreamMagpie disk image.
#
# THE ORDER IS LOAD-BEARING: sign -> notarize -> staple.
#   Signing a stapled DMG invalidates the ticket, so a re-sign after stapling
#   silently ships an image Gatekeeper will re-check online (and reject when
#   offline). Notarizing before signing fails outright. Stapling before the
#   ticket exists fails too. If you only remember one thing about this file,
#   remember that these three steps never get reordered.
#
# electron-builder has already signed and notarized the .app INSIDE the image.
# This step signs and notarizes the image itself, which is what the user
# actually downloads and what Gatekeeper checks on first open.
#
# Usage:
#   bash scripts/sign-dmg.sh                                  # find the DMG automatically
#   bash scripts/sign-dmg.sh path/to/StreamMagpie-1.2.3-arm64.dmg
#
# Env overrides:
#   CSC_FULL_NAME             signing identity (default below)
#   APPLE_KEYCHAIN_PROFILE    notarytool keychain profile (default: streammagpie)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RELEASE_DIR="$ROOT/packages/app/release"

# ⚠ TWO DIFFERENT SPELLINGS OF THE SAME IDENTITY. They are not interchangeable.
#
#   raw codesign (this script)   "Developer ID Application: Intheday Ltd (29UYFH4USR)"
#   electron-builder CSC_NAME    "Intheday Ltd (29UYFH4USR)"
#
# codesign --sign wants the certificate's full common name, prefix included.
# electron-builder prepends "Developer ID Application: " itself, so giving it
# the prefixed form yields a doubled prefix and a "no identity found" failure.
# packages/app/electron-builder.yml carries the same warning from its side.
#
# The team ID is published in every signed build we ship, so it is not a secret.
ID="${CSC_FULL_NAME:-Developer ID Application: Intheday Ltd (29UYFH4USR)}"
PROFILE="${APPLE_KEYCHAIN_PROFILE:-streammagpie}"

say()  { printf '\n==== %s ====\n' "$*"; }
step() { printf '....  %s\n' "$*"; }
ok()   { printf 'OK    %s\n' "$*"; }
warn() { printf 'WARN  %s\n' "$*"; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 0. Locate the disk image
#
# The artifact name comes from productName in packages/app/electron-builder.yml
# and is always StreamMagpie-<version>-arm64.dmg. With no argument, find it.
# ---------------------------------------------------------------------------
usage() {
  sed -n '3,29p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

DMG="${1:-}"

case "$DMG" in
  -h|--help) usage; exit 0 ;;
  -*) die "unknown argument: $DMG (pass a path to a .dmg, or nothing to auto-detect)" ;;
esac

if [[ -z "$DMG" ]]; then
  matches=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && matches+=("$line")
  done < <(ls -1 "$RELEASE_DIR"/StreamMagpie-*-arm64.dmg 2>/dev/null || true)

  case "${#matches[@]}" in
    0) die "no StreamMagpie-*-arm64.dmg in $RELEASE_DIR
     Build one first (npm run dist:dmg -w packages/app), or pass a path:
       bash scripts/sign-dmg.sh path/to/StreamMagpie-<version>-arm64.dmg" ;;
    1) DMG="${matches[0]}"
       ok "found $(basename "$DMG")" ;;
    *) printf 'ERROR: %s\n' "more than one StreamMagpie-*-arm64.dmg in $RELEASE_DIR:" >&2
       printf '       %s\n' "${matches[@]}" >&2
       die "pass the one you mean as an argument" ;;
  esac
fi

[[ -f "$DMG" ]] || die "not a file: $DMG"
DMG="$(cd "$(dirname "$DMG")" && pwd)/$(basename "$DMG")"

case "$(basename "$DMG")" in
  StreamMagpie-*-arm64.dmg) ok "artifact name matches StreamMagpie-<version>-arm64.dmg" ;;
  *.dmg) warn "expected a name of the form StreamMagpie-<version>-arm64.dmg, got $(basename "$DMG")
      That name comes from productName in packages/app/electron-builder.yml.
      Continuing, but check you are signing the artifact you meant to ship." ;;
  *) die "not a disk image: $DMG" ;;
esac

# ---------------------------------------------------------------------------
# 1. Preflight
# ---------------------------------------------------------------------------
say "preflight"

command -v codesign >/dev/null 2>&1 || die "codesign not found (install the Xcode command line tools)"
command -v xcrun    >/dev/null 2>&1 || die "xcrun not found (install the Xcode command line tools)"
xcrun notarytool --version >/dev/null 2>&1 \
  || die "xcrun notarytool is unavailable -- it needs Xcode 13 or newer"

if ! security find-identity -v -p codesigning 2>/dev/null | grep -qF "$ID"; then
  die "signing identity not found in any unlocked keychain:
       $ID
     List what you do have with:
       security find-identity -v -p codesigning
     Override with CSC_FULL_NAME if your certificate's common name differs.
     Note this is the PREFIXED spelling; electron-builder's CSC_NAME is the
     unprefixed one. See the comment at the top of this script."
fi
ok "signing identity: $ID"

ok "notarytool keychain profile: $PROFILE"
step "if notarization fails on credentials, recreate the profile with:"
step "  xcrun notarytool store-credentials $PROFILE \\"
step "    --key ~/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8 \\"
step "    --key-id XXXXXXXXXX --issuer <issuer-uuid>"
step "⚠ an App Store Connect API key, NOT an app-specific password: every"
step "  app-specific password on this account was revoked on 2026-08-23."

# ---------------------------------------------------------------------------
# 2. Sign
# ---------------------------------------------------------------------------
say "sign"
step "codesign $(basename "$DMG")"
codesign --sign "$ID" --timestamp --force "$DMG" \
  || die "codesign failed.
     The commonest causes are a locked keychain (unlock it in Keychain Access)
     and no network access for the secure timestamp (--timestamp requires it)."
codesign --verify --strict --verbose=2 "$DMG" 2>&1 | sed 's/^/      /'
ok "signed"

# ---------------------------------------------------------------------------
# 3. Notarize
#
# --wait blocks until Apple returns a verdict. A submission that comes back
# anything other than Accepted must stop the release here: stapling would fail
# anyway, and shipping an unnotarized DMG produces the "damaged and can't be
# opened" dialog on the user's machine.
# ---------------------------------------------------------------------------
say "notarize"
step "xcrun notarytool submit --wait (this takes a few minutes)"

set +e
submit_out="$(xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait 2>&1)"
submit_rc=$?
set -e
printf '%s\n' "$submit_out" | sed 's/^/      /'

submit_id="$(printf '%s\n' "$submit_out" | sed -nE 's/^[[:space:]]*id:[[:space:]]*([0-9a-fA-F-]{36}).*/\1/p' | head -1)"

if [[ "$submit_rc" -ne 0 ]] || ! printf '%s' "$submit_out" | grep -qE 'status:[[:space:]]*Accepted'; then
  printf 'ERROR: notarization did not come back Accepted.\n' >&2
  if [[ -n "$submit_id" ]]; then
    printf '     Read Apple'"'"'s reasons with:\n' >&2
    printf '       xcrun notarytool log %s --keychain-profile %s\n' "$submit_id" "$PROFILE" >&2
  else
    printf '     No submission id was returned, which usually means the credentials\n' >&2
    printf '     failed rather than the payload. Check the keychain profile "%s".\n' "$PROFILE" >&2
  fi
  printf '     The DMG is signed but NOT notarized -- do not ship it.\n' >&2
  exit 1
fi
ok "notarized (submission ${submit_id:-unknown})"

# ---------------------------------------------------------------------------
# 4. Staple
#
# Stapling attaches the ticket to the image so Gatekeeper can validate it with
# no network. Skipping it "works" on the build machine, which is exactly why it
# gets skipped and then fails for a user on a plane.
# ---------------------------------------------------------------------------
say "staple"
xcrun stapler staple "$DMG" \
  || die "stapler failed even though notarization was Accepted.
     Apple's ticket can take a minute to become fetchable; wait and re-run:
       xcrun stapler staple \"$DMG\""
ok "stapled"

# ---------------------------------------------------------------------------
# 5. Verify what we are about to hand to users
#
# Everything above reports on what we did. This reports on what the artifact
# now IS, which is the only thing the user experiences.
# ---------------------------------------------------------------------------
say "verify"

fails=0

if xcrun stapler validate "$DMG" >/dev/null 2>&1; then
  ok "stapler validate: ticket is attached and valid"
else
  printf 'FAIL  stapler validate rejected the image\n'; fails=1
fi

if codesign --verify --strict --verbose=2 "$DMG" >/dev/null 2>&1; then
  ok "codesign --verify --strict: signature intact"
else
  printf 'FAIL  codesign --verify --strict rejected the image\n'; fails=1
fi

# The check Gatekeeper itself performs when the user double-clicks the download.
spctl_out="$(spctl -a -t open --context context:primary-signature -v "$DMG" 2>&1 || true)"
printf '%s\n' "$spctl_out" | sed 's/^/      /'
if printf '%s' "$spctl_out" | grep -q 'accepted'; then
  ok "spctl: Gatekeeper accepts this image"
else
  printf 'FAIL  spctl did not accept the image -- users would see a Gatekeeper warning\n'; fails=1
fi

if [[ "$fails" -ne 0 ]]; then
  printf '\nverification FAILED -- do not ship this DMG\n' >&2
  exit 1
fi

say "done"
printf '%s\n' "$DMG"
echo
# ⚠ THESE TWO REMINDER LINES CONTAIN THE LITERAL STRINGS THE GATE GREPS FOR.
# If this script's output is teed into the SAME file as the electron-builder
# build log, both must-be-0 greps become 1 and the gate reports a failure that
# is really just this reminder quoting itself. Keep the logs separate:
#   npm run dist:dmg   2>&1 | tee /tmp/streammagpie-build.log
#   bash scripts/sign-dmg.sh "$DMG" 2>&1 | tee /tmp/streammagpie-sign.log
# There is no way to name a pattern without containing it, so separation is the
# rule rather than some cleverer quoting. Found 2026-08-24 during the 0.1.2 run.
echo "Before uploading, grep the BUILD log (not this script's output) for:"
echo "  skipped macOS notarization   (want 0 hits -- the .app inside must be notarized too)"
echo "  file source doesn't exist    (want 0 hits -- a missing vendor/ helper fails OPEN)"
echo
echo "⚠ Do NOT tee this script into that same log: the two lines above would"
echo "  themselves become hits and flip both gates from 0 to 1."
echo
echo "Official builds are distributed through Gumroad only, never as a GitHub"
echo "Release asset."
exit 0
