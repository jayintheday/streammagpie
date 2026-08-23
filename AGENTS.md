# StreamMagpie — working agreement

> Read this file in full before writing anything. Then
> [`docs/DISTRIBUTION.md`](docs/DISTRIBUTION.md) before touching packaging, and
> [`docs/licensing.md`](docs/licensing.md) before touching anything under
> `vendor/` or `scripts/`. This repo bundles more third-party code than it
> writes, and both of those documents describe obligations rather than
> preferences.

## What StreamMagpie is

A macOS app that turns a YouTube URL into an audio file on the user's own Mac:
paste a link, pick m4a, MP3 or ALAC, get a file. Everything runs locally — a
bundled yt-dlp wheel on a bundled CPython, a bundled LGPL static ffmpeg, and a
bundled JS runtime for signature solving — so nothing is uploaded, no account
exists, and there is no server to go down. A sibling app alongside Cast Gorilla.
Pay once through Gumroad. MIT source is public; the official notarized DMG is
sold.

**Stack: an Electron shell over a pure-TypeScript engine that builds yt-dlp
argv and parses its output.** The engine spawns yt-dlp per job and it exits;
nothing resident, no daemon, no background fetching.

**What we are not building** (v1):

- **No Mac App Store.** App Review guideline 5.2.3 rules out an app whose
  purpose is downloading from a third-party media service. Direct distribution
  is not a stage we are at; it is the only channel this product can have.
- **No video.** Audio out only. The yt-dlp flags exist and we do not expose
  them.
- **No playlist or channel batch manager, and no multi-item queue.** A mixed URL
  (`list=` plus a video id) saves **this track** only, deliberately.
- **No cookie import, no in-app sign-in, no PO-token provider plugins** — see
  [`docs/DEFERRED.md`](docs/DEFERRED.md), where they sit at the far end of the
  reliability ladder.
- **No proxy rotation, IP cycling or fingerprint randomisation. Ever.** That is
  the wrong side of the line: it turns a grey-area consumer utility into
  something built for evasion, and it is unnecessary — a residential IP at human
  request rates covers the realistic failure modes. This one is not deferred; it
  is refused.
- **No in-app updater for the app binary.** Gumroad re-download is the app
  channel. The *extractor* updates itself; the app does not.

---

## Identity constants, never to move

| Constant | Value |
|---|---|
| appId | `co.streammagpie.app` |
| productName | `StreamMagpie` |
| Minimum macOS | 14 |
| Architecture | arm64 only |
| Signing identity | supplied at build time via `CSC_NAME` |
| Keychain profile | `streammagpie` |
| Artifact | `packages/app/release/StreamMagpie-$V-arm64.dmg` |
| Version, source of truth | `packages/app/package.json` |

**`co.streammagpie.app` is the TCC and Gatekeeper identity.** The folder-access
grants the app asks for — Downloads, Desktop, Documents, whichever the user
picks as a save location — are recorded by macOS against that bundle
identifier, and so is the notarization ticket. **Changing it orphans every one
of them**: the user's existing permission stays attached to an app that no
longer exists, and the renamed one appears unpermitted with no explanation.
It is not a string to tidy, prefix, namespace, or align with anything. It never
changes. The shipped bundle carries it: `codesign` on the signed, notarized
`.app` reports `Identifier=co.streammagpie.app`. `[verified: run 2026-08-23]`
The *consequence* of changing it is still **[inferred]** — reasoned from the TCC
model and the usage-description keys in `extendInfo`. No folder grant has been
asked for yet, because the app's save flow has not been exercised through its
own UI.

**The signing identity is not committed.** `packages/app/electron-builder.yml`
carries no `mac.identity` key; official builds pass it in the environment as
`CSC_NAME="Intheday Ltd (29UYFH4USR)"`, and a contributor without that
certificate either lets electron-builder auto-discover their own or sets
`CSC_IDENTITY_AUTO_DISCOVERY=false` for an unsigned local build.
`[verified: source — electron-builder.yml has the comment and no identity key]`

**The identity has two spellings and the tools disagree.** `CSC_NAME` takes the
**bare** qualifier `Intheday Ltd (29UYFH4USR)`; raw `codesign` takes it
**prefixed**, `Developer ID Application: Intheday Ltd (29UYFH4USR)`. Each fails
unhelpfully when handed the other's form. `scripts/sign-dmg.sh` defaults to the
prefixed form for exactly this reason. Comment the inversion wherever both
appear.

