#!/bin/bash
# Creates a separate offline simulator. Never launches the Mac receiver.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
SIM_RUNTIME="${SIM_RUNTIME:-com.apple.CoreSimulator.SimRuntime.iOS-26-2}"
SIM_TYPE="${SIM_TYPE:-com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro}"
BUILD_PATH="${TMPDIR:-/tmp}/touchpad-screenshot-build"
DEVICE_ID="$(xcrun simctl create 'Pocket Touchpad Offline Screenshots' "$SIM_TYPE" "$SIM_RUNTIME")"
cleanup() {
  xcrun simctl shutdown "$DEVICE_ID" >/dev/null 2>&1 || true
  xcrun simctl delete "$DEVICE_ID" >/dev/null 2>&1 || true
}
trap cleanup EXIT
xcrun simctl boot "$DEVICE_ID"
xcrun simctl bootstatus "$DEVICE_ID" -b
xcodebuild -project Touchpad.xcodeproj -scheme Touchpad -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$BUILD_PATH" \
  CODE_SIGNING_ALLOWED=NO build
xcrun simctl install "$DEVICE_ID" "$BUILD_PATH/Build/Products/Debug-iphonesimulator/Touchpad.app"
xcrun simctl status_bar "$DEVICE_ID" override --time '9:41' --wifiMode active \
  --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState discharging --batteryLevel 100
# Suppress only this newly-created simulator's first-use keyboard tutorial.
xcrun simctl spawn "$DEVICE_ID" defaults write com.apple.keyboard.preferences DidShowContinuousPathIntroduction -bool true
mkdir -p docs/assets/screenshots
capture() {
  local name="$1" appearance="$2"
  shift 2
  xcrun simctl ui "$DEVICE_ID" appearance "$appearance"
  xcrun simctl launch "$DEVICE_ID" art.dongheng.touchpad --screenshot-preview "$@"
  sleep 5
  xcrun simctl io "$DEVICE_ID" screenshot "docs/assets/screenshots/$name.png"
  xcrun simctl terminate "$DEVICE_ID" art.dongheng.touchpad
}
capture portrait-light light
capture portrait-dark dark
capture landscape-dark dark --landscape
capture landscape-light light --landscape
capture keyboard-light light --keyboard
capture keyboard-dark dark --keyboard
capture portrait-drag-light light --drag
capture landscape-drag-dark dark --landscape --drag
capture layout-edit-light light --edit-layout
capture settings-gestures-light light --settings
capture settings-layout-light light --layout-settings
capture pairing-light light --pairing
python3 - <<'PYMETA'
from pathlib import Path
from datetime import date
import json, os
folder = Path('docs/assets/screenshots')
manifest = {
    'captured': date.today().isoformat(),
    'device': os.environ.get('SIM_TYPE', 'com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro'),
    'runtime': os.environ.get('SIM_RUNTIME', 'com.apple.CoreSimulator.SimRuntime.iOS-26-2'),
    'build': 'Debug simulator, Xcode-beta',
    'source': 'Actual SwiftUI app; offline connection and saved Mac fixtures',
    'network': 'Disabled in preview; no real Mac connection, input, or pairing credentials',
    'files': []
}
for path in sorted(folder.glob('*.png')):
    data = path.read_bytes()
    manifest['files'].append({'file': path.name, 'width': int.from_bytes(data[16:20], 'big'), 'height': int.from_bytes(data[20:24], 'big')})
(folder / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
PYMETA
printf '%s\n' 'Screenshots saved. Inspect each image before publishing.'
