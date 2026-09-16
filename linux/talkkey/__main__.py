"""talkkey run — start the daemon.  talkkey doctor — check this machine."""

from __future__ import annotations

import argparse
import asyncio
import os
import shutil
import sys

from . import clipboard, config as config_mod

OK = "  ok  "
BAD = " FAIL "
WARN = " warn "


def _line(status: str, label: str, detail: str = "") -> None:
    print(f"[{status}] {label}" + (f"\n         {detail}" if detail else ""))


async def _check_portals(uses_shortcuts_portal: bool,
                         uses_remote_portal: bool) -> tuple[bool, bool]:
    from .portal import Portal

    portal = Portal()
    try:
        await portal.connect()
    except Exception as exc:  # noqa: BLE001 - reported, not raised
        _line(BAD, "Desktop portals", f"could not reach the portal service: {exc}")
        return False, False

    try:
        described = await portal.raw_introspect()
    except Exception as exc:  # noqa: BLE001 - reported, not raised
        _line(BAD, "Desktop portals", f"the portal service did not answer: {exc}")
        return False, False

    found = []
    for name, label, hint, used in (
        (
            "org.freedesktop.portal.GlobalShortcuts",
            "GlobalShortcuts portal (the hotkeys)",
            "Needs KDE Plasma 6.1+ or GNOME 48+. Check with: echo $XDG_CURRENT_DESKTOP",
            uses_shortcuts_portal,
        ),
        (
            "org.freedesktop.portal.RemoteDesktop",
            "RemoteDesktop portal (delivering the text)",
            "Install xdg-desktop-portal-kde or xdg-desktop-portal-gnome, "
            "then log out and back in.",
            uses_remote_portal,
        ),
    ):
        present = f'"{name}"' in described
        if not used:
            # Present or not, it is not on the path this machine will take —
            # saying "ok" alone would imply it mattered.
            _line(OK if present else WARN, label,
                  "not used here" + ("" if present else ", and absent"))
        else:
            _line(OK if present else BAD, label, "" if present else hint)
        found.append(present)
    return found[0], found[1]


def _resolve(cfg: config_mod.Config) -> str:
    from .inject import resolve_method

    return resolve_method(cfg.input_method)


def _check_hotkeys(cfg: config_mod.Config) -> bool:
    from .hotkeys import choose_backend

    backend = choose_backend(cfg.hotkey_backend)
    if backend == "x11":
        try:
            import pynput  # noqa: F401
        except Exception as exc:  # noqa: BLE001 - pynput raises more than ImportError
            _line(BAD, "Catching the hotkeys",
                  f"listening directly on X11 needs pynput ({exc})\n"
                  "         pip install 'talkkey-linux[x11]'")
            return False
        _line(OK, "Catching the hotkeys", "listening directly (X11)")
        return True
    _line(OK, "Catching the hotkeys", "through the GlobalShortcuts portal")
    return True


def _on_x11() -> bool:
    return not (
        os.environ.get("XDG_SESSION_TYPE") == "wayland"
        or os.environ.get("WAYLAND_DISPLAY")
    )


def _check_input(cfg: config_mod.Config) -> bool:
    method = _resolve(cfg)
    if method == "portal":
        if cfg.input_method == "auto" and _on_x11():
            # Reached by falling back, not by choosing. It does work, but it
            # costs a permission dialog that xdotool would not.
            _line(WARN, "Sending keys",
                  "falling back to the RemoteDesktop portal because xdotool is "
                  "missing.\n         On X11 xdotool is simpler and asks for "
                  "nothing:  sudo apt install xdotool")
        else:
            _line(OK, "Sending keys", "through the RemoteDesktop portal")
        return True
    if shutil.which(method):
        _line(OK, "Sending keys", f"through {method}")
        return True
    hint = {
        "xdotool": "sudo apt install xdotool",
        "ydotool": "sudo apt install ydotool, and add yourself to the input group",
    }.get(method, "")
    _line(BAD, "Sending keys", f"{method} is not installed\n         {hint}")
    return False


def _check_audio() -> bool:
    try:
        import sounddevice as sd
    except ImportError:
        _line(BAD, "Microphone", "pip install sounddevice")
        return False
    except OSError as exc:
        # sounddevice imports fine but PortAudio itself is missing.
        _line(BAD, "Microphone",
              f"{exc}\n         sudo apt install libportaudio2   # or: dnf install portaudio")
        return False
    try:
        default_in = sd.query_devices(kind="input")
    except Exception as exc:  # noqa: BLE001
        _line(BAD, "Microphone", f"no input device: {exc}")
        return False
    _line(OK, "Microphone", f"{default_in['name']}")
    return True


