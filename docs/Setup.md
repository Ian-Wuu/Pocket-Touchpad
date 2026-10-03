# Build and setup

**English** | [简体中文](Setup.zh-CN.md)

Requirements: iOS 26+, macOS 26+, and Xcode with the required SDKs. Current development uses Xcode-beta. Neither app has third-party package dependencies.

## Signing and running

1. Open `Touchpad.xcodeproj`.
2. Select your development team in Signing & Capabilities for both Touchpad and TouchpadMac. Use unique bundle identifiers if required.
3. Alternatively, create `Config/Local.xcconfig` containing `DEVELOPMENT_TEAM = YOUR_TEAM_ID`. This file is ignored by Git; the shared signing configuration references it optionally.
4. Run the TouchpadMac scheme on My Mac. Click the control-permission button and enable the app in the system's Accessibility control settings.
5. Connect your iPhone and enable Developer Mode if prompted. Run the Touchpad scheme on the phone.
6. Join the same local network on both devices. Allow Local Network access on iPhone and camera access when scanning, then scan the Mac receiver's QR code. Pasting the pairing link is also supported.
7. Focus the target application on the Mac. The receiver does not need to remain in the foreground.

Pairing QR codes and links contain credentials. Do not publish or commit them.

## Build without controlling the desktop

```sh
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild -project Touchpad.xcodeproj -scheme Touchpad \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/touchpad-sim CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Touchpad.xcodeproj -scheme TouchpadMac \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/touchpad-mac CODE_SIGNING_ALLOWED=NO build
```

Adjust `DEVELOPER_DIR` if using a different Xcode installation. Disabling signing is for build checks; device installation and a stable Mac permission identity require correct signing.

`python3 scripts/create-project.py` regenerates the project and overwrites manual project-configuration changes. It is not required for normal use. The local team configuration remains in the ignored `Config/Local.xcconfig` file.

## Screenshots

`scripts/capture-screenshots.sh` creates an independent simulator, uses the Debug-only offline fixture, and captures twelve views covering light and dark appearance, landscape, dragging, the keyboard, layout editing, settings, and pairing. It does not connect to a receiver or inject Mac input. It shuts down and removes its own simulator on exit.

The default is an iPhone 17 Pro with iOS 26.2. Set `SIM_TYPE` and `SIM_RUNTIME` to another installed simulator if needed. README files directly display the screenshots; no website deployment is needed.

## Troubleshooting

- **The phone still requests control permission:** Ensure the running receiver is the same app listed in system permissions. Changing its location or signature can affect its identity. Keep both stable; if necessary, remove the old permission entry and add the actual signed app. The system may request a password or Touch ID.
- **The Mac cannot be reached:** Both devices must be on a mutually reachable local network. Guest networks or client isolation may prevent communication. Check Local Network permission.
- **The connection needs recovery after locking:** iOS can suspend background networking. Returning to the foreground checks the connection and attempts recovery using the saved pairing; indefinite background connectivity is not guaranteed.
- **Gestures differ between apps:** Check synchronization and capability status in the phone's settings. Some gestures depend on system preferences and private-interface compatibility. See [Gestures.md](Gestures.md) (Chinese).

No kernel extension or reduction of system security is required.
