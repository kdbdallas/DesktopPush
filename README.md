# DesktopPush

DesktopPush is a paired macOS sender and iOS receiver for testing and scripting APNs notifications.

## Included targets

- **DesktopPush (macOS):** manages local device tokens, imports password-protected `.p12` push certificates into the login Keychain, composes notifications, tracks APNs responses, and keeps a local scheduled-delivery queue.
- **DesktopPush Receiver (iOS):** registers for remote notifications, exposes its APNs device token for copying, and keeps a shared-container history of received notifications.
- **DesktopPush Notification Service:** downloads HTTPS image, GIF, audio, and video attachments before display and records rich notifications in the history.
- **desktoppush:** command-line sender for scripts and automation.

## Setup

1. In Xcode, select your development team and replace the default `com.port21` bundle identifiers.
2. Enable **Push Notifications** and the App Group `group.com.port21.desktoppush` for the iOS app and notification-service extension. Update the App Group in the entitlements and `NotificationHistory.swift` if you change it.
3. Create an APNs SSL certificate for the iOS app identifier in Apple Developer, export it as a `.p12`, and import it in the Mac app. The certificate and its password are stored in Keychain.
4. Install the iOS app on a physical device, allow notifications, copy its token, and add it in the Mac app. The Simulator cannot receive remote APNs pushes.
5. Select the matching sandbox or production environment, choose the certificate and device, then send.

Attachments must be publicly reachable HTTPS URLs. Custom sounds must already be bundled in the iOS app; otherwise use `default`.

## CLI

After building the **DesktopPush Mac** scheme, the `desktoppush` executable is in the build products directory.

```sh
desktoppush send \
  --certificate Push.p12 \
  --password "$P12_PASSWORD" \
  --topic com.example.DesktopPushReceiver \
  --token "$APNS_DEVICE_TOKEN" \
  --title "Build complete" \
  --body "All tests passed"
```

To include media:

```sh
desktoppush send --certificate Push.p12 --password "$P12_PASSWORD" \
  --topic com.example.DesktopPushReceiver --token "$APNS_DEVICE_TOKEN" \
  --title "Preview" --attachment https://example.com/preview.gif --attachment-kind gif
```

The initial Notification Center forwarding command is:

```sh
desktoppush notification-center --certificate Push.p12 --password "$P12_PASSWORD" \
  --topic com.example.DesktopPushReceiver --token "$APNS_DEVICE_TOKEN" --limit 1
```

It performs a best-effort read of macOS’s `usernoted` database. This is not a public macOS API, so grant the terminal **Full Disk Access** if prompted and expect its schema to change between macOS releases.

### Continuous Notification Center forwarding

`Scripts/forward-notification-center.zsh` polls for newly added Notification Center records and forwards them to every saved device. It processes exact ranges of delivered records in chronological batches, so bursts of notifications are queued instead of being replaced by whichever entries are newest when a poll runs. Positions are tracked by delivery time plus record ID rather than record ID alone, because macOS reuses the newest record ID after that notification is removed. It establishes a starting position when it launches, so it does not replay your existing notification history.

```sh
PUSH_P12=/path/to/Push.p12 P12_PASSWORD="$P12_PASSWORD" \
  nohup ./Scripts/forward-notification-center.zsh \
  > /private/tmp/desktoppush-forwarder.log 2>&1 &
```

Grant Full Disk Access to the terminal that starts the script. Set `DESKTOPPUSH_BIN` when `desktoppush` is not on `PATH`, and `NOTIFICATION_POLL_INTERVAL` to change the default two-second polling interval.

## Scheduling

The Mac app delivers scheduled notifications while it is open. For unattended sends, invoke the CLI through `launchd`, cron, or your build/automation system at the desired time.