`productName` is **StreamMagpie**, one capital M in the middle. Prose, titles,
UI strings and document headings use that spelling. Lowercase `streammagpie`
is an identifier, not the brand, and stays lowercase where it already is: the
npm package names, `co.streammagpie.app`, the `STREAMMAGPIE_*` environment
variables, the keychain profile, `window.streammagpie`.

---

## Distribution policy

Full protocol: [`docs/DISTRIBUTION.md`](docs/DISTRIBUTION.md). The short form,
which binds every agent:

- **DMGs go to Gumroad. Only Gumroad.** Never a GitHub Release asset, never
  public CI, never any channel that serves a signed build for free. Source is
  public (MIT); binaries are not.
- Tags for source milestones are fine, with **zero** release assets.
- **The one carve-out, and it is deliberate:** `yt_dlp-*.whl`,
  `extractor-manifest.json` and the manifest's signature **may** be published on
  this repo's GitHub Releases. That is how a shipped app survives YouTube
  changing extraction without waiting for a new DMG. **Those three files are
  extractor data, not the product.** Nothing else joins them — not a `.dmg`, not
  a zipped `.app`, not a "debug build".
- **Notary credentials stay in the local keychain profile `streammagpie`** (team
  `29UYFH4USR`). Never commit Apple IDs, app-specific passwords or API keys.
  Check the profile without submitting anything:
  `xcrun notarytool history --keychain-profile streammagpie`.
- **Never commit real video titles, channel names, watch URLs, or anybody's
  download history** — not in docs, not in tests, not in commit messages, not in
  issue text. A list of what someone converted is a list of what they watch.
  **Characteristics only**: duration, container, codec, itag, bitrate, file
  size, wall-clock time, exit code. Specifics go in a gitignored
  `NOTES.local.md`.
  - The one URL in the repo is `scripts/extractor-smoke.sh`'s default,
    `jNQXAC9IVRw` — the first video ever uploaded to YouTube, a public landmark
    chosen precisely because it is nobody's private taste. Do not replace it
    with something from your own history, and do not add a second one.

---

## How we work

**All implementation code is written by Opus subagents.** The orchestrating
session is manager and reviewer only: it briefs agents, reviews diffs, runs
verification, and commits. It does not patch product code — one-line throwaway
diagnostics during live debugging are the only tolerated exception, disclosed
and cleaned up.

- Concurrent agents get **non-overlapping path scopes, stated in the brief**.
  The scope is the whole of the contract: a file outside it is not yours to fix
  even when the fix is obvious. Report it instead.
- **No `npm install` unless the brief allows it** — single install, single
  lockfile write. A lockfile written by two agents at once is a merge conflict
  in a generated file.
- Tests are vitest, named `<area>-*.test.ts` under `packages/*/test/`. The suite
  stays green.

### Marking claims

Every claim in a document, a commit message or a report carries how it is known:

| Mark | Means |
|---|---|
| `[verified: run]` | A command was run and this is its output |
| `[verified: source]` | Read in the source, quoted accurately |
| `[verified: launching]` | The app or binary was launched and observed |
| `[inferred]` | Reasoned, not checked |

**An inferred claim that reads like a verified one costs somebody a day.** It
matters unusually much here, for two reasons. Exactly one build has been
packaged, signed, notarized, stapled and launched — 2026-08-23 — so a statement
about the shipped app is either a claim about that single dated artefact or an
inference, and the difference is not decoration. And the half that *can*
be run is time-sensitive: a client chain that extracted audio last week can be
dead today, so "it works" without a date is not a claim, it is a mood. Date the
runs.

### Emoji, ruled once

Zero emoji in anything user-facing: UI strings, error sentences, dialog copy,
log lines a user might be shown. That is the suite rule and it is absolute.
In **code comments and internal docs**, the warning sign (U+26A0) is permitted
as a callout marker — Cast Gorilla uses it that way and this repo inherits the
convention. Nothing else.

### Committing

**Agents commit at sensible intervals to save progress.** A sensible interval is
a coherent unit of work that leaves the gate green — a module plus its tests, a
bug plus its regression test, a document plus the reference that made it
necessary. Not every file save, and not one enormous commit at the end.

