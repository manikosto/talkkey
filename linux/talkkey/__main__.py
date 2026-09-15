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


async def _check_portals() -> tuple[bool, bool]:
    from .portal import Portal

    portal = Portal()
    try:
        await portal.connect()
    except Exception as exc:  # noqa: BLE001 - reported, not raised
        _line(BAD, "Desktop portals", f"could not reach the portal service: {exc}")
        return False, False

    have_shortcuts = have_remote = False
    for name, label, hint in (
        (
            "org.freedesktop.portal.GlobalShortcuts",
            "GlobalShortcuts portal (the hotkeys)",
            "Needs KDE Plasma 6.1+ or GNOME 48+. Check with: echo $XDG_CURRENT_DESKTOP",
        ),
        (
            "org.freedesktop.portal.RemoteDesktop",
            "RemoteDesktop portal (delivering the text)",
            "Install xdg-desktop-portal-kde or xdg-desktop-portal-gnome, "
            "then log out and back in.",
        ),
    ):
        try:
            portal.interface(name)
        except Exception:  # noqa: BLE001 - absence is the answer
            _line(BAD, label, hint)
        else:
            _line(OK, label)
            if "GlobalShortcuts" in name:
                have_shortcuts = True
            else:
                have_remote = True
    return have_shortcuts, have_remote


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

    audio_ok = _check_audio()
    speech_ok = _check_speech(cfg)
    translate_ok = _check_translation(cfg)
    shortcuts_ok, remote_ok = asyncio.run(_check_portals())

    required = [clip_ok, audio_ok, speech_ok, shortcuts_ok, remote_ok]
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
