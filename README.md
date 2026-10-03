# Pocket Touchpad

**English** | [简体中文](README.zh-CN.md)

Turn your iPhone into a trackpad and keyboard for your Mac.

Pocket Touchpad pairs a native iPhone app with a Mac receiver. Use one hand to move, click, and drag in portrait, or use both touch areas together in landscape. When you need to type, open your phone's system keyboard with a tap.

The interface centers on a large touch surface, two rows of separate controls, and four customizable shortcuts, with light and dark appearance. Pair your phone and Mac over the local network.

Native SwiftUI · iPhone + Mac · iOS 26+ / macOS 26+ · Developer preview

**Commercial work using Pocket Touchpad is allowed. Turning its source code or modified versions into commercial products or services is not.** See [LICENSE](LICENSE) and the [bilingual licensing notice](docs/OPEN_SOURCE.md).

## Screenshots

### Portrait — light and dark

A large touch area below two rows of separate controls.

<p>
  <img src="docs/assets/screenshots/portrait-light.png" width="300" alt="Portrait trackpad in light appearance">
  <img src="docs/assets/screenshots/portrait-dark.png" width="300" alt="Portrait trackpad in dark appearance">
</p>

### Landscape — both hands participate

Full-height touch areas on both sides, with controls in the middle. Both appearances are shown below.

![Landscape in light appearance](docs/assets/screenshots/landscape-light.png)

![Landscape in dark appearance](docs/assets/screenshots/landscape-dark.png)

### Drag lock — a visible held state

The highlighted button means the left mouse button stays held while you lift and reposition your finger. Tap again to release.

<img src="docs/assets/screenshots/portrait-drag-light.png" width="300" alt="Portrait with drag lock highlighted and the release action visible">

![Landscape with drag lock highlighted](docs/assets/screenshots/landscape-drag-dark.png)

### Keyboard — your phone's input method

Compose text, finish selecting characters, then send it to the Mac. Tab, Backspace, and Return have dedicated controls.

<p>
  <img src="docs/assets/screenshots/keyboard-light.png" width="300" alt="System keyboard and text composer in light appearance">
  <img src="docs/assets/screenshots/keyboard-dark.png" width="300" alt="System keyboard and text composer in dark appearance">
</p>

### Make room for your thumb

Edit mode exposes the touch-area resize handle and shortcut positions. Settings provide size sliders and four shortcut pickers.

<p>
  <img src="docs/assets/screenshots/layout-edit-light.png" width="300" alt="Edit mode with a resized touch area and visible resize handle">
  <img src="docs/assets/screenshots/settings-layout-light.png" width="300" alt="Touch-area size sliders and four customizable shortcut pickers">
</p>

### Pairing and gesture preferences

Reconnect to a saved Mac, or scan to pair. The settings view explains gesture behavior and compatibility.

<p>
  <img src="docs/assets/screenshots/pairing-light.png" width="300" alt="Pairing screen with an offline demonstration saved Mac record">
  <img src="docs/assets/screenshots/settings-gestures-light.png" width="300" alt="Gesture instructions and compatibility details in settings">
</p>

All 12 images are screenshots of the actual SwiftUI app in an iPhone Simulator. Connection status and the saved Mac record are offline demonstration data; no real Mac was connected and no pairing credentials are shown. Screenshots do not demonstrate real-device latency or haptics. The current app interface is in Chinese.

## What works today

- **Movement and clicks:** Relative pointer movement, with lift-and-reposition behavior like a regular trackpad. Move across displays following your Mac's display arrangement. Click, double-click, and right-click.
- **Dragging and gestures:** Enable the drag button, move, lift your finger, and continue dragging. Tap again to release. Scrolling, momentum, zoom, rotation, and additional gestures are available according to system settings and compatibility.
- **Two-handed landscape controls:** Both touch areas can move the pointer. Move both thumbs together or spread/pinch to zoom. Controls sit between the two areas.
- **Your phone's keyboard:** Use the iPhone system keyboard, finish composing text—including Chinese input or emoji—and tap Send to insert it at the Mac's current input position. Dedicated Tab, Return, and Backspace controls are included.
- **Adjustable layout:** Four customizable shortcuts, movable buttons and a resizable touch area in portrait, plus light, dark, and system appearance.
- **Remembered Macs:** Pair on the local network, save the connection, and attempt to reconnect when returning to the app. Connections use TLS-PSK encryption; pairing keys are stored in the system Keychain.

See the [gesture and compatibility notes](docs/Gestures.md) (Chinese) for details. No account, cloud relay, or kernel extension is required.

## Build and use

The app is named **Pocket Touchpad**; the Xcode project and schemes retain their development names, `Touchpad` and `TouchpadMac`.

1. Open `Touchpad.xcodeproj` in **Xcode**. Development and build checks currently use **Xcode-beta** with the required SDKs.
2. Select your development team under Signing & Capabilities for both **Touchpad** and **TouchpadMac**. Change the bundle identifiers if unique identifiers are required.
3. Run the **TouchpadMac** scheme on the Mac and grant the requested Accessibility control permission.
4. Run the **Touchpad** scheme on your iPhone. Enable Developer Mode if prompted.
5. Put both devices on the same local network, allow Local Network access on the phone, and scan the Mac receiver's pairing QR code.
6. Focus the target application or input field on the Mac, then use your phone to move, click, and send text.

See the [setup guide](docs/Setup.md) for build commands and troubleshooting. There is no App Store release or publicly distributed signed build at this stage.

## Known limitations

Pocket Touchpad is a software input bridge, not a registered hardware Magic Trackpad. Some advanced gestures and native acceleration rely on private macOS interfaces and may be affected by OS updates. Force Click, pressure levels, palm rejection, and every application's custom gestures are not fully reproduced.

iOS may suspend networking while the phone is locked or the app is in the background. Returning to the foreground triggers a connection check and reconnection attempt; permanent background connectivity is not guaranteed. Keyboard input is composed before sending. The app does not currently read the Mac's screen or clipboard. Wireless latency and gesture behavior in individual applications require real-device testing.

## License and contributions

This project uses the project-specific **[Pocket Touchpad Source-Available License 1.0](LICENSE)**.

- **Allowed:** Use Pocket Touchpad for commercial design, videos, software, paid client work, and internal business operations, including internal workflow modifications. Sell or deliver your independent results without being required to open-source them, credit Pocket Touchpad, or pay fees merely for using the tool.
- **Not allowed:** Sell the project's source or modified versions, charge for builds or subscriptions, or integrate its code or functionality into commercial products or services.
- **Sharing:** Share noncommercial forks and compiled builds for free while retaining [LICENSE](LICENSE), [NOTICE](NOTICE), and applicable third-party notices.

This is a **source-available** project, not a standard open-source license. Third-party material retains its original licenses; see [ThirdPartyNotices.txt](docs/ThirdPartyNotices.txt). See the [bilingual licensing notice](docs/OPEN_SOURCE.md) for the full boundaries and examples.

Issues and focused improvements are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md). Never submit pairing QR codes, pairing links, keys, signing certificates, or private device information.
