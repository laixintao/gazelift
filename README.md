# GazeLift

A little distance. A clearer day.

GazeLift is a native macOS menu bar app that reminds you to look away from your
screen. After 30 minutes of continuous work, a quiet green border grows inward
over 60 seconds until it fills every display. The **Start my break** and
**Remind me in 5 min** buttons stay above it.

Requires **macOS 14 Sonoma or later**, on Apple Silicon or Intel. Built with
Swift 6, SwiftUI and AppKit; no third-party runtime dependencies.

## How it works

| Event | What happens |
| --- | --- |
| 30 minutes of work | The expanding border appears. |
| Start my break | The border disappears. Input is ignored for 30 seconds, then fresh input starts a new work session. |
| Remind me in 5 min | The border disappears and returns five minutes later. |
| 30 seconds without mouse or keyboard input | The current session ends. Fresh input starts another full work session. |
| Lock, sleep, or switch away from the login session | Reminders disappear. Work restarts with new input after returning. |
| Pause reminders | Reminders stay paused until you resume from the menu bar. |

Reading and video playback without input also count as inactivity. Adjust the
inactivity threshold if needed. Settings take effect at the start of the next
work session. Restarting the app starts fresh rather than restoring an old timer.

The menu bar shows the countdown and current state. Settings let you adjust the
work interval, inactivity threshold, and manual-break waiting period, and enable
**Open at login**. Move the app to Applications before enabling that option.
English and Simplified Chinese follow your system language.

Activity detection queries elapsed time since the last input; it does not record
keystrokes or screen contents. Settings stay in local preferences. The app has no
analytics or network requests, and requires no camera, screen recording, or
Accessibility permission.

## Build and run

Install Apple's Command Line Tools (`xcode-select --install`), then:

```sh
make build
open build/Release-native/GazeLift.app
```

The eye icon appears in the menu bar. Reopening the app opens Settings. To open
Settings explicitly on first launch:

```sh
open build/Release-native/GazeLift.app --args --settings
```

## Install a release

Download `GazeLift-<version>-macos-universal.dmg` from
[Releases](https://github.com/laixintao/gazelift/releases), open it, and drag
GazeLift to Applications. The matching ZIP contains the same universal app.

Install with Homebrew, or update an existing installation:

```sh
brew install --cask laixintao/tap/gazelift
brew update
brew upgrade --cask laixintao/tap/gazelift
```

Releases are ad-hoc signed and are not notarized by Apple. If macOS blocks an app
you trust, attempt to open it, then use **System Settings → Privacy & Security →
Open Anyway**, following [Apple's instructions](https://support.apple.com/en-us/102445).
The cask preserves Gatekeeper and quarantine protections.

Uninstall with `brew uninstall --cask laixintao/tap/gazelift`. Adding `--zap`
also removes preferences.

## Develop and verify

```sh
make test       # deterministic state tests and native UI snapshots
make check      # metadata and disposable-Git release tests
make package    # universal app, DMG, ZIP, and checksum verification
make ci         # all of the above
```

Native UI tests require a logged-in macOS graphical session. They write English
and Chinese light/dark screenshots into `build/qa`. Builds and generated assets
stay under `build` and `dist`. Python 3.9+ is used for release tooling; normal CI
also runs ShellCheck and actionlint.

The pure `UsageEngine` consumes explicit monotonic timestamps, idle samples, and
session availability. `ActivityMonitor` adapts CoreGraphics idle time and macOS
session notifications. AppKit manages click-through borders and a separate
interactive panel; SwiftUI renders the menu, reminder and Settings.

The activity adapter observes lock/unlock distributed notifications and the
current session's lock state, in addition to public workspace sleep/session
notifications. Lock notifications and the lock-state dictionary key are macOS
implementation details; regression-test them on new macOS releases. Missing
session data suppresses reminders until detection is available again.

See [manual QA](docs/QA.md) for multi-monitor and lock/sleep scenarios.

## Release

```sh
git switch main
git pull --ff-only
make release
# Or: make release VERSION=0.2.0
```

Commit application changes first. The first invocation publishes the current
`0.1.0` version; subsequent invocations choose the next patch. The command checks
remote history and tags, prepares notes and versions, creates a release commit
and annotated tag, atomically pushes both, and prints the Actions URL. It returns
after the push; confirm the workflow succeeds before announcing a release.

CI builds and tests on `macos-15`; `macos-15-intel` downloads and verifies the
**same** universal installers. The publishing job verifies the tested artifacts
again on macOS, attests their provenance, uploads everything to a draft, and
only then publishes it. Published releases are immutable. To retry a failed
upload, rerun the release workflow for the existing tag. To retry a failed push,
use the exact command printed by `make release`, without rerunning the release
preparation command.

Assets follow the [tap release standard](https://github.com/laixintao/homebrew-tap/blob/main/docs/RELEASE_STANDARD.md):

```text
GazeLift-<version>-macos-universal.dmg
GazeLift-<version>-macos-universal.zip
SHA256SUMS
```

Verify downloaded checksums with `shasum -a 256 -c SHA256SUMS` and provenance with
`gh attestation verify <installer> --repo laixintao/gazelift`.
See [Homebrew onboarding](packaging/homebrew/README.md) for the first tap integration.

MIT licensed.