def _check_speech(cfg: config_mod.Config) -> bool:
    if cfg.speech_engine == "local":
        try:
            import faster_whisper  # noqa: F401
        except ImportError:
            _line(BAD, "Speech recognition (local)",
                  "pip install 'talkkey-linux[local]'")
            return False
        _line(OK, "Speech recognition (local)", f"model: {cfg.speech_model}")
        return True

    try:
        import openai  # noqa: F401
    except ImportError:
        _line(BAD, "Speech recognition (OpenAI)", "pip install 'talkkey-linux[cloud]'")
        return False
    if not cfg.api_key:
        _line(BAD, "Speech recognition (OpenAI)",
              "no API key — set OPENAI_API_KEY or [openai] api_key in the config")
        return False
    _line(OK, "Speech recognition (OpenAI)")
    return True


def _check_translation(cfg: config_mod.Config) -> bool:
    if cfg.translate_engine == "argos":
        try:
            import argostranslate  # noqa: F401
        except ImportError:
            _line(BAD, "Translation (offline)",
                  "pip install 'talkkey-linux[offline-translate]'")
            return False
        _line(OK, "Translation (offline, Argos)")
        return True

    try:
        import openai  # noqa: F401
    except ImportError:
        _line(BAD, "Translation (OpenAI)", "pip install 'talkkey-linux[cloud]'")
        return False
    if not cfg.api_key:
        _line(BAD, "Translation (OpenAI)", "no API key")
        return False
    _line(OK, "Translation (OpenAI)", f"target: {cfg.translate_target}")
    return True


def doctor() -> int:
    cfg = config_mod.load()
    print("TalkKey for Linux — checking this machine\n")

    session = os.environ.get("XDG_SESSION_TYPE", "unknown")
    desktop = os.environ.get("XDG_CURRENT_DESKTOP", "unknown")
    _line(OK if session in ("wayland", "x11") else WARN,
          f"Session: {session} on {desktop}")

    if sys.version_info < (3, 10):
        _line(BAD, "Python", f"{sys.version.split()[0]} — 3.10 or newer is needed")
    else:
        _line(OK, "Python", sys.version.split()[0])

    _line(OK, "Config", str(cfg.path))

    if clipboard.available():
        _line(OK, "Clipboard tool")
        clip_ok = True
    else:
        _line(BAD, "Clipboard tool", "sudo apt install wl-clipboard")
        clip_ok = False

    if shutil.which("notify-send"):
        _line(OK, "Notifications")
    else:
        _line(WARN, "Notifications",
              "notify-send is missing, so messages go to the terminal only "
              "(sudo apt install libnotify-bin)")

    hotkeys_ok = _check_hotkeys(cfg)
    input_ok = _check_input(cfg)
    audio_ok = _check_audio()
    speech_ok = _check_speech(cfg)
    translate_ok = _check_translation(cfg)
    from .hotkeys import choose_backend

    # Each portal only matters when it is actually the route being taken.
    uses_shortcuts_portal = choose_backend(cfg.hotkey_backend) == "portal"
    uses_remote_portal = _resolve(cfg) == "portal"
    shortcuts_ok, remote_ok = asyncio.run(
        _check_portals(uses_shortcuts_portal, uses_remote_portal)
    )

    required = [clip_ok, audio_ok, speech_ok, input_ok, hotkeys_ok]
    if uses_remote_portal:
        required.append(remote_ok)
    if uses_shortcuts_portal:
        required.append(shortcuts_ok)
    print()
    if all(required):
        extra = "" if translate_ok else " (translation is not set up, dictation is)"
        print(f"Everything dictation needs is in place{extra}. Start it with:  talkkey run")
        return 0
    print("Something above needs fixing before 'talkkey run' will work.")
    return 1


def run() -> int:
    from .app import TalkKey

    cfg = config_mod.load()
    try:
        return asyncio.run(TalkKey(cfg).run())
    except KeyboardInterrupt:
        print("\ntalkkey: stopped")
        return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="talkkey",
        description="Hold a key, speak, and the text lands where you are typing.",
    )
    parser.add_argument(
        "command",
        nargs="?",
        default="run",
        choices=["run", "doctor", "config"],
        help="run the daemon, check this machine, or print the config path",
    )
    args = parser.parse_args()

    if args.command == "doctor":
        return doctor()
    if args.command == "config":
        print(config_mod.write_default_config())
        return 0
    return run()


if __name__ == "__main__":
    sys.exit(main())
