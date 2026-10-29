# Click

[中文](README.zh.md)

A small native macOS app for per-device key mappings and keyboard macros. Runs in the menu bar after its window closes.

![Click macro editor](docs/images/macros.png)

## Features

- **Per-device mappings.** Give each keyboard its own layout. Remap a key to another key or a reusable macro.
- **Ordered macros.** Switch to an application, wait, send a shortcut, or type Unicode text. Reorder steps in the editor.
- **Load and export.** Versioned JSON files contain devices, mappings, and macros. Valid changes are saved automatically and applied after a short debounce.
- **Background operation.** Close the window and keep your mappings running. Click the menu bar icon to reopen the window. Pause or cancel a macro from the window’s options menu; quit with the red power button at the bottom of the sidebar.
- **Launch at login.** Enable it in Settings. macOS may require approval in Login Items.
- **Native editor.** A compact sidebar, mapping rows, and an ordered macro editor. Language changes update the interface and menus without discarding edits.
- **Local operation.** No account, analytics, or keyboard history. Driver installation downloads an official package only when requested; no settings or keystrokes are uploaded.

## Install

Requires **macOS 14+**. The interface defaults to **English**. Switch between English and 简体中文 in **Settings → Language**; your choice is remembered.

Download an architecture-matching app from [Releases](https://github.com/MrCroxx/click/releases), open the DMG (or unzip the ZIP), and move **Click.app** to Applications before granting permissions or enabling launch at login. Local builds use a stable Keychain signing identity. CI artifacts explicitly use ad-hoc signing; neither is notarized. Building from source is also supported.

Use **Permissions** in the sidebar to check Accessibility, Input Monitoring and background-item registration, and open their System Settings pages. Status refreshes when you return to Click; **Check Again** refreshes it manually.

Settings use a single grouped list for general preferences, keyboard services, the driver, and configuration. Key menus group supported keys into letters, numbers, punctuation, editing, navigation, function keys, and modifiers.

Input Monitoring uses the HID permission check and request. If Click is absent from the system list after requesting, **Show Click in Finder** locates the running app so you can add it with **+** in System Settings.

1. Open **Settings → Driver → Virtual HID Driver → Install…**. Click downloads the official signed **8.6.0** package, verifies its pinned SHA-256 and installer signature, and opens macOS Installer. Complete installation there. Existing **8.5.0/8.6.0** installations are supported; there is no automatic replacement.
2. Use **Activate…** if the driver extension is inactive, then **Enable…** beside **Driver service** if needed. Approve macOS prompts and restart if requested. An already-running shared driver service is reused. Karabiner-Elements itself is not required.
3. In Click Settings, enable **Keyboard Service**, approve it in macOS Login Items, and grant **Accessibility** and **Input Monitoring** when requested.
4. Select **Add device**, choose a connected keyboard, and add mappings.
5. For a macro, first create its steps in the macro editor, then assign it to a key.
6. Enable the device profile. Changes save automatically and apply immediately after a short debounce.
7. Enable **Launch at login** if desired.

Adding a device starts with mappings disabled. Changes persist before hardware application. If the service fails, configuration stays saved and mappings pause with an error. Only enabled profiles are applied. Pausing restores the previous mappings; resuming reapplies the current valid configuration. If keys are held during startup, Click waits and retries automatically; pausing or changing the configuration cancels the pending attempt. Closing the window keeps the service running. Quitting restores mappings and stops it.

## Build

Use a Swift 6 toolchain and a C++23-capable Apple Clang toolchain on macOS. The pinned upstream virtual HID client uses C++23.

```sh
make test
make dev
make release
```

`make release` creates `build/Click.app`, `build/Click-macOS-<arch>.dmg` and a ZIP for the build machine's architecture. The DMG includes an Applications shortcut and matching app, file and volume icons. By default, builds use the single code-signing identity in Keychain and fail if none or multiple exist. Set `SIGNING_IDENTITY` to select a certificate name or fingerprint; only explicit `SIGNING_IDENTITY=-` permits ad-hoc signing. Keep the same certificate across builds. Moving from an ad-hoc build to a certificate-signed build may require one-time permission approval and Keyboard Service re-registration. For an isolated UI preview with sample data and no keyboard access:

```sh
make demo
```

`Click.app/Contents/MacOS/Click --background` starts the user agent with no window.
The bundled **ClickDaemon** runs as a root LaunchDaemon; the UI registers it using
`SMAppService.daemon`. It only accepts the active console user's signed Click
app. Keyboard handling is leased to that agent; UI failure, session changes or
loss of the virtual driver release the devices. App activation and text insertion
remain in the user session. Launch at login starts the user agent.
The heartbeat continues while menus or modal panels are open; the daemon still
releases keyboards if the agent stops responding for five seconds.

Packaging checks launchd's explicit arguments and validates the daemon's enclosing
app signature from `/`, with a bundle-relative `argv[0]`. The **Enabled** device
switch stores intent; **Running** confirms that the service applied the mappings.
Mapping errors stay visible until a subsequent operation clears or replaces them;
they cannot be dismissed while troubleshooting a paused service.
If macOS disallows the background item after an update, allow Click in
System Settings → General → Login Items & Extensions before resuming.

## Configuration and recovery

Files live in `~/Library/Application Support/Click/`:

- `config.json` — atomically saved, validated configuration, restricted to the current user.
- `recovery.json` — legacy mapping journal, retained for migration from v0.1.x.

Device identity uses vendor/product and serial number when present, otherwise the connection location. When an anonymous keyboard changes location, Click reuses its profile if there is exactly one saved profile and one connected keyboard of that model, without rewriting the saved location or mappings. Multiple profiles (including disabled ones) or connected keyboards of the same model disable this fallback; exact identity matching still applies. Multiple keyboard interfaces with the same identity share a profile. IOHID callbacks reassess matches and release devices that no longer match; UI discovery refreshes every two seconds.

New mappings use exclusive HID capture and virtual HID output, without modifying system mapping properties. `recovery.json` is retained only to restore mappings left by older releases. Corrupt configuration/recovery files cause an error rather than being overwritten. Exported configuration can contain serial numbers and macro text; review it before publishing.

## Current limits

- The raw HID backend is under hardware validation. Local tests and packaging pass; physical input/IME ordering, permission approval, Secure Input, logout/login and disconnect recovery require testing on the target Mac. Existing v0.1.x downloads still use the older backend.
- Mappings support keyboard-page keys and left/right modifiers. Fn as a source, media-key remapping, mouse mappings, firmware programming and Caps Lock LED synchronization are not implemented. Key mappings can output held Fn or add Fn to their destination (for example, Fn + F1 for a standard function key). Supported extra keyboard input pages pass through; unsupported compound interfaces remain with macOS while compatible sibling interfaces can be captured. Devices with no compatible interface are refused.
- Triggers are single physical keys, scoped to their device. There are **no reserved F13–F20 channels and no eight-trigger limit**. Modifier keys cannot trigger macros.
- Physical capture and shortcut output use HID before the normal input-method path. Explicit Unicode text insertion remains a separate user-session action and may be rejected by Secure Input or individual apps.
- A single macro runs at a time. Overlapping triggers are ignored. Application activation has a five-second deadline; an unexpected focus change stops following actions. An already-requested app launch cannot be undone.
- Other tools, including Karabiner-Elements, must not seize the same physical keyboards. Virtual keyboards are excluded from capture. Sleep pauses mappings; resume explicitly after waking.

See [Input pipeline](docs/input-pipeline.md) for the privilege boundary, failure handling, driver version pin and hardware validation checklist.

## Development

`ClickCore` contains the configuration schema, key catalog, raw HID router, and legacy restoration logic. `Click` contains the SwiftUI editor, AppKit menu bar, XPC client, macro executor, and login integration. `ClickDaemon` captures raw HID and uses the official pqrs virtual HID client through a small C++ adapter. CI runs tests and uploads an app archive.

Driver installation uses Apple’s Installer and the signed pqrs activation manager. Click does not collect administrator passwords or run an elevated shell. Service registration uses `SMAppService`; approving the extension and background items remains a macOS step. Opening Installer is not reported as successful installation. Driver replacement pauses Click mappings first. The shared driver service is not unregistered when Click mappings are paused.

Translations live in `Sources/ClickCore/Resources/Translations.json`. Add a language to `AppLanguage` and provide the same keys and format arguments; localization tests check coverage. The app bundle includes these resources. Native system dialogs use macOS language preferences.

The architecture was informed by [Olanzi](https://github.com/MrCroxx/olanzi)'s native macro and lifecycle implementation; this repository has an independent UI and general keyboard backend. Relevant Apple documentation: [key remapping](https://developer.apple.com/library/archive/technotes/tn2450/) and [login registration](https://developer.apple.com/documentation/servicemanagement/smappservice/register()).

MIT licensed. Contributions and device compatibility reports are welcome.
