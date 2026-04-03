# Audio Wave Quick Preview Mac

Lightweight macOS audio inspection app for quickly finding where sound is actually present inside long files.

## Current v1 capabilities

- Open `wav`, `mp3`, `m4a`, and `flac`
- Play and pause the file
- Show a full-file waveform
- Highlight automatically detected sound sections using RMS analysis
- Click anywhere on the waveform to jump playback
- Tune sensitivity, minimum sound duration, and silence merge duration

## Development

This repository is currently structured as a Swift Package with:

- `AudioWaveQuickPreviewCore`: pure analysis logic with tests
- `AudioWaveQuickPreviewMac`: SwiftUI macOS app shell

## Packaging and install

Build an app bundle into `dist/`:

```bash
cd /Users/peter/Projects/audio-wave-quick-preview-mac
chmod +x scripts/package-app.sh scripts/install-app.sh
./scripts/package-app.sh
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

## Notes

- The app bundle declares support for `wav`, `mp3`, `m4a`, and `flac`, with a broader `public.audio` viewer role for Finder integration.
- The core app target compiles successfully in this environment. The Swift test target is still blocked by missing local test-framework modules in the installed Command Line Tools setup.
