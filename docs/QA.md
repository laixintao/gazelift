# Native acceptance checks

Automated state tests use an injected clock and do not wait for a real 30-minute
session. Native view tests render the UI in both languages and appearances.
These manual checks cover behaviors that need real input or display changes.

1. Build and run the app. Confirm an eye icon and countdown appear in the menu
   bar, with no Dock icon. Open the menu and Settings; check all labels and buttons.
2. For a short test, set the work interval to one minute. Pause and resume to
   apply the new settings, then keep operating the computer until the reminder.
3. Keep generating input while the border grows for 60 seconds. It must begin at
   every screen edge and fill the screen. The two buttons must stay above it,
   with no initial focus theft. Click **Remind me in 5 min**: all borders disappear.
4. At the next reminder, click **Start my break**. Generate input in the first
   30 seconds, then stop. That early input must not restart work after the grace
   period. New input after the grace period starts a full work countdown.
5. Stop input for 30 seconds during work, a reminder, and a snooze. Each should
   enter the waiting state, hide any borders, and start fresh on the next input.
6. Lock and quickly unlock. Then repeat after a long lock, system sleep, and a
   user-session switch. No reminder may appear on the lock screen; fresh input
   after return starts a new work cycle. A paused app must remain paused.
7. Check native fullscreen apps, separate Spaces, Stage Manager, Retina scaling,
   portrait monitors, and connecting/disconnecting a display during expansion.
   The controls should remain accessible if their original display is removed.
8. Verify English and Simplified Chinese, light/dark appearances, VoiceOver
   button labels, and Reduce Motion (six growth stages instead of smooth motion).
9. From Applications, enable Open at login yourself, check the macOS Login Items
   status, and disable it again. Quit/reopen the app and confirm timing settings persist.
10. Restore the default timings: 30 minutes / 30 seconds / 30 seconds.

## Packaging acceptance

`make package` checks both architectures, signatures, bundle metadata, resources,
the Applications shortcut, equality of the ZIP and DMG app, and native launch of
the packaged executable in both languages. CI repeats verification on Intel
using the same uploaded packages. The release smoke-test flag renders native
SwiftUI sizing and validates bundled resources without registering login items
or starting the reminder service.
