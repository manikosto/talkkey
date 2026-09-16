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
| Hotkey | hold a bare modifier, e.g. Right ⌘ | a **combination**, e.g. Ctrl+Alt+D — neither route can bind a lone modifier |
| Catching the hotkey | event tap | listened for directly on X11, the GlobalShortcuts portal on Wayland |
| Text delivery | typed in, or Accessibility | **clipboard + Ctrl+V**, and the clipboard is put back |
| Sending that Ctrl+V | — | xdotool on X11, the RemoteDesktop portal on Wayland |
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
# System pieces. xdotool is only for X11, and is what makes it simplest there.
sudo apt install wl-clipboard libportaudio2 libnotify-bin xdotool   # Debian, Ubuntu
sudo dnf install wl-clipboard portaudio libnotify xdotool           # Fedora
sudo pacman -S wl-clipboard portaudio libnotify xdotool             # Arch

# The program, in its own environment
git clone https://github.com/manikosto/talkkey.git ~/talkkey
python3 -m venv ~/.local/share/talkkey-venv
~/.local/share/talkkey-venv/bin/pip install -e "$HOME/talkkey/linux[local,cloud]"
mkdir -p ~/.local/bin
ln -sf ~/.local/share/talkkey-venv/bin/talkkey ~/.local/bin/talkkey
```

**Quote that pip line.** In zsh the square brackets are a glob pattern, so
without the quotes the extras are dropped or the command fails outright —
and then there is no speech recognition and no translation.

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
asking you to confirm them. On Wayland a second dialog asks permission to
send keystrokes; accept it too, and it is remembered so you are only asked
once. On X11 there is no second dialog — xdotool needs no permission.

Then: hold **Ctrl+Alt+D**, say something, let go. The text appears where
your cursor is. **Ctrl+Alt+T** replaces the text in the field with its
translation.

## Translation needs a key, dictation does not

Speech recognition runs on this machine and needs nothing. Translation does
not, so until a key is set `talkkey doctor` reports translation as missing
while everything else is ready — that is the expected state, and dictation
works.

```bash
echo 'export OPENAI_API_KEY="sk-..."' >> ~/.profile   # then log out and back in
```

Or put it in the config under `[openai] api_key`. For no key at all, see
Argos below.

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

## Tests

```bash
~/.local/share/talkkey-venv/bin/pip install pytest
~/.local/share/talkkey-venv/bin/python -m pytest linux/tests -q
```

These cover what can be checked without a desktop: the config, language
detection, audio encoding, the portal interface descriptions, and the
regression test for the crash that stopped the first Linux run.

## If the hotkey does nothing

The most likely cause is **KDE Plasma 5**, which ships in Ubuntu 24.04. Its
global shortcuts portal is unfinished: `BindShortcuts` opens the KDE settings
window, reports success, and binds nothing at all, so the key press never
arrives and the program sits there looking ready.

On an X11 session this is routed around entirely — the keys are listened for
directly and the portal is never involved. That is the default there. Check
what `talkkey doctor` says next to "Catching the hotkeys"; if it names the
portal on an X11 machine, force it:

```toml
[hotkeys]
backend = "x11"
```

On Wayland there is no way around it, and Plasma 6.1 or GNOME 48 is the
floor. TalkKey now refuses to start rather than pretending, if the desktop
accepts the shortcuts and binds none of them.

**Listening is not grabbing.** On X11 the combination still reaches the
window underneath, so choose one nothing else wants.

## If it complains about libcublas

```
Library libcublas.so.12 is not found or cannot be loaded
```

faster-whisper found an NVIDIA card and went looking for CUDA. It now falls
back to the CPU and says so rather than failing, so this is a message and
not a stop. To silence it, set `device = "cpu"` under `[speech]`. To use the
GPU for real:

```bash
~/.local/share/talkkey-venv/bin/pip install nvidia-cublas-cu12 nvidia-cudnn-cu12
```

Then set `device = "cuda"` and `compute_type = "float16"`.

## Requirements and known limits

- **On Wayland: KDE Plasma 6.1+ or GNOME 48+**, for the global shortcuts
  portal. There is no alternative there. On X11 any version will do, because
  the portal is not used.
- The portal's own description of itself cannot be parsed: it contains a
  property named `power-saver-enabled`, and a D-Bus member name may not hold
  a hyphen. The interfaces we need are described in `talkkey/introspection.py`
  instead, so nothing the desktop adds later can break startup.
- **Replacing the text in a field selects all of it first.** If the focus is
  not really a text field, Ctrl+A can select a whole page. Anything over
  5000 characters is refused rather than replaced, but this is the roughest
  edge here — it is precise on macOS and cannot be on Wayland.
- The clipboard is borrowed and put back. If something goes wrong mid-way,
  the translated or dictated text may be left on it.
- wlroots compositors (Sway, Hyprland) have no GlobalShortcuts portal yet.
