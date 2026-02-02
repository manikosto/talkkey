# TalkKey

A native macOS voice-to-text app powered by OpenAI Whisper. Press a hotkey, speak, and your words are instantly transcribed and pasted.

![TalkKey Screenshot](https://talkkey.io/screenshot.png)

## Features

- **Instant Transcription** — Hold Right Cmd, speak, release to transcribe and paste
- **Offline Mode** — Uses WhisperKit for on-device transcription (no internet required)
- **Cloud Mode** — OpenAI Whisper API for higher accuracy (requires API key)
- **Translation** — Transcribe and translate to any language with one hotkey
- **Review Mode** — Edit and restyle text before pasting
- **Auto Updates** — Built-in update mechanism via Sparkle

## Hotkeys

| Hotkey | Action |
|--------|--------|
| Right Cmd | Hold to record, release to transcribe & paste |
| Right Option | Hold to record, release to open review window |
| Fn | Hold to record with translation |
| Esc | Cancel recording |

## Requirements

- macOS 13.0 or later
- Microphone permission
- Accessibility permission (for auto-paste)

## Installation

1. Download the latest DMG from [Releases](https://github.com/manikosto/talkkey/releases)
2. Open the DMG and drag TalkKey to Applications
3. Launch TalkKey and grant permissions

## Modes

### Offline Mode (Free)
Uses WhisperKit to run transcription locally on your Mac. Works without internet, completely private.

### Cloud Mode (Pro)
Uses OpenAI Whisper API for faster and more accurate transcription. Requires your own API key.

## License

Free tier includes 10 transcriptions per day. [Purchase a Pro license](https://talkkey.io) for unlimited use.

## Links

- [Website](https://talkkey.io)
- [Download](https://github.com/manikosto/talkkey/releases/latest/download/TalkKey.dmg)
