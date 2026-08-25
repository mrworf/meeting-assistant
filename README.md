# Meeting Assistant

Meeting Assistant is a native macOS 14+ menu-bar application that watches the signed-in user's primary Google Calendar and presents an always-on-top meeting countdown on every display.

## Behavior

- Qualifies accepted invitations and hosted meetings with at least one other non-declined person.
- Skips all-day, cancelled, tentative, focus-time, working-location, out-of-office, solo, and room-only events.
- Appears five minutes before a meeting, pulses orange during the final minute, and flashes red after the start.
- Resolves Google Meet, Zoom, and Microsoft Teams links; otherwise opens the Google Calendar event.
- Acknowledges every currently displayed meeting when any Join/Open Event button succeeds.
- Has no alert dismissal control. Quit requires a five-second confirmation delay.
- Refreshes every five minutes and after launch, wake, app activation, and network recovery.

## Google setup

1. Create or select a project in [Google Cloud Console](https://console.cloud.google.com/).
2. Enable the **Google Calendar API**.
3. Configure an OAuth consent screen. For personal use, keep it in Testing and add your Google account as a test user.
4. Create an OAuth client with application type **Desktop app**.
5. Build and launch Meeting Assistant, choose **Configure**, paste the client ID, and click **Connect Google Account**.

The app requests only `https://www.googleapis.com/auth/calendar.readonly`. Refresh credentials are stored in macOS Keychain. Calendar state and non-sensitive settings are stored in the application's user defaults.

## Build and test

Full Xcode is required. The build commands select the installed Xcode toolchain explicitly because the standalone command-line tools on this machine do not match their SDK.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH="$PWD/.build/cache/clang" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/cache/swiftpm" \
swift test --disable-sandbox

./scripts/build-app.sh
```

The packaging script creates an ad-hoc-signed `MeetingAssistant.app` in the repository root. Move it to `/Applications`, launch it, and approve it under **System Settings → General → Login Items** if macOS requests approval. Running the raw SwiftPM executable is useful for development, but launch-at-login requires the packaged app.

## Architecture

- `MeetingAssistantCore` contains event decoding, qualification, URL resolution, alert policy, OAuth/token handling, Calendar synchronization, and persistence.
- `MeetingAssistant` contains the AppKit lifecycle, SwiftUI views, browser OAuth callback listener, menu, configuration window, and per-display alert panels.
- Tests use an injected clock and mocked `URLSession` transport; no live Google credentials are needed.

