# TalkKey for Linux

Hold a key, speak, and the text lands in whatever you were typing in. Press
another key and the text already in the field is replaced by its translation.

For **KDE Plasma** and **GNOME**, on Wayland or X11.

This is not a port of the macOS app — it is a separate program. The macOS
build stands on Accessibility, CGEvent taps, WhisperKit and Apple
Translation, none of which exist on Linux. What is shared is the idea.

## What is different from the macOS version

| | macOS | Linux |
|---|---|---|
| Hotkey | hold a bare modifier, e.g. Right ⌘ | a **combination**, e.g. Ctrl+Alt+D — the portal cannot bind a lone modifier |
| Text delivery | typed in, or Accessibility | **clipboard + Ctrl+V**, and the clipboard is put back |
| Reading the field | Accessibility | Ctrl+A, Ctrl+C, clipboard restored |
| Local speech | WhisperKit (CoreML) | faster-whisper |
| Translation | Apple Translation, on device | OpenAI, or Argos offline |

**Why the clipboard rather than typing the text out.** `ydotool` types
US-ASCII against a hardcoded layout, so it cannot produce Cyrillic — which
rules it out for the languages this exists for — and `wtype` needs a
virtual-keyboard protocol KDE does not offer. Sending one Ctrl+V works
everywhere, because the only keys synthesised are Control and V.

## Install

```bash
# System pieces
sudo apt install wl-clipboard libportaudio2 libnotify-bin   # Debian, Ubuntu
sudo dnf install wl-clipboard portaudio libnotify           # Fedora
sudo pacman -S wl-clipboard portaudio libnotify             # Arch

# The program, in its own environment
python3 -m venv ~/.local/share/talkkey-venv
~/.local/share/talkkey-venv/bin/pip install -e /path/to/press-to-talk/linux[local,cloud]
ln -s ~/.local/share/talkkey-venv/bin/talkkey ~/.local/bin/talkkey
```

Then check the machine before running anything:

```bash
talkkey doctor
```

It prints a line per requirement and tells you the exact command to fix each
failure. Get it to "Everything dictation needs is in place" first.

## Run

```bash
talkkey run
```

The **first run opens a dialog from KDE or GNOME** listing the shortcuts and
asking you to confirm them, and a second asking permission to send
keystrokes. Accept both. The second is remembered, so you are only asked
once.

Then: hold **Ctrl+Alt+D**, say something, let go. The text appears where
your cursor is. **Ctrl+Alt+T** replaces the text in the field with its
translation.

## Settings

`~/.config/talkkey/config.toml`, created on first run. Shortcuts, the speech
model, the target language, and whether speech and translation run locally
or through OpenAI. `talkkey config` prints the path.

Speech runs locally by default (`speech.engine = "local"`), which needs no
API key and no network. The first run downloads the model.

Translation needs an OpenAI key by default. Set `OPENAI_API_KEY`, or put it
in the config. For no key at all, set `translate.engine = "argos"` and
install a language pair with `argospm install translate-ru_en`.

## Start it with the session

```bash
mkdir -p ~/.config/systemd/user
cp talkkey.service ~/.config/systemd/user/
systemctl --user enable --now talkkey
journalctl --user -u talkkey -f    # to watch what it does
```

## Requirements and known limits

- **KDE Plasma 6.1+ or GNOME 48+** for the global shortcuts portal. Older
  versions do not offer it, and `talkkey doctor` will say so.
- **Replacing the text in a field selects all of it first.** If the focus is
  not really a text field, Ctrl+A can select a whole page. Anything over
  5000 characters is refused rather than replaced, but this is the roughest
  edge here — it is precise on macOS and cannot be on Wayland.
- The clipboard is borrowed and put back. If something goes wrong mid-way,
  the translated or dictated text may be left on it.
- wlroots compositors (Sway, Hyprland) have no GlobalShortcuts portal yet.
