"""Clipboard access, the way each session type provides it.

TalkKey borrows the clipboard to deliver text and puts back whatever was
there. That is worth doing carefully: losing what someone had copied is a
small betrayal that is very visible.
"""

from __future__ import annotations

import os
import shutil
import subprocess


class ClipboardError(RuntimeError):
    pass


def _wayland() -> bool:
    return os.environ.get("XDG_SESSION_TYPE") == "wayland" or bool(
        os.environ.get("WAYLAND_DISPLAY")
    )


def _tools() -> tuple[list[str], list[str]]:
    """Returns the (copy, paste) command for this session, or raises."""
    if _wayland() and shutil.which("wl-copy") and shutil.which("wl-paste"):
        return ["wl-copy"], ["wl-paste", "--no-newline"]
    if shutil.which("xclip"):
        return (
            ["xclip", "-selection", "clipboard"],
            ["xclip", "-selection", "clipboard", "-o"],
        )
    if shutil.which("xsel"):
        return ["xsel", "--clipboard", "--input"], ["xsel", "--clipboard", "--output"]
    raise ClipboardError(
        "no clipboard tool found. Install wl-clipboard (Wayland) or xclip (X11):\n"
        "  sudo apt install wl-clipboard     # Debian, Ubuntu\n"
        "  sudo dnf install wl-clipboard     # Fedora\n"
        "  sudo pacman -S wl-clipboard       # Arch"
    )


def available() -> bool:
    try:
        _tools()
    except ClipboardError:
        return False
    return True


def read() -> str:
    _, paste = _tools()
    try:
        done = subprocess.run(paste, capture_output=True, timeout=5)
    except subprocess.TimeoutExpired:
        return ""
    if done.returncode != 0:
        # An empty clipboard is an error for some of these tools, not a failure.
        return ""
    return done.stdout.decode("utf-8", errors="replace")


def write(text: str) -> None:
    copy, _ = _tools()
    try:
        subprocess.run(copy, input=text.encode("utf-8"), timeout=5, check=True)
    except subprocess.TimeoutExpired as exc:
        raise ClipboardError("the clipboard tool did not finish") from exc
    except subprocess.CalledProcessError as exc:
        raise ClipboardError(f"the clipboard tool failed: {exc}") from exc
