# Input pipeline

Click's new backend captures configured physical keyboards with
`IOHIDDeviceOpen(kIOHIDOptionsTypeSeizeDevice)` and consumes `IOHIDQueue` values.
Mapping and macro-trigger decisions use the originating device and raw HID
usage, before those captured events reach the normal macOS keyboard/IME path.
The output is a virtual HID keyboard. There is no CGEvent-tap capture fallback.
This follows the design described in
[Karabiner's development guide](https://github.com/pqrs-org/Karabiner-Elements/blob/main/DEVELOPMENT.md).

```text
Physical keyboard
    → IOHIDQueue (exclusive capture, configured devices only)
    → ClickDaemon / RawInputRouter
        → key mapping → Karabiner DriverKit virtual keyboard → macOS → input method → app
        → macro trigger → Click user agent
            → app activation / delay
            → shortcut → ClickDaemon → virtual keyboard
            → Unicode text insertion (explicit user-session text action)
```

This does not mean running before the hardware driver, firmware, or every macOS
component. The guarantee is about the capture and routing stage, not a guarantee
that every device or application accepts every output.

## Components and privilege boundary

- `ClickDaemon`: root LaunchDaemon registered with `SMAppService.daemon`.
  It accepts one XPC client from the active graphical console UID. The client's
  code must satisfy the enclosing signed Click app's designated requirement,
  captured at daemon startup. Ad-hoc builds bind to their code hash. The daemon
  accepts validated configuration and shortcuts, not executable commands or
  filesystem paths. Configuration is held in memory, never read as root from
  a user-selected path. Driver protocol traffic uses pqrs's official C++ client.
- `Click`: user-session UI and macro executor. Application activation and text
  insertion stay in this process. A one-second heartbeat leases device capture;
  stale leases over five seconds, console changes, driver loss, IPC invalidation,
  pause, and termination release capture. Sleep pauses; resume explicitly after wake.
- `RawInputRouter`: pure device/usage routing. Source state is remembered until
  key-up. Multiple sources holding the same destination do not release each
  other. Macro triggers are consumed directly, without reserved function keys.
- `Hardware`: enumerates devices for the UI and restores legacy `UserKeyMapping`
  journals. New operation never writes `UserKeyMapping`.

The virtual device must report ready before seizure. Driver package 8.5.0 and
8.6.0 both use client protocol 7; other protocols are rejected by the client.
Click Settings can download the pinned official 8.6.0 package (SHA-256 and
Developer ID Installer verification), open Apple's Installer, invoke the signed
pqrs activation manager, and register the shared daemon using its bundled
`SMAppService` plist. Existing 8.5.0/8.6.0 installations and a running shared
service are reused. Installation, extension activation and the daemon's running
state are checked separately; opening Installer is not installation success.
Click neither bundles the driver binary nor needs Karabiner-Elements configuration.
Other remappers must release the keyboards assigned to Click.

## Failure handling and limits

Key state is merged into complete reports, with a 32-key-per-page limit. Exceeding
that limit or a HID rollover error stops capture rather than dropping a key.
Disconnect removes that device's held keys. Pending values across devices are
ordered by their HID timestamps. Virtual keyboards are excluded from capture.
Compound interfaces with unsupported input pages/axes remain with macOS rather
than being partially swallowed. A compatible sibling interface on the same
physical keyboard can still be captured. A connected configured keyboard with
no compatible interface fails explicitly. This selection is tested against the
pure-keyboard plus compound-interface topology observed in read-only inspection
of a NuPhy Halo65 V2; actual event delivery and reconnection remain unverified. Keyboard-page mappings are supported; consumer,
system, and Apple vendor pages pass through on supported keyboard interfaces.
Mappings can output held Fn on Apple top-case page `0x00ff`, usage `3`, or add
Fn to a keyboard-page destination. Fn reports are posted before keyboard reports,
so the modifier is present when a function-key down reaches macOS. Held Fn is
owned per source, including overlapping sources, and released on disconnect.
`destinationPage` and `fn` are optional configuration fields; missing fields keep
legacy keyboard-page behavior. These mappings do not use macro taps or CGEvent.
Caps Lock LED synchronization is not implemented yet.

A normal stop emits empty reports and closes physical devices. On abrupt process
exit, IOKit releases open device handles and the driver's client connection ends.
These OS/driver behaviors and worst-case watchdog timing still require hardware
validation. No keyboard events are logged or persisted.

Unicode text has no universal HID equivalent. The explicit Type Text action
continues to insert Unicode using CGEvent in the user agent. It is not used to
capture keys, identify a device, trigger a macro, or emit shortcut key events;
Secure Input and application-specific text handling may reject it.

## Validation

Automated coverage checks per-device routing, independent key ownership,
disconnect/reset, modifier/media passthrough, consumed macro down/up and repeat,
F13 passthrough, more than eight bindings, configuration, legacy restoration,
localization, and macro ordering/focus/cancellation. `make release` packages and
signs both executables, the LaunchDaemon plist, and localization/license resources.

Before treating this backend as hardware-validated, exercise these on a test Mac:

1. Activate the supported official driver; install Click in Applications, approve
   Keyboard Service in Login Items, and grant the requested Input Monitoring access.
2. With a Chinese IME active and composing, test Caps Lock → Escape and a physical
   macro trigger on one keyboard while the same key on another remains unchanged.
3. Test held modifiers, two sources mapped to one key, autorepeat, simultaneous
   keys, unplug/replug, Bluetooth reconnect, sleep/wake, and fast user switching.
4. Stop/kill the UI and daemon separately while keys are held. Verify ordinary
   typing returns and no virtual modifiers remain pressed. Test driver restart.
5. Check Secure Input with ordinary test text; do not assume Unicode text insertion
   behaves like the raw HID key path. Verify login startup after a real login.

Source/build tests do not certify those hardware, permission, or session scenarios.

## Migration notes

Karabiner's per-device identifiers are not necessarily global wildcards when a
vendor/product pair is missing. Verify the corresponding device in its Settings
UI and resolve Click's identity from connected hardware. Back up the source and
save imported profiles disabled until takeover is authorized. Personal backups
and exports belong outside this repository.

Karabiner's F1 → F1 function-key setting is not merely a raw no-op through a
virtual Apple keyboard: macOS may interpret a bare F-key as a media key. Preserve
standard function-key intent with a held Fn + F-key mapping, following
[Karabiner's function-key documentation](https://karabiner-elements.pqrs.org/docs/help/how-to/function-keys/).
Physical Fn/Globe and function-key behavior still require hardware validation.
Stopping Karabiner-Elements must not remove the shared DriverKit virtual HID
driver and its service, which Click also needs.

## Driver setup verification

The package digest is pinned in `DriverPackage.swift`; it is not obtained from a
mutable latest-release endpoint at runtime. The package is opened only after its
size, SHA-256 and pqrs Developer ID Installer signature match. Activation and
service registration validate the installed app's Apple signing chain, team and
identifier. Registration does not unregister another app's shared service.
No privileged password or shell is exposed through Click. Installing/upgrading
through the system Installer and accepting extension/background approval still
requires user interaction. A future incompatible version is shown explicitly and
is never silently replaced.

Package verification can be tested without installation:

```sh
CLICK_DRIVER_TEST_PACKAGE=/path/to/Karabiner-DriverKit-VirtualHIDDevice-8.6.0.pkg swift test
```

Without that fixture the live-package verification test is skipped; rejection,
version compatibility, signature rejection and other tests still run. Fresh
installation, activation approval, reboot and service takeover require separate
manual validation.

## Automatic configuration updates

Valid edits are persisted atomically before hardware application. A serialized
250 ms debounce coalesces consecutive edits; newer edits invalidate in-flight
application and only the latest configuration is applied next. Pause and quit
cancel queued application. A failed save never applies unsaved input rules;
a failed hardware application leaves the saved configuration intact and reports
that mappings are paused. Invalid intermediate edits remain in the editor with
an error until corrected. Demo updates remain in memory.

Configuration XPC replies have a six-second deadline and exactly-once completion.
A timeout invalidates the connection and reports how to re-register Keyboard
Service via its Settings toggle. This also prevents a stale launchd registration
from indefinitely blocking subsequent configuration edits. Registration status
alone does not establish that launchd can execute the daemon; after replacing an
ad-hoc signed build, a stale service registration may need to be turned off and
on again. No TCC database or launchd security checks are bypassed.
