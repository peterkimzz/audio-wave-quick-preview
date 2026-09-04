# Audio Wave Quick Preview Mac

Lightweight macOS audio inspection app for quickly previewing a file's waveform and matching its loudness.

## Current v1 capabilities

- Open `wav`, `mp3`, `m4a`, and `flac`
- File inspector sidebar: a persistent library of files, searchable, with
  length / format / sample rate per row
- Check files in the sidebar to stack them as lanes
- Normalize every lane to a target loudness (RMS) in one press
- Trim each lane by ±1 dB by ear, with a `CLIP` badge when it would clip
- Audition any lane at its current gain
- Export gain-adjusted copies of all lanes into a folder; originals untouched
- Per-lane waveform: click to jump, drag to scrub, pinch to zoom, horizontal
  scroll to pan. Every lane carries a minimap strip underneath; once the lane is
  zoomed in, the strip highlights the visible span and can be dragged to move it

## Development

This repository is currently structured as a Swift Package with:

- `AudioWaveQuickPreviewCore`: pure waveform, viewport, and gain logic with tests
- `AudioWaveQuickPreviewMac`: SwiftUI macOS app shell

Run the development app directly from the repository root:

```bash
./scripts/run-app.sh
```

The script can be called from any directory and accepts audio files as
arguments, so a file can be opened immediately:

```bash
./scripts/run-app.sh /path/to/file.wav
```

It runs the current source as a Debug build. Keep the terminal open while the
app is running; press `Control-C` in the terminal to stop it.

Debug window titles include the current Git branch, or the Codex Worktree ID
when the worktree is in detached `HEAD` state. Release builds keep the clean
app name.

Formatting is handled by `swift format` (bundled with Xcode, configured in
`.swift-format`) and linting by [SwiftLint](https://github.com/realm/SwiftLint)
(`brew install swiftlint`, configured in `.swiftlint.yml`). Both run in CI, and
both auto-fix locally:

```bash
swift format --in-place --recursive Sources Tests && swiftlint lint --fix
```

The app target has no unit-test target (it needs AppKit and a run loop), so the
paths that write files or cross actors — batch export, per-lane analysis and
normalize, the library round-trip through `UserDefaults` — are covered by a
DEBUG-only self-check that runs as the app and exits non-zero on failure:

```bash
AWQP_SELF_CHECK=/path/to/a/folder/of/wavs swift run AudioWaveQuickPreviewMac
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
