# Audio Wave Quick Preview Mac

Lightweight macOS audio inspection app for quickly previewing a file's waveform and matching its loudness.

## Current v1 capabilities

- Open `wav`, `mp3`, `m4a`, and `flac`
- Create reusable folders such as BGM, Sound Effects, and Ambience; each folder
  remembers its location and loudness target between launches
- The `Folders` sidebar is the navigation: selecting a folder immediately loads
  every supported audio file directly inside it into the lanes
- Refresh the selected folder after adding or replacing files; subfolders are
  intentionally not scanned
- Normalize every loaded file to the selected folder's target loudness (RMS)
  in one press
- Adjust the saved target by 0.5 dB while auditioning files, then process the
  whole selected folder with `Normalize & Export`
- Write processed copies to the selected folder's `Normalized` subfolder so
  source files stay untouched and generated files are not reprocessed as inputs
- Trim each lane by ±1 dB by ear, with a `CLIP` badge when it would clip
- Audition any lane at its current gain
- Per-lane waveform: click to jump, drag to scrub, pinch to zoom, horizontal
  scroll to pan. Every lane carries a minimap strip underneath; once the lane is
  zoomed in, the strip highlights the visible span and can be dragged to move it

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

The app target has no unit-test target (it needs AppKit and a run loop), so the
paths that write files or cross actors — folder scanning, per-file analysis and
normalize, and batch export — are covered by a DEBUG-only self-check that runs
as the app and exits non-zero on failure:

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
- Folder matching currently uses full-file root-mean-square (RMS) level. This
  is a transparent, lightweight approximation for game assets, not a standards-
  based integrated loudness measurement such as LUFS. Long silence before or
  after a sound can therefore affect the result; audition the folder and move
  its target slider until the gameplay mix sounds right.
- GitHub Releases currently ship unsigned internal-distribution builds. Apple code signing and notarization are not configured yet.
- Tests run in two places: `swift test` (Swift Testing, `Tests/AudioWaveQuickPreviewCoreTests`) and `swift run AudioWaveQuickPreviewSpecs` (a plain executable covering viewport, pyramid, and keyboard behaviour that the test target does not). CI runs both on every pull request.