Three conditions on every commit:

1. **The gate passes.** Never commit a red suite to save progress; branch or
   stash instead.
2. **Say what is unverified.** If a claim rests on something not yet run — a
   packaged build, a live extraction, a notarization — the message says so.
3. **Never commit** video titles, channel names, watch URLs, download history,
   build output, `vendor/*` contents, `.dmg` files, or Apple credentials.

#### Concurrent agents must use pathspec-limited commits

`git add <my paths>` followed by a bare `git commit` **does not commit only your
paths. It commits the whole index** — including anything a concurrently running
agent has already staged. A sibling repo found this the hard way: an agent
scoped to the backend swept another agent's staged deletion of a stylesheet into
its own commit, having correctly `git add`ed only its own files.

So the commit itself carries the scope, not the `add`:

```bash
git commit -m "…" -- packages/engine packages/app   # commits ONLY these paths
git add packages/engine && git commit               # commits whatever else is staged too
```

Note the argument order: `-m` comes **before** the `--` separator. Anything
after `--` is a pathspec, so `git commit -- <paths> -m "…"` makes git look for a
file called `-m`.

⚠ **AND THE PATHSPEC FORM HAS ITS OWN DOOR, WHICH IS THIS ADVICE INVERTED. A
PATHSPEC COMMIT RECORDS THE WORKING TREE FOR THOSE PATHS, NOT THE INDEX.** So on
a file you have staged only PART of, `git commit -- <that file>` commits the
whole file as it currently sits on disk — including hunks you deliberately left
unstaged, and including another agent's unstaged edits if you share the file.
In the sibling repo an agent staged four stylesheet hunks totalling 84 lines and
the commit landed **293**.

**So the two forms are for two situations and neither is universally right:**

```bash
# every file you touch is wholly yours -> pathspec, as above
git commit -m "…" -- packages/engine

# you share a file and staged only your hunks -> stage, ASSERT, then bare commit
git add -p packages/app/src/renderer/main.ts
git diff --cached --name-only          # must list exactly your files, and no others
git commit -m "…"
```

**The invariant, either way: `git show --stat HEAD` immediately after, and read
the line count.** A scope leak is invisible in the diff you were reading, and it
is invisible in the `git add` you were careful about.

**Recovery, if it has already happened:** `git reset --soft HEAD~1`, then
recommit with the pathspec. That leaves the other agent's staging exactly as
they left it. Check with `git show --name-only HEAD` before moving on.

Because `docs/` holds files several agents have reason to touch, **no agent uses
`docs/` as a pathspec** — name the document files.

Pushing, tagging and releasing stay with the orchestrator.

---

## The gate

```bash
npx tsc -b && npm run typecheck -w packages/app && npm test
```

**Note the trap inherited from Cast Gorilla: the root `tsc -b` does NOT cover
`packages/app`.** The app's tsconfig targets DOM plus a bundler resolution mode,
which cannot join a NodeNext project-references graph, so the root graph covers
`packages/engine` only. `tsc -b` therefore **reports success while the app is
entirely unchecked** — a green-looking gate that has not looked at the Electron
half of the product. The app leg is a separate command, permanently. Do not
"simplify" the gate to one command; it has been two on purpose since the first
sibling repo hit this.

Run all three legs before every commit. `npm test` is `vitest run` at the root
and covers both workspaces.

---

## Layout

| | |
|---|---|
| App | `packages/app` — the Electron shell: URL entry, format choice, progress, save location, the extractor updater's host side. **Carries the product version.** |
| Engine | `packages/engine` — yt-dlp argv building, client-chain policy, progress-line parsing, ffprobe metadata, the extractor manifest reader and wheel swap. **Zero Electron, zero DOM.** It is a pure function library over strings and child processes, which is what makes it testable without a window. |
| Scripts | `scripts/` — `build-ffmpeg.sh`, `vendor-python.sh`, `vendor-js.sh`, `vendor-ytdlp.sh` fill `vendor/`; `sign-dmg.sh` signs, notarizes and staples; `extractor-smoke.sh` proves a yt-dlp version still extracts. |
| Vendor | `vendor/ffmpeg/arm64`, `vendor/python/arm64`, `vendor/js`, `vendor/ytdlp` — **tracked directories, ignored contents.** electron-builder's `extraResources` names these exact paths, so the directories must exist in a fresh clone; everything inside them is a build product or a download and **none of it is in git**, floor wheel included. `git ls-files vendor/` returns four `.gitkeep` files and nothing else. `[verified: run 2026-08-22]` |
| Docs | `docs/` — see below. |

