BRIO STUDIO
Native macOS camera controls for Logitech Brio 100 (USB 046d:094c).
Requires macOS 14 or later. No third-party dependencies or network access.

OPEN
Open build/Brio Studio.app in Finder. You can optionally drag it into Applications.
Click Start preview and allow Camera access when macOS asks. No microphone
permission is needed. Frames stay in the local preview; nothing is recorded.

QUICK START
1. Start preview, then click Lock current look to stop automatic exposure and
   white balance from drifting. This samples and reapplies the current values.
2. Adjust exposure, gain, and white balance. Exposure numeric values are in
   0.1 ms units (100 = 10 ms); the heading shows milliseconds. Sliders apply on
   release; numeric fields apply when you press Return.
3. Save a named look. Apply it again after reconnecting the camera if needed.
4. Restore camera defaults uses defaults reported by the webcam and asks first.

Controls are queried from the device, including supported ranges and modes.
This Brio reports exposure 5–2500 (0.5–250 ms), white balance 2800–7500 K,
gain, brightness, contrast, saturation, sharpness, backlight compensation,
variable-frame-rate priority, and 50/60 Hz anti-flicker. It does not advertise
focus, zoom, hue, or gamma controls, so those do not appear.

These are hardware settings, not preview-only filters or a virtual webcam.
Other apps can use the adjusted camera, but may overwrite settings. USB
reconnection can reset settings. Optional restoration reapplies the last
successfully applied/saved look on launch and detected reconnection; it is off
by default. The selected preset is remembered separately. Stop preview to free the video stream for another app.

TROUBLESHOOTING
- If USB access is unavailable, close other camera-control apps and Reconnect.
  The app never seizes the device or detaches Apple's camera driver.
- After unplugging/replugging, click Reconnect. Restart preview if necessary.
- If preview permission was denied, enable Brio Studio in System Settings >
  Privacy & Security > Camera.
- Sliders for exposure/gain or temperature are disabled in automatic modes.
- Long exposures can reduce frame rate. Raising gain can introduce noise.
- Presets live in macOS UserDefaults for local.brio.studio.

BUILD
Install Xcode Command Line Tools, then run ./build.sh from this folder.
Builds an ad-hoc signed, local Mac app and a diagnostic CLI.

DIAGNOSTICS
Close Brio Studio first: only one control connection can own the USB device.
./build/brio-probe                 Read capabilities and current values as JSON.
./build/brio-probe --self-test     Briefly enable manual exposure and WB, write
                                 back their current values, restore their modes,
                                 change brightness by one, and restore it.
The second command changes hardware settings temporarily; do not interrupt it.

VALIDATION
Compiled successfully on this Mac. Queried all 12 controls on the attached
Brio 100. Hardware self-test passed exposure/WB writes and readback, brightness
change/readback, and original-mode/value restoration. Native app window and
connected control display were verified through macOS accessibility.
Live preview, preset save/recall, remembered selection, modified-state display,
histogram, split comparison, and warning overlay were verified in the app.
Physical unplug/replug automatic restoration has not been tested.
Analysis and preset matching tests pass in Tests/PreviewToolsTests.m.

IMPLEMENTATION
Sources/Camera.m: IOKit USB Video Class descriptor parsing and bounded requests.
Sources/main.m: AppKit UI, serialized USB work, AVFoundation preview, presets.
Sources/probe.m: read-only diagnostics and optional hardware roundtrip test.

Protocol/API references:
https://developer.apple.com/documentation/iokit/iousbdeviceinterface182
https://www.usb.org/document-library/video-class-v15-document-set

PREVIEW TOOLS
Exposure warnings: red stripes mark pixels with any RGB channel >=250/255;
blue stripes mark luma <=8/255. These are near-clipping indicators from the
rendered video, not measurements of sensor RAW data. Dark objects and bright
lamps can be expected to trigger them; whole-frame percentages do not assess
face exposure. Histogram shows 64 luma bins, dark to bright, with square-root
height scaling. Analysis runs at up to five updates per second.

Capture before holds a 640-pixel-wide reference frame in memory. Compare shows
the frozen left half against the live right half. Recapture replaces it.
Stopping preview clears the reference. No images are saved to disk. Overlays
are local preview tools and do not affect the webcam output in other apps.

Saved-look status compares current reported controls with the selected preset;
automatically varying exposure/gain/WB values are ignored in automatic modes.
Use Refresh after changes from other apps. Save with the same name to update
a preset, or Apply to discard edits and restore it.

OPTIMIZE ONCE
Start preview, face the camera, then click Optimize once. A teal box shows the
face being metered. Choose your preferred face brightness with the slider
(default 60% rendered luma); this is a preference, not a universal skin-tone
standard. Detection runs locally with Apple Vision; no identity recognition,
face templates, image uploads, or stored face data are used.

The algorithm waits for one stable face and averages three measurements.
It snapshots exposure/gain/WB values, disables automatic exposure, and locks
white balance at its current value. It adjusts exposure/gain one at a time,
waiting at least one second for the result. Exposure is capped at 33.3 ms and
gain increases are capped at 120 in standard mode. Backlit mode permits the
full hardware gain range (255 on this Brio) to prioritize face brightness. These are
heuristic limits, not measured guarantees of image quality. Broad face luminance
clipping constrains the brightness target. Saturation of one color channel
alone does not cause the exposure optimizer to darken a face. Multiple/no detected faces
pause adjustments; a 45-second timeout and 24-write limit bound the run.

Stop keeps the settings reached so far. Undo optimization restores the exposure,
gain, white balance, and automatic modes captured before the first change.
The undo snapshot is in memory and is replaced by the next run's first write;
quitting loses it. Other settings are left alone. Save a look to retain a result.
The captured before frame is available through Compare. This is a one-shot
optimizer, not a continuous background adjustment service. It cannot fix poor
lighting or recover detail beyond the webcam's dynamic range.

Optimizer tests:
xcrun clang -fobjc-arc Sources/Optimizer.m Tests/OptimizerTests.m -framework Foundation -framework CoreGraphics -o build/optimizer-tests
./build/optimizer-tests

Face detection reference:
https://developer.apple.com/documentation/vision/vndetectfacerectanglesrequest

The revised optimizer retains its best measured exposure and restores it when
it reaches a limit or detects repeated direction reversals. The score favors
the requested face brightness and penalizes broad highlight clipping. The
color remains the white balance present when the run begins: use Evening -
Neutral first if the image is too yellow. This optimizer adjusts exposure,
not automatic color calibration.

BACKLIT MODE
Enabled by default for this setup. Allows higher gain while keeping exposure
at or below 33.3 ms. It meters the face rather than the background, which may
become very bright. Higher gain can add noise. Uncheck Backlit for the quieter,
more conservative gain cap. The checkbox does not directly toggle the camera
firmware backlight-compensation setting.
