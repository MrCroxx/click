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
The driver is installed separately from the official pqrs distribution. Click
neither bundles the driver binary nor needs Karabiner-Elements configuration.
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