| Document | |
|---|---|
| [`docs/DISTRIBUTION.md`](docs/DISTRIBUTION.md) | Where builds go, where they never go, and the ship checklist. |
| [`docs/licensing.md`](docs/licensing.md) | The LGPL boundary, the other four upstream licences, and the per-release compliance checklist. |
| [`docs/EULA.md`](docs/EULA.md) | Terms of sale for the paid DMG. The copy of record for the Gumroad listing. |
| [`docs/DEFERRED.md`](docs/DEFERRED.md) | What is deliberately not in the first shippable MVP. |
| `docs/extractor-manifest.example.json` | The shape the updater parses. |

Two structural facts that are easy to break and expensive to debug:

⚠ **`helper-paths.ts` must be imported FIRST in `packages/app/src/main/index.ts`.**
It sets the `STREAMMAGPIE_*` environment variables that point at the bundled
ffmpeg, CPython, JS runtime and floor wheel, and it does so at module load. Any
module that reads those variables at import time — directly or through the
engine — and is imported ahead of it sees a packaged app with no Homebrew on
`PATH` and nothing to fall back to. The failure is a "Python not found" on a
machine that obviously has Python. `[verified: source]`

⚠ **There are two yt-dlp wheels and they are not interchangeable.** The *floor*
wheel ships inside the DMG and never changes for a given build; the *updated*
wheel is downloaded into Application Support against a signed manifest and is
what actually runs when it verifies. Code that resolves "the wheel" must say
which one it means. Rollback exists (`rollbackWheel`) because a bad update has
to be survivable without a reinstall.

---

## Packaging

**This ran, once, on 2026-08-23.** The app was built, signed, notarized, stapled
and launched: `StreamMagpie-0.1.0-arm64.dmg`, 173,500,067 bytes, notary
submission `b3b32e8f-778d-4e50-80b9-1ad3f5f37023` **Accepted**, and Gatekeeper
returning `accepted / source=Notarized Developer ID` from a copy carrying a
quarantine attribute. `[verified: run 2026-08-23]` The record, including the two
risk hypotheses that run disproved and the belief about `mac.binaries` that it
corrected, is [`docs/DISTRIBUTION.md`](docs/DISTRIBUTION.md).

⚠ **One green build is not a proven pipeline. It is one artefact.** Every rebuild
re-earns every gate below, because two of the build's stages fail open and
neither the exit code nor the previous success says anything about this one. And
what that build did *not* cover is the half a customer sees: the app's own GUI
flow has never been exercised, and nothing has been checked on a clean Mac. Those
remain `[inferred]`.

The sequence is in [`docs/DISTRIBUTION.md`](docs/DISTRIBUTION.md), driven by
`.claude/skills/build-dmg`; the upload leg is separate and is
`.claude/skills/ship-gumroad`. The order inside `scripts/sign-dmg.sh` is
load-bearing: **sign, then notarize, then staple.** Signing a stapled DMG
invalidates the ticket, producing a file that passes every local check and fails
on a clean Mac.

⚠ **Two build stages fail OPEN. Both exit 0 and say so only in the log.**

| Stage | What goes wrong silently | Grep the log for | Want |
|---|---|---|---|
| `extraResources` copy | A `vendor/` directory is empty, so the DMG ships with no ffmpeg, no Python, no JS runtime, or no floor wheel — and the app installs fine and fails on first conversion | `file source doesn't exist` | 0 |
| Notarization | Credentials are missing or the keychain profile is wrong, so an unnotarized DMG lands in `release/` looking finished | `skipped macOS notarization` | 0 |

A third grep confirms the good path: `notarization successful`, want 1. Do not
call a build done without all three.

---

## Commands

