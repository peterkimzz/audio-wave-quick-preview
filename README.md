# Audio Wave Quick Preview Mac

Lightweight macOS audio inspection app for quickly previewing a file's waveform and matching its loudness.

## Current v1 capabilities

- Open `wav`, `mp3`, `m4a`, and `flac`
- Play and pause the file
- Toggle playback with the spacebar
- Show a full-file waveform
- Click anywhere on the waveform to jump playback
- Drag across the waveform to scrub playback
- Pinch to zoom and use horizontal trackpad scrolling to pan

## Development

This repository is currently structured as a Swift Package with:

- `AudioWaveQuickPreviewCore`: pure waveform, viewport, and gain logic with tests
- `AudioWaveQuickPreviewMac`: SwiftUI macOS app shell

Formatting is handled by `swift format` (bundled with Xcode, configured in
`.swift-format`) and linting by [SwiftLint](https://github.com/realm/SwiftLint)
(`brew install swiftlint`, configured in `.swiftlint.yml`). Both run in CI, and
both auto-fix locally:

```bash
swift format --in-place --recursive Sources Tests && swiftlint lint --fix
```

## Packaging and install

Build an app bundle into `dist/`:

```bash
cd /Users/peter/Projects/audio-wave-quick-preview-mac
chmod +x scripts/package-app.sh scripts/install-app.sh
./scripts/package-app.sh
```

Build a versioned release archive for sharing:

```bash
cd /Users/peter/Projects/audio-wave-quick-preview-mac
VERSION_NAME=v0.1.0 ./scripts/package-app.sh
```

Install the app into `~/Applications` and register it with Launch Services:

```bash
cd /Users/peter/Projects/audio-wave-quick-preview-mac
./scripts/install-app.sh
```

After installation, Finder should show `Audio Wave Quick Preview` in `Open With` for supported audio files.

You can also launch the installed app directly:

```bash
open -a "Audio Wave Quick Preview"
```

Or open a file with it:

```bash
open -a "Audio Wave Quick Preview" /path/to/file.wav
```

## Team distribution via GitHub Releases

Team members can install from the GitHub Releases page:

1. Download the latest `AudioWaveQuickPreview-vX.Y.Z-macos.zip` asset from Releases.
2. Unzip it to get `Audio Wave Quick Preview.app`.
3. Move the app to `Applications` or `~/Applications`.
4. Open it with right-click -> `Open` the first time if macOS shows an unsigned app warning.

If macOS quarantine still blocks launch, run:

```bash
xattr -dr com.apple.quarantine "Audio Wave Quick Preview.app"
```

Releases are created automatically when a `v*` git tag is pushed. Example:

```bash
git tag v0.1.0
git push origin v0.1.0
```

## Notes

- The app bundle declares support for `wav`, `mp3`, `m4a`, and `flac`, with a broader `public.audio` viewer role for Finder integration.
- GitHub Releases currently ship unsigned internal-distribution builds. Apple code signing and notarization are not configured yet.
- Tests run in two places: `swift test` (Swift Testing, `Tests/AudioWaveQuickPreviewCoreTests`) and `swift run AudioWaveQuickPreviewSpecs` (a plain executable covering viewport, pyramid, and keyboard behaviour that the test target does not). CI runs both on every pull request.
