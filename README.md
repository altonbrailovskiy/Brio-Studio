# Studio Cam Controls

[![Buy Me a Beer](https://img.shields.io/badge/Buy%20Me%20a%20Beer-%F0%9F%8D%BA-F5A623?style=for-the-badge&logo=buymeacoffee&logoColor=1F1F1F&labelColor=F5A623)](https://www.buymeacoffee.com/alton_br)

Native macOS camera controls for the **Logitech Brio 100** (USB `046d:094c`).

<sub>Formerly Brio Studio. Not affiliated with or endorsed by Logitech. Logitech and Brio are trademarks of Logitech.</sub>

- Requires **macOS 14** or later
- No third-party dependencies
- No network access

## Contents

> 📖 More detail, with diagrams, is in the [wiki](https://github.com/altonbrailovskiy/Studio-Cam-Controls/wiki).

- [Build](#build)
- [Open](#open)
- [Quick start](#quick-start)
- [Supported controls](#supported-controls)
- [How settings behave](#how-settings-behave)
- [Preview tools](#preview-tools)
- [Optimize once](#optimize-once)
- [Backlit mode](#backlit-mode)
- [Troubleshooting](#troubleshooting)
- [Distribution](#distribution)
- [Diagnostics](#diagnostics)
- [Validation](#validation)
- [Implementation](#implementation)

## Build

Install the Xcode Command Line Tools (`xcode-select --install`), then run from this folder:

```sh
./build.sh
```

This builds a universal (Apple silicon and Intel) app at `build/Studio Cam Controls.app`, ad-hoc signed for your Mac, plus a diagnostic CLI at `build/brio-probe`.

| Command | Result |
| --- | --- |
| `./build.sh` | Local build, ad-hoc signed |
| `./build.sh --sandbox` | Local build with the App Sandbox on, for testing App Store compatibility |
| `./build.sh --release` | Developer ID signed with the hardened runtime, ready to notarize |
| `./build.sh --appstore` | Apple Distribution signed `.pkg` for the Mac App Store |

See [Distribution](#distribution) for notarizing a release.

## Open

Open `build/Studio Cam Controls.app` in Finder. You can optionally drag it into **Applications**.

> [!NOTE]
> The app is ad-hoc signed, not notarized. If macOS blocks it the first time, right-click the app, choose **Open**, then confirm.

Click **Start preview** and allow Camera access when macOS asks. No microphone permission is needed. Frames stay in the local preview; nothing is recorded.

## Quick start

1. **Start preview**, then click **Lock current look** to stop automatic exposure and white balance from drifting. This samples and reapplies the current values.
2. **Adjust exposure, gain, and white balance.** Exposure numeric values are in 0.1 ms units (`100` = 10 ms); the heading shows milliseconds. Sliders apply on release; numeric fields apply when you press <kbd>Return</kbd>.
3. **Save a named look.** Apply it again after reconnecting the camera if needed.
4. **Restore camera defaults** uses the defaults reported by the webcam and asks first.

## Supported controls

Controls are queried from the device, including supported ranges and modes. This Brio reports:

| Control | Range / notes |
| --- | --- |
| Exposure | 5–2500 (0.5–250 ms) |
| White balance | 2800–7500 K |
| Gain | ✅ |
| Brightness | ✅ |
| Contrast | ✅ |
| Saturation | ✅ |
| Sharpness | ✅ |
| Backlight compensation | ✅ |
| Variable-frame-rate priority | ✅ |
| Anti-flicker | 50/60 Hz |

It does **not** advertise focus, zoom, hue, or gamma controls, so those do not appear.

## How settings behave

These are **hardware settings**, not preview-only filters or a virtual webcam.

- Other apps can use the adjusted camera, but may overwrite settings.
- USB reconnection can reset settings.
- Optional restoration reapplies the last successfully applied/saved look on launch and on detected reconnection. It is **off by default**.
- The selected preset is remembered separately.
- **Stop preview** to free the video stream for another app.

### Saved looks

Saved-look status compares the current reported controls with the selected preset. Automatically varying exposure/gain/WB values are ignored in automatic modes.

- Use **Refresh** after changes from other apps.
- **Save** with the same name to update a preset.
- **Apply** to discard edits and restore it.

Presets live in macOS `UserDefaults` for `com.altonbr.briostudio`. Looks saved by version 1.0 (`local.brio.studio`) are copied over automatically the first time 1.1 launches.

## Preview tools

### Exposure warnings

- 🟥 **Red stripes** mark pixels with any RGB channel `>= 250/255`.
- 🟦 **Blue stripes** mark luma `<= 8/255`.

These are near-clipping indicators from the rendered video, not measurements of sensor RAW data. Dark objects and bright lamps can be expected to trigger them; whole-frame percentages do not assess face exposure.

### Histogram

Shows 64 luma bins, dark to bright, with square-root height scaling. Analysis runs at up to five updates per second.

### Before / after compare

- **Capture before** holds a 640-pixel-wide reference frame in memory.
- **Compare** shows the frozen left half against the live right half.
- **Recapture** replaces it.
- Stopping preview clears the reference.

No images are saved to disk. Overlays are local preview tools and do not affect the webcam output in other apps.

## Optimize once

Start preview, face the camera, then click **Optimize once**. A teal box shows the face being metered.

Choose your preferred face brightness with the slider (default **60% rendered luma**). This is a preference, not a universal skin-tone standard.

> [!NOTE]
> Detection runs locally with Apple Vision. No identity recognition, face templates, image uploads, or stored face data are used.

### How it works

- Waits for one stable face and averages three measurements.
- Snapshots exposure/gain/WB values, disables automatic exposure, and locks white balance at its current value.
- Adjusts exposure and gain one at a time, waiting at least one second for each result.
- Exposure is capped at **33.3 ms**. Gain increases are capped at **120** in standard mode. [Backlit mode](#backlit-mode) permits the full hardware gain range (**255** on this Brio) to prioritize face brightness. These are heuristic limits, not measured guarantees of image quality.
- Broad face luminance clipping constrains the brightness target. Saturation of one color channel alone does not cause the optimizer to darken a face.
- Multiple or no detected faces pause adjustments. A **45-second timeout** and **24-write limit** bound the run.
- Retains its best measured exposure and restores it when it reaches a limit or detects repeated direction reversals. The score favors the requested face brightness and penalizes broad highlight clipping.

### Color

The color stays at the white balance present when the run begins. Use the **Evening - Neutral** look first if the image is too yellow. This optimizer adjusts exposure; it is not automatic color calibration.

### Stop and undo

- **Stop** keeps the settings reached so far.
- **Undo optimization** restores the exposure, gain, white balance, and automatic modes captured before the first change. Other settings are left alone.
- The undo snapshot is in memory only. It is replaced by the next run's first write, and quitting loses it. **Save a look** to retain a result.
- The captured before frame is available through **Compare**.

This is a one-shot optimizer, not a continuous background adjustment service. It cannot fix poor lighting or recover detail beyond the webcam's dynamic range.

## Backlit mode

**Enabled by default** for this setup.

- Allows higher gain while keeping exposure at or below 33.3 ms.
- Meters the face rather than the background, which may become very bright.
- Higher gain can add noise. Uncheck **Backlit** for the quieter, more conservative gain cap.

The checkbox does not directly toggle the camera firmware's backlight-compensation setting.

## Troubleshooting

- **USB access unavailable:** close other camera-control apps and click **Reconnect**. The app never seizes the device or detaches Apple's camera driver.
- **After unplugging/replugging:** click **Reconnect**. Restart preview if necessary.
- **Preview permission denied:** enable Studio Cam Controls in **System Settings → Privacy & Security → Camera**.
- **Sliders greyed out:** exposure/gain and temperature sliders are disabled in automatic modes.
- **Low frame rate:** long exposures can reduce frame rate.
- **Noisy image:** raising gain can introduce noise.

## Distribution

### Notarized download (GitHub Releases)

Requires a paid Apple Developer membership and a **Developer ID Application** certificate (create it in **Xcode → Settings → Accounts → Manage Certificates**).

One-time setup: create an [app-specific password](https://account.apple.com) for your Apple ID, then store it for the notary tool:

```sh
xcrun notarytool store-credentials brio-notary \
  --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-password"
```

Each release:

```sh
./build.sh --release
./notarize.sh
```

This produces `build/Studio-Cam-Controls-<version>.zip`, notarized and stapled, ready to attach to a GitHub Release. It opens on other Macs without the "unidentified developer" warning.

### Mac App Store compatibility test

```sh
./build.sh --sandbox
```

Open the sandboxed app and check that **Start preview**, the control sliders, **Lock current look**, and **Optimize once** all still work.

> [!NOTE]
> Sandboxed apps keep their settings in a separate container, so saved looks from the regular build don't appear in the sandboxed one.

### Mac App Store

One-time setup at [developer.apple.com](https://developer.apple.com/account/resources):

1. **Identifiers:** register an App ID for `com.altonbr.briostudio`. No extra capabilities are needed.
2. **Certificates:** create an **Apple Distribution** and a **Mac Installer Distribution** certificate (or use **Xcode → Settings → Accounts → Manage Certificates**).
3. **Profiles:** create a **Mac App Store Connect** profile for that App ID with the Apple Distribution certificate. Download it into this folder as `StudioCamControls_AppStore.provisionprofile` (it's git-ignored).
4. **App Store Connect:** create a new macOS app with the same bundle ID.

Each upload:

```sh
BUILD_NUMBER=3 ./build.sh --appstore
```

This creates `build/Studio-Cam-Controls-<version>-<build>.pkg`. Upload it with Apple's [Transporter](https://apps.apple.com/app/transporter/id1450874784) app. Every upload needs a higher `BUILD_NUMBER` than the last.

The app includes a privacy manifest (`Assets/PrivacyInfo.xcprivacy`) declaring no tracking, no collected data, and `UserDefaults` use for its own settings.

## Diagnostics

> [!IMPORTANT]
> Close Studio Cam Controls first. Only one control connection can own the USB device.

Read capabilities and current values as JSON:

```sh
./build/brio-probe
```

Run the hardware self-test:

```sh
./build/brio-probe --self-test
```

The self-test briefly enables manual exposure and WB, writes back their current values, restores their modes, changes brightness by one, and restores it.

> [!WARNING]
> `--self-test` changes hardware settings temporarily. Do not interrupt it.

### Tests

Preview analysis and preset matching tests:

```sh
xcrun clang -fobjc-arc Sources/PreviewTools.m Tests/PreviewToolsTests.m \
  -framework Cocoa \
  -o build/preview-tests
./build/preview-tests
```

Optimizer tests:

```sh
xcrun clang -fobjc-arc Sources/Optimizer.m Tests/OptimizerTests.m \
  -framework Foundation -framework CoreGraphics \
  -o build/optimizer-tests
./build/optimizer-tests
```

## Validation

- ✅ Compiled successfully on macOS.
- ✅ Queried all 12 controls on the attached Brio 100.
- ✅ Hardware self-test passed exposure/WB writes and readback, brightness change/readback, and original mode/value restoration.
- ✅ Native app window and connected control display verified through macOS accessibility.
- ✅ Live preview, preset save/recall, remembered selection, modified-state display, histogram, split comparison, and warning overlay verified in the app.
- ✅ Analysis and preset matching tests pass.
- ⚠️ Physical unplug/replug automatic restoration has **not** been tested.

## Implementation

| File | Purpose |
| --- | --- |
| `Sources/Camera.m` | IOKit USB Video Class descriptor parsing and bounded requests |
| `Sources/main.m` | AppKit UI, serialized USB work, AVFoundation preview, presets |
| `Sources/probe.m` | Read-only diagnostics and optional hardware roundtrip test |
| `Sources/Optimizer.m` | Face-metered one-shot exposure optimizer |
| `Sources/PreviewTools.m` | Histogram, clipping overlay, and preset matching |
| `Sources/icon.m` | Generates the app icon images |

### References

- [IOUSBDeviceInterface182 — Apple Developer](https://developer.apple.com/documentation/iokit/iousbdeviceinterface182)
- [USB Video Class v1.5 document set — USB-IF](https://www.usb.org/document-library/video-class-v15-document-set)
- [VNDetectFaceRectanglesRequest — Apple Developer](https://developer.apple.com/documentation/vision/vndetectfacerectanglesrequest)