| | |
|---|---|
| Gate | `npx tsc -b && npm run typecheck -w packages/app && npm test` |
| Build (TS) | `npm run build` — the same `tsc -b` |
| Clean | `npm run clean` |
| Tests only | `npm test` / `npm run test:watch` |
| Dev app | `npm run dev` |
| Fill `vendor/` | `bash scripts/vendor-ytdlp.sh`, `vendor-js.sh`, `vendor-python.sh`, `build-ffmpeg.sh` |
| Extractor smoke | `bash scripts/extractor-smoke.sh` |
| Check the notary profile | `xcrun notarytool history --keychain-profile streammagpie` |

Conventional commit prefixes (`feat:`, `fix:`, `docs:`, `refactor:`, `chore:`).
Focus the message on **why**, not what.

---

## Status — 2026-08-23

**The first signed, notarized, stapled DMG exists.**
`packages/app/release/StreamMagpie-0.1.0-arm64.dmg`, 173,500,067 bytes (165 MB),
built with electron-builder 26.15.3 and Electron 43.4.0 on macOS 26.5. Notary
submission `b3b32e8f-778d-4e50-80b9-1ad3f5f37023` came back **Accepted**,
`stapler validate` passes, and `spctl` returns
`accepted / source=Notarized Developer ID` from a copy carrying a hand-written
quarantine attribute. Roughly nine minutes end to end. The three fail-open greps
came out 0, 0, 1. `[verified: run 2026-08-23]`

The `streammagpie` keychain profile now exists on the maintainer's machine and
resolved unattended for both the inline app notarization and the DMG pass. Which
Apple ID it was created with is recorded nowhere in this repo, per the
distribution policy.

**One belief this repo held in three places was false, and it was load-bearing.**
`mac.binaries` is *not* the only thing electron-builder signs: it signs those
four with the entitlements, by name, and then makes a **separate recursive pass**
over the finished `.app`. All 14 Mach-Os in the shipped bundle carry our
Developer ID, our Team ID and `flags=0x10000(runtime)` — the ten under
`Contents/Resources/python/lib/` included. That belief was the basis of both
packaging risk hypotheses, and both are now disproven: the nested tree was never
unsigned, so the notary had nothing to reject, and the bundled interpreter
imports its C extensions under the hardened runtime without
`disable-library-validation`, which stays absent.
[`docs/DISTRIBUTION.md`](docs/DISTRIBUTION.md) and
`packages/app/build/entitlements.mac.plist` carry the evidence.

**Still not done, and it is the interesting half.** The app's own GUI flow has
never been exercised — no URL pasted into the running app, no sleeve preview
seen, nothing saved through the UI, no save-location TCC prompt answered. The two
conversions that were run (m4a and mp3, characteristics only) went through the
bundled toolchain directly. ALAC has not been produced at all. Nothing has been
checked on a clean Mac or with networking off, so `spctl` and `stapler validate`
prove **notarized** rather than conclusively **stapled**. The human GUI gate is
with Vijay. Until it clears, the pipeline is proven and the product is not.

One gotcha worth knowing before debugging anything about the installed app: while
the quarantine attribute is present, macOS runs it under **App Translocation**,
from a randomized read-only `/private/var/folders/.../AppTranslocation/<uuid>/d/`
path rather than from `/Applications`. It ran fine there.
`[verified: launching 2026-08-23]` `xattr -cr` clears it, signature intact.

## Status — 2026-08-22

**Kept as history. Superseded by the entry above.**

**Scrubbed for public release. Nothing packaged.** The repo has been prepared for
a public MIT source drop with a Gumroad-only paid DMG, matching the sibling
apps: brand casing normalised, private working notes kept out of the public
tree (`YouTube-Audio-Mac-App-Scope.md` and `NOTES.local.md` are gitignored),
distribution and licensing positions written down, and this working agreement
replacing a five-line stub.

What exists: `packages/engine` with its test suite, `packages/app`'s Electron
main, preload and renderer, the vendor scripts, and the docs. What does not
exist: a build. All four `vendor/` directories are empty on a fresh clone, so
the first packaging attempt will hit the fail-open `extraResources` stage above
unless the vendor scripts are run first. `packages/app/package.json` says `0.1.0` and no artifact has ever carried
that number.

The next real milestone is a signed, notarized, stapled
`StreamMagpie-0.1.0-arm64.dmg` that has been launched from a quarantined copy on
a clean Mac. Until that happens, treat the Packaging section as a plan rather
than a record.
